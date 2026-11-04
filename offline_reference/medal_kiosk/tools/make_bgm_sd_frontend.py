"""Build independent music frontend copies, preserving accepted sources."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
sd = root/'fpga/user_source_720p/hdl_source/SD'
asset = (sd/'fat32_sharedmeta_asset_loader.v').read_text()
asset = asset.replace('module fat32_sharedmeta_asset_loader #(', 'module fat32_sharedmeta_asset_loader_bgm #(', 1)
asset = asset.replace('    input wire pcm_mode,', '''    input wire lookup_only,
    output wire [27:0] lookup_file_cluster,
    output wire [31:0] lookup_file_size,
    input wire pcm_mode,''', 1)
asset = asset.replace('    reg pcm_mode_q;', '''    reg pcm_mode_q;
    reg lookup_only_q;
    assign lookup_file_cluster = file_first_cluster_latched;
    assign lookup_file_size = file_size_latched;''', 1)
asset = asset.replace('            pcm_mode_q <= 0;', '            pcm_mode_q <= 0; lookup_only_q <= 0;', 1)
asset = asset.replace('                        pcm_mode_q <= pcm_mode;', '                        pcm_mode_q <= pcm_mode; lookup_only_q <= lookup_only;', 1)
asset = asset.replace("            done          <= 1'b0;", "            done          <= 1'b0;\n            error         <= 1'b0;", 1)
asset = asset.replace('''                ST_FILE_START: begin
                    file_start <= 1'b1;''', '''                ST_FILE_START: if (lookup_only_q) begin
                    state <= ST_COMPLETE;
                end else begin
                    file_start <= 1'b1;''', 1)
(sd/'fat32_sharedmeta_asset_loader_bgm.v').write_text(asset)

front = (sd/'fat32_shared_boot_frontend_2line_candidate.v').read_text()
front = front.replace('module fat32_shared_boot_frontend_2line_candidate #(', 'module fat32_shared_boot_frontend_bgm #(', 1)
front = front.replace('    input wire pcm_start,', '''    input wire bgm_room,
    output wire bgm_valid,
    output wire [7:0] bgm_data,
    output wire bgm_active,
    output wire [7:0] bgm_error,
    output wire bgm_loop,
    input wire pcm_start,''', 1)
front = front.replace("ASSET = 2'd2;", "ASSET = 2'd2, DISCOVER = 2'd3;", 1)
front = front.replace('    reg owner_asset;', '''    reg owner_asset;
    reg bgm_discovered, bgm_start_q;
    reg [7:0] bgm_lookup_error;
    wire [27:0] lookup_file_cluster;
    wire [31:0] lookup_file_size;
    wire [7:0] bgm_cursor_error;
    assign bgm_error = bgm_lookup_error != 0 ? bgm_lookup_error : bgm_cursor_error;''', 1)
front = front.replace('    wire sd_data_valid, sd_end;', '''    wire sd_data_valid, sd_end;
    wire physical_valid, physical_end, physical_req;
    wire [31:0] physical_addr;
    wire bgm_sd_req, bgm_sd_valid, bgm_sd_end;
    wire [31:0] bgm_sd_addr;''', 1)
front = front.replace('assign busy = state != IDLE ||', 'assign busy = state != IDLE || !bgm_discovered ||', 1)
front = front.replace('            state <= IDLE;', '''            state <= IDLE;
            bgm_discovered <= 0; bgm_start_q <= 0; bgm_lookup_error <= 0;''', 1)
front = front.replace('            if (shared_boot_done) boot_finished <= 1;', '''            bgm_start_q <= 0;
            if (shared_boot_done) begin
                boot_finished <= 1;
                if (!shared_metadata_valid) begin
                    bgm_discovered <= 1;
                    bgm_lookup_error <= {4'h1, shared_boot_error_code};
                end
            end''', 1)
front = front.replace('''                IDLE: if (pcm_start''', '''                IDLE: if (!bgm_discovered && boot_finished && shared_metadata_valid) begin
                    owner_asset <= 1; pcm_owner <= 0;
                    name_q <= "BGM     PCM";
                    asset_start_q <= 1;
                    state <= DISCOVER;
                end else if (pcm_start''', 1)
front = front.replace('''                FRAME: if (frame_done''', '''                DISCOVER: if (asset_done || asset_error) begin
                    bgm_discovered <= 1;
                    if (asset_error) bgm_lookup_error <= asset_error_code;
                    else bgm_start_q <= 1;
                    state <= IDLE;
                end
                FRAME: if (frame_done''', 1)
old = '''        .sd_sec_read(!boot_finished ? boot_read : (owner_asset ? asset_sd_read : frame_sd_read)),
        .sd_sec_read_addr(!boot_finished ? boot_addr : (owner_asset ? asset_sd_addr : frame_sd_addr)),
        .sd_sec_read_data(sd_data),
        .sd_sec_read_data_valid(sd_data_valid),
        .sd_sec_read_end(sd_end),'''
new = '''        .sd_sec_read(physical_req), .sd_sec_read_addr(physical_addr),
        .sd_sec_read_data(sd_data),
        .sd_sec_read_data_valid(physical_valid),
        .sd_sec_read_end(physical_end),'''
assert old in front
front = front.replace(old, new, 1)
front = front.replace('    fat32_sharedmeta_asset_loader u_asset (', '''    fat32_sharedmeta_asset_loader_bgm u_asset (
        .lookup_only(state == DISCOVER),
        .lookup_file_cluster(lookup_file_cluster), .lookup_file_size(lookup_file_size),''', 1)
front = front.replace('.sd_init_done(sd_sector_ready && state == ASSET)', '.sd_init_done(sd_sector_ready && (state == ASSET || state == DISCOVER))', 1)
insert = '''
    sd_sector_arbiter_bgm u_sector_arbiter (
        .clk(clk), .rst(rst), .sector_ready(sd_sector_ready),
        .legacy_req(!boot_finished ? boot_read : (owner_asset ? asset_sd_read : frame_sd_read)),
        .legacy_addr(!boot_finished ? boot_addr : (owner_asset ? asset_sd_addr : frame_sd_addr)),
        .bgm_req(bgm_sd_req), .bgm_addr(bgm_sd_addr),
        .sd_req(physical_req), .sd_addr(physical_addr),
        .sd_valid(physical_valid), .sd_end(physical_end),
        .legacy_valid(sd_data_valid), .legacy_end(sd_end),
        .bgm_valid(bgm_sd_valid), .bgm_end(bgm_sd_end)
    );
    fat32_bgm_sector_cursor u_bgm_cursor (
        .clk(clk), .rst(rst), .start(bgm_start_q), .room(bgm_room),
        .first_cluster(lookup_file_cluster), .file_size(lookup_file_size),
        .sectors_per_cluster(shared_sectors_per_cluster),
        .sectors_per_fat(shared_sectors_per_fat),
        .fat_start_lba(shared_fat_start_lba), .data_start_lba(shared_data_start_lba),
        .volume_start_lba(shared_volume_start_lba), .volume_sector_count(shared_volume_sector_count),
        .sd_req(bgm_sd_req), .sd_addr(bgm_sd_addr),
        .sd_data(sd_data), .sd_valid(bgm_sd_valid), .sd_end(bgm_sd_end),
        .pcm_valid(bgm_valid), .pcm_data(bgm_data), .active(bgm_active),
        .error_code(bgm_cursor_error), .loop_pulse(bgm_loop)
    );
'''
front = front.replace('endmodule', insert+'endmodule', 1)
(sd/'fat32_shared_boot_frontend_bgm.v').write_text(front)
print('Generated lookup-only asset copy and sector-interleaved BGM frontend')
