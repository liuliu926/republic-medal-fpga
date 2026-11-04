`timescale 1ns/1ps
// 640x360 B96 (4x8, four-color) bilinear scanout, no external SDRAM.
// Port requests sample rd_en/rd_addr on an edge; rd_valid/rd_data become valid
// AFTER that edge. This module captures the return on the following edge.
// line_prepare must pulse >=12 clocks before first active pixel; native_x=0
// at first active pixel, with native coordinates=floor(output/2) and phase
// =output mod2. Each new native4-pixel block spans eight output clocks.
// A 3-column x2-row compressed-tile cache is primed during horizontal blanking.
// At a predicted x-block boundary it shifts before the next input pixel, then
// fetches only the two new right-column blocks. Edge neighbors clamp to639/359.
// Cache entries contain fourRGB888 colors and only the eight selector bits
// for the relevant source line. Bottom entries always represent y+1, including
// when both source lines share one compressed block row. No pixel can consume
// the other56 selector bits during this output line, so they are not retained.
// Pixel latency is EXACTLY FIVE video clocks, including lookup and output reg:
// lookup4colors -> horizontalRGB -> verticalRGB -> delayRGB -> outputRGB.
// Fractions use phase*128={0,128}; both mixes round +128.
module opening_bilinear_tile_scanout_640(
 input wire clk,rst,active,line_prepare,frame_valid,
 input wire [9:0] native_x,input wire [8:0] native_y,
 input wire [2:0] phase_x,phase_y,
 output wire rd_en,output wire [5:0] rd_row,output wire [7:0] rd_col,
 input wire [95:0] rd_data,input wire rd_valid,
 output reg [23:0] rgb,output wire pixel_valid,output reg cache_miss
);
 localparam IDLE=2'd0,PRIME=2'd1,PREFETCH=2'd2;
 reg [1:0] fetch_state;
 reg [2:0] issue;
 reg [7:0] cache_x,fetch_column;
 reg [5:0] row_top,row_bottom;
 reg tiles_ready,next_ready;
 reg [103:0] c0t,c0b,c1t,c1b,c2t,c2b;
 wire [2:0] slot=fetch_state==PRIME ? issue : {2'b10,issue[0]};
 wire [7:0] column=fetch_state==PRIME ? {6'd0,issue[2:1]} : fetch_column;
 assign rd_en=frame_valid && fetch_state!=IDLE &&
              ((fetch_state==PRIME && issue<6)||(fetch_state==PREFETCH && issue<2));
 assign rd_row=slot[0] ? row_bottom : row_top;
 assign rd_col=column;
 reg pending_valid,palette_valid;
 reg [2:0] pending_slot,palette_slot,pending_y,local_top,local_bottom;
 reg [23:0] a_q,b_q;
 reg [7:0] selectors_q;
 function [7:0] quarter;
  input [7:0] heavy,light;reg [9:0] sum;
  begin sum={2'b0,heavy}+{1'b0,heavy,1'b0}+{2'b0,light};quarter=sum[9:2];end
 endfunction
 wire [23:0] a_now={rd_data[15:11],rd_data[15:13],rd_data[10:5],rd_data[10:9],rd_data[4:0],rd_data[4:2]};
 wire [23:0] b_now={rd_data[31:27],rd_data[31:29],rd_data[26:21],rd_data[26:25],rd_data[20:16],rd_data[20:18]};
 wire [23:0] color1={quarter(a_q[23:16],b_q[23:16]),quarter(a_q[15:8],b_q[15:8]),quarter(a_q[7:0],b_q[7:0])};
 wire [23:0] color2={quarter(b_q[23:16],a_q[23:16]),quarter(b_q[15:8],a_q[15:8]),quarter(b_q[7:0],a_q[7:0])};
 wire [103:0] palette_word={selectors_q,b_q,color2,color1,a_q};
 wire shift_column=active && frame_valid && tiles_ready &&
                    native_x[1:0]==2'd3 && phase_x==1 && native_x<639;
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   fetch_state<=IDLE;issue<=0;cache_x<=0;fetch_column<=0;
   row_top<=0;row_bottom<=0;tiles_ready<=0;next_ready<=0;
   pending_valid<=0;palette_valid<=0;pending_slot<=0;palette_slot<=0;
   pending_y<=0;local_top<=0;local_bottom<=0;
   a_q<=0;b_q<=0;selectors_q<=0;cache_miss<=0;
   c0t<=0;c0b<=0;c1t<=0;c1b<=0;c2t<=0;c2b<=0;
  end else begin
   pending_valid<=rd_en;
   if(rd_en)begin
    pending_slot<=slot;pending_y<=slot[0]?local_bottom:local_top;issue<=issue+1'b1;
    if((fetch_state==PRIME && issue==5)||(fetch_state==PREFETCH && issue==1))fetch_state<=IDLE;
   end
   palette_valid<=pending_valid && rd_valid;
   if(pending_valid && rd_valid)begin
    a_q<=a_now;b_q<=b_now;
    selectors_q<=rd_data[32+pending_y*8+:8];palette_slot<=pending_slot;
   end
   if(pending_valid && !rd_valid)cache_miss<=1;
   if(palette_valid)begin
    case(palette_slot)
     0:c0t<=palette_word;1:c0b<=palette_word;
     2:c1t<=palette_word;3:c1b<=palette_word;
     4:c2t<=palette_word;
     5:begin c2b<=palette_word;next_ready<=1;tiles_ready<=1;end
    endcase
   end
   if(shift_column)begin
    if(!next_ready || fetch_state!=IDLE)begin tiles_ready<=0;cache_miss<=1;end
    else begin
     c0t<=c1t;c0b<=c1b;c1t<=c2t;c1b<=c2b;
     cache_x<=cache_x+1'b1;next_ready<=0;
     fetch_column<=cache_x>=157 ? 8'd159 : cache_x+8'd3;
     fetch_state<=PREFETCH;issue<=0;
    end
   end
   if(active && frame_valid && (!tiles_ready || native_x[9:2]!=cache_x))cache_miss<=1;
   if(line_prepare)begin
    fetch_state<=frame_valid ? PRIME : IDLE;issue<=0;cache_x<=0;
    row_top<=native_y[8:3];
    row_bottom<=native_y>=359 ? 6'd44 : (({1'b0,native_y}+10'd1)>>3);
    local_top<=native_y[2:0];local_bottom<=native_y>=359?3'd7:native_y[2:0]+3'd1;
    tiles_ready<=0;next_ready<=0;pending_valid<=0;palette_valid<=0;
   end
   if(!frame_valid)begin fetch_state<=IDLE;tiles_ready<=0;next_ready<=0;end
  end
 end
 function [23:0] lookup;
  input [103:0] tile;input [1:0] xx;
  reg [1:0] select;reg [7:0] bits;
  begin
   bits=tile[103:96];select=bits>>(xx*2);
   case(select)0:lookup=tile[23:0];1:lookup=tile[47:24];2:lookup=tile[71:48];default:lookup=tile[95:72];endcase
  end
 endfunction
 wire cross_x=native_x[1:0]==3 && native_x!=639;
 wire [1:0] x1=native_x==639 ? 2'd3 : native_x[1:0]+2'd1;
 wire [23:0] p00=lookup(c0t,native_x[1:0]);
 wire [23:0] p10=lookup(cross_x ? c1t : c0t,x1);
 wire [23:0] p01=lookup(c0b,native_x[1:0]);
 wire [23:0] p11=lookup(cross_x ? c1b : c0b,x1);
 // Native640->1280 uses only phase0 and halfphase1. These rounded
 // averages are bit-exact to the general signed multiply/round pipeline:
 // (256*A + 128*(B-A) + 128) >> 8 == (A+B+1) >> 1.
 // Keep all FIVE stages so the accepted AXIS sideband alignment is unchanged.
 reg [4:0] valid_pipe;
 reg [23:0] p00_s0,p10_s0,p01_s0,p11_s0;
 reg fx_s0,fy_s0;
 reg [23:0] upper_s1,lower_s1;
 reg fy_s1;
 reg [23:0] final_s2,final_s3;
 function [7:0] average;
  input [7:0] a,b;
  reg [8:0] sum;
  begin sum={1'b0,a}+{1'b0,b}+9'd1;average=sum[8:1];end
 endfunction
 function [23:0] average_rgb;
  input [23:0] a,b;
  begin average_rgb={average(a[23:16],b[23:16]),average(a[15:8],b[15:8]),average(a[7:0],b[7:0])};end
 endfunction
 assign pixel_valid=valid_pipe[4];
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   valid_pipe<=0;rgb<=0;
   p00_s0<=0;p10_s0<=0;p01_s0<=0;p11_s0<=0;fx_s0<=0;fy_s0<=0;
   upper_s1<=0;lower_s1<=0;fy_s1<=0;final_s2<=0;final_s3<=0;
  end else begin
   valid_pipe<={valid_pipe[3:0],active && frame_valid && tiles_ready && native_x[9:2]==cache_x};
   p00_s0<=p00;p10_s0<=p10;p01_s0<=p01;p11_s0<=p11;
   fx_s0<=phase_x!=0;fy_s0<=phase_y!=0;
   upper_s1<=fx_s0?average_rgb(p00_s0,p10_s0):p00_s0;
   lower_s1<=fx_s0?average_rgb(p01_s0,p11_s0):p01_s0;fy_s1<=fy_s0;
   final_s2<=fy_s1?average_rgb(upper_s1,lower_s1):upper_s1;
   final_s3<=final_s2;
   if(valid_pipe[3])rgb<=final_s3;
   else rgb<=0;
  end
 end
endmodule
