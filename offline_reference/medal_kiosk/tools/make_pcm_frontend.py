"""Create a separate shared-SD variant with an additional PCM client."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]/'fpga/user_source_720p/hdl_source/SD'
s=(root/'fat32_shared_layer_frontend.v').read_text(encoding='utf-8')
s=s.replace('module fat32_shared_layer_frontend #(', 'module fat32_shared_pcm_frontend #(',1)
s=s.replace('    input  wire                 asset_mode,', '''    input wire pcm_start,
    input wire pcm_ready,
    output wire pcm_valid,
    output wire [7:0] pcm_data,
    output wire pcm_active,
    output reg pcm_done,
    output reg pcm_error,
    input  wire                 asset_mode,''',1)
s=s.replace('IDLE = 2\'d0, FRAME = 2\'d1, ASSET = 2\'d2;',"IDLE = 2'd0, FRAME = 2'd1, ASSET = 2'd2, PCM = 2'd3;",1)
s=s.replace('    reg owner_asset;', '''    reg owner_asset;
    reg pcm_start_q;
    wire pcm_sd_read, pcm_client_done, pcm_client_error;
    wire [31:0] pcm_sd_addr;
    assign pcm_active = state == PCM;''',1)
s=s.replace("            state <= IDLE;\n            owner_asset", "            state <= IDLE;\n            pcm_start_q <= 0; pcm_done <= 0; pcm_error <= 0;\n            owner_asset",1)
s=s.replace("            frame_start_q <= 1'b0;\n            asset_start_q <= 1'b0;\n            done <= 1'b0;", "            frame_start_q <= 1'b0;\n            asset_start_q <= 1'b0;\n            pcm_start_q <= 0; pcm_done <= 0; pcm_error <= 0;\n            done <= 1'b0;",1)
s=s.replace('                IDLE: if (start && sd_sector_ready && !frame_recovery) begin', '''                IDLE: if (pcm_start && !start && sd_sector_ready && !frame_recovery) begin
                    pcm_start_q <= 1;
                    state <= PCM;
                end else if (start && sd_sector_ready && !frame_recovery) begin''',1)
s=s.replace('                FRAME: if (frame_done || frame_error) begin', '''                PCM: if (pcm_client_done || pcm_client_error) begin
                    pcm_done <= pcm_client_done && !pcm_client_error;
                    pcm_error <= pcm_client_error;
                    state <= IDLE;
                end
                FRAME: if (frame_done || frame_error) begin''',1)
s=s.replace('.sd_sec_read(owner_asset ? asset_sd_read : frame_sd_read),', '.sd_sec_read(state == PCM ? pcm_sd_read : (owner_asset ? asset_sd_read : frame_sd_read)),',1)
s=s.replace('.sd_sec_read_addr(owner_asset ? asset_sd_addr : frame_sd_addr),', '.sd_sec_read_addr(state == PCM ? pcm_sd_addr : (owner_asset ? asset_sd_addr : frame_sd_addr)),',1)
s=s.replace('sd_data_valid && !owner_asset', 'sd_data_valid && state == FRAME',1).replace('sd_end && !owner_asset','sd_end && state == FRAME',1)
s=s.replace('sd_data_valid && owner_asset','sd_data_valid && state == ASSET',1).replace('sd_end && owner_asset','sd_end && state == ASSET',1)
idx=s.rindex('endmodule')
s=s[:idx]+'''    fat32_pcm_asset_loader u_pcm (
      .clk(clk), .rst(rst), .sd_init_done(sd_sector_ready && state == PCM),
      .start(pcm_start_q), .target_sfn("YUMIN01 PCM"),
      .sd_sec_read(pcm_sd_read), .sd_sec_read_addr(pcm_sd_addr),
      .sd_sec_read_data(sd_data), .sd_sec_read_data_valid(sd_data_valid && state == PCM),
      .sd_sec_read_end(sd_end && state == PCM),
      .pcm_valid(pcm_valid), .pcm_ready(pcm_ready), .pcm_data(pcm_data),
      .pixel_enable(1'b0), .pixel_ready(1'b0), .header_done(), .header_valid(),
      .source_width(), .source_height(), .pixel_valid(), .pixel_data(),
      .busy(), .done(pcm_client_done), .error(pcm_client_error), .error_code(),
      .debug_bpb_error(), .debug_bpb_offset(), .debug_boot_error(),
      .debug_fat_count(), .debug_sectors_per_cluster());
''' + s[idx:]
(root/'fat32_shared_pcm_frontend.v').write_text(s,encoding='utf-8')
print('Prepared isolated shared PCM frontend')
