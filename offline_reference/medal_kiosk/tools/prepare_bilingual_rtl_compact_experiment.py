from pathlib import Path
import re, shutil
from PIL import Image, ImageDraw, ImageFont
R=Path(__file__).resolve().parents[1]; H=R/'fpga/user_source_720p/hdl_source'
t=(H/'top_volume_brightness_candidate.v').read_text(encoding='utf-8')
t=t.replace('input                       sw4,','input                       sw2,\n    input                       sw4,',1)
t=t.replace('reg [1:0] sw4_sync;','reg [1:0] sw4_sync;\nreg [1:0] language_sync;\nwire loaded_english;\nreg [1:0] english_video;\nalways @(posedge clk or posedge rst_all) begin\n if(rst_all) language_sync<=0; else language_sync<={language_sync[0],sw2};\nend\nalways @(posedge video_clk or posedge rst_video) begin\n if(rst_video) english_video<=0; else english_video<={english_video[0],loaded_english};\nend')
t=t.replace('kiosk_fat32_sequence_menu u_sequence (','kiosk_fat32_sequence_menu u_sequence (\n    .english(language_sync[1]), .loaded_english(loaded_english),')
t=t.replace('home_text_mask u_home_text (','home_text_mask u_home_text (\n    .english(english_video[1]),')
t=t.replace('home_text_mask u_home_text (', '''reg english_clip_done_sd;
reg [1:0] english_clip_done_video;
always @(posedge sd_card_clk or posedge rst_all) begin
 if(rst_all) english_clip_done_sd<=0;
 else if(!voice_requested) english_clip_done_sd<=0;
 else if(voice_done) english_clip_done_sd<=1;
end
always @(posedge video_clk or posedge rst_video) begin
 if(rst_video) english_clip_done_video<=0;
 else english_clip_done_video<={english_clip_done_video[0],english_clip_done_sd};
end
home_text_mask u_home_text (
    .clip_complete(english_clip_done_video[1]),''')
