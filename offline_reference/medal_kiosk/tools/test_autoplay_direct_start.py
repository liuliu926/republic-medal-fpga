from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
out = root / 'fpga/sim/runs/autoplay_direct_start'
out.mkdir(parents=True, exist_ok=True)
binpath = root / 'tools/local_hdl/iverilog/app/bin'
hdl = root / 'fpga/user_source_720p/hdl_source'

# Keep the page-change guard identical to the synthesized top, rather than
# independently reimplementing the request expression in the test fixture.
top = (hdl/'top_fat32_all_article_voice_auto3.v').read_text(encoding='utf-8')
guard = top[top.index('reg [7:0] voice_page_q;'):top.index('// A uniform 8.3 name')]
(out/'voice_request_guard.v').write_text('''module voice_request_guard(
input sd_card_clk, rst_all, article_text_mode,
input [1:0] display_level, input [4:0] display_person,
input [2:0] display_section, input [7:0] display_page,
output voice_requested);
''' + guard.replace('wire voice_requested =', 'assign voice_requested =') + '\nendmodule\n', encoding='utf-8')

# Reuse the exhaustive duration/pause/wrap fixture, expecting row 1 immediately.
fixture = (root/'fpga/sim/tb_autoplay_fast_start.sv').read_text(encoding='utf-8')
fixture = fixture.replace(', .ARTICLE_INTRO_CYCLES(2)', '')
fixture = fixture.replace('      dwell(2,p,s,0,2);\n', '')
fixture = fixture.replace('39 intro pages use 1-second dwell;', '39 sections start at row 1 without empty intro dwell;')
(out/'tb_duration.sv').write_text(fixture, encoding='utf-8')

logs = []
for name, sources in [
    ('duration', [out/'tb_duration.sv', hdl/'kiosk_autoplay_720p_direct_start.v']),
    ('loading_gate', [root/'fpga/sim/tb_autoplay_direct_start_loading.sv',
                      hdl/'kiosk_autoplay_720p_direct_start.v',
                      hdl/'SD/kiosk_fat32_sequence_autoplay_pilot.v', out/'voice_request_guard.v'])
]:
    exe = out / (name + '.vvp')
    subprocess.run([str(binpath/'iverilog.exe'), '-g2012', '-s', 'tb', '-o', str(exe)] +
                   [str(p) for p in sources], check=True, cwd=out, timeout=30)
    result = subprocess.run([str(binpath/'vvp.exe'), str(exe)], cwd=out,
                            capture_output=True, text=True, timeout=30)
    logs.append(name + ':\n' + result.stdout + result.stderr)
    (out/'result.log').write_text('\n'.join(logs), encoding='utf-8')
    print(logs[-1])
    result.check_returncode()
    assert 'PASS:' in result.stdout
