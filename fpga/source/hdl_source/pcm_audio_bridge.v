// Serializes SD bytes into signed PCM samples, crosses from the SD clock to
// pixel clock through the existing FPGA FIFO IP, and emits 48 kHz audio.
module pcm_audio_bridge #(parameter integer CLOCK_HZ=75000000, AUDIO_HZ=48000) (
 input wire sd_clk, pixel_clk, rst, pixel_rst,
 input wire requested, start_allowed,
 input wire raw_valid, output wire raw_ready, input wire [7:0] raw_data,
 input wire raw_active, raw_done, raw_error,
 output reg raw_start,
 output wire audio_valid, output wire signed [23:0] audio_data,
 output wire [31:0] samples_played, output wire underrun
);
 reg started, low_valid, draining;
 reg [7:0] low_byte;
 wire fifo_full, fifo_empty;
 wire [15:0] fifo_data;
 wire pcm_ready;
 wire fifo_reset = rst || !requested;
 reg want_meta, want_sync;
 always @(posedge pixel_clk or posedge pixel_rst) begin
   if(pixel_rst) begin want_meta<=0; want_sync<=0; end
   else begin want_meta<=requested; want_sync<=want_meta; end
 end
 always @(posedge sd_clk or posedge rst) begin
   if(rst) begin started<=0; low_valid<=0; low_byte<=0; raw_start<=0; draining<=0; end
   else begin
     raw_start<=0;
     if(!requested) begin started<=0; low_valid<=0; if(raw_active) draining<=1; end
     else begin
       if(draining && !raw_active) draining<=0;
       if(!started && !draining && start_allowed && !raw_active) begin raw_start<=1; started<=1; end
       if(!draining && raw_valid && raw_ready) begin
         if(!low_valid) begin low_byte<=raw_data; low_valid<=1; end
         else low_valid<=0;
       end
     end
   end
 end
 // Aborted reads drain to allow the shared SD interface to be released.
 assign raw_ready = !requested || draining || !fifo_full;
 wfifo_32_32_512 #(.DATA_WIDTH_W(16),.DATA_WIDTH_R(16),
   .ADDR_WIDTH_W(8),.ADDR_WIDTH_R(8),.AL_FULL_NUM(253),.AL_EMPTY_NUM(2)) fifo (
   .rst(fifo_reset),.clkw(sd_clk),.clkr(pixel_clk),
   .we(requested && !draining && raw_valid && raw_ready && low_valid),.di({raw_data,low_byte}),
   .re(pcm_ready && !fifo_empty),.dout(fifo_data),.valid(),
   .full_flag(fifo_full),.empty_flag(fifo_empty),.afull(),.aempty(),.wrusedw(),.rdusedw());
 pcm_voice_player #(.CLOCK_HZ(CLOCK_HZ),.AUDIO_HZ(AUDIO_HZ)) player(.pixel_clk(pixel_clk),.rst(pixel_rst),.enable(want_sync),
   .sample_valid(!fifo_empty),.sample_data(fifo_data),.sample_ready(pcm_ready),
   .audio_valid(audio_valid),.audio_data(audio_data),.samples_played(samples_played),.underrun(underrun));
endmodule
