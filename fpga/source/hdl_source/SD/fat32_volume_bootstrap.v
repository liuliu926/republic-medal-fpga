// Bootstrap FAT32 volume metadata through the existing one-sector SD reader.
// Reads LBA 0 as MBR, selects a FAT32 primary partition, then reads that
// partition's volume boot record and reports its FAT/data layout.
module fat32_volume_bootstrap #(
    parameter integer READ_TIMEOUT_CYCLES = 100_000_000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        sd_init_done,
    output reg         sd_sec_read,
    output reg  [31:0] sd_sec_read_addr,
    input  wire [7:0]  sd_sec_read_data,
    input  wire        sd_sec_read_data_valid,
    input  wire        sd_sec_read_end,
    output reg         busy,
    output reg         done,
    output reg         metadata_valid,
    output reg  [3:0]  error_code,
    output reg  [1:0]  partition_index,
    output reg  [7:0]  partition_type,
    output reg  [31:0] volume_start_lba,
    output reg  [31:0] volume_sector_count,
    output wire [7:0]  sectors_per_cluster,
    output wire [15:0] reserved_sectors,
    output wire [7:0]  fat_count,
    output wire [31:0] sectors_per_fat,
    output wire [31:0] total_sectors,
    output wire [27:0] root_cluster,
    output wire [31:0] fat_start_lba,
    output wire [31:0] data_start_lba,
    output wire [3:0]  debug_bpb_error,
    output wire [8:0]  debug_bpb_offset
);

localparam [3:0] ERR_NONE           = 4'd0;
localparam [3:0] ERR_MBR_SIGNATURE  = 4'd1;
localparam [3:0] ERR_NO_FAT32       = 4'd2;
localparam [3:0] ERR_PARTITION_RANGE= 4'd3;
localparam [3:0] ERR_BPB_SIGNATURE  = 4'd4;
localparam [3:0] ERR_BPB_FORMAT     = 4'd5;
localparam [3:0] ERR_BPB_RANGE      = 4'd6;
localparam [3:0] ERR_READ_TIMEOUT   = 4'd7;
localparam [3:0] ERR_MBR_SHORT      = 4'd8;
localparam [3:0] ERR_BPB_SHORT      = 4'd9;

localparam [2:0] ST_IDLE      = 3'd0;
localparam [2:0] ST_MBR_REQ   = 3'd1;
localparam [2:0] ST_MBR_WAIT  = 3'd2;
localparam [2:0] ST_VBR_REQ   = 3'd3;
localparam [2:0] ST_VBR_WAIT  = 3'd4;
localparam [2:0] ST_DONE      = 3'd5;
localparam [2:0] ST_ERROR     = 3'd6;

reg [2:0] state;
reg [31:0] wait_counter;
reg started;
reg mbr_parse_seen;
reg mbr_parse_ok;
reg mbr_read_seen;
reg bpb_parse_seen;
reg bpb_parse_ok;
reg bpb_read_seen;

wire mbr_busy;
wire mbr_done;
wire mbr_valid;
wire [3:0] mbr_error;
wire [1:0] mbr_partition_index;
wire [7:0] mbr_partition_type;
wire [31:0] mbr_partition_start;
wire [31:0] mbr_partition_sectors;

wire bpb_busy;
wire bpb_done;
wire bpb_valid;
wire [3:0] bpb_error;
wire [7:0] bpb_sectors_per_cluster;
wire [15:0] bpb_reserved_sectors;
wire [7:0] bpb_fat_count;
wire [31:0] bpb_sectors_per_fat;
wire [31:0] bpb_total_sectors;
wire [27:0] bpb_root_cluster;
wire [31:0] bpb_fat_start_lba;
wire [31:0] bpb_data_start_lba;

reg mbr_start;
reg bpb_start;

assign sectors_per_cluster = bpb_sectors_per_cluster;
assign reserved_sectors    = bpb_reserved_sectors;
assign fat_count           = bpb_fat_count;
assign sectors_per_fat     = bpb_sectors_per_fat;
assign total_sectors        = bpb_total_sectors;
assign root_cluster         = bpb_root_cluster;
assign fat_start_lba        = bpb_fat_start_lba;
assign data_start_lba       = bpb_data_start_lba;
assign debug_bpb_error      = bpb_error;

fat32_mbr_partition_scan u_mbr_scan (
    .clk                   (clk),
    .rst                   (rst),
    .start                 (mbr_start),
    .byte_valid            (sd_sec_read_data_valid),
    .byte_data             (sd_sec_read_data),
    .sector_end            (sd_sec_read_end),
    .busy                  (mbr_busy),
    .done                  (mbr_done),
    .partition_valid       (mbr_valid),
    .error_code            (mbr_error),
    .partition_index       (mbr_partition_index),
    .partition_type        (mbr_partition_type),
    .partition_start_lba   (mbr_partition_start),
    .partition_sector_count(mbr_partition_sectors)
);

fat32_bpb_parser u_bpb_parse (
    .clk                (clk),
    .rst                (rst),
    .start              (bpb_start),
    .volume_start_lba   (volume_start_lba),
    .byte_valid         (sd_sec_read_data_valid),
    .byte_data          (sd_sec_read_data),
    .sector_end         (sd_sec_read_end),
    .busy               (bpb_busy),
    .done               (bpb_done),
    .bpb_valid          (bpb_valid),
    .error_code         (bpb_error),
    .sectors_per_cluster(bpb_sectors_per_cluster),
    .reserved_sectors   (bpb_reserved_sectors),
    .fat_count          (bpb_fat_count),
    .sectors_per_fat    (bpb_sectors_per_fat),
    .total_sectors      (bpb_total_sectors),
    .root_cluster       (bpb_root_cluster),
    .fat_start_lba      (bpb_fat_start_lba),
    .data_start_lba     (bpb_data_start_lba),
    .debug_byte_offset  (debug_bpb_offset)
);

