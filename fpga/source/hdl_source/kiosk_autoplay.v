// Autoplay shows biography, contributions and representative deeds only.
// Interactive quizzes remain available through manual navigation.
module kiosk_autoplay #(
    parameter integer HOME_CYCLES = 100_000_000,
    parameter integer PERSON_CYCLES = 100_000_000,
    parameter integer ARTICLE_CYCLES = 300_000_000
)(
    input wire clk,
    input wire rst,
    input wire auto_mode,
    input wire pause,
    output reg [1:0] level,
    output reg [4:0] person_index,
    output reg [2:0] section_index,
    output reg [7:0] page_index
);

localparam [1:0] HOME = 2'd0;
localparam [1:0] PERSON = 2'd1;
localparam [1:0] ARTICLE = 2'd2;
localparam [2:0] LAST_AUTO_SECTION = 3'd2;
reg [31:0] count;

wire [31:0] duration = (level == HOME) ? HOME_CYCLES :
                       (level == PERSON) ? PERSON_CYCLES : ARTICLE_CYCLES;

always @(posedge clk) begin
    if (rst || !auto_mode) begin
        level <= HOME;
        person_index <= 5'd0;
        section_index <= 3'd0;
        page_index <= 8'd0;
        count <= 32'd0;
    end else if (!pause) begin
        if (count < duration - 32'd1) begin
            count <= count + 32'd1;
        end else begin
            count <= 32'd0;
            case (level)
                HOME: level <= PERSON;
                PERSON: begin
                    level <= ARTICLE;
                    section_index <= 3'd0;
                    page_index <= 8'd0;
                end
                ARTICLE: begin
                    if (person_index == 5'd0 && section_index <= LAST_AUTO_SECTION && page_index == 8'd0) begin
                        page_index <= 8'd1;
                    end else if (section_index < LAST_AUTO_SECTION) begin
                        section_index <= section_index + 3'd1;
                        page_index <= 8'd0;
                    end else begin
                        person_index <= (person_index == 5'd12) ? 5'd0 : person_index + 5'd1;
                        section_index <= 3'd0;
                        page_index <= 8'd0;
                        level <= HOME;
                    end
                end
                default: level <= HOME;
            endcase
        end
    end
end

endmodule
