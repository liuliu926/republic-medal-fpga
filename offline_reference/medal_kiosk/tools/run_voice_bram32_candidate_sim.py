"""Check the candidate against the existing 720p subtitle mask."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
src = root / "fpga/user_source_720p/hdl_source"
out = root / "fpga/sim/runs/voice_bram32_candidate"
out.mkdir(parents=True, exist_ok=True)
reference = (src / "home_text_mask_voice_autoplay.v").read_text(encoding="utf-8")
reference = reference.replace("module home_text_mask (", "module home_text_mask_reference (", 1)
(out / "reference.v").write_text(reference, encoding="utf-8")
binary = root / "tools/local_hdl/iverilog/app/bin"
exe = out / "test.vvp"
commands = [
    [str(binary / "iverilog.exe"), "-g2005", "-s", "tb_voice_mask_equivalence", "-o", str(exe),
     str(root / "fpga/sim/tb_voice_mask_equivalence.sv"), str(out / "reference.v"),
     str(src / "home_text_mask_voice_bram32_candidate.v")],
    [str(binary / "vvp.exe"), str(exe)],
]
for command in commands:
    result = subprocess.run(command, capture_output=True, text=True, timeout=240)
    print(result.stdout, result.stderr)
    if result.returncode:
        raise SystemExit(result.returncode)
