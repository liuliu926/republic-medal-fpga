
module top(
    input                       clk,
    input                       key1,           // 下一项
    input                       key2,           // 上一项
    input                       key3,           // 返回
    input                       key4,           // 确定
    input                       sw3,            // 自动轮播拨码

	output [5:0]                seg_sel,
	output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso
);

// Temporary verification build: display the scanned TF image over the whole
// HDMI frame and let physical KEY1 cycle through the discovered BMP files.
// The medal UI remains in the project and the last verified bitstream is kept.
// 720p bring-up stage: show TF images full-screen while HDMI timing and the
// resized BMP path are validated. The kiosk OSD is re-enabled after this test.
parameter IMAGE_SCAN_TEST = 1'b1;
// Stage-one PPT proof: after the six already-tested BMPs, load BG001.BMP
// (copied seventh to the TF card) as the initial full-screen background.
parameter PPT_BG_TEST = 1'b1;
parameter PPT_PORTRAIT_TEST = 1'b1;

parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter FRAME_PIXELS  = 24'd921600;   // 1280*720
parameter BUF0_ADDR     = 24'd0;
parameter BUF1_ADDR     = FRAME_PIXELS;

wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;

wire [23:0] vout_data_raw;
wire [23:0] vout_data;
wire [23:0] osd_rgb;
wire [3:0]  key_pulse;
wire [1:0]  nav_level;
wire [4:0]  nav_person;
wire [2:0]  nav_section;
wire [7:0]  nav_page;
wire        nav_quiz_option;
wire        nav_quiz_revealed;
wire        auto_mode;
wire        exit_to_home_pulse;
wire        prompt_visible;
wire [1:0]  auto_level;
wire [4:0]  auto_person;
wire [2:0]  auto_section;
wire [7:0]  auto_page;
wire [1:0]  display_level = auto_mode ? auto_level : nav_level;
wire [4:0]  display_person = auto_mode ? auto_person : nav_person;
wire [2:0]  display_section = auto_mode ? auto_section : nav_section;
wire [7:0]  display_page = auto_mode ? auto_page : nav_page;
wire        display_quiz_option = auto_mode ? 1'b0 : nav_quiz_option;
wire        display_quiz_revealed = auto_mode ? 1'b0 : nav_quiz_revealed;
reg  [1:0]  nav_level_sync1, nav_level_sync2;
reg  [4:0]  nav_person_sync1, nav_person_sync2;
reg  [2:0]  nav_section_sync1, nav_section_sync2;
reg  [7:0]  nav_page_sync1, nav_page_sync2;
reg         nav_quiz_option_sync1, nav_quiz_option_sync2;
reg         nav_quiz_revealed_sync1, nav_quiz_revealed_sync2;
reg         auto_mode_sync1, auto_mode_sync2;
reg         prompt_sync1, prompt_sync2;
wire        display_valid;
wire        selected_image_valid;
reg         display_valid_sync1, display_valid_sync2;
reg         selected_image_valid_sync1, selected_image_valid_sync2;

wire [3:0]  state_code;
wire [3:0]  debug_found_count;
wire [3:0]  debug_display_index;
wire [3:0]  debug_requested_index;
wire        debug_load_busy;
wire        portrait_load_mode;
wire [3:0]  portrait_image_index;
// 100 rows, each padded to 256 words, per portrait.
wire [20:0] portrait_first_offset = portrait_image_index * 21'd25600;
wire        portrait_pixel_valid;
wire [23:0] portrait_pixel_data;
wire        portrait_pixel_start;
wire [23:0] portrait_composited_rgb;
wire [23:0] home_text_rgb, home_text_pixel;
wire home_text_start, home_text_valid;
reg [4:0] home_selected;
reg [4:0] home_selected_meta, home_selected_video;

wire [1:0]  debug_load_progress;
wire [6:0]  seg_data_0;
wire [6:0]  seg_data_1;
wire [6:0]  seg_data_2;
wire [6:0]  seg_data_3;
wire [6:0]  seg_data_4;
wire [6:0]  seg_data_5;

wire        video_read_req;
wire        video_read_req_ack;
reg         video_read_req_ack_meta;
reg         video_read_req_ack_sync;
wire diag_fifo_empty_seen, diag_fifo_full_seen;
wire        video_read_en;
wire [31:0] video_read_data;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
reg         sd_card_write_req_ack_meta;
reg         sd_card_write_req_ack_sync;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

