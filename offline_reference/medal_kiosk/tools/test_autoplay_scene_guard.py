"""Reproduce the lost-start race, then exercise the isolated fix.

Navigation pipeline, request guard and shared SD owner FSM are extracted from
production RTL. The real sequence, autoplay and PCM bridge are instantiated.
Only card/file transfer latency and the FIFO data path are mocked.
"""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
hdl = root/'fpga/user_source_720p/hdl_source'
out = root/'fpga/sim/runs/autoplay_scene_guard'
out.mkdir(parents=True, exist_ok=True)
binpath = root/'tools/local_hdl/iverilog/app/bin'
top_old = (hdl/'top_fat32_all_article_voice_auto3.v').read_text(encoding='utf-8')
nav = top_old[top_old.index('reg [1:0] nav_level_meta_sd'):top_old.index('always @(posedge video_clk',top_old.index('reg [1:0] nav_level_meta_sd'))]
(out/'nav_delay.v').write_text('''module nav_delay(
input sd_card_clk,rst_all,input [1:0] display_level,input [4:0] display_person,
input [2:0] display_section,output [1:0] nav_level_sd,
output [4:0] nav_person_sd,output [2:0] nav_section_sd);
''' + nav + '\nendmodule\n', encoding='utf-8')

frontend = (hdl/'SD/fat32_shared_boot_frontend_2line_candidate.v').read_text(encoding='utf-8')
frontend = frontend[:frontend.index('    frame_write_status_cdc u_write_status_cdc')]
frontend += '''
 assign sd_sector_ready=1; assign shared_metadata_valid=1;
 assign shared_boot_done=0; assign frame_recovery=0;
 assign frame_error=0; assign asset_error=0;
 assign frame_error_code=0; assign asset_error_code=0;
 reg mock_frame_done=0, mock_asset_done=0;
 assign frame_done=mock_frame_done; assign asset_done=mock_asset_done;
 integer frame_delay=0, asset_delay=0, mock_requests=0;
 always @(posedge clk) begin
  mock_frame_done<=0; mock_asset_done<=0;
  if(rst) begin frame_delay<=0; asset_delay<=0; mock_requests<=0; end
  else begin
   if(frame_start_q) begin frame_delay<=7+(mock_requests%5); mock_requests<=mock_requests+1; end
   else if(frame_delay>0) begin
    frame_delay<=frame_delay-1;
    if(frame_delay==1) mock_frame_done<=1;
   end
   if(asset_start_q) begin asset_delay<=pcm_owner?20:8+(mock_requests%7); mock_requests<=mock_requests+1; end
   else if(asset_delay>0) begin
    asset_delay<=asset_delay-1;
    if(asset_delay==1) mock_asset_done<=1;
   end
  end
 end
endmodule
'''
(out/'shared_owner.v').write_text(frontend, encoding='utf-8')
logs=[]
for name, topname, seqname, flags in [
    ('old_reproduction','top_fat32_all_article_voice_auto3.v','kiosk_fat32_sequence_autoplay_pilot.v',[]),
    ('fixed','top_fat32_all_article_voice_scene_guard.v','kiosk_fat32_sequence_scene_guard.v',['-DFIXED'])]:
    top=(hdl/topname).read_text(encoding='utf-8')
    guard=top[top.index('reg [7:0] voice_page_q;'):top.index('// A uniform 8.3 name')]
    guardpath=out/(name+'_guard.v')
    guardpath.write_text('''module voice_request_guard(
input sd_card_clk,rst_all,article_text_mode,input [1:0] display_level,
input [4:0] display_person,sequence_person,input [2:0] display_section,sequence_section,
input [7:0] display_page,output voice_requested);
''' + guard.replace('wire voice_requested =','assign voice_requested =')+'\nendmodule\n',encoding='utf-8')
    sources=[root/'fpga/sim/tb_autoplay_scene_guard.sv',hdl/'kiosk_autoplay_720p_direct_start.v',
             hdl/'SD'/seqname,hdl/'pcm_audio_bridge.v',hdl/'pcm_voice_player.v',
             out/'nav_delay.v',out/'shared_owner.v',guardpath]
    exe=out/(name+'.vvp')
    subprocess.run([str(binpath/'iverilog.exe'),'-g2012',*flags,'-s','tb','-o',str(exe),
                    *map(str,sources)],check=True,cwd=out,timeout=30)
    result=subprocess.run([str(binpath/'vvp.exe'),str(exe)],cwd=out,capture_output=True,text=True,timeout=30)
    logs.append(name+':\n'+result.stdout+result.stderr)
    (out/'result.log').write_text('\n'.join(logs),encoding='utf-8')
    print(logs[-1])
    result.check_returncode()
    assert 'PASS:' in result.stdout
