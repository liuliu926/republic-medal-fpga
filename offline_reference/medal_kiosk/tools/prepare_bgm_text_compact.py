"""Isolate an equivalent one-adder subtitle timing implementation for BGM."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
src = root / 'fpga/user_source_720p/hdl_source'
old = (src / 'home_text_mask_all_article_voice.v').read_text(encoding='utf-8')
start = old.index('        if (voice_generic) begin')
end = old.index('        voice_index <= voice_index +', start)
timing = old[start:end]
timing = re.sub(r'voice_next <= voice_next \+ ([^;]+);', r'next_delta = \1;', timing)
timing = re.sub(r'voice_next <= ([^;]+);', r'begin next_base = \1; next_delta = 0; end', timing)
assert 'voice_next <=' not in timing
comb = '''    // Select operands before a single 18-bit adder. All original cue
    // constants and update conditions are retained exactly.
    reg [17:0] next_base, next_delta;
    always @* begin
        next_base = voice_next; next_delta = 0;
''' + timing + '''    end
'''
new = old[:start] + '        voice_next <= next_base + next_delta;\n' + old[end:]
marker = '    always @(posedge video_clk or posedge video_rst) begin'
assert new.count(marker) == 2
new = new.replace(marker, comb + marker, 1)
(src / 'home_text_mask_bgm_compact.v').write_text(new, encoding='utf-8')
print('Isolated subtitle timing candidate generated.')
