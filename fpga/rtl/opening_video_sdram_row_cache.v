`timescale 1ns/1ps
// Read-only nativeSDRAM frontend for immutable640x360 B96 frames.
//75frames x21600words plus224zero words are preloaded before this runs.
// A compressed row is160blocks x3words =480words. Native reads are ALWAYS
// aligned256-word requests; prefix/tail are discarded from512/768returnedwords.
// Request/return counts AND10drainclocks must complete before cache publication.
//
// Three video-owned rowbanks: protect current/next, prefetch lookahead+2.
// requested_frame/row_hint/frame_request_valid are in video_clk domain.
// Change frame at blanking; row_hint=0 during vertical blanking.
// rd_en/rd_row/rd_col -> rd_data/rd_valid after the same video edge (1cycle).
module opening_video_sdram_row_cache #(
 parameter integer READ_TIMEOUT_CYCLES=1250000
)(
 input wire mem_clk,mem_rst,preload_done_mem,
 input wire Sdr_init_done,Sdr_init_ref_vld,Sdr_busy,external_write_busy,
 input wire Sdr_rd_en,input wire [31:0] Sdr_rd_dout,
 output reg App_rd_en,output reg [20:0] App_rd_addr,
 input wire video_clk,video_rst,
 input wire frame_request_valid,input wire [6:0] requested_frame,
 input wire [5:0] row_hint,output wire frame_ready,
 input wire rd_en,input wire [5:0] rd_row,input wire [7:0] rd_col,
 output wire [95:0] rd_data,output reg rd_valid,
 output reg [3:0] error_code,output reg cache_miss,output wire native_idle_mem,native_read_busy_mem
);
 reg [2:0] bank_valid;
 reg [5:0] tag_row[0:2];reg [6:0] tag_frame[0:2];
 reg [6:0] initialized_frame;reg initialized;
 reg fetch_toggle,fetch_outstanding;
 reg [6:0] fetch_frame;
 reg [5:0] fetch_row;
 reg [1:0] fetch_bank;
 reg acknowledge_toggle;
 (* ASYNC_REG="TRUE" *) reg preload_v1,preload_v2,ack_v1,ack_v2;
 reg [5:0] plan0,plan1,plan2,wanted_row;
 reg hit0,hit1,hit2,need_fetch,have_victim;
 reg [1:0] victim,read_bank_now;
 reg read_hit,current_ready,next_ready;
 // Three short planning stages replace inputframe->rowmux->alltagmatches->
 // victimpriority->writeCE. Tags stay stable while no fetch is outstanding.
 // The captured frame/hint must still match at commit, otherwise retry.
 localparam [1:0] PCAPTURE=0,PCHECK=1,PCOMMIT=2;
 reg [1:0] planner_state;
 reg [6:0] planner_frame;
 reg [5:0] planner_hint,decision_row;
 reg decision_all_hit,decision_need,decision_have;
 reg [1:0] decision_victim;
 wire [5:0] hint_clamped=row_hint>44?6'd44:row_hint;
 wire [5:0] hint_next=hint_clamped>=44?6'd44:hint_clamped+6'd1;
 wire [5:0] plan_base_now=(initialized&&initialized_frame==requested_frame)?hint_clamped:6'd0;
 integer i;
 always @*begin
  hit0=0;hit1=0;hit2=0;
  for(i=0;i<3;i=i+1)begin
   if(bank_valid[i]&&tag_frame[i]==planner_frame)begin
    if(tag_row[i]==plan0)hit0=1;
    if(tag_row[i]==plan1)hit1=1;
    if(tag_row[i]==plan2)hit2=1;
   end
  end
  need_fetch=!(hit0&&hit1&&hit2);
  wanted_row=!hit0?plan0:!hit1?plan1:plan2;
  victim=0;have_victim=0;
  for(i=2;i>=0;i=i-1)begin
   if(!bank_valid[i]||tag_frame[i]!=planner_frame||
      (tag_row[i]!=plan0&&tag_row[i]!=plan1&&tag_row[i]!=plan2))begin
    victim=i;have_victim=1;
   end
  end
  read_hit=0;read_bank_now=0;current_ready=0;next_ready=0;
  for(i=2;i>=0;i=i-1)begin
   if(bank_valid[i]&&tag_frame[i]==requested_frame)begin
    if(tag_row[i]==rd_row)begin read_hit=1;read_bank_now=i;end
    if(tag_row[i]==hint_clamped)current_ready=1;
    if(tag_row[i]==hint_next)next_ready=1;
   end
  end
 end
 assign frame_ready=preload_v2&&frame_request_valid&&initialized&&
                    initialized_frame==requested_frame&&current_ready&&next_ready;
 always @(posedge video_clk or posedge video_rst)begin
  if(video_rst)begin preload_v1<=0;preload_v2<=0;ack_v1<=0;ack_v2<=0;end
  else begin
   preload_v1<=preload_done_mem;preload_v2<=preload_v1;
   ack_v1<=acknowledge_toggle;ack_v2<=ack_v1;
  end
 end
 integer j;
 always @(posedge video_clk or posedge video_rst)begin
  if(video_rst)begin
   bank_valid<=0;initialized<=0;initialized_frame<=0;
   fetch_toggle<=0;fetch_outstanding<=0;fetch_frame<=0;fetch_row<=0;fetch_bank<=0;
   planner_state<=PCAPTURE;planner_frame<=0;planner_hint<=0;plan0<=0;plan1<=0;plan2<=0;
   decision_row<=0;decision_all_hit<=0;decision_need<=0;decision_have<=0;decision_victim<=0;
   cache_miss<=0;
   for(j=0;j<3;j=j+1)begin tag_row[j]<=0;tag_frame[j]<=0;end
  end else begin
   if(!frame_request_valid)initialized<=0;
   if(fetch_outstanding)begin
    planner_state<=PCAPTURE;
    if(ack_v2==fetch_toggle)begin
     tag_row[fetch_bank]<=fetch_row;tag_frame[fetch_bank]<=fetch_frame;
     bank_valid[fetch_bank]<=1;fetch_outstanding<=0;
    end
   end else if(preload_v2&&frame_request_valid&&requested_frame<75)begin
    case(planner_state)
     PCAPTURE:begin
      planner_frame<=requested_frame;planner_hint<=row_hint;
      plan0<=plan_base_now;
      plan1<=plan_base_now>=44?6'd44:plan_base_now+6'd1;
      plan2<=plan_base_now>=43?6'd44:plan_base_now+6'd2;
      planner_state<=PCHECK;
     end
     PCHECK:begin
      decision_all_hit<=hit0&&hit1&&hit2;decision_need<=need_fetch;
      decision_have<=have_victim;decision_victim<=victim;decision_row<=wanted_row;
      planner_state<=PCOMMIT;
     end
     PCOMMIT:begin
      planner_state<=PCAPTURE;
      if(planner_frame==requested_frame&&planner_hint==row_hint)begin
       if((!initialized||initialized_frame!=planner_frame)&&decision_all_hit)begin
        initialized<=1;initialized_frame<=planner_frame;
       end
       if(decision_need&&decision_have)begin
        bank_valid[decision_victim]<=0;fetch_frame<=planner_frame;
        fetch_row<=decision_row;fetch_bank<=decision_victim;
        fetch_toggle<=!fetch_toggle;fetch_outstanding<=1;
       end
      end
     end
     default:planner_state<=PCAPTURE;
    endcase
   end else begin
    planner_state<=PCAPTURE;
   end
   if(rd_en&&frame_request_valid&&(!read_hit||rd_col>=160))cache_miss<=1;
  end
 end

 // Stable request bundle: metadata2FF, request3FF for one extra settling clock.
 (* ASYNC_REG="TRUE" *)reg req_m1,req_m2,req_m3;
 reg [6:0] frame_m1,frame_m2;
 reg [5:0] row_m1,row_m2;
 reg [1:0] bank_m1,bank_m2;
 always @(posedge mem_clk or posedge mem_rst)begin
  if(mem_rst)begin
   req_m1<=0;req_m2<=0;req_m3<=0;
   frame_m1<=0;frame_m2<=0;row_m1<=0;row_m2<=0;bank_m1<=0;bank_m2<=0;
  end else begin
   req_m1<=fetch_toggle;req_m2<=req_m1;req_m3<=req_m2;
   frame_m1<=fetch_frame;frame_m2<=frame_m1;
   row_m1<=fetch_row;row_m2<=row_m1;bank_m1<=fetch_bank;bank_m2<=bank_m1;
  end
 end
 localparam [3:0] IDLE=0,PLAN0=1,PLAN1=2,PLAN2=3,PLAN3=4,WAIT=5,ISSUE=6,DRAIN=7,FAIL=8;
 reg [3:0] state;
 reg [20:0] base_a,base_b,row_offset,row_base;
 reg [7:0] prefix;
 reg [9:0] commands_goal,commands_sent,received;
 reg [8:0] burst_count;
 reg [3:0] drain_count;
 reg [20:0] timeout_count;
 reg [1:0] destination_bank,word_phase;
 reg [7:0] block_col;
 reg [95:0] pack96;
 reg request_latched;
 wire accepting_returns=state==WAIT||state==ISSUE||state==DRAIN;
 wire logical_return=Sdr_rd_en&&accepting_returns&&received>={2'b0,prefix}&&
                     received<({2'b0,prefix}+10'd480);
 wire cache_store=logical_return&&word_phase==2;
 wire [95:0] cache_word={Sdr_rd_dout,pack96[95:32]};
 always @(posedge mem_clk or posedge mem_rst)begin
  if(mem_rst)begin
   state<=IDLE;App_rd_en<=0;App_rd_addr<=0;acknowledge_toggle<=0;
   base_a<=0;base_b<=0;row_offset<=0;row_base<=0;prefix<=0;
   commands_goal<=0;commands_sent<=0;received<=0;burst_count<=0;drain_count<=0;
   destination_bank<=0;word_phase<=0;block_col<=0;pack96<=0;
   request_latched<=0;timeout_count<=0;error_code<=0;
  end else begin
   if(App_rd_en)begin App_rd_addr<=App_rd_addr+1'b1;commands_sent<=commands_sent+1'b1;end
   if(Sdr_rd_en&&accepting_returns)begin
    received<=received+1'b1;
   end
   if(logical_return)begin
    pack96<=cache_word;
    if(word_phase==2)begin word_phase<=0;block_col<=block_col+1'b1;end
    else word_phase<=word_phase+1'b1;
   end
   if(state!=IDLE&&state!=FAIL)begin
    timeout_count<=timeout_count+1'b1;
   end
   case(state)
    IDLE:begin
     App_rd_en<=0;timeout_count<=0;
     if(req_m3!=acknowledge_toggle&&preload_done_mem&&Sdr_init_done)begin
      destination_bank<=bank_m2;request_latched<=req_m3;state<=PLAN0;
      commands_sent<=0;received<=0;word_phase<=0;block_col<=0;pack96<=0;
     end
    end
    PLAN0:begin
     //21600F=(16384+4096)F+(1024+64+32)F;480R=(512-32)R.
     base_a<=({frame_m2,14'd0}+{2'd0,frame_m2,12'd0});
     base_b<=({8'd0,frame_m2,6'd0}+{9'd0,frame_m2,5'd0});
     row_offset<=({6'd0,row_m2,9'd0}-{10'd0,row_m2,5'd0});state<=PLAN1;
    end
    PLAN1:begin base_a<=base_a+row_offset;base_b<=base_b+{4'd0,frame_m2,10'd0};state<=PLAN2;end
    PLAN2:begin row_base<=base_a+base_b;state<=PLAN3;end
    PLAN3:begin
     App_rd_addr<={row_base[20:8],8'd0};prefix<=row_base[7:0];
     commands_goal<=row_base[7:0]<=32?10'd512:10'd768;
     state<=WAIT;
    end
    WAIT:if(!(Sdr_busy||external_write_busy)&&!Sdr_init_ref_vld)begin
     App_rd_en<=1;burst_count<=0;state<=ISSUE;
    end
    ISSUE:begin
     //Exactly256registered native commands, addresses advance on actual enable.
     if(burst_count==255)begin App_rd_en<=0;drain_count<=0;state<=DRAIN;end
     else burst_count<=burst_count+1'b1;
    end
    DRAIN:begin
     if(drain_count<10)drain_count<=drain_count+1'b1;
     if(drain_count==10&&received==commands_sent&&!(Sdr_busy||external_write_busy)&&!Sdr_init_ref_vld)begin
      if(commands_sent<commands_goal)state<=WAIT;
      else if(block_col==160&&word_phase==0)begin acknowledge_toggle<=request_latched;state<=IDLE;end
      else begin error_code<=4'd3;state<=FAIL;end
     end
    end
    FAIL:App_rd_en<=0;
    default:;
   endcase
   // Faults outrank a simultaneous drain/commit transition. Never publish a
   // row if an extra native return or timeout occurs on its final cycle.
   if((Sdr_rd_en&&accepting_returns&&received>=commands_goal)||
      (state!=IDLE&&state!=FAIL&&timeout_count>=READ_TIMEOUT_CYCLES-1))begin
    error_code<=(Sdr_rd_en&&accepting_returns&&received>=commands_goal)?4'd2:4'd1;
    state<=FAIL;App_rd_en<=0;acknowledge_toggle<=acknowledge_toggle;
   end
  end
 end

 wire read_ok=rd_en&&preload_v2&&frame_request_valid&&read_hit&&rd_col<160;
 // All three logical banks share six parallel2Kx16 large BRAMs.
 // A single read and a single write port suffice; each address carries bank.
 wire [95:0] read_block;
 opening_compressed_rows_bram storage(
  .write_clk(mem_clk),.write_enable(cache_store),
  .write_bank(destination_bank),.write_col(block_col),.write_data(cache_word),
  .read_clk(video_clk),.read_enable(read_ok),
  .read_bank(read_bank_now),.read_col(rd_col),.read_data(read_block));
 always @(posedge video_clk or posedge video_rst)begin
  if(video_rst)rd_valid<=0;
  else rd_valid<=read_ok;
 end
 assign rd_data=rd_valid?read_block:96'd0;
 // Includes the bundled request crossing, not just the native command pin.
 assign native_idle_mem=state==IDLE&&req_m3==acknowledge_toggle&&!App_rd_en;
 // Reserve native reads throughout address planning, issuance and final drain.
 // A GUI write that wins the same IDLE edge finishes before row WAIT launches.
 assign native_read_busy_mem=state!=IDLE;
endmodule

module opening_compressed_rows_bram(
 input wire write_clk,write_enable,input wire [1:0] write_bank,
 input wire [7:0] write_col,input wire [95:0] write_data,
 input wire read_clk,read_enable,input wire [1:0] read_bank,
 input wire [7:0] read_col,output wire [95:0] read_data
);
 wire [10:0] write_address={1'b0,write_bank,write_col};
 wire [10:0] read_address={1'b0,read_bank,read_col};
`ifdef VIDEO_BRAM_BEHAVIORAL
 reg [95:0] memory[0:767];reg [95:0] q;
 always @(posedge write_clk)if(write_enable)memory[write_address]<=write_data;
 always @(posedge read_clk)if(read_enable)q<=memory[read_address];
 assign read_data=q;
`else
 genvar s;
 generate for(s=0;s<6;s=s+1)begin:slices
  EG_PHY_BRAM32K #(
   .MODE("DP16K"),.DATA_WIDTH_A("16"),.DATA_WIDTH_B("16"),
   .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
   .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL")
  ) ram(
   .doa(),.dia(write_data[s*16+:16]),.addra(write_address),
   .bytea(1'b0),.bytewea(1'b0),.csa(write_enable),.wea(write_enable),
   .clka(write_clk),.rsta(1'b0),.ocea(1'b1),
   .dob(read_data[s*16+:16]),.dib(16'd0),.addrb(read_address),
   .byteb(1'b0),.byteweb(1'b0),.csb(read_enable),.web(1'b0),
   .clkb(read_clk),.rstb(1'b0),.oceb(1'b1));
 end endgenerate
`endif
endmodule
