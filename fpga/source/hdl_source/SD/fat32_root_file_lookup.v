// Find one 8.3 file in the FAT32 root directory, following its FAT cluster
// chain when the directory spans more than one cluster.
module fat32_root_file_lookup #(
    parameter integer READ_TIMEOUT_CYCLES = 100_000_000,
    parameter integer MAX_DIRECTORY_CLUSTERS = 1024
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        metadata_valid,
    input  wire [31:0] volume_start_lba,
    input  wire [31:0] volume_sector_count,
    input  wire [7:0]  sectors_per_cluster,
    input  wire [31:0] sectors_per_fat,
    input  wire [27:0] root_cluster,
    input  wire [31:0] fat_start_lba,
    input  wire [31:0] data_start_lba,
    input  wire [87:0] target_sfn,
    output reg         sd_sec_read,
    output reg  [31:0] sd_sec_read_addr,
    input  wire [7:0]  sd_sec_read_data,
    input  wire        sd_sec_read_data_valid,
    input  wire        sd_sec_read_end,
    output reg         busy,
    output reg         done,
    output reg         file_found,
    output reg  [3:0]  error_code,
    output reg  [27:0] file_first_cluster,
    output reg  [31:0] file_size
);

localparam [3:0] ERR_NONE             = 4'd0;
localparam [3:0] ERR_METADATA         = 4'd1;
localparam [3:0] ERR_READ_TIMEOUT     = 4'd2;
localparam [3:0] ERR_SHORT_SECTOR     = 4'd3;
localparam [3:0] ERR_FAT_CHAIN        = 4'd4;
localparam [3:0] ERR_FAT_BOUNDS       = 4'd5;
localparam [3:0] ERR_CLUSTER_LIMIT    = 4'd6;
localparam [3:0] ERR_LBA_RANGE        = 4'd7;
localparam [3:0] ERR_FILE_NOT_FOUND   = 4'd8;
localparam [3:0] ERR_DIRECTORY_CHAIN  = 4'd9;

localparam [3:0] ST_IDLE       = 4'd0;
localparam [3:0] ST_DIR_REQ    = 4'd1;
localparam [3:0] ST_DIR_WAIT   = 4'd2;
localparam [3:0] ST_FAT_REQ    = 4'd3;
localparam [3:0] ST_FAT_WAIT   = 4'd4;
localparam [3:0] ST_FAT_CHECK  = 4'd5;
localparam [3:0] ST_DONE       = 4'd6;
localparam [3:0] ST_ERROR      = 4'd7;
localparam [3:0] ST_DIR_SHIFT  = 4'd8;
localparam [3:0] ST_DIR_OFFSET = 4'd9;
localparam [3:0] ST_DIR_LBA    = 4'd10;
localparam [3:0] ST_DIR_CHECK  = 4'd11;
localparam [3:0] ST_FAT_PREP   = 4'd12;

reg [3:0] state;
reg [2:0] directory_shift_q;
reg [34:0] directory_offset_q;
reg [35:0] directory_lba_q;
reg [32:0] volume_end_q;
reg [32:0] fat_lba_q;
reg directory_lba_valid_q;
reg [31:0] timeout_counter;
reg [87:0] target_sfn_latched;
reg [27:0] current_directory_cluster;
reg [7:0] directory_sector_index;
reg [31:0] visited_cluster_count;
reg [8:0] fat_byte_index;
reg [8:0] stream_byte_index;
reg [31:0] fat_entry_word;
reg [3:0] fat_byte_seen;
reg directory_scan_seen;
reg directory_scan_match;
reg directory_scan_end;
reg directory_sd_end_seen;
reg [27:0] directory_match_cluster;
reg [31:0] directory_match_size;

reg scan_start;
wire scan_busy;
wire scan_done;
wire scan_match_found;
wire scan_end_of_directory;
wire [27:0] scan_first_cluster;
wire [31:0] scan_file_size;

reg [2:0] sectors_per_cluster_shift;
reg [34:0] cluster_sector_offset;
reg [35:0] directory_lba_ext;
reg [32:0] fat_lba_ext;
reg [32:0] volume_end_lba_ext;
reg [31:0] fat_next_cluster;

