from pathlib import Path
p=Path(__file__).resolve().parents[1]/'fpga/user_source_720p/hdl_source/SD'
s=(p/'fat32_shared_layer_frontend.v').read_text(encoding='utf-8')
s=s.replace('module fat32_shared_layer_frontend #(', 'module fat32_shared_reused_pcm_frontend #(',1)
s=s.replace('    input  wire                 asset_mode,', '''    input wire pcm_start,
    input wire pcm_ready,
    output wire pcm_valid,
    output wire [7:0] pcm_data,
    output wire pcm_active,
    output reg pcm_done,
    output reg pcm_error,
    input  wire                 asset_mode,''',1)
s=s.replace('    reg owner_asset;', '''    reg owner_asset;
    reg pcm_owner;
    assign pcm_active = state == ASSET && pcm_owner;''',1)
s=s.replace("            state <= IDLE;\n            owner_asset", "            state <= IDLE;\n            pcm_owner <= 0; pcm_done <= 0; pcm_error <= 0;\n            owner_asset",1)
s=s.replace("            frame_start_q <= 1'b0;\n            asset_start_q <= 1'b0;\n            done <= 1'b0;", "            frame_start_q <= 1'b0;\n            asset_start_q <= 1'b0;\n            pcm_done <= 0; pcm_error <= 0;\n            done <= 1'b0;",1)
s=s.replace('                IDLE: if (start && sd_sector_ready && !frame_recovery) begin', '''                IDLE: if (pcm_start && !start && sd_sector_ready && !frame_recovery) begin
                    owner_asset <= 1; pcm_owner <= 1;
                    name_q <= "YUMIN01 PCM";
                    asset_start_q <= 1;
                    state <= ASSET;
                end else if (start && sd_sector_ready && !frame_recovery) begin
                    pcm_owner <= 0;''',1)
s=s.replace("                    done <= asset_done && !asset_error;\n                    error <= asset_error;", "                    done <= !pcm_owner && asset_done && !asset_error;\n                    error <= !pcm_owner && asset_error;\n                    pcm_done <= pcm_owner && asset_done && !asset_error;\n                    pcm_error <= pcm_owner && asset_error;",1)
s=s.replace('    fat32_bmp_asset_loader u_asset (', '    fat32_bmp_pcm_asset_loader u_asset (',1)
s=s.replace('        .start(asset_start_q), .target_sfn(name_q),', '        .start(asset_start_q), .target_sfn(name_q),\n        .pcm_mode(pcm_owner), .pcm_ready(pcm_ready), .pcm_valid(pcm_valid), .pcm_data(pcm_data),',1)
(p/'fat32_shared_reused_pcm_frontend.v').write_text(s,encoding='utf-8')
print('Prepared SD frontend with shared BMP/PCM client')
