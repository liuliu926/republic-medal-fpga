"""Create an isolated candidate; never alter the accepted FPGA input files."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
hdl = root / 'fpga/user_source_720p/hdl_source'
top = (hdl / 'top_fat32_all_article_voice_auto3.v').read_text(encoding='utf-8')

def replace_once(text, old, new):
    assert text.count(old) == 1, old
    return text.replace(old, new)

top = replace_once(top, 'wire article_text_mode;', '''wire article_text_mode;
wire [4:0] sequence_person;
wire [2:0] sequence_section;''')
top = replace_once(top, '.article_text_mode(article_text_mode),', '''.article_text_mode(article_text_mode),
    .loaded_person(sequence_person), .loaded_section(sequence_section),''')
top = replace_once(top, 'wire voice_requested = article_text_mode && display_level == 2 &&', '''// Navigation reaches the asset scheduler two clocks later. Do not arm PCM
// against the previous article while its replacement scene is still pending.
wire voice_requested = article_text_mode && display_level == 2 &&
    display_person == sequence_person && display_section == sequence_section &&''')
# Both clients register their one-cycle start strobes. The pending PCM strobe
# reserves the shared port before busy rises, just as sequence_start already
# prevents the PCM bridge from issuing while an image start is pending.
top = replace_once(top, '.shared_busy(diag_busy),', '.shared_busy(diag_busy || voice_start),')
(hdl / 'top_fat32_all_article_voice_scene_guard.v').write_text(top, encoding='utf-8')

seq = (hdl / 'SD/kiosk_fat32_sequence_autoplay_pilot.v').read_text(encoding='utf-8')
seq = replace_once(seq, 'output wire        article_text_mode,', '''output wire        article_text_mode,
    output wire [4:0]  loaded_person,
    output wire [2:0]  loaded_section,''')
seq = replace_once(seq, '    assign loading = loading_state;', '''    // Existing scene registers: no new storage, valid for playback only when
    // article_text_mode is asserted after both background and caption complete.
    assign loaded_person = person_q;
    assign loaded_section = section_q;
    assign loading = loading_state;''')
(hdl / 'SD/kiosk_fat32_sequence_scene_guard.v').write_text(seq, encoding='utf-8')

build = (root / 'tools/build_720p_all_article_voice_direct_start.tcl').read_text(encoding='utf-8')
build = build.replace('all_article_voice_direct_start_20261031', 'all_article_voice_scene_guard_20261031')
build = build.replace('medal_720p_all_article_voice_direct_start.bit', 'medal_720p_all_article_voice_scene_guard.bit')
build = build.replace('ALL_ARTICLE_VOICE_DIRECT_START_BUILD_COMPLETE', 'ALL_ARTICLE_VOICE_SCENE_GUARD_BUILD_COMPLETE')
anchor = 'set f [open [file join $run_dir medal_kiosk_720p.prj] w]'
assert anchor in build
build = build.replace(anchor, '''foreach source {top_fat32_all_article_voice_auto3.v kiosk_fat32_sequence_autoplay_pilot.v} {
 if {[string first $source $project_text] < 0} {error "Expected source missing: $source"}
}
set project_text [string map {
 top_fat32_all_article_voice_auto3.v top_fat32_all_article_voice_scene_guard.v
 kiosk_fat32_sequence_autoplay_pilot.v kiosk_fat32_sequence_scene_guard.v
} $project_text]
''' + anchor)
(root / 'tools/build_720p_all_article_voice_scene_guard.tcl').write_text(build, encoding='utf-8')
download = (root / 'download_720p_all_article_voice_direct_start.tcl').read_text(encoding='utf-8')
download = download.replace('direct_start', 'scene_guard').replace('DIRECT_START', 'SCENE_GUARD')
(root / 'download_720p_all_article_voice_scene_guard.tcl').write_text(download, encoding='utf-8')
print('Prepared isolated top, scene scheduler, build and download scripts.')
