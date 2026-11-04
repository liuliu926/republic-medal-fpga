
module sd_card_bmp #(
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    parameter [31:0]  SCAN_START_SECTOR = 32'd0,
    parameter [31:0]  SCAN_MAX_SECTOR   = 32'd131071,
    parameter [4:0]   SCAN_TARGET_COUNT = 4'd4,
    parameter [4:0]   INITIAL_INDEX     = 4'd0,
    parameter         PPT_PORTRAIT_TEST = 1'b0,
    parameter integer OUTPUT_WIDTH      = 640,
    parameter integer OUTPUT_HEIGHT     = 480,
    parameter integer IMAGE_LEFT        = 0,
    parameter integer IMAGE_TOP         = 0,
    parameter integer IMAGE_WIDTH       = OUTPUT_WIDTH,
    parameter integer IMAGE_HEIGHT      = OUTPUT_HEIGHT
)(
    input                       clk,
    input                       rst,
    input                       key_next,
    input                       key_auto,
    input                       select_mode,
    input                       desired_intro,
    output reg                  intro_active,
    output wire                 fullportrait_mode,
    input  [3:0]                selected_index,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output reg                  display_valid,
    output      [3:0]           state_code,
    output      [3:0]           debug_found_count,
    output      [3:0]           debug_display_index,
    output      [3:0]           debug_requested_index,
    output                      debug_load_busy,
    output      [1:0]           debug_load_progress,
    output                      selected_image_valid,
    output                      portrait_load_mode,
    output [3:0]                portrait_image_index,
    output                      text_pixel_start,
    output                      text_pixel_valid,
    output [23:0]               text_pixel_data,

    input                       write_finish_toggle,
    output reg [1:0]            write_buf_idx,
    output reg [1:0]            disp_buf_idx,

    output                      write_req,
    input                       write_req_ack,
    output                      write_en,
    output [31:0]               write_data,
    output                      SD_nCS,
    output                      SD_DCLK,
    output                      SD_MOSI,
    input                       SD_MISO
);

wire key_next_press;
wire key_auto_press;

wire             sd_sec_read;
wire [31:0]      sd_sec_read_addr;
wire [7:0]       sd_sec_read_data;
wire             sd_sec_read_data_valid;
wire             sd_sec_read_end;
wire [3:0]       state_code_i;
wire             bmp_data_wr_en;
wire             bmp_write_req;
wire             text_load_mode;
wire [23:0]      bmp_data;
wire             resize_start;
wire             resize_input_ready;
wire [15:0]      source_width;
wire [15:0]      source_height;
wire             resized_valid;
wire [23:0]      resized_pixel;
wire             portrait_resized_valid;
wire [23:0]      portrait_resized_pixel;
wire             background_resize_input_ready;
wire             portrait_resize_input_ready;
wire             sd_init_done;
wire             bmp_ready;
wire             scan_done;
wire             scan_found_valid;
wire [31:0]      scan_found_sector;
wire [4:0]       scan_found_total;

reg              scan_start_pulse;
reg              load_start_pulse;
reg [31:0]       load_sector;
reg              scan_kicked;
reg              scan_done_seen;
reg              first_image_committed;
reg              auto_play_en;
reg [31:0]       auto_cnt;
reg [4:0]        img_found_count;
reg [4:0]        img_idx;              // 当前真正显示中的图片编号
reg [4:0]        load_idx;             // 当前正在写入的图片编号
reg              image4_cached;
reg              image5_cached;
reg [3:0]        selected_index_sync1;
reg [3:0]        selected_index_sync2;
reg [1:0]        pending_buf_idx;      // 当前正在写入的目标缓冲区
reg [31:0]       img_sector0;
reg [31:0]       img_sector1;
reg [31:0]       img_sector2;
reg [31:0]       img_sector3;
reg [31:0]       img_sector4;
reg [31:0]       img_sector5;
reg [31:0]       img_sector6;
reg [31:0]       img_sector7;
reg [31:0]       img_sector8;
reg [31:0]       img_sector9;
reg [31:0]       img_sector10;
reg [31:0]       img_sector11;
reg [31:0]       img_sector12;
reg [31:0]       img_sector13;
reg [31:0]       img_sector14;
reg [31:0]       img_sector15;
reg [31:0]       img_sector16;
reg [31:0]       img_sector17;
reg [31:0]       img_sector18;
reg [31:0]       img_sector19;
reg [31:0]       img_sector20;
reg [31:0]       img_sector21, img_sector22;
reg [2:0]        page_loading;
reg [1:0]        intro_sync;

