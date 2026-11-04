`timescale 1ns/1ps

// One physical SD SPI owner for both full-frame backgrounds and decoded
// portrait/caption pixels. Requests are serialized; the inactive client sees
// no sector responses. The caller must keep asset_pixel_ready asserted when
// it can accept decoded pixels, and must reset after a recovery_required error.
module fat32_shared_boot_frontend_2line_candidate #(
    parameter integer ADDR_BITS = 21,
    parameter integer SPI_LOW_SPEED_DIV = 248,
    parameter integer SPI_HIGH_SPEED_DIV = 0
)(
    input  wire                 clk,
    input  wire                 mem_clk,
    input  wire                 rst,
    input  wire                 start,
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

    localparam [1:0] IDLE = 2'd0, FRAME = 2'd1, ASSET = 2'd2;
    reg [1:0] state;
    reg owner_asset;
    reg pcm_owner;
    assign pcm_active = state == ASSET && pcm_owner;
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
    wire sd_write_req_unused, sd_write_end_unused;
    wire frame_sd_read, asset_sd_read;
    wire [31:0] frame_sd_addr, asset_sd_addr;
    wire frame_busy, frame_done, frame_error, frame_recovery;
    wire [7:0] frame_error_code;
    wire asset_busy, asset_done, asset_error;
    wire [7:0] asset_error_code;
    wire ack_stream, finish_stream;

    assign write_req_ack_stream = ack_stream;
    assign write_finish_stream = finish_stream;

    assign busy = state != IDLE || (!shared_metadata_valid && !boot_finished);
    assign sd_init_done = sd_sector_ready;
    assign recovery_required = frame_recovery;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            boot_finished <= 0;
            pcm_owner <= 0; pcm_done <= 0; pcm_error <= 0;
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
            if (shared_boot_done) boot_finished <= 1;
            frame_start_q <= 1'b0;
            asset_start_q <= 1'b0;
            pcm_done <= 0; pcm_error <= 0;
            done <= 1'b0;
            error <= 1'b0;
            case (state)
                IDLE: if (pcm_start && !start && sd_sector_ready && (shared_metadata_valid || boot_finished) && !frame_recovery) begin
                    owner_asset <= 1; pcm_owner <= 1;
                    name_q <= pcm_target_sfn;
                    asset_start_q <= 1;
                    state <= ASSET;
                end else if (start && sd_sector_ready && (shared_metadata_valid || boot_finished) && !frame_recovery) begin
                    pcm_owner <= 0;
                    owner_asset <= asset_mode;
                    name_q <= target_sfn;
                    frame_index_q <= frame_index;
                    frame_start_q <= !asset_mode;
                    asset_start_q <= asset_mode;
                    state <= asset_mode ? ASSET : FRAME;
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
                    pcm_done <= pcm_owner && asset_done && !asset_error;
                    pcm_error <= pcm_owner && asset_error;
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
        .sd_sec_read(!boot_finished ? boot_read : (owner_asset ? asset_sd_read : frame_sd_read)),
        .sd_sec_read_addr(!boot_finished ? boot_addr : (owner_asset ? asset_sd_addr : frame_sd_addr)),
        .sd_sec_read_data(sd_data),
        .sd_sec_read_data_valid(sd_data_valid),
        .sd_sec_read_end(sd_end),
        .sd_sec_write(1'b0), .sd_sec_write_addr(32'd0),
        .sd_sec_write_data(8'd0),
        .sd_sec_write_data_req(sd_write_req_unused),
        .sd_sec_write_end(sd_write_end_unused)
    );

    // Each FAT client owns a separate metadata cache. Only let the current
    // owner start bootstrapping, otherwise both clients request sector zero
    // at power-up and the inactive client's request is never serviced.
    fat32_sharedmeta_frame_pipeline #(.ADDR_BITS(ADDR_BITS)) u_frame (
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

        .clk(clk), .rst(rst), .sd_init_done(sd_sector_ready && state == FRAME),
        .start(frame_start_q), .target_sfn(name_q),
        .sd_sec_read(frame_sd_read), .sd_sec_read_addr(frame_sd_addr),
        .sd_sec_read_data(sd_data),
        .sd_sec_read_data_valid(sd_data_valid && !owner_asset),
        .sd_sec_read_end(sd_end && !owner_asset),
        .frame_index(frame_index_q),
        .write_fifo_full(write_fifo_full),
        .write_req_ack(ack_stream), .write_finish(finish_stream),
        .write_req(write_req), .write_addr_index(write_addr_index),
        .write_len(write_len), .write_first_offset(write_first_offset),
        .write_line_width(write_line_width), .write_line_jump(write_line_jump),
        .write_en(write_en), .write_data(write_data),
        .busy(frame_busy), .done(frame_done), .error(frame_error),
        .error_code(frame_error_code), .recovery_required(frame_recovery),
        .debug_bpb_error(), .debug_bpb_offset(), .debug_boot_error(),
        .debug_fat_count(), .debug_sectors_per_cluster()
    );

    fat32_sharedmeta_asset_loader u_asset (
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

        .clk(clk), .rst(rst), .sd_init_done(sd_sector_ready && state == ASSET),
        .start(asset_start_q), .target_sfn(name_q),
        .pcm_mode(pcm_owner), .pcm_ready(pcm_ready), .pcm_valid(pcm_valid), .pcm_data(pcm_data),
        .sd_sec_read(asset_sd_read), .sd_sec_read_addr(asset_sd_addr),
        .sd_sec_read_data(sd_data),
        .sd_sec_read_data_valid(sd_data_valid && owner_asset),
        .sd_sec_read_end(sd_end && owner_asset),
        .pixel_enable(asset_pixel_enable), .pixel_ready(asset_pixel_ready),
        .header_done(asset_header_done), .header_valid(asset_header_valid),
        .source_width(asset_width), .source_height(asset_height),
        .pixel_valid(asset_pixel_valid), .pixel_data(asset_pixel_data),
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
endmodule
