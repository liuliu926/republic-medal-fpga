"""Check status pulse/level transfer; analog metastability is not modeled."""
from pathlib import Path
import subprocess

root=Path(__file__).resolve().parents[1]
bins=root/'tools/local_hdl/iverilog/app/bin'
out=root/'fpga/sim/runs/cdc'
out.mkdir(parents=True,exist_ok=True)
exe=out/'cdc.vvp'
commands=[
    [str(bins/'iverilog.exe'),'-g2012','-s','tb_frame_write_status_cdc','-o',str(exe),
     str(root/'fpga/sim/tb_frame_write_status_cdc.sv'),
     str(root/'fpga/user_source_720p/hdl_source/SD/frame_write_status_cdc.v')],
    [str(bins/'vvp.exe'),str(exe)]]
logs=[]
for cmd in commands:
    r=subprocess.run(cmd,capture_output=True,text=True,timeout=30)
    logs.append(r.stdout+r.stderr)
    (out/'result.log').write_text('\n'.join(logs),encoding='utf-8')
    print(logs[-1])
    if r.returncode: raise SystemExit(r.returncode)
