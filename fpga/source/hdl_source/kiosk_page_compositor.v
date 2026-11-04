// Sequentially dispatch all portrait/text layers for one inactive page.
// The background manager loads the background before starting this block.
// An external renderer owns TF decoding, positioning and memory arbitration;
// asset_done must occur at least one cycle after an accepted asset_valid.
module kiosk_page_compositor (
    input wire clk, input wire rst,
    input wire start, input wire [15:0] generation, input wire [1:0] frame_index,
    input wire [1:0] level, input wire [4:0] person, input wire [2:0] section,
    input wire language_en, input wire [2:0] reveal_step,
    output wire asset_valid, input wire asset_ready,
    output wire [15:0] asset_generation, output wire [1:0] asset_frame_index,
    output wire [1:0] asset_kind, output wire [87:0] asset_sfn,
    output wire [4:0] asset_person, output wire [2:0] asset_layer, asset_reveal_step,
    output wire [10:0] asset_x, asset_width, output wire [9:0] asset_y, asset_height,
    input wire asset_done, input wire asset_error, input wire asset_recovery_required,
    output reg busy, output reg done, output reg error, output reg recovery_required,
    output reg quiz_page
);
    localparam IDLE=3'd0, PLAN_START=3'd1, DISPATCH=3'd2, WAIT_ASSET=3'd3,
               COMPLETE=3'd4, ABORT=3'd5;
    reg [2:0] state;
    reg [15:0] generation_q;
    reg [1:0] frame_q, level_q;
    reg [4:0] person_q;
    reg [2:0] section_q, reveal_q;
    reg language_q, plan_finished;
    wire plan_ready, plan_valid, plan_done, plan_error, plan_quiz;
    wire [1:0] plan_kind;
    wire plan_command_ready = (state==DISPATCH) && plan_valid &&
                              ((plan_kind==0) || asset_ready);
    assign asset_valid = (state==DISPATCH) && plan_valid && plan_kind!=0;
    assign asset_kind = plan_kind;
    assign asset_frame_index = frame_q;

    kiosk_page_plan planner (
        .clk(clk),.rst(rst || state==ABORT),
        .request_valid(state==PLAN_START),.request_ready(plan_ready),
        .request_generation(generation_q),.request_level(level_q),
        .request_person(person_q),.request_section(section_q),
        .request_language_en(language_q),.request_reveal_step(reveal_q),
        .command_valid(plan_valid),.command_ready(plan_command_ready),
        .command_generation(asset_generation),.command_kind(plan_kind),
        .command_sfn(asset_sfn),.command_person(asset_person),
        .command_layer(asset_layer),.command_reveal_step(asset_reveal_step),
        .command_x(asset_x),.command_y(asset_y),.command_width(asset_width),
        .command_height(asset_height),.plan_done(plan_done),.plan_error(plan_error),
        .quiz_page(plan_quiz)
    );
    always @(posedge clk) begin
        if(rst) begin
            state<=IDLE;generation_q<=0;frame_q<=0;level_q<=0;person_q<=0;
            section_q<=0;reveal_q<=0;language_q<=0;plan_finished<=0;
            busy<=0;done<=0;error<=0;recovery_required<=0;quiz_page<=0;
        end else begin
            done<=0;
            if(plan_done && (state==DISPATCH || state==WAIT_ASSET)) begin
                plan_finished<=1;
                if(plan_error) error<=1;
                if(plan_quiz) quiz_page<=1;
            end
            case(state)
                IDLE: if(start) begin
                    generation_q<=generation;frame_q<=frame_index;level_q<=level;
                    person_q<=person;section_q<=section;language_q<=language_en;
                    reveal_q<=reveal_step;plan_finished<=0;
                    busy<=1;error<=0;recovery_required<=0;quiz_page<=0;
                    state<=PLAN_START;
                end
                PLAN_START: if(plan_ready) state<=DISPATCH;
                DISPATCH: begin
                    if(plan_finished) state<=COMPLETE;
                    else if(asset_valid && asset_ready) state<=WAIT_ASSET;
                end
                WAIT_ASSET: if(asset_done) begin
                    if(asset_error || asset_recovery_required) begin
                        error<=1;recovery_required<=asset_recovery_required;state<=ABORT;
                    end else state<=DISPATCH;
                end
                ABORT: state<=COMPLETE;
                COMPLETE: begin busy<=0;done<=1;state<=IDLE;end
                default: begin error<=1;state<=ABORT;end
            endcase
        end
    end
endmodule
