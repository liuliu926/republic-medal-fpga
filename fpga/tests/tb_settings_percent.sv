`timescale 1ns/1ps
module tb_settings_percent;
reg clk=0;
always #5 clk=~clk;
reg rst=1,c_visible=0;
reg [3:0] keys=0;
wire [3:0] brightness_step,volume_step;
wire selected;
settings_percent_control control(clk,rst,c_visible,keys,brightness_step,volume_step,selected);
reg signed [23:0] audio_in=0;
reg [3:0] audio_step=10;
wire signed [23:0] audio_out;
audio_volume_percent volume(audio_in,audio_step,audio_out);
reg de=1,visible=0,english=0,selected_ui=0;
reg [10:0] x=0;
reg [9:0] y=0;
reg [3:0] level=10,volume_level=10;
reg [23:0] rgb=24'hc4318f;
wire [23:0] out_rgb;
settings_percent_renderer_reference popup(de,visible,x,y,level,volume_level,english,selected_ui,rgb,out_rgb);
integer tests=0,i,j,k,s,t,n,fd,a,b,expected,previous,run_count,last_color;
integer coeff[0:10];
reg [31:0] random_state=32'h61793aec;
reg signed [63:0] reference_product;
reg [23:0] want;
reg [1023:0] name;

task check(input bit condition,input [1023:0] message_text);
begin
 tests=tests+1;
 if(!condition)begin $display("FAIL %0s tests=%0d",message_text,tests);$fatal(1);end
end endtask
task press(input [3:0] pulse);
begin
 @(negedge clk);keys=pulse;
 @(posedge clk);#1;
 @(negedge clk);keys=0;
end endtask
task pixel(input integer px,input integer py);
begin x=px;y=py;#1;end endtask
task check_audio(input integer sample,input integer step);
begin
 audio_in=sample;audio_step=step;#1;
 reference_product=$signed(audio_in)*coeff[step];
 expected=reference_product>>>8;
 check($signed(audio_out)==expected,"signed audio gain / endpoints");
end endtask
task write_crop(input integer step,input integer language);
integer px,py;
begin
 level=step;volume_level=step;english=language;visible=1;de=1;selected_ui=0;
 $sformat(name,"ui_%0d_%0d.ppm",step,language);
 fd=$fopen(name,"wb");
 if(!fd)$fatal(1,"cannot create UI crop");
 $fwrite(fd,"P6\n164 344\n255\n");
 for(py=240;py<584;py=py+1)
  for(px=1128;px<1292;px=px+1)begin
   pixel(px,py);$fwrite(fd,"%c%c%c",out_rgb[23:16],out_rgb[15:8],out_rgb[7:0]);
  end
 $fclose(fd);
end endtask

initial begin
 coeff[0]=0;coeff[1]=26;coeff[2]=51;coeff[3]=77;coeff[4]=102;coeff[5]=128;
 coeff[6]=154;coeff[7]=179;coeff[8]=205;coeff[9]=230;coeff[10]=256;
 #12;check(brightness_step===10 && volume_step===10 && selected===0,"reset default 100");
 @(negedge clk);rst=0;c_visible=1;
 // Every brightness level and saturating boundaries.
 for(i=9;i>=0;i=i-1)begin press(2);check(brightness_step==i && volume_step==10,"brightness down by ten");end
 repeat(3)press(2);check(brightness_step==0,"brightness lower clamp");
 for(i=1;i<=10;i=i+1)begin press(1);check(brightness_step==i,"brightness up by ten");end
 repeat(3)press(1);check(brightness_step==10,"brightness upper clamp");
 repeat(6)begin press(8);check(selected==1,"KEY4 selects volume cyclically");press(8);check(selected==0,"KEY4 wraps to brightness");end
 repeat(6)begin press(4);check(selected==1,"KEY3 selects volume cyclically");press(4);check(selected==0,"KEY3 wraps to brightness");end
 press(8);
 for(i=9;i>=0;i=i-1)begin press(2);check(volume_step==i && brightness_step==10,"volume down by ten");end
 repeat(3)press(2);check(volume_step==0,"volume mute clamp");
 for(i=1;i<=10;i=i+1)begin press(1);check(volume_step==i,"volume up by ten");end
 repeat(3)press(1);check(volume_step==10,"volume upper clamp");
 press(2);press(2);check(volume_step==8,"prepare persistence 80");
 c_visible=0;
 for(i=0;i<4;i=i+1)begin press(1<<i);check(brightness_step==10 && volume_step==8 && selected==0,"closed SW4 retains values and ignores keys");end
 c_visible=1;press(2);check(brightness_step==9 && volume_step==8,"reopen starts on brightness and retains values");
 // Signed full-range audio vectors plus pseudorandom values at every level.
 for(s=0;s<=10;s=s+1)begin
  check_audio(0,s);check_audio(1,s);check_audio(-1,s);check_audio(255,s);check_audio(-255,s);
  check_audio(256,s);check_audio(-256,s);check_audio(8388607,s);check_audio(-8388608,s);
  check_audio(65535,s);check_audio(-65535,s);
  for(i=0;i<128;i=i+1)begin random_state=random_state*1664525+1013904223;check_audio($signed(random_state[23:0]),s);end
 end
 // All channel values, all legal steps. Other channels differ to catch swaps.
 visible=0;
 for(s=0;s<=10;s=s+1)begin
  level=s;
  for(i=0;i<256;i=i+1)begin
   rgb={i[7:0],(8'd255-i[7:0]),(i[7:0]^8'h59)};pixel(400,200);
   a=(i*coeff[s])>>8;b=((255-i)*coeff[s])>>8;n=((i^89)*coeff[s])>>8;
   want={a[7:0],b[7:0],n[7:0]};check(out_rgb===want,"all RGB values scale correctly, full scale is identity");
  end
 end
 // At 0 brightness, active controls remain bright, empty bar has no separator.
 level=0;volume_level=0;visible=1;rgb=24'hc4318f;
 pixel(400,200);check(out_rgb==0,"brightness zero background black");
 pixel(1160,300);check(out_rgb==24'hFFF2D0,"brightness zero keeps bar border visible");
 pixel(1172,300);check(out_rgb==24'h6D3540,"zero bar empty interior");
 // Across each bar's centre, fill is one continuous interval; exactly 24px per step.
 for(s=0;s<=10;s=s+1)begin
  level=s;volume_level=s;
  for(k=0;k<2;k=k+1)begin
   n=0;run_count=0;last_color=0;
   for(j=258;j<498;j=j+1)begin
    pixel(k==0 ? 1172 : 1232,j);
    check(out_rgb==24'hFFD34E || out_rgb==24'h6D3540,"no internal segment lines");
    if(out_rgb==24'hFFD34E)begin n=n+1;if(last_color==0)run_count=run_count+1;last_color=1;end
    else last_color=0;
   end
   check(n==24*s,"fill exact 24 pixels per 10 percent");
   check(run_count==(s==0 ? 0 : 1),"one continuous fill interval");
  end
 end
 // Digit placement and labels stay inside each 44px selection column.
 // Pixel files provide the actual RTL output, then Python checks glyph shapes.
 write_crop(0,0);write_crop(1,0);write_crop(9,0);write_crop(10,0);
 write_crop(0,1);write_crop(1,1);write_crop(9,1);write_crop(10,1);
 $display("PASS SETTINGS_PERCENT assertions=%0d",tests);
 $finish;
end
endmodule
