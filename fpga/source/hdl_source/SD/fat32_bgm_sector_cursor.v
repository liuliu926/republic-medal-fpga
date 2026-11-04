`timescale 1ns/1ps
// Bounded-memory PCM cursor. File discovery is shared with the existing
// asset loader; this cursor follows FAT links without duplicating a parser.
// room must guarantee at least 512 free bytes before each data request.
module fat32_bgm_sector_cursor #(
    parameter integer READ_TIMEOUT_CYCLES = 100_000_000
)(
    input wire clk, rst, start, room,
    input wire [27:0] first_cluster,
    input wire [31:0] file_size,
    input wire [7:0] sectors_per_cluster,
    input wire [31:0] sectors_per_fat, fat_start_lba, data_start_lba,
    input wire [31:0] volume_start_lba, volume_sector_count,
    output reg sd_req, output wire [31:0] sd_addr,
    input wire [7:0] sd_data, input wire sd_valid, sd_end,
    output wire pcm_valid, output wire [7:0] pcm_data,
    output wire active, output reg [7:0] error_code, output reg loop_pulse
);
    localparam [3:0] IDLE=0, MAP=1, SHIFT=2, ADD_BASE=3, CHECK=4,
                     DATA_REQ=5, DATA_WAIT=6, FAT_PREP=7, FAT_REQ=8,
                     FAT_WAIT=9, FAT_CHECK=10, FAILED=11;
    localparam integer TIMER_BITS = $clog2(READ_TIMEOUT_CYCLES+1);
    reg [3:0] state;
    reg [2:0] cluster_shift, shift_remaining;
    reg [27:0] first_q, cluster_q;
    // Count sectors rather than decrementing a 32-bit byte counter on each
    // byte. tail_q == 0 denotes a complete final 512-byte sector.
    reg [22:0] last_sector_q, sectors_left;
    reg [8:0] tail_q;
    reg [6:0] sector_index;
    // One address register serves data and FAT requests. Cluster mapping
    // shifts one bit per cycle instead of using a wide barrel shifter.
    reg [32:0] address_work, volume_end;
    reg mapping_fat;
    reg [9:0] received;
    reg [TIMER_BITS-1:0] timer;
    reg [27:0] fat_entry;
    wire [8:0] fat_byte_offset = {cluster_q[6:0], 2'b00};
    wire [9:0] received_next = received + (sd_valid ? 10'd1 : 10'd0);
    wire [22:0] initial_last_sector = file_size[31:9] - (file_size[8:0]==0 ? 23'd1 : 23'd0);
    assign sd_addr = address_work[31:0];
    assign pcm_valid = state == DATA_WAIT && sd_valid && !received[9] &&
                      (sectors_left!=0 || tail_q==0 || received[8:0]<tail_q);
    assign pcm_data = sd_data;
    assign active = state != IDLE && state != FAILED;

    always @(posedge clk) begin
        if (rst) begin
            state<=IDLE; cluster_shift<=0; shift_remaining<=0; first_q<=0; cluster_q<=0;
            last_sector_q<=0; sectors_left<=0; tail_q<=0; sector_index<=0;
            address_work<=0; volume_end<=0; mapping_fat<=0; received<=0; timer<=0;
            fat_entry<=0; sd_req<=0;
            error_code<=0; loop_pulse<=0;
        end else begin
            sd_req<=0; loop_pulse<=0;
            case(state)
                IDLE: if(start) begin
                    first_q<=first_cluster; cluster_q<=first_cluster;
                    last_sector_q<=initial_last_sector; sectors_left<=initial_last_sector;
                    tail_q<=file_size[8:0]; sector_index<=0;
                    volume_end<={1'b0,volume_start_lba}+{1'b0,volume_sector_count};
                    state<=MAP;
                    case(sectors_per_cluster)
                        1:cluster_shift<=0; 2:cluster_shift<=1; 4:cluster_shift<=2;
                        8:cluster_shift<=3; 16:cluster_shift<=4; 32:cluster_shift<=5;
                        64:cluster_shift<=6; 128:cluster_shift<=7;
                        default:begin error_code<=8'hb1; state<=FAILED; end
                    endcase
                    if(first_cluster<2 || first_cluster>=28'hffffff0 ||
                       file_size==0 || file_size[0] || volume_sector_count==0) begin
                        error_code<=8'hb1; state<=FAILED;
                    end
                end
                MAP: begin
                    address_work<={5'b0,cluster_q}-33'd2;
                    shift_remaining<=cluster_shift;
                    mapping_fat<=0; state<=SHIFT;
                end
                SHIFT: begin
                    if(address_work[32]) begin error_code<=8'hb2; state<=FAILED; end
                    else if(shift_remaining==0) state<=ADD_BASE;
                    else begin address_work<={address_work[31:0],1'b0}; shift_remaining<=shift_remaining-1'b1; end
                end
                ADD_BASE: begin
                    address_work<=address_work+{1'b0,(mapping_fat ? fat_start_lba : data_start_lba)};
                    state<=mapping_fat ? FAT_REQ : CHECK;
                end
                CHECK: begin
                    if(address_work[32] || address_work<{1'b0,volume_start_lba} ||
                       address_work>=volume_end) begin
                        error_code<=8'hb2; state<=FAILED;
                    end else state<=DATA_REQ;
                end
                DATA_REQ: if(room) begin
                    sd_req<=1; received<=0; timer<=0; state<=DATA_WAIT;
                end
                DATA_WAIT: begin
                    if(sd_valid) received<=received+1'b1;
                    if(sd_end) begin
                        if(received_next!=512) begin error_code<=8'hb3; state<=FAILED; end
                        else if(sectors_left==0) begin
                            sectors_left<=last_sector_q; cluster_q<=first_q; sector_index<=0;
                            loop_pulse<=1; state<=MAP;
                        end else begin
                            sectors_left<=sectors_left-1'b1;
                            if({1'b0,sector_index}==sectors_per_cluster-1'b1) state<=FAT_PREP;
                            else begin sector_index<=sector_index+1'b1; address_work<=address_work+1'b1; state<=CHECK; end
                        end
                    end else if(timer>=READ_TIMEOUT_CYCLES-1) begin
                        error_code<=8'hb4; state<=FAILED;
                    end else timer<=timer+1'b1;
                end
                FAT_PREP: begin
                    if({11'b0,cluster_q[27:7]}>=sectors_per_fat) begin error_code<=8'hb5; state<=FAILED; end
                    else begin
                        address_work<={12'b0,cluster_q[27:7]};
                        mapping_fat<=1; state<=ADD_BASE;
                    end
                end
                FAT_REQ: begin
                    if(address_work[32] || address_work<{1'b0,volume_start_lba} || address_work>=volume_end) begin
                        error_code<=8'hb5; state<=FAILED;
                    end else begin
                        sd_req<=1; received<=0; timer<=0;
                        fat_entry<=0; state<=FAT_WAIT;
                    end
                end
                FAT_WAIT: begin
                    if(sd_valid) begin
                        received<=received+1'b1;
                        if(received[8:2]==fat_byte_offset[8:2] && !received[9]) begin
                            case(received[1:0])
                                0:fat_entry[7:0]<=sd_data;
                                1:fat_entry[15:8]<=sd_data;
                                2:fat_entry[23:16]<=sd_data;
                                3:fat_entry[27:24]<=sd_data[3:0];
                            endcase
                        end
                    end
                    if(sd_end) begin
                        if(received_next!=512) begin error_code<=8'hb3; state<=FAILED; end
                        else state<=FAT_CHECK;
                    end else if(timer>=READ_TIMEOUT_CYCLES-1) begin
                        error_code<=8'hb4; state<=FAILED;
                    end else timer<=timer+1'b1;
                end
                FAT_CHECK: begin
                    if(fat_entry[27:0]<2 || fat_entry[27:0]>=28'hffffff0 ||
                       fat_entry[27:0]==cluster_q) begin
                        error_code<=8'hb6; state<=FAILED;
                    end else begin cluster_q<=fat_entry[27:0]; sector_index<=0; state<=MAP; end
                end
                FAILED: state<=FAILED;
                default: state<=IDLE;
            endcase
        end
    end
endmodule
