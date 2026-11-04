from pathlib import Path
import subprocess
from run_pipeline_sim import fixture,bmp
r=Path(__file__).resolve().parents[1]; sd=r/'fpga/user_source_720p/hdl_source/SD'
dest,n=fixture('sharedboot_frontend',41,31,dir_mode='second_sector'); data,_=bmp(41,31)
(dest/'pcm_expected.hex').write_text(''.join(f'{b:02x}\n' for b in data))
hexfile=dest/'sectors.hex'; values=bytearray(int(s,16) for s in hexfile.read_text().split())
idx=values.find(b'TEST    BMP'); assert idx>=0
values[idx+32:idx+64]=values[idx:idx+32]; values[idx+32:idx+43]=b'YUMIN01 PCM'
hexfile.write_text(''.join(f'{v:02x}\n' for v in values))
mods=['fat32_shared_boot_frontend','frame_write_status_cdc','fat32_volume_bootstrap',
 'fat32_mbr_partition_scan','fat32_bpb_parser','fat32_sharedmeta_frame_pipeline',
 'fat32_sharedmeta_resize_stream','fat32_sharedmeta_asset_loader','fat32_root_file_lookup',
 'fat32_dir_sector_scan','fat32_file_stream_reader','bmp_stream_decoder','bmp_resize_stream','bmp_scaled_frame_write_ctrl']
b=r/'tools/local_hdl/iverilog/app/bin'; out=dest/'test.vvp'
front=(sd/'fat32_shared_boot_frontend.v').read_text(encoding='utf-8').replace(
 'fat32_sharedmeta_frame_pipeline #(.ADDR_BITS(ADDR_BITS))',
 'fat32_sharedmeta_frame_pipeline #(.ADDR_BITS(ADDR_BITS), .OUT_WIDTH(16), .OUT_HEIGHT(12))',1)
(dest/'frontend.v').write_text(front,encoding='utf-8')
cmds=[[str(b/'iverilog.exe'),'-g2012','-s','tb_sharedboot_frontend','-o',str(out),str(r/'fpga/sim/tb_sharedboot_frontend.sv'),str(dest/'frontend.v')]+[str(sd/(m+'.v')) for m in mods[1:]],
 [str(b/'vvp.exe'),str(out),f'+FIXTURE={dest.as_posix()}',f'+SECTORS={n}',f'+LENGTH={len(data)}']]
for c in cmds:
 v=subprocess.run(c,capture_output=True,text=True,timeout=90); print(v.stdout,v.stderr)
 if v.returncode: raise SystemExit(v.returncode)
