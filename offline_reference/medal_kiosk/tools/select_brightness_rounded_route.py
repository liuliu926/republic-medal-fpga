"""Try bounded placement seeds, selecting only positive HDMI serial margins."""
from pathlib import Path
import subprocess
import json
import re

root = Path(__file__).resolve().parents[1]
exe = Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe')
template = (root / 'tools/retry_720p_brightness_rounded_seed3.tcl').read_text()
results = []
for seed in [0, 1, 4]:
    text = template.replace('seed3', f'seed{seed}').replace('seed 3', f'seed {seed}').replace('SEED3', f'SEED{seed}')
    script = root / f'tools/retry_720p_brightness_rounded_seed{seed}.tcl'
    script.write_text(text, encoding='utf-8')
    run = root / f'fpga/td_project_720p/cli_runs/brightness_rounded_seed{seed}_20261031'
    log = root / f'fpga/td_project_720p/brightness_rounded_seed{seed}_build_console.log'
    print('Building seed', seed, flush=True)
    with log.open('w') as stream:
        result = subprocess.run([str(exe), script.as_posix()], cwd=root, stdout=stream, stderr=subprocess.STDOUT, timeout=1200)
    timing = run / 'final_timing.rpt'
    bit = run / 'medal_720p_brightness_rounded.bit'
    record = {'seed': seed, 'returncode': result.returncode, 'run': str(run.relative_to(root)), 'script': str(script.relative_to(root))}
    if result.returncode == 0 and timing.exists() and bit.exists():
        report = timing.read_text()
        clock = re.search(r'clk(\d+):\s+\S+\s+\d+\s+hdmi_5x_clk', report).group(1)
        row = re.search(r'^\s*clk'+clock+r'\s+local\s+.*$', report, re.M).group(0).split()
        record.update(hdmi_setup_ns=float(row[8]), hdmi_hold_ns=float(row[10]))
        record['selected'] = record['hdmi_setup_ns'] > 0 and record['hdmi_hold_ns'] > 0
    results.append(record)
    (root / 'fpga/td_project_720p/brightness_rounded_route_selection.json').write_text(json.dumps(results, indent=2)+'\n')
    print(json.dumps(record), flush=True)
    if record.get('selected'):
        print('HDMI_ROUTE_SELECTED', flush=True)
        break
else:
    raise SystemExit('No candidate with positive HDMI serial margins; do not download automatically.')
