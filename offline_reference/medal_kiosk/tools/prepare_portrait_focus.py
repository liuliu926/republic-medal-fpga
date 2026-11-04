"""Isolated portrait transform candidate; never edits the accepted BGM inputs.

SDRAM tail is reused by scene: 13 home thumbnails OR a 320x400 RGB888
portrait (512-word stride). Returning home already reloads all thumbnails.
The raster reader transforms addresses, so a moved photo leaves its original
clean background visible and needs neither another full frame nor TF reads.
"""
from pathlib import Path
import hashlib
import json
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
src = root / 'fpga/user_source_720p/hdl_source'
release = root / 'releases/bgm_accepted_20261031'
snapshot = release / 'source_snapshot/fpga/user_source_720p/hdl_source'
run = root / 'fpga/td_project_720p/cli_runs/portrait_focus_20261031'
run.mkdir(parents=True, exist_ok=True)
manifest = json.loads((release/'release_manifest.json').read_text(encoding='utf-8'))
assert hashlib.sha256((release/manifest['bit']).read_bytes()).hexdigest().upper() == manifest['sha256']

def replace(text, old, new):
    assert text.count(old)==1, (old[:90], text.count(old))
    return text.replace(old,new)

# A small ROM of frame-atomic geometry, all values generated from one scale.
geo = '''`timescale 1ns/1ps
module portrait_focus_geometry(input wire [5:0] step,
    output reg [10:0] left, right,
    output reg [9:0] top, bottom,
    output reg [16:0] source_step);
always @* begin
    left=100; right=420; top=160; bottom=560; source_step=65536;
    case(step)
'''
for s in range(33):
    w,h=320+8*s,400+10*s
    left=100+round(252*s/32)
    top=160-5*s
    geo+=f"    6'd{s}: begin left=11'd{left}; right=11'd{left+w}; top=10'd{top}; bottom=10'd{top+h}; source_step=17'd{(320<<16)//w}; end\n"
geo+='    default: ;\n    endcase\nend\nendmodule\n'
(src/'portrait_focus_geometry.v').write_text(geo,encoding='utf-8')

# Store full-colour independent portrait in the scene's reusable SDRAM tail.
seq=(snapshot/'SD/kiosk_fat32_sequence_scene_guard.v').read_text(encoding='utf-8')
seq=replace(seq,"assign writer_frame_index = state == S_THM ? 2'd2 : 2'd1;", "assign writer_frame_index = 2'd2;")
seq=replace(seq,": 21'd715620;", ": 21'd204288;")
seq=replace(seq,"21'd2097103 : 21'd1599;", "21'd2097103 : 21'd831;")
(src/'SD/kiosk_fat32_sequence_focus.v').write_text(seq,encoding='utf-8')

reader=(snapshot/'SD/frame_fifo_read_fat32_menu_timing.v').read_text(encoding='utf-8')
reader=replace(reader,'    input wire intro_mode,','''    input wire intro_mode,
    input wire focus_scene, focus_target,
    output reg [5:0] focus_step,
    output reg focus_scene_latched,''')
reader=replace(reader,'    // Registered row decodes', '''    reg [1:0] focus_scene_sync, focus_target_sync;
    wire [10:0] focus_left, focus_right;
    wire [9:0] focus_top, focus_bottom;
    wire [16:0] focus_increment;
    reg [24:0] source_x_phase, source_y_phase;
    wire [24:0] source_x_next = source_x_phase + focus_increment;
    reg [20:0] focus_row_address;
    reg focus_burst;
    wire focus_row = focus_scene_latched &&
        screen_y >= focus_top && screen_y < focus_bottom;
    portrait_focus_geometry u_geometry (.step(focus_step),
        .left(focus_left), .right(focus_right), .top(focus_top),
        .bottom(focus_bottom), .source_step(focus_increment));
    // Bundled scene/geometry is committed only at a frame request boundary.
    always @(posedge mem_clk or posedge rst) begin
        if (rst) begin
            focus_scene_sync<=0; focus_target_sync<=0;
            focus_scene_latched<=0; focus_step<=0;
            source_y_phase<=0; focus_row_address<=21'd1843200;
            focus_burst<=0;
        end else begin
            focus_scene_sync<={focus_scene_sync[0],focus_scene};
            focus_target_sync<={focus_target_sync[0],focus_target};
            if (state == ACK && !req2) begin
                focus_scene_latched<=focus_scene_sync[1];
                if (!focus_scene_sync[1]) focus_step<=0;
                else if (focus_target_sync[1] && focus_step<32) focus_step<=focus_step+1'b1;
                else if (!focus_target_sync[1] && focus_step!=0) focus_step<=focus_step-1'b1;
            end
            if (state == ACK) source_y_phase<=0;
            else if (App_rd_en && screen_x==1279 && focus_row)
                source_y_phase<=source_y_phase+focus_increment;
            if (state == PLAN_CAPTURE)
                focus_row_address<=21'd1843200 + {7'd0,source_y_phase[24:16],9'd0};
            if (state == CHECK_FIFO)
                focus_burst<=focus_row && screen_x>=focus_left && screen_x<focus_right;
        end
    end

    // Registered row decodes''')
