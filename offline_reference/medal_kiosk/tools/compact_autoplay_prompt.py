"""Create a compact BRAM glyph ROM in the autoplay candidate only."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
path=Path(__file__).resolve().parents[1]/'fpga/user_source_720p/hdl_source/top_fat32_autoplay_pilot.v'
source=path.read_text(encoding='utf-8')
start=source.index('// Diagnostic: compare whole home-frame FIFO output')
end=source.index('wire        sd_card_write_en;',start)
source=source[:start]+source[end:]
source=source.replace("hash_changed_clk[1] ? 4'd2 : hash_valid_clk[1] ? 4'd1 : 4'd0", "{2'b00,diag_sd_ready,Sdr_init_done}")
start=source.index('// A prompt-only overlay for the 1280x720 TF-backed presentation.')
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',14)
rows=[]
for char in '拨SW3退出轮播':
    im=Image.new('L',(16,16),0); ImageDraw.Draw(im).text((0,-2),char,font=font,fill=255)
    for y in range(16):
        value=0
        for x in range(16): value=(value<<1)|(1 if im.getpixel((x,y))>=96 else 0)
        rows.append(value)
assert len(rows)==128
init='\n'.join("    rom[%d] = 16'h%04X;"%(i,v) for i,v in enumerate(rows))
module='''// Prompt-only BRAM glyph overlay, eight 16x16 characters.
module autoplay_prompt_720p(input wire clk,rst,vs,de,visible,
    input wire [23:0] rgb_in, output reg [23:0] rgb_out);
reg [15:0] rom [0:127];
initial begin
%s
end
reg [10:0] x; reg [9:0] y; reg last_de,last_vs;
wire [7:0] px=x-11'd512;
wire [5:0] py=y-10'd70;
reg [15:0] glyph; reg [3:0] glyph_x; reg text_active;
always @(posedge clk or posedge rst) begin
    if (rst) begin x<=0; y<=0; last_de<=0; last_vs<=0; glyph<=0; glyph_x<=0; text_active<=0; end
    else begin
        last_de<=de; last_vs<=vs;
        glyph<=rom[{px[7:5],py[4:1]}]; glyph_x<=px[4:1];
        text_active<=de && x>=512 && x<768 && y>=70 && y<102;
        if (vs != last_vs) begin x<=0; y<=0; end
        else begin if (de) x<=x+1'b1; else x<=0; if(last_de && !de) y<=y+1'b1; end
    end
end
always @* begin
    rgb_out=rgb_in;
    if (visible && de && x>=480 && x<800 && y>=50 && y<120) begin
        rgb_out=(x<484 || x>=796 || y<54 || y>=116) ? 24'hFFD34E : 24'h9C0018;
        if (text_active && glyph[15-glyph_x]) rgb_out=24'hFFF1CD;
    end
end
endmodule
''' % init
path.write_text(source[:start]+module,encoding='utf-8')
print('Compacted prompt ROM; removed completed hash diagnostic.')
