`timescale 1ns/1ps
module portrait_focus_video(input wire clk,rst,
    input wire [10:0] x, input wire [9:0] y,
    input wire [5:0] step_mem, input wire scene_mem,
    input wire [23:0] photo_rgb,scene_rgb, output wire [23:0] rgb);
    reg [5:0] step_meta,step;
    reg [1:0] scene;
    always @(posedge clk or posedge rst) begin
        if(rst) begin step_meta<=0;step<=0;scene<=0;end
        else begin step_meta<=step_mem;step<=step_meta;scene<={scene[0],scene_mem};end
    end
    wire [10:0] left,right;
    wire [9:0] top,bottom;
    wire [16:0] unused_step;
    portrait_focus_geometry u_geo(.step(step),.left(left),.right(right),
        .top(top),.bottom(bottom),.source_step(unused_step));
    wire photo_here=scene[1] && x>=left && x<right && y>=top && y<bottom;
    // Same 1/8 gain as SW4 level 0; preserve RGB proportions and hue.
    wire [23:0] dim_color={3'b0,scene_rgb[23:19],3'b0,scene_rgb[15:11],3'b0,scene_rgb[7:3]};
    assign rgb=photo_here ? photo_rgb :
        (scene[1] && step!=0) ? dim_color : scene_rgb;
endmodule