reader=replace(reader,"    wire portrait_row = !intro_mode &&", "    wire portrait_row = !intro_mode && !focus_scene_latched &&")
reader=replace(reader,"        if (portrait_row) begin", """        if (focus_row) begin
            if (screen_x < focus_left) segment_end=focus_left;
            else if (screen_x < focus_right) segment_end=focus_right;
        end else if (portrait_row) begin""")
reader=replace(reader,'            portrait_row_units <= 0;','            portrait_row_units <= 0;\n            source_x_phase <= 0;')
reader=replace(reader,'                read_address <= read_address + 1\'b1;', '''                if (focus_burst) begin
                    source_x_phase <= source_x_next;
                    read_address <= focus_row_address + source_x_next[24:16];
                end else read_address <= read_address + 1'b1;''')
reader=replace(reader,"                    3'd5: read_address <= background_address - 1'b1;", """                    3'd5: read_address <= background_address - 1'b1;
                    3'd6: begin
                        read_address<=focus_row_address;
                        source_x_phase<=0;
                    end""")
# The topmost portrait begins at y=0 only when fully enlarged; x remains >0,
# so segment source selection still always occurs at its left boundary.
reader=replace(reader,'                if (portrait_row && segment_limit <= page_limit) begin', '''                if (focus_row && segment_distance <= 256 && segment_limit <= page_limit) begin
                    if (segment_end_latched==focus_left) next_source<=3'd6;
                    else if (segment_end_latched==focus_right) next_source<=3'd5;
                end else if (portrait_row && segment_limit <= page_limit) begin''')
(src/'SD/frame_fifo_read_portrait_focus.v').write_text(reader,encoding='utf-8')

wrapper=(snapshot/'SD/frame_read_write_fat32_diag.v').read_text(encoding='utf-8')
wrapper=replace(wrapper,'\tinput                            read_req,','''    input wire focus_scene, focus_target,
    output wire [5:0] focus_step,
    output wire focus_scene_latched,
\tinput                            read_req,''')
wrapper=replace(wrapper,'frame_fifo_read_m0\n(\n', 'frame_fifo_read_m0\n(\n') if False else wrapper
wrapper=replace(wrapper,'    .intro_mode                 (intro_mode               ),','''    .intro_mode                 (intro_mode               ),
    .focus_scene(focus_scene), .focus_target(focus_target),
    .focus_step(focus_step), .focus_scene_latched(focus_scene_latched),''')
(src/'SD/frame_read_write_portrait_focus.v').write_text(wrapper,encoding='utf-8')

top=(snapshot/'top_fat32_bgm_candidate.v').read_text(encoding='utf-8')
top=replace(top,'kiosk_nav #(.PERSON_COUNT(13)) u_kiosk_nav (','''// Focus is available only in a fully loaded manual person introduction.
wire focus_eligible = nav_level == 1 && !auto_mode && !brightness_open && !debug_load_busy;
wire focus_short, focus_long;
reg focus_target;
wire [5:0] focus_step_mem;
wire focus_scene_mem;
reg [1:0] focus_moving_sync;
wire focus_lock = focus_target || focus_moving_sync[1];
portrait_focus_key u_focus_key (.clk(clk), .rst(rst_all), .key_n(key1),
    .enable(focus_eligible), .short_pulse(focus_short), .long_pulse(focus_long));
always @(posedge clk or posedge rst_all) begin
    if (rst_all) begin focus_target<=0; focus_moving_sync<=0; end
    else begin
        focus_moving_sync<={focus_moving_sync[0],(focus_step_mem!=0)};
        if (!focus_eligible || key_pulse[2]) focus_target<=0;
        else if (focus_long) focus_target<=!focus_target;
    end
end
wire focus_nav_next = (nav_level==1 && !auto_mode) ? focus_short : key_pulse[0];
kiosk_nav #(.PERSON_COUNT(13)) u_kiosk_nav (''')
top=replace(top,'.key_next_pulse(key_pulse[0] && !brightness_open), .key_prev_pulse(key_pulse[1] && !brightness_open),', '.key_next_pulse(focus_nav_next && !brightness_open && !focus_lock), .key_prev_pulse(key_pulse[1] && !brightness_open && !focus_lock),')
top=replace(top,'.key_back_pulse(key_pulse[2] && !brightness_open),','.key_back_pulse(key_pulse[2] && !brightness_open && !focus_lock),')
top=replace(top,'.key_enter_pulse(key_pulse[3] && !brightness_open &&','.key_enter_pulse(key_pulse[3] && !brightness_open && !focus_lock &&')
top=replace(top,'    .intro_mode        (intro_mem_sync),','''    .intro_mode        (intro_mem_sync),
    .focus_scene(nav_level_sd == 1 && sequence_debug_state == 7 && !sequence_loading),
    .focus_target(focus_target), .focus_step(focus_step_mem),
    .focus_scene_latched(focus_scene_mem),''')
