"""Aligned SDRAM reads + synchronous line-cache resampling, based on BGM rollback.

APUG011 p12: jumps within groups of four are unsupported. Never send scaled
pixel addresses to that controller. Read 256+64 contiguous words into one line
cache, then overlay the scaled row on the returned background pixel stream.
"""
from pathlib import Path
import runpy
root=Path(__file__).resolve().parents[1]
runpy.run_path(str(root/'tools/prepare_portrait_focus.py'))
src=root/'fpga/user_source_720p/hdl_source'
base=root/'releases/bgm_accepted_20261031/source_snapshot/fpga/user_source_720p/hdl_source'
run=root/'fpga/td_project_720p/cli_runs/portrait_focus_linecache_20261031'
run.mkdir(parents=True,exist_ok=True)
def rep(s,a,b):
    assert s.count(a)==1,(s.count(a),a[:100])
    return s.replace(a,b)

r=(base/'SD/frame_fifo_read_fat32_menu_timing.v').read_text(encoding='utf-8')
r=rep(r,'    input wire intro_mode,','''    input wire intro_mode,
    input wire focus_scene, focus_target,
    output reg [5:0] focus_step,
    output reg focus_scene_latched,
    input wire [31:0] Sdr_rd_dout,
    output wire pixel_valid,
    output wire [31:0] pixel_data,''')
r=rep(r,'PLAN_CAPTURE=8;','PLAN_CAPTURE=8, CACHE_START=9, CACHE_WAIT=10, CACHE_READ=11, CACHE_END=12;')
r=rep(r,'    // Registered row decodes', '''    // Geometry commits only at the start of a video-frame request.
    reg [1:0] focus_scene_sync, focus_target_sync;
    wire [10:0] focus_left, focus_right;
    wire [9:0] focus_top, focus_bottom;
    wire [16:0] focus_increment;
    reg [24:0] source_y_phase;
    wire focus_row = focus_scene_latched && screen_y>=focus_top && screen_y<focus_bottom;
    wire [8:0] source_y = source_y_phase[24:16];
    portrait_focus_geometry u_geometry(.step(focus_step),.left(focus_left),
        .right(focus_right),.top(focus_top),.bottom(focus_bottom),.source_step(focus_increment));
    always @(posedge mem_clk or posedge rst) begin
        if (rst) begin
            focus_scene_sync<=0; focus_target_sync<=0;
            focus_step<=0; focus_scene_latched<=0; source_y_phase<=0;
        end else begin
            focus_scene_sync<={focus_scene_sync[0],focus_scene};
            focus_target_sync<={focus_target_sync[0],focus_target};
            if(state==ACK && !req2) begin
                focus_scene_latched<=focus_scene_sync[1];
                if(!focus_scene_sync[1]) focus_step<=0;
                else if(focus_target_sync[1] && focus_step<32) focus_step<=focus_step+1'b1;
                else if(!focus_target_sync[1] && focus_step!=0) focus_step<=focus_step-1'b1;
            end
            if(state==ACK) source_y_phase<=0;
            else if(read_enable_d && screen_x==1279 && focus_row)
                source_y_phase<=source_y_phase+focus_increment;
        end
    end

    // Two aligned bursts (256 + 64) fetch a 320-pixel source row.
    // Cache reuse also avoids rereading rows duplicated by vertical scaling.
    reg cache_valid;
    reg [8:0] cache_tag, cache_sent, cache_received, cache_goal;
    reg [20:0] cache_address;
    wire cache_mode = state==CACHE_START || state==CACHE_WAIT || state==CACHE_READ || state==CACHE_END;
    wire cache_request = state==CACHE_READ && cache_sent<cache_goal;
    wire cache_return = cache_mode && Sdr_rd_en;
    wire cache_complete = cache_sent==cache_goal && cache_received==cache_goal && drain_count==10;
    wire need_cache = focus_row && screen_x==0 && (!cache_valid || cache_tag!=source_y);
    always @(posedge mem_clk or posedge rst) begin
        if(rst) begin
            cache_valid<=0;cache_tag<=0;cache_sent<=0;cache_received<=0;
            cache_goal<=256;cache_address<=1843200;
        end else begin
            if(state==ACK) cache_valid<=0;
            if(state==CACHE_START) begin
                cache_sent<=0; cache_received<=0; cache_goal<=256;
                cache_address<=21'd1843200+{3'd0,source_y,9'd0};
            end else begin
                if(cache_request) begin cache_sent<=cache_sent+1'b1;cache_address<=cache_address+1'b1;end
                if(cache_return) cache_received<=cache_received+1'b1;
            end
            if(state==CACHE_END) begin
                if(cache_goal==256) cache_goal<=320;
                else begin cache_valid<=1;cache_tag<=source_y;end
            end
        end
    end

    // True synchronous memory: no asynchronous combinational RAM read.
    reg [31:0] portrait_line [0:511];
    reg [31:0] line_pixel, background_pixel;
    reg composed_valid, composed_photo;
    reg [10:0] return_x;
    reg [9:0] return_y;
    reg [24:0] return_phase;
    wire background_return = Sdr_rd_en && !cache_mode;
    wire photo_return = focus_scene_latched && return_y>=focus_top && return_y<focus_bottom &&
                        return_x>=focus_left && return_x<focus_right;
    always @(posedge mem_clk) begin
        if(cache_return) portrait_line[cache_received]<=Sdr_rd_dout;
        line_pixel<=portrait_line[return_phase[24:16]];
    end
    always @(posedge mem_clk or posedge rst) begin
        if(rst) begin
            composed_valid<=0;composed_photo<=0;background_pixel<=0;
            return_x<=0;return_y<=0;return_phase<=0;
        end else if(state==ACK) begin
            composed_valid<=0;composed_photo<=0;
            return_x<=0;return_y<=0;return_phase<=0;
        end else begin
            composed_valid<=background_return;
            if(background_return) begin
                background_pixel<=Sdr_rd_dout;composed_photo<=photo_return;
                if(return_x==1279) begin return_x<=0;return_y<=return_y+1'b1;return_phase<=0;end
                else begin
                    return_x<=return_x+1'b1;
                    if(photo_return) return_phase<=return_phase+focus_increment;
                end
            end
        end
    end
    // Home and article paths preserve the accepted direct-return timing.
    assign pixel_valid = focus_scene_latched ? composed_valid : background_return;
    assign pixel_data = focus_scene_latched ? (composed_photo ? line_pixel : background_pixel) : Sdr_rd_dout;

    // Registered row decodes''')
