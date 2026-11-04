"""Freeze the board-accepted rounded brightness build without rebuilding it."""
from pathlib import Path
from datetime import datetime
import hashlib
import json
import shutil

root = Path(__file__).resolve().parents[1]
run = root / 'fpga/td_project_720p/cli_runs/brightness_rounded_seed0_20261031'
release = root / 'releases/brightness_rounded_20261031'
manifest_path = run / 'candidate_manifest.json'
manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest().upper()
assert manifest['sha256'] == '2AD722FA0B569FE1F2566DF40D7F838DB685135D17452D7547D1B5C623A9C56B'
assert digest(run / manifest['bit']) == manifest['sha256']
for item in manifest['files']:
    assert digest(run / 'source_snapshot' / item['path']) == item['sha256'], item['path']
release.mkdir(parents=True, exist_ok=True)
for item in manifest['files']:
    destination = release / 'source_snapshot' / item['path']
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(run / 'source_snapshot' / item['path'], destination)
for name in [manifest['bit'], 'medal_kiosk_720p.prj', 'final_timing.rpt',
             'timing_status.rpt', 'utilization.rpt', 'download_console.log']:
    shutil.copy2(run / name, release / name)
    assert digest(run / name) == digest(release / name), name
for item in manifest['files']:
    assert digest(release / 'source_snapshot' / item['path']) == item['sha256'], item['path']
manifest.update(status='hardware_accepted', hardware_check_pending=False,
                accepted_at=datetime.now().astimezone().isoformat(),
                user_acceptance='圆角效果和操作都正常',
                acceptance_scope='SW4 rounded right-side brightness control; four cells, label, KEY1/KEY2 and closing behavior.',
                resume_note='User paused work until afternoon. No further build or board download performed at acceptance.',
                frozen_release=str(release.relative_to(root)).replace('\\', '/'))
encoded = json.dumps(manifest, ensure_ascii=False, indent=2) + '\n'
(release / 'release_manifest.json').write_text(encoded, encoding='utf-8')
manifest_path.write_text(encoded, encoding='utf-8')
print('Accepted snapshot verified:', len(manifest['files']), 'input files;', manifest['sha256'])
