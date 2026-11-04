`timescale 1ns/1ps
// Video-clock-only session coordinator. All asynchronous status inputs must
// already be synchronized by the parent. frame_tick marks vertical blanking.
// It never resets HDMI, the PLLs, the raster, or the physical SD frontend.
// preload_start is a LEVEL during LOAD; opening_audio_requested is a LEVEL
// during ARM_AUDIO/PLAY. The parent resets their local counters while low.
// Default fades take32 frame ticks. Navigation is released only in HOME.
module opening_session_control #(
 parameter integer HOLD_MIN_FRAMES=30,
 parameter integer GUI_SETTLE_FRAMES=2,
 parameter integer RELOAD_DRAIN_FRAMES=2,
 parameter integer LOAD_TIMEOUT_FRAMES=3600,
 parameter integer AUDIO_ARM_TIMEOUT_FRAMES=600,
 parameter integer PLAY_TIMEOUT_FRAMES=1200,
 parameter integer GUI_LOAD_TIMEOUT_FRAMES=1800,
 parameter integer DRAIN_TIMEOUT_FRAMES=180,
 parameter integer GUI_SETTLE_TIMEOUT_FRAMES=180,
 parameter [31:0] AUDIO_END_SAMPLES=32'd80000
)(
 input wire clk,rst,frame_tick,replay_pulse,
 input wire sd_ready,preload_done,preload_error,
 input wire pcm_active,pcm_error,input wire [31:0] audio_samples,
 input wire video_finished,video_reader_idle,
 input wire gui_ready,shared_idle,mem_idle,
 output reg preload_start,opening_audio_requested,
 output reg video_enable,video_play_enable,
 output reg gui_assets_reset,gui_nav_reset,gui_read_enable,show_gui,bgm_enable,
 output reg abort_writer,
 output reg [5:0] fade_gain,
 output wire [3:0] stage,output reg [7:0] error
);
 localparam [3:0] LOAD=0,ARM_AUDIO=1,PLAY=2,HOLD=3,FADE_VIDEO_OUT=4,
                  WAIT_GUI=5,GUI_SETTLE=6,FADE_HOME_IN=7,HOME=8,
                  FADE_HOME_OUT=9,WAIT_RELOAD=10,FAIL_DRAIN=11,FAIL_HOME_LOAD=12;
 reg [3:0] state,next_state;
 reg [15:0] frame_age;
 reg [5:0] next_gain;
 reg [7:0] raised_error;
 reg preload_clear_seen,audio_zero_seen;
 // Meaningful progress evidence for diagnostics: distinguish an unavailable
 // file stream from an active stream that never produces an audio sample.
 reg pcm_active_seen;
 assign stage=state;
 wire drained=video_reader_idle && shared_idle && mem_idle;
 // All externally consumed enables/resets are actual flip-flops. In
 // particular, a multibit stage transition must never generate a short
 // asynchronous-reset pulse in an otherwise live GUI child module.
 function [6:0] controls;
  input [3:0] s;
  begin
   // video_enable,video_play_enable,assets_reset,nav_reset,read,show,bgm
   case(s)
    ARM_AUDIO:controls=7'b1011000;
    PLAY:controls=7'b1111000;
    HOLD,FADE_VIDEO_OUT:controls=7'b1001000;
    WAIT_GUI,FAIL_HOME_LOAD:controls=7'b0001000;
    GUI_SETTLE,FADE_HOME_IN:controls=7'b0001111;
    FADE_HOME_OUT:controls=7'b0001111;
    HOME:controls=7'b0000111;
    default:controls=7'b0011000;
   endcase
  end
 endfunction
 always @*begin
  next_state=state;next_gain=fade_gain;raised_error=0;
  case(state)
   LOAD:begin
    next_gain=32;
    if(preload_error)begin raised_error=8'h01;next_state=FAIL_DRAIN;end
    else if(sd_ready && preload_clear_seen && preload_done)next_state=ARM_AUDIO;
    else if(frame_tick && frame_age>=LOAD_TIMEOUT_FRAMES-1)begin
     raised_error=8'h02;next_state=FAIL_DRAIN;
    end
   end
   ARM_AUDIO:begin
    next_gain=32;
    if(pcm_error)begin raised_error=8'h03;next_state=FAIL_DRAIN;end
    else if(audio_zero_seen && audio_samples!=0)next_state=PLAY;
    else if(frame_tick && frame_age>=AUDIO_ARM_TIMEOUT_FRAMES-1)begin
     raised_error=pcm_active_seen ? 8'h04 : 8'h0c;next_state=FAIL_DRAIN;
    end
   end
   PLAY:begin
    next_gain=32;
    if(pcm_error)begin raised_error=8'h03;next_state=FAIL_DRAIN;end
    // The engine commits frame74 at frame_tick and raises video_finished
    // only after that last frame and the audio end boundary. Stopping here
    // from the sample count alone can freeze frame73 between frame ticks.
    else if(video_finished)next_state=HOLD;
    else if(frame_tick && frame_age>=PLAY_TIMEOUT_FRAMES-1)begin
     raised_error=8'h05;next_state=FAIL_DRAIN;
    end
   end
   HOLD:begin
    next_gain=32;
    // The final frame resides above6.39MB, separately from home BUF0 and
    // thumbnails. Only asset writes run while the final video is displayed.
    if(frame_tick && frame_age>=HOLD_MIN_FRAMES-1 && gui_ready)next_state=FADE_VIDEO_OUT;
    else if(frame_tick && frame_age>=GUI_LOAD_TIMEOUT_FRAMES-1)begin
     raised_error=8'h06;next_state=FAIL_DRAIN;
    end
   end
   FADE_VIDEO_OUT:begin
    if(frame_tick)begin
     if(fade_gain>0)next_gain=fade_gain-1'b1;
     if(fade_gain<=1)begin next_gain=0;next_state=WAIT_GUI;end
    end
   end
   WAIT_GUI:begin
    next_gain=0;
    // Switch the display source only on a blanking boundary after all old
    // SDRAM traffic is drained. No new GUI reads are issued during this wait.
    if(frame_tick && drained)next_state=GUI_SETTLE;
    else if(frame_tick && frame_age>=DRAIN_TIMEOUT_FRAMES-1)begin
     raised_error=8'h07;next_state=FAIL_DRAIN;
    end
   end
   GUI_SETTLE:begin
    next_gain=0;
    if(frame_tick && frame_age>=GUI_SETTLE_FRAMES-1 && gui_ready)next_state=FADE_HOME_IN;
    else if(frame_tick && frame_age>=GUI_SETTLE_TIMEOUT_FRAMES-1)begin
     // The original GUI keeps its own Loading/error presentation. Return
     // control to it rather than trapping the system in an opening state.
     raised_error=8'h08;next_state=FADE_HOME_IN;
    end
   end
   FADE_HOME_IN:begin
    if(frame_tick)begin
     if(fade_gain<32)next_gain=fade_gain+1'b1;
     if(fade_gain>=31)begin next_gain=32;next_state=HOME;end
    end
   end
   HOME:begin
    next_gain=32;
    if(replay_pulse)next_state=FADE_HOME_OUT;
   end
   FADE_HOME_OUT:begin
    if(frame_tick)begin
     if(fade_gain>0)next_gain=fade_gain-1'b1;
     if(fade_gain<=1)begin next_gain=0;next_state=WAIT_RELOAD;end
    end
   end
   WAIT_RELOAD:begin
    next_gain=0;
    // Disable GUI reads/assets/navigation first, then wait at least two
    // complete blanking ticks in addition to explicit physical idle levels.
    if(frame_tick && frame_age>=RELOAD_DRAIN_FRAMES-1 && drained)next_state=LOAD;
    else if(frame_tick && frame_age>=DRAIN_TIMEOUT_FRAMES-1)begin
     raised_error=8'h09;next_state=FAIL_DRAIN;
    end
   end
   FAIL_DRAIN:begin
    next_gain=32;
    if(frame_tick && frame_age>=RELOAD_DRAIN_FRAMES-1 && drained)next_state=FAIL_HOME_LOAD;
    else if(frame_tick && frame_age>=DRAIN_TIMEOUT_FRAMES-1)begin
     // Video/audio requests are already low. Let the original GUI continue
     // its own recovery even if an old idle status is permanently stuck.
     raised_error=8'h0a;next_state=FAIL_HOME_LOAD;
    end
   end
   FAIL_HOME_LOAD:begin
    next_gain=0;
    if(frame_tick && gui_ready && shared_idle && mem_idle)next_state=GUI_SETTLE;
    else if(frame_tick && frame_age>=GUI_LOAD_TIMEOUT_FRAMES-1)begin
     raised_error=8'h0b;next_state=GUI_SETTLE;
    end
   end
   default:begin next_state=FAIL_DRAIN;next_gain=32;raised_error=8'hff;end
  endcase
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=LOAD;frame_age<=0;fade_gain<=32;error<=0;
   preload_start<=0;opening_audio_requested<=0;
   abort_writer<=0;
   {video_enable,video_play_enable,gui_assets_reset,gui_nav_reset,
    gui_read_enable,show_gui,bgm_enable}<=7'b0011000;
   preload_clear_seen<=0;audio_zero_seen<=0;pcm_active_seen<=0;
  end else begin
   state<=next_state;fade_gain<=next_gain;
   preload_start<=next_state==LOAD;
   opening_audio_requested<=next_state==ARM_AUDIO || next_state==PLAY;
   abort_writer<=next_state==FAIL_DRAIN;
   {video_enable,video_play_enable,gui_assets_reset,gui_nav_reset,
    gui_read_enable,show_gui,bgm_enable}<=controls(next_state);
   if(next_state!=state)frame_age<=0;
   else if(frame_tick && frame_age!=16'hffff)frame_age<=frame_age+1'b1;
   if(error==0 && raised_error!=0)error<=raised_error;
   if(next_state==LOAD && state!=LOAD)preload_clear_seen<=0;
   else if(state==LOAD && !preload_done)preload_clear_seen<=1;
   if(next_state==ARM_AUDIO && state!=ARM_AUDIO)begin audio_zero_seen<=0;pcm_active_seen<=0;end
   else if(state==ARM_AUDIO)begin
    if(audio_samples==0)audio_zero_seen<=1;
    if(pcm_active)pcm_active_seen<=1;
   end
  end
 end
endmodule
