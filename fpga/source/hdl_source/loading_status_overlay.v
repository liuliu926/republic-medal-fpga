// China-red full-screen transition overlay for TF-backed page loads.
// A frame-quantized horizontal wipe replaces alpha fading and needs no image RAM.
module loading_status_overlay (
    input  wire        clk,
    input  wire        rst,
    input  wire        vs,
    input  wire        de,
    input  wire        loading,
    input  wire [23:0] rgb_in,
    output reg  [23:0] rgb_out
);
    reg [10:0] x;
    reg [9:0] y;
    reg de_q, vs_q;
    reg [6:0] sweep_pos;
    reg       sweep_reverse;
    reg [10:0] wipe_x;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            x <= 0; y <= 0; de_q <= 0; vs_q <= 0;
            sweep_pos <= 0; sweep_reverse <= 0; wipe_x <= 0;
        end else begin
            de_q <= de;
            vs_q <= vs;
            // Advance/retract the reveal edge once per frame for a smooth wipe.
            if (vs && !vs_q) begin
                if (loading && wipe_x < 11'd1280) begin
                    if (wipe_x > 11'd1215) wipe_x <= 11'd1280;
                    else wipe_x <= wipe_x + 11'd64;
                end else if (!loading && wipe_x != 0) begin
                    if (wipe_x < 11'd64) wipe_x <= 0;
                    else wipe_x <= wipe_x - 11'd64;
                end

                // A triangular sweep reverses at the ends instead of jumping
                // back to the left edge, so the progress light moves smoothly.
                if (loading) begin
                    if (!sweep_reverse) begin
                        if (sweep_pos >= 7'd64)
                            sweep_reverse <= 1'b1;
                        else
                            sweep_pos <= sweep_pos + 1'b1;
                    end else begin
                        if (sweep_pos == 0)
                            sweep_reverse <= 1'b0;
                        else
                            sweep_pos <= sweep_pos - 1'b1;
                    end
                end
            end
            if (!loading && wipe_x == 0) begin
                sweep_pos <= 0;
                sweep_reverse <= 0;
            end

            if (vs != vs_q) begin x <= 0; y <= 0; end
            else begin
                if (de) x <= x + 1'b1;
                else x <= 0;
                if (de_q && !de) y <= y + 1'b1;
            end
        end
    end

    wire panel = x >= 11'd440 && x < 11'd840 &&
                 y >= 10'd300 && y < 10'd420;
    wire panel_border = panel && (x < 11'd444 || x >= 11'd836 ||
                                  y < 10'd304 || y >= 10'd416);
    wire panel_inner = panel && (x < 11'd448 || x >= 11'd832 ||
                                 y < 10'd308 || y >= 10'd412);
    wire text_area = x >= 11'd528 && x < 11'd752 &&
                     y >= 10'd332 && y < 10'd348;
    wire [2:0] char_index = (x - 11'd528) >> 5;
    wire [2:0] glyph_x = (x - 11'd528) >> 2;
    wire [2:0] glyph_y = (y - 10'd332) >> 1;
    reg [7:0] glyph_row;

    always @* begin
        glyph_row = 8'h00;
        case (char_index)
            3'd0: case (glyph_y)
                0: glyph_row=8'hFE; 1: glyph_row=8'h80; 2: glyph_row=8'h80;
                3: glyph_row=8'h80; 4: glyph_row=8'h80; 5: glyph_row=8'h80;
                6: glyph_row=8'h80; 7: glyph_row=8'h80; default: ;
            endcase // L
            3'd1: case (glyph_y)
                0: glyph_row=8'h7C; 1: glyph_row=8'h82; 2: glyph_row=8'h82;
                3: glyph_row=8'h82; 4: glyph_row=8'h82; 5: glyph_row=8'h82;
                6: glyph_row=8'h82; 7: glyph_row=8'h7C; default: ;
            endcase // O
            3'd2: case (glyph_y)
                0: glyph_row=8'h7C; 1: glyph_row=8'h82; 2: glyph_row=8'h82;
                3: glyph_row=8'hFE; 4: glyph_row=8'h82; 5: glyph_row=8'h82;
                6: glyph_row=8'h82; 7: glyph_row=8'h82; default: ;
            endcase // A
            3'd3: case (glyph_y)
                0: glyph_row=8'hFC; 1: glyph_row=8'h82; 2: glyph_row=8'h82;
                3: glyph_row=8'h82; 4: glyph_row=8'h82; 5: glyph_row=8'h82;
                6: glyph_row=8'h82; 7: glyph_row=8'hFC; default: ;
            endcase // D
            3'd4: case (glyph_y)
                0: glyph_row=8'hFE; 1: glyph_row=8'h10; 2: glyph_row=8'h10;
                3: glyph_row=8'h10; 4: glyph_row=8'h10; 5: glyph_row=8'h10;
                6: glyph_row=8'h10; 7: glyph_row=8'hFE; default: ;
            endcase // I
            3'd5: case (glyph_y)
                0: glyph_row=8'h82; 1: glyph_row=8'hC2; 2: glyph_row=8'hA2;
                3: glyph_row=8'h92; 4: glyph_row=8'h8A; 5: glyph_row=8'h86;
                6: glyph_row=8'h82; 7: glyph_row=8'h82; default: ;
            endcase // N
            3'd6: case (glyph_y)
                0: glyph_row=8'h7C; 1: glyph_row=8'h82; 2: glyph_row=8'h80;
                3: glyph_row=8'h9E; 4: glyph_row=8'h82; 5: glyph_row=8'h82;
                6: glyph_row=8'h82; 7: glyph_row=8'h7C; default: ;
            endcase // G
            default: glyph_row=8'h00;
        endcase
    end

    wire glyph_pixel = glyph_row[7-glyph_x];
    wire bar_track = x >= 11'd520 && x < 11'd760 &&
                     y >= 10'd376 && y < 10'd392;
    wire [8:0] moving_start = 9'd520 + {sweep_pos, 1'b0} + sweep_pos;
    wire bar_body = bar_track && y >= 10'd380 && y < 10'd388 &&
                    x >= moving_start && x < moving_start + 9'd48;
    wire bar_head = bar_body && x < moving_start + 9'd12;
    wire bar_tail = bar_body && x >= moving_start + 9'd36;

    always @* begin
        rgb_out = rgb_in;
        if ((loading || wipe_x != 0) && de && x < wipe_x) begin
            // Full-page Chinese flag red, with a bright yellow loading card.
            rgb_out = 24'hDE2910;
            if (panel) rgb_out = 24'hFFDE00;
            if (panel_border) rgb_out = 24'hFFF2C0;
            if (panel_inner) rgb_out = 24'hF2C400;
            if (text_area && glyph_pixel) rgb_out = 24'h8C1C13;
            if (bar_track) rgb_out = 24'h8C1C13;
            if (bar_body) rgb_out = 24'hFFF2C0;
            if (bar_tail) rgb_out = 24'hF2C400;
            if (bar_head) rgb_out = 24'hFFFFFF;
        end
    end
endmodule
