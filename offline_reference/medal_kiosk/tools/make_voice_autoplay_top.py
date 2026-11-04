"""Build an isolated pilot combining the existing autoplay and one voice clip."""
from pathlib import Path
p=Path(__file__).resolve().parents[1]/'fpga/user_source_720p/hdl_source'
s=(p/'top_fat32_voice_pilot.v').read_text(encoding='utf-8')
original=(p/'top_fat32_audio_tone_pilot.v').read_text(encoding='utf-8')
old='''assign auto_mode = 1'b0;
assign exit_to_home_pulse = 1'b0;
assign prompt_visible = 1'b0;
assign auto_level = 0; assign auto_person = 0; assign auto_section = 0; assign auto_page = 0;
'''
start=original.index('kiosk_mode u_kiosk_mode (')
end=original.index('kiosk_nav #(',start)
block=original[start:end].replace('kiosk_autoplay u_kiosk_autoplay (',
                                  'kiosk_autoplay #(.ARTICLE_CYCLES(600_000_000)) u_kiosk_autoplay (')
assert old in s
s=s.replace(old,block,1)
s=s.replace('display_person == 0 && display_section == 0 && display_page == 1 && !auto_mode;',
            'display_person == 0 && display_section == 0 && display_page == 1;',1)
s=s.replace('nav_section_sync2 == 0 && nav_page_sync2 == 1 && !auto_mode_sync2)',
            'nav_section_sync2 == 0 && nav_page_sync2 == 1)',1)
(p/'top_fat32_voice_autoplay.v').write_text(s,encoding='utf-8')
print('Prepared autoplay + voice candidate; automatic test does not modify stable bitstream')
