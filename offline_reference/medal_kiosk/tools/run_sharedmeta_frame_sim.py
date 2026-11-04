from pathlib import Path
import subprocess
from run_pipeline_sim import fixture
r=Path(__file__).resolve().parents[1]; sd=r/'fpga/user_source_720p/hdl_source/SD'
dest,n=fixture('frame_sharedmeta',41,31,dir_mode='second_sector')
tb=(r/'fpga/sim/tb_fat32_bmp_pipeline.sv').read_text(encoding='utf-8')
tb=tb.replace('fat32_bmp_frame_pipeline #(', 'fat32_sharedmeta_frame_pipeline #(',1)
tb=tb.replace('.clk(clk),.rst(rst),.sd_init_done(!rst),.start(start),', '''.clk(clk),.rst(rst),.sd_init_done(!rst),.start(start),
    .shared_metadata_valid(1'b1), .shared_boot_done(1'b0), .shared_boot_error_code(4'd0),
    .shared_fat_count(8'd2), .shared_volume_start_lba(32'd1), .shared_volume_sector_count(32'd70000),
    .shared_sectors_per_cluster(8'd2), .shared_sectors_per_fat(32'd600), .shared_root_cluster(28'd2),
    .shared_fat_start_lba(32'd33), .shared_data_start_lba(32'd1233),
    .shared_debug_bpb_error(4'd0), .shared_debug_bpb_offset(9'd0),''',1)
(dest/'tb.v').write_text(tb,encoding='utf-8')
mods=['fat32_sharedmeta_frame_pipeline','fat32_sharedmeta_resize_stream','fat32_sharedmeta_asset_loader',
      'fat32_root_file_lookup','fat32_dir_sector_scan','fat32_file_stream_reader',
      'bmp_stream_decoder','bmp_resize_stream','bmp_scaled_frame_write_ctrl']
b=r/'tools/local_hdl/iverilog/app/bin'; out=dest/'test.vvp'
commands=[[str(b/'iverilog.exe'),'-g2012','-s','tb_fat32_bmp_pipeline','-o',str(out),str(dest/'tb.v')]+[str(sd/(m+'.v')) for m in mods],
          [str(b/'vvp.exe'),str(out),f'+FIXTURE={dest.as_posix()}',f'+SECTORS={n}','+CASE=frame_sharedmeta']]
for c in commands:
 v=subprocess.run(c,capture_output=True,text=True,timeout=90); print(v.stdout,v.stderr)
 if v.returncode: raise SystemExit(v.returncode)
