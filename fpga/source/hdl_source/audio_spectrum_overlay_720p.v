// Eight measured frequency bands, smoothly drawn as16 thinner columns.
// Odd columns interpolate adjacent measured levels, not extra measured bins.
// Transparent128x32 strip remains below all text and circular portraits.
module audio_waveform_overlay_720p (
    input wire clk, rst, de,
    input wire [10:0] pixel_x,
    input wire [9:0] pixel_y,
    input wire audio_valid,
    input wire signed [23:0] audio_sample,
    input wire [23:0] rgb_in,
    output wire [23:0] rgb_out
);
    wire [31:0] spectrum_levels;
    wire spectrum_valid;
    audio_spectrum_analyzer u_spectrum (
        .clk(clk), .rst(rst),
        .audio_valid(audio_valid), .audio_sample(audio_sample),
        .levels(spectrum_levels), .levels_valid(spectrum_valid)
    );
    localparam [10:0] LEFT=11'd1120, RIGHT=11'd1248;
    localparam [9:0] TOP=10'd658, BASELINE=10'd689;
    // Register the8:1 level selection one pixel ahead as in the accepted overlay.
    wire [10:0] lookahead_x=pixel_x+11'd1;
    wire [10:0] offset=lookahead_x-LEFT;
    wire [2:0] read_index=offset[6:4];
    wire [2:0] next_index=read_index==7 ? 3'd7 : read_index+3'd1;
    wire [3:0] level_a=spectrum_levels[{read_index,2'b00} +:4];
    wire [3:0] level_b=spectrum_levels[{next_index,2'b00} +:4];
    wire [4:0] level_sum={1'b0,level_a}+{1'b0,level_b};
    reg [3:0] display_level;
    always @(posedge clk or posedge rst) begin
        if(rst) display_level<=0;
        else display_level<=offset[3] ? level_sum[4:1] : level_a;
    end
    wire [5:0] height=display_level==0 ? 6'd0 :
        {1'b0,display_level,1'b0}+6'd2;
    wire in_area=de && pixel_x>=LEFT && pixel_x<RIGHT &&
        pixel_y>=TOP && pixel_y<=BASELINE;
    wire bar=in_area && display_level!=0 && pixel_x[2:0]>=2 && pixel_x[2:0]<=4 &&
        pixel_y<=BASELINE && pixel_y>=BASELINE-{4'd0,height}+10'd1;
    wire axis=in_area && pixel_y==BASELINE;
    assign rgb_out=bar ? 24'hFFE7AE : axis ? 24'hD99243 : rgb_in;
endmodule
