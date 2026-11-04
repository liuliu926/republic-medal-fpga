// Parse the BPB/extended BPB of one FAT32 volume boot sector.
// The caller is responsible for locating the volume start LBA (for example,
// from the MBR partition table) and streaming the 512-byte sector in order.
// `start` must be asserted at least one cycle before byte offset zero.
module fat32_bpb_parser (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [31:0] volume_start_lba,
    input  wire        byte_valid,
    input  wire [7:0]  byte_data,
    input  wire        sector_end,
    output reg         busy,
    output reg         done,
    output reg         bpb_valid,
    output reg  [3:0]  error_code,
    output reg  [7:0]  sectors_per_cluster,
    output reg  [15:0] reserved_sectors,
    output reg  [7:0]  fat_count,
    output reg  [31:0] sectors_per_fat,
    output reg  [31:0] total_sectors,
    output reg  [27:0] root_cluster,
    output reg  [31:0] fat_start_lba,
    output reg  [31:0] data_start_lba,
    output wire [8:0] debug_byte_offset
);

localparam [3:0] ERR_NONE       = 4'd0;
localparam [3:0] ERR_SHORT      = 4'd1;
localparam [3:0] ERR_SIGNATURE  = 4'd2;
localparam [3:0] ERR_BPS        = 4'd3;
localparam [3:0] ERR_CLUSTER    = 4'd4;
localparam [3:0] ERR_LAYOUT     = 4'd5;
localparam [3:0] ERR_ROOT       = 4'd6;
localparam [3:0] ERR_RANGE      = 4'd7;

reg [8:0] byte_offset;
assign debug_byte_offset = byte_offset;
reg [31:0] volume_start_lba_latched;
reg [15:0] bytes_per_sector;
reg [15:0] reserved_sectors_reg;
reg [7:0]  fat_count_reg;
reg [15:0] root_entry_count;
reg [15:0] total_sectors_16;
reg [15:0] sectors_per_fat_16;
reg [31:0] total_sectors_32;
reg [31:0] sectors_per_fat_32;
reg [31:0] root_cluster_reg;
reg [7:0]  signature_lo;

reg [32:0] fat_span_ext;
reg [32:0] data_offset_ext;
reg [32:0] data_start_ext;
reg [31:0] total_sectors_candidate;
reg [31:0] sectors_per_fat_candidate;
reg [32:0] fat_span_candidate;
reg [32:0] data_offset_candidate;
reg [32:0] data_start_candidate;
reg [32:0] volume_end_candidate;
reg range_ok;

