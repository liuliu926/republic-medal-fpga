// Pixel-synchronous overlay for the campus information / emergency demo.
// The text is generated in FPGA logic; it is not part of the BMP files.
module emergency_osd (
    input             clk,
    input             rst,
    input             vs,
    input             de,
    input             alarm_mode,
    input      [23:0] rgb_in,
    output reg [23:0] rgb_out
);

reg [9:0] x;
reg [8:0] y;
reg de_q;
reg vs_q;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        x    <= 10'd0;
        y    <= 9'd0;
        de_q <= 1'b0;
        vs_q <= 1'b0;
    end else begin
        de_q <= de;
        vs_q <= vs;
        if (vs != vs_q) begin
            x <= 10'd0;
            y <= 9'd0;
        end else begin
            if (de)
                x <= x + 10'd1;
            else
                x <= 10'd0;
            if (de_q && !de)
                y <= y + 9'd1;
        end
    end
end

function [7:0] title_char;
    input [4:0] index;
    input emergency;
    begin
        title_char = " ";
        if (emergency) begin
            case (index)
                 0: title_char = "E";
                 1: title_char = "M";
                 2: title_char = "E";
                 3: title_char = "R";
                 4: title_char = "G";
                 5: title_char = "E";
                 6: title_char = "N";
                 7: title_char = "C";
                 8: title_char = "Y";
                10: title_char = "A";
                11: title_char = "L";
                12: title_char = "E";
                13: title_char = "R";
                14: title_char = "T";
                default: title_char = " ";
            endcase
        end else begin
            case (index)
                 0: title_char = "C";
                 1: title_char = "A";
                 2: title_char = "M";
                 3: title_char = "P";
                 4: title_char = "U";
                 5: title_char = "S";
                 7: title_char = "I";
                 8: title_char = "N";
                 9: title_char = "F";
                10: title_char = "O";
                default: title_char = " ";
            endcase
        end
    end
endfunction

// Seven rows of five pixels per glyph, MSB is the leftmost pixel.
function [34:0] glyph;
    input [7:0] c;
    begin
        case (c)
            "A": glyph = {5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
            "C": glyph = {5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
            "E": glyph = {5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
            "F": glyph = {5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
            "G": glyph = {5'b01111,5'b10000,5'b10000,5'b10111,5'b10001,5'b10001,5'b01111};
            "I": glyph = {5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b11111};
            "L": glyph = {5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
            "M": glyph = {5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
            "N": glyph = {5'b10001,5'b11001,5'b10101,5'b10011,5'b10001,5'b10001,5'b10001};
            "O": glyph = {5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
            "P": glyph = {5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
            "R": glyph = {5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
            "S": glyph = {5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
            "T": glyph = {5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
            "U": glyph = {5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
            "Y": glyph = {5'b10001,5'b10001,5'b01010,5'b00100,5'b00100,5'b00100,5'b00100};
            default: glyph = 35'd0;
        endcase
    end
endfunction

wire [9:0] text_x = x - 10'd24;
wire [8:0] text_y = y - 9'd25;
wire [4:0] letter_index = text_x[8:4];
wire [34:0] letter_glyph = glyph(title_char(letter_index, alarm_mode));
reg [4:0] row_bits;

always @* begin
    case (text_y[3:1])
        3'd0: row_bits = letter_glyph[34:30];
        3'd1: row_bits = letter_glyph[29:25];
        3'd2: row_bits = letter_glyph[24:20];
        3'd3: row_bits = letter_glyph[19:15];
        3'd4: row_bits = letter_glyph[14:10];
        3'd5: row_bits = letter_glyph[9:5];
        3'd6: row_bits = letter_glyph[4:0];
        default: row_bits = 5'd0;
    endcase
end

wire text_pixel = (x >= 10'd24 && x < 10'd264 &&
                   y >= 9'd25 && y < 9'd39 &&
                   text_x[3:1] < 3'd5 &&
                   row_bits[4 - text_x[3:1]]);

always @* begin
    rgb_out = rgb_in;
    if (de) begin
        if (x >= 10'd12 && x < 10'd628 && y >= 9'd12 && y < 9'd62)
            rgb_out = alarm_mode ? 24'hB52028 : 24'h123B64;
        if (x >= 10'd12 && x < 10'd628 && y >= 9'd58 && y < 9'd62)
            rgb_out = alarm_mode ? 24'hFFC247 : 24'h52C7E8;
        if (text_pixel)
            rgb_out = 24'hFFFFFF;
    end
end

endmodule
