// Free-running 720p AXI video source for the Anlogic HDMI transmitter.
// The vendor's example advances with pixel_clk, including blanking. In this
// configuration O_axis_s_ready is not a usable pixel-clock enable: gating the
// counters on ready held x at zero and displayed solid red.
module video_pattern_720p (
    input  wire        clk,
    input  wire        rst,
    input  wire        ready,  // Kept for the top-level interface; not a clock enable.
    output reg         user,
    output reg         valid,
    output reg         last,
    output reg  [23:0] data
);

localparam [10:0] H_TOTAL = 11'd1650;
localparam [9:0]  V_TOTAL = 10'd750;
localparam [10:0] H_BLANK = 11'd370;
localparam [9:0]  V_BLANK = 10'd30;

reg [10:0] h_count;
reg [9:0]  v_count;
wire active = (h_count >= H_BLANK) && (v_count >= V_BLANK);
wire [10:0] active_x = h_count - H_BLANK;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        h_count <= 11'd0;
        v_count <= 10'd0;
        user <= 1'b0;
        valid <= 1'b0;
        last <= 1'b0;
        data <= 24'd0;
    end else begin
        if (h_count == H_TOTAL - 11'd1) begin
            h_count <= 11'd0;
            v_count <= (v_count == V_TOTAL - 10'd1) ? 10'd0 : v_count + 10'd1;
        end else begin
            h_count <= h_count + 11'd1;
        end

        valid <= active;
        user <= active && (h_count == H_BLANK) && (v_count == V_BLANK);
        last <= active && (h_count == H_TOTAL - 11'd1);

        if (!active)
            data <= 24'd0;
        else if (active_x < 11'd160)
            data <= 24'hFF0000;
        else if (active_x < 11'd320)
            data <= 24'h00FF00;
        else if (active_x < 11'd480)
            data <= 24'h0000FF;
        else if (active_x < 11'd640)
            data <= 24'h00FFFF;
        else if (active_x < 11'd800)
            data <= 24'hFF00FF;
        else if (active_x < 11'd960)
            data <= 24'hFFFF00;
        else if (active_x < 11'd1120)
            data <= 24'hFFFFFF;
        else
            data <= 24'h000000;
    end
end

wire unused_ready = ready;

endmodule
