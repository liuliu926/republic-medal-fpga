`timescale 1ns/1ps
// Sink-only replacement for the old FRAME client's private FAT/BMP loader.
// Header/pixels come from the SAME asset loader used by portraits/PCM/raw.
// The accepted scaler and bottom-up frame writer are instantiated unchanged.
module fat32_shared_pixel_frame_pipeline #(
 parameter integer ADDR_BITS=21,OUT_WIDTH=1280,OUT_HEIGHT=720,
 parameter integer BOX_LEFT=0,BOX_TOP=0,BOX_WIDTH=OUT_WIDTH,BOX_HEIGHT=OUT_HEIGHT,
 parameter integer READ_TIMEOUT_CYCLES=100_000_000,
 parameter integer REQUEST_TIMEOUT_CYCLES=10_000_000,
 parameter integer STREAM_TIMEOUT_CYCLES=1_000_000_000,
 parameter integer FIFO_RELEASE_CYCLES=8
)(
 input wire clk,rst,start,input wire [1:0] frame_index,
 input wire header_done,header_valid,input wire [15:0] source_width,source_height,
 input wire source_pixel_valid,input wire [23:0] source_pixel,
 output wire source_pixel_enable,source_pixel_ready,
 input wire loader_done,loader_error,input wire [7:0] loader_error_code,
 input wire sd_sector_req,sd_sector_end,
 output wire loader_cancel,
 input wire write_fifo_full,write_req_ack,write_finish,
 output wire write_req,output wire [1:0] write_addr_index,
 output wire [ADDR_BITS-1:0] write_len,write_first_offset,write_line_jump,
 output wire [15:0] write_line_width,
 output wire write_en,output wire [31:0] write_data,
 output wire busy,output reg done,error,output reg [7:0] error_code,
 output wire recovery_required
);
 reg active,writer_launched,waiting_frame_ready;
 reg loader_done_seen,scaler_done_seen,writer_done_seen;
 reg frame_start,scaler_start;
 reg [1:0] index_q;
 reg sector_pending,sd_recovery,cancelled;
 reg [31:0] sector_timer;
 wire frame_write_ready,scaled_ready,scaled_valid,scaler_done;
 wire [23:0] scaled_pixel;
 wire writer_busy,writer_done,writer_error,writer_recovery;
 wire accept_start=start&&!active&&!recovery_required;
 assign busy=active;
 assign recovery_required=writer_recovery||sd_recovery;
 assign loader_cancel=writer_recovery||sd_recovery||cancelled;
 wire all_done=(loader_done_seen||loader_done)&&
               (scaler_done_seen||scaler_done||loader_error)&&
               (!writer_launched||writer_done_seen||writer_done);

 bmp_resize_stream #(
  .ENABLE_OUTPUT_BACKPRESSURE(1),.OUT_WIDTH(OUT_WIDTH),.OUT_HEIGHT(OUT_HEIGHT),
  .BOX_LEFT(BOX_LEFT),.BOX_TOP(BOX_TOP),.BOX_WIDTH(BOX_WIDTH),.BOX_HEIGHT(BOX_HEIGHT)
 )u_resize(
  .clk(clk),.rst(rst||accept_start||loader_error||loader_cancel),.start(scaler_start),
  .source_width(source_width),.source_height(source_height),
  .input_ready(source_pixel_enable),.pixel_ready(source_pixel_ready),
  .pixel_valid(source_pixel_valid),.pixel_data(source_pixel),
  .out_valid(scaled_valid),.out_ready(scaled_ready),.out_pixel(scaled_pixel),.done(scaler_done));

 bmp_scaled_frame_write_ctrl #(
  .ADDR_BITS(ADDR_BITS),.OUT_WIDTH(OUT_WIDTH),.OUT_HEIGHT(OUT_HEIGHT),
  .REQUEST_TIMEOUT_CYCLES(REQUEST_TIMEOUT_CYCLES),.STREAM_TIMEOUT_CYCLES(STREAM_TIMEOUT_CYCLES),
  .FIFO_RELEASE_CYCLES(FIFO_RELEASE_CYCLES)
 )u_frame_write_ctrl(
  .clk(clk),.rst(rst),.frame_start(frame_start),.frame_index(index_q),
  .scaled_valid(scaled_valid),.scaled_pixel(scaled_pixel),.scaler_done(scaler_done),
  .upstream_abort(loader_error||sd_recovery),.write_fifo_full(write_fifo_full),
  .write_req_ack(write_req_ack),.write_finish(write_finish),
  .write_req(write_req),.write_addr_index(write_addr_index),.write_len(write_len),
  .write_first_offset(write_first_offset),.write_line_width(write_line_width),.write_line_jump(write_line_jump),
  .write_en(write_en),.write_data(write_data),.frame_write_ready(frame_write_ready),.scaled_ready(scaled_ready),
  .busy(writer_busy),.done(writer_done),.error(writer_error),.recovery_required(writer_recovery));

 always @(posedge clk or posedge rst)begin
  if(rst)begin
   active<=0;writer_launched<=0;waiting_frame_ready<=0;
   loader_done_seen<=0;scaler_done_seen<=0;writer_done_seen<=0;
   frame_start<=0;scaler_start<=0;index_q<=0;
   sector_pending<=0;sd_recovery<=0;cancelled<=0;sector_timer<=0;
   done<=0;error<=0;error_code<=0;
  end else begin
   done<=0;frame_start<=0;scaler_start<=0;
   if(sd_sector_req)begin sector_pending<=1;sector_timer<=0;end
   else if(sd_sector_end)begin sector_pending<=0;sector_timer<=0;end
   else if(sector_pending&&!sd_recovery)begin
    if(sector_timer>=READ_TIMEOUT_CYCLES-1)sd_recovery<=1;
    else sector_timer<=sector_timer+1'b1;
   end
   if(accept_start)begin
    active<=1;writer_launched<=0;waiting_frame_ready<=0;
    loader_done_seen<=0;scaler_done_seen<=0;writer_done_seen<=0;
    index_q<=frame_index;error<=0;error_code<=0;
   end else if(active)begin
    if(header_done&&header_valid&&!loader_error&&!loader_cancel)begin
     frame_start<=1;writer_launched<=1;waiting_frame_ready<=1;
    end
    if(waiting_frame_ready&&frame_write_ready)begin scaler_start<=1;waiting_frame_ready<=0;end
    if(loader_done)loader_done_seen<=1;
    if(scaler_done)scaler_done_seen<=1;
    if(writer_done)writer_done_seen<=1;
    if(loader_error)begin error<=1;error_code<=loader_error_code;end
    if(writer_error&&writer_launched&&!loader_error)begin error<=1;error_code<=8'h50;end
    if(sd_recovery)begin error<=1;error_code<=8'h51;end
    if(loader_cancel)begin cancelled<=1;waiting_frame_ready<=0;frame_start<=0;scaler_start<=0;end
    if(all_done&&(!sector_pending||sd_sector_end||sd_recovery))begin
     active<=0;done<=1;waiting_frame_ready<=0;
     loader_done_seen<=0;scaler_done_seen<=0;writer_done_seen<=0;
    end
   end
  end
 end
endmodule
