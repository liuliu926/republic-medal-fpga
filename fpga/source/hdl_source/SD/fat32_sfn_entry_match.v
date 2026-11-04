// Match one FAT32 32-byte directory entry against an 11-byte short name.
// begin_entry must precede the first byte by at least one clock. Feed exactly
// 32 bytes in directory order using byte_valid, with arbitrary idle cycles.
// Results are single-cycle pulses when byte 31 is consumed. The caller must
// stop scanning on end_of_directory and must follow the FAT chain itself.
module fat32_sfn_entry_match (
    input wire clk,
    input wire rst,
    input wire begin_entry,
    input wire [87:0] target_sfn,
    input wire byte_valid,
    input wire [7:0] byte_data,
    output reg busy,
    output reg entry_done,
    output reg match_found,
    output reg end_of_directory,
    output reg [27:0] first_cluster,
    output reg [31:0] file_size
);
reg [5:0] index;
reg [87:0] name_shift;
reg name_matches, deleted_entry, unused_entry;
reg [7:0] attributes;
reg [15:0] cluster_hi, cluster_lo;
reg [23:0] size_lo;

always @(posedge clk) begin
    if (rst) begin
        busy <= 0; entry_done <= 0; match_found <= 0; end_of_directory <= 0;
        first_cluster <= 0; file_size <= 0; index <= 0; name_shift <= 0;
        name_matches <= 0; deleted_entry <= 0; unused_entry <= 0;
        attributes <= 0; cluster_hi <= 0; cluster_lo <= 0; size_lo <= 0;
    end else begin
        entry_done <= 0;
        match_found <= 0;
        end_of_directory <= 0;
        if (begin_entry && !busy) begin
            busy <= 1; index <= 0; name_shift <= target_sfn; name_matches <= 1;
            deleted_entry <= 0; unused_entry <= 0; attributes <= 0;
            cluster_hi <= 0; cluster_lo <= 0; size_lo <= 0;
        end else if (busy && byte_valid) begin
            if (index < 11) begin
                if (byte_data != name_shift[87:80]) name_matches <= 0;
                name_shift <= {name_shift[79:0], 8'b0};
            end
            case (index)
                0: begin deleted_entry <= (byte_data == 8'he5); unused_entry <= (byte_data == 0); end
                11: attributes <= byte_data;
                20: cluster_hi[7:0] <= byte_data;
                21: cluster_hi[15:8] <= byte_data;
                26: cluster_lo[7:0] <= byte_data;
                27: cluster_lo[15:8] <= byte_data;
                28: size_lo[7:0] <= byte_data;
                29: size_lo[15:8] <= byte_data;
                30: size_lo[23:16] <= byte_data;
                31: begin
                    busy <= 0;
                    entry_done <= 1;
                    end_of_directory <= unused_entry;
                    if (!unused_entry && !deleted_entry && name_matches &&
                        !(attributes & 8'h18) &&
                        ({cluster_hi[11:0], cluster_lo} >= 28'd2) &&
                        ({byte_data, size_lo} != 0)) begin
                        first_cluster <= {cluster_hi[11:0], cluster_lo};
                        file_size <= {byte_data, size_lo};
                        match_found <= 1;
                    end
                end
                default: ;
            endcase
            if (index != 31) index <= index + 1'b1;
        end
    end
end
endmodule
