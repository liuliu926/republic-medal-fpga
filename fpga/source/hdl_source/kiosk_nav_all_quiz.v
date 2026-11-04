// Three-level navigation for the Republic Medal exhibition.
// All key inputs are single-clock pulses produced by a separate debounce block.
module kiosk_nav #(
    parameter integer PERSON_COUNT  = 13,
    parameter integer SECTION_COUNT = 4
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       auto_mode,
    input  wire       exit_to_home_pulse,
    input  wire       key_next_pulse,
    input  wire       key_prev_pulse,
    input  wire       key_back_pulse,
    input  wire       key_enter_pulse,
    input  wire [7:0] page_count,
    output reg  [1:0] level,
    output reg  [4:0] person_index,
    output reg  [2:0] section_index,
    output reg  [7:0] page_index,
    output reg        quiz_option,
    output reg        quiz_revealed
);

localparam [1:0] HOME = 2'd0;
localparam [1:0] PERSON = 2'd1;
localparam [1:0] ARTICLE = 2'd2;

always @(posedge clk) begin
    if (rst || exit_to_home_pulse) begin
        level         <= HOME;
        person_index  <= 5'd0;
        section_index <= 3'd0;
        page_index    <= 8'd0;
        quiz_option   <= 1'b0;
        quiz_revealed <= 1'b0;
    end else if (auto_mode) begin
        // In autoplay, physical keys are handled by kiosk_mode as a help prompt.
    end else if (key_back_pulse) begin
        case (level)
            ARTICLE: level <= PERSON;
            PERSON:  level <= HOME;
            default: level <= HOME;
        endcase
    end else if (key_enter_pulse) begin
        case (level)
            HOME: begin
                level         <= PERSON;
                section_index <= 3'd0;
            end
            PERSON: begin
                level      <= ARTICLE;
                page_index <= 8'd0;
                quiz_option <= 1'b0;
                quiz_revealed <= 1'b0;
            end
            ARTICLE: if (section_index == 3'd3)
                         quiz_revealed <= 1'b1;
            default: ;
        endcase
    end else if (key_next_pulse) begin
        case (level)
            HOME: person_index <= (person_index == PERSON_COUNT - 1)
                                     ? 5'd0 : person_index + 5'd1;
            PERSON: section_index <= (section_index == SECTION_COUNT - 1)
                                        ? 3'd0 : section_index + 3'd1;
            ARTICLE: if (section_index == 3'd3) begin
                         page_index <= page_index == 2 ? 0 : page_index + 1'b1;
                         quiz_revealed <= 1'b0;
                     end else if (page_count != 8'd0 && page_index < page_count - 8'd1)
                         page_index <= page_index + 8'd1;
            default: ;
        endcase
    end else if (key_prev_pulse) begin
        case (level)
            HOME: person_index <= (person_index == 5'd0)
                                     ? PERSON_COUNT - 1 : person_index - 5'd1;
            PERSON: section_index <= (section_index == 3'd0)
                                        ? SECTION_COUNT - 1 : section_index - 3'd1;
            ARTICLE: if (section_index == 3'd3) begin
                         page_index <= page_index == 0 ? 2 : page_index - 1'b1;
                         quiz_revealed <= 1'b0;
                     end else if (page_index != 8'd0)
                         page_index <= page_index - 8'd1;
            default: ;
        endcase
    end
end

endmodule
