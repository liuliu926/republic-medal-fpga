`timescale 1ns/1ps

// Convenience adapter: FAT32 filename lookup -> BMP decode -> existing
// aspect-preserving line-buffer scaler. The frame writer remains external.
module fat32_bmp_resize_stream #(
    parameter integer READ_TIMEOUT_CYCLES = 100_000_000,
    parameter integer MAX_DIRECTORY_CLUSTERS = 1024,
    parameter integer MAX_FILE_CLUSTERS = 131072,
    parameter integer OUT_WIDTH = 1280,
    parameter integer OUT_HEIGHT = 720,
    parameter integer BOX_LEFT = 0,
    parameter integer BOX_TOP = 0,
    parameter integer BOX_WIDTH = OUT_WIDTH,
    parameter integer BOX_HEIGHT = OUT_HEIGHT
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        sd_init_done,
    input  wire        start,
    input  wire        cancel,
    input  wire [87:0] target_sfn,

    output wire        sd_sec_read,
    output wire [31:0] sd_sec_read_addr,
    input  wire [7:0]  sd_sec_read_data,
    input  wire        sd_sec_read_data_valid,
    input  wire        sd_sec_read_end,

    output reg         frame_start,
    input  wire        frame_write_ready,
    input  wire        scaled_ready,
    output wire        header_done,
    output wire        header_valid,
    output wire [15:0] source_width,
    output wire [15:0] source_height,
    output wire        scaled_valid,
    output wire [23:0] scaled_pixel,
    output wire        scaler_done,
    output reg         busy,
    output reg         done,
    output wire        error,
    output wire [7:0]  error_code,
    output wire [3:0]  debug_bpb_error,
    output wire [8:0]  debug_bpb_offset,
    output wire [3:0]  debug_boot_error,
    output wire [7:0]  debug_fat_count,
    output wire [7:0]  debug_sectors_per_cluster
);

    wire loader_busy;
    wire loader_done;
    wire loader_error;
    wire [7:0] loader_error_code;
    wire source_pixel_valid;
    wire [23:0] source_pixel;
    wire scaler_input_ready;
    wire scaler_pixel_ready;
    reg scaler_start;
    reg waiting_frame_ready;
    reg loader_done_seen;
    reg scaler_done_seen;
    reg cancelled;
    wire accept_start = start && !busy && !cancel && !cancelled;

    assign error = loader_error;
    assign error_code = loader_error_code;

    fat32_bmp_asset_loader #(
        .READ_TIMEOUT_CYCLES(READ_TIMEOUT_CYCLES),
        .MAX_DIRECTORY_CLUSTERS(MAX_DIRECTORY_CLUSTERS),
        .MAX_FILE_CLUSTERS(MAX_FILE_CLUSTERS)
    ) u_asset_loader (
        .clk(clk),
        .rst(rst || cancel || cancelled),
        .sd_init_done(sd_init_done),
        .start(accept_start),
        .target_sfn(target_sfn),
        .sd_sec_read(sd_sec_read),
        .sd_sec_read_addr(sd_sec_read_addr),
        .sd_sec_read_data(sd_sec_read_data),
        .sd_sec_read_data_valid(sd_sec_read_data_valid),
        .sd_sec_read_end(sd_sec_read_end),
        .pixel_enable(scaler_input_ready),
        .header_done(header_done),
        .header_valid(header_valid),
        .source_width(source_width),
        .source_height(source_height),
        .pixel_valid(source_pixel_valid),
        .pixel_ready(scaler_pixel_ready),
        .pixel_data(source_pixel),
        .busy(loader_busy),
        .done(loader_done),
        .error(loader_error),
        .error_code(loader_error_code),
        .debug_bpb_error(debug_bpb_error), .debug_bpb_offset(debug_bpb_offset), .debug_boot_error(debug_boot_error),
        .debug_fat_count(debug_fat_count), .debug_sectors_per_cluster(debug_sectors_per_cluster)
    );

    always @(posedge clk) begin
        if (rst) begin
            scaler_start      <= 1'b0;
            frame_start       <= 1'b0;
            waiting_frame_ready <= 1'b0;
            loader_done_seen  <= 1'b0;
            scaler_done_seen  <= 1'b0;
            busy              <= 1'b0;
            done              <= 1'b0;
            cancelled         <= 1'b0;
        end else begin
            scaler_start <= 1'b0;
            frame_start <= 1'b0;
            done <= 1'b0;

            if (accept_start) begin
                busy <= 1'b1;
                loader_done_seen <= 1'b0;
                scaler_done_seen <= 1'b0;
                waiting_frame_ready <= 1'b0;
            end else if (busy) begin
            if (header_done && header_valid && !loader_error && !cancel)
                begin
                    frame_start <= 1'b1;
                    waiting_frame_ready <= 1'b1;
                end

            if (waiting_frame_ready && frame_write_ready) begin
                scaler_start <= 1'b1;
                waiting_frame_ready <= 1'b0;
            end

            if (loader_done)
                loader_done_seen <= 1'b1;
            if (scaler_done)
                scaler_done_seen <= 1'b1;

            if ((loader_done_seen || loader_done) &&
                ((scaler_done_seen || scaler_done) || loader_error)) begin
                busy <= 1'b0;
                done <= 1'b1;
                waiting_frame_ready <= 1'b0;
            end
            if (cancel) begin
                busy <= 1'b0;
                done <= 1'b1;
                cancelled <= 1'b1;
                waiting_frame_ready <= 1'b0;
                frame_start <= 1'b0;
                scaler_start <= 1'b0;
            end
            end
        end
    end

    bmp_resize_stream #(
        .ENABLE_OUTPUT_BACKPRESSURE(1),
        .OUT_WIDTH(OUT_WIDTH),
        .OUT_HEIGHT(OUT_HEIGHT),
        .BOX_LEFT(BOX_LEFT),
        .BOX_TOP(BOX_TOP),
        .BOX_WIDTH(BOX_WIDTH),
        .BOX_HEIGHT(BOX_HEIGHT)
    ) u_resize (
        .clk(clk),
        // Clear startup-ready from the previous image before any new BMP
        // pixel can be decoded, rather than waiting for the new frame ack.
        .rst(rst || accept_start || loader_error || cancel || cancelled),
        .start(scaler_start),
        .source_width(source_width),
        .source_height(source_height),
        .input_ready(scaler_input_ready),
        .pixel_ready(scaler_pixel_ready),
        .pixel_valid(source_pixel_valid),
        .pixel_data(source_pixel),
        .out_valid(scaled_valid),
        .out_ready(scaled_ready),
        .out_pixel(scaled_pixel),
        .done(scaler_done)
    );

endmodule
