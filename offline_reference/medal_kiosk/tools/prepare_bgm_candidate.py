"""Create isolated BGM candidate top/project from the frozen rounded release."""
from pathlib import Path
import hashlib
import json
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
release = root / 'releases/brightness_rounded_20261031'
manifest = json.loads((release / 'release_manifest.json').read_text(encoding='utf-8'))
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest().upper()
assert digest(release / manifest['bit']) == manifest['sha256']
for item in manifest['files']:
    if item['path'].startswith('fpga/user_source_720p/'):
        assert digest(root / item['path']) == item['sha256'], item['path']

source = root / 'fpga/user_source_720p/hdl_source'
old = (release / 'source_snapshot/fpga/user_source_720p/hdl_source/top_fat32_brightness_rounded.v').read_text(encoding='utf-8')
top = old
before = '''wire hdmi_audio_valid = voice_requested_video[1] ?
    voice_audio_valid : silent_audio_tick;
wire signed [23:0] hdmi_audio_data = voice_requested_video[1] ?
    voice_audio_data : 24'sd0;'''
after = '''// Independent BGM stream survives navigation; speech sample counters remain untouched.
wire bgm_room, bgm_urgent, bgm_valid, bgm_active, bgm_loop;
wire [7:0] bgm_data, bgm_error;
wire bgm_underrun, bgm_overflow;
wire hdmi_audio_valid;
wire signed [23:0] hdmi_audio_data;
bgm_audio_mixer u_bgm_audio (
    .sd_clk(sd_card_clk), .pixel_clk(video_clk), .rst(rst_all), .pixel_rst(rst_video),
    .bgm_valid(bgm_valid), .bgm_data(bgm_data),
    .bgm_room(bgm_room), .bgm_urgent(bgm_urgent),
    .voice_enable(voice_requested_video[1]),
    .voice_valid(voice_audio_valid), .voice_data(voice_audio_data),
    .audio_valid(hdmi_audio_valid), .audio_data(hdmi_audio_data),
    .bgm_underrun(bgm_underrun), .bgm_overflow(bgm_overflow), .bgm_playing()
);'''
assert top.count(before) == 1
top = top.replace(before, after)
top = top.replace('fat32_shared_boot_frontend_2line_candidate u_fat32_shared (',
                  'fat32_shared_boot_frontend_bgm u_fat32_shared (\n'
                  '    .bgm_room(bgm_room),\n'
                  '    .bgm_valid(bgm_valid), .bgm_data(bgm_data),\n'
                  '    .bgm_active(bgm_active), .bgm_error(bgm_error), .bgm_loop(bgm_loop),')
assert top != old
(source / 'top_fat32_bgm_candidate.v').write_text(top, encoding='utf-8')

run = root / 'fpga/td_project_720p/cli_runs/bgm_compact_20261031'
run.mkdir(parents=True, exist_ok=True)
project_text = (release / 'medal_kiosk_720p.prj').read_text(encoding='utf-8')
tree = ET.ElementTree(ET.fromstring(project_text.replace('UsedInP&R', 'UsedInP&amp;R')))
verilog = tree.getroot().find('./Source_Files/Verilog')
for node in verilog.findall('File'):
    if node.attrib['Path'].endswith('/top_fat32_brightness_rounded.v'):
        node.set('Path', node.attrib['Path'].replace('top_fat32_brightness_rounded.v', 'top_fat32_bgm_candidate.v'))
    for original, compact in [('home_text_mask_all_article_voice.v', 'home_text_mask_bgm_compact.v'),
                              ('fat32_file_stream_reader.v', 'fat32_file_stream_reader_bgm_bram.v')]:
        if node.attrib['Path'].endswith('/' + original):
            node.set('Path', node.attrib['Path'].replace(original, compact))
            assert (run / node.attrib['Path']).resolve().is_file(), compact
add = ['bgm_audio_mixer.v', 'SD/fat32_sharedmeta_asset_loader_bgm.v',
       'SD/fat32_shared_boot_frontend_bgm.v', 'SD/fat32_bgm_sector_cursor.v', 'SD/sd_sector_arbiter_bgm.v']
for i, name in enumerate(add):
    assert (source / name).is_file(), name
    node = ET.SubElement(verilog, 'File', Path='../../../user_source_720p/hdl_source/' + name)
    info = ET.SubElement(node, 'FileInfo')
    for key, val in [('UsedInSyn', 'true'), ('UsedInP&R', 'true'), ('BelongTo', 'design_1'), ('CompileOrder', str(150+i))]:
        ET.SubElement(info, 'Attr', Name=key, Val=val)
tree.write(str(run / 'medal_kiosk_720p.prj'), encoding='utf-8', xml_declaration=True)
print('BGM candidate project prepared; baseline hashes unchanged.')
