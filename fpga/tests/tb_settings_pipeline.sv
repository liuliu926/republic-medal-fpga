`timescale 1ns/1ps
module tb_settings_pipeline;
reg clk=0;always #5 clk=~clk;
reg rst=1,de=0,vs=0,visible=0,english=0,selected=0;
reg [10:0] x=0;reg [9:0] y=0;
reg [3:0] level=10,volume_level=10;
reg [5:0] gain=32;
reg [23:0] rgb=0;
wire [23:0] pixel_out,reference;
wire de_out,vs_out;wire [5:0] gain_out;
brightness_popup_720p dut(.clk(clk),.rst(rst),.de(de),.vs(vs),.visible(visible),
 .pixel_x(x),.pixel_y(y),.level(level),.volume_level(volume_level),
 .english(english),.selected(selected),.fade_gain_in(gain),.fade_gain_out(gain_out),
 .rgb_in(rgb),.rgb_out(pixel_out),.de_out(de_out),.vs_out(vs_out));
settings_percent_renderer_reference oracle(.de(de),.visible(visible),.pixel_x(x),.pixel_y(y),
 .level(level),.volume_level(volume_level),.english(english),.selected(selected),.rgb_in(rgb),.rgb_out(reference));
reg signed [23:0] audio_in=0;reg [3:0] audio_step=10;reg sample_valid=0;
wire signed [23:0] audio_out,audio_reference;
wire sample_out_valid;
audio_volume_percent_pipeline adut(.clk(clk),.rst(rst),.sample_valid(sample_valid),.sample_in(audio_in),
 .step(audio_step),.sample_out_valid(sample_out_valid),.sample_out(audio_out));
audio_volume_percent aref(.sample_in(audio_in),.step(audio_step),.sample_out(audio_reference));
reg [23:0] pixel_expected=0,pixel_held=0;
reg de_expected=0,vs_expected=0,de_held=0,vs_held=0;
reg [5:0] gain_expected=0,gain_held=0;
reg audio_valid_expected=0,audio_valid_held=0;
reg signed [23:0] audio_expected=0,audio_held=0;
integer warm=0,checks=0,pixels=0,audio_samples=0,cycles=0;
integer i,j,k,s,lang,fd,px,py;
reg [31:0] rng=32'h816492c5;
reg [1023:0] filename;

task verify(input bit good,input [511:0] message_text);
begin checks=checks+1;if(!good)begin
 $display("FAIL %0s cycle=%0d xy=%0d,%0d step=%0d out=%h expected=%h",message_text,cycles,x,y,level,pixel_out,pixel_held);
 $fatal(1);end
end endtask
// Inputs are set just after a falling edge. Both implementations sample on
// rising edge N; two sequential stages expose the corresponding result after N+1.
task tick;
begin
 #1;pixel_expected=reference;de_expected=de;vs_expected=vs;gain_expected=gain;
 audio_valid_expected=sample_valid;audio_expected=audio_reference;
 @(posedge clk);#1;cycles=cycles+1;
 if(warm>0)begin
  verify(pixel_out===pixel_held,"two-stage RGB and OSD match combinational oracle");
  verify(de_out===de_held && vs_out===vs_held,"two-stage DE/VS alignment");
  verify(gain_out===gain_held,"two-stage fade alignment");pixels=pixels+1;
 end
 verify(sample_out_valid===audio_valid_held,"two-stage audio valid alignment");
 if(audio_valid_held)begin verify(audio_out===audio_held,"two-stage signed audio sample");audio_samples=audio_samples+1;end
 pixel_held=pixel_expected;de_held=de_expected;vs_held=vs_expected;gain_held=gain_expected;
 audio_valid_held=audio_valid_expected;audio_held=audio_expected;warm=warm+1;
 @(negedge clk);
end endtask
task reset_pipeline;
begin
 rst=1;sample_valid=0;de=0;vs=0;#1;
 verify(!de_out && !vs_out && !sample_out_valid,"asynchronous reset suppresses output validity");
 repeat(3)@(negedge clk);
 warm=0;audio_valid_held=0;rst=0;
end endtask
task next_random;
begin rng=rng*1664525+1013904223;end endtask
task render_crop(input integer st,input integer lg);
begin
 level=st;volume_level=st;english=lg;visible=1;de=1;selected=0;rgb=24'hc4318f;
 $sformat(filename,"pipeline_ui_%0d_%0d.ppm",st,lg);fd=$fopen(filename,"wb");
 if(!fd)$fatal(1,"preview output failure");$fwrite(fd,"P6\n164 344\n255\n");
 for(py=240;py<584;py=py+1)for(px=1128;px<1292;px=px+1)begin
  x=px;y=py;repeat(2)begin @(posedge clk);#1;end
  $fwrite(fd,"%c%c%c",pixel_out[23:16],pixel_out[15:8],pixel_out[7:0]);@(negedge clk);
 end
 $fclose(fd);
end endtask

initial begin
 repeat(2)@(negedge clk);reset_pipeline();
 // Rapid per-cycle changes catch stale coefficient, selection and fade stages.
 for(i=0;i<12000;i=i+1)begin
  next_random();rgb=rng[23:0];audio_in=$signed(rng[23:0]);
  next_random();x=rng%1280;next_random();y=rng%720;
  next_random();level=rng%11;next_random();volume_level=rng%11;
  next_random();audio_step=rng%11;next_random();gain=rng%33;
  de=rng[1];vs=rng[2];visible=rng[3];english=rng[4];selected=rng[5];
  sample_valid=i<4000 ? 1'b1 : i<8000 ? i%17==0 : rng[6];
  if(i%31==0)audio_in=24'sh800000;
  if(i%31==1)audio_in=24'sh7fffff;
  if(i%31==2)audio_in=0;
  tick();if(i==3999 || i==8001)reset_pipeline();
 end
 sample_valid=0;de=1;visible=1;vs=0;gain=32;rgb=24'hc4318f;
 // Exhaustive popup region at all eleven levels, both languages and selections.
 for(lang=0;lang<2;lang=lang+1)for(s=0;s<=10;s=s+1)begin
  english=lang;level=s;volume_level=10-s;selected=s[0];
  for(j=240;j<584;j=j+1)for(k=1140;k<1264;k=k+1)begin
   x=k;y=j;rgb={k[7:0],j[7:0],(k[7:0]^j[7:0])};
   gain=(k+j)%33;de=k%19!=0;vs=j%71==0;
   tick();
  end
 end
 de=0;visible=0;repeat(3)tick();
 render_crop(0,0);render_crop(1,0);render_crop(9,0);render_crop(10,0);
 render_crop(0,1);render_crop(1,1);render_crop(9,1);render_crop(10,1);
 $display("PASS SETTINGS_PIPELINE checks=%0d pixels=%0d audio_samples=%0d cycles=%0d",checks,pixels,audio_samples,cycles);
 $finish;
end
endmodule