reg              next_req_pending;
reg              prev_req_pending;
reg              load_busy;
reg [31:0]       load_timeout_cnt;

reg              load_abort;

// bmp_ready 先表示“源文件读取/送 FIFO 完成”；真正切显示要等 write_finish_toggle 同步后
reg              source_done_seen;
reg              write_done_seen;
reg              reader_left_idle;
reg              startup_bg_q, startup_portrait_q;
always @(posedge clk or posedge rst) begin
    if (rst) begin startup_bg_q <= 0; startup_portrait_q <= 0; end
    else begin
        startup_bg_q <= PPT_PORTRAIT_TEST && load_idx == 5'd6 && img_found_count > 5'd7;
        startup_portrait_q <= PPT_PORTRAIT_TEST && load_idx >= 5'd7 && load_idx < 5'd20;
    end
end
reg              load_complete_q;
always @(posedge clk or posedge rst) begin
    if (rst) load_complete_q <= 0;
    else load_complete_q <= load_busy && source_done_seen && write_done_seen && !load_complete_q;
end

// 同步 mem_clk 域的 write_finish_toggle
reg [2:0]        wrfin_tgl_sync;
wire             write_finish_pulse;

wire auto_tick;
wire [4:0] next_from_current;
wire [4:0] prev_from_current;
wire [3:0] selected_index_limited;

reg text_load_mode_q, portrait_load_mode_q;
always @(posedge clk or posedge rst) begin
    if (rst) begin text_load_mode_q <= 0; portrait_load_mode_q <= 0; end
    else begin
        text_load_mode_q <= PPT_PORTRAIT_TEST && (load_idx == 5'd20 || load_idx == 5'd22);
        portrait_load_mode_q <= PPT_PORTRAIT_TEST && page_loading != 3'd2 && load_idx >= 5'd7 && load_idx <= 5'd19;
    end
end
assign text_load_mode = text_load_mode_q;
assign fullportrait_mode = page_loading == 3'd2;
assign text_pixel_start = resize_start && text_load_mode;
assign text_pixel_valid = bmp_data_wr_en && text_load_mode;
assign text_pixel_data = bmp_data;
assign write_req = bmp_write_req && !text_load_mode;
assign portrait_load_mode = portrait_load_mode_q;
assign portrait_image_index = load_idx - 5'd7;
assign resize_input_ready = (text_load_mode || fullportrait_mode) ? 1'b1 : (portrait_load_mode ? portrait_resize_input_ready : background_resize_input_ready);
assign write_en   = text_load_mode ? 1'b0 : (fullportrait_mode ? bmp_data_wr_en : (portrait_load_mode ? portrait_resized_valid : resized_valid));
assign write_data = {fullportrait_mode ? bmp_data : (portrait_load_mode ? portrait_resized_pixel : resized_pixel), 8'b0};
assign auto_tick  = (auto_cnt == (CLK_FREQ_HZ - 1));
assign next_from_current = (img_idx >= 5'd19 || img_idx < 5'd7) ? 5'd7 : img_idx + 5'd1;
assign prev_from_current = (img_idx <= 5'd7 || img_idx > 5'd19) ? 5'd19 : img_idx - 5'd1;
assign selected_index_limited = (selected_index_sync2 < img_found_count)
    ? selected_index_sync2 : 4'd0;
assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];
assign state_code = state_code_i;
assign debug_found_count = img_found_count[3:0];
assign debug_display_index = (img_idx >= 5'd7) ? (img_idx - 5'd7) : 4'd0;
assign debug_requested_index = selected_index_sync2;
assign debug_load_busy = load_busy;
assign debug_load_progress = {source_done_seen, write_done_seen};
assign selected_image_valid = display_valid &&
    (!select_mode || (img_idx == selected_index_sync2));

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (50)
) u_key_next (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_next),
    .press_pulse(key_next_press)
);

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (50)
) u_key_auto (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_auto),
    .press_pulse(key_auto_press)
);

