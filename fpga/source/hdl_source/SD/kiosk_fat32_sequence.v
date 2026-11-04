`timescale 1ns/1ps

// First complete FAT32 asset schedule: one cached home frame, 13 cached home
// portraits, and one replaceable person frame. The current person frame is
// composed before it becomes visible. All requests use 8.3 FAT names.
module kiosk_fat32_sequence (
    input  wire        clk,
    input  wire        rst,
    input  wire        mem_ready,
    input  wire        sd_ready,
    input  wire [1:0]  nav_level,
    input  wire [4:0]  nav_person,
    input  wire        shared_busy,
    input  wire        shared_done,
    input  wire        shared_error,
    input  wire        shared_recovery,
    input  wire        writer_done,
    input  wire        writer_error,
    input  wire        asset_header_done,
    input  wire        asset_header_valid,
    input  wire [15:0] asset_width,
    input  wire [15:0] asset_height,
    output reg         shared_start,
    output wire        asset_mode,
    output reg [87:0]  target_sfn,
    output wire [1:0]  frame_index,
    output reg         writer_start,
    output wire [1:0]  writer_frame_index,
    output wire [20:0] writer_first_offset,
    output wire [15:0] writer_width,
    output wire [15:0] writer_height,
    output wire [20:0] writer_length,
    output wire [20:0] writer_line_jump,
    output wire        writer_pixel_route,
    output wire        mask_pixel_route,
    output reg         mask_start,
    output wire [1:0]  display_frame_index,
    output reg         display_valid,
    output wire        text_visible,
    output wire        loading,
    output reg [3:0]   error_stage,
    output reg  [3:0]  debug_state,
    output reg  [3:0]  debug_thumb_index
);
    localparam [3:0] S_BG=4'd0, S_THM=4'd1, S_HOMETXT=4'd2,
                     S_HOME=4'd3, S_PBG=4'd4, S_POR=4'd5,
                     S_PTEXT=4'd6, S_PERSON=4'd7,
                     S_RETURN_TEXT=4'd8, S_FAIL=4'd9;
    reg [3:0] state;
    reg issued, shared_seen, writer_seen;
    reg [3:0] thumb_index;
    reg person_q;
    reg [1:0] display_q;
    reg [1:0] mem_ready_sync;

    wire loading_state = state == S_BG || state == S_THM ||
        state == S_HOMETXT || state == S_PBG || state == S_POR ||
        state == S_PTEXT || state == S_RETURN_TEXT;
    wire portrait_state = state == S_THM || state == S_POR;
    wire text_state = state == S_HOMETXT || state == S_PTEXT ||
                      state == S_RETURN_TEXT;
    wire command_complete = (shared_seen || shared_done) &&
                            (!portrait_state || writer_seen || writer_done);

    assign loading = loading_state;
    assign text_visible = (state == S_HOME || state == S_PERSON) && display_valid;
    assign display_frame_index = display_q;
    assign asset_mode = state != S_BG && state != S_PBG;
    assign frame_index = state == S_PBG ? 2'd1 : 2'd0;
    assign writer_pixel_route = portrait_state;
    assign mask_pixel_route = text_state;
    assign writer_frame_index = state == S_THM ? 2'd2 : 2'd1;
    assign writer_first_offset = state == S_THM ?
        ({17'd0,thumb_index} * 21'd12800) : 21'd715620;
    assign writer_width = state == S_THM ? 16'd80 : 16'd320;
    assign writer_height = state == S_THM ? 16'd100 : 16'd400;
    assign writer_length = state == S_THM ? 21'd8000 : 21'd128000;
    // The home scanout reads portrait rows from bottom to top. Keep the
    // BMP's bottom-up row order in this cache; 2^21-49 advances 128 words.
    assign writer_line_jump = state == S_THM ? 21'd2097103 : 21'd1599;

    always @* begin
        target_sfn = "BG001   BMP";
        case (state)
            S_BG: target_sfn = "BG001   BMP";
            S_THM: case (thumb_index)
                4'd0: target_sfn="THM01   BMP";
                4'd1: target_sfn="THM02   BMP";
                4'd2: target_sfn="THM03   BMP";
                4'd3: target_sfn="THM04   BMP";
                4'd4: target_sfn="THM05   BMP";
                4'd5: target_sfn="THM06   BMP";
                4'd6: target_sfn="THM07   BMP";
                4'd7: target_sfn="THM08   BMP";
                4'd8: target_sfn="THM09   BMP";
                4'd9: target_sfn="THM10   BMP";
                4'd10: target_sfn="THM11   BMP";
                4'd11: target_sfn="THM12   BMP";
                default: target_sfn="THM13   BMP";
            endcase
            S_HOMETXT, S_RETURN_TEXT: target_sfn="HOMETXT BMP";
            S_PBG: target_sfn=person_q ? "BG006   BMP" : "BG002   BMP";
            S_POR: target_sfn=person_q ? "POR02   BMP" : "POR01   BMP";
            S_PTEXT: target_sfn=person_q ? "SJTEXT  BMP" : "YMTEXT  BMP";
            default: target_sfn="BG001   BMP";
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_BG;
            issued <= 1'b0;
            shared_seen <= 1'b0;
            writer_seen <= 1'b0;
            thumb_index <= 4'd0;
            person_q <= 1'b0;
            display_q <= 2'd0;
            mem_ready_sync <= 2'b00;
            shared_start <= 1'b0;
            writer_start <= 1'b0;
            mask_start <= 1'b0;
            display_valid <= 1'b0;
            error_stage <= 4'd0;
            debug_state <= 4'd0;
            debug_thumb_index <= 4'd0;
        end else begin
            debug_state <= state;
            debug_thumb_index <= thumb_index;
            mem_ready_sync <= {mem_ready_sync[0],mem_ready};
            shared_start <= 1'b0;
            writer_start <= 1'b0;
            mask_start <= 1'b0;
            if (shared_done) shared_seen <= 1'b1;
            if (writer_done) writer_seen <= 1'b1;

            if (loading_state) begin
                if (shared_error || shared_recovery || writer_error) begin
                    error_stage <= state;
                    state <= S_FAIL;
                end else if (!issued && mem_ready_sync[1] && sd_ready && !shared_busy) begin
                    shared_start <= 1'b1;
                    writer_start <= portrait_state;
                    issued <= 1'b1;
                    shared_seen <= 1'b0;
                    writer_seen <= 1'b0;
                end else if (issued && command_complete) begin
                    issued <= 1'b0;
                    shared_seen <= 1'b0;
                    writer_seen <= 1'b0;
                    case (state)
                        S_BG: begin
                            display_q <= 2'd0;
                            display_valid <= 1'b1;
                            state <= S_THM;
                        end
                        S_THM: if (thumb_index == 4'd12)
                            state <= S_HOMETXT;
                        else thumb_index <= thumb_index + 4'd1;
                        S_HOMETXT, S_RETURN_TEXT: begin
                            display_q <= 2'd0;
                            state <= S_HOME;
                        end
                        S_PBG: state <= S_POR;
                        S_POR: state <= S_PTEXT;
                        S_PTEXT: begin
                            display_q <= 2'd1;
                            state <= S_PERSON;
                        end
                        default: state <= S_FAIL;
                    endcase
                end
                if (text_state && issued && asset_header_done) begin
                    if (asset_header_valid && asset_width == 16'd768 &&
                        asset_height == 16'd320)
                        mask_start <= 1'b1;
                    else begin
                        error_stage <= state;
                        state <= S_FAIL;
                    end
                end
            end else if (state == S_HOME) begin
                if (nav_level != 2'd0) begin
                    person_q <= nav_person[0];
                    state <= S_PBG;
                end
            end else if (state == S_PERSON) begin
                if (nav_level == 2'd0)
                    state <= S_RETURN_TEXT;
                else if (nav_person[0] != person_q) begin
                    person_q <= nav_person[0];
                    state <= S_PBG;
                end
            end
        end
    end
endmodule
