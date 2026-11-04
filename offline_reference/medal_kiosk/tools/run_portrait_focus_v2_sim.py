from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[1]
src=root/'fpga/user_source_720p/hdl_source'
run=root/'fpga/sim/runs/portrait_focus_linecache';run.mkdir(parents=True,exist_ok=True)
bins=root/'tools/local_hdl/iverilog/app/bin'
log=[]
def call(args):
    p=subprocess.run([str(x) for x in args],capture_output=True,text=True,timeout=180)
    print(p.stdout+p.stderr,end='',flush=True);log.append(p.stdout+p.stderr)
    (run/'result.log').write_text('\n'.join(log),encoding='utf-8')
    if p.returncode:raise SystemExit(p.returncode)
for top in ['tb_portrait_focus_key','tb_focus_colour','tb_portrait_focus_linecache']:
    out=run/(top+'.vvp')
    call([bins/'iverilog.exe','-g2012','-s',top,'-o',out,
        root/'fpga/sim/tb_portrait_focus.sv',root/'fpga/sim/tb_portrait_focus_linecache.sv',
        src/'portrait_focus_key.v',src/'portrait_focus_geometry.v',src/'portrait_focus_video.v',
        src/'SD/frame_fifo_read_portrait_focus.v'])
    if top!='tb_portrait_focus_linecache':call([bins/'vvp.exe',out]);continue
    for step in [0,1,3,12,16,24,31,32]:call([bins/'vvp.exe',out,f'+STEP={step}'])
    for mode in [1,2]:call([bins/'vvp.exe',out,f'+MODE={mode}'])
    for step in [0,32]:call([bins/'vvp.exe',out,f'+STEP={step}','+LATENCY=8','+OCCUPANCY=1'])
