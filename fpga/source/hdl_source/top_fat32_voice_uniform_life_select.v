
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

// The FAT/BMP decoder misses the 100 MHz setup budget in the routed pilot.
// Clock only the removable-card pipeline from the 50 MHz board reference;
// keep the independently generated 125 MHz SDRAM and 75 MHz video clocks.
wire sd_card_clk = clk;
wire sd_pll_feedback_clk_unused;
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
wire [23:0] loading_overlay_rgb;
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
reg         load_busy_video_meta, load_busy_video_sync;

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
wire [23:0] home_text_rgb, home_text_pixel, home_text_mask_rgb;
wire [23:0] text_layer_rgb;
wire home_text_start, home_text_valid;
wire intro_active, fullportrait_mode;
reg intro_mem_meta, intro_mem_sync, intro_video_meta, intro_video_sync;
always @(posedge ext_mem_clk or posedge rst_all) begin
    if (rst_all) begin intro_mem_meta<=0; intro_mem_sync<=0; end
    else begin intro_mem_meta<=intro_active; intro_mem_sync<=intro_mem_meta; end
end
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin intro_video_meta<=0; intro_video_sync<=0; end
    else begin intro_video_meta<=intro_active; intro_video_sync<=intro_video_meta; end
end
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin load_busy_video_meta<=0; load_busy_video_sync<=0; end
    else begin load_busy_video_meta<=debug_load_busy; load_busy_video_sync<=load_busy_video_meta; end
end
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
// Track all thirteen home selections for the visible gold border.
always @(posedge clk or posedge rst_all) begin
    if (rst_all) home_selected <= 5'd0;
    else home_selected <= nav_person;
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

kiosk_autoplay #(.ARTICLE_CYCLES(600_000_000)) u_kiosk_autoplay (
    .clk(clk), .rst(rst_all), .auto_mode(auto_mode), .pause(prompt_visible || debug_load_busy),
    .level(auto_level), .person_index(auto_person),
    .section_index(auto_section), .page_index(auto_page)
);


