// Enumerate the assets required for a requested exhibition page.
// This module plans work only: the downstream compositor/loader must stage
// assets, discard stale generations, and commit them at a frame boundary.
module kiosk_page_plan (
    input wire clk, input wire rst,
    input wire request_valid, output wire request_ready,
    input wire [15:0] request_generation,
    input wire [1:0] request_level,
    input wire [4:0] request_person,
    input wire [2:0] request_section,
    input wire request_language_en,
    input wire [2:0] request_reveal_step,
    output wire command_valid, input wire command_ready,
    output wire [15:0] command_generation,
    output reg [1:0] command_kind, // 0 background, 1 portrait, 2 text
    output reg [87:0] command_sfn,
    output reg [4:0] command_person,
    output reg [2:0] command_layer, command_reveal_step,
    output reg [10:0] command_x, command_width,
    output reg [9:0] command_y, command_height,
    output reg plan_done, output reg plan_error, output reg quiz_page
);
    localparam IDLE=3'd0, SELECT_PAGE=3'd1, BACKGROUND=3'd2,
               PORTRAIT=3'd3, TEXT_CHECK=3'd4, TEXT_EMIT=3'd5, DONE=3'd6;
    reg [2:0] state;
    reg [15:0] generation_q;
    reg [1:0] level_q;
    reg [4:0] person_q, portrait_index;
    reg [2:0] section_q, reveal_q, layer_index, text_count_q;
    reg language_q;
    wire page_valid, is_quiz, unused_portrait_valid, text_valid;
    wire [5:0] slide_unused;
    wire [87:0] background_sfn, unused_portrait_sfn, text_sfn;
    wire [2:0] text_count, text_reveal;
    wire [10:0] text_x, text_width;
    wire [9:0] text_y, text_height;
    wire portrait_valid;
    wire [87:0] portrait_sfn;

    assign request_ready = state == IDLE;
    assign command_valid = state == BACKGROUND || state == PORTRAIT || state == TEXT_EMIT;
    assign command_generation = generation_q;

    kiosk_resource_lookup page_lookup (
        .level(level_q), .person_index(person_q), .section_index(section_q),
        .layer_index(layer_index), .language_en(language_q), .page_valid(page_valid),
        .quiz_page(is_quiz), .slide_number(slide_unused), .background_sfn(background_sfn),
        .portrait_valid(unused_portrait_valid), .portrait_sfn(unused_portrait_sfn),
        .layer_count(text_count), .layer_valid(text_valid), .layer_sfn(text_sfn),
        .layer_x(text_x), .layer_y(text_y), .layer_width(text_width),
        .layer_height(text_height), .reveal_step(text_reveal)
    );
    // Home contains all 13 independent portraits; person pages use one.
    kiosk_resource_lookup portrait_lookup (
        .level(2'd1), .person_index(portrait_index), .section_index(3'd0),
        .layer_index(3'd0), .language_en(1'b0), .page_valid(), .quiz_page(),
        .slide_number(), .background_sfn(), .portrait_valid(portrait_valid),
        .portrait_sfn(portrait_sfn), .layer_count(), .layer_valid(), .layer_sfn(),
        .layer_x(), .layer_y(), .layer_width(), .layer_height(), .reveal_step()
    );
    always @* begin
        command_kind=0; command_sfn=0; command_person=person_q;
        command_layer=0; command_reveal_step=0;
        command_x=0; command_y=0; command_width=0; command_height=0;
        case (state)
            BACKGROUND: begin command_kind=0; command_sfn=background_sfn; end
            PORTRAIT: begin command_kind=1; command_sfn=portrait_sfn; command_person=portrait_index; end
            TEXT_EMIT: begin
                command_kind=2; command_sfn=text_sfn; command_layer=layer_index;
                command_reveal_step=text_reveal; command_x=text_x; command_y=text_y;
                command_width=text_width; command_height=text_height;
            end
            default: ;
        endcase
    end
    always @(posedge clk) begin
        if (rst) begin
            state<=IDLE; generation_q<=0; level_q<=0; person_q<=0; section_q<=0;
            reveal_q<=0; language_q<=0; portrait_index<=0; layer_index<=0;
            text_count_q<=0; plan_done<=0; plan_error<=0; quiz_page<=0;
        end else begin
            plan_done<=0;
            case (state)
                IDLE: if (request_valid) begin
                    generation_q<=request_generation; level_q<=request_level;
                    person_q<=request_person; section_q<=request_section;
                    language_q<=request_language_en; reveal_q<=request_reveal_step;
                    plan_error<=0; quiz_page<=0; layer_index<=0;
                    portrait_index<=request_level==0 ? 0 : request_person;
                    state<=SELECT_PAGE;
                end
                SELECT_PAGE: begin
                    if (is_quiz) begin quiz_page<=1; state<=DONE; end
                    else if (!page_valid) begin plan_error<=1; state<=DONE; end
                    else begin text_count_q<=text_count; state<=BACKGROUND; end
                end
                BACKGROUND: if (command_ready) state<=PORTRAIT;
                PORTRAIT: if (!portrait_valid) begin plan_error<=1; state<=DONE; end
                          else if (command_ready) begin
                              if (level_q==0 && portrait_index<12) portrait_index<=portrait_index+1'b1;
                              else state<=TEXT_CHECK;
                          end
                TEXT_CHECK: begin
                    if (layer_index>=text_count_q) state<=DONE;
                    else if (!text_valid) begin plan_error<=1; state<=DONE; end
                    else if (text_reveal<=reveal_q) state<=TEXT_EMIT;
                    else layer_index<=layer_index+1'b1;
                end
                TEXT_EMIT: if (command_ready) begin layer_index<=layer_index+1'b1; state<=TEXT_CHECK; end
                DONE: begin plan_done<=1; state<=IDLE; end
                default: begin plan_error<=1; state<=DONE; end
            endcase
        end
    end
endmodule
