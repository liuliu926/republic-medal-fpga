from pathlib import Path
import subprocess
r=Path(__file__).resolve().parents[1]; src=r/'fpga/user_source_720p/hdl_source'; d=r/'fpga/sim/runs/pcm_bridge'; d.mkdir(parents=True,exist_ok=True)
b=r/'tools/local_hdl/iverilog/app/bin'; out=d/'test.vvp'
cmd=[str(b/'iverilog.exe'),'-g2005','-s','tb_pcm_audio_bridge','-o',str(out),str(r/'fpga/sim/tb_pcm_audio_bridge.v'),str(src/'pcm_audio_bridge.v'),str(src/'pcm_voice_player.v'),str(src/'IP/afifo_16_32_256.v')]
for c in (cmd,[str(b/'vvp.exe'),str(out)]):
 p=subprocess.run(c,capture_output=True,text=True,timeout=90); print(p.stdout,p.stderr)
 if p.returncode: raise SystemExit(p.returncode)
