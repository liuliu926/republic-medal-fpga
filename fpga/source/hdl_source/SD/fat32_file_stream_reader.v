// Stream a file from FAT32 by file size, following its cluster chain.
// One 512-byte sector is buffered before bytes are offered to the consumer,
// so `out_valid/out_ready` backpressure never stalls an active SPI read.
module fat32_file_stream_reader #(
    parameter integer READ_TIMEOUT_CYCLES = 100_000_000,
    parameter integer MAX_FILE_CLUSTERS = 131072
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        metadata_valid,
    input  wire [31:0] volume_start_lba,
    input  wire [31:0] volume_sector_count,
    input  wire [7:0]  sectors_per_cluster,
    input  wire [31:0] sectors_per_fat,
    input  wire [31:0] fat_start_lba,
    input  wire [31:0] data_start_lba,
    input  wire [27:0] file_first_cluster,
    input  wire [31:0] file_size,
    output reg         sd_sec_read,
    output reg  [31:0] sd_sec_read_addr,
    input  wire [7:0]  sd_sec_read_data,
    input  wire        sd_sec_read_data_valid,
    input  wire        sd_sec_read_end,
    output wire        out_valid,
    input  wire        out_ready,
    output wire [7:0]  out_data,
    output reg         busy,
    output reg         done,
    output reg         error,
    output reg  [3:0]  error_code
);

localparam [3:0] ERR_NONE          = 4'd0;
localparam [3:0] ERR_METADATA      = 4'd1;
localparam [3:0] ERR_READ_TIMEOUT  = 4'd2;
localparam [3:0] ERR_SHORT_SECTOR  = 4'd3;
localparam [3:0] ERR_FAT_BOUNDS    = 4'd4;
localparam [3:0] ERR_FAT_CHAIN     = 4'd5;
localparam [3:0] ERR_CLUSTER_LIMIT = 4'd6;
localparam [3:0] ERR_LBA_RANGE     = 4'd7;

localparam [3:0] ST_IDLE        = 4'd0;
localparam [3:0] ST_SECTOR_REQ  = 4'd1;
localparam [3:0] ST_SECTOR_WAIT = 4'd2;
localparam [3:0] ST_SECTOR_CHECK= 4'd3;
localparam [3:0] ST_EMIT        = 4'd4;
localparam [3:0] ST_FAT_REQ     = 4'd5;
localparam [3:0] ST_FAT_WAIT    = 4'd6;
localparam [3:0] ST_FAT_CHECK   = 4'd7;
localparam [3:0] ST_DONE        = 4'd8;
localparam [3:0] ST_ERROR       = 4'd9;
localparam [3:0] ST_SECTOR_SHIFT = 4'd10;
localparam [3:0] ST_SECTOR_OFFSET= 4'd11;
localparam [3:0] ST_SECTOR_LBA   = 4'd12;

reg [3:0] state;
reg [2:0] sector_shift_q;
reg [34:0] sector_offset_q;
reg [35:0] sector_lba_q;
reg [32:0] volume_end_q;
reg [7:0] sector_buffer [0:511];
reg [9:0] received_count;
reg [8:0] emit_index;
reg [9:0] emit_limit;
reg emit_is_last;
reg [31:0] remaining_bytes;
reg [31:0] timeout_counter;
reg [31:0] visited_cluster_count;
reg [27:0] current_cluster;
reg [7:0] current_sector_in_cluster;
reg [8:0] fat_byte_index;
reg [8:0] stream_byte_index;
reg [31:0] fat_entry_word;
reg [3:0] fat_byte_seen;

reg [2:0] sectors_per_cluster_shift;
reg [34:0] cluster_sector_offset;
reg [35:0] sector_lba_ext;
reg [32:0] fat_lba_ext;
reg [32:0] volume_end_lba_ext;

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

assign out_valid = (state == ST_EMIT);
assign out_data = sector_buffer[emit_index];