function [3:0] next_index_limited;
    input [3:0] cur;
    input [3:0] count;
    begin
        if (count <= 4'd1 || cur + 4'd1 >= count)
            next_index_limited = 4'd0;
        else
            next_index_limited = cur + 4'd1;
    end
endfunction

function [31:0] sector_lut;
    input [4:0] idx;
    begin
        case (idx)
            2'd0: sector_lut = img_sector0;
            2'd1: sector_lut = img_sector1;
            2'd2: sector_lut = img_sector2;
            2'd3: sector_lut = img_sector3;
            3'd4: sector_lut = img_sector4;
            3'd5: sector_lut = img_sector5;
            3'd6: sector_lut = img_sector6;
            4'd7: sector_lut = img_sector7;
            5'd8: sector_lut = img_sector8;
            5'd9: sector_lut = img_sector9;
            5'd10: sector_lut = img_sector10;
            5'd11: sector_lut = img_sector11;
            5'd12: sector_lut = img_sector12;
            5'd13: sector_lut = img_sector13;
            5'd14: sector_lut = img_sector14;
            5'd15: sector_lut = img_sector15;
            5'd16: sector_lut = img_sector16;
            5'd17: sector_lut = img_sector17;
            5'd18: sector_lut = img_sector18;
            5'd19: sector_lut = img_sector19;
            5'd20: sector_lut = img_sector20;
            5'd21: sector_lut = img_sector21;
            5'd22: sector_lut = img_sector22;
            default: sector_lut = img_sector0;
        endcase
    end
endfunction

