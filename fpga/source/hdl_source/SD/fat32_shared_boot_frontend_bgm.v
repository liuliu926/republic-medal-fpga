`timescale 1ns/1ps

// One physical SD SPI owner for both full-frame backgrounds and decoded
// portrait/caption pixels. Requests are serialized; the inactive client sees
// no sector responses. The caller must keep asset_pixel_ready asserted when
// it can accept decoded pixels, and must reset after a recovery_required error.
module fat32_shared_boot_frontend_bgm #(
    parameter integer ADDR_BITS = 21,
    parameter integer SPI_LOW_SPEED_DIV = 248,
    parameter integer SPI_HIGH_SPEED_DIV = 0
)(
    input  wire                 clk,
    input  wire                 mem_clk,
    input  wire                 rst,
    input  wire                 start,
    // Opening reuses the asset loader's raw/PCM reader. No second FAT, SPI,
    // lookup engine, or sector buffer is instantiated. Hold start until active.
    input wire opening_start,
    input wire [87:0] opening_sfn,
    input wire opening_raw_ready,
    output wire opening_raw_valid,
    output wire [7:0] opening_raw_data,
    output wire opening_active,
    output reg opening_done,
    output reg [7:0] opening_error,
    // Initial low suppresses BGM discovery/start while opening is preloaded.
    // Enable at GUI handoff. Later low pauses new BGM sector requests only.
    input wire bgm_enable,
    input wire bgm_room,
    output wire bgm_valid,
    output wire [7:0] bgm_data,
    output wire bgm_active,
    output wire [7:0] bgm_error,
    output wire bgm_loop,
    input wire pcm_start,
    input wire [87:0] pcm_target_sfn,
    input wire pcm_ready,
    output wire pcm_valid,
    output wire [7:0] pcm_data,
    output wire pcm_active,
    output reg pcm_done,
    output reg pcm_error,
    input  wire                 asset_mode,
    input  wire [87:0]          target_sfn,
    input  wire [1:0]           frame_index,

    output wire                 SD_nCS,
    output wire                 SD_DCLK,
    output wire                 SD_MOSI,
    input  wire                 SD_MISO,
    output wire                 sd_init_done,

    input  wire                 write_req_ack_mem,
    input  wire                 write_finish_mem,
    input  wire                 write_fifo_full,
    output wire                 write_req_ack_stream,
    output wire                 write_finish_stream,
    output wire                 write_req,
    output wire [1:0]           write_addr_index,
    output wire [ADDR_BITS-1:0] write_len,
    output wire [ADDR_BITS-1:0] write_first_offset,
    output wire [15:0]          write_line_width,
    output wire [ADDR_BITS-1:0] write_line_jump,
    output wire                 write_en,
    output wire [31:0]          write_data,

    input  wire                 asset_pixel_enable,
    input  wire                 asset_pixel_ready,
    output wire                 asset_header_done,
    output wire                 asset_header_valid,
    output wire [15:0]          asset_width,
    output wire [15:0]          asset_height,
    output wire                 asset_pixel_valid,
    output wire [23:0]          asset_pixel_data,

    output wire                 busy,
    output reg                  done,
    output reg                  error,
    output reg [7:0]            error_code,
    output reg                  completed_asset_mode,
    output wire                 recovery_required
);

    localparam [1:0] IDLE = 2'd0, FRAME = 2'd1, ASSET = 2'd2, DISCOVER = 2'd3;
    reg [1:0] state;
    reg owner_asset;
    reg bgm_discovered, bgm_start_q, bgm_cursor_started;
    reg [27:0] bgm_file_cluster;
    reg [31:0] bgm_file_size;
    reg [7:0] bgm_lookup_error;
    wire [27:0] lookup_file_cluster;
    wire [31:0] lookup_file_size;
    wire [7:0] bgm_cursor_error;
    assign bgm_error = bgm_lookup_error != 0 ? bgm_lookup_error : bgm_cursor_error;
    reg pcm_owner, opening_owner;
    wire raw_valid;
    wire [7:0] raw_data;
    wire raw_ready = opening_owner ? opening_raw_ready : pcm_ready;
    assign pcm_active = state == ASSET && pcm_owner && !opening_owner;
    assign pcm_valid = raw_valid && pcm_active;
    assign pcm_data = raw_data;
    assign opening_active = state == ASSET && opening_owner;
    assign opening_raw_valid = raw_valid && opening_active;
    assign opening_raw_data = raw_data;
    reg frame_start_q, asset_start_q;
    reg [87:0] name_q;
    reg [1:0] frame_index_q;

    wire sd_ready_raw, sd_sector_ready;
    wire boot_read; wire [31:0] boot_addr;
    wire shared_metadata_valid, shared_boot_done;
    reg boot_finished;
    wire [3:0] shared_boot_error_code;
    wire [7:0] shared_fat_count;
    wire [31:0] shared_volume_start_lba;
    wire [31:0] shared_volume_sector_count;
    wire [7:0] shared_sectors_per_cluster;
    wire [31:0] shared_sectors_per_fat;
    wire [27:0] shared_root_cluster;
    wire [31:0] shared_fat_start_lba;
    wire [31:0] shared_data_start_lba;
    wire [3:0] shared_debug_bpb_error;
    wire [8:0] shared_debug_bpb_offset;

    wire [7:0] sd_data;
    wire sd_data_valid, sd_end;
    wire physical_valid, physical_end, physical_req;
    wire [31:0] physical_addr;
    wire bgm_sd_req, bgm_sd_valid, bgm_sd_end;
    wire [31:0] bgm_sd_addr;
    wire sd_write_req_unused, sd_write_end_unused;
    wire asset_sd_read;
    wire [31:0] asset_sd_addr;
    wire frame_busy, frame_done, frame_error, frame_recovery;
    wire [7:0] frame_error_code;
    wire asset_busy, asset_done, asset_error;
    wire [7:0] asset_error_code;
    wire ack_stream, finish_stream;
    wire frame_pixel_enable,frame_pixel_ready,frame_cancel;
    wire decoded_header_done,decoded_header_valid,decoded_pixel_valid;
    wire [15:0] decoded_width,decoded_height;
    wire [23:0] decoded_pixel;
    assign asset_header_done=decoded_header_done && state==ASSET;
    assign asset_header_valid=decoded_header_valid;
    assign asset_width=decoded_width;
    assign asset_height=decoded_height;
    assign asset_pixel_valid=decoded_pixel_valid && state==ASSET;
    assign asset_pixel_data=decoded_pixel;

    assign write_req_ack_stream = ack_stream;
    assign write_finish_stream = finish_stream;

    assign busy = state != IDLE || (bgm_enable && !bgm_discovered) || (!shared_metadata_valid && !boot_finished);
    assign sd_init_done = sd_sector_ready;
    assign recovery_required = frame_recovery;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            bgm_discovered <= 0; bgm_start_q <= 0; bgm_lookup_error <= 0;
            bgm_cursor_started <= 0; bgm_file_cluster <= 0; bgm_file_size <= 0;
            boot_finished <= 0;
            pcm_owner <= 0; opening_owner <= 0;
            pcm_done <= 0; pcm_error <= 0;
            opening_done <= 0; opening_error <= 0;
            owner_asset <= 1'b0;
            frame_start_q <= 1'b0;
            asset_start_q <= 1'b0;
            name_q <= 88'd0;
            frame_index_q <= 2'd0;
            done <= 1'b0;
            error <= 1'b0;
            error_code <= 8'd0;
            completed_asset_mode <= 1'b0;
        end else begin
            bgm_start_q <= 0;
            if (shared_boot_done) begin
                boot_finished <= 1;
                if (!shared_metadata_valid) begin
                    bgm_discovered <= 1;
                    bgm_lookup_error <= {4'h1, shared_boot_error_code};
                end
            end
            frame_start_q <= 1'b0;
            asset_start_q <= 1'b0;
            pcm_done <= 0; pcm_error <= 0;
            opening_done <= 0; opening_error <= 0;
            done <= 1'b0;
            error <= 1'b0;
            case (state)
                IDLE: if (opening_start && sd_sector_ready && (shared_metadata_valid || boot_finished) && !frame_recovery) begin
                    owner_asset <= 1; pcm_owner <= 1; opening_owner <= 1;
                    name_q <= opening_sfn;
                    asset_start_q <= 1;
                    state <= ASSET;
                end else if (bgm_enable && !bgm_discovered && boot_finished && shared_metadata_valid) begin
                    owner_asset <= 1; pcm_owner <= 0; opening_owner <= 0;
                    name_q <= "BGM     PCM";
                    asset_start_q <= 1;
                    state <= DISCOVER;
                end else if (bgm_enable && bgm_discovered && !bgm_cursor_started && bgm_lookup_error == 0) begin
                    // Enabling may occur after discovery was paused. Retain
                    // its metadata so subsequent raw/image lookups cannot
                    // accidentally redirect the music cursor to their file.
                    bgm_start_q <= 1; bgm_cursor_started <= 1;
                end else if (pcm_start && !start && sd_sector_ready && (shared_metadata_valid || boot_finished) && !frame_recovery) begin
                    owner_asset <= 1; pcm_owner <= 1; opening_owner <= 0;
                    name_q <= pcm_target_sfn;
                    asset_start_q <= 1;
                    state <= ASSET;
                end else if (start && sd_sector_ready && (shared_metadata_valid || boot_finished) && !frame_recovery) begin
                    pcm_owner <= 0; opening_owner <= 0;
                    // Both FRAME and ASSET now use the one shared decoder.
                    owner_asset <= 1'b1;
                    name_q <= target_sfn;
                    frame_index_q <= frame_index;
                    frame_start_q <= !asset_mode;
                    asset_start_q <= 1'b1;
                    state <= asset_mode ? ASSET : FRAME;
                end
                DISCOVER: if (asset_done || asset_error) begin
                    bgm_discovered <= 1;
                    if (asset_error) bgm_lookup_error <= asset_error_code;
                    else begin
                        bgm_file_cluster <= lookup_file_cluster;
                        bgm_file_size <= lookup_file_size;
                        bgm_start_q <= bgm_enable;
                        bgm_cursor_started <= bgm_enable;
                    end
                    state <= IDLE;
                end
                FRAME: if (frame_done || frame_error) begin
                    done <= frame_done && !frame_error;
                    error <= frame_error;
                    error_code <= frame_error_code;
                    completed_asset_mode <= 1'b0;
                    state <= IDLE;
                end
                ASSET: if (asset_done || asset_error) begin
                    done <= !pcm_owner && asset_done && !asset_error;
                    error <= !pcm_owner && asset_error;
                    pcm_done <= pcm_owner && !opening_owner && asset_done && !asset_error;
                    pcm_error <= pcm_owner && !opening_owner && asset_error;
                    opening_done <= opening_owner && asset_done && !asset_error;
                    opening_error <= opening_owner && asset_error ? asset_error_code : 8'd0;
                    error_code <= asset_error_code;
                    completed_asset_mode <= 1'b1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end

    frame_write_status_cdc u_write_status_cdc (
        .stream_clk(clk), .mem_clk(mem_clk), .rst(rst),
        .write_req_ack_mem(write_req_ack_mem),
        .write_finish_mem(write_finish_mem),
        .write_req_ack_stream(ack_stream),
        .write_finish_pulse_stream(finish_stream)
    );

    sd_card_top #(
        .SPI_LOW_SPEED_DIV(SPI_LOW_SPEED_DIV),
        .SPI_HIGH_SPEED_DIV(SPI_HIGH_SPEED_DIV)
    ) u_sd_card_top (
        .clk(clk), .rst(rst),
        .SD_nCS(SD_nCS), .SD_DCLK(SD_DCLK),
        .SD_MOSI(SD_MOSI), .SD_MISO(SD_MISO),
        .sd_init_done(sd_ready_raw), .sd_sector_ready(sd_sector_ready),
        .sd_sec_read(physical_req), .sd_sec_read_addr(physical_addr),
        .sd_sec_read_data(sd_data),
        .sd_sec_read_data_valid(physical_valid),
        .sd_sec_read_end(physical_end),
        .sd_sec_write(1'b0), .sd_sec_write_addr(32'd0),
        .sd_sec_write_data(8'd0),
        .sd_sec_write_data_req(sd_write_req_unused),
        .sd_sec_write_end(sd_write_end_unused)
    );

    // A single FAT lookup/file reader/BMP decoder serves every client.
    // FRAME owns only the accepted scaler and native-frame writer sink.
    fat32_shared_pixel_frame_pipeline #(.ADDR_BITS(ADDR_BITS)) u_frame (
        .clk(clk),.rst(rst),.start(frame_start_q),.frame_index(frame_index_q),
        .header_done(decoded_header_done && state==FRAME),.header_valid(decoded_header_valid),
        .source_width(decoded_width),.source_height(decoded_height),
        .source_pixel_valid(decoded_pixel_valid && state==FRAME),.source_pixel(decoded_pixel),
        .source_pixel_enable(frame_pixel_enable),.source_pixel_ready(frame_pixel_ready),
        .loader_done(asset_done && state==FRAME),.loader_error(asset_error && state==FRAME),
        .loader_error_code(asset_error_code),.loader_cancel(frame_cancel),
        .sd_sector_req(asset_sd_read && state==FRAME),.sd_sector_end(sd_end && state==FRAME),
        .write_fifo_full(write_fifo_full),.write_req_ack(ack_stream),.write_finish(finish_stream),
        .write_req(write_req),.write_addr_index(write_addr_index),.write_len(write_len),
        .write_first_offset(write_first_offset),.write_line_width(write_line_width),.write_line_jump(write_line_jump),
        .write_en(write_en),.write_data(write_data),
        .busy(frame_busy),.done(frame_done),.error(frame_error),
        .error_code(frame_error_code),.recovery_required(frame_recovery)
    );

    fat32_sharedmeta_asset_loader_bgm u_asset (
        .lookup_only(state == DISCOVER),
        .lookup_file_cluster(lookup_file_cluster), .lookup_file_size(lookup_file_size),
        .shared_metadata_valid(shared_metadata_valid),
        .shared_boot_done(shared_boot_done),
        .shared_boot_error_code(shared_boot_error_code),
        .shared_fat_count(shared_fat_count),
        .shared_volume_start_lba(shared_volume_start_lba),
        .shared_volume_sector_count(shared_volume_sector_count),
        .shared_sectors_per_cluster(shared_sectors_per_cluster),
        .shared_sectors_per_fat(shared_sectors_per_fat),
        .shared_root_cluster(shared_root_cluster),
        .shared_fat_start_lba(shared_fat_start_lba),
        .shared_data_start_lba(shared_data_start_lba),
        .shared_debug_bpb_error(shared_debug_bpb_error),
        .shared_debug_bpb_offset(shared_debug_bpb_offset),

        .clk(clk), .rst(rst || frame_cancel), .sd_init_done(sd_sector_ready && (state == ASSET || state == DISCOVER || state == FRAME)),
        .start(asset_start_q), .target_sfn(name_q),
        .pcm_mode(pcm_owner), .pcm_ready(raw_ready), .pcm_valid(raw_valid), .pcm_data(raw_data),
        .sd_sec_read(asset_sd_read), .sd_sec_read_addr(asset_sd_addr),
        .sd_sec_read_data(sd_data),
        .sd_sec_read_data_valid(sd_data_valid && owner_asset),
        .sd_sec_read_end(sd_end && owner_asset),
        .pixel_enable(state==FRAME ? frame_pixel_enable : asset_pixel_enable),
        .pixel_ready(state==FRAME ? frame_pixel_ready : asset_pixel_ready),
        .header_done(decoded_header_done), .header_valid(decoded_header_valid),
        .source_width(decoded_width), .source_height(decoded_height),
        .pixel_valid(decoded_pixel_valid), .pixel_data(decoded_pixel),
        .busy(asset_busy), .done(asset_done), .error(asset_error),
        .error_code(asset_error_code),
        .debug_bpb_error(), .debug_bpb_offset(), .debug_boot_error(),
        .debug_fat_count(), .debug_sectors_per_cluster()
    );
    fat32_volume_bootstrap u_shared_boot (
      .clk(clk), .rst(rst), .sd_init_done(sd_sector_ready),
      .sd_sec_read(boot_read), .sd_sec_read_addr(boot_addr), .sd_sec_read_data(sd_data),
      .sd_sec_read_data_valid(sd_data_valid && !boot_finished), .sd_sec_read_end(sd_end && !boot_finished),
      .busy(), .done(shared_boot_done), .metadata_valid(shared_metadata_valid), .error_code(shared_boot_error_code),
      .partition_index(), .partition_type(), .reserved_sectors(), .total_sectors(),
      .volume_start_lba(shared_volume_start_lba), .volume_sector_count(shared_volume_sector_count),
      .sectors_per_cluster(shared_sectors_per_cluster), .fat_count(shared_fat_count),
      .sectors_per_fat(shared_sectors_per_fat), .root_cluster(shared_root_cluster),
      .fat_start_lba(shared_fat_start_lba), .data_start_lba(shared_data_start_lba),
      .debug_bpb_error(shared_debug_bpb_error), .debug_bpb_offset(shared_debug_bpb_offset));

    sd_sector_arbiter_bgm u_sector_arbiter (
        .clk(clk), .rst(rst), .sector_ready(sd_sector_ready),
        .bgm_enable(bgm_enable),
        .legacy_req(!boot_finished ? boot_read : asset_sd_read),
        .legacy_addr(!boot_finished ? boot_addr : asset_sd_addr),
        .bgm_req(bgm_sd_req), .bgm_addr(bgm_sd_addr),
        .sd_req(physical_req), .sd_addr(physical_addr),
        .sd_valid(physical_valid), .sd_end(physical_end),
        .legacy_valid(sd_data_valid), .legacy_end(sd_end),
        .bgm_valid(bgm_sd_valid), .bgm_end(bgm_sd_end)
    );
    fat32_bgm_sector_cursor u_bgm_cursor (
        .clk(clk), .rst(rst), .start(bgm_start_q), .room(bgm_room && bgm_enable),
        .first_cluster(bgm_file_cluster), .file_size(bgm_file_size),
        .sectors_per_cluster(shared_sectors_per_cluster),
        .sectors_per_fat(shared_sectors_per_fat),
        .fat_start_lba(shared_fat_start_lba), .data_start_lba(shared_data_start_lba),
        .volume_start_lba(shared_volume_start_lba), .volume_sector_count(shared_volume_sector_count),
        .sd_req(bgm_sd_req), .sd_addr(bgm_sd_addr),
        .sd_data(sd_data), .sd_valid(bgm_sd_valid), .sd_end(bgm_sd_end),
        .pcm_valid(bgm_valid), .pcm_data(bgm_data), .active(bgm_active),
        .error_code(bgm_cursor_error), .loop_pulse(bgm_loop)
    );
endmodule
