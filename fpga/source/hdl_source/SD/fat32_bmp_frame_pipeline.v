`timescale 1ns/1ps

// Prototype end-to-end path for one named BMP:
// FAT32 lookup/read -> BMP decode -> aspect-preserving resize -> SDRAM frame FIFO.
// SD and frame-write handshakes remain external so this block can be connected
// to the existing board-level SD and frame_read_write instances incrementally.
module fat32_bmp_frame_pipeline #(
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
    input  wire                  rst,
    input  wire                  sd_init_done,
    input  wire                  start,
    input  wire [87:0]           target_sfn,

    output wire                  sd_sec_read,
    output wire [31:0]           sd_sec_read_addr,
    input  wire [7:0]            sd_sec_read_data,
    input  wire                  sd_sec_read_data_valid,
    input  wire                  sd_sec_read_end,

    input  wire [1:0]            frame_index,
    input  wire                  write_fifo_full,
    input  wire                  write_req_ack,
    input  wire                  write_finish,
    output wire                  write_req,
    output wire [1:0]            write_addr_index,
    output wire [ADDR_BITS-1:0]  write_len,
    output wire [ADDR_BITS-1:0]  write_first_offset,
    output wire [15:0]           write_line_width,
    output wire [ADDR_BITS-1:0]  write_line_jump,
    output wire                  write_en,
    output wire [31:0]           write_data,

    output wire                  busy,
    output reg                   done,
    output reg                   error,
    output reg  [7:0]            error_code,
    output wire                  recovery_required,
    output wire [3:0]            debug_bpb_error,
    output wire [8:0]            debug_bpb_offset,
    output wire [3:0]            debug_boot_error,
    output wire [7:0]            debug_fat_count,
    output wire [7:0]            debug_sectors_per_cluster
);

    wire frame_start;
    wire frame_write_ready;
    wire scaled_ready;
    wire header_done;
    wire header_valid;
    wire [15:0] source_width;
    wire [15:0] source_height;
    wire scaled_valid;
    wire [23:0] scaled_pixel;
    wire scaler_done;
    wire loader_busy;
    wire loader_done;
    wire loader_error;
    wire [7:0] loader_error_code;
    wire writer_busy;
    wire writer_done;
    wire writer_error;
    wire writer_recovery;
    reg loader_done_seen;
    reg writer_done_seen;
    reg active;
    reg writer_launched;
    reg [1:0] frame_index_latched;
    reg sector_pending;
    reg [31:0] sector_timer;
    reg sd_recovery;
    wire accept_start = start && !active && !recovery_required;
    wire cancel_loader = writer_recovery || sd_recovery;

    assign busy = active;
    // A timed-out physical transaction cannot safely be reused. Reset the
    // frontend AND its memory controller before accepting another request.
    assign recovery_required = writer_recovery || sd_recovery;

    fat32_bmp_resize_stream #(
        .READ_TIMEOUT_CYCLES(READ_TIMEOUT_CYCLES),
        .MAX_DIRECTORY_CLUSTERS(MAX_DIRECTORY_CLUSTERS),
        .MAX_FILE_CLUSTERS(MAX_FILE_CLUSTERS),
        .OUT_WIDTH(OUT_WIDTH),
        .OUT_HEIGHT(OUT_HEIGHT),
        .BOX_LEFT(BOX_LEFT),
        .BOX_TOP(BOX_TOP),
        .BOX_WIDTH(BOX_WIDTH),
        .BOX_HEIGHT(BOX_HEIGHT)
    ) u_load_resize (
        .clk(clk),
        .rst(rst),
        .sd_init_done(sd_init_done),
        .start(accept_start),
        .cancel(cancel_loader),
        .target_sfn(target_sfn),
        .sd_sec_read(sd_sec_read),
        .sd_sec_read_addr(sd_sec_read_addr),
        .sd_sec_read_data(sd_sec_read_data),
        .sd_sec_read_data_valid(sd_sec_read_data_valid),
        .sd_sec_read_end(sd_sec_read_end),
        .frame_start(frame_start),
        .frame_write_ready(frame_write_ready),
        .scaled_ready(scaled_ready),
        .header_done(header_done),
        .header_valid(header_valid),
        .source_width(source_width),
        .source_height(source_height),
        .scaled_valid(scaled_valid),
        .scaled_pixel(scaled_pixel),
        .scaler_done(scaler_done),
        .busy(loader_busy),
        .done(loader_done),
        .error(loader_error),
        .error_code(loader_error_code),
        .debug_bpb_error(debug_bpb_error), .debug_bpb_offset(debug_bpb_offset), .debug_boot_error(debug_boot_error),
        .debug_fat_count(debug_fat_count), .debug_sectors_per_cluster(debug_sectors_per_cluster)
    );

    bmp_scaled_frame_write_ctrl #(
        .ADDR_BITS(ADDR_BITS),
        .OUT_WIDTH(OUT_WIDTH),
        .OUT_HEIGHT(OUT_HEIGHT),
        .REQUEST_TIMEOUT_CYCLES(REQUEST_TIMEOUT_CYCLES),
        .STREAM_TIMEOUT_CYCLES(STREAM_TIMEOUT_CYCLES),
        .FIFO_RELEASE_CYCLES(FIFO_RELEASE_CYCLES)
    ) u_frame_write_ctrl (
        .clk(clk),
        .rst(rst),
        .frame_start(frame_start),
        .frame_index(frame_index_latched),
        .scaled_valid(scaled_valid),
        .scaled_pixel(scaled_pixel),
        .scaler_done(scaler_done),
        .upstream_abort(loader_error || sd_recovery),
        .write_fifo_full(write_fifo_full),
        .write_req_ack(write_req_ack),
        .write_finish(write_finish),
        .write_req(write_req),
        .write_addr_index(write_addr_index),
        .write_len(write_len),
        .write_first_offset(write_first_offset),
        .write_line_width(write_line_width),
        .write_line_jump(write_line_jump),
        .write_en(write_en),
        .write_data(write_data),
        .frame_write_ready(frame_write_ready),
        .scaled_ready(scaled_ready),
        .busy(writer_busy),
        .done(writer_done),
        .error(writer_error),
        .recovery_required(writer_recovery)
    );

    always @(posedge clk or posedge rst) begin
        if (rst)
            begin
                loader_done_seen <= 1'b0;
                writer_done_seen <= 1'b0;
                done <= 1'b0;
                active <= 1'b0;
                writer_launched <= 1'b0;
                frame_index_latched <= 2'd0;
                error <= 1'b0;
                error_code <= 8'd0;
                sector_pending <= 1'b0;
                sector_timer <= 32'd0;
                sd_recovery <= 1'b0;
            end
        else begin
            done <= 1'b0;
            // Also track reads issued by the automatic volume bootstrap.
            if (sd_sec_read) begin
                sector_pending <= 1'b1;
                sector_timer <= 32'd0;
            end else if (sd_sec_read_end) begin
                sector_pending <= 1'b0;
                sector_timer <= 32'd0;
            end else if (sector_pending && !sd_recovery) begin
                if (sector_timer >= READ_TIMEOUT_CYCLES-1)
                    sd_recovery <= 1'b1;
                else sector_timer <= sector_timer + 32'd1;
            end
            if (accept_start) begin
                active <= 1'b1;
                writer_launched <= 1'b0;
                frame_index_latched <= frame_index;
                loader_done_seen <= 1'b0;
                writer_done_seen <= 1'b0;
                error <= 1'b0;
                error_code <= 8'd0;
            end else if (active) begin
                if (frame_start) writer_launched <= 1'b1;
                if (loader_error) begin
                    error <= 1'b1;
                    error_code <= loader_error_code;
                end
                if (writer_error && writer_launched && !loader_error) begin
                    error <= 1'b1;
                    error_code <= 8'h50;
                end
                if (sd_recovery) begin
                    error <= 1'b1;
                    error_code <= 8'h51;
                end
                if (loader_done)
                    loader_done_seen <= 1'b1;
                if (writer_done)
                    writer_done_seen <= 1'b1;
                if ((loader_done_seen || loader_done) &&
                    (!writer_launched || writer_done_seen || writer_done) &&
                    (!sector_pending || sd_sec_read_end || sd_recovery)) begin
                    done <= 1'b1;
                    active <= 1'b0;
                    loader_done_seen <= 1'b0;
                    writer_done_seen <= 1'b0;
                end
            end
        end
    end

endmodule