function [1:0] next_buf_lut;
    input [1:0] cur_disp_buf;
    input       valid_now;
    begin
        if (!valid_now)
            next_buf_lut = 2'd0;                 // 首图固定写 buffer0
        else if (cur_disp_buf == 2'd0)
            next_buf_lut = 2'd1;
        else
            next_buf_lut = 2'd0;
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        wrfin_tgl_sync        <= 3'b000;
        scan_start_pulse      <= 1'b0;
        load_start_pulse      <= 1'b0;
        load_sector           <= 32'd0;
        scan_kicked           <= 1'b0;
        scan_done_seen        <= 1'b0;
        first_image_committed <= 1'b0;
        auto_play_en          <= 1'b0;
        auto_cnt              <= 32'd0;
        img_found_count       <= 3'd0;
        img_idx               <= 3'd0;
        load_idx              <= 3'd0;
        image4_cached         <= 1'b0;
        image5_cached         <= 1'b0;
        selected_index_sync1  <= 3'd0;
        selected_index_sync2  <= 3'd0;
        pending_buf_idx       <= 2'd0;
        write_buf_idx         <= 2'd0;
        disp_buf_idx          <= 2'd0;
        img_sector0           <= 32'd0;
        img_sector1           <= 32'd0;
        img_sector2           <= 32'd0;
        img_sector3           <= 32'd0;
        img_sector4           <= 32'd0;
        img_sector5           <= 32'd0;
        img_sector6           <= 32'd0;
        img_sector7           <= 32'd0;
        img_sector8 <= 32'd0;
        img_sector9 <= 32'd0;
        img_sector10 <= 32'd0;
        img_sector11 <= 32'd0;
        img_sector12 <= 32'd0;
        img_sector13 <= 32'd0;
        img_sector14 <= 32'd0;
        img_sector15 <= 32'd0;
        img_sector16 <= 32'd0;
        img_sector17 <= 32'd0;
        img_sector18 <= 32'd0;
        img_sector19 <= 32'd0;
        img_sector20 <= 32'd0;
        img_sector21 <= 32'd0; img_sector22 <= 32'd0;
        next_req_pending      <= 1'b0;
        prev_req_pending      <= 1'b0;
        load_busy             <= 1'b0;
        load_timeout_cnt      <= 32'd0;
        load_abort            <= 1'b0;
        page_loading <= 0; intro_active <= 0; intro_sync <= 0;
        source_done_seen      <= 1'b0;
        write_done_seen       <= 1'b0;
        reader_left_idle      <= 1'b0;
        display_valid         <= 1'b0;
    end else begin
        intro_sync <= {intro_sync[0], desired_intro};
        selected_index_sync1 <= selected_index;
        selected_index_sync2 <= selected_index_sync1;
        wrfin_tgl_sync   <= {wrfin_tgl_sync[1:0], write_finish_toggle};
        scan_start_pulse <= 1'b0;
        load_start_pulse <= 1'b0;
        load_abort       <= 1'b0;

        if (!sd_init_done) begin
            scan_kicked           <= 1'b0;
            page_loading <= 0; intro_active <= 0;
            scan_done_seen        <= 1'b0;
            first_image_committed <= 1'b0;
            auto_play_en          <= 1'b0;
            auto_cnt              <= 32'd0;
            img_found_count       <= 3'd0;
            img_idx               <= 3'd0;
            load_idx              <= 3'd0;
            image4_cached         <= 1'b0;
            image5_cached         <= 1'b0;
            pending_buf_idx       <= 2'd0;
            write_buf_idx         <= 2'd0;
            disp_buf_idx          <= 2'd0;
            img_sector0           <= 32'd0;
            img_sector1           <= 32'd0;
            img_sector2           <= 32'd0;
            img_sector3           <= 32'd0;
            img_sector4           <= 32'd0;
            img_sector5           <= 32'd0;
            img_sector6           <= 32'd0;
            img_sector7           <= 32'd0;
        img_sector8 <= 32'd0;
        img_sector9 <= 32'd0;
        img_sector10 <= 32'd0;
        img_sector11 <= 32'd0;
        img_sector12 <= 32'd0;
        img_sector13 <= 32'd0;
        img_sector14 <= 32'd0;
        img_sector15 <= 32'd0;
        img_sector16 <= 32'd0;
        img_sector17 <= 32'd0;
        img_sector18 <= 32'd0;
        img_sector19 <= 32'd0;
        img_sector20 <= 32'd0;
        img_sector21 <= 32'd0; img_sector22 <= 32'd0;
            next_req_pending      <= 1'b0;
        prev_req_pending      <= 1'b0;
            load_busy             <= 1'b0;
            load_timeout_cnt      <= 32'd0;
            load_abort            <= 1'b0;
            source_done_seen      <= 1'b0;
            write_done_seen       <= 1'b0;
            reader_left_idle      <= 1'b0;
            display_valid         <= 1'b0;
        end else begin
            // bmp_read asserts scan_done and scan_found_valid together for the
            // final file. Wait one extra cycle for sector5/count to enter LUT.
            scan_done_seen <= scan_done;
            // 扫描阶段缓存前 4 张图的起始 sector
            if (scan_found_valid) begin
                case (img_found_count)
                    3'd0: img_sector0 <= scan_found_sector;
                    3'd1: img_sector1 <= scan_found_sector;
                    3'd2: img_sector2 <= scan_found_sector;
                    3'd3: img_sector3 <= scan_found_sector;
                    3'd4: img_sector4 <= scan_found_sector;
                    3'd5: img_sector5 <= scan_found_sector;
                    3'd6: img_sector6 <= scan_found_sector;
                    4'd7: img_sector7 <= scan_found_sector;
                    5'd8: img_sector8 <= scan_found_sector;
                    5'd9: img_sector9 <= scan_found_sector;
                    5'd10: img_sector10 <= scan_found_sector;
                    5'd11: img_sector11 <= scan_found_sector;
                    5'd12: img_sector12 <= scan_found_sector;
                    5'd13: img_sector13 <= scan_found_sector;
                    5'd14: img_sector14 <= scan_found_sector;
                    5'd15: img_sector15 <= scan_found_sector;
                    5'd16: img_sector16 <= scan_found_sector;
                    5'd17: img_sector17 <= scan_found_sector;
                    5'd18: img_sector18 <= scan_found_sector;
                    5'd19: img_sector19 <= scan_found_sector;
                    5'd20: img_sector20 <= scan_found_sector;
                    5'd21: img_sector21 <= scan_found_sector;
                    5'd22: img_sector22 <= scan_found_sector;
                    default: ;
                endcase

                if (img_found_count < SCAN_TARGET_COUNT)
                    img_found_count <= img_found_count + 3'd1;
            end

            // 记住 bmp_read 已经把源图送完 FIFO，但还不能切显示，得等整帧写完
            if (load_busy && !bmp_ready)
                reader_left_idle <= 1'b1;
            if (load_busy && reader_left_idle && bmp_ready)
                source_done_seen <= 1'b1;

            // 记住写帧完成脉冲，避免“先写完后源结束”导致脉冲丢失而卡死
            if (load_busy && write_finish_pulse)
                write_done_seen <= 1'b1;

            // Atlas pixels bypass SDRAM and are committed into on-chip RAM.
            if (load_busy && text_load_mode && source_done_seen)
                write_done_seen <= 1'b1;

            // 只有“源图送完 + 整帧写完”都满足，才提交新图并切换显示缓冲区
            if (load_complete_q) begin
                load_busy             <= 1'b0;
                load_timeout_cnt      <= 32'd0;
                source_done_seen      <= 1'b0;
                write_done_seen       <= 1'b0;
                reader_left_idle      <= 1'b0;
                if (page_loading == 3'd1) begin
                    page_loading <= 3'd2; load_idx <= 5'd7; load_sector <= img_sector7;
                    write_buf_idx <= 2'd1; load_start_pulse <= 1; load_busy <= 1;
                end else if (page_loading == 3'd2) begin
                    page_loading <= 3'd3; load_idx <= 5'd22; load_sector <= img_sector22;
                    load_start_pulse <= 1; load_busy <= 1;
                end else if (page_loading == 3'd3) begin
                    page_loading <= 0; intro_active <= 1; display_valid <= 1;
                end else if (page_loading == 3'd4) begin
                    page_loading <= 3'd5; load_idx <= 5'd20; load_sector <= img_sector20;
                    load_start_pulse <= 1; load_busy <= 1;
                end else if (page_loading == 3'd5) begin
                    page_loading <= 0; intro_active <= 0; display_valid <= 1;
                end else if (startup_bg_q) begin
                    // Commit the full-screen background first so a slow or
                    // unsupported portrait can never leave the HDMI output
                    // black. Then write the portrait into its home-card area
                    // in the same frame buffer; the background remains visible
                    // everywhere outside that rectangle.
                    disp_buf_idx          <= pending_buf_idx;
                    img_idx               <= load_idx;
                    // Do not read the framebuffer until all 13 portraits
                    // have completed their writes. This isolates the writer
                    // from scanout during initial composition.
                    display_valid         <= 1'b0;
                    first_image_committed <= 1'b1;
                    // Portrait layers use a dedicated SDRAM region; keep
                    // the background in buffer zero for later scanout.
                    write_buf_idx    <= 2'd1;
                    load_idx         <= 4'd7;
                    load_sector      <= img_sector7;
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                end else if (startup_portrait_q) begin
                    // Keep writing independent TF portraits to their own
                    // rectangles in the same home frame, in card order.
                    load_idx         <= load_idx + 5'd1;
                    load_sector      <= sector_lut(load_idx + 5'd1);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                end else begin
                    if (select_mode && load_idx == 4'd4)
                        image4_cached <= 1'b1;
                    if (select_mode && load_idx == 4'd5)
                        image5_cached <= 1'b1;
                    if (!select_mode || load_idx == selected_index_limited) begin
                        disp_buf_idx  <= pending_buf_idx;
                        img_idx       <= load_idx;
                        display_valid <= 1'b1;
                    end
                    first_image_committed <= 1'b1;
                end
            end else if (load_busy) begin
                if (load_timeout_cnt > CLK_FREQ_HZ * 5) begin
                    // 大图可能需要超过 1 秒。真正超时后重启扫描，避免 scan_done
                    // 被 bmp_read 的 abort 清除后永久无法再响应换图请求。
                    load_busy             <= 1'b0;
                    load_timeout_cnt      <= 32'd0;
                    source_done_seen      <= 1'b0;
                    write_done_seen       <= 1'b0;
                    reader_left_idle      <= 1'b0;
                    load_abort            <= 1'b1;
                    scan_kicked           <= 1'b0;
                    scan_done_seen        <= 1'b0;
                end else begin
                    load_timeout_cnt <= load_timeout_cnt + 32'd1;
                end
            end else begin
                load_timeout_cnt <= 32'd0;
            end

            // 上电后自动发起一次“扫描前 4 张 BMP”
            if (!scan_kicked && bmp_ready) begin
                scan_start_pulse      <= 1'b1;
                scan_kicked           <= 1'b1;
                scan_done_seen        <= 1'b0;
                first_image_committed <= 1'b0;
                auto_play_en          <= 1'b0;
                auto_cnt              <= 32'd0;
                img_found_count       <= 3'd0;
                img_idx               <= 3'd0;
                load_idx              <= 3'd0;
                image4_cached         <= 1'b0;
                image5_cached         <= 1'b0;
                pending_buf_idx       <= 2'd0;
                write_buf_idx         <= 2'd0;
                disp_buf_idx          <= 2'd0;
                next_req_pending      <= 1'b0;
                prev_req_pending      <= 1'b0;
                display_valid         <= 1'b0;
                load_busy             <= 1'b0;
                source_done_seen      <= 1'b0;
                write_done_seen       <= 1'b0;
                reader_left_idle      <= 1'b0;
            end else begin
                // 忙的时候也只记 1 次“下一张”请求，不会累积成连跳两张
                if (!select_mode && key_next_press && scan_done && img_found_count >= 5'd20) begin
                    next_req_pending <= 1'b1;
                    prev_req_pending <= 1'b0;
                end

                // KEY2 queues a single previous portrait request.
                if (!select_mode && key_auto_press && scan_done && img_found_count >= 5'd20) begin
                    prev_req_pending <= 1'b1;
                    next_req_pending <= 1'b0;
                end

                // 自动播放 1s 计数：只有当前没有写图任务时才计时
                if (scan_done && scan_done_seen && auto_play_en && display_valid && !load_busy && first_image_committed && (img_found_count > 3'd1)) begin
                    if (auto_tick)
                        auto_cnt <= 32'd0;
                    else
                        auto_cnt <= auto_cnt + 32'd1;
                end else begin
                    auto_cnt <= 32'd0;
                end

                // 首图自动加载到 buffer0
                if (scan_done && scan_done_seen && !first_image_committed && bmp_ready && !load_busy && (img_found_count >= 5'd23)) begin
                    load_idx         <= select_mode ? 3'd4 : INITIAL_INDEX;
                    load_sector      <= sector_lut(select_mode ? 3'd4 : INITIAL_INDEX);
                    pending_buf_idx  <= 2'd0;
                    write_buf_idx    <= 2'd0;
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    reader_left_idle <= 1'b0;
                    next_req_pending <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
                // 试点把第 5 张和第 6 张固定放在 buffer0/buffer1。
                // 两张均已缓存后，翻页只切读地址，不再读 TF 卡。
                else if (select_mode && scan_done && scan_done_seen && !load_busy && image4_cached &&
                         selected_index_sync2 == 3'd4 && (disp_buf_idx != 2'd0 || img_idx != 3'd4)) begin
                    disp_buf_idx  <= 2'd0;
                    img_idx       <= 3'd4;
                    display_valid <= 1'b1;
                end
                else if (!load_busy && bmp_ready && display_valid && first_image_committed &&
                         (intro_sync[1] != intro_active)) begin
                    display_valid <= 0; pending_buf_idx <= 0; write_buf_idx <= 0;
                    if (intro_sync[1]) begin
                        page_loading <= 3'd1; load_idx <= 5'd21; load_sector <= img_sector21;
                    end else begin
                        page_loading <= 3'd4; load_idx <= 5'd6; load_sector <= img_sector6;
                    end
                    load_start_pulse <= 1; load_busy <= 1;
                    source_done_seen <= 0; write_done_seen <= 0; reader_left_idle <= 0;
                end
                else if (select_mode && scan_done && scan_done_seen && !load_busy && image5_cached &&
                         selected_index_sync2 == 3'd5 && (disp_buf_idx != 2'd1 || img_idx != 3'd5)) begin
                    disp_buf_idx  <= 2'd1;
                    img_idx       <= 3'd5;
                    display_valid <= 1'b1;
                end
                // 首图写好后，在用户浏览首页时把宽图预读到另一块 buffer。
                else if (select_mode && scan_done && scan_done_seen && bmp_ready && !load_busy &&
                         image4_cached && !image5_cached && img_found_count > 3'd5) begin
                    load_idx         <= 3'd5;
                    load_sector      <= img_sector5;
                    pending_buf_idx  <= 2'd1;
                    write_buf_idx    <= 2'd1;
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    reader_left_idle <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
                // Previous portrait loads into the inactive frame buffer.
                else if (!select_mode && scan_done && scan_done_seen && bmp_ready && display_valid && !load_busy && prev_req_pending && img_found_count >= 5'd20) begin
                    load_idx         <= prev_from_current;
                    load_sector      <= sector_lut(prev_from_current);
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    reader_left_idle <= 1'b0;
                    prev_req_pending <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
                // 手动下一张优先：写到“非当前显示”的另一块 buffer
                else if (!select_mode && scan_done && scan_done_seen && bmp_ready && display_valid && !load_busy && next_req_pending && (img_found_count != 3'd0)) begin
                    load_idx         <= next_from_current;
                    load_sector      <= sector_lut(next_from_current);
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    reader_left_idle <= 1'b0;
                    next_req_pending <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
                // 自动播放下一张：同样写到“非当前显示”的另一块 buffer
                else if (!select_mode && scan_done && scan_done_seen && bmp_ready && display_valid && !load_busy && auto_play_en && auto_tick && (img_found_count > 3'd1)) begin
                    load_idx         <= next_from_current;
                    load_sector      <= sector_lut(next_from_current);
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    reader_left_idle <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
            end
        end
    end
end

bmp_read bmp_read_m0(
    .clk                    (clk),
    .rst                    (rst),
    .ready                  (bmp_ready),

    .scan_start             (scan_start_pulse),
    .scan_start_sector      (SCAN_START_SECTOR),
    .scan_max_sector        (SCAN_MAX_SECTOR),
    .scan_target_count      (SCAN_TARGET_COUNT),
    .scan_done              (scan_done),
    .scan_found_valid       (scan_found_valid),
    .scan_found_sector      (scan_found_sector),
    .scan_found_total       (scan_found_total),

    .load_start             (load_start_pulse),
    .load_abort             (load_abort),
    .load_sector            (load_sector),

    .sd_init_done           (sd_init_done),
    .state_code             (state_code_i),
    .bmp_width              (bmp_width),
    .bmp_height             (bmp_height),
    .resize_start           (resize_start),
    .resize_input_ready     (resize_input_ready),
    .source_width           (source_width),
    .source_height          (source_height),
    .write_req              (bmp_write_req),
    .write_req_ack          (text_load_mode ? bmp_write_req : write_req_ack),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .bmp_data_wr_en         (bmp_data_wr_en),
    .bmp_data               (bmp_data)
);

bmp_resize_stream #(
    .OUT_WIDTH (OUTPUT_WIDTH),
    .OUT_HEIGHT(OUTPUT_HEIGHT),
    .BOX_LEFT  (IMAGE_LEFT),
    .BOX_TOP   (IMAGE_TOP),
    .BOX_WIDTH (IMAGE_WIDTH),
    .BOX_HEIGHT(IMAGE_HEIGHT)
) bmp_resize_stream_m0 (
    .clk          (clk),
    .rst          (rst || !sd_init_done || load_abort),
    .start        (resize_start && !portrait_load_mode && !text_load_mode && !fullportrait_mode),
    .source_width (source_width),
    .source_height(source_height),
    .input_ready  (background_resize_input_ready),
    .pixel_valid  (bmp_data_wr_en && !portrait_load_mode && !text_load_mode && !fullportrait_mode),
    .pixel_data   (bmp_data),
    .out_valid    (resized_valid),
    .out_pixel    (resized_pixel),
    .done         ()
);

// High-quality fixed thumbnail stage for the 320x400 TF portraits.
portrait_downscale_box4 portrait_resize_m0 (
    .clk          (clk),
    .rst          (rst || !sd_init_done || load_abort),
    .start        (resize_start && portrait_load_mode),
    .input_ready  (portrait_resize_input_ready),
    .pixel_valid  (bmp_data_wr_en && portrait_load_mode),
    .pixel_data   (bmp_data),
    .out_valid    (portrait_resized_valid),
    .out_pixel    (portrait_resized_pixel),
    .done         ()
);

sd_card_top sd_card_top_m0(
    .clk                    (clk),
    .rst                    (rst),
    .SD_nCS                 (SD_nCS),
    .SD_DCLK                (SD_DCLK),
    .SD_MOSI                (SD_MOSI),
    .SD_MISO                (SD_MISO),
    .sd_init_done           (sd_init_done),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .sd_sec_write           (1'b0),
    .sd_sec_write_addr      (32'd0),
    .sd_sec_write_data      (),
    .sd_sec_write_data_req  (),
    .sd_sec_write_end       ()
);

endmodule

module key_press_debounce #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,    // 默认：松开=1，按下=0
    output reg  press_pulse
);

localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

reg button_sync0;
reg button_sync1;
reg button_stable;
reg [31:0] cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        button_sync0  <= 1'b1;
        button_sync1  <= 1'b1;
        button_stable <= 1'b1;
        cnt           <= 32'd0;
        press_pulse   <= 1'b0;
    end else begin
        button_sync0 <= button_in;
        button_sync1 <= button_sync0;
        press_pulse  <= 1'b0;

        if (button_sync1 == button_stable) begin
            cnt <= 32'd0;
        end else begin
            if (cnt >= DEBOUNCE_CYCLES - 1) begin
                if (button_stable && !button_sync1)
                    press_pulse <= 1'b1;
                button_stable <= button_sync1;
                cnt           <= 32'd0;
            end else begin
                cnt <= cnt + 32'd1;
            end
        end
    end
end

endmodule
