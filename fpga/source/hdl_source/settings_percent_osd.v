`timescale 1ns/1ps
// Steps represent percentages 0,10,...100. Settings persist when SW4 closes.
module settings_percent_control(input wire clk,rst,visible,
    input wire [3:0] key_pulse,
    output reg [3:0] brightness_step,volume_step,
    output reg selected);
always @(posedge clk or posedge rst) begin
 if(rst)begin brightness_step<=10;volume_step<=10;selected<=0;end
 else begin
  if(!visible) selected<=0;
  else if(key_pulse[2] || key_pulse[3]) selected<=~selected;
  if(visible && key_pulse[0])begin
   if(!selected && brightness_step<10)brightness_step<=brightness_step+1'b1;
   else if(selected && volume_step<10)volume_step<=volume_step+1'b1;
  end else if(visible && key_pulse[1])begin
   if(!selected && brightness_step>0)brightness_step<=brightness_step-1'b1;
   else if(selected && volume_step>0)volume_step<=volume_step-1'b1;
  end
 end
end
endmodule

// Positive signed coefficient; keep 100 bit-identical to the accepted audio.
module audio_volume_percent(input wire signed [23:0] sample_in,
    input wire [3:0] step,output wire signed [23:0] sample_out);
function [8:0] gain_q8;
input [3:0] step;
begin case (step)
  0: gain_q8=0; 1: gain_q8=26; 2: gain_q8=51; 3: gain_q8=77;
  4: gain_q8=102; 5: gain_q8=128; 6: gain_q8=154;
  7: gain_q8=179; 8: gain_q8=205; 9: gain_q8=230;
  default: gain_q8=256;
endcase end
endfunction

wire signed [9:0] coefficient = $signed({1'b0,gain_q8(step)});
wire signed [33:0] product = sample_in * coefficient;
assign sample_out = step==0 ? 24'sd0 : step>=10 ? sample_in : product[31:8];
endmodule

module settings_percent_renderer_reference(input wire de,visible,
 input wire [10:0] pixel_x,input wire [9:0] pixel_y,
 input wire [3:0] level,volume_level,input wire english,selected,
 input wire [23:0] rgb_in,output reg [23:0] rgb_out);
function [8:0] gain_q8;
input [3:0] step;
begin case (step)
  0: gain_q8=0; 1: gain_q8=26; 2: gain_q8=51; 3: gain_q8=77;
  4: gain_q8=102; 5: gain_q8=128; 6: gain_q8=154;
  7: gain_q8=179; 8: gain_q8=205; 9: gain_q8=230;
  default: gain_q8=256;
endcase end
endfunction

wire [8:0] brightness_gain=gain_q8(level);
wire [16:0] red_product=rgb_in[23:16]*brightness_gain;
wire [16:0] green_product=rgb_in[15:8]*brightness_gain;
wire [16:0] blue_product=rgb_in[7:0]*brightness_gain;
wire [23:0] dimmed_rgb=level>=10 ? rgb_in :
    {red_product[15:8],green_product[15:8],blue_product[15:8]};
function [15:0] label_row;
    input [5:0] address;
    begin
        case (address)
            6'd0: label_row = 16'h0100;
            6'd1: label_row = 16'h0180;
            6'd2: label_row = 16'h7FFE;
            6'd3: label_row = 16'h0000;
            6'd4: label_row = 16'h1FF8;
            6'd5: label_row = 16'h1008;
            6'd6: label_row = 16'h1FF8;
            6'd7: label_row = 16'h0000;
            6'd8: label_row = 16'h7FFE;
            6'd9: label_row = 16'h4002;
            6'd10: label_row = 16'h0FE0;
            6'd11: label_row = 16'h0C23;
            6'd12: label_row = 16'h0C23;
            6'd13: label_row = 16'h3823;
            6'd14: label_row = 16'h603E;
            6'd15: label_row = 16'h0000;
            6'd16: label_row = 16'h0000;
            6'd17: label_row = 16'h0080;
            6'd18: label_row = 16'h00C0;
            6'd19: label_row = 16'h3FFF;
            6'd20: label_row = 16'h2000;
            6'd21: label_row = 16'h2218;
            6'd22: label_row = 16'h3FFF;
            6'd23: label_row = 16'h2218;
            6'd24: label_row = 16'h23F8;
            6'd25: label_row = 16'h2000;
            6'd26: label_row = 16'h2FFC;
            6'd27: label_row = 16'h6218;
            6'd28: label_row = 16'h61F0;
            6'd29: label_row = 16'hC7F8;
            6'd30: label_row = 16'h9C0E;
            6'd31: label_row = 16'h0000;
            6'd32: label_row = 16'h6000;
            6'd33: label_row = 16'h27FE;
            6'd34: label_row = 16'h3602;
            6'd35: label_row = 16'h1662;
            6'd36: label_row = 16'h07FA;
            6'd37: label_row = 16'hE662;
            6'd38: label_row = 16'h27FE;
            6'd39: label_row = 16'h2602;
            6'd40: label_row = 16'h26FA;
            6'd41: label_row = 16'h2C9A;
            6'd42: label_row = 16'h3CFA;
            6'd43: label_row = 16'h2C82;
            6'd44: label_row = 16'h0802;
            6'd45: label_row = 16'h181E;
            6'd46: label_row = 16'h0000;
            6'd47: label_row = 16'h0000;
            6'd48: label_row = 16'h0420;
            6'd49: label_row = 16'h0420;
            6'd50: label_row = 16'hFFFF;
            6'd51: label_row = 16'h0C30;
            6'd52: label_row = 16'h0420;
            6'd53: label_row = 16'h0000;
            6'd54: label_row = 16'h7FFC;
            6'd55: label_row = 16'h060C;
            6'd56: label_row = 16'h060C;
            6'd57: label_row = 16'h060C;
            6'd58: label_row = 16'h060C;
            6'd59: label_row = 16'h060C;
            6'd60: label_row = 16'h06F8;
            6'd61: label_row = 16'h0600;
            6'd62: label_row = 16'h0600;
            6'd63: label_row = 16'h0000;
            default: label_row = 16'h0000;
        endcase
    end
endfunction
function [15:0] audio_label_row;
    input [4:0] address;
    begin
        case (address)
            5'd0: audio_label_row = 16'h0000;
            5'd1: audio_label_row = 16'h0000;
            5'd2: audio_label_row = 16'h0180;
            5'd3: audio_label_row = 16'h7FFC;
            5'd4: audio_label_row = 16'h0810;
            5'd5: audio_label_row = 16'h0420;
            5'd6: audio_label_row = 16'hFFFE;
            5'd7: audio_label_row = 16'h0000;
            5'd8: audio_label_row = 16'h3FF8;
            5'd9: audio_label_row = 16'h2008;
            5'd10: audio_label_row = 16'h2008;
            5'd11: audio_label_row = 16'h3FF8;
            5'd12: audio_label_row = 16'h2008;
            5'd13: audio_label_row = 16'h2008;
            5'd14: audio_label_row = 16'h3FF8;
            5'd15: audio_label_row = 16'h2008;
            5'd16: audio_label_row = 16'h0000;
            5'd17: audio_label_row = 16'h0000;
            5'd18: audio_label_row = 16'h0000;
            5'd19: audio_label_row = 16'h1FF8;
            5'd20: audio_label_row = 16'h1008;
            5'd21: audio_label_row = 16'h1FF8;
            5'd22: audio_label_row = 16'h1008;
            5'd23: audio_label_row = 16'h1FF8;
            5'd24: audio_label_row = 16'h0000;
            5'd25: audio_label_row = 16'h7FFE;
            5'd26: audio_label_row = 16'h1088;
            5'd27: audio_label_row = 16'h1FF8;
            5'd28: audio_label_row = 16'h1088;
            5'd29: audio_label_row = 16'h3FFC;
            5'd30: audio_label_row = 16'h0080;
            5'd31: audio_label_row = 16'h7FFE;
            default: audio_label_row = 16'h0000;
        endcase
    end
endfunction
function [15:0] english_label_row;
input [5:0] address;
begin case(address)
6'd0: english_label_row=16'h0000;
6'd1: english_label_row=16'h0000;
6'd2: english_label_row=16'h4080;
6'd3: english_label_row=16'h4000;
6'd4: english_label_row=16'h408d;
6'd5: english_label_row=16'h4093;
6'd6: english_label_row=16'h4091;
6'd7: english_label_row=16'h4091;
6'd8: english_label_row=16'h4091;
6'd9: english_label_row=16'h4093;
6'd10: english_label_row=16'h7e8d;
6'd11: english_label_row=16'h0001;
6'd12: english_label_row=16'h001e;
6'd13: english_label_row=16'h0000;
6'd14: english_label_row=16'h0000;
6'd15: english_label_row=16'h0000;
6'd16: english_label_row=16'h0000;
6'd17: english_label_row=16'h0040;
6'd18: english_label_row=16'h2040;
6'd19: english_label_row=16'h20e0;
6'd20: english_label_row=16'h2c40;
6'd21: english_label_row=16'h3240;
6'd22: english_label_row=16'h2240;
6'd23: english_label_row=16'h2240;
6'd24: english_label_row=16'h2240;
6'd25: english_label_row=16'h2260;
6'd26: english_label_row=16'h2200;
6'd27: english_label_row=16'h0000;
6'd28: english_label_row=16'h0000;
6'd29: english_label_row=16'h0000;
6'd30: english_label_row=16'h0000;
6'd31: english_label_row=16'h0000;
6'd32: english_label_row=16'h0000;
6'd33: english_label_row=16'h0000;
6'd34: english_label_row=16'h4100;
6'd35: english_label_row=16'h4100;
6'd36: english_label_row=16'h2238;
6'd37: english_label_row=16'h2244;
6'd38: english_label_row=16'h2244;
6'd39: english_label_row=16'h1444;
6'd40: english_label_row=16'h1444;
6'd41: english_label_row=16'h0844;
6'd42: english_label_row=16'h0838;
6'd43: english_label_row=16'h0000;
6'd44: english_label_row=16'h0000;
6'd45: english_label_row=16'h0000;
6'd46: english_label_row=16'h0000;
6'd47: english_label_row=16'h0000;
6'd48: english_label_row=16'h0000;
6'd49: english_label_row=16'h0000;
6'd50: english_label_row=16'h8000;
6'd51: english_label_row=16'h8000;
6'd52: english_label_row=16'h8000;
6'd53: english_label_row=16'h8000;
6'd54: english_label_row=16'h8000;
6'd55: english_label_row=16'h8000;
6'd56: english_label_row=16'h8000;
6'd57: english_label_row=16'h8000;
6'd58: english_label_row=16'h8000;
6'd59: english_label_row=16'h0000;
6'd60: english_label_row=16'h0000;
6'd61: english_label_row=16'h0000;
6'd62: english_label_row=16'h0000;
6'd63: english_label_row=16'h0000;
default:english_label_row=0; endcase end endfunction
wire [10:0] x=pixel_x;
wire [9:0] y=pixel_y;
// Same column centres as the accepted popup, but bars shrink 40 ->24 pixels.
wire bar_left=x>=1160 && x<1184;
wire bar_right=x>=1220 && x<1244;
wire bar_area=(bar_left || bar_right) && y>=256 && y<500;
wire [4:0] bar_x=bar_left ? x-1160 : x-1220;
wire [4:0] edge_x=bar_x<12 ? bar_x : 23-bar_x;
wire [7:0] edge_y=y<378 ? y-256 : 499-y;
wire [3:0] bar_step=bar_left ? level : volume_level;
function [7:0] corner_limits;
 input [3:0] row;
 begin case(row)
  0:corner_limits=8'h9b;1:corner_limits=8'h68;
  2:corner_limits=8'h57;3:corner_limits=8'h46;
  4:corner_limits=8'h35;5:corner_limits=8'h24;
  6:corner_limits=8'h13;7:corner_limits=8'h13;
  8:corner_limits=8'h02;default:corner_limits=8'h02;
 endcase end
endfunction
wire [7:0] limits=edge_y<12 ? corner_limits(edge_y[3:0]) : 8'h02;
wire inside_rounded=edge_x>=limits[7:4];
wire inside_fill=edge_y>=2 && edge_x>=limits[3:0];
// 240 inner pixels give exactly 24 pixels per ten-percent increment.
wire [8:0] fill_height={bar_step,4'b0000}+{bar_step,3'b000};
wire [9:0] fill_top=10'd498-fill_height;
wire filled=bar_step!=0 && y>=fill_top;
wire label_left=x>=1156 && x<1188;
wire label_right=x>=1216 && x<1248;
wire [4:0] label_x=label_left ? x-1156 : x-1216;
wire [4:0] glyph_address={label_x[4],y[3:0]};
wire [15:0] glyph_row=english ? english_label_row({!label_left,glyph_address}) :
    label_left ? label_row({1'b0,glyph_address}) : audio_label_row(glyph_address);
wire glyph_pixel=(label_left || label_right) && y>=528 && y<544 && glyph_row[15-label_x[3:0]];

// Small 5x7 digits at 2x scale. Numeric value is centred below each label.
function [4:0] digit_row;
 input [3:0] digit;input [2:0] row;
 reg [34:0] bitmap;
 begin
 case(digit)
  0:bitmap=35'b01110_10001_10011_10101_11001_10001_01110;
  1:bitmap=35'b00100_01100_00100_00100_00100_00100_01110;
  2:bitmap=35'b01110_10001_00001_00010_00100_01000_11111;
  3:bitmap=35'b11110_00001_00001_01110_00001_00001_11110;
  4:bitmap=35'b00010_00110_01010_10010_11111_00010_00010;
  5:bitmap=35'b11111_10000_10000_11110_00001_00001_11110;
  6:bitmap=35'b01110_10000_10000_11110_10001_10001_01110;
  7:bitmap=35'b11111_00001_00010_00100_01000_01000_01000;
  8:bitmap=35'b01110_10001_10001_01110_10001_10001_01110;
  default:bitmap=35'b01110_10001_10001_01111_00001_00001_01110;
 endcase
 case(row)
  0:digit_row=bitmap[34:30];1:digit_row=bitmap[29:25];
  2:digit_row=bitmap[24:20];3:digit_row=bitmap[19:15];
  4:digit_row=bitmap[14:10];5:digit_row=bitmap[9:5];
  6:digit_row=bitmap[4:0];default:digit_row=0;
 endcase
 end
endfunction
wire numeric_left=x>=1150 && x<1194;
wire numeric_right=x>=1210 && x<1254;
wire [3:0] number_step=numeric_left ? level : volume_level;
wire [10:0] number_center=numeric_left ? 1172 : 1232;
wire [10:0] number_origin=number_center-(number_step>=10 ? 17 : number_step==0 ? 5 : 11);
wire [5:0] number_x=x-number_origin;
reg [3:0] number_digit;
reg [5:0] digit_x;
always @* begin
 number_digit=0;digit_x=number_x;
 if(number_step>=10)begin
  if(number_x<12)number_digit=1;
  else if(number_x<24)digit_x=number_x-12;
  else digit_x=number_x-24;
 end else if(number_step!=0)begin
  if(number_x<12)number_digit=number_step;
  else digit_x=number_x-12;
 end
end
wire [9:0] number_y=y-552;
wire [4:0] number_row=digit_row(number_digit,number_y[3:1]);
wire number_pixel=(numeric_left || numeric_right) && x>=number_origin &&
 number_x<(number_step>=10 ? 34 : number_step==0 ? 10 : 22) &&
 y>=552 && y<566 && digit_x<10 && number_row[4-digit_x[3:1]];
wire [10:0] frame_origin=selected ? 1210 : 1150;
wire [5:0] frame_x=x-frame_origin;
wire [5:0] frame_edge_x=frame_x<22 ? frame_x : 43-frame_x;
wire [2:0] frame_edge_y=y<252 ? y-248 : y>=568 ? 571-y : 4;
wire outer_rounded=frame_edge_y>=4 || frame_edge_x>=(4-frame_edge_y);
wire frame_inner=frame_x>=2 && frame_x<42 && y>=250 && y<570;
wire selected_frame=x>=frame_origin && x<frame_origin+44 && y>=248 && y<572 &&
 outer_rounded && !frame_inner;
always @* begin
 rgb_out=dimmed_rgb;
 if(visible && de)begin
  if(bar_area && inside_rounded)rgb_out=!inside_fill ? 24'hFFF2D0 :
       filled ? 24'hFFD34E : 24'h6D3540;
  if(glyph_pixel || number_pixel)rgb_out=24'hFFF2D0;
  if(selected_frame)rgb_out=24'hFFE277;
 end
end
endmodule


// Runtime audio gain is sampled with the corresponding PCM sample.
// Stage 1 registers limited PCM/coefficient; stage 2 registers the product.
module audio_volume_percent_pipeline(input wire clk,rst,sample_valid,
 input wire signed [23:0] sample_in,input wire [3:0] step,
 output reg sample_out_valid,output reg signed [23:0] sample_out);
function [8:0] gain_q8;
 input [3:0] s;
 begin case(s)
  0:gain_q8=0;1:gain_q8=26;2:gain_q8=51;3:gain_q8=77;
  4:gain_q8=102;5:gain_q8=128;6:gain_q8=154;7:gain_q8=179;
  8:gain_q8=205;9:gain_q8=230;default:gain_q8=256;
 endcase end
endfunction
(* syn_preserve=1 *) reg signed [23:0] pcm_r;
(* syn_preserve=1 *) reg signed [9:0] coefficient_r;
reg valid_r;
wire signed [33:0] product=pcm_r*coefficient_r;
always @(posedge clk)begin
 if(sample_valid)begin pcm_r<=sample_in;coefficient_r<=$signed({1'b0,gain_q8(step)});end
 if(valid_r)sample_out<=product[31:8];
end
always @(posedge clk or posedge rst)begin
 if(rst)begin valid_r<=0;sample_out_valid<=0;end
 else begin valid_r<=sample_valid;sample_out_valid<=valid_r;end
end
endmodule

// Two matched pixel stages. No slow font/address chain is cascaded with gain.
module brightness_popup_720p(input wire clk,rst,de,vs,visible,
 input wire [10:0] pixel_x,input wire [9:0] pixel_y,
 input wire [3:0] level,volume_level,input wire english,selected,
 input wire [5:0] fade_gain_in,
 input wire [23:0] rgb_in,output wire [23:0] rgb_out,
 output reg de_out,vs_out,output reg [5:0] fade_gain_out);
function [8:0] gain_q8;
input [3:0] step;
begin case (step)
  0: gain_q8=0; 1: gain_q8=26; 2: gain_q8=51; 3: gain_q8=77;
  4: gain_q8=102; 5: gain_q8=128; 6: gain_q8=154;
  7: gain_q8=179; 8: gain_q8=205; 9: gain_q8=230;
  default: gain_q8=256;
endcase end
endfunction
function [15:0] label_row;
    input [5:0] address;
    begin
        case (address)
            6'd0: label_row = 16'h0100;
            6'd1: label_row = 16'h0180;
            6'd2: label_row = 16'h7FFE;
            6'd3: label_row = 16'h0000;
            6'd4: label_row = 16'h1FF8;
            6'd5: label_row = 16'h1008;
            6'd6: label_row = 16'h1FF8;
            6'd7: label_row = 16'h0000;
            6'd8: label_row = 16'h7FFE;
            6'd9: label_row = 16'h4002;
            6'd10: label_row = 16'h0FE0;
            6'd11: label_row = 16'h0C23;
            6'd12: label_row = 16'h0C23;
            6'd13: label_row = 16'h3823;
            6'd14: label_row = 16'h603E;
            6'd15: label_row = 16'h0000;
            6'd16: label_row = 16'h0000;
            6'd17: label_row = 16'h0080;
            6'd18: label_row = 16'h00C0;
            6'd19: label_row = 16'h3FFF;
            6'd20: label_row = 16'h2000;
            6'd21: label_row = 16'h2218;
            6'd22: label_row = 16'h3FFF;
            6'd23: label_row = 16'h2218;
            6'd24: label_row = 16'h23F8;
            6'd25: label_row = 16'h2000;
            6'd26: label_row = 16'h2FFC;
            6'd27: label_row = 16'h6218;
            6'd28: label_row = 16'h61F0;
            6'd29: label_row = 16'hC7F8;
            6'd30: label_row = 16'h9C0E;
            6'd31: label_row = 16'h0000;
            6'd32: label_row = 16'h6000;
            6'd33: label_row = 16'h27FE;
            6'd34: label_row = 16'h3602;
            6'd35: label_row = 16'h1662;
            6'd36: label_row = 16'h07FA;
            6'd37: label_row = 16'hE662;
            6'd38: label_row = 16'h27FE;
            6'd39: label_row = 16'h2602;
            6'd40: label_row = 16'h26FA;
            6'd41: label_row = 16'h2C9A;
            6'd42: label_row = 16'h3CFA;
            6'd43: label_row = 16'h2C82;
            6'd44: label_row = 16'h0802;
            6'd45: label_row = 16'h181E;
            6'd46: label_row = 16'h0000;
            6'd47: label_row = 16'h0000;
            6'd48: label_row = 16'h0420;
            6'd49: label_row = 16'h0420;
            6'd50: label_row = 16'hFFFF;
            6'd51: label_row = 16'h0C30;
            6'd52: label_row = 16'h0420;
            6'd53: label_row = 16'h0000;
            6'd54: label_row = 16'h7FFC;
            6'd55: label_row = 16'h060C;
            6'd56: label_row = 16'h060C;
            6'd57: label_row = 16'h060C;
            6'd58: label_row = 16'h060C;
            6'd59: label_row = 16'h060C;
            6'd60: label_row = 16'h06F8;
            6'd61: label_row = 16'h0600;
            6'd62: label_row = 16'h0600;
            6'd63: label_row = 16'h0000;
            default: label_row = 16'h0000;
        endcase
    end
endfunction
function [15:0] audio_label_row;
    input [4:0] address;
    begin
        case (address)
            5'd0: audio_label_row = 16'h0000;
            5'd1: audio_label_row = 16'h0000;
            5'd2: audio_label_row = 16'h0180;
            5'd3: audio_label_row = 16'h7FFC;
            5'd4: audio_label_row = 16'h0810;
            5'd5: audio_label_row = 16'h0420;
            5'd6: audio_label_row = 16'hFFFE;
            5'd7: audio_label_row = 16'h0000;
            5'd8: audio_label_row = 16'h3FF8;
            5'd9: audio_label_row = 16'h2008;
            5'd10: audio_label_row = 16'h2008;
            5'd11: audio_label_row = 16'h3FF8;
            5'd12: audio_label_row = 16'h2008;
            5'd13: audio_label_row = 16'h2008;
            5'd14: audio_label_row = 16'h3FF8;
            5'd15: audio_label_row = 16'h2008;
            5'd16: audio_label_row = 16'h0000;
            5'd17: audio_label_row = 16'h0000;
            5'd18: audio_label_row = 16'h0000;
            5'd19: audio_label_row = 16'h1FF8;
            5'd20: audio_label_row = 16'h1008;
            5'd21: audio_label_row = 16'h1FF8;
            5'd22: audio_label_row = 16'h1008;
            5'd23: audio_label_row = 16'h1FF8;
            5'd24: audio_label_row = 16'h0000;
            5'd25: audio_label_row = 16'h7FFE;
            5'd26: audio_label_row = 16'h1088;
            5'd27: audio_label_row = 16'h1FF8;
            5'd28: audio_label_row = 16'h1088;
            5'd29: audio_label_row = 16'h3FFC;
            5'd30: audio_label_row = 16'h0080;
            5'd31: audio_label_row = 16'h7FFE;
            default: audio_label_row = 16'h0000;
        endcase
    end
endfunction
function [15:0] english_label_row;
input [5:0] address;
begin case(address)
6'd0: english_label_row=16'h0000;
6'd1: english_label_row=16'h0000;
6'd2: english_label_row=16'h4080;
6'd3: english_label_row=16'h4000;
6'd4: english_label_row=16'h408d;
6'd5: english_label_row=16'h4093;
6'd6: english_label_row=16'h4091;
6'd7: english_label_row=16'h4091;
6'd8: english_label_row=16'h4091;
6'd9: english_label_row=16'h4093;
6'd10: english_label_row=16'h7e8d;
6'd11: english_label_row=16'h0001;
6'd12: english_label_row=16'h001e;
6'd13: english_label_row=16'h0000;
6'd14: english_label_row=16'h0000;
6'd15: english_label_row=16'h0000;
6'd16: english_label_row=16'h0000;
6'd17: english_label_row=16'h0040;
6'd18: english_label_row=16'h2040;
6'd19: english_label_row=16'h20e0;
6'd20: english_label_row=16'h2c40;
6'd21: english_label_row=16'h3240;
6'd22: english_label_row=16'h2240;
6'd23: english_label_row=16'h2240;
6'd24: english_label_row=16'h2240;
6'd25: english_label_row=16'h2260;
6'd26: english_label_row=16'h2200;
6'd27: english_label_row=16'h0000;
6'd28: english_label_row=16'h0000;
6'd29: english_label_row=16'h0000;
6'd30: english_label_row=16'h0000;
6'd31: english_label_row=16'h0000;
6'd32: english_label_row=16'h0000;
6'd33: english_label_row=16'h0000;
6'd34: english_label_row=16'h4100;
6'd35: english_label_row=16'h4100;
6'd36: english_label_row=16'h2238;
6'd37: english_label_row=16'h2244;
6'd38: english_label_row=16'h2244;
6'd39: english_label_row=16'h1444;
6'd40: english_label_row=16'h1444;
6'd41: english_label_row=16'h0844;
6'd42: english_label_row=16'h0838;
6'd43: english_label_row=16'h0000;
6'd44: english_label_row=16'h0000;
6'd45: english_label_row=16'h0000;
6'd46: english_label_row=16'h0000;
6'd47: english_label_row=16'h0000;
6'd48: english_label_row=16'h0000;
6'd49: english_label_row=16'h0000;
6'd50: english_label_row=16'h8000;
6'd51: english_label_row=16'h8000;
6'd52: english_label_row=16'h8000;
6'd53: english_label_row=16'h8000;
6'd54: english_label_row=16'h8000;
6'd55: english_label_row=16'h8000;
6'd56: english_label_row=16'h8000;
6'd57: english_label_row=16'h8000;
6'd58: english_label_row=16'h8000;
6'd59: english_label_row=16'h0000;
6'd60: english_label_row=16'h0000;
6'd61: english_label_row=16'h0000;
6'd62: english_label_row=16'h0000;
6'd63: english_label_row=16'h0000;
default:english_label_row=0; endcase end endfunction
function [7:0] corner_limits;
 input [3:0] row;
 begin case(row)
  0:corner_limits=8'h9b;1:corner_limits=8'h68;
  2:corner_limits=8'h57;3:corner_limits=8'h46;
  4:corner_limits=8'h35;5:corner_limits=8'h24;
  6:corner_limits=8'h13;7:corner_limits=8'h13;
  8:corner_limits=8'h02;default:corner_limits=8'h02;
 endcase end
endfunction
function [4:0] digit_row;
 input [3:0] digit;input [2:0] row;
 reg [34:0] bitmap;
 begin
 case(digit)
  0:bitmap=35'b01110_10001_10011_10101_11001_10001_01110;
  1:bitmap=35'b00100_01100_00100_00100_00100_00100_01110;
  2:bitmap=35'b01110_10001_00001_00010_00100_01000_11111;
  3:bitmap=35'b11110_00001_00001_01110_00001_00001_11110;
  4:bitmap=35'b00010_00110_01010_10010_11111_00010_00010;
  5:bitmap=35'b11111_10000_10000_11110_00001_00001_11110;
  6:bitmap=35'b01110_10000_10000_11110_10001_10001_01110;
  7:bitmap=35'b11111_00001_00010_00100_01000_01000_01000;
  8:bitmap=35'b01110_10001_10001_01110_10001_10001_01110;
  default:bitmap=35'b01110_10001_10001_01111_00001_00001_01110;
 endcase
 case(row)
  0:digit_row=bitmap[34:30];1:digit_row=bitmap[29:25];
  2:digit_row=bitmap[24:20];3:digit_row=bitmap[19:15];
  4:digit_row=bitmap[14:10];5:digit_row=bitmap[9:5];
  6:digit_row=bitmap[4:0];default:digit_row=0;
 endcase
 end
endfunction
wire [10:0] x=pixel_x;
wire [9:0] y=pixel_y;
// Same column centres as the accepted popup, but bars shrink 40 ->24 pixels.
wire bar_left=x>=1160 && x<1184;
wire bar_right=x>=1220 && x<1244;
wire bar_area=(bar_left || bar_right) && y>=256 && y<500;
wire [4:0] bar_x=bar_left ? x-1160 : x-1220;
wire [4:0] edge_x=bar_x<12 ? bar_x : 23-bar_x;
wire [7:0] edge_y=y<378 ? y-256 : 499-y;
wire [3:0] bar_step=bar_left ? level : volume_level;
wire [7:0] limits=edge_y<12 ? corner_limits(edge_y[3:0]) : 8'h02;
wire inside_rounded=edge_x>=limits[7:4];
wire inside_fill=edge_y>=2 && edge_x>=limits[3:0];
// 240 inner pixels give exactly 24 pixels per ten-percent increment.
wire [8:0] fill_height={bar_step,4'b0000}+{bar_step,3'b000};
wire [9:0] fill_top=10'd498-fill_height;
wire filled=bar_step!=0 && y>=fill_top;
wire label_left=x>=1156 && x<1188;
wire label_right=x>=1216 && x<1248;
wire [4:0] label_x=label_left ? x-1156 : x-1216;
wire [4:0] glyph_address={label_x[4],y[3:0]};

// Small 5x7 digits at 2x scale. Numeric value is centred below each label.
wire numeric_left=x>=1150 && x<1194;
wire numeric_right=x>=1210 && x<1254;
wire [3:0] number_step=numeric_left ? level : volume_level;
wire [10:0] number_center=numeric_left ? 1172 : 1232;
wire [10:0] number_origin=number_center-(number_step>=10 ? 17 : number_step==0 ? 5 : 11);
wire [5:0] number_x=x-number_origin;
reg [3:0] number_digit;
reg [5:0] digit_x;
always @* begin
 number_digit=0;digit_x=number_x;
 if(number_step>=10)begin
  if(number_x<12)number_digit=1;
  else if(number_x<24)digit_x=number_x-12;
  else digit_x=number_x-24;
 end else if(number_step!=0)begin
  if(number_x<12)number_digit=number_step;
  else digit_x=number_x-12;
 end
end
wire [9:0] number_y=y-552;
wire number_active=(numeric_left || numeric_right) && x>=number_origin &&
 number_x<(number_step>=10 ? 34 : number_step==0 ? 10 : 22) &&
 y>=552 && y<566 && digit_x<10;
wire [10:0] frame_origin=selected ? 1210 : 1150;
wire [5:0] frame_x=x-frame_origin;
wire [5:0] frame_edge_x=frame_x<22 ? frame_x : 43-frame_x;
wire [2:0] frame_edge_y=y<252 ? y-248 : y>=568 ? 571-y : 4;
wire outer_rounded=frame_edge_y>=4 || frame_edge_x>=(4-frame_edge_y);
wire frame_inner=frame_x>=2 && frame_x<42 && y>=250 && y<570;
wire selected_frame=x>=frame_origin && x<frame_origin+44 && y>=248 && y<572 &&
 outer_rounded && !frame_inner;

(* syn_preserve=1 *) reg [23:0] rgb_r;
(* syn_preserve=1 *) reg [8:0] gain_r;
(* syn_preserve=1 *) reg [15:0] red_product_r,green_product_r,blue_product_r;
reg de_r,vs_r,visible_r;
reg [5:0] fade_gain_r;
reg bar_active_r,bar_edge_r,bar_filled_r,frame_r;
reg label_active_r,label_left_r,english_r;
reg [5:0] label_address_r;
reg [3:0] label_column_r;
reg number_active_r;
reg [3:0] number_digit_r;
reg [2:0] number_row_r,number_column_r;
reg overlay_mask_r;
reg [23:0] overlay_color_r;
wire [15:0] text_row=english_r ? english_label_row(label_address_r) :
 label_left_r ? label_row({1'b0,label_address_r[4:0]}) : audio_label_row(label_address_r[4:0]);
wire [4:0] digit_bits=digit_row(number_digit_r,number_row_r);
wire text_ink=label_active_r && text_row[15-label_column_r];
wire number_ink=number_active_r && digit_bits[4-number_column_r];
// All arithmetic data registers use a plain clock, allowing DSP registers.
// The resettable DE/VS pipeline suppresses uninitialized data during startup.
always @(posedge clk)begin
 rgb_r<=rgb_in;gain_r<=gain_q8(level);
 red_product_r<=rgb_r[23:16]*gain_r;
 green_product_r<=rgb_r[15:8]*gain_r;
 blue_product_r<=rgb_r[7:0]*gain_r;
 fade_gain_r<=fade_gain_in;fade_gain_out<=fade_gain_r;
 bar_active_r<=bar_area && inside_rounded;
 bar_edge_r<=!inside_fill;bar_filled_r<=filled;frame_r<=selected_frame;
 label_active_r<=(label_left || label_right) && y>=528 && y<544;
 label_address_r<={!label_left,glyph_address};
 label_left_r<=label_left;english_r<=english;label_column_r<=label_x[3:0];
 number_active_r<=number_active;number_digit_r<=number_digit;
 number_row_r<=number_y[3:1];number_column_r<=digit_x[3:1];
 overlay_color_r<=frame_r ? 24'hFFE277 : (text_ink || number_ink || bar_edge_r) ?
     24'hFFF2D0 : bar_filled_r ? 24'hFFD34E : 24'h6D3540;
end
always @(posedge clk or posedge rst)begin
 if(rst)begin de_r<=0;vs_r<=0;de_out<=0;vs_out<=0;visible_r<=0;overlay_mask_r<=0;end
 else begin
  de_r<=de;vs_r<=vs;de_out<=de_r;vs_out<=vs_r;visible_r<=visible;
  overlay_mask_r<=visible_r && de_r && (frame_r || text_ink || number_ink || bar_active_r);
 end
end
assign rgb_out=overlay_mask_r ? overlay_color_r :
 {red_product_r[15:8],green_product_r[15:8],blue_product_r[15:8]};
endmodule
