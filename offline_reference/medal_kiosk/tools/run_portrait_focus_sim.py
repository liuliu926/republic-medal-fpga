from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[1]
src=root/'fpga/user_source_720p/hdl_source'
run=root/'fpga/sim/runs/portrait_focus';run.mkdir(parents=True,exist_ok=True)
bins=root/'tools/local_hdl/iverilog/app/bin'
log=[]
def call(args):
    r=subprocess.run([str(x) for x in args],capture_output=True,text=True,timeout=120)
    print(r.stdout+r.stderr,end='');log.append(r.stdout+r.stderr)
    (run/'result.log').write_text('\n'.join(log),encoding='utf-8')
    if r.returncode:raise SystemExit(r.returncode)
tb=root/'fpga/sim/tb_portrait_focus.sv'
for top in ['tb_portrait_focus_key','tb_portrait_focus_frames','tb_portrait_focus']:
    out=run/(top+'.vvp')
    call([bins/'iverilog.exe','-g2012','-s',top,'-o',out,tb,
          src/'portrait_focus_key.v',src/'portrait_focus_geometry.v',src/'SD/frame_fifo_read_portrait_focus.v'])
    for step in ([0] if top!='tb_portrait_focus' else [0,1,8,16,24,31,32]):
        call([bins/'vvp.exe',out,f'+STEP={step}'])
    if top=='tb_portrait_focus':
        for mode in [1,2]:call([bins/'vvp.exe',out,f'+MODE={mode}'])
