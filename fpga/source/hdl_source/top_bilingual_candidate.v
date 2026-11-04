
module top(
    input                       clk,
    input                       key1,           // 下一项
    input                       key2,           // 上一项
    input                       key3,           // 返回
    input                       key4,           // 确定
    input                       sw3,            // 自动轮播拨码
    input                       sw2,
    input                       sw4,            // 亮度与音量调节弹窗

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
reg [1:0] sw4_sync;
reg [1:0] language_sync;
wire loaded_english;
reg [1:0] english_video;
always @(posedge clk or posedge rst_all) begin
 if(rst_all) language_sync<=0; else language_sync<={language_sync[0],sw2};
end
always @(posedge video_clk or posedge rst_video) begin
 if(rst_video) english_video<=0; else english_video<={english_video[0],loaded_english};
end
reg [1:0] brightness_level;
reg [1:0] volume_level;
reg popup_selected;  // 0: brightness, 1: volume
reg [1:0] volume_level_video_meta, volume_level_video;
reg popup_selected_video_meta, popup_selected_video;
wire brightness_open = sw4_sync[1];
always @(posedge clk or posedge rst_all) begin
    if (rst_all) begin
        sw4_sync <= 2'b00;
        brightness_level <= 2'd3;
        volume_level <= 2'd3;
        popup_selected <= 1'b0;
    end else begin
        sw4_sync <= {sw4_sync[0], sw4};
        if (!brightness_open) popup_selected <= 1'b0;
        else if (key_pulse[2] || key_pulse[3]) popup_selected <= ~popup_selected;
        if (brightness_open && key_pulse[0]) begin
            if (!popup_selected && brightness_level != 2'd3)
                brightness_level <= brightness_level + 1'b1;
            else if (popup_selected && volume_level != 2'd3)
                volume_level <= volume_level + 1'b1;
        end else if (brightness_open && key_pulse[1]) begin
            if (!popup_selected && brightness_level != 2'd0)
                brightness_level <= brightness_level - 1'b1;
            else if (popup_selected && volume_level != 2'd0)
                volume_level <= volume_level - 1'b1;
        end
    end
end
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
    .key_any_pulse((|key_pulse) && !brightness_open),
    .auto_mode(auto_mode), .exit_to_home_pulse(exit_to_home_pulse),
    .prompt_visible(prompt_visible)
);

// 50 MHz reference: person introduction dwell reduced from 8 s to 3 s.
// Narrated article dwell remains 12 s so the complete voice clip can play.
kiosk_autoplay #(.PERSON_CYCLES(150_000_000), .ARTICLE_CYCLES(600_000_000)) u_kiosk_autoplay (
    .clk(clk), .rst(rst_all), .auto_mode(auto_mode), .pause(prompt_visible || debug_load_busy || brightness_open),
    .level(auto_level), .person_index(auto_person),
    .section_index(auto_section), .page_index(auto_page)
);


// Focus is available only in a fully loaded manual person introduction.
wire focus_eligible = nav_level == 1 && !auto_mode && !brightness_open && !debug_load_busy;
wire focus_short, focus_long;
reg focus_target;
wire [5:0] focus_step_mem;
wire focus_scene_mem;
reg [1:0] focus_moving_sync;
wire focus_lock = focus_target || focus_moving_sync[1];
portrait_focus_key u_focus_key (.clk(clk), .rst(rst_all), .key_n(key1),
    .enable(focus_eligible), .short_pulse(focus_short), .long_pulse(focus_long));
always @(posedge clk or posedge rst_all) begin
    if (rst_all) begin focus_target<=0; focus_moving_sync<=0; end
    else begin
        focus_moving_sync<={focus_moving_sync[0],(focus_step_mem!=0)};
        if (!focus_eligible || key_pulse[2]) focus_target<=0;
        else if (focus_long) focus_target<=!focus_target;
    end
end
wire focus_nav_next = (nav_level==1 && !auto_mode) ? focus_short : key_pulse[0];
kiosk_nav #(.PERSON_COUNT(13)) u_kiosk_nav (
    .clk(clk), .rst(rst_all), .auto_mode(auto_mode), .exit_to_home_pulse(exit_to_home_pulse),
    .key_next_pulse(focus_nav_next && !brightness_open && !focus_lock), .key_prev_pulse(key_pulse[1] && !brightness_open && !focus_lock),
    .key_back_pulse(key_pulse[2] && !brightness_open && !focus_lock),
    .key_enter_pulse(key_pulse[3] && !brightness_open && !focus_lock &&
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
wire [4:0] sequence_person;
wire [2:0] sequence_section;
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
    .english(language_sync[1]), .loaded_english(loaded_english),
    .clk(sd_card_clk), .rst(rst_all), .mem_ready(Sdr_init_done),
    .sd_ready(diag_sd_ready), .nav_level(nav_level_sd), .nav_person(nav_person_sd),
    .nav_section(nav_section_sd),
    .shared_busy(diag_busy || voice_start), .shared_done(diag_done), .shared_error(diag_error),
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
    .loaded_person(sequence_person), .loaded_section(sequence_section),
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
// Navigation reaches the asset scheduler two clocks later. Do not arm PCM
// against the previous article while its replacement scene is still pending.
wire voice_requested = article_text_mode && display_level == 2 &&
    display_person == sequence_person && display_section == sequence_section &&
    (display_person <= 12 && display_page >= 1 &&
     ((display_section <= 1 && display_page <= 4) ||
      (display_section == 2 && display_page <= 3))) &&
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
wire [7:0] voice_section_ascii = display_section == 0 ? "L" : display_section == 1 ? "C" : "D";
wire [87:0] voice_sfn = {"P", voice_tens_ascii, voice_ones_ascii,
                         voice_section_ascii, "0", voice_row_ascii, "  PCM"};
wire voice_start, voice_ready, voice_valid, voice_active, voice_done, voice_error;
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
// Independent BGM stream survives navigation; speech sample counters remain untouched.
wire bgm_room, bgm_urgent, bgm_valid, bgm_active, bgm_loop;
wire [7:0] bgm_data, bgm_error;
wire bgm_underrun, bgm_overflow;
wire hdmi_audio_valid;
wire signed [23:0] hdmi_audio_data;
bgm_audio_mixer u_bgm_audio (
    .sd_clk(sd_card_clk), .pixel_clk(video_clk), .rst(rst_all), .pixel_rst(rst_video),
    .volume_level(volume_level_video),
    .bgm_valid(bgm_valid), .bgm_data(bgm_data),
    .bgm_room(bgm_room), .bgm_urgent(bgm_urgent),
    .voice_enable(voice_requested_video[1]),
    .voice_valid(voice_audio_valid), .voice_data(voice_audio_data),
    .audio_valid(hdmi_audio_valid), .audio_data(hdmi_audio_data),
    .bgm_underrun(bgm_underrun), .bgm_overflow(bgm_overflow), .bgm_playing()
);
pcm_audio_bridge u_voice (
    .sd_clk(sd_card_clk), .pixel_clk(video_clk), .rst(rst_all), .pixel_rst(rst_video),
    .requested(voice_requested), .start_allowed(!diag_busy && !sequence_start),
    .raw_valid(voice_valid), .raw_ready(voice_ready), .raw_data(voice_byte),
    .raw_active(voice_active), .raw_done(voice_done), .raw_error(voice_error),
    .raw_start(voice_start), .audio_valid(voice_audio_valid), .audio_data(voice_audio_data),
    .samples_played(voice_samples), .underrun(voice_underrun));
fat32_shared_boot_frontend_bgm u_fat32_shared (
    .bgm_room(bgm_room),
    .bgm_valid(bgm_valid), .bgm_data(bgm_data),
    .bgm_active(bgm_active), .bgm_error(bgm_error), .bgm_loop(bgm_loop),
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
seg_decoder seg_decoder_m0(.bin_data(4'd0), .seg_data(seg_data_0));
seg_decoder seg_decoder_m1(.bin_data(4'd0), .seg_data(seg_data_1));
seg_decoder seg_decoder_m2(.bin_data(4'd0), .seg_data(seg_data_2));
seg_decoder seg_decoder_m3(.bin_data(4'd0), .seg_data(seg_data_3));
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

// Speech lengths are grouped into nine 300-sample pacing classes.  The
// resulting small table tracks the TF PCM clip without storing subtitles in
// FPGA logic.  Generated from assets_720p/audio_life_batch/manifest.json.
reg [15:0] life_pace_packed;
always @* begin
    case (nav_person_sync2)
        5'd2: life_pace_packed = 16'h6367;
        5'd3: life_pace_packed = 16'h4644;
        5'd4: life_pace_packed = 16'h4463;
        5'd5: life_pace_packed = 16'h4786;
        5'd6: life_pace_packed = 16'h5366;
        5'd7: life_pace_packed = 16'h6376;
        5'd8: life_pace_packed = 16'h6566;
        5'd9: life_pace_packed = 16'h7555;
        5'd10: life_pace_packed = 16'h2134;
        5'd11: life_pace_packed = 16'h0364;
        5'd12: life_pace_packed = 16'h4233;
        default: life_pace_packed = 16'h5555;
    endcase
end
reg [3:0] life_pace_class;
always @* begin
    case (nav_page_sync2[2:0])
        3'd1: life_pace_class = life_pace_packed[3:0];
        3'd2: life_pace_class = life_pace_packed[7:4];
        3'd3: life_pace_class = life_pace_packed[11:8];
        3'd4: life_pace_class = life_pace_packed[15:12];
        default: life_pace_class = 4'd5;
    endcase
end
reg [12:0] life_voice_step;
always @* begin
    case (life_pace_class)
        4'd0: life_voice_step = 13'd2400;
        4'd1: life_voice_step = 13'd2700;
        4'd2: life_voice_step = 13'd3000;
        4'd3: life_voice_step = 13'd3300;
        4'd4: life_voice_step = 13'd3600;
        4'd5: life_voice_step = 13'd3900;
        4'd6: life_voice_step = 13'd4200;
        4'd7: life_voice_step = 13'd4500;
        default: life_voice_step = 13'd4800;
    endcase
end

// Body cues follow consumed PCM samples; the heading is visible immediately.
wire article_voice_enabled = article_text_mode_video[1] && nav_level_sync2 == 2 &&
    nav_person_sync2 <= 12 && nav_page_sync2 >= 1 &&
    ((nav_section_sync2 == 1 && nav_page_sync2 <= 4) ||
     (nav_section_sync2 == 2 && nav_page_sync2 <= 3));
wire [1:0] article_row = nav_page_sync2[1:0] - 2'd1;
wire [6:0] article_slot = {nav_person_sync2[3:0], (nav_section_sync2 == 2), article_row};
wire [9:0] article_body_limit;
wire article_voice_finished;
article_voice_reveal u_article_voice_reveal (
    .clk(video_clk), .rst(rst_video),
    .active(article_voice_enabled && voice_requested_video[1]),
    .slot(article_slot), .samples_played(voice_samples),
    .body_limit(article_body_limit), .finished(article_voice_finished)
);

reg english_clip_done_sd;
reg [1:0] english_clip_done_video;
always @(posedge sd_card_clk or posedge rst_all) begin
 if(rst_all) english_clip_done_sd<=0;
 else if(!voice_requested) english_clip_done_sd<=0;
 else if(voice_done) english_clip_done_sd<=1;
end
always @(posedge video_clk or posedge rst_video) begin
 if(rst_video) english_clip_done_video<=0;
 else english_clip_done_video<={english_clip_done_video[0],english_clip_done_sd};
end
home_text_mask u_home_text (
    .clip_complete(english_clip_done_video[1]),
    .english(english_video[1]),
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
    .voice_active(nav_level_sync2 == 2 && nav_person_sync2 <= 12 &&
        nav_section_sync2 == 0 && nav_page_sync2 >= 1 && nav_page_sync2 <= 4),
    .article_voice_active(article_voice_enabled), .article_body_limit(article_body_limit),
    .voice_shen(nav_person_sync2 == 1 && nav_section_sync2 == 0),
    .voice_generic(nav_person_sync2 >= 2 && nav_section_sync2 == 0),
    .voice_step_samples(life_voice_step),
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
wire [23:0] focus_rgb;
portrait_focus_video u_focus_video (
    .clk(video_clk), .rst(rst_video), .x(overlay_x), .y(overlay_y),
    .step_mem(focus_step_mem), .scene_mem(focus_scene_mem),
    .photo_rgb(vout_data), .scene_rgb(home_text_rgb), .rgb(focus_rgb));
loading_status_overlay u_loading_status (
    .clk(video_clk), .rst(rst_video), .vs(vs), .de(de),
    .loading(load_busy_video_sync), .rgb_in(IMAGE_SCAN_TEST ? focus_rgb : osd_rgb),
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
    .focus_scene(nav_level_sd == 1 && sequence_debug_state == 7 && !sequence_loading),
    .focus_target(focus_target), .focus_step(focus_step_mem),
    .focus_scene_latched(focus_scene_mem),
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
wire [23:0] brightness_overlay_rgb;
wire [10:0] overlay_x;
wire [9:0] overlay_y;
reg [1:0] brightness_open_video;
reg [1:0] brightness_level_video_meta, brightness_level_video;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        brightness_open_video <= 2'b00;
        brightness_level_video_meta <= 2'd3;
        brightness_level_video <= 2'd3;
        volume_level_video_meta <= 2'd3;
        volume_level_video <= 2'd3;
        popup_selected_video_meta <= 1'b0;
        popup_selected_video <= 1'b0;
    end else begin
        brightness_open_video <= {brightness_open_video[0], brightness_open};
        brightness_level_video_meta <= brightness_level;
        brightness_level_video <= brightness_level_video_meta;
        volume_level_video_meta <= volume_level;
        volume_level_video <= volume_level_video_meta;
        popup_selected_video_meta <= popup_selected;
        popup_selected_video <= popup_selected_video_meta;
    end
end
autoplay_prompt_720p u_autoplay_prompt (
    .english(english_video[1]),
    .clk(video_clk), .rst(rst_video), .vs(vs), .de(de),
    .visible(prompt_sync2), .rgb_in(loading_overlay_rgb), .rgb_out(prompt_overlay_rgb),
    .pixel_x(overlay_x), .pixel_y(overlay_y)
);
brightness_popup_720p u_brightness_popup (
    .de(de), .pixel_x(overlay_x), .pixel_y(overlay_y),
    .visible(brightness_open_video[1]), .level(brightness_level_video),
    .volume_level(volume_level_video), .selected(popup_selected_video), .english(english_video[1]),
    .rgb_in(prompt_overlay_rgb), .rgb_out(brightness_overlay_rgb)
);
video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_video),
    .I_vs          (vs),
    .I_de          (de),
    .I_rgb         (brightness_overlay_rgb),
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

// SW4 right-edge brightness/volume indicator. Only bars, glyphs and the
// selected frame cover the image; the four-cell bars fill bottom to top.
module brightness_popup_720p(
    input wire de, visible,
    input wire [10:0] pixel_x,
    input wire [9:0] pixel_y,
    input wire [1:0] level,
    input wire english,
    input wire [1:0] volume_level,
    input wire selected,
    input wire [23:0] rgb_in,
    output reg [23:0] rgb_out
);
function [7:0] dim_component;
    input [7:0] c;
    input [1:0] l;
    begin
        case (l)
            2'd0: dim_component = c >> 3;
            2'd1: dim_component = c >> 2;
            2'd2: dim_component = c >> 1;
            default: dim_component = c;
        endcase
    end
endfunction
function [15:0] label_row;
    input [5:0] address;
    begin
        case (address)
            6'd0: label_row = 16'h0100;
            6'd1: label_row = 16'h0180;
            6'd2: label_row = 16'h7FFE;
            6'd3: label_row = 16'h0000;
            6'd4: label_row = 16'h1FF8;
            6'd5: label_row = 16'h1008;
            6'd6: label_row = 16'h1FF8;
            6'd7: label_row = 16'h0000;
            6'd8: label_row = 16'h7FFE;
            6'd9: label_row = 16'h4002;
            6'd10: label_row = 16'h0FE0;
            6'd11: label_row = 16'h0C23;
            6'd12: label_row = 16'h0C23;
            6'd13: label_row = 16'h3823;
            6'd14: label_row = 16'h603E;
            6'd15: label_row = 16'h0000;
            6'd16: label_row = 16'h0000;
            6'd17: label_row = 16'h0080;
            6'd18: label_row = 16'h00C0;
            6'd19: label_row = 16'h3FFF;
            6'd20: label_row = 16'h2000;
            6'd21: label_row = 16'h2218;
            6'd22: label_row = 16'h3FFF;
            6'd23: label_row = 16'h2218;
            6'd24: label_row = 16'h23F8;
            6'd25: label_row = 16'h2000;
            6'd26: label_row = 16'h2FFC;
            6'd27: label_row = 16'h6218;
            6'd28: label_row = 16'h61F0;
            6'd29: label_row = 16'hC7F8;
            6'd30: label_row = 16'h9C0E;
            6'd31: label_row = 16'h0000;
            6'd32: label_row = 16'h6000;
            6'd33: label_row = 16'h27FE;
            6'd34: label_row = 16'h3602;
            6'd35: label_row = 16'h1662;
            6'd36: label_row = 16'h07FA;
            6'd37: label_row = 16'hE662;
            6'd38: label_row = 16'h27FE;
            6'd39: label_row = 16'h2602;
            6'd40: label_row = 16'h26FA;
            6'd41: label_row = 16'h2C9A;
            6'd42: label_row = 16'h3CFA;
            6'd43: label_row = 16'h2C82;
            6'd44: label_row = 16'h0802;
            6'd45: label_row = 16'h181E;
            6'd46: label_row = 16'h0000;
            6'd47: label_row = 16'h0000;
            6'd48: label_row = 16'h0420;
            6'd49: label_row = 16'h0420;
            6'd50: label_row = 16'hFFFF;
            6'd51: label_row = 16'h0C30;
            6'd52: label_row = 16'h0420;
            6'd53: label_row = 16'h0000;
            6'd54: label_row = 16'h7FFC;
            6'd55: label_row = 16'h060C;
            6'd56: label_row = 16'h060C;
            6'd57: label_row = 16'h060C;
            6'd58: label_row = 16'h060C;
            6'd59: label_row = 16'h060C;
            6'd60: label_row = 16'h06F8;
            6'd61: label_row = 16'h0600;
            6'd62: label_row = 16'h0600;
            6'd63: label_row = 16'h0000;
            default: label_row = 16'h0000;
        endcase
    end
endfunction
function [15:0] audio_label_row;
    input [4:0] address;
    begin
        case (address)
            5'd0: audio_label_row = 16'h0000;
            5'd1: audio_label_row = 16'h0000;
            5'd2: audio_label_row = 16'h0180;
            5'd3: audio_label_row = 16'h7FFC;
            5'd4: audio_label_row = 16'h0810;
            5'd5: audio_label_row = 16'h0420;
            5'd6: audio_label_row = 16'hFFFE;
            5'd7: audio_label_row = 16'h0000;
            5'd8: audio_label_row = 16'h3FF8;
            5'd9: audio_label_row = 16'h2008;
            5'd10: audio_label_row = 16'h2008;
            5'd11: audio_label_row = 16'h3FF8;
            5'd12: audio_label_row = 16'h2008;
            5'd13: audio_label_row = 16'h2008;
            5'd14: audio_label_row = 16'h3FF8;
            5'd15: audio_label_row = 16'h2008;
            5'd16: audio_label_row = 16'h0000;
            5'd17: audio_label_row = 16'h0000;
            5'd18: audio_label_row = 16'h0000;
            5'd19: audio_label_row = 16'h1FF8;
            5'd20: audio_label_row = 16'h1008;
            5'd21: audio_label_row = 16'h1FF8;
            5'd22: audio_label_row = 16'h1008;
            5'd23: audio_label_row = 16'h1FF8;
            5'd24: audio_label_row = 16'h0000;
            5'd25: audio_label_row = 16'h7FFE;
            5'd26: audio_label_row = 16'h1088;
            5'd27: audio_label_row = 16'h1FF8;
            5'd28: audio_label_row = 16'h1088;
            5'd29: audio_label_row = 16'h3FFC;
            5'd30: audio_label_row = 16'h0080;
            5'd31: audio_label_row = 16'h7FFE;
            default: audio_label_row = 16'h0000;
        endcase
    end
endfunction
wire [10:0] x = pixel_x;
wire [9:0] y = pixel_y;
wire bar_left = x >= 11'd1152 && x < 11'd1192;
wire bar_right = x >= 11'd1212 && x < 11'd1252;
wire bar_area = (bar_left || bar_right) && y >= 10'd256 && y < 10'd512;
wire [5:0] bar_x = bar_left ? x - 11'd1152 : x - 11'd1212;
wire [1:0] bar_level = bar_left ? level : volume_level;
wire [1:0] first_filled_cell = ~bar_level;
// Four corners share one small radius lookup. No multiplier or divider.
wire [5:0] edge_x = bar_x < 6'd20 ? bar_x : 6'd39 - bar_x;
wire [7:0] edge_y = y[7] ? ~y[7:0] : y[7:0];
function [7:0] corner_limits;
    input [3:0] row;
    begin
        case (row)
            4'd0: corner_limits = 8'h9F;
            4'd1: corner_limits = 8'h6F;
            4'd2: corner_limits = 8'h59;
            4'd3: corner_limits = 8'h47;
            4'd4: corner_limits = 8'h35;
            4'd5: corner_limits = 8'h24;
            4'd6: corner_limits = 8'h14;
            4'd7: corner_limits = 8'h13;
            4'd8: corner_limits = 8'h13;
            4'd9: corner_limits = 8'h02;
            4'd10: corner_limits = 8'h02;
            4'd11: corner_limits = 8'h02;
            default: corner_limits = 8'h02;
        endcase
    end
endfunction
wire [7:0] rounded_limits = edge_y < 8'd12 ? corner_limits(edge_y[3:0]) : 8'h02;
wire inside_rounded = edge_x >= rounded_limits[7:4];
wire inside_fill = edge_y >= 8'd2 && edge_x >= rounded_limits[3:0];
wire cell_border = !inside_fill || y[5:0] < 6'd2 || y[5:0] >= 6'd62;
wire label_left = x >= 11'd1156 && x < 11'd1188;
wire label_right = x >= 11'd1216 && x < 11'd1248;
wire [4:0] label_x = label_left ? x - 11'd1156 : x - 11'd1216;
wire [4:0] glyph_address = {label_x[4], y[3:0]};
function [15:0] english_label_row;
input [5:0] address;
begin case(address)
6'd0: english_label_row=16'h0000;
6'd1: english_label_row=16'h0000;
6'd2: english_label_row=16'h4080;
6'd3: english_label_row=16'h4000;
6'd4: english_label_row=16'h408d;
6'd5: english_label_row=16'h4093;
6'd6: english_label_row=16'h4091;
6'd7: english_label_row=16'h4091;
6'd8: english_label_row=16'h4091;
6'd9: english_label_row=16'h4093;
6'd10: english_label_row=16'h7e8d;
6'd11: english_label_row=16'h0001;
6'd12: english_label_row=16'h001e;
6'd13: english_label_row=16'h0000;
6'd14: english_label_row=16'h0000;
6'd15: english_label_row=16'h0000;
6'd16: english_label_row=16'h0000;
6'd17: english_label_row=16'h0040;
6'd18: english_label_row=16'h2040;
6'd19: english_label_row=16'h20e0;
6'd20: english_label_row=16'h2c40;
6'd21: english_label_row=16'h3240;
6'd22: english_label_row=16'h2240;
6'd23: english_label_row=16'h2240;
6'd24: english_label_row=16'h2240;
6'd25: english_label_row=16'h2260;
6'd26: english_label_row=16'h2200;
6'd27: english_label_row=16'h0000;
6'd28: english_label_row=16'h0000;
6'd29: english_label_row=16'h0000;
6'd30: english_label_row=16'h0000;
6'd31: english_label_row=16'h0000;
6'd32: english_label_row=16'h0000;
6'd33: english_label_row=16'h0000;
6'd34: english_label_row=16'h4100;
6'd35: english_label_row=16'h4100;
6'd36: english_label_row=16'h2238;
6'd37: english_label_row=16'h2244;
6'd38: english_label_row=16'h2244;
6'd39: english_label_row=16'h1444;
6'd40: english_label_row=16'h1444;
6'd41: english_label_row=16'h0844;
6'd42: english_label_row=16'h0838;
6'd43: english_label_row=16'h0000;
6'd44: english_label_row=16'h0000;
6'd45: english_label_row=16'h0000;
6'd46: english_label_row=16'h0000;
6'd47: english_label_row=16'h0000;
6'd48: english_label_row=16'h0000;
6'd49: english_label_row=16'h0000;
6'd50: english_label_row=16'h8000;
6'd51: english_label_row=16'h8000;
6'd52: english_label_row=16'h8000;
6'd53: english_label_row=16'h8000;
6'd54: english_label_row=16'h8000;
6'd55: english_label_row=16'h8000;
6'd56: english_label_row=16'h8000;
6'd57: english_label_row=16'h8000;
6'd58: english_label_row=16'h8000;
6'd59: english_label_row=16'h0000;
6'd60: english_label_row=16'h0000;
6'd61: english_label_row=16'h0000;
6'd62: english_label_row=16'h0000;
6'd63: english_label_row=16'h0000;
default:english_label_row=0; endcase end endfunction
wire [15:0] glyph_row = english ? english_label_row({!label_left,glyph_address}) : label_left ? label_row({1'b0,glyph_address}) :
    audio_label_row(glyph_address);
wire glyph_pixel = (label_left || label_right) && y >= 10'd528 && y < 10'd544 &&
    glyph_row[15-label_x[3:0]];
wire frame_left = x >= 11'd1148 && x < 11'd1196;
wire frame_right = x >= 11'd1208 && x < 11'd1256;
wire [10:0] frame_origin = selected ? 11'd1208 : 11'd1148;
wire [5:0] frame_x = x - frame_origin;
wire [5:0] frame_edge_x = frame_x < 6'd24 ? frame_x : 6'd47 - frame_x;
wire [2:0] frame_edge_y = y < 10'd252 ? y - 10'd248 :
                            y >= 10'd548 ? 10'd551 - y : 3'd4;
wire outer_rounded = frame_edge_y >= 3'd4 || frame_edge_x >= (3'd4-frame_edge_y);
wire frame_inner = frame_x >= 6'd2 && frame_x < 6'd46 &&
                   y >= 10'd250 && y < 10'd550;
wire selected_frame = (selected ? frame_right : frame_left) &&
    y >= 10'd248 && y < 10'd552 && outer_rounded && !frame_inner;
always @* begin
    rgb_out = {dim_component(rgb_in[23:16], level),
               dim_component(rgb_in[15:8], level),
               dim_component(rgb_in[7:0], level)};
    if (visible && de) begin
        if (bar_area && inside_rounded)
            rgb_out = cell_border ? 24'hFFF2D0 :
                      (y[7:6] >= first_filled_cell ? 24'hFFD34E : 24'h6D3540);
        if (glyph_pixel) rgb_out = 24'hFFF2D0;
        if (selected_frame) rgb_out = 24'hFFE277;
    end
end
endmodule

// Prompt-only BRAM glyph overlay, eight 16x16 characters.
module autoplay_prompt_720p(input wire clk,rst,vs,de,visible,english,
    input wire [23:0] rgb_in, output reg [23:0] rgb_out,
    output wire [10:0] pixel_x, output wire [9:0] pixel_y);
reg [15:0] rom [0:255];
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
rom[128]=16'h0000;
rom[129]=16'h0000;
rom[130]=16'h3e41;
rom[131]=16'h4142;
rom[132]=16'h4122;
rom[133]=16'h4022;
rom[134]=16'h3822;
rom[135]=16'h0614;
rom[136]=16'h0114;
rom[137]=16'h4114;
rom[138]=16'h4108;
rom[139]=16'h3e08;
rom[140]=16'h0000;
rom[141]=16'h0000;
rom[142]=16'h0000;
rom[143]=16'h0000;
rom[144]=16'h0000;
rom[145]=16'h0000;
rom[146]=16'h05e0;
rom[147]=16'h8610;
rom[148]=16'h8810;
rom[149]=16'h8810;
rom[150]=16'h88e0;
rom[151]=16'h5010;
rom[152]=16'h5010;
rom[153]=16'h5010;
rom[154]=16'h2210;
rom[155]=16'h21e0;
rom[156]=16'h0000;
rom[157]=16'h0000;
rom[158]=16'h0000;
rom[159]=16'h0000;
rom[160]=16'h0000;
rom[161]=16'h0000;
rom[162]=16'h0f0f;
rom[163]=16'h1088;
rom[164]=16'h2048;
rom[165]=16'h2048;
rom[166]=16'h204f;
rom[167]=16'h2048;
rom[168]=16'h2048;
rom[169]=16'h2048;
rom[170]=16'h1088;
rom[171]=16'h0f08;
rom[172]=16'h0000;
rom[173]=16'h0000;
rom[174]=16'h0000;
rom[175]=16'h0000;
rom[176]=16'h0000;
rom[177]=16'h0000;
rom[178]=16'hcfc1;
rom[179]=16'h0800;
rom[180]=16'h0800;
rom[181]=16'h0800;
rom[182]=16'h8f80;
rom[183]=16'h0800;
rom[184]=16'h0800;
rom[185]=16'h0800;
rom[186]=16'h0800;
rom[187]=16'h0800;
rom[188]=16'h0000;
rom[189]=16'h0000;
rom[190]=16'h0000;
rom[191]=16'h0000;
rom[192]=16'h0000;
rom[193]=16'h0000;
rom[194]=16'hfc78;
rom[195]=16'h2084;
rom[196]=16'h2102;
rom[197]=16'h2102;
rom[198]=16'h2102;
rom[199]=16'h2102;
rom[200]=16'h2102;
rom[201]=16'h2102;
rom[202]=16'h2084;
rom[203]=16'h2078;
rom[204]=16'h0000;
rom[205]=16'h0000;
rom[206]=16'h0000;
rom[207]=16'h0000;
rom[208]=16'h0000;
rom[209]=16'h0000;
rom[210]=16'h07f4;
rom[211]=16'h0402;
rom[212]=16'h0402;
rom[213]=16'h0401;
rom[214]=16'h07f0;
rom[215]=16'h0400;
rom[216]=16'h0401;
rom[217]=16'h0402;
rom[218]=16'h0402;
rom[219]=16'h07f4;
rom[220]=16'h0000;
rom[221]=16'h0000;
rom[222]=16'h0000;
rom[223]=16'h0000;
rom[224]=16'h0000;
rom[225]=16'h0000;
rom[226]=16'h15fc;
rom[227]=16'h2420;
rom[228]=16'h2420;
rom[229]=16'h4420;
rom[230]=16'h8420;
rom[231]=16'h8420;
rom[232]=16'h4420;
rom[233]=16'h2420;
rom[234]=16'h2420;
rom[235]=16'h1420;
rom[236]=16'h0000;
rom[237]=16'h0000;
rom[238]=16'h0000;
rom[239]=16'h0000;
rom[240]=16'h0000;
rom[241]=16'h0000;
rom[242]=16'h0000;
rom[243]=16'h0000;
rom[244]=16'h0000;
rom[245]=16'h0000;
rom[246]=16'h0000;
rom[247]=16'h0000;
rom[248]=16'h0000;
rom[249]=16'h0000;
rom[250]=16'h0000;
rom[251]=16'h0000;
rom[252]=16'h0000;
rom[253]=16'h0000;
rom[254]=16'h0000;
rom[255]=16'h0000;
end
reg [10:0] x; reg [9:0] y; reg last_de,last_vs;
assign pixel_x = x;
assign pixel_y = y;
wire [7:0] px=x-11'd512;
wire [5:0] py=y-10'd70;
reg [15:0] glyph; reg [3:0] glyph_x; reg text_active;
always @(posedge clk or posedge rst) begin
    if (rst) begin x<=0; y<=0; last_de<=0; last_vs<=0; glyph<=0; glyph_x<=0; text_active<=0; end
    else begin
        last_de<=de; last_vs<=vs;
        glyph<=rom[{english,px[7:5],py[4:1]}]; glyph_x<=px[4:1];
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