t=t.replace('autoplay_prompt_720p u_autoplay_prompt (','autoplay_prompt_720p u_autoplay_prompt (\n    .english(english_video[1]),')
t=t.replace('.volume_level(volume_level_video), .selected(popup_selected_video),','.volume_level(volume_level_video), .selected(popup_selected_video), .english(english_video[1]),')
t=t.replace('input wire [1:0] volume_level,','input wire english,\n    input wire [1:0] volume_level,')
# English bitmap labels use the same 32x16 area as the existing Chinese labels.
fn='function [15:0] english_label_row;\ninput [5:0] address;\nbegin case(address)\n'
for b,word in enumerate(['Light','Vol']):
 im=Image.new('1',(32,16)); ImageDraw.Draw(im).text((0,0),word,font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',12),fill=1)
 for c in range(2):
  for y in range(16):
   bits=sum(int(im.getpixel((c*16+x,y))!=0)<<(15-x) for x in range(16))
   fn+=f"6'd{b*32+c*16+y}: english_label_row=16'h{bits:04x};\n"
fn+="default:english_label_row=0; endcase end endfunction\n"
t=t.replace('wire [15:0] glyph_row = label_left ?',fn+'wire [15:0] glyph_row = english ? english_label_row({!label_left,glyph_address}) : label_left ?')
t=t.replace('module autoplay_prompt_720p(input wire clk,rst,vs,de,visible,','module autoplay_prompt_720p(input wire clk,rst,vs,de,visible,english,')
t=t.replace('reg [15:0] rom [0:127];','reg [15:0] rom [0:255];')
im=Image.new('1',(128,16)); ImageDraw.Draw(im).text((0,0),'SW3 OFF TO EXIT',font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',13),fill=1)
rom=''
for c in range(8):
 for y in range(16):
  bits=sum(int(im.getpixel((c*16+x,y))!=0)<<(15-x) for x in range(16))
  rom+=f"rom[{128+c*16+y}]=16'h{bits:04x};\n"
t=t.replace('end\nreg [10:0] x; reg [9:0] y; reg last_de,last_vs;',rom+'end\nreg [10:0] x; reg [9:0] y; reg last_de,last_vs;')
t=t.replace('glyph<=rom[{px[7:5],py[4:1]}]','glyph<=rom[{english,px[7:5],py[4:1]}]')
(H/'top_bilingual_candidate.v').write_text(t,encoding='utf-8')
s=(H/'SD/kiosk_fat32_sequence_focus.v').read_text(encoding='utf-8')
s=s.replace('input  wire        mem_ready,','input wire english,\n    output wire loaded_english,\n    input  wire        mem_ready,')
s=s.replace('reg [3:0] state;','reg [3:0] state;\nreg language_q;\nassign loaded_english=language_q;')
# Substitute only the language byte of text filenames, not any audio filename.
s=s.replace('target_sfn="HOMETXT BMP"','target_sfn=language_q ? "HOMEENG BMP" : "HOMETXT BMP"')
end=s.index('\n    always @(posedge clk')
s=s[:end].replace('\n        endcase\n    end','\n        endcase\n        if(language_q && (state==S_PTEXT || state==S_ATEXT)) begin\n            if(state==S_PTEXT || (state==S_ATEXT && section_q!=3)) target_sfn[39:32]="E";\n            else target_sfn[31:24]="E";\n        end\n    end')+s[end:]
# ITX01C and ART03C C byte is character index 5 = bits47:40, quiz3C index5 too;
# QUIZ02C has C at index6. Correct individual cases explicitly below.
s=s.replace('if(state==S_PTEXT || (state==S_ATEXT && section_q!=3)) target_sfn[39:32]="E";\n            else target_sfn[31:24]="E";', 'if(state==S_PTEXT || section_q!=3 || person_q==0) target_sfn[47:40]="E";\n            else target_sfn[39:32]="E";')
s=re.sub(r'        if\(language_q &&.*?\n        end\n', '', s, flags=re.S)
s=s.replace('output reg [87:0]  target_sfn,','output wire [87:0] target_sfn,')
s=s.replace('target_sfn =','raw_sfn =').replace('target_sfn=','raw_sfn=')
s=s.replace('reg language_q;','reg language_q;\nreg [87:0] raw_sfn;\nwire translate_text=language_q && (state==S_PTEXT || state==S_ATEXT);\nassign target_sfn=translate_text ? ((state==S_PTEXT || section_q!=3 || person_q==0) ?\n {raw_sfn[87:48],8\'h45,raw_sfn[39:0]} : {raw_sfn[87:40],8\'h45,raw_sfn[31:0]}) : raw_sfn;')
s=s.replace('state <= S_BG;\n            issued',"language_q <= 0;\n            state <= S_BG;\n            issued",1)
s=s.replace('end else if (state == S_HOME) begin','end else if ((state==S_HOME || state==S_PERSON || state==S_ARTICLE) && language_q!=english) begin\n                language_q<=english;\n                if(state==S_HOME) state<=S_RETURN_TEXT;\n                else if(state==S_PERSON) state<=S_PTEXT;\n                else state<=S_ATEXT;\n            end else if (state == S_HOME) begin')
s=s.replace('else state<=S_ATEXT;', 'else if(section_q==1) state<=S_ABG; else state<=S_ATEXT;')
s=s.replace(' : raw_sfn;', " : (language_q && state==S_ABG && section_q==1 ? {raw_sfn[87:80],8'h45,raw_sfn[71:0]} : raw_sfn);")
(H/'SD/kiosk_fat32_sequence_bilingual.v').write_text(s,encoding='utf-8')
m=(H/'home_text_mask_vertical_contrib_v2.v').read_text(encoding='utf-8').replace('input wire intro_mode,','input wire english,\n    input wire intro_mode,')
needle='        end else if (article_mode && contribution_mode) begin'
branch='''        end else if (article_mode && contribution_mode && english) begin
            if(de && next_x>=80 && next_x<680 && y>=46 && y<110) begin
                inside=1; x_bias=944; y_bias=466;
            end else if(de && next_x>=342 && next_x<1110) begin
                x_bias=682;
                if(reveal_step>=1 && y>=180 && y<244) begin inside=1; y_bias=396; end
                else if(reveal_step>=2 && y>=298 && y<362) begin inside=1; y_bias=342; end
                else if(reveal_step>=3 && y>=412 && y<476) begin inside=1; y_bias=292; end
                else if(reveal_step>=4 && y>=534 && y<598) begin inside=1; y_bias=234; end
            end
'''
m=m.replace(needle,needle.replace('contribution_mode)', 'contribution_mode && !english)'))
m=m.replace('else if (de && next_x >= 11\'d55', 'else if (!contribution_mode && de && next_x >= 11\'d55')
m=m.replace('else if (de && next_x >= 11\'d100', 'else if (!contribution_mode && de && next_x >= 11\'d100')
m=m.replace('        if (article_voice_active && deeds_mode &&','        if(english && article_voice_active && contribution_mode && atlas_y[8:6]==voice_line && atlas_y[5] &&\n           {5\'d0,atlas_x} >= ( {5\'d0,article_body_limit} << 5)) inside=0;\n        if (article_voice_active && deeds_mode &&')
m=m.replace('wire gold_letter = article_mode && contribution_mode &&','wire gold_letter = article_mode && contribution_mode &&\n                       (english ? !atlas_y_r[5] : 1\'b1) &&')
m=m.replace('input wire english,', 'input wire english, clip_complete,')
m=m.replace('if (article_mode && !quiz_mode', 'if (!(english && clip_complete) && article_mode && !quiz_mode')
m=m.replace('if(english && article_voice_active', 'if(english && !clip_complete && article_voice_active')
m=m.replace('if (article_voice_active && deeds_mode', 'if (!(english && clip_complete) && article_voice_active && deeds_mode')
# Chinese vertical headings are selected by x-band; English headings by atlas top half.
m=m.replace("atlas_y_r[8:6] != 0 && atlas_y_r[5:0] >= 40;","atlas_y_r[8:6] != 0 && (english || atlas_y_r[5:0] >= 40);")
(H/'home_text_mask_bilingual.v').write_text(m,encoding='utf-8')
run=R/'fpga/td_project_720p/cli_runs/bilingual_20261101'; run.mkdir(exist_ok=True)
old=R/'fpga/td_project_720p/cli_runs/volume_brightness_20261101'
prj=(old/'medal_kiosk_720p.prj').read_text(encoding='utf-8').replace('top_volume_brightness_candidate.v','top_bilingual_candidate.v').replace('kiosk_fat32_sequence_focus.v','kiosk_fat32_sequence_bilingual.v').replace('home_text_mask_vertical_contrib_v2.v','home_text_mask_bilingual.v')
(run/'medal_kiosk_720p.prj').write_text(prj,encoding='utf-8'); shutil.copy2(old/'article_voice_cues.hex',run/'article_voice_cues.hex')
adc=R/'fpga/user_source_720p/constraints_source'
(adc/'pin_bilingual.adc').write_text((adc/'pin_brightness_sw4.adc').read_text()+ '\nset_pin_assignment { sw2 } { LOCATION = C7; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }\n')
b=(R/'tools/build_720p_volume_brightness.tcl').read_text().replace('volume_brightness_20261101','bilingual_20261101').replace('pin_brightness_sw4.adc','pin_bilingual.adc').replace('medal_720p_volume_brightness_seed1.bit','medal_720p_bilingual.bit')
(R/'tools/build_720p_bilingual.tcl').write_text(b)
d=(R/'tools/download_720p_volume_brightness.tcl').read_text().replace('volume_brightness_20261101','bilingual_20261101').replace('medal_720p_volume_brightness_seed1.bit','medal_720p_bilingual.bit')
(R/'tools/download_720p_bilingual.tcl').write_text(d)
print('Bilingual RTL candidate prepared')
