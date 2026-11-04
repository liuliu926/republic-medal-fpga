// Select the first primary MBR partition with a FAT32 partition type.
// Streams one 512-byte MBR sector in disk byte order; does not read the volume.
module fat32_mbr_partition_scan (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        byte_valid,
    input  wire [7:0]  byte_data,
    input  wire        sector_end,
    output reg         busy,
    output reg         done,
    output reg         partition_valid,
    output reg  [3:0]  error_code,
    output reg  [1:0]  partition_index,
    output reg  [7:0]  partition_type,
    output reg  [31:0] partition_start_lba,
    output reg  [31:0] partition_sector_count
);

localparam [3:0] ERR_NONE      = 4'd0;
localparam [3:0] ERR_SHORT     = 4'd1;
localparam [3:0] ERR_SIGNATURE = 4'd2;
localparam [3:0] ERR_NO_FAT32  = 4'd3;
localparam [3:0] ERR_RANGE     = 4'd4;

reg [8:0] byte_offset;
reg [7:0] signature_lo;
reg [7:0] current_type;
reg [31:0] current_start;
reg [31:0] current_size;
reg found_candidate;
reg saw_fat32_candidate;
reg [1:0] candidate_index;
reg [7:0] candidate_type;
reg [31:0] candidate_start;
reg [31:0] candidate_size;
reg candidate_range_ok;
reg [32:0] partition_end_exclusive;

wire [8:0] entry_offset = byte_offset - 9'd446;
wire [1:0] entry_number = entry_offset[5:4];
wire [3:0] field_offset = entry_offset[3:0];
wire current_type_is_fat32 = (current_type == 8'h0B) ||
                             (current_type == 8'h0C) ||
                             (current_type == 8'h1B) ||
                             (current_type == 8'h1C);

always @(posedge clk) begin
    if (rst) begin
        byte_offset           <= 9'd0;
        signature_lo          <= 8'd0;
        current_type          <= 8'd0;
        current_start         <= 32'd0;
        current_size          <= 32'd0;
        found_candidate       <= 1'b0;
        saw_fat32_candidate   <= 1'b0;
        candidate_index       <= 2'd0;
        candidate_type        <= 8'd0;
        candidate_start       <= 32'd0;
        candidate_size        <= 32'd0;
        candidate_range_ok    <= 1'b0;
        partition_end_exclusive <= 33'd0;
        busy                  <= 1'b0;
        done                  <= 1'b0;
        partition_valid       <= 1'b0;
        error_code            <= ERR_NONE;
        partition_index       <= 2'd0;
        partition_type        <= 8'd0;
        partition_start_lba   <= 32'd0;
        partition_sector_count<= 32'd0;
    end else begin
        done <= 1'b0;

        if (start && !busy) begin
            byte_offset             <= 9'd0;
            signature_lo            <= 8'd0;
            current_type            <= 8'd0;
            current_start           <= 32'd0;
            current_size            <= 32'd0;
            found_candidate         <= 1'b0;
            saw_fat32_candidate     <= 1'b0;
            candidate_index         <= 2'd0;
            candidate_type          <= 8'd0;
            candidate_start         <= 32'd0;
            candidate_size          <= 32'd0;
            candidate_range_ok      <= 1'b0;
            busy                    <= 1'b1;
            partition_valid         <= 1'b0;
            error_code              <= ERR_NONE;
        end else if (busy && byte_valid) begin
            if (byte_offset == 9'd510) signature_lo <= byte_data;

            if (byte_offset >= 9'd446 && byte_offset <= 9'd509) begin
                if (field_offset == 4'd0) begin
                    current_type  <= 8'd0;
                    current_start <= 32'd0;
                    current_size  <= 32'd0;
                end

                case (field_offset)
                    4'd4: current_type <= byte_data;
                    4'd8: current_start[7:0]   <= byte_data;
                    4'd9: current_start[15:8]  <= byte_data;
                    4'd10: current_start[23:16] <= byte_data;
                    4'd11: current_start[31:24] <= byte_data;
                    4'd12: current_size[7:0]   <= byte_data;
                    4'd13: current_size[15:8]  <= byte_data;
                    4'd14: current_size[23:16] <= byte_data;
                    4'd15: begin
                        current_size[31:24] <= byte_data;
                        partition_end_exclusive = {1'b0, current_start} +
                                                  {1'b0, byte_data, current_size[23:0]};
                        if (current_type_is_fat32)
                            saw_fat32_candidate <= 1'b1;
                        if (!found_candidate && current_type_is_fat32 &&
                            current_start != 32'd0 &&
                            {byte_data, current_size[23:0]} != 32'd0 &&
                            partition_end_exclusive <= 33'h1_0000_0000) begin
                            found_candidate    <= 1'b1;
                            candidate_index    <= entry_number;
                            candidate_type     <= current_type;
                            candidate_start    <= current_start;
                            candidate_size     <= {byte_data, current_size[23:0]};
                            candidate_range_ok <= 1'b1;
                        end
                    end
                    default: ;
                endcase
            end

            if (byte_offset == 9'd511) begin
                busy <= 1'b0;
                done <= 1'b1;
                if (signature_lo != 8'h55 || byte_data != 8'hAA) begin
                    partition_valid <= 1'b0;
                    error_code <= ERR_SIGNATURE;
                end else if (!found_candidate && saw_fat32_candidate) begin
                    partition_valid <= 1'b0;
                    error_code <= ERR_RANGE;
                end else if (!found_candidate) begin
                    partition_valid <= 1'b0;
                    error_code <= ERR_NO_FAT32;
                end else if (!candidate_range_ok) begin
                    partition_valid <= 1'b0;
                    error_code <= ERR_RANGE;
                end else begin
                    partition_valid        <= 1'b1;
                    error_code              <= ERR_NONE;
                    partition_index         <= candidate_index;
                    partition_type          <= candidate_type;
                    partition_start_lba     <= candidate_start;
                    partition_sector_count  <= candidate_size;
                end
            end else begin
                byte_offset <= byte_offset + 9'd1;
                if (sector_end) begin
                    busy           <= 1'b0;
                    done           <= 1'b1;
                    partition_valid <= 1'b0;
                    error_code     <= ERR_SHORT;
                end
            end
        end else if (busy && sector_end) begin
            busy            <= 1'b0;
            done            <= 1'b1;
            partition_valid<= 1'b0;
            error_code      <= ERR_SHORT;
        end
    end
end

endmodule
