from pathlib import Path
import subprocess

root=Path(__file__).resolve().parents[1]
src=root/'fpga/user_source_720p/hdl_source'
run=root/'fpga/sim/runs/bgm_audio'
run.mkdir(parents=True,exist_ok=True)
bin_dir=root/'tools/local_hdl/iverilog/app/bin'
commands=[
 [str(bin_dir/'iverilog.exe'),'-g2012','-s','tb_bgm_audio_mixer','-o',str(run/'test.vvp'),
  str(root/'fpga/sim/tb_bgm_audio_mixer.v'),str(src/'bgm_audio_mixer.v'),str(src/'IP/afifo_16_32_256.v')],
 [str(bin_dir/'vvp.exe'),str(run/'test.vvp')],
]
logs=[]
for command in commands:
    result=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,universal_newlines=True,timeout=90)
    logs.append(result.stdout)
    print(result.stdout)
    (run/'result.log').write_text('\n'.join(logs),encoding='utf-8')
    if result.returncode: raise SystemExit(result.returncode)
