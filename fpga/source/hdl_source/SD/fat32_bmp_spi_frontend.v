`timescale 1ns/1ps

// Board-level SPI SD frontend for the prototype FAT32/BMP frame pipeline.
// Do not instantiate alongside another SD pin owner such as sd_card_bmp.
module fat32_bmp_spi_frontend #(
    parameter integer SPI_LOW_SPEED_DIV = 248,
    parameter integer SPI_HIGH_SPEED_DIV = 0,
    parameter integer READ_TIMEOUT_CYCLES = 100_000_000,
    parameter integer MAX_DIRECTORY_CLUSTERS = 1024,
    parameter integer MAX_FILE_CLUSTERS = 131072,
    parameter integer ADDR_BITS = 21,
    parameter integer OUT_WIDTH = 1280,
    parameter integer OUT_HEIGHT = 720,
    parameter integer BOX_LEFT = 0,
    parameter integer BOX_TOP = 0,
    parameter integer BOX_WIDTH = OUT_WIDTH,
    parameter integer BOX_HEIGHT = OUT_HEIGHT,
    parameter integer REQUEST_TIMEOUT_CYCLES = 10_000_000,
    parameter integer STREAM_TIMEOUT_CYCLES = 1_000_000_000,
    parameter integer FIFO_RELEASE_CYCLES = 8
)(
    input  wire                  clk,
    input  wire                  mem_clk,
    input  wire                  rst,
    input  wire                  start,
    input  wire [87:0]           target_sfn,
    input  wire [1:0]            frame_index,

    output wire                  SD_nCS,
    output wire                  SD_DCLK,
    output wire                  SD_MOSI,
    input  wire                  SD_MISO,

    input  wire                  write_req_ack_mem,
    input  wire                  write_finish_mem,
    input  wire                  write_fifo_full,
    output wire                  write_req,
    output wire [1:0]            write_addr_index,
    output wire [ADDR_BITS-1:0]  write_len,
    output wire [ADDR_BITS-1:0]  write_first_offset,
    output wire [15:0]           write_line_width,
    output wire [ADDR_BITS-1:0]  write_line_jump,
    output wire                  write_en,
    output wire [31:0]           write_data,

    output wire                  sd_init_done,
    output wire                  busy,
    output wire                  done,
    output wire                  error,
    output wire [7:0]            error_code,
    output wire                  recovery_required,
    output wire [3:0]            debug_bpb_error,
    output wire [8:0]            debug_bpb_offset,
    output wire [3:0]            debug_boot_error,
    output wire [7:0]            debug_fat_count,
    output wire [7:0]            debug_sectors_per_cluster
);

    wire sd_sec_read;
    wire sd_init_raw;
    wire sd_sector_ready;
    assign sd_init_done = sd_sector_ready;
    wire [31:0] sd_sec_read_addr;
    wire [7:0] sd_sec_read_data;
    wire sd_sec_read_data_valid;
    wire sd_sec_read_end;
    wire sd_sec_write_data_req_unused;
    wire sd_sec_write_end_unused;
    wire write_req_ack_stream;
    wire write_finish_pulse_stream;

    frame_write_status_cdc u_write_status_cdc (
        .stream_clk(clk),
        .mem_clk(mem_clk),
        .rst(rst),
        .write_req_ack_mem(write_req_ack_mem),
        .write_finish_mem(write_finish_mem),
        .write_req_ack_stream(write_req_ack_stream),
        .write_finish_pulse_stream(write_finish_pulse_stream)
    );

    sd_card_top #(
        .SPI_LOW_SPEED_DIV(SPI_LOW_SPEED_DIV),
        .SPI_HIGH_SPEED_DIV(SPI_HIGH_SPEED_DIV)
    ) u_sd_card_top (
        .clk(clk),
        .rst(rst),
        .SD_nCS(SD_nCS),
        .SD_DCLK(SD_DCLK),
        .SD_MOSI(SD_MOSI),
        .SD_MISO(SD_MISO),
        .sd_init_done(sd_init_raw),
        .sd_sector_ready(sd_sector_ready),
        .sd_sec_read(sd_sec_read),
        .sd_sec_read_addr(sd_sec_read_addr),
        .sd_sec_read_data(sd_sec_read_data),
        .sd_sec_read_data_valid(sd_sec_read_data_valid),
        .sd_sec_read_end(sd_sec_read_end),
        .sd_sec_write(1'b0),
        .sd_sec_write_addr(32'd0),
        .sd_sec_write_data(8'd0),
        .sd_sec_write_data_req(sd_sec_write_data_req_unused),
        .sd_sec_write_end(sd_sec_write_end_unused)
    );

    fat32_bmp_frame_pipeline #(
        .READ_TIMEOUT_CYCLES(READ_TIMEOUT_CYCLES),
        .MAX_DIRECTORY_CLUSTERS(MAX_DIRECTORY_CLUSTERS),
        .MAX_FILE_CLUSTERS(MAX_FILE_CLUSTERS),
        .ADDR_BITS(ADDR_BITS),
        .OUT_WIDTH(OUT_WIDTH),
        .OUT_HEIGHT(OUT_HEIGHT),
        .BOX_LEFT(BOX_LEFT),
        .BOX_TOP(BOX_TOP),
        .BOX_WIDTH(BOX_WIDTH),
        .BOX_HEIGHT(BOX_HEIGHT),
        .REQUEST_TIMEOUT_CYCLES(REQUEST_TIMEOUT_CYCLES),
        .STREAM_TIMEOUT_CYCLES(STREAM_TIMEOUT_CYCLES),
        .FIFO_RELEASE_CYCLES(FIFO_RELEASE_CYCLES)
    ) u_frame_pipeline (
        .clk(clk),
        .rst(rst),
        .sd_init_done(sd_sector_ready),
        .start(start),
        .target_sfn(target_sfn),
        .sd_sec_read(sd_sec_read),
        .sd_sec_read_addr(sd_sec_read_addr),
        .sd_sec_read_data(sd_sec_read_data),
        .sd_sec_read_data_valid(sd_sec_read_data_valid),
        .sd_sec_read_end(sd_sec_read_end),
        .frame_index(frame_index),
        .write_fifo_full(write_fifo_full),
        .write_req_ack(write_req_ack_stream),
        .write_finish(write_finish_pulse_stream),
        .write_req(write_req),
        .write_addr_index(write_addr_index),
        .write_len(write_len),
        .write_first_offset(write_first_offset),
        .write_line_width(write_line_width),
        .write_line_jump(write_line_jump),
        .write_en(write_en),
        .write_data(write_data),
        .busy(busy),
        .done(done),
        .error(error),
        .error_code(error_code),
        .recovery_required(recovery_required),
        .debug_bpb_error(debug_bpb_error), .debug_bpb_offset(debug_bpb_offset), .debug_boot_error(debug_boot_error),
        .debug_fat_count(debug_fat_count), .debug_sectors_per_cluster(debug_sectors_per_cluster)
    );

endmodule
