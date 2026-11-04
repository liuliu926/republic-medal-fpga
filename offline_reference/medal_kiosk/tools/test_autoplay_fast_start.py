from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
out = root / 'fpga/sim/runs/autoplay_fast_start'
out.mkdir(parents=True, exist_ok=True)
binpath = root / 'tools/local_hdl/iverilog/app/bin'
exe = out / 'test.vvp'
subprocess.run([str(binpath/'iverilog.exe'), '-g2012', '-s', 'tb', '-o', str(exe),
                str(root/'fpga/sim/tb_autoplay_fast_start.sv'),
                str(root/'fpga/user_source_720p/hdl_source/kiosk_autoplay_720p_fast_start.v')],
               check=True, cwd=str(out), timeout=30)
result = subprocess.run([str(binpath/'vvp.exe'), str(exe)],
                        cwd=str(out), capture_output=True, text=True, timeout=30)
(out/'result.log').write_text(result.stdout + result.stderr, encoding='utf-8')
print(result.stdout + result.stderr)
result.check_returncode()
assert 'PASS:' in result.stdout, result.stdout
