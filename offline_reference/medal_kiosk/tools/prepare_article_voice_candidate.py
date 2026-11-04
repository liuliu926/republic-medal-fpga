"""Derive an isolated candidate from the accepted SW4 brightness sources."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'fpga/user_source_720p/hdl_source'

def change(text, old, new):
    assert text.count(old) == 1, old
    return text.replace(old, new, 1)

top = (SRC / 'top_fat32_brightness_sw4.v').read_text(encoding='utf-8-sig')
top = change(top, '''((display_person <= 12 && display_section == 0 &&
      display_page >= 1 && display_page <= 4) ||
     (display_person == 0 && display_section == 1 && display_page == 1))''',
'''(display_person <= 12 && display_page >= 1 &&
     ((display_section <= 1 && display_page <= 4) ||
      (display_section == 2 && display_page <= 3)))''')
top = change(top, 'display_section == 1 ? "C" : "L"',
             'display_section == 0 ? "L" : display_section == 1 ? "C" : "D"')
top = change(top, 'home_text_mask u_home_text (', '''// Body cues follow consumed PCM samples; the heading is visible immediately.
wire article_voice_enabled = article_text_mode_video[1] && nav_level_sync2 == 2 &&
    nav_person_sync2 <= 12 && nav_page_sync2 >= 1 &&
    ((nav_section_sync2 == 1 && nav_page_sync2 <= 4) ||
     (nav_section_sync2 == 2 && nav_page_sync2 <= 3));
wire [1:0] article_row = nav_page_sync2[1:0] - 2'd1;
wire [6:0] article_slot = {nav_person_sync2[3:0], (nav_section_sync2 == 2), article_row};
wire [9:0] article_body_limit;
wire article_voice_finished;
article_voice_reveal u_article_voice_reveal (
    .clk(video_clk), .rst(rst_video),
    .active(article_voice_enabled && voice_requested_video[1]),
    .slot(article_slot), .samples_played(voice_samples),
    .body_limit(article_body_limit), .finished(article_voice_finished)
);

home_text_mask u_home_text (''')
top = change(top, '''.voice_active(nav_level_sync2 == 2 &&
        ((nav_person_sync2 <= 12 && nav_section_sync2 == 0 &&
          nav_page_sync2 >= 1 && nav_page_sync2 <= 4) ||
         (nav_person_sync2 == 0 && nav_section_sync2 == 1 && nav_page_sync2 == 1))),''',
'''.voice_active(nav_level_sync2 == 2 && nav_person_sync2 <= 12 &&
        nav_section_sync2 == 0 && nav_page_sync2 >= 1 && nav_page_sync2 <= 4),
    .article_voice_active(article_voice_enabled), .article_body_limit(article_body_limit),''')
top = change(top, '''.voice_generic((nav_person_sync2 >= 2 && nav_section_sync2 == 0) ||
                   (nav_person_sync2 == 0 && nav_section_sync2 == 1)),
    .voice_step_samples(nav_person_sync2 == 0 && nav_section_sync2 == 1 ?
                        13'd5900 : life_voice_step),''',
'''.voice_generic(nav_person_sync2 >= 2 && nav_section_sync2 == 0),
    .voice_step_samples(life_voice_step),''')
(SRC / 'top_fat32_all_article_voice.v').write_text(top, encoding='utf-8')

mask = (SRC / 'home_text_mask_voice_yu_contribution_pilot.v').read_text(encoding='utf-8-sig')
mask = change(mask, '    input wire voice_active,', '''    input wire voice_active,
    input wire article_voice_active,
    input wire [9:0] article_body_limit,''')
mask = change(mask, '''                if (voice_active && voice_line == 1 &&
                    atlas_x >= voice_text_limit) inside=0;
''', '')
mask = change(mask, '''    end
    reg [9:0] atlas_x_r;''', '''        // Each atlas row has a 32px heading band and a 32px body band.
        // In deeds, the date spans both bands at x<130 and remains visible.
        // Restrict the wipe to the current row; earlier rows stay complete.
        if (article_voice_active && (contribution_mode || deeds_mode) &&
            atlas_y[8:6] == voice_line && atlas_y[5] &&
            (!deeds_mode || atlas_x >= 130) && atlas_x >= article_body_limit)
            inside=0;
    end
    reg [9:0] atlas_x_r;''')
# Share coordinate arithmetic after selecting constant biases.
from share_text_geometry import share_geometry
mask = share_geometry(mask)
(SRC / 'home_text_mask_all_article_voice.v').write_text(mask, encoding='utf-8')
print('Prepared isolated top/mask candidate; accepted brightness sources unchanged.')
