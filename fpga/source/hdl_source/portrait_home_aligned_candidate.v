// One TF-loaded 80x100 portrait, cached independently of the background.
// The BMP stream is bottom-up; the video reader reverses its row order.
module portrait_bram_overlay (
    input wire write_clk,
    input wire write_rst,
    input wire pixel_start,
    input wire pixel_valid,
    input wire [23:0] pixel_data,
    input wire video_clk,
    input wire video_rst,
    input wire vs,
    input wire de,
    input wire [4:0] selected_index,
    input wire [23:0] background,
    output wire [23:0] rgb_out
);
    reg [23:0] portrait_ram [0:7999];
    reg [12:0] write_index;
    reg portrait_ready;

    always @(posedge write_clk or posedge write_rst) begin
        if (write_rst) begin
            write_index <= 13'd0;
            portrait_ready <= 1'b0;
        end else if (pixel_start) begin
            write_index <= 13'd0;
            portrait_ready <= 1'b0;
        end else if (pixel_valid && !portrait_ready) begin
            portrait_ram[write_index] <= pixel_data;
            if (write_index == 13'd7999) begin
                portrait_ready <= 1'b1;
            end else begin
                write_index <= write_index + 13'd1;
            end
        end
    end

    reg [10:0] x;
    reg [9:0] y;
    reg de_q, vs_q;
    reg ready_meta, ready_sync;
    reg in_portrait_q;
    reg selected_border_q;
    // Measured outer strokes in BG001.BMP, inclusive pixel coordinates.
    // The PPT grid uses rounded fractional spacing; repeated integer 296/133
    // arithmetic drifts by up to four pixels in the lower/right cards.
    reg [10:0] card_left,card_right;
    reg [9:0] card_top,card_bottom;
    always @* begin
        case(selected_index[1:0])
          0:begin card_left=57;card_right=333;end
          1:begin card_left=353;card_right=629;end
          2:begin card_left=650;card_right=926;end
          default:begin card_left=946;card_right=1222;end
        endcase
        case(selected_index[4:2])
          0:begin card_top=163;card_bottom=276;end
          1:begin card_top=296;card_bottom=409;end
          2:begin card_top=430;card_bottom=542;end
          default:begin card_top=563;card_bottom=675;end
        endcase
    end
    // Registered border uses a one-pixel look-ahead, so its output remains
    // aligned to the undelayed background without a long final RGB path.
    wire [10:0] border_x=x+11'd1;
    wire in_card=de && border_x>=card_left && border_x<=card_right && y>=card_top && y<=card_bottom;
    wire [10:0] edge_x=(border_x-card_left < card_right-border_x) ? border_x-card_left : card_right-border_x;
    wire [9:0] edge_y=(y-card_top < card_bottom-y) ? y-card_top : card_bottom-y;
    // Six-pixel rounded outer corners, matching the independent TF artwork.
    wire rounded_outer=(edge_y>=5 || edge_x>=5) ||
        (edge_y>=1 && edge_x>=3) || (edge_y>=2 && edge_x>=2) ||
        (edge_y>=3 && edge_x>=1);
    wire selected_border=in_card && rounded_outer && (edge_x<3 || edge_y<3);
    reg [23:0] portrait_data_q;
    wire in_portrait = de && x >= 11'd66 && x < 11'd146 &&
                       y >= 10'd170 && y < 10'd270;
    wire [9:0] source_row = 10'd269 - y;
    wire [12:0] row_extended = {3'b000, source_row};
    wire [12:0] portrait_address = (row_extended << 6) +
                                   (row_extended << 4) + (x - 11'd66);

    // Inferred dual-clock memory with a synchronous video read.
    always @(posedge video_clk) begin
        if (in_portrait)
            portrait_data_q <= portrait_ram[portrait_address];
    end

    always @(posedge video_clk or posedge video_rst) begin
        if (video_rst) begin
            x <= 11'd0;
            y <= 10'd0;
            de_q <= 1'b0;
            vs_q <= 1'b0;
            ready_meta <= 1'b0;
            ready_sync <= 1'b0;
            in_portrait_q <= 1'b0;
            selected_border_q <= 1'b0;
        end else begin
            ready_meta <= portrait_ready;
            ready_sync <= ready_meta;
            in_portrait_q <= in_portrait;
            selected_border_q <= selected_border;
            de_q <= de;
            vs_q <= vs;
            if (vs != vs_q) begin
                x <= 11'd0;
                y <= 10'd0;
            end else begin
                if (de) x <= x + 11'd1;
                else x <= 11'd0;
                if (de_q && !de) y <= y + 10'd1;
            end
        end
    end

    assign rgb_out = selected_border_q ? 24'hFFD34E :
                     ((ready_sync && in_portrait_q) ? portrait_data_q : background);
endmodule
