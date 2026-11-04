"""Run sector streaming tests without card, FPGA, or accepted-file edits."""
from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[1]
sd=root/'fpga/user_source_720p/hdl_source/SD'
sim=root/'fpga/sim'
out=sim/'runs/bgm_sd'
out.mkdir(parents=True,exist_ok=True)
binary=root/'tools/local_hdl/iverilog/app/bin'
exe=out/'bgm.vvp'
commands=[[str(binary/'iverilog.exe'),'-g2012','-s','tb_bgm_sector_stream','-o',str(exe),
           str(sim/'tb_bgm_sector_stream.sv'),str(sd/'fat32_bgm_sector_cursor.v'),str(sd/'sd_sector_arbiter_bgm.v')]]
commands += [[str(binary/'vvp.exe'),str(exe),'+MODE='+str(i)] for i in range(13)]
logs=[]
for cmd in commands:
    r=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,universal_newlines=True,timeout=60)
    logs.append(r.stdout)
    (out/'result.log').write_text(''.join(logs),encoding='utf-8')
    print(r.stdout)
    if r.returncode: raise SystemExit(r.returncode)