kiosk_nav #(.PERSON_COUNT(13)) u_kiosk_nav (
    .clk(clk), .rst(rst_all), .auto_mode(auto_mode), .exit_to_home_pulse(exit_to_home_pulse),
    .key_next_pulse(key_pulse[0]), .key_prev_pulse(key_pulse[1]),
    .key_back_pulse(key_pulse[2]),
    .key_enter_pulse(key_pulse[3] &&
        (nav_level == 0 || nav_level == 1 || (nav_level == 2 && nav_section == 3))),
    .page_count((nav_section == 3'd2) ? 8'd4 :
                (nav_section <= 3'd1) ? 8'd5 :
                (nav_person == 5'd0 && nav_section < 3'd3) ? 8'd2 : 8'd1),
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
    .clk0_out   (sd_pll_feedback_clk_unused),
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

// FAT32 layer scheduler. One SD SPI port services both the frame scaler and
// the direct asset decoder; home portraits live after the two full frames.
wire diag_sd_ready, diag_busy, diag_done, diag_error, diag_recovery;
wire [7:0] diag_error_code;
wire diag_fifo_full;
wire [20:0] diag_write_len, diag_offset, diag_jump;
wire [15:0] diag_width;
wire [1:0] frame_write_idx, asset_write_idx;
wire [20:0] frame_write_len, frame_offset, frame_jump;
wire [15:0] frame_width;
wire frame_req, frame_en;
wire [31:0] frame_data;
wire [20:0] asset_write_len, asset_offset, asset_jump;
wire [15:0] asset_width_wr;
wire asset_req, asset_en;
wire [31:0] asset_data;
wire write_ack_stream, write_finish_stream;
wire asset_header_done, asset_header_valid;
wire [15:0] asset_width, asset_height;
wire asset_pixel_valid;
wire [23:0] asset_pixel_data;
wire asset_pixel_enable, asset_pixel_ready;
wire writer_pixel_enable, writer_pixel_ready;
wire writer_start, writer_done, writer_error;
wire [2:0] writer_error_code;
wire [1:0] writer_target_index, sequence_frame_index;
wire [20:0] writer_target_offset, writer_target_length, writer_target_jump;
wire [15:0] writer_target_width, writer_target_height;
wire writer_pixel_route, mask_pixel_route;
wire mask_start, text_visible, sequence_loading;
wire article_text_mode;
reg [1:0] article_text_mode_video;
wire sequence_start, sequence_asset_mode, sequence_valid;
wire [87:0] sequence_sfn;
wire [1:0] sequence_display_index;
wire [3:0] sequence_error_stage;
wire [3:0] sequence_debug_state, sequence_debug_thumb;
wire [3:0] writer_debug_step;
reg [1:0] nav_level_meta_sd, nav_level_sd;
reg [4:0] nav_person_meta_sd, nav_person_sd;
reg [2:0] nav_section_meta_sd, nav_section_sd;
reg [1:0] text_visible_meta;
always @(posedge sd_card_clk or posedge rst_all) begin
    if (rst_all) begin
        nav_level_meta_sd<=0; nav_level_sd<=0;
        nav_person_meta_sd<=0; nav_person_sd<=0;
        nav_section_meta_sd<=0; nav_section_sd<=0;
    end else begin
        nav_level_meta_sd<=display_level; nav_level_sd<=nav_level_meta_sd;
        nav_person_meta_sd<=display_person; nav_person_sd<=nav_person_meta_sd;
        nav_section_meta_sd<=display_section; nav_section_sd<=nav_section_meta_sd;
    end
end
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        text_visible_meta<=0;
        article_text_mode_video<=0;
    end else begin
        text_visible_meta<={text_visible_meta[0],text_visible};
        article_text_mode_video<={article_text_mode_video[0],article_text_mode};
    end
end

kiosk_fat32_sequence_menu u_sequence (
    .clk(sd_card_clk), .rst(rst_all), .mem_ready(Sdr_init_done),
    .sd_ready(diag_sd_ready), .nav_level(nav_level_sd), .nav_person(nav_person_sd),
    .nav_section(nav_section_sd),
    .shared_busy(diag_busy), .shared_done(diag_done), .shared_error(diag_error),
    .shared_recovery(diag_recovery), .writer_done(writer_done),
    .writer_error(writer_error), .asset_header_done(asset_header_done),
    .asset_header_valid(asset_header_valid), .asset_width(asset_width),
    .asset_height(asset_height), .shared_start(sequence_start),
    .asset_mode(sequence_asset_mode), .target_sfn(sequence_sfn),
    .frame_index(sequence_frame_index), .writer_start(writer_start),
    .writer_frame_index(writer_target_index),
    .writer_first_offset(writer_target_offset),
    .writer_width(writer_target_width), .writer_height(writer_target_height),
    .writer_length(writer_target_length), .writer_line_jump(writer_target_jump),
    .writer_pixel_route(writer_pixel_route), .mask_pixel_route(mask_pixel_route),
    .mask_start(mask_start), .display_frame_index(sequence_display_index),
    .display_valid(sequence_valid), .text_visible(text_visible),
    .article_text_mode(article_text_mode),
    .loading(sequence_loading), .error_stage(sequence_error_stage),
    .debug_state(sequence_debug_state), .debug_thumb_index(sequence_debug_thumb)
);

// A page change drops the request for one SD clock, resetting the audio FIFO
// and allowing an in-flight previous clip to drain before a fresh start.
reg [7:0] voice_page_q;
reg voice_page_holdoff;
always @(posedge sd_card_clk or posedge rst_all) begin
    if (rst_all) begin voice_page_q <= 0; voice_page_holdoff <= 0; end
    else begin
        voice_page_holdoff <= (voice_page_q != display_page);
        voice_page_q <= display_page;
    end
end
wire voice_requested = article_text_mode && display_level == 2 &&
    display_person <= 12 && display_section == 0 &&
    display_page >= 1 && display_page <= 4 &&
    // The page source can change just after this clock edge.  Without the
    // equality guard, requested rises for one cycle before holdoff catches
    // up, starts a read, drops, then starts a second read of the same clip.
    (voice_page_q == display_page) && !voice_page_holdoff;
// A uniform 8.3 name replaces a wide 52-way filename multiplexer.
// P01L01.PCM is Yu Min's first life row, P13L04.PCM the last person's fourth.
wire [4:0] voice_person_number = display_person + 5'd1;
wire [7:0] voice_tens_ascii = voice_person_number >= 5'd10 ? 8'h31 : 8'h30;
wire [7:0] voice_ones_ascii = 8'h30 +
    (voice_person_number >= 5'd10 ? voice_person_number - 5'd10 : voice_person_number);
wire [7:0] voice_row_ascii = 8'h30 + display_page[3:0];
wire [87:0] voice_sfn = {"P", voice_tens_ascii, voice_ones_ascii,
                         "L0", voice_row_ascii, "  PCM"};
wire voice_start, voice_ready, voice_valid, voice_active, voice_done, voice_error;
// Diagnostic counters persist until reset.  They distinguish a duplicate
// playback request from duplicate PCM data inside a single file read.
reg [3:0] voice_start_count, voice_active_count, voice_fall_count, voice_done_count;
reg voice_active_q, voice_requested_q;
always @(posedge sd_card_clk or posedge rst_all) begin
    if (rst_all) begin
        voice_start_count <= 0;
        voice_active_count <= 0;
        voice_fall_count <= 0;
        voice_done_count <= 0;
        voice_active_q <= 0;
        voice_requested_q <= 0;
    end else begin
        voice_active_q <= voice_active;
        voice_requested_q <= voice_requested;
        if (voice_start && voice_start_count != 4'hf)
            voice_start_count <= voice_start_count + 1'b1;
        if (voice_active && !voice_active_q && voice_active_count != 4'hf)
            voice_active_count <= voice_active_count + 1'b1;
        if (!voice_requested && voice_requested_q && voice_fall_count != 4'hf)
            voice_fall_count <= voice_fall_count + 1'b1;
        if (voice_done && voice_done_count != 4'hf)
            voice_done_count <= voice_done_count + 1'b1;
    end
end
wire [7:0] voice_byte;
wire voice_audio_valid, voice_underrun;
wire signed [23:0] voice_audio_data;
wire [31:0] voice_samples;
reg [10:0] silent_audio_divider;
reg silent_audio_half;
reg [1:0] voice_requested_video;
wire silent_audio_tick = silent_audio_divider ==
    (silent_audio_half ? 11'd1562 : 11'd1561);
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        silent_audio_divider <= 11'd0;
        silent_audio_half <= 1'b0;
        voice_requested_video <= 2'b00;
    end else begin
        voice_requested_video <= {voice_requested_video[0], voice_requested};
        if (silent_audio_tick) begin
            silent_audio_divider <= 11'd0;
            silent_audio_half <= !silent_audio_half;
        end else silent_audio_divider <= silent_audio_divider + 1'b1;
    end
end
wire hdmi_audio_valid = voice_requested_video[1] ?
    voice_audio_valid : silent_audio_tick;
wire signed [23:0] hdmi_audio_data = voice_requested_video[1] ?
    voice_audio_data : 24'sd0;
pcm_audio_bridge u_voice (
    .sd_clk(sd_card_clk), .pixel_clk(video_clk), .rst(rst_all), .pixel_rst(rst_video),
    .requested(voice_requested), .start_allowed(!diag_busy && !sequence_start),
    .raw_valid(voice_valid), .raw_ready(voice_ready), .raw_data(voice_byte),
    .raw_active(voice_active), .raw_done(voice_done), .raw_error(voice_error),
    .raw_start(voice_start), .audio_valid(voice_audio_valid), .audio_data(voice_audio_data),
    .samples_played(voice_samples), .underrun(voice_underrun));
fat32_shared_boot_frontend_2line_candidate u_fat32_shared (
    .clk(sd_card_clk), .mem_clk(ext_mem_clk), .rst(rst_all),
    .pcm_start(voice_start), .pcm_target_sfn(voice_sfn), .pcm_ready(voice_ready), .pcm_valid(voice_valid),
    .pcm_data(voice_byte), .pcm_active(voice_active), .pcm_done(voice_done), .pcm_error(voice_error),
    .start(sequence_start), .asset_mode(sequence_asset_mode),
    .target_sfn(sequence_sfn), .frame_index(sequence_frame_index),
    .SD_nCS(sd_ncs), .SD_DCLK(sd_dclk), .SD_MOSI(sd_mosi), .SD_MISO(sd_miso),
    .write_req_ack_mem(sd_card_write_req_ack), .write_finish_mem(frame_write_finish),
    .write_fifo_full(diag_fifo_full),
    .write_req_ack_stream(write_ack_stream), .write_finish_stream(write_finish_stream),
    .write_req(frame_req), .write_addr_index(frame_write_idx),
    .write_len(frame_write_len), .write_first_offset(frame_offset),
    .write_line_width(frame_width), .write_line_jump(frame_jump),
    .write_en(frame_en), .write_data(frame_data),
    .asset_pixel_enable(asset_pixel_enable), .asset_pixel_ready(asset_pixel_ready),
    .asset_header_done(asset_header_done), .asset_header_valid(asset_header_valid),
    .asset_width(asset_width), .asset_height(asset_height),
    .asset_pixel_valid(asset_pixel_valid), .asset_pixel_data(asset_pixel_data),
    .sd_init_done(diag_sd_ready), .busy(diag_busy), .done(diag_done),
    .error(diag_error), .error_code(diag_error_code),
    .completed_asset_mode(), .recovery_required(diag_recovery)
);

fat32_asset_sdram_writer u_asset_writer (
    .clk(sd_card_clk), .rst(rst_all), .start(writer_start),
    .target_frame_index(writer_target_index), .target_first_offset(writer_target_offset),
    .target_width(writer_target_width), .target_height(writer_target_height),
    .target_length(writer_target_length), .target_line_jump(writer_target_jump),
    .bmp_header_done(asset_header_done), .bmp_header_valid(asset_header_valid),
    .bmp_width(asset_width), .bmp_height(asset_height),
    .bmp_pixel_valid(asset_pixel_valid), .bmp_pixel_data(asset_pixel_data),
    .bmp_done(diag_done), .bmp_error(diag_error),
    .write_fifo_full(diag_fifo_full), .write_req_ack_stream(write_ack_stream),
    .write_finish_stream(write_finish_stream),
    .bmp_pixel_enable(writer_pixel_enable), .bmp_pixel_ready(writer_pixel_ready),
    .write_req(asset_req), .write_addr_index(asset_write_idx),
    .write_len(asset_write_len), .write_first_offset(asset_offset),
    .write_line_width(asset_width_wr), .write_line_jump(asset_jump),
    .write_en(asset_en), .write_data(asset_data),
    .busy(), .done(writer_done), .error(writer_error), .error_code(writer_error_code),
    .debug_step(writer_debug_step)
);
assign asset_pixel_enable=mask_pixel_route ? 1'b1 : writer_pixel_enable;
assign asset_pixel_ready=mask_pixel_route ? 1'b1 : writer_pixel_ready;
assign sd_card_write_req=writer_pixel_route ? asset_req : frame_req;
assign write_buf_idx=writer_pixel_route ? asset_write_idx : frame_write_idx;
assign diag_write_len=writer_pixel_route ? asset_write_len : frame_write_len;
assign diag_offset=writer_pixel_route ? asset_offset : frame_offset;
assign diag_width=writer_pixel_route ? asset_width_wr : frame_width;
assign diag_jump=writer_pixel_route ? asset_jump : frame_jump;
assign sd_card_write_en=writer_pixel_route ? asset_en : frame_en;
assign sd_card_write_data=writer_pixel_route ? asset_data : frame_data;
assign home_text_start=mask_start;
assign home_text_valid=mask_pixel_route && asset_pixel_valid;
assign home_text_pixel=asset_pixel_data;
assign disp_buf_idx=sequence_display_index;
assign display_valid=sequence_valid;
assign selected_image_valid=sequence_valid;
assign intro_active=disp_buf_idx==2'd1;
assign fullportrait_mode=1'b0;
assign portrait_load_mode=1'b0;
assign portrait_image_index=4'd0;
assign state_code=sequence_error_stage;
assign debug_found_count=thumb_count_debug;
assign debug_display_index={3'b000,disp_buf_idx[0]};
assign debug_requested_index={3'b000,nav_person_sd[0]};
assign debug_load_busy=sequence_loading;
assign debug_load_progress=2'd0;
wire [3:0] thumb_count_debug=4'd0;
reg [1:0] disp_buf_mem_meta, disp_buf_mem_sync;
always @(posedge ext_mem_clk or posedge rst_all) begin
    if (rst_all) begin
        disp_buf_mem_meta<=2'd0; disp_buf_mem_sync<=2'd0;
    end else begin
        disp_buf_mem_meta<=disp_buf_idx;
        disp_buf_mem_sync<=disp_buf_mem_meta;
    end
end

// Diagnostic digits, left to right: found, displayed, requested, busy,
// source/write done bits, SD reader state. Useful when a page changes text
// but a TF image fails to commit to the alternate frame buffer.
// Diagnostic bitstream: left to right = ready flags, error code,
// writer error, shared busy, thumbnail index, sequence state.
// Left to right on the board: start pulses, accepted reads, request falls,
// completed reads, SD error nibble, SD ready flags.
seg_decoder seg_decoder_m0(.bin_data(voice_start_count), .seg_data(seg_data_0));
seg_decoder seg_decoder_m1(.bin_data(voice_active_count), .seg_data(seg_data_1));
seg_decoder seg_decoder_m2(.bin_data(voice_fall_count), .seg_data(seg_data_2));
seg_decoder seg_decoder_m3(.bin_data(voice_done_count), .seg_data(seg_data_3));
seg_decoder seg_decoder_m4(.bin_data(diag_error_code[3:0]), .seg_data(seg_data_4));
seg_decoder seg_decoder_m5(.bin_data({2'b00,diag_sd_ready,Sdr_init_done}), .seg_data(seg_data_5));

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
    .intro_mode(intro_video_sync),
    .article_mode(article_text_mode_video[1]),
    .contribution_mode(nav_section_sync2 == 3'd1),
    .deeds_mode(nav_section_sync2 == 3'd2),
    .quiz_mode(nav_section_sync2 == 3'd3),
    .quiz_choice(nav_page_sync2[1:0]), .quiz_revealed(nav_quiz_revealed_sync2),
    .quiz_correct((nav_person_sync2 == 0 || nav_person_sync2 == 1 || nav_person_sync2 == 4 || nav_person_sync2 == 7 || nav_person_sync2 == 10) ? (nav_page_sync2 == 1) : (nav_person_sync2 == 2 || nav_person_sync2 == 5 || nav_person_sync2 == 8 || nav_person_sync2 == 11) ? (nav_page_sync2 == 2) : (nav_page_sync2 == 0)),
    .voice_active(nav_level_sync2 == 2 && nav_person_sync2 == 0 &&
        nav_section_sync2 == 0 && nav_page_sync2 >= 1 && nav_page_sync2 <= 4),
    .voice_line(nav_page_sync2[2:0]),
    .voice_samples(voice_samples), .reveal_step(nav_page_sync2[2:0]),
    .rgb_in(intro_video_sync ? vout_data : portrait_composited_rgb), .rgb_out(home_text_mask_rgb)
);

assign text_layer_rgb=text_visible_meta[1] ? home_text_mask_rgb :
                     (intro_video_sync ? vout_data : portrait_composited_rgb);

intro_section_highlight u_intro_section_highlight (
    .clk(video_clk), .rst(rst_video), .vs(vs), .de(de),
    .active(nav_level_sync2 == 2'd1 && intro_video_sync && !load_busy_video_sync),
    .section_index(nav_section_sync2),
    .rgb_in(text_layer_rgb), .rgb_out(home_text_rgb)
);

// Keep the last rendered page/status visible during TF reads, and show a
// small loading panel instead of a confusing black gap. The busy flag is
// synchronized into the pixel clock domain above.
loading_status_overlay u_loading_status (
    .clk(video_clk), .rst(rst_video), .vs(vs), .de(de),
    .loading(load_busy_video_sync), .rgb_in(IMAGE_SCAN_TEST ? home_text_rgb : osd_rgb),
    .rgb_out(loading_overlay_rgb)
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
    // Keep the SDRAM reader synchronized to every video-frame request.
    // display_valid_sync2 only masks pixels below; gating the request here
    // can make the first accepted frame start mid-raster and misalign the
    // background/portrait overlay coordinates.
    .read_req          (video_read_req),
    .intro_mode        (intro_mem_sync),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (24'd0),
    .read_addr_3       (24'd0),
    .read_addr_index   (disp_buf_mem_sync),
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
    .write_addr_2      (24'd1843200),
    .write_addr_3      (24'd0),
    .write_addr_index  (write_buf_idx),
    .write_len         (diag_write_len),
    .write_first_offset(diag_offset),
    .write_line_width  (diag_width),
    .write_line_jump   (diag_jump),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .write_fifo_full   (diag_fifo_full)
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
wire [23:0] prompt_overlay_rgb;
autoplay_prompt_720p u_autoplay_prompt (
    .clk(video_clk), .rst(rst_video), .vs(vs), .de(de),
    .visible(prompt_sync2), .rgb_in(loading_overlay_rgb), .rgb_out(prompt_overlay_rgb)
);
video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_video),
    .I_vs          (vs),
    .I_de          (de),
    .I_rgb         (prompt_overlay_rgb),
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

// Derive ACR cadence from the actual voice samples; no second sample clock.
reg [5:0] tone_acr_count;
reg tone_acr_valid;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin tone_acr_count<=0; tone_acr_valid<=0; end
    else begin
        tone_acr_valid<=0;
        if (hdmi_audio_valid) begin
            if (tone_acr_count==47) begin tone_acr_count<=0; tone_acr_valid<=1; end
            else tone_acr_count<=tone_acr_count+1'b1;
        end
    end
end
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

    .I_audio_valid      (hdmi_audio_valid),
    .I_audio_left_data  (hdmi_audio_data),
    .I_audio_right_data (hdmi_audio_data),
    .I_acr_valid        (tone_acr_valid),
    .I_acr_cts          (20'd75000),
    .I_acr_n            (20'd6144),

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

// Prompt-only BRAM glyph overlay, eight 16x16 characters.
module autoplay_prompt_720p(input wire clk,rst,vs,de,visible,
    input wire [23:0] rgb_in, output reg [23:0] rgb_out);
reg [15:0] rom [0:127];
initial begin
    rom[0] = 16'h0000;
    rom[1] = 16'h0000;
    rom[2] = 16'h26B0;
    rom[3] = 16'h2488;
    rom[4] = 16'hFC80;
    rom[5] = 16'h27FC;
    rom[6] = 16'h2100;
    rom[7] = 16'h39F8;
    rom[8] = 16'h7388;
    rom[9] = 16'hE290;
    rom[10] = 16'h24F0;
    rom[11] = 16'h2C60;
    rom[12] = 16'h39B8;
    rom[13] = 16'hE60C;
    rom[14] = 16'h0000;
    rom[15] = 16'h0000;
    rom[16] = 16'h0000;
    rom[17] = 16'h0000;
    rom[18] = 16'h3E00;
    rom[19] = 16'h7200;
    rom[20] = 16'h6000;
    rom[21] = 16'h6000;
    rom[22] = 16'h7000;
    rom[23] = 16'h3800;
    rom[24] = 16'h0E00;
    rom[25] = 16'h0600;
    rom[26] = 16'h0200;
    rom[27] = 16'h6600;
    rom[28] = 16'h7C00;
    rom[29] = 16'h0000;
    rom[30] = 16'h0000;
    rom[31] = 16'h0000;
    rom[32] = 16'h0000;
    rom[33] = 16'h0000;
    rom[34] = 16'hC30C;
    rom[35] = 16'hC30C;
    rom[36] = 16'h438C;
    rom[37] = 16'h6788;
    rom[38] = 16'h6698;
    rom[39] = 16'h2498;
    rom[40] = 16'h34D0;
    rom[41] = 16'h3CD0;
    rom[42] = 16'h3C70;
    rom[43] = 16'h1870;
    rom[44] = 16'h1860;
    rom[45] = 16'h0000;
    rom[46] = 16'h0000;
    rom[47] = 16'h0000;
    rom[48] = 16'h0000;
    rom[49] = 16'h0000;
    rom[50] = 16'h3C00;
    rom[51] = 16'h6600;
    rom[52] = 16'h0600;
    rom[53] = 16'h0600;
    rom[54] = 16'h0C00;
    rom[55] = 16'h3C00;
    rom[56] = 16'h0600;
    rom[57] = 16'h0200;
    rom[58] = 16'h0200;
    rom[59] = 16'h4600;
    rom[60] = 16'h7C00;
    rom[61] = 16'h0000;
    rom[62] = 16'h0000;
    rom[63] = 16'h0000;
    rom[64] = 16'h0000;
    rom[65] = 16'h0000;
    rom[66] = 16'h67F0;
    rom[67] = 16'h3410;
    rom[68] = 16'h07F0;
    rom[69] = 16'h0410;
    rom[70] = 16'hE410;
    rom[71] = 16'h27F0;
    rom[72] = 16'h2588;
    rom[73] = 16'h24F0;
    rom[74] = 16'h24A0;
    rom[75] = 16'h2710;
    rom[76] = 16'hF608;
    rom[77] = 16'h9FFC;
    rom[78] = 16'h0000;
    rom[79] = 16'h0000;
    rom[80] = 16'h0000;
    rom[81] = 16'h0000;
    rom[82] = 16'h0300;
    rom[83] = 16'h2310;
    rom[84] = 16'h2310;
    rom[85] = 16'h2310;
    rom[86] = 16'h3FF0;
    rom[87] = 16'h0310;
    rom[88] = 16'h6318;
    rom[89] = 16'h6318;
    rom[90] = 16'h6318;
    rom[91] = 16'h6318;
    rom[92] = 16'h7FF8;
    rom[93] = 16'h0018;
    rom[94] = 16'h0000;
    rom[95] = 16'h0000;
    rom[96] = 16'h0000;
    rom[97] = 16'h0000;
    rom[98] = 16'h30C0;
    rom[99] = 16'h20E0;
    rom[100] = 16'hFD30;
    rom[101] = 16'h6318;
    rom[102] = 16'h540C;
    rom[103] = 16'h5100;
    rom[104] = 16'hFD30;
    rom[105] = 16'h1160;
    rom[106] = 16'h1DC0;
    rom[107] = 16'hF108;
    rom[108] = 16'h1108;
    rom[109] = 16'h11F8;
    rom[110] = 16'h0000;
    rom[111] = 16'h0000;
    rom[112] = 16'h0000;
    rom[113] = 16'h0000;
    rom[114] = 16'h2078;
    rom[115] = 16'h27F8;
    rom[116] = 16'hFAF0;
    rom[117] = 16'h2FFC;
    rom[118] = 16'h23F0;
    rom[119] = 16'h34CC;
    rom[120] = 16'h7FF8;
    rom[121] = 16'hE4C8;
    rom[122] = 16'h27F8;
    rom[123] = 16'h2488;
    rom[124] = 16'h27F8;
    rom[125] = 16'hE408;
    rom[126] = 16'h0000;
    rom[127] = 16'h0000;
end
reg [10:0] x; reg [9:0] y; reg last_de,last_vs;
wire [7:0] px=x-11'd512;
wire [5:0] py=y-10'd70;
reg [15:0] glyph; reg [3:0] glyph_x; reg text_active;
always @(posedge clk or posedge rst) begin
    if (rst) begin x<=0; y<=0; last_de<=0; last_vs<=0; glyph<=0; glyph_x<=0; text_active<=0; end
    else begin
        last_de<=de; last_vs<=vs;
        glyph<=rom[{px[7:5],py[4:1]}]; glyph_x<=px[4:1];
        text_active<=de && x>=512 && x<768 && y>=70 && y<102;
        if (vs != last_vs) begin x<=0; y<=0; end
        else begin if (de) x<=x+1'b1; else x<=0; if(last_de && !de) y<=y+1'b1; end
    end
end
always @* begin
    rgb_out=rgb_in;
    if (visible && de && x>=480 && x<800 && y>=50 && y<120) begin
        rgb_out=(x<484 || x>=796 || y<54 || y>=116) ? 24'hFFD34E : 24'h9C0018;
        if (text_active && glyph[15-glyph_x]) rgb_out=24'hFFF1CD;
    end
end
endmodule
