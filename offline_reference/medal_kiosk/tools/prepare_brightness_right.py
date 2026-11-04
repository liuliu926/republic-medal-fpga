"""Derive a UI-only candidate from the frozen, accepted scene-guard source."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import hashlib

root = Path(__file__).resolve().parents[1]
hdl = root / 'fpga/user_source_720p/hdl_source'
baseline = root / 'releases/all_article_voice_scene_guard_20261031/source_snapshot/fpga/user_source_720p/hdl_source/top_fat32_all_article_voice_scene_guard.v'
text = baseline.read_text(encoding='utf-8-sig')
begin = text.index('// SW4 opens a local brightness control.')
end = text.index('// Prompt-only BRAM glyph overlay', begin)
original_module = text[begin:end]
dimmer = original_module[original_module.index('function [7:0] dim_component;'):original_module.index('wire [10:0] x = pixel_x;')]

# Only four static glyphs: no TF changes, no additional card transactions.
font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 16)
rows = []
for ch in '亮度调节':
    canvas = Image.new('L', (48, 48))
    ImageDraw.Draw(canvas).text((0,0), ch, font=font, fill=255)
    glyph = canvas.crop(canvas.getbbox())
    im = Image.new('L', (16, 16))
    im.paste(glyph, ((16-glyph.width)//2, (16-glyph.height)//2))
    for y in range(16):
        rows.append(sum((im.getpixel((x,y)) >= 96) << (15-x) for x in range(16)))
glyph_case = '\n'.join(f"            6'd{i}: label_row = 16'h{r:04X};" for i,r in enumerate(rows))
module = '''// SW4 right-edge brightness indicator. The original four dimmer gains and
// control inputs are retained; four bordered cells fill from bottom to top.
// Only the cells and Chinese glyph pixels cover the background.
module brightness_popup_720p(
    input wire de, visible,
    input wire [10:0] pixel_x,
    input wire [9:0] pixel_y,
    input wire [1:0] level,
    input wire [23:0] rgb_in,
    output reg [23:0] rgb_out
);
''' + dimmer + '''function [15:0] label_row;
    input [5:0] address;
    begin
        case (address)
''' + glyph_case + '''
            default: label_row = 16'h0000;
        endcase
    end
endfunction
wire [10:0] x = pixel_x;
wire [9:0] y = pixel_y;
wire [5:0] label_x = x - 11'd1200;
wire [15:0] glyph_row = label_row({label_x[5:4], y[3:0]});
wire [1:0] first_filled_cell = ~level;
wire cell_border = x < 11'd1210 || x >= 11'd1254 ||
                   y[5:0] < 6'd2 || y[5:0] >= 6'd62;
always @* begin
    rgb_out = {dim_component(rgb_in[23:16], level),
               dim_component(rgb_in[15:8], level),
               dim_component(rgb_in[7:0], level)};
    if (visible && de) begin
        if (x >= 11'd1208 && x < 11'd1256 && y >= 10'd256 && y < 10'd512)
            rgb_out = cell_border ? 24'hFFF2D0 :
                      (y[7:6] >= first_filled_cell ? 24'hFFD34E : 24'h6D3540);
        if (x >= 11'd1200 && x < 11'd1264 && y >= 10'd528 && y < 10'd544 &&
            glyph_row[15-label_x[3:0]])
            rgb_out = 24'hFFF2D0;
    end
end
endmodule

'''
candidate = hdl / 'top_fat32_brightness_right.v'
candidate.write_text(text[:begin]+module+text[end:], encoding='utf-8')
assert candidate.read_text(encoding='utf-8').replace(module, original_module) == text
print('Created UI-only candidate; all logic outside brightness_popup_720p is identical to accepted scene_guard.')
print('Candidate SHA256:', hashlib.sha256(candidate.read_bytes()).hexdigest().upper())
