`timescale 1ns/1ps

// First complete FAT32 asset schedule: one cached home frame, 13 cached home
// portraits, and one replaceable person frame. The current person frame is
// composed before it becomes visible. All requests use 8.3 FAT names.
module kiosk_fat32_sequence_menu (
    input  wire        clk,
    input  wire        rst,
    input wire english,
    output wire loaded_english,
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
    output wire [87:0] target_sfn,
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
    output wire [4:0]  loaded_person,
    output wire [2:0]  loaded_section,
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
reg language_q;
reg [87:0] raw_sfn;
wire translate_text=language_q && (state==S_PTEXT || state==S_ATEXT);
assign target_sfn=translate_text ? ((state==S_PTEXT || section_q!=3 || person_q==0) ?
 {raw_sfn[87:48],8'h45,raw_sfn[39:0]} : {raw_sfn[87:40],8'h45,raw_sfn[31:0]}) : (language_q && state==S_ABG && section_q==1 ? {raw_sfn[87:80],8'h45,raw_sfn[71:0]} : raw_sfn);
assign loaded_english=language_q;
    reg issued, shared_seen, writer_seen;
    reg [3:0] thumb_index;
    reg [4:0] person_q;
    reg [2:0] section_q;
    wire [6:0] article_bg_number = 7'd3 + {person_q,2'b00} + (section_q == 3'd3 ? 7'd0 : {4'b0000,section_q});
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

    // Existing scene registers: no new storage, valid for playback only when
    // article_text_mode is asserted after both background and caption complete.
    assign loaded_person = person_q;
    assign loaded_section = section_q;
    assign loading = loading_state;
    assign text_visible = (state == S_HOME || state == S_PERSON ||
        (state == S_ARTICLE && section_q <= 3'd3)) &&
        display_valid;
    assign article_text_mode = state == S_ARTICLE && section_q <= 3'd3;
    assign display_frame_index = display_q;
    assign asset_mode = state != S_BG && state != S_PBG && state != S_ABG;
    assign frame_index = (state == S_PBG || state == S_ABG) ? 2'd1 : 2'd0;
    assign writer_pixel_route = portrait_state;
    assign mask_pixel_route = text_state;
    assign writer_frame_index = 2'd2;
    assign writer_first_offset = state == S_THM ?
        ({17'd0,thumb_index} * 21'd12800) : 21'd204288;
    assign writer_width = state == S_THM ? 16'd80 : 16'd320;
    assign writer_height = state == S_THM ? 16'd100 : 16'd400;
    assign writer_length = state == S_THM ? 21'd8000 : 21'd128000;
    // The home scanout reads portrait rows from bottom to top. Keep the
    // BMP's bottom-up row order in this cache; 2^21-49 advances 128 words.
    assign writer_line_jump = state == S_THM ? 21'd2097103 : 21'd831;

    always @* begin
        raw_sfn = "BG001   BMP";
        case (state)
            S_BG: raw_sfn = "BG001   BMP";
            S_THM: case (thumb_index)
                4'd0: raw_sfn="THM01   BMP";
                4'd1: raw_sfn="THM02   BMP";
                4'd2: raw_sfn="THM03   BMP";
                4'd3: raw_sfn="THM04   BMP";
                4'd4: raw_sfn="THM05   BMP";
                4'd5: raw_sfn="THM06   BMP";
                4'd6: raw_sfn="THM07   BMP";
                4'd7: raw_sfn="THM08   BMP";
                4'd8: raw_sfn="THM09   BMP";
                4'd9: raw_sfn="THM10   BMP";
                4'd10: raw_sfn="THM11   BMP";
                4'd11: raw_sfn="THM12   BMP";
                default: raw_sfn="THM13   BMP";
            endcase
            S_HOMETXT, S_RETURN_TEXT: raw_sfn=language_q ? "HOMEENG BMP" : "HOMETXT BMP";
            S_PBG: case (person_q)
                5'd0: raw_sfn="BG002   BMP";
                5'd1: raw_sfn="BG006   BMP";
                5'd2: raw_sfn="BG010   BMP";
                5'd3: raw_sfn="BG014   BMP";
                5'd4: raw_sfn="BG018   BMP";
                5'd5: raw_sfn="BG022   BMP";
                5'd6: raw_sfn="BG026   BMP";
                5'd7: raw_sfn="BG030   BMP";
                5'd8: raw_sfn="BG034   BMP";
                5'd9: raw_sfn="BG038   BMP";
                5'd10: raw_sfn="BG042   BMP";
                5'd11: raw_sfn="BG046   BMP";
                default: raw_sfn="BG050   BMP";
            endcase
            S_POR: case (person_q)
                5'd0: raw_sfn="POR01   BMP";
                5'd1: raw_sfn="POR02   BMP";
                5'd2: raw_sfn="POR03   BMP";
                5'd3: raw_sfn="POR04   BMP";
                5'd4: raw_sfn="POR05   BMP";
                5'd5: raw_sfn="POR06   BMP";
                5'd6: raw_sfn="POR07   BMP";
                5'd7: raw_sfn="POR08   BMP";
                5'd8: raw_sfn="POR09   BMP";
                5'd9: raw_sfn="POR10   BMP";
                5'd10: raw_sfn="POR11   BMP";
                5'd11: raw_sfn="POR12   BMP";
                default: raw_sfn="POR13   BMP";
            endcase
            S_PTEXT: case (person_q)
                5'd0: raw_sfn="ITX01C  BMP";
                5'd1: raw_sfn="ITX02C  BMP";
                5'd2: raw_sfn="ITX03C  BMP";
                5'd3: raw_sfn="ITX04C  BMP";
                5'd4: raw_sfn="ITX05C  BMP";
                5'd5: raw_sfn="ITX06C  BMP";
                5'd6: raw_sfn="ITX07C  BMP";
                5'd7: raw_sfn="ITX08C  BMP";
                5'd8: raw_sfn="ITX09C  BMP";
                5'd9: raw_sfn="ITX10C  BMP";
                5'd10: raw_sfn="ITX11C  BMP";
                5'd11: raw_sfn="ITX12C  BMP";
                default: raw_sfn="ITX13C  BMP";
            endcase
            S_ABG: raw_sfn=article_background_sfn;
            S_ATEXT: if (section_q != 3'd3) raw_sfn={"ART", article_background_sfn[63:48], "C  BMP"};
                else case (person_q)
                    0: raw_sfn="QUIZ3C  BMP"; 1: raw_sfn="QUIZ02C BMP"; 2: raw_sfn="QUIZ03C BMP";
                    3: raw_sfn="QUIZ04C BMP"; 4: raw_sfn="QUIZ05C BMP"; 5: raw_sfn="QUIZ06C BMP";
                    6: raw_sfn="QUIZ07C BMP"; 7: raw_sfn="QUIZ08C BMP"; 8: raw_sfn="QUIZ09C BMP";
                    9: raw_sfn="QUIZ10C BMP"; 10: raw_sfn="QUIZ11C BMP"; 11: raw_sfn="QUIZ12C BMP";
                    default: raw_sfn="QUIZ13C BMP";
                endcase
            default: raw_sfn="BG001   BMP";
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            language_q <= 0;
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
                            if (section_q <= 3'd3)
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
            end else if ((state==S_HOME || state==S_PERSON || state==S_ARTICLE) && language_q!=english) begin
                language_q<=english;
                if(state==S_HOME) state<=S_RETURN_TEXT;
                else if(state==S_PERSON) state<=S_PTEXT;
                else if(section_q==1) state<=S_ABG; else state<=S_ATEXT;
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
                else if (nav_level == 2'd2 && nav_section <= 3'd3) begin
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
                else if (nav_level == 2'd1) begin
                    person_q <= nav_person;
                    state <= S_PBG;
                end else if (nav_level == 2'd2 && nav_section != section_q && nav_section < 3'd3) begin
                    section_q <= nav_section;
                    state <= S_ABG;
                end
            end
        end
    end
endmodule