wire spc_is_power_of_two = (sectors_per_cluster != 8'd0) &&
                           ((sectors_per_cluster & (sectors_per_cluster - 8'd1)) == 8'd0);

// All geometry fields have arrived by byte 47, whereas validation is at
// byte 511. Register each stage well before then; invalid FAT counts are
// rejected separately below.
always @(posedge clk) begin
    fat_span_candidate <= fat_count_reg == 8'd1 ? {1'b0, sectors_per_fat_32}
                                                : {sectors_per_fat_32, 1'b0};
    data_offset_candidate <= {17'd0, reserved_sectors_reg} + fat_span_candidate;
    data_start_candidate <= {1'b0, volume_start_lba_latched} + data_offset_candidate;
    volume_end_candidate <= {1'b0, volume_start_lba_latched} + {1'b0, total_sectors_32};
    range_ok <= (data_offset_candidate < {1'b0, total_sectors_32}) &&
                !data_start_candidate[32] && !volume_end_candidate[32];
end

always @(posedge clk) begin
    if (rst) begin
        byte_offset               <= 9'd0;
        volume_start_lba_latched  <= 32'd0;
        bytes_per_sector           <= 16'd0;
        sectors_per_cluster        <= 8'd0;
        reserved_sectors_reg       <= 16'd0;
        reserved_sectors           <= 16'd0;
        fat_count_reg              <= 8'd0;
        fat_count                  <= 8'd0;
        root_entry_count           <= 16'd0;
        total_sectors_16           <= 16'd0;
        sectors_per_fat_16         <= 16'd0;
        total_sectors_32           <= 32'd0;
        sectors_per_fat_32         <= 32'd0;
        root_cluster_reg           <= 32'd0;
        root_cluster               <= 28'd0;
        signature_lo               <= 8'd0;
        sectors_per_fat            <= 32'd0;
        total_sectors              <= 32'd0;
        fat_start_lba              <= 32'd0;
        data_start_lba             <= 32'd0;
        fat_span_ext               <= 33'd0;
        data_offset_ext            <= 33'd0;
        data_start_ext             <= 33'd0;
        total_sectors_candidate    <= 32'd0;
        sectors_per_fat_candidate  <= 32'd0;
        busy                       <= 1'b0;
        done                       <= 1'b0;
        bpb_valid                  <= 1'b0;
        error_code                 <= ERR_NONE;
    end else begin
        done <= 1'b0;

        if (start && !busy) begin
            byte_offset              <= 9'd0;
            volume_start_lba_latched <= volume_start_lba;
            bytes_per_sector          <= 16'd0;
            sectors_per_cluster       <= 8'd0;
            reserved_sectors_reg      <= 16'd0;
            fat_count_reg             <= 8'd0;
            root_entry_count          <= 16'd0;
            total_sectors_16          <= 16'd0;
            sectors_per_fat_16        <= 16'd0;
            total_sectors_32          <= 32'd0;
            sectors_per_fat_32        <= 32'd0;
            root_cluster_reg          <= 32'd0;
            signature_lo              <= 8'd0;
            busy                      <= 1'b1;
            bpb_valid                 <= 1'b0;
            error_code                <= ERR_NONE;
        end else if (busy && byte_valid) begin
            case (byte_offset)
                9'd11: bytes_per_sector[7:0]    <= byte_data;
                9'd12: bytes_per_sector[15:8]   <= byte_data;
                9'd13: sectors_per_cluster       <= byte_data;
                9'd14: reserved_sectors_reg[7:0] <= byte_data;
                9'd15: reserved_sectors_reg[15:8]<= byte_data;
                9'd16: fat_count_reg             <= byte_data;
                9'd17: root_entry_count[7:0]     <= byte_data;
                9'd18: root_entry_count[15:8]    <= byte_data;
                9'd19: total_sectors_16[7:0]     <= byte_data;
                9'd20: total_sectors_16[15:8]    <= byte_data;
                9'd22: sectors_per_fat_16[7:0]  <= byte_data;
                9'd23: sectors_per_fat_16[15:8] <= byte_data;
                9'd32: total_sectors_32[7:0]    <= byte_data;
                9'd33: total_sectors_32[15:8]   <= byte_data;
                9'd34: total_sectors_32[23:16]  <= byte_data;
                9'd35: total_sectors_32[31:24]  <= byte_data;
                9'd36: sectors_per_fat_32[7:0]  <= byte_data;
                9'd37: sectors_per_fat_32[15:8] <= byte_data;
                9'd38: sectors_per_fat_32[23:16]<= byte_data;
                9'd39: sectors_per_fat_32[31:24]<= byte_data;
                9'd44: root_cluster_reg[7:0]    <= byte_data;
                9'd45: root_cluster_reg[15:8]   <= byte_data;
                9'd46: root_cluster_reg[23:16]  <= byte_data;
                9'd47: root_cluster_reg[31:24]  <= byte_data;
                9'd510: signature_lo             <= byte_data;
                9'd511: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    if (sector_end && (byte_data != 8'hAA)) begin
                        bpb_valid <= 1'b0;
                        error_code <= ERR_SIGNATURE;
                    end else if (signature_lo != 8'h55 || byte_data != 8'hAA) begin
                        bpb_valid <= 1'b0;
                        error_code <= ERR_SIGNATURE;
                    end else if (bytes_per_sector != 16'd512) begin
                        bpb_valid <= 1'b0;
                        error_code <= ERR_BPS;
                    end else if (!spc_is_power_of_two || sectors_per_cluster > 8'd128) begin
                        bpb_valid <= 1'b0;
                        error_code <= ERR_CLUSTER;
                    end else if (reserved_sectors_reg == 16'd0 ||
                                 (fat_count_reg != 8'd1 && fat_count_reg != 8'd2) ||
                                 root_entry_count != 16'd0 ||
                                 sectors_per_fat_16 != 16'd0 ||
                                 sectors_per_fat_32 == 32'd0 ||
                                 total_sectors_16 != 16'd0 || total_sectors_32 == 32'd0) begin
                        bpb_valid <= 1'b0;
                        error_code <= ERR_LAYOUT;
                    end else if (root_cluster_reg[27:0] < 28'd2 ||
                                 root_cluster_reg[31:28] != 4'd0) begin
                        bpb_valid <= 1'b0;
                        error_code <= ERR_ROOT;
                    end else begin
                        if (!range_ok) begin
                            bpb_valid <= 1'b0;
                            error_code <= ERR_RANGE;
                        end else begin
                            total_sectors_candidate   <= total_sectors_32;
                            sectors_per_fat_candidate <= sectors_per_fat_32;
                            fat_span_ext               <= fat_span_candidate;
                            data_offset_ext            <= data_offset_candidate;
                            data_start_ext             <= data_start_candidate;
                            sectors_per_fat            <= sectors_per_fat_32;
                            total_sectors              <= total_sectors_32;
                            reserved_sectors           <= reserved_sectors_reg;
                            fat_count                  <= fat_count_reg;
                            root_cluster               <= root_cluster_reg[27:0];
                            fat_start_lba              <= volume_start_lba_latched + reserved_sectors_reg;
                            data_start_lba             <= data_start_candidate[31:0];
                            bpb_valid                  <= 1'b1;
                            error_code                 <= ERR_NONE;
                        end
                    end
                end
                default: ;
            endcase

            if (byte_offset != 9'd511) begin
                byte_offset <= byte_offset + 9'd1;
            end
            if (sector_end && byte_offset != 9'd511) begin
                busy       <= 1'b0;
                done       <= 1'b1;
                bpb_valid  <= 1'b0;
                error_code <= ERR_SHORT;
            end
        end else if (busy && sector_end) begin
            busy       <= 1'b0;
            done       <= 1'b1;
            bpb_valid  <= 1'b0;
            error_code <= ERR_SHORT;
        end
    end
end

endmodule
