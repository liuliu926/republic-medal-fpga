// TF-loaded home title/name atlas, 768x320 bottom-up monochrome BMP pixels.
// One bit per pixel is cached independently of the SDRAM portrait/background.
module home_text_mask (
    input wire write_clk, write_rst, pixel_start, pixel_valid,
    input wire [23:0] pixel_data,
    input wire video_clk, video_rst, vs, de,
    input wire [23:0] rgb_in,
    output wire [23:0] rgb_out
);
    reg mask_ram [0:245759];
    reg [17:0] write_addr;
    reg ready;
    always @(posedge write_clk or posedge write_rst) begin
        if (write_rst) begin write_addr <= 0; ready <= 0; end
        else if (pixel_start) begin write_addr <= 0; ready <= 0; end
        else if (pixel_valid && !ready) begin
            mask_ram[write_addr] <= pixel_data[23];
            if (write_addr == 18'd245759) ready <= 1;
            else write_addr <= write_addr + 1'b1;
        end
    end
    reg [10:0] x;
    reg [9:0] y;
    reg de_q, vs_q, ready_meta, ready_sync;
    // Two-cycle look-ahead covers coordinate registration and BRAM latency.
    wire [10:0] next_x = x + 2'd2;
    reg [9:0] atlas_x;
    reg [8:0] atlas_y;
    reg inside;
    reg [10:0] local_x;
    reg [9:0] local_y;
    reg [1:0] col, row;
    always @* begin
        inside=0; atlas_x=0; atlas_y=0; local_x=0; local_y=0; col=0; row=0;
        if (de && y >= 10'd18 && y < 10'd82 && next_x >= 11'd320 && next_x < 11'd832) begin
            inside=1; atlas_x=next_x-11'd320; atlas_y=9'd256 + (y-10'd18);
        end else begin
            if (next_x >= 11'd151 && next_x < 11'd343) begin col=0; local_x=next_x-11'd151; end
            else if (next_x >= 11'd447 && next_x < 11'd639) begin col=1; local_x=next_x-11'd447; end
            else if (next_x >= 11'd743 && next_x < 11'd935) begin col=2; local_x=next_x-11'd743; end
            else if (next_x >= 11'd1039 && next_x < 11'd1231) begin col=3; local_x=next_x-11'd1039; end
            else col=0;
            if (y >= 10'd180 && y < 10'd244) begin row=0; local_y=y-10'd180; end
            else if (y >= 10'd313 && y < 10'd377) begin row=1; local_y=y-10'd313; end
            else if (y >= 10'd446 && y < 10'd510) begin row=2; local_y=y-10'd446; end
            else if (y >= 10'd579 && y < 10'd643) begin row=3; local_y=y-10'd579; end
            else row=0;
            if (de && ((next_x >= 151 && next_x < 343) ||
                       (next_x >= 447 && next_x < 639) ||
                       (next_x >= 743 && next_x < 935) ||
                       (next_x >= 1039 && next_x < 1231)) &&
                      ((y >= 180 && y < 244) || (y >= 313 && y < 377) ||
                       (y >= 446 && y < 510) || (y >= 579 && y < 643))) begin
                inside=1;
                atlas_x = local_x + col * 10'd192;
                atlas_y = local_y + row * 9'd64;
            end
        end
    end
    reg [9:0] atlas_x_r;
    reg [8:0] atlas_y_r;
    reg inside_r;
    wire [8:0] bottom_row = 9'd319 - atlas_y_r;
    wire [17:0] addr = ({9'd0,bottom_row} << 9) + ({9'd0,bottom_row} << 8) + atlas_x_r;
    reg mask_q, inside_q;
    always @(posedge video_clk) begin
        inside_r <= inside;
        atlas_x_r <= atlas_x;
        atlas_y_r <= atlas_y;
        if (inside_r) mask_q <= mask_ram[addr];
        inside_q <= inside_r;
    end
    always @(posedge video_clk or posedge video_rst) begin
        if (video_rst) begin x<=0; y<=0; de_q<=0; vs_q<=0; ready_meta<=0; ready_sync<=0; end
        else begin
            ready_meta<=ready; ready_sync<=ready_meta; de_q<=de; vs_q<=vs;
            if (vs != vs_q) begin x<=0; y<=0; end
            else begin
                if (de) x<=x+1'b1; else x<=0;
                if (de_q && !de) y<=y+1'b1;
            end
        end
    end
    assign rgb_out = (ready_sync && inside_q && mask_q) ? 24'hFFF1CD : rgb_in;
endmodule
