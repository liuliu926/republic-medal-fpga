`timescale 1ns/1ps

// Load one root-directory FAT32 file by its 8.3 short name and decode it as
// an uncompressed 24-bit BMP. The caller owns scaler setup and pixel storage.
module fat32_sharedmeta_asset_loader_bgm #(
    parameter integer READ_TIMEOUT_CYCLES = 100_000_000,
    parameter integer MAX_DIRECTORY_CLUSTERS = 1024,
    parameter integer MAX_FILE_CLUSTERS = 131072
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        sd_init_done,
    input wire shared_metadata_valid,
    input wire shared_boot_done,
    input wire [3:0] shared_boot_error_code,
    input wire [7:0] shared_fat_count,
    input wire [31:0] shared_volume_start_lba,
    input wire [31:0] shared_volume_sector_count,
    input wire [7:0] shared_sectors_per_cluster,
    input wire [31:0] shared_sectors_per_fat,
    input wire [27:0] shared_root_cluster,
    input wire [31:0] shared_fat_start_lba,
    input wire [31:0] shared_data_start_lba,
    input wire [3:0] shared_debug_bpb_error,
    input wire [8:0] shared_debug_bpb_offset,
    input wire lookup_only,
    output wire [27:0] lookup_file_cluster,
    output wire [31:0] lookup_file_size,
    input wire pcm_mode,
    input wire pcm_ready,
    output wire pcm_valid,
    output wire [7:0] pcm_data,
    input  wire        start,
    input  wire [87:0] target_sfn,

    output wire        sd_sec_read,
    output wire [31:0] sd_sec_read_addr,
    input  wire [7:0]  sd_sec_read_data,
    input  wire        sd_sec_read_data_valid,
    input  wire        sd_sec_read_end,

    input  wire        pixel_enable,
    output wire        header_done,
    output wire        header_valid,
    output wire [15:0] source_width,
    output wire [15:0] source_height,
    output wire        pixel_valid,
    input  wire        pixel_ready,
    output wire [23:0] pixel_data,

    output reg         busy,
    output reg         done,
    output reg         error,
    output reg  [7:0]  error_code,
    output wire [3:0]  debug_bpb_error,
    output wire [8:0]  debug_bpb_offset,
    output wire [3:0]  debug_boot_error,
    output wire [7:0]  debug_fat_count,
    output wire [7:0]  debug_sectors_per_cluster
);

    localparam [3:0] ST_IDLE         = 4'd0;
    localparam [3:0] ST_WAIT_META    = 4'd1;
    localparam [3:0] ST_LOOKUP_START = 4'd2;
    localparam [3:0] ST_LOOKUP_WAIT  = 4'd3;
    localparam [3:0] ST_FILE_START   = 4'd4;
    localparam [3:0] ST_FILE_WAIT    = 4'd5;
    localparam [3:0] ST_COMPLETE     = 4'd6;
    localparam [3:0] ST_FAIL         = 4'd7;

    reg [3:0] state;
    reg [87:0] target_sfn_latched;
    reg [27:0] file_first_cluster_latched;
    reg [31:0] file_size_latched;
    reg [31:0] meta_wait_counter;
    reg bootstrap_finished;
    reg lookup_start;
    reg file_start;
    reg decoder_start;
    reg reader_done_seen;
    reg decoder_done_seen;

    wire boot_sd_read;
    wire [31:0] boot_sd_addr;
    wire boot_busy;
    wire boot_done;
    wire metadata_valid;
    wire [3:0] boot_error_code;
    wire [1:0] boot_partition_index_unused;
    wire [7:0] boot_partition_type_unused;
    wire [15:0] reserved_sectors_unused;
    wire [7:0] fat_count_unused;
    wire [31:0] total_sectors_unused;
    wire [31:0] volume_start_lba;
    wire [31:0] volume_sector_count;
    wire [7:0] sectors_per_cluster;
    wire [31:0] sectors_per_fat;
    wire [27:0] root_cluster;
    wire [31:0] fat_start_lba;
    wire [31:0] data_start_lba;

    wire lookup_sd_read;
    wire [31:0] lookup_sd_addr;
    wire lookup_busy;
    wire lookup_done;
    wire file_found;
    wire [3:0] lookup_error_code;
    wire [27:0] file_first_cluster;
    wire [31:0] file_size;

    wire reader_sd_read;
    wire [31:0] reader_sd_addr;
    wire reader_valid;
    wire reader_ready;
    wire [7:0] reader_data;
    wire reader_busy;
    wire reader_done;
    wire reader_error;
    wire [3:0] reader_error_code;

    wire decoder_ready;
    wire bmp_reader_ready;
    reg pcm_mode_q;
    reg lookup_only_q;
    assign lookup_file_cluster = file_first_cluster_latched;
    assign lookup_file_size = file_size_latched;
    wire decoder_header_done;
    wire decoder_header_valid;
    wire [15:0] decoder_width;
    wire [15:0] decoder_height;
    wire decoder_pixel_valid;
    wire [23:0] decoder_pixel_data;
    wire decoder_done;
    wire decoder_error;

    reg sd_sec_read_mux;
    reg [31:0] sd_sec_read_addr_mux;

    assign sd_sec_read      = sd_sec_read_mux;
    assign sd_sec_read_addr = sd_sec_read_addr_mux;
    assign pcm_valid = pcm_mode_q && reader_valid;
    assign pcm_data = reader_data;
    assign reader_ready = pcm_mode_q ? pcm_ready : bmp_reader_ready;
    assign header_done      = decoder_header_done;
    assign header_valid     = decoder_header_valid;
    assign source_width     = decoder_width;
    assign source_height    = decoder_height;
    assign pixel_valid      = decoder_pixel_valid;
    assign pixel_data       = decoder_pixel_data;
    assign debug_boot_error = boot_error_code;
    assign debug_fat_count = fat_count_unused;
    assign debug_sectors_per_cluster = sectors_per_cluster;

    always @* begin
        sd_sec_read_mux      = 1'b0;
        sd_sec_read_addr_mux = 32'd0;
        if (!metadata_valid) begin
            sd_sec_read_mux      = boot_sd_read;
            sd_sec_read_addr_mux = boot_sd_addr;
        end else if ((state == ST_LOOKUP_START) || (state == ST_LOOKUP_WAIT)) begin
            sd_sec_read_mux      = lookup_sd_read;
            sd_sec_read_addr_mux = lookup_sd_addr;
        end else if ((state == ST_FILE_START) || (state == ST_FILE_WAIT)) begin
            sd_sec_read_mux      = reader_sd_read;
            sd_sec_read_addr_mux = reader_sd_addr;
        end
    end

    assign boot_sd_read = 1'b0;
    assign boot_sd_addr = 0;
    assign boot_busy = 0;
    assign metadata_valid = shared_metadata_valid;
    assign boot_done = shared_boot_done;
    assign boot_error_code = shared_boot_error_code;
    assign fat_count_unused = shared_fat_count;
    assign volume_start_lba = shared_volume_start_lba;
    assign volume_sector_count = shared_volume_sector_count;
    assign sectors_per_cluster = shared_sectors_per_cluster;
    assign sectors_per_fat = shared_sectors_per_fat;
    assign root_cluster = shared_root_cluster;
    assign fat_start_lba = shared_fat_start_lba;
    assign data_start_lba = shared_data_start_lba;
    assign debug_bpb_error = shared_debug_bpb_error;
    assign debug_bpb_offset = shared_debug_bpb_offset;

    fat32_root_file_lookup #(
        .READ_TIMEOUT_CYCLES(READ_TIMEOUT_CYCLES),
        .MAX_DIRECTORY_CLUSTERS(MAX_DIRECTORY_CLUSTERS)
    ) u_root_file_lookup (
        .clk(clk),
        .rst(rst),
        .start(lookup_start),
        .metadata_valid(metadata_valid),
        .volume_start_lba(volume_start_lba),
        .volume_sector_count(volume_sector_count),
        .sectors_per_cluster(sectors_per_cluster),
        .sectors_per_fat(sectors_per_fat),
        .root_cluster(root_cluster),
        .fat_start_lba(fat_start_lba),
        .data_start_lba(data_start_lba),
        .target_sfn(target_sfn_latched),
        .sd_sec_read(lookup_sd_read),
        .sd_sec_read_addr(lookup_sd_addr),
        .sd_sec_read_data(sd_sec_read_data),
        .sd_sec_read_data_valid(sd_sec_read_data_valid),
        .sd_sec_read_end(sd_sec_read_end),
        .busy(lookup_busy),
        .done(lookup_done),
        .file_found(file_found),
        .error_code(lookup_error_code),
        .file_first_cluster(file_first_cluster),
        .file_size(file_size)
    );

    fat32_file_stream_reader #(
        .READ_TIMEOUT_CYCLES(READ_TIMEOUT_CYCLES),
        .MAX_FILE_CLUSTERS(MAX_FILE_CLUSTERS)
    ) u_file_stream_reader (
        .clk(clk),
        .rst(rst || (state == ST_FAIL)),
        .start(file_start),
        .metadata_valid(metadata_valid),
        .volume_start_lba(volume_start_lba),
        .volume_sector_count(volume_sector_count),
        .sectors_per_cluster(sectors_per_cluster),
        .sectors_per_fat(sectors_per_fat),
        .fat_start_lba(fat_start_lba),
        .data_start_lba(data_start_lba),
        .file_first_cluster(file_first_cluster_latched),
        .file_size(file_size_latched),
        .sd_sec_read(reader_sd_read),
        .sd_sec_read_addr(reader_sd_addr),
        .sd_sec_read_data(sd_sec_read_data),
        .sd_sec_read_data_valid(sd_sec_read_data_valid),
        .sd_sec_read_end(sd_sec_read_end),
        .out_valid(reader_valid),
        .out_ready(reader_ready),
        .out_data(reader_data),
        .busy(reader_busy),
        .done(reader_done),
        .error(reader_error),
        .error_code(reader_error_code)
    );

    bmp_stream_decoder u_bmp_stream_decoder (
        .clk(clk),
        .rst_n(!rst && (state != ST_FAIL)),
        .start(decoder_start),
        .file_size_bytes(file_size_latched),
        .stream_valid(reader_valid && !pcm_mode_q),
        .stream_ready(bmp_reader_ready),
        .stream_data(reader_data),
        .pixel_enable(pixel_enable),
        .header_done(decoder_header_done),
        .header_valid(decoder_header_valid),
        .source_width(decoder_width),
        .source_height(decoder_height),
        .pixel_valid(decoder_pixel_valid),
        .pixel_ready(pixel_ready),
        .pixel_data(decoder_pixel_data),
        .image_done(decoder_done),
        .image_error(decoder_error)
    );

    always @(posedge clk) begin
        if (rst) begin
            pcm_mode_q <= 0; lookup_only_q <= 0;
            state                    <= ST_IDLE;
            target_sfn_latched       <= 88'd0;
            file_first_cluster_latched <= 28'd0;
            file_size_latched        <= 32'd0;
            meta_wait_counter        <= 32'd0;
            bootstrap_finished      <= 1'b0;
            lookup_start            <= 1'b0;
            file_start              <= 1'b0;
            decoder_start           <= 1'b0;
            reader_done_seen        <= 1'b0;
            decoder_done_seen       <= 1'b0;
            busy                    <= 1'b0;
            done                    <= 1'b0;
            error                   <= 1'b0;
            error_code              <= 8'd0;
        end else begin
            done          <= 1'b0;
            error         <= 1'b0;
            lookup_start  <= 1'b0;
            file_start    <= 1'b0;
            decoder_start <= 1'b0;

            if (boot_done)
                bootstrap_finished <= 1'b1;

            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        pcm_mode_q <= pcm_mode; lookup_only_q <= lookup_only;
                        target_sfn_latched <= target_sfn;
                        error             <= 1'b0;
                        error_code        <= 8'd0;
                        reader_done_seen  <= 1'b0;
                        decoder_done_seen <= 1'b0;
                        meta_wait_counter <= 32'd0;
                        busy              <= 1'b1;
                        if (metadata_valid)
                            state <= ST_LOOKUP_START;
                        else if (bootstrap_finished || boot_done) begin
                            error_code <= {4'h1, boot_error_code};
                            state <= ST_FAIL;
                        end else begin
                            state <= ST_WAIT_META;
                        end
                    end
                end

                ST_WAIT_META: begin
                    if (metadata_valid) begin
                        state <= ST_LOOKUP_START;
                    end else if (bootstrap_finished || boot_done) begin
                        error_code <= {4'h1, boot_error_code};
                        state <= ST_FAIL;
                    end else if (meta_wait_counter >= READ_TIMEOUT_CYCLES-1) begin
                        error_code <= 8'h1f;
                        state <= ST_FAIL;
                    end else begin
                        meta_wait_counter <= meta_wait_counter + 32'd1;
                    end
                end

                ST_LOOKUP_START: begin
                    lookup_start <= 1'b1;
                    state <= ST_LOOKUP_WAIT;
                end

                ST_LOOKUP_WAIT: begin
                    if (lookup_done) begin
                        if (file_found) begin
                            file_first_cluster_latched <= file_first_cluster;
                            file_size_latched <= file_size;
                            state <= ST_FILE_START;
                        end else begin
                            error_code <= {4'h2, lookup_error_code};
                            state <= ST_FAIL;
                        end
                    end
                end

                ST_FILE_START: if (lookup_only_q) begin
                    state <= ST_COMPLETE;
                end else begin
                    file_start <= 1'b1;
                    decoder_start <= !pcm_mode_q;
                    reader_done_seen <= 1'b0;
                    decoder_done_seen <= 1'b0;
                    state <= ST_FILE_WAIT;
                end

                ST_FILE_WAIT: begin
                    if (reader_done)
                        reader_done_seen <= 1'b1;
                    if (decoder_done)
                        decoder_done_seen <= 1'b1;

                    if (reader_error) begin
                        error_code <= {4'h3, reader_error_code};
                        state <= ST_FAIL;
                    end else if (decoder_error && !pcm_mode_q) begin
                        error_code <= 8'h41;
                        state <= ST_FAIL;
                    end else if ((reader_done_seen || reader_done) &&
                                 (pcm_mode_q || decoder_done_seen || decoder_done)) begin
                        state <= ST_COMPLETE;
                    end
                end

                ST_COMPLETE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= ST_IDLE;
                end

                ST_FAIL: begin
                    busy <= 1'b0;
                    error <= 1'b1;
                    done <= 1'b1;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
