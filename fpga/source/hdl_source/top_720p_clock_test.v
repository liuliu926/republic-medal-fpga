// Standalone HDMI timing bring-up top for the isolated experimental project.
// The isolated video_pll is based on the vendor EG4S20 HDMI example and uses
// 75 MHz pixel / 375 MHz 5x serial clocks (720p timing, ~60.6 Hz refresh).
module top_720p_clock_test (
    input  wire       clk,
    input  wire       key1,
    input  wire       key2,
    input  wire       key3,
    input  wire       key4,
    input  wire       sw3,
    output wire [5:0] seg_sel,
    output wire [7:0] seg_data,
    output wire       HDMI_CLK_P,
    output wire       HDMI_D2_P,
    output wire       HDMI_D1_P,
    output wire       HDMI_D0_P,
    output wire       HDMI_DDC_SCL,
    inout  wire       HDMI_DDC_SDA,
    output wire       sd_ncs,
    output wire       sd_dclk,
    output wire       sd_mosi,
    input  wire       sd_miso
);

    wire pixel_clk;
    wire serial_clk;
    wire pll_lock;
    reg [1:0] pll_lock_sync = 2'b00;
    reg [19:0] power_count = 20'd0;
    reg [19:0] lock_count = 20'd0;
    reg power_done = 1'b0;
    reg reset_all = 1'b1;
    reg [1:0] pixel_reset_sync = 2'b11;
    reg [1:0] serial_reset_sync = 2'b11;
    reg [1:0] serial_neg_reset_sync = 2'b11;
    wire pixel_reset = pixel_reset_sync[1];
    wire serial_reset = serial_reset_sync[1];
    wire serial_neg_reset = serial_neg_reset_sync[1];

    wire axis_user;
    wire axis_valid;
    wire axis_last;
    wire [23:0] axis_data;
    wire axis_ready;
    wire edid_trigger;
    wire edid_valid;
    wire [7:0] edid_data;
    wire [9:0] tmds_ch0;
    wire [9:0] tmds_ch1;
    wire [9:0] tmds_ch2;
    wire [9:0] tmds_clk;

    // Existing board reference clock is 50 MHz. Hold reset until the PLL is
    // locked and has remained locked for 20 ms.
    always @(posedge clk) begin
        pll_lock_sync <= {pll_lock_sync[0], pll_lock};
        if (!power_done) begin
            if (power_count == 20'd999_999)
                power_done <= 1'b1;
            else
                power_count <= power_count + 1'b1;
        end

        if (!power_done || !pll_lock_sync[1]) begin
            lock_count <= 20'd0;
            reset_all <= 1'b1;
        end else if (lock_count < 20'd1_000_000) begin
            lock_count <= lock_count + 1'b1;
            reset_all <= 1'b1;
        end else begin
            reset_all <= 1'b0;
        end
    end

    video_pll video_pll_m0 (
        .refclk(clk),
        .reset(1'b0),
        .extlock(pll_lock),
        .clk0_out(pixel_clk),
        .clk1_out(serial_clk)
    );

    // reset_all is generated in the 50 MHz control domain. Assert each local
    // reset asynchronously, then release it synchronously in its own clock
    // domain so HDMI pixel/serial logic never sees an unsafe reset release.
    always @(posedge pixel_clk or posedge reset_all) begin
        if (reset_all)
            pixel_reset_sync <= 2'b11;
        else
            pixel_reset_sync <= {pixel_reset_sync[0], 1'b0};
    end

    always @(posedge serial_clk or posedge reset_all) begin
        if (reset_all)
            serial_reset_sync <= 2'b11;
        else
            serial_reset_sync <= {serial_reset_sync[0], 1'b0};
    end

    // The first toggle sampler uses the falling serial edge, so release its
    // reset on that edge as well and retain a full-cycle recovery budget.
    always @(negedge serial_clk or posedge reset_all) begin
        if (reset_all)
            serial_neg_reset_sync <= 2'b11;
        else
            serial_neg_reset_sync <= {serial_neg_reset_sync[0], 1'b0};
    end

    video_pattern_720p u_video_pattern_720p (
        .clk(pixel_clk),
        .rst(pixel_reset),
        .ready(axis_ready),
        .user(axis_user),
        .valid(axis_valid),
        .last(axis_last),
        .data(axis_data)
    );

    startup_pulse #(.CNT_MAX(20'd100_000)) u_edid_startup (
        .I_clk(pixel_clk),
        .I_rst(pixel_reset),
        .O_pulse(edid_trigger)
    );

    hdmi_1_4b_transmitter_core_wrapper #(
        .DEVICE("EG"),
        .HTOTAL(1650), .HSA(40), .HFP(110), .HBP(220), .HACTIVE(1280),
        .VTOTAL(750), .VSA(5), .VFP(5), .VBP(20), .VACTIVE(720),
        .VIDEO_VIC(4), .VIDEO_TPG("Disable"), .VIDEO_FORMAT("RGB"),
        .AUDIO_SAMPLE_RATE("48K"), .IIC_SCL_DIV(250)
    ) u_hdmi_tx (
        .I_pixel_clk(pixel_clk),
        .I_rst(pixel_reset),
        .I_edid_read_trig(edid_trigger),
        .O_edid_read_valid(edid_valid),
        .O_edid_read_data(edid_data),
        .I_axis_s_user(axis_user),
        .I_axis_s_valid(axis_valid),
        .I_axis_s_last(axis_last),
        .I_axis_s_data(axis_data),
        .O_axis_s_ready(axis_ready),
        .I_audio_valid(1'b0),
        .I_audio_left_data(24'd0),
        .I_audio_right_data(24'd0),
        .I_acr_valid(1'b0),
        .I_acr_cts(20'd0),
        .I_acr_n(20'd0),
        .O_video_locked(),
        .O_ddc_scl(HDMI_DDC_SCL),
        .IO_ddc_sda(HDMI_DDC_SDA),
        .O_ch0_tmds_data(tmds_ch0),
        .O_ch1_tmds_data(tmds_ch1),
        .O_ch2_tmds_data(tmds_ch2),
        .O_clk_tmds_data(tmds_clk)
    );

    hdmi_phy_wrapper #(.DEVICE("EG")) u_hdmi_phy (
        .I_pixel_clk(pixel_clk),
        .I_serial_clk(serial_clk),
        .I_pixel_rst(pixel_reset),
        .I_serial_neg_rst(serial_neg_reset),
        .I_rst(serial_reset),
        .I_tmds_channel_0(tmds_ch0),
        .I_tmds_channel_1(tmds_ch1),
        .I_tmds_channel_2(tmds_ch2),
        .I_tmds_channel_clk(tmds_clk),
        .O_tmds_ch0_p(HDMI_D0_P),
        .O_tmds_ch1_p(HDMI_D1_P),
        .O_tmds_ch2_p(HDMI_D2_P),
        .O_tmds_clk_p(HDMI_CLK_P)
    );

    // Keep unused board-facing pins defined while this test top is selected.
    assign seg_sel = 6'b111111;
    assign seg_data = 8'hff;
    assign sd_ncs = 1'b1;
    assign sd_dclk = 1'b0;
    assign sd_mosi = 1'b0;

    // Explicitly consume unused physical inputs in this test-only top.
    wire unused_inputs = key1 ^ key2 ^ key3 ^ key4 ^ sw3 ^ sd_miso;

endmodule
