`timescale 1ns/1ps
// Two 720p backgrounds occupy SDRAM frames 0 and 1. The 13 home portraits
// are independent 80x100 layers in the spare tail starting at word 1843200.
// Portrait rows are padded to 128 words to stay inside SDRAM row pages.
// The intro portrait is already composited into frame 1 by the asset writer.
module frame_fifo_read #(
    parameter MEM_DATA_BITS = 32,
    parameter ADDR_BITS = 21,
    parameter BURST_BITS = 10,
    parameter FIFO_DEPTH = 512,
    parameter BURST_SIZE = 256
) (
    input wire rst, mem_clk, Sdr_init_done, Sdr_init_ref_vld, Sdr_busy,
    input wire Sdr_rd_en, App_wr_busy,
    output wire O_rd_busy,
    output wire App_rd_en,
    output wire [ADDR_BITS-1:0] App_rd_addr,
    input wire read_req,
    input wire intro_mode,
    output reg read_req_ack,
    output wire read_finish,
    input wire [ADDR_BITS-1:0] read_addr_0, read_addr_1, read_addr_2, read_addr_3,
    input wire [1:0] read_addr_index,
    input wire [ADDR_BITS-1:0] read_len,
    output reg fifo_aclr,
    input wire [9:0] wrusedw
);
    localparam [3:0] IDLE=0, ACK=1, PLAN_SEG=2, PLAN_MIN=3,
                     CHECK_FIFO=4, READ_BURST=5, READ_END=6, DONE=7, PLAN_CAPTURE=8;
    reg [3:0] state;
    reg req0, req1, req2;
    reg [ADDR_BITS-1:0] len0, len1, len_latched, read_count;
    reg [ADDR_BITS-1:0] read_address, background_address;
    reg [10:0] screen_x;
    reg [9:0] screen_y;
    reg [13:0] portrait_row_units;
    reg [8:0] segment_limit, page_limit, burst_target;
    reg [2:0] next_source;
    reg [10:0] segment_end_latched, screen_x_latched;
    reg [8:0] page_remaining_latched;
    reg [BURST_BITS-1:0] burst_count;
    reg read_enable_r, read_enable_d;
    reg [3:0] drain_count;

    // Registered row decodes are stable well before the first portrait x=66.
    // The reader drains each row-end burst before planning the following row.
    reg row0, row1, row2, row3;
    always @(posedge mem_clk or posedge rst) begin
        if (rst) begin row0 <= 0; row1 <= 0; row2 <= 0; row3 <= 0; end
        else begin
            row0 <= screen_y >= 10'd170 && screen_y < 10'd270;
            row1 <= screen_y >= 10'd303 && screen_y < 10'd403;
            row2 <= screen_y >= 10'd436 && screen_y < 10'd536;
            row3 <= screen_y >= 10'd569 && screen_y < 10'd669;
        end
    end
    wire portrait_row = !intro_mode && (row0 || row1 || row2 || row3);

    // End of the current background or portrait segment, in screen pixels.
    reg [10:0] segment_end;
    always @* begin
        segment_end = 11'd1280;
        if (portrait_row) begin
            if      (screen_x < 11'd68)   segment_end = 11'd68;
            else if (screen_x < 11'd148)  segment_end = 11'd148;
            else if (!row3 && screen_x < 11'd364)  segment_end = 11'd364;
            else if (!row3 && screen_x < 11'd444)  segment_end = 11'd444;
            else if (!row3 && screen_x < 11'd660)  segment_end = 11'd660;
            else if (!row3 && screen_x < 11'd740)  segment_end = 11'd740;
            else if (!row3 && screen_x < 11'd956)  segment_end = 11'd956;
            else if (!row3 && screen_x < 11'd1036) segment_end = 11'd1036;
        end
    end
    wire [10:0] segment_distance = segment_end_latched - screen_x_latched;
    wire [8:0] segment_capped = (segment_distance >= 11'd256)
        ? 9'd256 : segment_distance[8:0];
    wire [8:0] page_remaining = 9'd256 - {1'b0, read_address[7:0]};
    wire burst_drained = (state == READ_BURST) &&
                         (burst_count >= burst_target) && (drain_count == 4'd10);

    assign App_rd_en = read_enable_d;
    assign App_rd_addr = read_address;
    assign O_rd_busy = (state == READ_BURST);
    assign read_finish = (state == DONE);

    always @(posedge mem_clk or posedge rst) begin
        if (rst) begin
            req0 <= 0; req1 <= 0; req2 <= 0;
            len0 <= 0; len1 <= 0;
        end else begin
            req0 <= read_req; req1 <= req0; req2 <= req1;
            len0 <= read_len; len1 <= len0;
        end
    end

    always @(posedge mem_clk or posedge rst) begin
        if (rst) begin
            read_address <= 0;
            background_address <= 0;
            screen_x <= 0;
            screen_y <= 0;
            portrait_row_units <= 0;
            burst_count <= 0;
            read_enable_d <= 0;
            drain_count <= 0;
        end else begin
            if (state == CHECK_FIFO) burst_count <= 0;
            else if (App_rd_en) burst_count <= burst_count + 1'b1;

            if (App_rd_en) drain_count <= 0;
            else if (drain_count < 4'd10) drain_count <= drain_count + 1'b1;

            read_enable_d <= read_enable_r &&
                             ((burst_count + App_rd_en) < burst_target);

            if (state == ACK) begin
                read_address <= read_addr_index == 2'd1 ? read_addr_1 : read_addr_0;
                background_address <= (read_addr_index == 2'd1 ? read_addr_1 : read_addr_0) + 1'b1;
                screen_x <= 0;
                screen_y <= 0;
            end else if (App_rd_en) begin
                // Each group starts at a 128-word row-aligned address.
                if (screen_x == 0) begin
                    if      (row0) portrait_row_units <= 14'd14669 - screen_y;
                    else if (row1) portrait_row_units <= 14'd15202 - screen_y;
                    else if (row2) portrait_row_units <= 14'd15735 - screen_y;
                    else if (row3) portrait_row_units <= 14'd16268 - screen_y;
                end
                background_address <= background_address + 1'b1;
                // Keep the address counter's per-word path short. Segment
                // source changes happen in READ_END, after the final word
                // has retired and before the next burst is planned.
                read_address <= read_address + 1'b1;

                if (screen_x == 11'd1279) begin
                    screen_x <= 0;
                    screen_y <= screen_y + 1'b1;
                end else screen_x <= screen_x + 1'b1;
            end else if (state == READ_END) begin
                // next_source was decoded before the burst. No screen-x
                // comparison or segment arithmetic is left on this path.
                case (next_source)
                    3'd1: read_address <= {portrait_row_units, 7'b0};
                    3'd2: read_address <= {portrait_row_units + 14'd100, 7'b0};
                    3'd3: read_address <= {portrait_row_units + 14'd200, 7'b0};
                    3'd4: read_address <= {portrait_row_units + 14'd300, 7'b0};
                    3'd5: read_address <= background_address - 1'b1;
                    default: ;
                endcase
            end
        end
    end

    always @(posedge mem_clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            read_req_ack <= 0;
            fifo_aclr <= 0;
            len_latched <= 0;
            read_count <= 0;
            segment_end_latched <= 0;
            screen_x_latched <= 0;
            page_remaining_latched <= 0;
            segment_limit <= 0;
            page_limit <= 0;
            burst_target <= 0;
            next_source <= 0;
            read_enable_r <= 0;
        end else case (state)
            IDLE: begin
                read_req_ack <= 0;
                if (req2 && Sdr_init_done) state <= ACK;
            end
            ACK: begin
                read_count <= 0;
                if (!req2) begin
                    read_req_ack <= 0;
                    fifo_aclr <= 0;
                    state <= PLAN_CAPTURE;
                end else begin
                    read_req_ack <= 1;
                    fifo_aclr <= 1;
                    len_latched <= len1;
                end
            end
            PLAN_CAPTURE: begin
                segment_end_latched <= segment_end;
                screen_x_latched <= screen_x;
                page_remaining_latched <= page_remaining;
                state <= PLAN_SEG;
            end
            PLAN_SEG: begin
                segment_limit <= segment_capped;
                page_limit <= page_remaining_latched;
                state <= PLAN_MIN;
            end
            PLAN_MIN: begin
                burst_target <= segment_limit < page_limit ? segment_limit : page_limit;
                next_source <= 3'd0;
                if (portrait_row && segment_limit <= page_limit) begin
                    case (segment_end_latched)
                        11'd68: next_source <= 3'd1;
                        11'd148: next_source <= 3'd5;
                        11'd364: if (!row3) next_source <= 3'd2;
                        11'd444: if (!row3) next_source <= 3'd5;
                        11'd660: if (!row3) next_source <= 3'd3;
                        11'd740: if (!row3) next_source <= 3'd5;
                        11'd956: if (!row3) next_source <= 3'd4;
                        11'd1036: if (!row3) next_source <= 3'd5;
                        default: ;
                    endcase
                end
                state <= CHECK_FIFO;
            end
            CHECK_FIFO: begin
                if (req2) state <= ACK;
                else if (wrusedw < FIFO_DEPTH - BURST_SIZE && !App_wr_busy) begin
                    state <= READ_BURST;
                    read_enable_r <= 1;
                end
            end
            READ_BURST: if (burst_drained) begin
                read_enable_r <= 0;
                read_count <= read_count + burst_target;
                state <= READ_END;
            end
            READ_END: begin
                if (req2) state <= ACK;
                else if (read_count < len_latched) state <= PLAN_CAPTURE;
                else state <= DONE;
            end
            DONE: state <= IDLE;
            default: state <= IDLE;
        endcase
    end
endmodule
