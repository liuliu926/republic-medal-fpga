"""Freeze the accepted input tree and prepare an isolated optimization project.

Never changes current HDL, accepted bitstreams, TF assets, or default downloader.
"""
import hashlib
import json
import shutil
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'releases/title_waveform_gain_candidate_20261101'
RUN = ROOT / 'fpga/td_project_720p/cli_runs/title_waveform_gain_20261101'
SOURCE = ROOT / 'fpga/user_source_720p'
OUT = ROOT / 'experiments/resource_opt_20261101'
EXPECTED = '29525ac759df876c89de3ec73182c903d5b4832ba82f986d64289420ca02464d'

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

assert sha(BASE / 'medal_720p_title_waveform_gain.bit') == EXPECTED
if OUT.exists():
    raise SystemExit('Experiment already exists; refusing to overwrite the snapshot')
freeze = OUT / 'rollback'
freeze.mkdir(parents=True)
shutil.copytree(SOURCE, freeze / 'source')
shutil.copytree(SOURCE, OUT / 'source')
for name in ['medal_720p_title_waveform_gain.bit', 'final_timing.rpt',
             'timing_status.rpt', 'utilization.rpt', 'README.md', 'verification.json']:
    shutil.copy2(BASE / name, freeze / name)
for name in ['medal_kiosk_720p.prj', 'article_voice_cues.hex']:
    shutil.copy2(RUN / name, freeze / name)
for name in ['download_720p_current.tcl', 'download_720p_title_waveform_gain_accepted.tcl']:
    shutil.copy2(ROOT / name, freeze / name)
shutil.copy2(ROOT / 'tools/build_720p_title_waveform_gain.tcl', freeze)
assets = json.loads((ROOT / 'releases/bilingual_layout_v2_20261101/card_asset_manifest.json').read_text(encoding='utf-8-sig'))
(freeze / 'card_asset_manifest_reference.json').write_text(json.dumps(assets, ensure_ascii=False, indent=2), encoding='utf-8')
for name in ['HOMETXT.BMP', 'HOMEENG.BMP']:
    shutil.copy2(ROOT / 'releases/title_waveform_candidate_20261101' / name, freeze / name)

candidate_run = OUT / 'run'
candidate_run.mkdir()
tree = ET.parse(RUN / 'medal_kiosk_720p.prj')
dependencies = []
for node in tree.iter('File'):
    if node.get('Path'):
        original = (RUN / node.get('Path')).resolve()
        if not original.is_file():
            raise RuntimeError(f'Missing project dependency: {original}')
        rel = original.relative_to(SOURCE)
        node.set('Path', (OUT / 'source' / rel).as_posix())
        dependencies.append({'file': rel.as_posix(), 'sha256': sha(original)})
tree.write(candidate_run / 'medal_kiosk_720p.prj', encoding='utf-8', xml_declaration=True)
shutil.copy2(RUN / 'article_voice_cues.hex', candidate_run)
build = (ROOT / 'tools/build_720p_title_waveform_gain.tcl').read_text(encoding='utf-8-sig')
build = build.replace('set root [file normalize [file join [file dirname [info script]] ..]]',
                      'set root [file normalize [file dirname [info script]]]')
build = build.replace('set run_dir [file join $root fpga td_project_720p cli_runs title_waveform_gain_20261101]',
                      'set run_dir [file join $root run]')
build = build.replace('../../../user_source_720p/constraints_source/', '../source/constraints_source/')
build = build.replace('medal_720p_title_waveform_gain.bit', 'medal_720p_resource_opt.bit')
build = build.replace('WAVEFORM_GAIN_BUILD_COMPLETE', 'RESOURCE_OPT_BUILD_COMPLETE')
(OUT / 'build.tcl').write_text(build, encoding='utf-8')
(OUT / 'rollback.tcl').write_text('set root [file normalize [file dirname [info script]]]\ncd [file join $root rollback]\nimport_device eagle_s20.db -package EG4S20BG256\ndownload -bit medal_720p_title_waveform_gain.bit -mode jtag -spd 7 -sec 64 -cable 0\nputs {RESOURCE_OPT_ROLLBACK_DOWNLOADED}\nexit 0\n', encoding='utf-8')
manifest = [{'file': p.relative_to(freeze).as_posix(), 'bytes': p.stat().st_size, 'sha256': sha(p)} for p in freeze.rglob('*') if p.is_file()]
(freeze / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
(OUT / 'status.json').write_text(json.dumps({'status':'prepared_not_built', 'baseline_bit_sha256':EXPECTED,
    'baseline_resources':{'lut':18444,'register':9560,'bram9k':51,'bram32k':8,'dsp':4},
    'dependencies':dependencies,'default_download_unchanged':True,'tf_card_unchanged':True},indent=2),encoding='utf-8')
print(json.dumps({'snapshot_files':len(manifest),'project_dependencies':len(dependencies),'experiment':str(OUT)}))
