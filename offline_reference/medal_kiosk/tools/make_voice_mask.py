"""Add an isolated sample-indexed character reveal to the Yu Min life row."""
import json, math
from pathlib import Path
from PIL import ImageFont
root=Path(__file__).resolve().parents[1]
source=root/'fpga/user_source_720p/hdl_source/home_text_mask_all_quiz.v'
out=root/'fpga/user_source_720p/hdl_source/home_text_mask_voice_pilot.v'
s=source.read_text(encoding='utf-8')
s=s.replace('    input wire [2:0] reveal_step,', '    input wire voice_active,\n    input wire [31:0] voice_samples,\n    input wire [2:0] reveal_step,',1)
s=s.replace('    reg mask_ram [0:245759];', '''    // 30 explicit 8K banks avoid allocating two unused banks in a 2^18 RAM.
    wire [29:0] bank_q;
    wire [17:0] addr;
    reg [4:0] read_bank;
    genvar b;
    generate for (b=0; b<30; b=b+1) begin: g_mask_bank
        reg bits [0:8191];
        reg q;
        always @(posedge write_clk)
            if (pixel_valid && !ready && write_addr[17:13] == b)
                bits[write_addr[12:0]] <= pixel_data[23];
        always @(posedge video_clk) if (inside_r) q <= bits[addr[12:0]];
        assign bank_q[b] = q;
    end endgenerate''',1)
s=s.replace('            mask_ram[write_addr] <= pixel_data[23];\n','',1)
s=s.replace('    wire [17:0] addr =', '    assign addr =',1)
s=s.replace('    reg mask_q, inside_q;', '    wire mask_q = read_bank < 30 ? bank_q[read_bank] : 1\'b0;\n    reg inside_q;',1)
s=s.replace('        if (inside_r) mask_q <= mask_ram[addr];', '        if (inside_r) read_bank <= addr[17:13];',1)
data=json.loads((root/'assets_720p/audio_pilot/yumin_1926_character_cues.json').read_text(encoding='utf-8'))['cues']
yearfont=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',31)
textfont=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',25)
year=''; desc=''; lines=[]
for idx,cue in enumerate(data):
    if idx<4:
        year+=cue['character']; limit=2+yearfont.getsize(year)[0]
        update=f"voice_year_limit <= 10'd{limit};"
    else:
        desc+=cue['character']; limit=183+textfont.getsize(desc)[0]
        update=f"voice_text_limit <= 10'd{limit};"
    nxt=data[idx+1]['start_sample'] if idx+1<len(data) else 262143
    lines.append(f"          5'd{idx}: begin {update} voice_next <= 18'd{nxt}; end")
insertion='''    reg [9:0] voice_year_limit, voice_text_limit;
    reg [4:0] voice_index;
    reg [17:0] voice_next;
    always @(posedge video_clk or posedge video_rst) begin
      if (video_rst || !voice_active) begin
        voice_year_limit<=10'd2; voice_text_limit<=10'd183;
        voice_index<=0; voice_next<=0;
      end else if (voice_index < 21 && voice_samples[17:0] >= voice_next) begin
        case (voice_index)
'''+ '\n'.join(lines)+'''
          default: voice_next <= 18'd262143;
        endcase
        voice_index <= voice_index + 1'b1;
      end
    end
'''
s=s.replace('    reg [10:0] x;',insertion+'    reg [10:0] x;',1)
needle='''                if (reveal_step >= 3'd1 && y >= 10'd180 && y < 10'd244) begin
                    inside=1; atlas_y=9'd64+y-10'd180;'''
replacement='''                if (reveal_step >= 3'd1 && y >= 10'd180 && y < 10'd244) begin
                    inside=1; atlas_y=9'd64+y-10'd180;
                    if (voice_active && ((atlas_x < 126 && atlas_x >= voice_year_limit) ||
                        (atlas_x >= 183 && atlas_x >= voice_text_limit))) inside=0;'''
assert needle in s
s=s.replace(needle,replacement,1)
out.write_text(s,encoding='utf-8')
print('Prepared character reveal,',len(data),'sample cues')