always @(posedge clk) begin
    if (rst) begin
        state                 <= ST_IDLE;
        wait_counter          <= 32'd0;
        started               <= 1'b0;
        mbr_start             <= 1'b0;
        bpb_start             <= 1'b0;
        sd_sec_read           <= 1'b0;
        sd_sec_read_addr      <= 32'd0;
        busy                  <= 1'b0;
        done                  <= 1'b0;
        metadata_valid        <= 1'b0;
        error_code            <= ERR_NONE;
        partition_index       <= 2'd0;
        partition_type        <= 8'd0;
        volume_start_lba      <= 32'd0;
        volume_sector_count   <= 32'd0;
        mbr_parse_seen        <= 1'b0;
        mbr_parse_ok          <= 1'b0;
        mbr_read_seen         <= 1'b0;
        bpb_parse_seen        <= 1'b0;
        bpb_parse_ok          <= 1'b0;
        bpb_read_seen         <= 1'b0;
    end else begin
        done        <= 1'b0;
        mbr_start   <= 1'b0;
        bpb_start   <= 1'b0;
        sd_sec_read <= 1'b0;

        case (state)
            ST_IDLE: begin
                busy <= 1'b0;
                if (sd_init_done && !started) begin
                    started          <= 1'b1;
                    busy             <= 1'b1;
                    metadata_valid   <= 1'b0;
                    error_code       <= ERR_NONE;
                    state            <= ST_MBR_REQ;
                end
            end

            ST_MBR_REQ: begin
                sd_sec_read      <= 1'b1;
                sd_sec_read_addr <= 32'd0;
                mbr_start        <= 1'b1;
                wait_counter     <= 32'd0;
                mbr_parse_seen   <= 1'b0;
                mbr_parse_ok     <= 1'b0;
                mbr_read_seen    <= 1'b0;
                state            <= ST_MBR_WAIT;
            end

            ST_MBR_WAIT: begin
                if (mbr_done) begin
                    mbr_parse_seen <= 1'b1;
                    mbr_parse_ok   <= mbr_valid;
                    if (mbr_valid) begin
                        partition_index     <= mbr_partition_index;
                        partition_type      <= mbr_partition_type;
                        volume_start_lba    <= mbr_partition_start;
                        volume_sector_count <= mbr_partition_sectors;
                    end
                end
                if (sd_sec_read_end) mbr_read_seen <= 1'b1;

                if ((mbr_parse_seen || mbr_done) && (mbr_read_seen || sd_sec_read_end)) begin
                    if (mbr_parse_seen ? mbr_parse_ok : mbr_valid) begin
                        state <= ST_VBR_REQ;
                    end else begin
                        error_code <= (mbr_error == 4'd1) ? ERR_MBR_SHORT :
                                      (mbr_error == 4'd2) ? ERR_MBR_SIGNATURE :
                                      (mbr_error == 4'd4) ? ERR_PARTITION_RANGE : ERR_NO_FAT32;
                        state <= ST_ERROR;
                    end
                end else if (wait_counter >= READ_TIMEOUT_CYCLES-1) begin
                    error_code <= ERR_READ_TIMEOUT;
                    state <= ST_ERROR;
                end else begin
                    wait_counter <= wait_counter + 32'd1;
                end
            end

            ST_VBR_REQ: begin
                sd_sec_read      <= 1'b1;
                sd_sec_read_addr <= volume_start_lba;
                bpb_start        <= 1'b1;
                wait_counter     <= 32'd0;
                bpb_parse_seen   <= 1'b0;
                bpb_parse_ok     <= 1'b0;
                bpb_read_seen    <= 1'b0;
                state            <= ST_VBR_WAIT;
            end

            ST_VBR_WAIT: begin
                if (bpb_done) begin
                    bpb_parse_seen <= 1'b1;
                    bpb_parse_ok   <= bpb_valid;
                end
                if (sd_sec_read_end) bpb_read_seen <= 1'b1;

                if ((bpb_parse_seen || bpb_done) && (bpb_read_seen || sd_sec_read_end)) begin
                    if (bpb_parse_seen ? bpb_parse_ok : bpb_valid) begin
                        metadata_valid <= 1'b1;
                        error_code     <= ERR_NONE;
                        state          <= ST_DONE;
                    end else begin
                        error_code <= (bpb_error == 4'd1) ? ERR_BPB_SHORT :
                                      (bpb_error == 4'd2) ? ERR_BPB_SIGNATURE :
                                      (bpb_error == 4'd7) ? ERR_BPB_RANGE : ERR_BPB_FORMAT;
                        state <= ST_ERROR;
                    end
                end else if (wait_counter >= READ_TIMEOUT_CYCLES-1) begin
                    error_code <= ERR_READ_TIMEOUT;
                    state <= ST_ERROR;
                end else begin
                    wait_counter <= wait_counter + 32'd1;
                end
            end

            ST_DONE: begin
                busy  <= 1'b0;
                done  <= 1'b1;
                state <= ST_IDLE;
            end

            ST_ERROR: begin
                busy           <= 1'b0;
                metadata_valid <= 1'b0;
                done           <= 1'b1;
                state          <= ST_IDLE;
            end

            default: begin
                state <= ST_IDLE;
            end
        endcase
    end
end

endmodule
