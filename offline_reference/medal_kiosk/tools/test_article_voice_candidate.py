"""Exercise all cue timelines and verify unchanged overlay coordinate paths."""
import json
import shutil
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
src = root / 'fpga/user_source_720p/hdl_source'
out = root / 'fpga/sim/runs/all_article_voice'
out.mkdir(parents=True, exist_ok=True)
binpath = root / 'tools/local_hdl/iverilog/app/bin'
index = json.loads((root / 'assets_720p/audio_article_cues/cue_index.json').read_text(encoding='utf-8'))
shutil.copyfile(src / 'article_voice_cues.hex', out / 'article_voice_cues.hex')
checks = []
for clip in index:
    checks.append('start_clip(7\'d%d);' % clip['slot'])
    limit = 0
    for tick, x in clip['events']:
        checks.append('check_at(32\'d%d, 10\'d%d);' % (tick*64-1, limit))
        checks.append('check_at(32\'d%d, 10\'d%d);' % (tick*64, x))
        limit = x
    checks.append('if (!finished) $fatal(1,"Missing completion");')
    checks.append('check_at(32\'d%d, 10\'d768);' % clip['samples'])
tb = '''`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,active=0; reg [6:0] slot=0; reg [31:0] samples=0;
wire [9:0] limit; wire finished;
always #5 clk=~clk;
article_voice_reveal dut(clk,rst,active,slot,samples,limit,finished);
task wait_cycles; begin repeat(6) @(negedge clk); end endtask
task check_at(input [31:0] n,input [9:0] want); begin
 samples=n; wait_cycles;
 if (limit!==want) $fatal(1,"slot %d at %d got %d want %d",slot,n,limit,want);
 repeat(20) @(negedge clk);
 if (limit!==want) $fatal(1,"Advanced while PCM counter stalled");
end endtask
task start_clip(input [6:0] s); begin
 active=0; slot=s; samples=123456; wait_cycles;
 active=1; wait_cycles;
 if(limit!==0) $fatal(1,"Used stale previous PCM count");
 samples=0; wait_cycles;
 if(limit!==0) $fatal(1,"Body visible before narration");
end endtask
initial begin
 wait_cycles; rst=0;
 CHECKS
 start_clip(0); check_at(40000,16); // interrupted first clip, replay from zero
 start_clip(0); check_at(0,0);
 $display("PASS: 91 timelines, PCM stalls, old counters, replay and completion");
 $finish;
end
endmodule
'''.replace('CHECKS', '\n'.join(checks))
# Use the first cue's exact boundary rather than assuming a font width.
first_tick, first_x = index[0]['events'][0]
tb = tb.replace('check_at(40000,16)', 'check_at(%d,%d)' % (first_tick*64,first_x))
(out / 'tb_cues.sv').write_text(tb, encoding='ascii')
reference = (src / 'home_text_mask_voice_yu_contribution_pilot.v').read_text(encoding='utf-8')
(out / 'reference.v').write_text(reference.replace('module home_text_mask (', 'module home_text_mask_reference (',1), encoding='utf-8')
mask_tb = '''`timescale 1ns/1ps
module tb_mask;
reg clk=0; always #5 clk=~clk;
reg intro=0,article=0,contrib=0,deeds=0,quiz=0;
reg [2:0] step=1,line=1;
reg cue_active=0; reg[9:0] limit=0;
reg life_voice=0,answered=0,correct=0;
reg[9:0] year_limit=0,text_limit=0;
reg [10:0] xx=0; reg[9:0] yy=0;
wire[23:0] unused_a,unused_b;
home_text_mask candidate(COMMON,
 .article_voice_active(cue_active),.article_body_limit(limit),.rgb_out(unused_a));
home_text_mask_reference reference(COMMON,.rgb_out(unused_b));
integer m,x,y,r,k;
task compare_paths; begin
 if(candidate.inside!==reference.inside || (reference.inside &&
 (candidate.atlas_x!==reference.atlas_x || candidate.atlas_y!==reference.atlas_y)))
 $fatal(1,"Regression mode%d x%d y%d",m,xx,yy);
end endtask
task at(input integer x,input integer y,input integer expected); begin
 xx=x-2; yy=y; #1;
 if(candidate.inside!==expected[0]) $fatal(1,"Bad visibility at %d,%d",x,y);
end endtask
initial begin
 force candidate.x=xx; force candidate.y=yy;
 force reference.x=xx; force reference.y=yy;
 for(m=0;m<6;m=m+1) begin
 intro=(m==1); article=(m>=2); contrib=(m==3); deeds=(m==4); quiz=(m==5);
 step=4; cue_active=0;
 for(y=0;y<720;y=y+1) for(x=0;x<1280;x=x+1) begin xx=x;yy=y;#1;compare_paths;end
 end
 // The shared arithmetic must also preserve life wipes and quiz feedback.
 article=1;intro=0;contrib=0;deeds=0;quiz=0;life_voice=1;
 force candidate.voice_year_limit=year_limit; force reference.voice_year_limit=year_limit;
 force candidate.voice_text_limit=text_limit; force reference.voice_text_limit=text_limit;
 for(r=1;r<=4;r=r+1) for(k=0;k<3;k=k+1) begin
 line=r;year_limit=(k==0)?2:(k==1)?38:90;text_limit=(k==0)?183:(k==1)?300:768;
 for(y=40;y<610;y=y+8) for(x=0;x<1280;x=x+1) begin xx=x;yy=y;#1;compare_paths;end
 end
 life_voice=0;quiz=1;answered=1;
 for(k=0;k<2;k=k+1) begin
 correct=k;
 for(y=110;y<143;y=y+1) for(x=500;x<680;x=x+1) begin xx=x;yy=y;#1;compare_paths;end
 end
 answered=0;
 // First title fully visible, body hidden; earlier lines remain complete.
 article=1; intro=0; quiz=0; contrib=1;deeds=0;step=4;cue_active=1;line=1;limit=0;
 at(90,200,1); at(90,230,0); at(690,230,1);
 limit=30; at(100,230,1); at(120,230,0);
 for(r=1;r<=4;r=r+1) begin
 line=r;limit=0;
 at((r==2||r==4)?682:90,(r>=3)?435:200,1);
 at((r==2||r==4)?682:90,(r>=3)?465:230,0);
 end
 // Deeds' date overlaps lower band and must remain intact.
 contrib=0; deeds=1; line=1; limit=0;
 at(70,230,1); at(210,200,1); at(210,230,0); at(210,380,1);
 limit=180; at(230,230,1); at(250,230,0);
 $display("PASS: full-frame mapping unchanged for 6 modes; title/body split and deeds date");
 $finish;
end
endmodule
'''
common = '''.write_clk(clk),.write_rst(1'b1),.pixel_start(1'b0),.pixel_valid(1'b0),.pixel_data(24'd0),
 .video_clk(clk),.video_rst(1'b1),.vs(1'b0),.de(1'b1),.intro_mode(intro),
 .article_mode(article),.contribution_mode(contrib),.deeds_mode(deeds),.quiz_mode(quiz),
 .quiz_revealed(answered),.quiz_correct(correct),.quiz_choice(2'b0),.voice_active(life_voice),
 .voice_shen(1'b0),.voice_generic(1'b0),.voice_step_samples(13'd4000),
 .voice_line(line),.voice_samples(32'd0),.reveal_step(step),.rgb_in(24'd0)'''
(out / 'tb_mask.sv').write_text(mask_tb.replace('COMMON',common),encoding='ascii')
for name, files in [('cues',[src/'article_voice_reveal.v']),
                    ('mask',[src/'home_text_mask_all_article_voice.v',out/'reference.v',root/'fpga/sim/eg_phy_bram32k_behavioral.v'])]:
    cmd=[str(binpath/'iverilog.exe'),'-g2005','-s','tb' if name=='cues' else 'tb_mask',
         '-o',str(out/(name+'.vvp')),str(out/('tb_'+name+'.sv'))]+[str(p) for p in files]
    subprocess.run(cmd,cwd=str(out),check=True)
    result=subprocess.run([str(binpath/'vvp.exe'),str(out/(name+'.vvp'))],cwd=str(out),capture_output=True,text=True,timeout=180)
    print(result.stdout,result.stderr)
    if result.returncode: raise SystemExit(result.returncode)
