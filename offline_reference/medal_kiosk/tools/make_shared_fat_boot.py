"""Generate isolated FAT clients which share one volume metadata cache."""
from pathlib import Path
p=Path(__file__).resolve().parents[1]/'fpga/user_source_720p/hdl_source/SD'
signals=[('metadata_valid',1),('boot_done',1),('boot_error_code',4),('fat_count',8),
         ('volume_start_lba',32),('volume_sector_count',32),('sectors_per_cluster',8),
         ('sectors_per_fat',32),('root_cluster',28),('fat_start_lba',32),('data_start_lba',32),
         ('debug_bpb_error',4),('debug_bpb_offset',9)]
ports=''.join('    input wire '+(f'[{n-1}:0] ' if n>1 else '')+'shared_'+name+',\n' for name,n in signals)
connections=''.join(f'        .shared_{name}(shared_{name}),\n' for name,_ in signals)
loader=(p/'fat32_bmp_pcm_asset_loader.v').read_text(encoding='utf-8')
loader=loader.replace('module fat32_bmp_pcm_asset_loader #(', 'module fat32_sharedmeta_asset_loader #(',1)
loader=loader.replace('    input wire pcm_mode,',ports+'    input wire pcm_mode,',1)
begin=loader.index('    fat32_volume_bootstrap #(')
end=loader.index('    fat32_root_file_lookup #(',begin)
aliases='''    assign boot_sd_read = 1'b0;
    assign boot_sd_addr = 0;
    assign boot_busy = 0;
'''
for name,_ in signals:
    dest={'fat_count':'fat_count_unused'}.get(name,name)
    aliases+=f'    assign {dest} = shared_{name};\n'
loader=loader[:begin]+aliases+'\n'+loader[end:]
(p/'fat32_sharedmeta_asset_loader.v').write_text(loader,encoding='utf-8')

# The frame resize path keeps its existing recovery behavior while using the
# same physical asset client interface and shared read-only metadata.
resize=(p/'fat32_bmp_resize_stream.v').read_text(encoding='utf-8')
resize=resize.replace('module fat32_bmp_resize_stream #(', 'module fat32_sharedmeta_resize_stream #(',1)
resize=resize.replace('    input  wire        clk,',ports+'    input  wire        clk,',1)
resize=resize.replace('    fat32_bmp_asset_loader #(', '    fat32_sharedmeta_asset_loader #(',1)
resize=resize.replace('    ) u_asset_loader (', '    ) u_asset_loader (\n'+connections+"        .pcm_mode(1'b0), .pcm_ready(1'b0), .pcm_valid(), .pcm_data(),",1)
(p/'fat32_sharedmeta_resize_stream.v').write_text(resize,encoding='utf-8')

frame=(p/'fat32_bmp_frame_pipeline.v').read_text(encoding='utf-8')
frame=frame.replace('module fat32_bmp_frame_pipeline #(', 'module fat32_sharedmeta_frame_pipeline #(',1)
frame=frame.replace('    input  wire                  clk,',ports+'    input  wire                  clk,',1)
frame=frame.replace('    fat32_bmp_resize_stream #(', '    fat32_sharedmeta_resize_stream #(',1)
frame=frame.replace('    ) u_load_resize (', '    ) u_load_resize (\n'+connections,1)
(p/'fat32_sharedmeta_frame_pipeline.v').write_text(frame,encoding='utf-8')

front=(p/'fat32_shared_reused_pcm_frontend.v').read_text(encoding='utf-8')
front=front.replace('module fat32_shared_reused_pcm_frontend #(', 'module fat32_shared_boot_frontend #(',1)
front=front.replace('    wire sd_ready_raw, sd_sector_ready;', '''    wire sd_ready_raw, sd_sector_ready;
    wire boot_read; wire [31:0] boot_addr;
    wire shared_metadata_valid, shared_boot_done;
    reg boot_finished;
'''+''.join('    wire '+(f'[{n-1}:0] ' if n>1 else '')+'shared_'+name+';\n' for name,n in signals if name not in ('metadata_valid','boot_done')),1)
front=front.replace('    assign busy = state != IDLE;', '    assign busy = state != IDLE || (!shared_metadata_valid && !boot_finished);',1)
front=front.replace('            state <= IDLE;\n            pcm_owner', '            state <= IDLE;\n            boot_finished <= 0;\n            pcm_owner',1)
front=front.replace("            frame_start_q <= 1'b0;\n            asset_start_q <= 1'b0;\n            pcm_done <= 0;", "            if (shared_boot_done) boot_finished <= 1;\n            frame_start_q <= 1'b0;\n            asset_start_q <= 1'b0;\n            pcm_done <= 0;",1)
front=front.replace('pcm_start && !start && sd_sector_ready && !frame_recovery', 'pcm_start && !start && sd_sector_ready && (shared_metadata_valid || boot_finished) && !frame_recovery',1)
front=front.replace('start && sd_sector_ready && !frame_recovery', 'start && sd_sector_ready && (shared_metadata_valid || boot_finished) && !frame_recovery',1)
front=front.replace('.sd_sec_read(owner_asset ? asset_sd_read : frame_sd_read),', '.sd_sec_read(!boot_finished ? boot_read : (owner_asset ? asset_sd_read : frame_sd_read)),',1)
front=front.replace('.sd_sec_read_addr(owner_asset ? asset_sd_addr : frame_sd_addr),', '.sd_sec_read_addr(!boot_finished ? boot_addr : (owner_asset ? asset_sd_addr : frame_sd_addr)),',1)
front=front.replace('fat32_bmp_frame_pipeline #(.ADDR_BITS(ADDR_BITS)) u_frame (', 'fat32_sharedmeta_frame_pipeline #(.ADDR_BITS(ADDR_BITS)) u_frame (\n'+connections,1)
front=front.replace('fat32_bmp_pcm_asset_loader u_asset (', 'fat32_sharedmeta_asset_loader u_asset (\n'+connections,1)
idx=front.rindex('endmodule')
front=front[:idx]+'''    fat32_volume_bootstrap u_shared_boot (
      .clk(clk), .rst(rst), .sd_init_done(sd_sector_ready),
      .sd_sec_read(boot_read), .sd_sec_read_addr(boot_addr), .sd_sec_read_data(sd_data),
      .sd_sec_read_data_valid(sd_data_valid && !boot_finished), .sd_sec_read_end(sd_end && !boot_finished),
      .busy(), .done(shared_boot_done), .metadata_valid(shared_metadata_valid), .error_code(shared_boot_error_code),
      .partition_index(), .partition_type(), .reserved_sectors(), .total_sectors(),
      .volume_start_lba(shared_volume_start_lba), .volume_sector_count(shared_volume_sector_count),
      .sectors_per_cluster(shared_sectors_per_cluster), .fat_count(shared_fat_count),
      .sectors_per_fat(shared_sectors_per_fat), .root_cluster(shared_root_cluster),
      .fat_start_lba(shared_fat_start_lba), .data_start_lba(shared_data_start_lba),
      .debug_bpb_error(shared_debug_bpb_error), .debug_bpb_offset(shared_debug_bpb_offset));
''' + front[idx:]
(p/'fat32_shared_boot_frontend.v').write_text(front,encoding='utf-8')
print('Generated isolated shared FAT bootstrap candidate')
