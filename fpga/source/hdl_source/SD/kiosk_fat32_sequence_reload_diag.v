`timescale 1ns/1ps

// First complete FAT32 asset schedule: one cached home frame, 13 cached home
// portraits, and one replaceable person frame. The current person frame is
// composed before it becomes visible. All requests use 8.3 FAT names.
module kiosk_fat32_sequence_menu (
    input  wire        clk,
    input  wire        rst,
    input  wire        mem_ready,
    input  wire        sd_ready,
    input  wire [1:0]  nav_level,
    input  wire [4:0]  nav_person,
    input  wire [2:0]  nav_section,
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
    output wire        article_text_mode,
    output wire        loading,
    output reg [3:0]   error_stage,
    output reg  [3:0]  debug_state,
    output reg  [3:0]  debug_thumb_index
);
    localparam [3:0] S_BG=4'd0, S_THM=4'd1, S_HOMETXT=4'd2,
                     S_HOME=4'd3, S_PBG=4'd4, S_POR=4'd5,
                     S_PTEXT=4'd6, S_PERSON=4'd7,
                     S_RETURN_TEXT=4'd8, S_FAIL=4'd9,
                     S_ABG=4'd10, S_ARTICLE=4'd11,
                     S_ATEXT=4'd12;
    reg [3:0] state;
    reg issued, shared_seen, writer_seen;
    reg [3:0] thumb_index;
    reg [4:0] person_q;
    reg [2:0] section_q;
    wire [6:0] article_bg_number = 7'd3 + {person_q,2'b00} + {4'b0000,section_q};
    reg [87:0] article_background_sfn;
    always @* begin
        article_background_sfn = "BG003   BMP";
        case (article_bg_number)
            7'd3: article_background_sfn="BG003   BMP";
            7'd4: article_background_sfn="BG004   BMP";
            7'd5: article_background_sfn="BG005   BMP";
            7'd7: article_background_sfn="BG007   BMP";
            7'd8: article_background_sfn="BG008   BMP";
            7'd9: article_background_sfn="BG009   BMP";
            7'd11: article_background_sfn="BG011   BMP";
            7'd12: article_background_sfn="BG012   BMP";
            7'd13: article_background_sfn="BG013   BMP";
            7'd15: article_background_sfn="BG015   BMP";
            7'd16: article_background_sfn="BG016   BMP";
            7'd17: article_background_sfn="BG017   BMP";
            7'd19: article_background_sfn="BG019   BMP";
            7'd20: article_background_sfn="BG020   BMP";
            7'd21: article_background_sfn="BG021   BMP";
            7'd23: article_background_sfn="BG023   BMP";
            7'd24: article_background_sfn="BG024   BMP";
            7'd25: article_background_sfn="BG025   BMP";
            7'd27: article_background_sfn="BG027   BMP";
            7'd28: article_background_sfn="BG028   BMP";
            7'd29: article_background_sfn="BG029   BMP";
            7'd31: article_background_sfn="BG031   BMP";
            7'd32: article_background_sfn="BG032   BMP";
            7'd33: article_background_sfn="BG033   BMP";
            7'd35: article_background_sfn="BG035   BMP";
            7'd36: article_background_sfn="BG036   BMP";
            7'd37: article_background_sfn="BG037   BMP";
            7'd39: article_background_sfn="BG039   BMP";
            7'd40: article_background_sfn="BG040   BMP";
            7'd41: article_background_sfn="BG041   BMP";
            7'd43: article_background_sfn="BG043   BMP";
            7'd44: article_background_sfn="BG044   BMP";
            7'd45: article_background_sfn="BG045   BMP";
            7'd47: article_background_sfn="BG047   BMP";
            7'd48: article_background_sfn="BG048   BMP";
            7'd49: article_background_sfn="BG049   BMP";
            7'd51: article_background_sfn="BG051   BMP";
            7'd52: article_background_sfn="BG052   BMP";
            7'd53: article_background_sfn="BG053   BMP";
            default: article_background_sfn="BG003   BMP";
        endcase
    end
    reg [1:0] display_q;
    reg [1:0] mem_ready_sync;

    wire loading_state = state == S_BG || state == S_THM ||
        state == S_HOMETXT || state == S_PBG || state == S_POR ||
        state == S_PTEXT || state == S_RETURN_TEXT || state == S_ABG ||
        state == S_ATEXT;
    wire portrait_state = state == S_THM || state == S_POR;
    wire text_state = state == S_HOMETXT || state == S_PTEXT ||
                      state == S_RETURN_TEXT || state == S_ATEXT;
    wire command_complete = (shared_seen || shared_done) &&
                            (!portrait_state || writer_seen || writer_done);

    assign loading = loading_state;
    assign text_visible = (state == S_HOME || state == S_PERSON ||
        (state == S_ARTICLE && person_q == 5'd0 && section_q <= 3'd3)) &&
        display_valid;
    assign article_text_mode = state == S_ARTICLE && person_q == 5'd0 && section_q <= 3'd3;
    assign display_frame_index = display_q;
    assign asset_mode = state != S_BG && state != S_PBG && state != S_ABG;
    assign frame_index = (state == S_PBG || state == S_ABG) ? 2'd1 : 2'd0;
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
            S_PBG: case (person_q)
                5'd0: target_sfn="BG002   BMP";
                5'd1: target_sfn="BG006   BMP";
                5'd2: target_sfn="BG010   BMP";
                5'd3: target_sfn="BG014   BMP";
                5'd4: target_sfn="BG018   BMP";
                5'd5: target_sfn="BG022   BMP";
                5'd6: target_sfn="BG026   BMP";
                5'd7: target_sfn="BG030   BMP";
                5'd8: target_sfn="BG034   BMP";
                5'd9: target_sfn="BG038   BMP";
                5'd10: target_sfn="BG042   BMP";
                5'd11: target_sfn="BG046   BMP";
                default: target_sfn="BG050   BMP";
            endcase
            S_POR: case (person_q)
                5'd0: target_sfn="POR01   BMP";
                5'd1: target_sfn="POR02   BMP";
                5'd2: target_sfn="POR03   BMP";
                5'd3: target_sfn="POR04   BMP";
                5'd4: target_sfn="POR05   BMP";
                5'd5: target_sfn="POR06   BMP";
                5'd6: target_sfn="POR07   BMP";
                5'd7: target_sfn="POR08   BMP";
                5'd8: target_sfn="POR09   BMP";
                5'd9: target_sfn="POR10   BMP";
                5'd10: target_sfn="POR11   BMP";
                5'd11: target_sfn="POR12   BMP";
                default: target_sfn="POR13   BMP";
            endcase
            S_PTEXT: case (person_q)
                5'd0: target_sfn="ITX01C  BMP";
                5'd1: target_sfn="ITX02C  BMP";
                5'd2: target_sfn="ITX03C  BMP";
                5'd3: target_sfn="ITX04C  BMP";
                5'd4: target_sfn="ITX05C  BMP";
                5'd5: target_sfn="ITX06C  BMP";
                5'd6: target_sfn="ITX07C  BMP";
                5'd7: target_sfn="ITX08C  BMP";
                5'd8: target_sfn="ITX09C  BMP";
                5'd9: target_sfn="ITX10C  BMP";
                5'd10: target_sfn="ITX11C  BMP";
                5'd11: target_sfn="ITX12C  BMP";
                default: target_sfn="ITX13C  BMP";
            endcase
            S_ABG: target_sfn=section_q == 3'd3 ? "BG003   BMP" : article_background_sfn;
            S_ATEXT: target_sfn=section_q == 3'd3 ? "QUIZ3C  BMP" : section_q == 3'd2 ? "ART05C  BMP" : section_q == 3'd1 ? "ART04C  BMP" : "ART03C  BMP";
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
            person_q <= 5'd0;
            section_q <= 3'd0;
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
                        S_ABG: begin
                            display_q <= 2'd1;
                            if (person_q == 5'd0 && section_q <= 3'd3)
                                state <= S_ATEXT;
                            else state <= S_ARTICLE;
                        end
                        S_ATEXT: begin
                            state <= S_ARTICLE;
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
                    person_q <= nav_person;
                    state <= S_PBG;
                end
            end else if (state == S_PERSON) begin
                if (nav_level == 2'd0) begin
                    thumb_index <= 0;
                    state <= S_BG;
                end
                else if (nav_level == 2'd2 && (nav_section < 3'd3 || (person_q == 0 && nav_section == 3'd3))) begin
                    section_q <= nav_section;
                    state <= S_ABG;
                end
                else if (nav_person != person_q) begin
                    person_q <= nav_person;
                    state <= S_PBG;
                end
            end else if (state == S_ARTICLE) begin
                if (nav_level == 2'd0) begin
                    thumb_index <= 0;
                    state <= S_BG;
                end
                else if (nav_level == 2'd1)
                    state <= S_PBG;
            end
        end
    end
endmodule