function [2:0] decode_spc_shift;
    input [7:0] spc;
    begin
        case (spc)
            8'd1:   decode_spc_shift = 3'd0;
            8'd2:   decode_spc_shift = 3'd1;
            8'd4:   decode_spc_shift = 3'd2;
            8'd8:   decode_spc_shift = 3'd3;
            8'd16:  decode_spc_shift = 3'd4;
            8'd32:  decode_spc_shift = 3'd5;
            8'd64:  decode_spc_shift = 3'd6;
            8'd128: decode_spc_shift = 3'd7;
            default:decode_spc_shift = 3'd0;
        endcase
    end
endfunction

wire spc_is_valid = (sectors_per_cluster == 8'd1)   ||
                    (sectors_per_cluster == 8'd2)   ||
                    (sectors_per_cluster == 8'd4)   ||
                    (sectors_per_cluster == 8'd8)   ||
                    (sectors_per_cluster == 8'd16)  ||
                    (sectors_per_cluster == 8'd32)  ||
                    (sectors_per_cluster == 8'd64)  ||
                    (sectors_per_cluster == 8'd128);

always @* begin
    sectors_per_cluster_shift = decode_spc_shift(sectors_per_cluster);
    cluster_sector_offset = ({7'd0, (current_directory_cluster - 28'd2)} <<
                             sectors_per_cluster_shift);
    directory_lba_ext = {4'd0, data_start_lba} +
                        {1'd0, cluster_sector_offset} +
                        {28'd0, directory_sector_index};
    fat_lba_ext = {1'b0, fat_start_lba} + {12'd0, current_directory_cluster[27:7]};
    volume_end_lba_ext = {1'b0, volume_start_lba} + {1'b0, volume_sector_count};
end

fat32_dir_sector_scan u_directory_sector_scan (
    .clk              (clk),
    .rst              (rst),
    .start            (scan_start),
    .target_sfn       (target_sfn_latched),
    .byte_valid       (sd_sec_read_data_valid),
    .byte_data        (sd_sec_read_data),
    .sector_end       (sd_sec_read_end),
    .busy             (scan_busy),
    .scan_done        (scan_done),
    .match_found      (scan_match_found),
    .end_of_directory (scan_end_of_directory),
    .first_cluster    (scan_first_cluster),
    .file_size        (scan_file_size)
);

always @(posedge clk) begin
    if (rst) begin
        state                    <= ST_IDLE;
        timeout_counter          <= 32'd0;
        target_sfn_latched       <= 88'd0;
        current_directory_cluster<= 28'd0;
        directory_sector_index   <= 8'd0;
        visited_cluster_count    <= 32'd0;
        fat_byte_index           <= 9'd0;
        stream_byte_index        <= 9'd0;
        fat_entry_word           <= 32'd0;
        fat_byte_seen            <= 4'd0;
        directory_scan_seen      <= 1'b0;
        directory_scan_match     <= 1'b0;
        directory_scan_end       <= 1'b0;
        directory_sd_end_seen    <= 1'b0;
        directory_match_cluster  <= 28'd0;
        directory_match_size     <= 32'd0;
        scan_start               <= 1'b0;
        sd_sec_read              <= 1'b0;
        sd_sec_read_addr         <= 32'd0;
        busy                     <= 1'b0;
        done                     <= 1'b0;
        file_found               <= 1'b0;
        error_code               <= ERR_NONE;
        file_first_cluster       <= 28'd0;
        file_size                <= 32'd0;
    end else begin
        done        <= 1'b0;
        scan_start  <= 1'b0;
        sd_sec_read <= 1'b0;

        case (state)
            ST_IDLE: begin
                busy <= 1'b0;
                if (start) begin
                    if (!metadata_valid || !spc_is_valid || root_cluster < 28'd2 ||
                        volume_sector_count == 32'd0 || sectors_per_fat == 32'd0) begin
                        error_code <= ERR_METADATA;
                        file_found <= 1'b0;
                        state      <= ST_ERROR;
                    end else begin
                        busy                      <= 1'b1;
                        error_code                <= ERR_NONE;
                        file_found                <= 1'b0;
                        file_first_cluster        <= 28'd0;
                        file_size                 <= 32'd0;
                        target_sfn_latched        <= target_sfn;
                        current_directory_cluster <= root_cluster;
                        directory_sector_index    <= 8'd0;
                        visited_cluster_count     <= 32'd1;
                        state                     <= ST_DIR_SHIFT;
                    end
                end
            end

            ST_DIR_SHIFT: begin
                directory_shift_q <= decode_spc_shift(sectors_per_cluster);
                volume_end_q <= {1'b0, volume_start_lba} + {1'b0, volume_sector_count};
                state <= ST_DIR_OFFSET;
            end
            ST_DIR_OFFSET: begin
                directory_offset_q <= {7'd0, (current_directory_cluster - 28'd2)} << directory_shift_q;
                state <= ST_DIR_LBA;
            end
            ST_DIR_LBA: begin
                directory_lba_q <= {4'd0, data_start_lba} + {1'b0, directory_offset_q} + {28'd0, directory_sector_index};
                state <= ST_DIR_CHECK;
            end
            ST_DIR_CHECK: begin
                directory_lba_valid_q <= (directory_lba_q <= 36'h0_FFFF_FFFF) &&
                    ({1'b0, directory_lba_q[31:0]} >= {1'b0, volume_start_lba}) &&
                    ({1'b0, directory_lba_q[31:0]} < volume_end_q);
                state <= ST_DIR_REQ;
            end
            ST_DIR_REQ: begin
                if (!directory_lba_valid_q) begin
                    error_code <= ERR_LBA_RANGE;
                    state <= ST_ERROR;
                end else begin
                    sd_sec_read              <= 1'b1;
                    sd_sec_read_addr         <= directory_lba_q[31:0];
                    scan_start               <= 1'b1;
                    timeout_counter          <= 32'd0;
                    stream_byte_index        <= 9'd0;
                    directory_scan_seen     <= 1'b0;
                    directory_scan_match    <= 1'b0;
                    directory_scan_end      <= 1'b0;
                    directory_sd_end_seen   <= 1'b0;
                    directory_match_cluster <= 28'd0;
                    directory_match_size    <= 32'd0;
                    state                    <= ST_DIR_WAIT;
                end
            end

            ST_DIR_WAIT: begin
                if (sd_sec_read_data_valid)
                    stream_byte_index <= stream_byte_index + 9'd1;
                if (scan_done) begin
                    directory_scan_seen <= 1'b1;
                    directory_scan_match <= scan_match_found;
                    directory_scan_end <= scan_end_of_directory;
                    if (scan_match_found) begin
                        directory_match_cluster <= scan_first_cluster;
                        directory_match_size    <= scan_file_size;
                    end
                end
                if (sd_sec_read_end) directory_sd_end_seen <= 1'b1;

                if ((directory_scan_seen || scan_done) &&
                    (directory_sd_end_seen || sd_sec_read_end)) begin
                    if (directory_scan_seen ? directory_scan_match : scan_match_found) begin
                        file_first_cluster <= directory_scan_seen ? directory_match_cluster : scan_first_cluster;
                        file_size          <= directory_scan_seen ? directory_match_size : scan_file_size;
                        file_found         <= 1'b1;
                        state              <= ST_DONE;
                    end else if (directory_scan_seen ? directory_scan_end : scan_end_of_directory) begin
                        error_code <= ERR_FILE_NOT_FOUND;
                        state <= ST_ERROR;
                    end else if (directory_sector_index + 8'd1 < sectors_per_cluster) begin
                        directory_sector_index <= directory_sector_index + 8'd1;
                        state <= ST_DIR_SHIFT;
                    end else begin
                        state <= ST_FAT_PREP;
                    end
                end else if (timeout_counter >= READ_TIMEOUT_CYCLES-1) begin
                    error_code <= ERR_READ_TIMEOUT;
                    state <= ST_ERROR;
                end else begin
                    timeout_counter <= timeout_counter + 32'd1;
                end
            end

            ST_FAT_PREP: begin
                fat_lba_q <= {1'b0, fat_start_lba} + {12'd0, current_directory_cluster[27:7]};
                state <= ST_FAT_REQ;
            end
            ST_FAT_REQ: begin
                if ((fat_lba_q > 33'h0_FFFF_FFFF) ||
                    (current_directory_cluster[27:7] >= sectors_per_fat) ||
                    ({1'b0, fat_lba_q[31:0]} < {1'b0, fat_start_lba}) ||
                    ({1'b0, fat_lba_q[31:0]} >= volume_end_q)) begin
                    error_code <= ERR_FAT_BOUNDS;
                    state <= ST_ERROR;
                end else begin
                    sd_sec_read       <= 1'b1;
                    sd_sec_read_addr  <= fat_lba_q[31:0];
                    timeout_counter   <= 32'd0;
                    stream_byte_index <= 9'd0;
                    fat_byte_index    <= {current_directory_cluster[6:0], 2'b00};
                    fat_entry_word    <= 32'd0;
                    fat_byte_seen     <= 4'd0;
                    state             <= ST_FAT_WAIT;
                end
            end

            ST_FAT_WAIT: begin
                if (sd_sec_read_data_valid) begin
                    if (stream_byte_index == fat_byte_index) begin
                        fat_entry_word[7:0] <= sd_sec_read_data;
                        fat_byte_seen[0] <= 1'b1;
                    end
                    if (stream_byte_index == fat_byte_index + 9'd1) begin
                        fat_entry_word[15:8] <= sd_sec_read_data;
                        fat_byte_seen[1] <= 1'b1;
                    end
                    if (stream_byte_index == fat_byte_index + 9'd2) begin
                        fat_entry_word[23:16] <= sd_sec_read_data;
                        fat_byte_seen[2] <= 1'b1;
                    end
                    if (stream_byte_index == fat_byte_index + 9'd3) begin
                        fat_entry_word[31:24] <= sd_sec_read_data;
                        fat_byte_seen[3] <= 1'b1;
                    end
                    stream_byte_index <= stream_byte_index + 9'd1;
                end
                if (sd_sec_read_end) begin
                    state <= ST_FAT_CHECK;
                end else if (timeout_counter >= READ_TIMEOUT_CYCLES-1) begin
                    error_code <= ERR_READ_TIMEOUT;
                    state <= ST_ERROR;
                end else begin
                    timeout_counter <= timeout_counter + 32'd1;
                end
            end

            ST_FAT_CHECK: begin
                if (fat_byte_seen != 4'b1111) begin
                    error_code <= ERR_SHORT_SECTOR;
                    state <= ST_ERROR;
                end else if (fat_entry_word[27:0] >= 28'h0FFFFFF8) begin
                    error_code <= ERR_DIRECTORY_CHAIN;
                    state <= ST_ERROR;
                end else if (fat_entry_word[27:0] < 28'd2 ||
                             (fat_entry_word[27:0] >= 28'h0FFFFFF0)) begin
                    error_code <= ERR_FAT_CHAIN;
                    state <= ST_ERROR;
                end else if (visited_cluster_count >= MAX_DIRECTORY_CLUSTERS) begin
                    error_code <= ERR_CLUSTER_LIMIT;
                    state <= ST_ERROR;
                end else begin
                    current_directory_cluster <= fat_entry_word[27:0];
                    directory_sector_index    <= 8'd0;
                    visited_cluster_count     <= visited_cluster_count + 32'd1;
                    state                     <= ST_DIR_SHIFT;
                end
            end

            ST_DONE: begin
                busy  <= 1'b0;
                done  <= 1'b1;
                state <= ST_IDLE;
            end

            ST_ERROR: begin
                busy  <= 1'b0;
                done  <= 1'b1;
                state <= ST_IDLE;
            end

            default: state <= ST_IDLE;
        endcase
    end
end

endmodule