top=replace(top,'loading_status_overlay u_loading_status (','''wire [23:0] focus_rgb;
portrait_focus_video u_focus_video (
    .clk(video_clk), .rst(rst_video), .x(overlay_x), .y(overlay_y),
    .step_mem(focus_step_mem), .scene_mem(focus_scene_mem),
    .photo_rgb(vout_data), .scene_rgb(home_text_rgb), .rgb(focus_rgb));
loading_status_overlay u_loading_status (''')
top=replace(top,'.loading(load_busy_video_sync), .rgb_in(IMAGE_SCAN_TEST ? home_text_rgb : osd_rgb),','.loading(load_busy_video_sync), .rgb_in(IMAGE_SCAN_TEST ? focus_rgb : osd_rgb),')
(src/'top_portrait_focus_candidate.v').write_text(top,encoding='utf-8')

video='''`timescale 1ns/1ps
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
    // Green-channel luminance approximation: gray/dim backdrop without
    // placing extra carry chains after the subtitle BRAM pixel output.
    wire [7:0] dimgray={1'b0,scene_rgb[15:9]};
    assign rgb=photo_here ? photo_rgb :
        (scene[1] && step!=0) ? {dimgray,dimgray,dimgray} : scene_rgb;
endmodule
'''
(src/'portrait_focus_video.v').write_text(video,encoding='utf-8')

tree=ET.ElementTree(ET.fromstring((release/'medal_kiosk_720p.prj').read_text(encoding='utf-8').replace('UsedInP&R','UsedInP&amp;R')))
verilog=tree.getroot().find('./Source_Files/Verilog')
replacements={'top_fat32_bgm_candidate.v':'top_portrait_focus_candidate.v',
 'kiosk_fat32_sequence_scene_guard.v':'kiosk_fat32_sequence_focus.v',
 'frame_fifo_read_fat32_menu_timing.v':'frame_fifo_read_portrait_focus.v',
 'frame_read_write_fat32_diag.v':'frame_read_write_portrait_focus.v'}
for node in verilog.findall('File'):
    name=Path(node.attrib['Path']).name
    if name in replacements: node.set('Path',node.attrib['Path'].replace(name,replacements[name]))
    assert (run/node.attrib['Path']).resolve().is_file(),node.attrib['Path']
for i,name in enumerate(['portrait_focus_key.v','portrait_focus_geometry.v','portrait_focus_video.v']):
    node=ET.SubElement(verilog,'File',Path='../../../user_source_720p/hdl_source/'+name)
    info=ET.SubElement(node,'FileInfo')
    for k,v in [('UsedInSyn','true'),('UsedInP&R','true'),('BelongTo','design_1'),('CompileOrder',str(160+i))]:
        ET.SubElement(info,'Attr',Name=k,Val=v)
tree.write(run/'medal_kiosk_720p.prj',encoding='utf-8',xml_declaration=True)
build=(root/'tools/build_720p_bgm_candidate.tcl').read_text(encoding='utf-8').replace('bgm_compact_20261031','portrait_focus_20261031').replace('medal_720p_bgm_candidate.bit','medal_720p_portrait_focus.bit').replace('BGM_CANDIDATE','PORTRAIT_FOCUS')
(root/'tools/build_720p_portrait_focus.tcl').write_text(build,encoding='utf-8')
print('Prepared isolated portrait focus candidate. No TF files or accepted sources modified.')
