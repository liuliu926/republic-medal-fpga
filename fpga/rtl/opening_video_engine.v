`timescale 1ns/1ps
// Opening playback only. Clocks, raster, SD frontend, preload writer/FIFO,
// SDRAM physical controller, HDMI and audio are shared by the parent design.
// All three96-bit compressed row caches together use six BRAM32K instances.
// Inputs enable_video/play_enable and raster coordinates are in video_clk.
// rgb/pixel_valid have exactly five clocks of pixel pipeline latency.
//
// Hand off SDRAM only after enable_video=0 and reader_idle_mem=1. This waits
// for the old bundled row request and all physical native returns to drain.
// rst_mem/rst_video reset THIS engine only, never the SDRAM/HDMI controllers.
module opening_video_engine #(
 parameter integer FRAME_COUNT=75,
 parameter integer REFRESH_PER_FRAME=4,
 parameter integer AUDIO_TOTAL_SAMPLES=80000
)(
 input wire mem_clk,rst_mem,video_clk,rst_video,
 input wire enable_video,play_enable,preload_done_mem,
 input wire audio_timed,input wire [31:0] audio_samples,
 input wire external_write_busy,
 input wire Sdr_init_done,Sdr_init_ref_vld,Sdr_busy,
 input wire Sdr_rd_en,input wire [31:0] Sdr_rd_dout,
 output wire App_rd_en,output wire [20:0] App_rd_addr,
 input wire frame_tick,line_prepare,active,
 input wire [10:0] pixel_x,input wire [9:0] pixel_y,
 output wire [23:0] rgb,output wire pixel_valid,
 output wire frame_ready,output reg [6:0] frame_index,
 output reg finished,output wire reader_idle_mem,native_read_busy_mem,
 output wire cache_miss,output wire [3:0] error_code
);
 localparam [6:0] LAST_FRAME=FRAME_COUNT-1;
 localparam [15:0] LAST_REFRESH=REFRESH_PER_FRAME-1;
 (* ASYNC_REG="TRUE" *)reg [1:0] loaded_video;
 reg play_started;
 reg [15:0] refresh_count;
 reg [31:0] next_sample;
 reg [1:0] sample_phase;
 always @(posedge video_clk or posedge rst_video)begin
  if(rst_video)loaded_video<=0;
  else loaded_video<={loaded_video[0],preload_done_mem};
 end
 always @(posedge video_clk or posedge rst_video)begin
  if(rst_video)begin
   frame_index<=0;refresh_count<=0;play_started<=0;finished<=0;
   next_sample<=32'd1067;sample_phase<=0;
  end else if(!enable_video)begin
   frame_index<=0;refresh_count<=0;play_started<=0;finished<=0;
   next_sample<=32'd1067;sample_phase<=0;
  end else if(frame_tick)begin
   if(!play_enable)refresh_count<=0;
   else if(!play_started)begin
    if(frame_ready)begin play_started<=1;refresh_count<=0;end
   end else if(audio_timed)begin
    refresh_count<=0;
    if(frame_index==LAST_FRAME)begin
     if(audio_samples>=AUDIO_TOTAL_SAMPLES)finished<=1;
    end else if(audio_samples>=next_sample)begin
     frame_index<=frame_index+1'b1;
     // ceil(N*16000/15):1067,2134,3200,4267,...,80000.
     next_sample<=next_sample+(sample_phase==1?32'd1066:32'd1067);
     sample_phase<=sample_phase==2?2'd0:sample_phase+1'b1;
    end
   end else if(refresh_count==LAST_REFRESH)begin
    refresh_count<=0;
    if(frame_index<LAST_FRAME)frame_index<=frame_index+1'b1;
    else finished<=1;
   end else refresh_count<=refresh_count+1'b1;
  end
 end

 wire [9:0] native_x=pixel_x[10:1];
 wire [8:0] native_y=pixel_y[9:1];
 // Parent keeps pixel_y for the next active line during horizontal blanking.
 // Therefore only frame_tick (vertical blank) should force row_hint to zero;
 // line_prepare uses the upcoming active-line pixel_y, including row changes.
 reg [5:0] row_hint_q;
 always @(posedge video_clk or posedge rst_video)begin
  if(rst_video)row_hint_q<=0;
  else if(!enable_video||frame_tick)row_hint_q<=0;
  else if(line_prepare||active)row_hint_q<=native_y[8:3];
 end
 wire rd_en,rd_valid,row_miss,scaler_miss,native_idle;
 wire [5:0] rd_row;
 wire [7:0] rd_col;
 wire [95:0] rd_data;
 opening_video_sdram_row_cache rows(
  .mem_clk(mem_clk),.mem_rst(rst_mem),.preload_done_mem(preload_done_mem),
  .Sdr_init_done(Sdr_init_done),.Sdr_init_ref_vld(Sdr_init_ref_vld),.Sdr_busy(Sdr_busy),
  .external_write_busy(external_write_busy),
  .Sdr_rd_en(Sdr_rd_en),.Sdr_rd_dout(Sdr_rd_dout),
  .App_rd_en(App_rd_en),.App_rd_addr(App_rd_addr),
  .video_clk(video_clk),.video_rst(rst_video),
  .frame_request_valid(enable_video&&loaded_video[1]),.requested_frame(frame_index),
  .row_hint(row_hint_q),.frame_ready(frame_ready),
  .rd_en(rd_en),.rd_row(rd_row),.rd_col(rd_col),.rd_data(rd_data),.rd_valid(rd_valid),
  .error_code(error_code),.cache_miss(row_miss),.native_idle_mem(native_idle),
  .native_read_busy_mem(native_read_busy_mem));
 // Break the ready-tag compare path before its high-fanout palette/cache CE.
 reg scan_frame_valid;
 always @(posedge video_clk or posedge rst_video)begin
  if(rst_video)scan_frame_valid<=0;
  else scan_frame_valid<=enable_video&&frame_ready;
 end
 opening_bilinear_tile_scanout_640 scanout(
  .clk(video_clk),.rst(rst_video),.active(active),.line_prepare(line_prepare),
  .frame_valid(scan_frame_valid),.native_x(native_x),.native_y(native_y),
  .phase_x({2'd0,pixel_x[0]}),.phase_y({2'd0,pixel_y[0]}),
  .rd_en(rd_en),.rd_row(rd_row),.rd_col(rd_col),.rd_data(rd_data),.rd_valid(rd_valid),
  .rgb(rgb),.pixel_valid(pixel_valid),.cache_miss(scaler_miss));
 assign cache_miss=row_miss||scaler_miss;

 // Stop/idle qualifier has enough quiet clocks to cover the video->memory
 // request crossing even when enable drops just after a final row request.
 (* ASYNC_REG="TRUE" *)reg [2:0] enabled_mem;
 reg [4:0] idle_count;
 always @(posedge mem_clk or posedge rst_mem)begin
  if(rst_mem)begin enabled_mem<=0;idle_count<=0;end
  else begin
   enabled_mem<={enabled_mem[1:0],enable_video};
   if(enabled_mem[2]||!native_idle)idle_count<=0;
   else if(idle_count<16)idle_count<=idle_count+1'b1;
  end
 end
 assign reader_idle_mem=!enabled_mem[2]&&native_idle&&idle_count==16;
endmodule