r=rep(r,'wire portrait_row = !intro_mode &&','wire portrait_row = !intro_mode && !focus_scene_latched &&')
r=rep(r,'assign App_rd_en = read_enable_d;','assign App_rd_en = read_enable_d || cache_request;')
r=rep(r,'assign App_rd_addr = read_address;','assign App_rd_addr = cache_mode ? cache_address : read_address;')
r=rep(r,'assign O_rd_busy = (state == READ_BURST);','assign O_rd_busy = (state == READ_BURST) || (state == CACHE_READ) || (state == CACHE_END);')
r=rep(r,'else if (App_rd_en) burst_count','else if (read_enable_d) burst_count')
r=rep(r,'((burst_count + App_rd_en) < burst_target)','((burst_count + read_enable_d) < burst_target)')
r=rep(r,'end else if (App_rd_en) begin','end else if (read_enable_d) begin')
r=rep(r,'                state <= PLAN_SEG;','                state <= need_cache ? CACHE_START : PLAN_SEG;')
r=rep(r,'            PLAN_SEG: begin','''            CACHE_START: state<=CACHE_WAIT;
            CACHE_WAIT: begin
                if(req2) state<=ACK;
                else if(!App_wr_busy && !Sdr_busy && !Sdr_init_ref_vld) state<=CACHE_READ;
            end
            CACHE_READ: if(cache_complete) state<=CACHE_END;
            CACHE_END: begin
                if(req2) state<=ACK;
                else if(cache_goal==256) state<=CACHE_WAIT;
                else state<=PLAN_CAPTURE;
            end
            PLAN_SEG: begin''')
(src/'SD/frame_fifo_read_portrait_focus.v').write_text(r,encoding='utf-8')

w=(src/'SD/frame_read_write_portrait_focus.v').read_text(encoding='utf-8')
w=rep(w,'wire diag_read_empty, diag_read_full;','wire diag_read_empty, diag_read_full;\nwire focus_pixel_valid;\nwire [31:0] focus_pixel_data;')
w=rep(w,'.we                     \t(Sdr_rd_en       \t\t\t)','.we                     \t(focus_pixel_valid)')
w=rep(w,'.di                      \t(Sdr_rd_dout                )','.di                      \t(focus_pixel_data)')
w=rep(w,'    .focus_scene(focus_scene), .focus_target(focus_target),','''    .Sdr_rd_dout(Sdr_rd_dout), .pixel_valid(focus_pixel_valid), .pixel_data(focus_pixel_data),
    .focus_scene(focus_scene), .focus_target(focus_target),''')
(src/'SD/frame_read_write_portrait_focus.v').write_text(w,encoding='utf-8')
v=(src/'portrait_focus_video.v').read_text(encoding='utf-8')
v=v[:v.index('    // Green-channel')]+'''    // Same 1/8 gain as SW4 level 0; preserve RGB proportions and hue.
    wire [23:0] dim_color={3'b0,scene_rgb[23:19],3'b0,scene_rgb[15:11],3'b0,scene_rgb[7:3]};
    assign rgb=photo_here ? photo_rgb :
        (scene[1] && step!=0) ? dim_color : scene_rgb;
endmodule
'''
(src/'portrait_focus_video.v').write_text(v,encoding='utf-8')
(run/'medal_kiosk_720p.prj').write_bytes((root/'fpga/td_project_720p/cli_runs/portrait_focus_20261031/medal_kiosk_720p.prj').read_bytes())
b=(root/'tools/build_720p_portrait_focus.tcl').read_text().replace('portrait_focus_20261031','portrait_focus_linecache_20261031')
(root/'tools/build_720p_portrait_focus_v2.tcl').write_text(b)
print('Prepared v2: one 512x32 line cache, aligned SDRAM requests, colour-preserving 1/8 backdrop.')
