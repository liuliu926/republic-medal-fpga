"""Derive rounded outer corners from the user-verified right-edge indicator."""
from pathlib import Path
import hashlib
import json
import shutil

root = Path(__file__).resolve().parents[1]
run = root / 'fpga/td_project_720p/cli_runs/brightness_right_seed2_20261031'
release = root / 'releases/brightness_right_20261031'
bit_name = 'medal_720p_brightness_right.bit'
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest().upper()
assert digest(run / bit_name) == 'E9BE6E3EE06584E25992C69EA51802BFBF806D3773D8152A6AD8F0D915A025CC'
if not release.exists():
    release.mkdir()
    for name in [bit_name, 'final_timing.rpt', 'timing_status.rpt', 'utilization.rpt', 'medal_kiosk_720p.prj', 'download_console.log']:
        shutil.copy2(run / name, release / name)
    shutil.copytree(run / 'source_snapshot', release / 'source_snapshot')
    manifest = json.loads((run / 'candidate_manifest.json').read_text(encoding='utf-8'))
    manifest.update(status='accepted_by_user', hardware_check_pending=False,
                    hardware_result='User confirmed functionality normal; requested rounded outer corners as next visual refinement.')
    (release / 'release_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
assert digest(release / bit_name) == digest(run / bit_name)

top = 'fpga/user_source_720p/hdl_source/top_fat32_brightness_right.v'
source = (release / 'source_snapshot' / top).read_text(encoding='utf-8-sig')
old = '''wire cell_border = x < 11'd1210 || x >= 11'd1254 ||
                   y[5:0] < 6'd2 || y[5:0] >= 6'd62;'''
# Precompute a radius-12 outer curve and radius-10 inner curve, sharing the
# same centre. Hardware uses only tiny constant lookup tables and comparisons.
rows = []
for dy in range(12):
    def inset(radius):
        for dx in range(12):
            if (11.5-dx)**2 + (11.5-dy)**2 <= radius**2:
                return dx
        return 15
    rows.append(f"            4'd{dy}: corner_limits = 8'h{inset(12):X}{inset(10):X};")
new = '''// Four corners share one small radius lookup. No multiplier or divider.
wire [5:0] edge_x = x < 11'd1232 ? x - 11'd1208 : 11'd1255 - x;
wire [7:0] edge_y = y[7] ? ~y[7:0] : y[7:0];
function [7:0] corner_limits;
    input [3:0] row;
    begin
        case (row)
''' + '\n'.join(rows) + '''
            default: corner_limits = 8'h02;
        endcase
    end
endfunction
wire [7:0] rounded_limits = edge_y < 8'd12 ? corner_limits(edge_y[3:0]) : 8'h02;
wire inside_rounded = edge_x >= rounded_limits[7:4];
wire inside_fill = edge_y >= 8'd2 && edge_x >= rounded_limits[3:0];
wire cell_border = !inside_fill || y[5:0] < 6'd2 || y[5:0] >= 6'd62;'''
assert source.count(old) == 1
candidate = source.replace(old, new)
condition = "if (x >= 11'd1208 && x < 11'd1256 && y >= 10'd256 && y < 10'd512)"
assert candidate.count(condition) == 1
candidate = candidate.replace(condition, condition[:-1]+' && inside_rounded)')
# All other top-level/control/dimmer behavior remains the accepted source.
assert candidate.replace(new, old).replace(condition[:-1]+' && inside_rounded)', condition) == source
(root / 'fpga/user_source_720p/hdl_source/top_fat32_brightness_rounded.v').write_text(candidate, encoding='utf-8')
print('Frozen accepted rectangular UI; generated UI-only rounded candidate.')
print('Top SHA256:', hashlib.sha256(candidate.encode()).hexdigest().upper())

build = (root / 'tools/build_720p_brightness_right.tcl').read_text()
build = build.replace('brightness_right', 'brightness_rounded').replace('BRIGHTNESS_RIGHT', 'BRIGHTNESS_ROUNDED').replace('place seed 1', 'place seed 2')
(root / 'tools/build_720p_brightness_rounded.tcl').write_text(build, encoding='utf-8')
download = '''set root [file normalize [file dirname [info script]]]
cd [file join $root fpga td_project_720p cli_runs brightness_rounded_seed0_20261031]
import_device eagle_s20.db -package EG4S20BG256
download -bit medal_720p_brightness_rounded.bit -mode jtag -spd 7 -sec 64 -cable 0
puts {BRIGHTNESS_ROUNDED_DOWNLOADED}
exit 0
'''
(root / 'download_720p_brightness_rounded.tcl').write_text(download, encoding='utf-8')
rollback = '''set root [file normalize [file dirname [info script]]]
cd [file join $root releases brightness_right_20261031]
import_device eagle_s20.db -package EG4S20BG256
download -bit medal_720p_brightness_right.bit -mode jtag -spd 7 -sec 64 -cable 0
puts {BRIGHTNESS_RIGHT_ACCEPTED_DOWNLOADED}
exit 0
'''
(root / 'download_720p_brightness_right_accepted.tcl').write_text(rollback, encoding='utf-8')
