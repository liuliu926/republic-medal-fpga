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
    wire [10:0] card_left = 11'd56 + selected_index[1:0] * 11'd296;
    wire [9:0] card_top = 10'd162 + selected_index[4:2] * 10'd133;
    wire in_card = de && x >= card_left && x < card_left + 11'd278 &&
                         y >= card_top && y < card_top + 10'd115;
    wire selected_border = in_card && ((x < card_left + 11'd3) ||
                           (x >= card_left + 11'd275) ||
                           (y < card_top + 10'd3) || (y >= card_top + 10'd112));
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