always @* begin
    sectors_per_cluster_shift = decode_spc_shift(sectors_per_cluster);
    cluster_sector_offset = ({7'd0, (current_cluster - 28'd2)} <<
                             sectors_per_cluster_shift);
    sector_lba_ext = {4'd0, data_start_lba} +
                     {1'd0, cluster_sector_offset} +
                     {28'd0, current_sector_in_cluster};
    fat_lba_ext = {1'b0, fat_start_lba} + {12'd0, current_cluster[27:7]};
    volume_end_lba_ext = {1'b0, volume_start_lba} + {1'b0, volume_sector_count};
end

always @(posedge clk) begin
    if (rst) begin
        state                   <= ST_IDLE;
        received_count          <= 10'd0;
        emit_index              <= 9'd0;
        emit_limit              <= 10'd0;
        emit_is_last            <= 1'b0;
        remaining_bytes         <= 32'd0;
        timeout_counter         <= 32'd0;
        visited_cluster_count   <= 32'd0;
        current_cluster         <= 28'd0;
        current_sector_in_cluster<= 8'd0;
        fat_byte_index          <= 9'd0;
        stream_byte_index       <= 9'd0;
        fat_entry_word          <= 32'd0;
        fat_byte_seen           <= 4'd0;
        sd_sec_read             <= 1'b0;
        sd_sec_read_addr        <= 32'd0;
        busy                    <= 1'b0;
        done                    <= 1'b0;
        error                   <= 1'b0;
        error_code              <= ERR_NONE;
    end else begin
        done        <= 1'b0;
        sd_sec_read <= 1'b0;

        case (state)
            ST_IDLE: begin
                busy <= 1'b0;
                if (start) begin
                    if (!metadata_valid || !spc_is_valid || file_first_cluster < 28'd2 ||
                        file_size == 32'd0 || volume_sector_count == 32'd0 ||
                        sectors_per_fat == 32'd0) begin
                        error      <= 1'b1;
                        error_code <= ERR_METADATA;
                        state      <= ST_ERROR;
                    end else begin
                        busy                     <= 1'b1;
                        error                    <= 1'b0;
                        error_code               <= ERR_NONE;
                        remaining_bytes          <= file_size;
                        current_cluster          <= file_first_cluster;
                        current_sector_in_cluster<= 8'd0;
                        visited_cluster_count    <= 32'd1;
                        state                    <= ST_SECTOR_SHIFT;
                    end
                end
            end

            ST_SECTOR_SHIFT: begin
                sector_shift_q <= decode_spc_shift(sectors_per_cluster);
                volume_end_q <= {1'b0, volume_start_lba} + {1'b0, volume_sector_count};
                state <= ST_SECTOR_OFFSET;
            end
            ST_SECTOR_OFFSET: begin
                sector_offset_q <= {7'd0, (current_cluster - 28'd2)} << sector_shift_q;
                state <= ST_SECTOR_LBA;
            end
            ST_SECTOR_LBA: begin
                sector_lba_q <= {4'd0, data_start_lba} + {1'b0, sector_offset_q} + {28'd0, current_sector_in_cluster};
                state <= ST_SECTOR_REQ;
            end
            ST_SECTOR_REQ: begin
                if ((sector_lba_q > 36'h0_FFFF_FFFF) ||
                    ({1'b0, sector_lba_q[31:0]} < {1'b0, volume_start_lba}) ||
                    ({1'b0, sector_lba_q[31:0]} >= volume_end_q)) begin
                    error_code <= ERR_LBA_RANGE;
                    state <= ST_ERROR;
                end else begin
                    sd_sec_read       <= 1'b1;
                    sd_sec_read_addr  <= sector_lba_q[31:0];
                    received_count    <= 10'd0;
                    timeout_counter   <= 32'd0;
                    state             <= ST_SECTOR_WAIT;
                end
            end

            ST_SECTOR_WAIT: begin
                if (sd_sec_read_data_valid) begin
                    if (received_count < 10'd512) begin
                        sector_buffer[received_count[8:0]] <= sd_sec_read_data;
                        received_count <= received_count + 10'd1;
                    end else begin
                        error_code <= ERR_SHORT_SECTOR;
                        state <= ST_ERROR;
                    end
                end
                if (sd_sec_read_end) begin
                    state <= ST_SECTOR_CHECK;
                end else if (timeout_counter >= READ_TIMEOUT_CYCLES-1) begin
                    error_code <= ERR_READ_TIMEOUT;
                    state <= ST_ERROR;
                end else begin
                    timeout_counter <= timeout_counter + 32'd1;
                end
            end

            ST_SECTOR_CHECK: begin
                if (received_count != 10'd512) begin
                    error_code <= ERR_SHORT_SECTOR;
                    state <= ST_ERROR;
                end else begin
                    emit_index   <= 9'd0;
                    emit_limit   <= (remaining_bytes >= 32'd512) ? 10'd512 : remaining_bytes[9:0];
                    emit_is_last <= (remaining_bytes <= 32'd512);
                    state        <= ST_EMIT;
                end
            end

            ST_EMIT: begin
                if (out_ready) begin
                    remaining_bytes <= remaining_bytes - 32'd1;
                    if ({1'b0, emit_index} + 10'd1 >= emit_limit) begin
                        if (emit_is_last) begin
                            state <= ST_DONE;
                        end else if (current_sector_in_cluster + 8'd1 < sectors_per_cluster) begin
                            current_sector_in_cluster <= current_sector_in_cluster + 8'd1;
                            state <= ST_SECTOR_SHIFT;
                        end else begin
                            state <= ST_FAT_REQ;
                        end
                    end else begin
                        emit_index <= emit_index + 9'd1;
                    end
                end
            end

            ST_FAT_REQ: begin
                if ((fat_lba_ext > 33'h0_FFFF_FFFF) ||
                    (current_cluster[27:7] >= sectors_per_fat) ||
                    ({1'b0, fat_lba_ext[31:0]} < {1'b0, fat_start_lba}) ||
                    ({1'b0, fat_lba_ext[31:0]} >= volume_end_lba_ext)) begin
                    error_code <= ERR_FAT_BOUNDS;
                    state <= ST_ERROR;
                end else begin
                    sd_sec_read       <= 1'b1;
                    sd_sec_read_addr  <= fat_lba_ext[31:0];
                    timeout_counter   <= 32'd0;
                    stream_byte_index <= 9'd0;
                    fat_byte_index    <= {current_cluster[6:0], 2'b00};
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
                end else if (fat_entry_word[27:0] < 28'd2 ||
                             fat_entry_word[27:0] >= 28'h0FFFFFF0) begin
                    error_code <= ERR_FAT_CHAIN;
                    state <= ST_ERROR;
                end else if (visited_cluster_count >= MAX_FILE_CLUSTERS) begin
                    error_code <= ERR_CLUSTER_LIMIT;
                    state <= ST_ERROR;
                end else begin
                    current_cluster           <= fat_entry_word[27:0];
                    current_sector_in_cluster <= 8'd0;
                    visited_cluster_count     <= visited_cluster_count + 32'd1;
                    state                     <= ST_SECTOR_SHIFT;
                end
            end

            ST_DONE: begin
                busy  <= 1'b0;
                done  <= 1'b1;
                state <= ST_IDLE;
            end

            ST_ERROR: begin
                busy  <= 1'b0;
                error <= 1'b1;
                done  <= 1'b1;
                state <= ST_IDLE;
            end

            default: state <= ST_IDLE;
        endcase
    end
end

endmodule
