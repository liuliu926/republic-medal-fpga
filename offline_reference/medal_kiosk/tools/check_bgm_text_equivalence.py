"""Compare actual old/new subtitle RTL over all line/mode cue sequences."""
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[1]
src = root / 'fpga/user_source_720p/hdl_source'
run = root / 'fpga/sim/runs/bgm_text_equivalence'
run.mkdir(parents=True, exist_ok=True)
old = (src / 'home_text_mask_all_article_voice.v').read_text(encoding='utf-8')
new = (src / 'home_text_mask_bgm_compact.v').read_text(encoding='utf-8')
(run / 'reference.v').write_text(old.replace('module home_text_mask (','module home_text_reference (',1), encoding='utf-8')
ports = old.split(');',1)[0].split('module home_text_mask (',1)[1]
decl=[]; connections=[]
for line in ports.splitlines():
    if 'input wire' in line:
        expr=line.strip()[len('input wire'):].strip().rstrip(',')
        match=re.match(r'(\[[^\]]+\])?\s*(.*)',expr)
        width=match.group(1) or ''
        for name in match.group(2).split(','):
            name=name.strip()
            decl.append('reg %s %s=0;' % (width,name))
            connections.append('.%s(%s)'%(name,name))
conn=','.join(connections)
tb='''`timescale 1ns/1ps
module tb;
'''+ '\n'.join(decl)+'''
wire [23:0] a,b;
integer scenario,ln,n,checks=0;
always #5 video_clk=~video_clk;
always #7 write_clk=~write_clk;
home_text_reference ref_dut('''+conn+''',.rgb_out(a));
home_text_mask new_dut('''+conn+''',.rgb_out(b));
task check;
begin
 if ({ref_dut.voice_year_limit,ref_dut.voice_text_limit,ref_dut.voice_index,ref_dut.voice_next,ref_dut.voice_line_q}
 !== {new_dut.voice_year_limit,new_dut.voice_text_limit,new_dut.voice_index,new_dut.voice_next,new_dut.voice_line_q})
 $fatal(1,"cue mismatch scenario=%0d line=%0d sample=%0d",scenario,ln,voice_samples);
 if (a !== b || ref_dut.addr !== new_dut.addr || ref_dut.inside !== new_dut.inside)
 $fatal(1,"pixel mapping mismatch");
 checks=checks+1;
end
endtask
initial begin
 write_rst=1; video_rst=1;
 repeat(4) @(negedge video_clk); write_rst=0; video_rst=0;
 for(scenario=0;scenario<16;scenario=scenario+1) begin
  voice_generic=scenario[0]; voice_shen=scenario[1];
  contribution_mode=scenario[2]; deeds_mode=scenario[3];
  article_mode=1; article_voice_active=1; reveal_step=4;
  for(ln=0;ln<8;ln=ln+1) begin
   voice_active=0; voice_samples=0; voice_line=ln; voice_step_samples=1500+ln*500;
   @(negedge video_clk); check(); voice_active=1;
   for(n=0;n<700;n=n+1) begin
    voice_samples=n*400; article_body_limit=n; de=(n%7!=0); vs=(n%401==0);
    @(negedge video_clk); check();
   end
  end
 end
 // Change every control while the old/new sequencers are live.
 for(n=0;n<5000;n=n+1) begin
  {voice_active,voice_generic,voice_shen,contribution_mode,deeds_mode,voice_line}= $random;
  voice_samples=$random; voice_step_samples=$random;
  @(negedge video_clk); check();
 end
 $display("PASS old/new actual RTL cue registers, pixel mapping and RGB: %0d cycles",checks);
 $finish;
end
endmodule
'''
(run / 'tb.sv').write_text(tb, encoding='utf-8')
bindir=root/'tools/local_hdl/iverilog/app/bin'
commands=[
 [str(bindir/'iverilog.exe'),'-g2005','-s','tb','-o',str(run/'test.vvp'),str(run/'tb.sv'),str(run/'reference.v'),str(src/'home_text_mask_bgm_compact.v'),str(root/'fpga/sim/eg_phy_bram32k_behavioral.v')],
 [str(bindir/'vvp.exe'),str(run/'test.vvp')]]
logs=[]
for cmd in commands:
 result=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=120)
 logs.append(result.stdout); print(result.stdout)
 (run/'result.log').write_text('\n'.join(logs),encoding='utf-8')
 if result.returncode: raise SystemExit(result.returncode)
