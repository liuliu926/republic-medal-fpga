"""Compare banked and original subtitle RAM over a complete HDMI frame."""
from pathlib import Path
import subprocess
r=Path(__file__).resolve().parents[1]
d=r/'fpga/sim/runs/voice_mask'; d.mkdir(parents=True,exist_ok=True)
src=r/'fpga/user_source_720p/hdl_source'
(d/'reference.v').write_text((src/'home_text_mask_all_quiz.v').read_text().replace('module home_text_mask (','module home_text_mask_reference (',1))
tb=r/'fpga/sim/tb_voice_mask_equivalence.sv'
exe=d/'test.vvp'; bin=r/'tools/local_hdl/iverilog/app/bin'
for c in ([str(bin/'iverilog.exe'),'-g2005','-s','tb_voice_mask_equivalence','-o',str(exe),str(tb),str(d/'reference.v'),str(src/'home_text_mask_voice_pilot.v')], [str(bin/'vvp.exe'),str(exe)]):
    p=subprocess.run(c,capture_output=True,text=True,timeout=240)
    print(p.stdout,p.stderr)
    if p.returncode: raise SystemExit(p.returncode)
