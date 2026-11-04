"""Verify unchanged image dimming outside the small UI and render actual RTL pixels."""
from pathlib import Path
import subprocess
import argparse
from PIL import Image, ImageChops

parser = argparse.ArgumentParser()
parser.add_argument('--rounded', action='store_true')
args = parser.parse_args()
variant = 'brightness_rounded' if args.rounded else 'brightness_right'
root = Path(__file__).resolve().parents[1]
hdl = root / 'fpga/user_source_720p/hdl_source'
out = root / 'fpga/sim/runs' / variant
out.mkdir(parents=True, exist_ok=True)
def get_module(path):
    text = path.read_text(encoding='utf-8-sig')
    start = text.index('module brightness_popup_720p(')
    return text[start:text.index('endmodule', start)+len('endmodule')]
(out/'overlay.v').write_text(get_module(hdl/f'top_fat32_{variant}.v'), encoding='utf-8')
(out/'baseline.v').write_text(get_module(hdl/'top_fat32_all_article_voice_scene_guard.v').replace('brightness_popup_720p','brightness_baseline'), encoding='utf-8')
tb = '''`timescale 1ns/1ps
module tb;
reg de=1,visible=1; reg [10:0] x=0; reg [9:0] y=0;
reg [1:0] level=0; reg [23:0] rgb=24'h123456;
wire [23:0] result, baseline;
brightness_popup_720p dut(de,visible,x,y,level,rgb,result);
brightness_baseline reference(de,1'b0,x,y,level,rgb,baseline);
integer i,j,k,f,checks=0;
initial begin
 for(k=0;k<4;k=k+1) begin
  level=k;
  f=$fopen($sformatf("panel%0d.ppm",k),"wb");
  $fwrite(f,"P6\\n96 320\\n255\\n");
  for(j=0;j<720;j=j+1) begin
   y=j;
   for(i=0;i<1280;i=i+1) begin
    x=i; #1;
    if(!(i>=1208 && i<1256 && j>=256 && j<512) &&
       !(i>=1200 && i<1264 && j>=528 && j<544)) begin
      if(result!==baseline) $fatal(1,"Image modified outside right UI x=%0d y=%0d",i,j);
      checks=checks+1;
    end
    if(i>=1184 && j>=240 && j<560)
      $fwrite(f,"%c%c%c",result[23:16],result[15:8],result[7:0]);
   end
  end
  $fclose(f);
  // Hidden/blanking UI must preserve the exact original dimmer at any level.
  x=1220; y=280;
  for(i=0;i<256;i=i+1) begin
   rgb={i[7:0],~i[7:0],i[7:0]}; visible=0; de=1; #1;
   if(result!==baseline) $fatal(1,"Hidden overlay differs from baseline");
   visible=1; de=0; #1;
   if(result!==baseline) $fatal(1,"Blanking overlay differs from baseline");
  end
  rgb=24'h123456; visible=1; de=1;
 end
 $display("PASS: %0d background pixels unchanged outside right UI; original four gains retained with hidden/blanking checks.",checks);
 $finish;
end
endmodule
'''
(out/'tb.sv').write_text(tb, encoding='utf-8')
binpath = root/'tools/local_hdl/iverilog/app/bin'
subprocess.run([str(binpath/'iverilog.exe'),'-g2012','-s','tb','-o',str(out/'overlay.vvp'),str(out/'tb.sv'),str(out/'overlay.v'),str(out/'baseline.v')],cwd=out,check=True,timeout=30)
result=subprocess.run([str(binpath/'vvp.exe'),str(out/'overlay.vvp')],cwd=out,capture_output=True,text=True,timeout=90)
(out/'result.log').write_text(result.stdout+result.stderr,encoding='utf-8')
result.check_returncode()
assert 'PASS:' in result.stdout
print(result.stdout)
background=Image.open(root/'materials_review/preview_home_720p.png').convert('RGB').resize((1280,720))
sheet=Image.new('RGB',(96*4,320))
for level in range(4):
    panel=Image.open(out/f'panel{level}.ppm').convert('RGB')
    shift=3-level
    raw=(0x12>>shift,0x34>>shift,0x56>>shift)
    mask=ImageChops.difference(panel,Image.new('RGB',panel.size,raw)).convert('L').point(lambda v:255 if v else 0)
    image=background.point(lambda v:v>>shift)
    image.paste(panel,(1184,240),mask)
    image.save(out/f'preview_level{level+1}.png')
    sheet.paste(image.crop((1184,240,1280,560)),(level*96,0))
sheet.resize((768,640),Image.NEAREST).save(out/'four_levels_detail.png')
print('Rendered actual RTL overlay pixels: preview_level1..4.png, four_levels_detail.png')
