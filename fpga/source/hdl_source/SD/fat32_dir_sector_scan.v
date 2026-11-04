// Search one 512-byte FAT32 directory sector for an 8.3 short filename.
// The caller supplies bytes in on-card order and handles partition offsets,
// root-directory cluster traversal, and FAT-chain lookup between sectors.
// `start` must be asserted before the first byte. Assert `sector_end` with
// on the final valid byte or on a later cycle with no valid data.
// `target_sfn` uses the on-disk 11-byte
// 8.3 representation (8 name bytes followed by 3 extension bytes, padded
// with spaces), most-significant byte first.
module fat32_dir_sector_scan (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [87:0] target_sfn,
    input  wire        byte_valid,
    input  wire [7:0]  byte_data,
    input  wire        sector_end,
    output reg         busy,
    output reg         scan_done,
    output reg         match_found,
    output reg         end_of_directory,
    output reg  [27:0] first_cluster,
    output reg  [31:0] file_size
);

reg [8:0] byte_offset;
reg [87:0] target_shift;
reg name_matches;
reg deleted_entry;
reg [7:0] attributes;
reg [15:0] cluster_hi;
reg [15:0] cluster_lo;
reg [31:0] size_bytes;

wire [4:0] entry_offset = byte_offset[4:0];
wire [27:0] parsed_cluster = {cluster_hi[11:0], cluster_lo};

always @(posedge clk) begin
    if (rst) begin
        byte_offset      <= 9'd0;
        target_shift     <= 88'd0;
        name_matches     <= 1'b0;
        deleted_entry    <= 1'b0;
        attributes       <= 8'd0;
        cluster_hi       <= 16'd0;
        cluster_lo       <= 16'd0;
        size_bytes       <= 32'd0;
        busy             <= 1'b0;
        scan_done        <= 1'b0;
        match_found      <= 1'b0;
        end_of_directory <= 1'b0;
        first_cluster    <= 28'd0;
        file_size        <= 32'd0;
    end else begin
        scan_done        <= 1'b0;
        match_found      <= 1'b0;
        end_of_directory <= 1'b0;

        if (start && !busy) begin
            byte_offset   <= 9'd0;
            target_shift  <= target_sfn;
            name_matches  <= 1'b1;
            deleted_entry <= 1'b0;
            attributes    <= 8'd0;
            cluster_hi    <= 16'd0;
            cluster_lo    <= 16'd0;
            size_bytes    <= 32'd0;
            busy          <= 1'b1;
        end else if (busy && byte_valid) begin
            if (entry_offset == 5'd0) begin
                // Each 32-byte entry is an independent comparison.
                deleted_entry <= (byte_data == 8'hE5);
                name_matches  <= (byte_data == target_sfn[87:80]);
                target_shift  <= {target_sfn[79:0], 8'd0};
                attributes    <= 8'd0;
                cluster_hi    <= 16'd0;
                cluster_lo    <= 16'd0;
                size_bytes    <= 32'd0;
                if (byte_data == 8'h00) begin
                    busy             <= 1'b0;
                    scan_done        <= 1'b1;
                    end_of_directory <= 1'b1;
                end
            end else begin
                if (entry_offset >= 5'd1 && entry_offset < 5'd11) begin
                    if (byte_data != target_shift[87:80]) name_matches <= 1'b0;
                    target_shift <= {target_shift[79:0], 8'd0};
                end
                case (entry_offset)
                    5'd11: attributes <= byte_data;
                    5'd20: cluster_hi[7:0]  <= byte_data;
                    5'd21: cluster_hi[15:8] <= byte_data;
                    5'd26: cluster_lo[7:0]  <= byte_data;
                    5'd27: cluster_lo[15:8] <= byte_data;
                    5'd28: size_bytes[7:0]   <= byte_data;
                    5'd29: size_bytes[15:8]  <= byte_data;
                    5'd30: size_bytes[23:16] <= byte_data;
                    5'd31: begin
                        size_bytes[31:24] <= byte_data;
                        if (!deleted_entry && name_matches &&
                            !(attributes & 8'h18) &&
                            (parsed_cluster >= 28'd2) &&
                            ({byte_data, size_bytes[23:0]} != 32'd0)) begin
                            first_cluster <= parsed_cluster;
                            file_size     <= {byte_data, size_bytes[23:0]};
                            match_found   <= 1'b1;
                            scan_done     <= 1'b1;
                            busy          <= 1'b0;
                        end
                    end
                    default: ;
                endcase
            end

            if (byte_offset == 9'd511) begin
                busy        <= 1'b0;
                scan_done   <= 1'b1;
                byte_offset <= 9'd0;
                target_shift <= target_sfn;
            end else begin
                byte_offset <= byte_offset + 9'd1;
            end

            // If asserted with the final valid byte, consume that byte first
            // and then end this sector. This also covers partial sectors.
            if (sector_end) begin
                busy      <= 1'b0;
                scan_done <= 1'b1;
            end
        end else if (busy && sector_end) begin
            busy      <= 1'b0;
            scan_done <= 1'b1;
        end
    end
end

endmodule
