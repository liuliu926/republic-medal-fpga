"""Exercise the raw-file client against a fragmented FAT32 sector fixture."""
from pathlib import Path
import subprocess
from run_pipeline_sim import fixture, bmp

root=Path(__file__).resolve().parents[1]
sd=root/'fpga/user_source_720p/hdl_source/SD'
binary=root/'tools/local_hdl/iverilog/app/bin'
dest,n=fixture('pcm_raw',41,31,dir_mode='second_sector')
data,_=bmp(41,31)
(dest/'pcm_expected.hex').write_text(''.join(f'{b:02x}\n' for b in data))
out=dest/'pcm.vvp'
modules=['fat32_bmp_pcm_asset_loader','bmp_stream_decoder','fat32_volume_bootstrap','fat32_root_file_lookup',
         'fat32_file_stream_reader','fat32_mbr_partition_scan','fat32_bpb_parser',
         'fat32_dir_sector_scan']
cmd=[str(binary/'iverilog.exe'),'-g2012','-s','tb_pcm_fat_loader','-o',str(out),
     str(root/'fpga/sim/tb_pcm_fat_loader.sv')]+[str(sd/(m+'.v')) for m in modules]
for command in (cmd,[str(binary/'vvp.exe'),str(out),f'+FIXTURE={dest.as_posix()}',
                     f'+SECTORS={n}',f'+LENGTH={len(data)}']):
    result=subprocess.run(command,capture_output=True,text=True,timeout=60)
    print(result.stdout,result.stderr)
    if result.returncode: raise SystemExit(result.returncode)