// HDMI 1.4b 相关
wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

// 统一复位：TF 图像链路 + HDMI 链路
wire sys_pll_lock;
wire video_pll_lock;
wire rst_all;
reg [1:0] pixel_reset_sync = 2'b11;
reg [1:0] serial_reset_sync = 2'b11;
reg [1:0] serial_neg_reset_sync = 2'b11;
wire rst_video = pixel_reset_sync[1];
wire rst_serial = serial_reset_sync[1];
wire rst_serial_neg = serial_neg_reset_sync[1];
// This pilot only enables the home selector; page navigation is added later.
always @(posedge clk or posedge rst_all) begin
    if (rst_all) home_selected <= 5'd0;
    else if (key_pulse[0]) home_selected <= (home_selected == 5'd12) ? 5'd0 : home_selected + 5'd1;
    else if (key_pulse[1]) home_selected <= (home_selected == 5'd0) ? 5'd12 : home_selected - 5'd1;
end
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin home_selected_meta <= 5'd0; home_selected_video <= 5'd0; end
    else begin home_selected_meta <= home_selected; home_selected_video <= home_selected_meta; end
end

reg [19:0] powerup_count = 20'd0;
reg        powerup_done = 1'b0;
wire       rst_n = powerup_done;

reg [19:0] rst_cnt = 20'd0;
reg rst_all_reg = 1'b1;

// KEY1 is now a navigation key. Generate the initial reset on power-up.
always @(posedge clk) begin
    if (!powerup_done) begin
        if (powerup_count == 20'd999_999)
            powerup_done <= 1'b1;
        else
            powerup_count <= powerup_count + 20'd1;
    end
end

always @(posedge clk) begin
    if (!rst_n) begin
        rst_cnt <= 20'd0;
        rst_all_reg <= 1'b1;
    end else if (!rst_all_reg) begin
        // 一旦复位释放，忽略后续微小的 PLL 抖动，防止系统在使用时随机复位
        rst_all_reg <= 1'b0;
    end else if (sys_pll_lock && video_pll_lock) begin
        // 等待 PLL 连续稳定 20ms @ 50MHz
        if (rst_cnt < 20'd1_000_000) begin
            rst_cnt <= rst_cnt + 1'b1;
            rst_all_reg <= 1'b1;
        end else begin
            rst_all_reg <= 1'b0;
        end
    end else begin
        rst_cnt <= 20'd0;
        rst_all_reg <= 1'b1;
    end
end

assign rst_all = rst_all_reg;

// The HDMI pixel and 5x serial clocks have different reset recovery edges.
// Assert together, then release on the local edge of each clock domain.
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all)
        pixel_reset_sync <= 2'b11;
    else
        pixel_reset_sync <= {pixel_reset_sync[0], 1'b0};
end
always @(posedge hdmi_5x_clk or posedge rst_all) begin
    if (rst_all)
        serial_reset_sync <= 2'b11;
    else
        serial_reset_sync <= {serial_reset_sync[0], 1'b0};
end
always @(negedge hdmi_5x_clk or posedge rst_all) begin
    if (rst_all)
        serial_neg_reset_sync <= 2'b11;
    else
        serial_neg_reset_sync <= {serial_neg_reset_sync[0], 1'b0};
end

key_remove_shakes u_key1 (.I_clk(clk), .I_rst_n(~rst_all), .I_key_in(key1), .O_key_trig_out(key_pulse[0]));
key_remove_shakes u_key2 (.I_clk(clk), .I_rst_n(~rst_all), .I_key_in(key2), .O_key_trig_out(key_pulse[1]));
key_remove_shakes u_key3 (.I_clk(clk), .I_rst_n(~rst_all), .I_key_in(key3), .O_key_trig_out(key_pulse[2]));
key_remove_shakes u_key4 (.I_clk(clk), .I_rst_n(~rst_all), .I_key_in(key4), .O_key_trig_out(key_pulse[3]));

kiosk_mode u_kiosk_mode (
    .clk(clk), .rst(rst_all), .sw3_raw(sw3),
    .key_any_pulse(|key_pulse),
    .auto_mode(auto_mode), .exit_to_home_pulse(exit_to_home_pulse),
    .prompt_visible(prompt_visible)
);

kiosk_autoplay u_kiosk_autoplay (
    .clk(clk), .rst(rst_all), .auto_mode(auto_mode), .pause(prompt_visible),
    .level(auto_level), .person_index(auto_person),
    .section_index(auto_section), .page_index(auto_page)
);

kiosk_nav u_kiosk_nav (
    .clk(clk), .rst(rst_all), .auto_mode(auto_mode), .exit_to_home_pulse(exit_to_home_pulse),
    .key_next_pulse(key_pulse[0]), .key_prev_pulse(key_pulse[1]),
    .key_back_pulse(key_pulse[2]), .key_enter_pulse(key_pulse[3]),
    .page_count((nav_person == 5'd0 && nav_section < 3'd3) ? 8'd2 : 8'd1),
    .level(nav_level), .person_index(nav_person),
    .section_index(nav_section), .page_index(nav_page),
    .quiz_option(nav_quiz_option), .quiz_revealed(nav_quiz_revealed)
);

always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        nav_level_sync1 <= 2'd0; nav_level_sync2 <= 2'd0;
        nav_person_sync1 <= 5'd0; nav_person_sync2 <= 5'd0;
        nav_section_sync1 <= 3'd0; nav_section_sync2 <= 3'd0;
        nav_page_sync1 <= 8'd0; nav_page_sync2 <= 8'd0;
        nav_quiz_option_sync1 <= 1'b0; nav_quiz_option_sync2 <= 1'b0;
        nav_quiz_revealed_sync1 <= 1'b0; nav_quiz_revealed_sync2 <= 1'b0;
        auto_mode_sync1 <= 1'b0; auto_mode_sync2 <= 1'b0;
        prompt_sync1 <= 1'b0; prompt_sync2 <= 1'b0;
        display_valid_sync1 <= 1'b0; display_valid_sync2 <= 1'b0;
        selected_image_valid_sync1 <= 1'b0; selected_image_valid_sync2 <= 1'b0;
    end else begin
        nav_level_sync1 <= display_level; nav_level_sync2 <= nav_level_sync1;
        nav_person_sync1 <= display_person; nav_person_sync2 <= nav_person_sync1;
        nav_section_sync1 <= display_section; nav_section_sync2 <= nav_section_sync1;
        nav_page_sync1 <= display_page; nav_page_sync2 <= nav_page_sync1;
        nav_quiz_option_sync1 <= display_quiz_option; nav_quiz_option_sync2 <= nav_quiz_option_sync1;
        nav_quiz_revealed_sync1 <= display_quiz_revealed; nav_quiz_revealed_sync2 <= nav_quiz_revealed_sync1;
        auto_mode_sync1 <= auto_mode; auto_mode_sync2 <= auto_mode_sync1;
        prompt_sync1 <= prompt_visible; prompt_sync2 <= prompt_sync1;
        display_valid_sync1 <= display_valid; display_valid_sync2 <= display_valid_sync1;
        selected_image_valid_sync1 <= selected_image_valid;
        selected_image_valid_sync2 <= selected_image_valid_sync1;
    end
end

// 保持你原来的 TF / SDRAM / video 时钟
sys_pll sys_pll_m0(
    .refclk     (clk),
    .reset      (1'b0),
    .extlock    (sys_pll_lock),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft)
);

video_pll video_pll_m0(
    .refclk     (clk),
    .reset      (1'b0),
    .extlock    (video_pll_lock),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk)
);

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or posedge rst_all) begin
    if (rst_all)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// The memory writer holds its request acknowledgement until the TF reader
// drops write_req. Synchronize that level before the 100 MHz reader FSM uses it.
always @(posedge sd_card_clk or posedge rst_all) begin
    if (rst_all) begin
        sd_card_write_req_ack_meta <= 1'b0;
        sd_card_write_req_ack_sync <= 1'b0;
    end else begin
        sd_card_write_req_ack_meta <= sd_card_write_req_ack;
        sd_card_write_req_ack_sync <= sd_card_write_req_ack_meta;
    end
end

always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        video_read_req_ack_meta <= 1'b0;
        video_read_req_ack_sync <= 1'b0;
    end else begin
        video_read_req_ack_meta <= video_read_req_ack;
        video_read_req_ack_sync <= video_read_req_ack_meta;
    end
end

// ===================== TF 多图扫描与缓存（双缓冲） =====================
sd_card_bmp #(
    .CLK_FREQ_HZ       (100_000_000),
    .SCAN_START_SECTOR (32'd0),
    .SCAN_MAX_SECTOR   (32'd131071),
    .SCAN_TARGET_COUNT (5'd21),
    .INITIAL_INDEX     (PPT_BG_TEST ? 4'd6 : 4'd0),
    .PPT_PORTRAIT_TEST (PPT_PORTRAIT_TEST),
    .IMAGE_LEFT       (IMAGE_SCAN_TEST ? 0 : 40),
    .IMAGE_TOP        (IMAGE_SCAN_TEST ? 0 : 150),
    .OUTPUT_WIDTH     (1280),
    .OUTPUT_HEIGHT    (720),
    .IMAGE_WIDTH      (IMAGE_SCAN_TEST ? 1280 : 420),
    .IMAGE_HEIGHT     (IMAGE_SCAN_TEST ? 720 : 420)
) sd_card_bmp_m0(
    .clk               (sd_card_clk),
    .rst               (rst_all),
    .key_next          (1'b1),
    .key_auto          (1'b1),
    .select_mode       (!IMAGE_SCAN_TEST),
    // Temporary image mapping for the Yu Min pilot: article page 0/1 uses
    // the two different-size BMPs added after the original four card images.
    .selected_index    (display_page[0] ? 3'd5 : 3'd4),
    .state_code        (state_code),
    .debug_found_count (debug_found_count),
    .debug_display_index(debug_display_index),
    .debug_requested_index(debug_requested_index),
    .debug_load_busy   (debug_load_busy),
    .debug_load_progress(debug_load_progress),
    .bmp_width         (16'd1280),
    .bmp_height        (16'd720),
    .display_valid     (display_valid),
    .selected_image_valid(selected_image_valid),
    .portrait_load_mode(portrait_load_mode),
    .portrait_image_index(portrait_image_index),
    .text_pixel_start(home_text_start), .text_pixel_valid(home_text_valid),
    .text_pixel_data(home_text_pixel),

    .write_finish_toggle(frame_write_toggle_mem),
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx),

    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack_sync),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .SD_nCS            (sd_ncs),
    .SD_DCLK           (sd_dclk),
    .SD_MOSI           (sd_mosi),
    .SD_MISO           (sd_miso)
);

// Diagnostic digits, left to right: found, displayed, requested, busy,
// source/write done bits, SD reader state. Useful when a page changes text
// but a TF image fails to commit to the alternate frame buffer.
seg_decoder seg_decoder_m0(.bin_data(state_code), .seg_data(seg_data_0));
seg_decoder seg_decoder_m1(.bin_data({2'b00, diag_fifo_full_seen, diag_fifo_empty_seen}), .seg_data(seg_data_1));
seg_decoder seg_decoder_m2(.bin_data({3'b000, debug_load_busy}), .seg_data(seg_data_2));
seg_decoder seg_decoder_m3(.bin_data(debug_requested_index), .seg_data(seg_data_3));
seg_decoder seg_decoder_m4(.bin_data(debug_display_index), .seg_data(seg_data_4));
seg_decoder seg_decoder_m5(.bin_data(debug_found_count), .seg_data(seg_data_5));

seg_scan seg_scan_m0(
    .clk               (clk),
    .rst_n             (rst_n),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .seg_data_0        ({1'b1,seg_data_0}),
    .seg_data_1        ({1'b1,seg_data_1}),
    .seg_data_2        ({1'b1,seg_data_2}),
    .seg_data_3        ({1'b1,seg_data_3}),
    .seg_data_4        ({1'b1,seg_data_4}),
    .seg_data_5        ({1'b1,seg_data_5})
);

// ===================== 原图像时序与帧缓存 =====================
video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (rst_video),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack_sync),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

video_delay video_delay_m0(
    .video_clk         (video_clk),
    .rst               (rst_video),
    .read_en           (video_read_en),
    .read_data         (video_read_data[31:8]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (vout_data_raw)
);

// 首图提交前黑屏；提交后一直显示当前显示缓冲区内容
// A newly selected page keeps its image area blank until its own BMP has
// finished loading. This prevents an unrelated cached image from flashing.
assign vout_data = (IMAGE_SCAN_TEST ? display_valid_sync2 : selected_image_valid_sync2)
    ? vout_data_raw : 24'd0;

// Independently loaded TF portrait is cached in on-chip RAM.  The background
// stays in SDRAM and is combined at the video output, avoiding discontinuous
// rectangle writes to SDRAM during scanout.
portrait_bram_overlay portrait_bram_overlay_m0 (
    .write_clk(sd_card_clk), .write_rst(rst_all),
    .pixel_start(1'b0), .pixel_valid(1'b0),
    .pixel_data(24'd0),
    .video_clk(video_clk), .video_rst(rst_video), .vs(vs), .de(de),
    .selected_index(home_selected_video),
    .background(vout_data), .rgb_out(portrait_composited_rgb)
);

home_text_mask u_home_text (
    .write_clk(sd_card_clk), .write_rst(rst_all),
    .pixel_start(home_text_start), .pixel_valid(home_text_valid), .pixel_data(home_text_pixel),
    .video_clk(video_clk), .video_rst(rst_video), .vs(vs), .de(de),
    .rgb_in(portrait_composited_rgb), .rgb_out(home_text_rgb)
);

// First milestone UI is generated directly in FPGA video logic.
medal_ui_osd u_medal_ui_osd (
    .clk        (video_clk),
    .rst        (rst_video),
    .vs         (vs),
    .de         (de),
    .level      (nav_level_sync2),
    .person_index(nav_person_sync2),
    .section_index(nav_section_sync2),
    .page_index (nav_page_sync2),
    .quiz_option(nav_quiz_option_sync2),
    .quiz_revealed(nav_quiz_revealed_sync2),
    .auto_mode  (auto_mode_sync2),
    .prompt_visible(prompt_sync2),
    .rgb_in     (vout_data),
    .rgb_out    (osd_rgb)
);

frame_read_write #(
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (1280),
    .FRAME_HEIGHT     (720)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (video_read_req && display_valid_sync2),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (24'd0),
    .read_addr_3       (24'd0),
    .read_addr_index   (disp_buf_idx),
    .read_len          (FRAME_PIXELS),
    .read_en           (video_read_en),
    .read_data         (video_read_data),
    .diag_fifo_empty_seen (diag_fifo_empty_seen),
    .diag_fifo_full_seen (diag_fifo_full_seen),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (24'd0),
    .write_addr_3      (24'd0),
    .write_addr_index  (write_buf_idx),
    .write_len         (portrait_load_mode ? 21'd8000 : FRAME_PIXELS),
    .write_first_offset(portrait_load_mode ? portrait_first_offset : 21'd920320),
    .write_line_width  (portrait_load_mode ? 16'd80 : 16'd1280),
    .write_line_jump   (portrait_load_mode ? 21'd2096975 : 21'd2559),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

// ===================== RGB/DE 转 AXIS 视频 =====================
video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_video),
    .I_vs          (vs),
    .I_de          (de),
    .I_rgb         (IMAGE_SCAN_TEST ? home_text_rgb : osd_rgb),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// 上电后自动打一拍，触发一次 EDID 读取
startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (rst_video),
    .O_pulse (edid_trig)
);

// ===================== HDMI 1.4b 发射 =====================
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 1650       ),
    .HSA                    ( 40         ),
    .HFP                    ( 110        ),
    .HBP                    ( 220        ),
    .HACTIVE                ( 1280       ),
    .VTOTAL                 ( 750        ),
    .VSA                    ( 5          ),
    .VFP                    ( 5          ),
    .VBP                    ( 20         ),
    .VACTIVE                ( 720        ),
    .VIDEO_VIC              ( 4          ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (rst_video),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (1'b0),
    .I_audio_left_data  (24'd0),
    .I_audio_right_data (24'd0),
    .I_acr_valid        (1'b0),
    .I_acr_cts          (20'd0),
    .I_acr_n            (20'd0),

    .O_video_locked     (),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi_phy(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_pixel_rst        (rst_video),
    .I_serial_neg_rst   (rst_serial_neg),
    .I_rst              (rst_serial),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule
