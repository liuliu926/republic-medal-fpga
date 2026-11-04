`timescale 1ns/1ps

// Starts one existing frame_read_write transaction, then forwards the
// scaler's fixed-size RGB stream into its asynchronous write FIFO.
// `clk` must be the same clock connected to frame_read_write.write_clk.
module bmp_scaled_frame_write_ctrl #(
    parameter integer ADDR_BITS = 21,
    parameter integer OUT_WIDTH = 1280,
    parameter integer OUT_HEIGHT = 720,
    parameter integer REQUEST_TIMEOUT_CYCLES = 10_000_000,
    parameter integer STREAM_TIMEOUT_CYCLES = 100_000_000,
    parameter integer FIFO_RELEASE_CYCLES = 8
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  frame_start,
    input  wire [1:0]            frame_index,
    input  wire                  scaled_valid,
    input  wire [23:0]           scaled_pixel,
    input  wire                  scaler_done,
    input  wire                  upstream_abort,
    input  wire                  write_fifo_full,
    input  wire                  write_req_ack,
    input  wire                  write_finish,

    output reg                   write_req,
    output reg  [1:0]            write_addr_index,
    output wire [ADDR_BITS-1:0]  write_len,
    output wire [ADDR_BITS-1:0]  write_first_offset,
    output wire [15:0]           write_line_width,
    output wire [ADDR_BITS-1:0]  write_line_jump,
    output wire                  write_en,
    output wire [31:0]           write_data,

    output wire                  frame_write_ready,
    output wire                  scaled_ready,
    output reg                   busy,
    output reg                   done,
    output reg                   error,
    output reg                   recovery_required
);

    localparam [2:0] ST_IDLE        = 3'd0;
    localparam [2:0] ST_WAIT_ACK    = 3'd1;
    localparam [2:0] ST_FIFO_SETTLE = 3'd2;
    localparam [2:0] ST_STREAM      = 3'd3;
    localparam [2:0] ST_COMPLETE    = 3'd4;
    localparam [2:0] ST_ERROR       = 3'd5;
    localparam [2:0] ST_PAD         = 3'd6;
    localparam [2:0] ST_WAIT_DRAIN  = 3'd7;

    localparam [ADDR_BITS-1:0] FRAME_PIXELS = OUT_WIDTH * OUT_HEIGHT;
    localparam [ADDR_BITS-1:0] BOTTOM_ROW_OFFSET = (OUT_HEIGHT - 1) * OUT_WIDTH;
    // frame_fifo_write increments through a row, then subtracts line_jump
    // from the last pixel address.  2*width-1 lands at the next bottom-up row.
    localparam [ADDR_BITS-1:0] ROW_JUMP = (2 * OUT_WIDTH) - 1;

    reg [2:0] state;
    reg [31:0] timeout_count;
    reg [7:0] settle_count;
    reg [ADDR_BITS-1:0] accepted_pixels;
    reg scaler_done_seen;
    reg write_finish_seen;
    reg [31:0] stall_count;
    wire frame_complete_now;

    assign write_len          = FRAME_PIXELS;
    assign write_first_offset = BOTTOM_ROW_OFFSET;
    assign write_line_width   = OUT_WIDTH;
    assign write_line_jump    = ROW_JUMP;
    assign write_en           = ((state == ST_STREAM) &&
                                 (accepted_pixels < FRAME_PIXELS) && scaled_valid &&
                                 !write_fifo_full) ||
                                ((state == ST_PAD) &&
                                 (accepted_pixels < FRAME_PIXELS) &&
                                 !write_fifo_full);
    // Existing HDMI scanout consumes frame data [31:8] as RGB.
    assign write_data         = (state == ST_PAD) ? 32'd0 : {scaled_pixel, 8'h00};
    // Avoid putting FIFO-full through a wide incrementer and equality check
    // in the same cycle; the fixed terminal count has only these two cases.
    assign frame_complete_now = (accepted_pixels == FRAME_PIXELS) ||
                                ((accepted_pixels == FRAME_PIXELS-1) && write_en);
    assign frame_write_ready  = (state == ST_STREAM);
    assign scaled_ready       = (state == ST_STREAM) &&
                                (accepted_pixels < FRAME_PIXELS) &&
                                !write_fifo_full;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state             <= ST_IDLE;
            timeout_count     <= 32'd0;
            settle_count      <= 8'd0;
            accepted_pixels   <= {ADDR_BITS{1'b0}};
            scaler_done_seen  <= 1'b0;
            write_finish_seen <= 1'b0;
            write_req         <= 1'b0;
            write_addr_index  <= 2'd0;
            busy              <= 1'b0;
            done              <= 1'b0;
            error             <= 1'b0;
            recovery_required <= 1'b0;
            stall_count       <= 32'd0;
        end else begin
            done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    write_req <= 1'b0;
                    if (frame_start && !recovery_required) begin
                        write_addr_index  <= frame_index;
                        accepted_pixels   <= {ADDR_BITS{1'b0}};
                        scaler_done_seen  <= 1'b0;
                        write_finish_seen <= 1'b0;
                        timeout_count     <= 32'd0;
                        settle_count      <= 8'd0;
                        error             <= 1'b0;
                        busy              <= 1'b1;
                        write_req         <= 1'b1;
                        state             <= ST_WAIT_ACK;
                    end
                end

                ST_WAIT_ACK: begin
                    if (write_req_ack) begin
                        write_req     <= 1'b0;
                        settle_count  <= 8'd0;
                        timeout_count <= 32'd0;
                        state         <= ST_FIFO_SETTLE;
                    end else if (timeout_count >= REQUEST_TIMEOUT_CYCLES-1) begin
                        write_req <= 1'b0;
                        error     <= 1'b1;
                        state     <= ST_ERROR;
                    end else begin
                        timeout_count <= timeout_count + 32'd1;
                    end
                end

                ST_FIFO_SETTLE: begin
                    if (!write_req_ack) begin
                        if (settle_count >= FIFO_RELEASE_CYCLES) begin
                            state <= ST_STREAM;
                        end else begin
                            settle_count <= settle_count + 8'd1;
                        end
                    end else if (timeout_count >= REQUEST_TIMEOUT_CYCLES-1) begin
                        error <= 1'b1;
                        state <= ST_ERROR;
                    end else begin
                        timeout_count <= timeout_count + 32'd1;
                    end
                end

                ST_STREAM: begin
                    if (write_en)
                        accepted_pixels <= accepted_pixels + {{(ADDR_BITS-1){1'b0}}, 1'b1};

                    if (scaler_done || upstream_abort)
                        scaler_done_seen <= 1'b1;

                    if (((scaler_done && !frame_complete_now) ||
                         upstream_abort)) begin
                        // Finish the fixed-length SDRAM transaction even if
                        // a damaged/truncated asset stops the scaler early or
                        // the loader aborts the upstream stream.
                        error <= 1'b1;
                        if (!frame_complete_now)
                            state <= ST_PAD;
                        else
                            state <= ST_WAIT_DRAIN;
                    end

                    if (scaled_valid && (accepted_pixels >= FRAME_PIXELS)) begin
                        error <= 1'b1;
                        state <= ST_ERROR;
                    end

                    if (write_finish) begin
                        if (!frame_complete_now) begin
                            error <= 1'b1;
                            state <= ST_ERROR;
                        end else
                            write_finish_seen <= 1'b1;
                    end

                    if ((scaler_done_seen || scaler_done) &&
                        (write_finish_seen || write_finish) &&
                        frame_complete_now)
                        state <= ST_COMPLETE;
                end

                ST_PAD: begin
                    if (write_en)
                        accepted_pixels <= accepted_pixels + {{(ADDR_BITS-1){1'b0}}, 1'b1};

                    if (write_finish && !frame_complete_now) begin
                        error <= 1'b1;
                        state <= ST_ERROR;
                    end else if (frame_complete_now) begin
                        if (write_finish) begin
                            write_finish_seen <= 1'b1;
                            state <= ST_COMPLETE;
                        end else begin
                            state <= ST_WAIT_DRAIN;
                        end
                    end
                end

                ST_WAIT_DRAIN: begin
                    if (scaler_done || upstream_abort)
                        scaler_done_seen <= 1'b1;
                    if (write_finish)
                        write_finish_seen <= 1'b1;

                    if ((scaler_done_seen || scaler_done) &&
                        (write_finish_seen || write_finish) &&
                        (accepted_pixels == FRAME_PIXELS))
                        state <= ST_COMPLETE;
                end

                ST_COMPLETE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= ST_IDLE;
                end

                ST_ERROR: begin
                    busy <= 1'b0;
                    error <= 1'b1;
                    done <= 1'b1;
                    recovery_required <= 1'b1;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase

            // Bound waits for a stalled producer/full FIFO or a missing
            // physical completion. Never retry an uncertain memory request.
            if ((state == ST_STREAM) || (state == ST_PAD) ||
                (state == ST_WAIT_DRAIN)) begin
                if (write_en || write_finish)
                    stall_count <= 32'd0;
                else if (stall_count >= STREAM_TIMEOUT_CYCLES-1) begin
                    error <= 1'b1;
                    state <= ST_ERROR;
                end else stall_count <= stall_count + 32'd1;
            end else stall_count <= 32'd0;
        end
    end

endmodule
