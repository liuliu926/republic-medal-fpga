`timescale 1ns/1ps
module frame_fifo_write
#
(
	parameter MEM_DATA_BITS          = 32,
	parameter ADDR_BITS              = 21,
	parameter BURST_BITS             = 9,
	parameter BURST_SIZE             = 128,
	parameter WRITE_V_FLIP           = 1,      // 1: write image rows upside-down to cancel BMP bottom-up storage
	parameter FRAME_WIDTH            = 640,
	parameter FRAME_HEIGHT           = 480
)               
(
	input                            rst,                  
	input                            mem_clk,                    // external memory controller user interface clock
	input							 Sdr_init_done,
	input							 Sdr_init_ref_vld,
    input							 Sdr_busy,
	input							 App_rd_busy,
    output							 O_wr_busy,
	
	output 							 App_wr_en,
	output  [ADDR_BITS - 1:0]	 	App_wr_addr,
	/*
    output reg                       wr_burst_req,               // to external memory controller,send out a burst write request  
	output reg[BURST_BITS - 1:0]     wr_burst_len,               // to external memory controller,data length of the burst write request, not bytes 
	output reg[ADDR_BITS - 1:0]      wr_burst_addr,              // to external memory controller,base address of the burst write request 
	input                            wr_burst_data_req,          // from external memory controller,write data request ,before data 1 clock 
	input                            wr_burst_finish,            // from external memory controller,burst write finish
	*/
	input                            write_req,                  // data write module write request,keep '1' until read_req_ack = '1'
	output reg                       write_req_ack,              // data write module write request response
	output                           write_finish,               // data write module write request finish
	input[ADDR_BITS - 1:0]           write_addr_0,               // data write module write request base address 0, used when write_addr_index = 0
	input[ADDR_BITS - 1:0]           write_addr_1,               // data write module write request base address 1, used when write_addr_index = 1
	input[ADDR_BITS - 1:0]           write_addr_2,               // data write module write request base address 1, used when write_addr_index = 2
	input[ADDR_BITS - 1:0]           write_addr_3,               // data write module write request base address 1, used when write_addr_index = 3
	input[1:0]                       write_addr_index,           // select valid base address from write_addr_0 write_addr_1 write_addr_2 write_addr_3
	input[ADDR_BITS - 1:0]           write_len,                  // data write module write request data length
	input[ADDR_BITS - 1:0]           write_first_offset,         // first pixel relative to selected frame base
	input[15:0]                      write_line_width,           // written pixels per row
	input[ADDR_BITS - 1:0]           write_line_jump,            // address subtraction at row end
	output reg                       fifo_aclr,                  // to fifo asynchronous clear
	input[9:0]                      rdusedw                     // from fifo read used words
);
localparam ONE                       = 256'd1;                   //256 bit '1'   you can use ONE[n-1:0] for n bit '1'
localparam ZERO                      = 256'd0;                   //256 bit '0'

// The caller supplies the address of the first bottom-up BMP row and the
// address jump at each row end. A full frame and a portrait rectangle can
// therefore share the same burst writer without overwriting other pixels.

//write state machine code
localparam S_IDLE                    = 0;                        //idle state,waiting for write
localparam S_ACK                     = 1;                        //written request response
localparam S_CHECK_FIFO              = 2;                        //check the FIFO status, ensure that there is enough space to burst write
localparam S_WRITE_BURST             = 3;                        //begin a burst write
localparam S_WRITE_BURST_END         = 4;                        //a burst write complete
localparam S_END                     = 5;                        //a frame of data is written to complete


reg                                 write_req_d0;                //asynchronous write request, synchronize to 'mem_clk' clock domain,first beat
reg                                 write_req_d1;                //the second
reg                                 write_req_d2;                //third,Why do you need 3 ? Here's the design habit
reg[ADDR_BITS - 1:0]                write_len_d0;                //asynchronous write_len(write data length), synchronize to 'mem_clk' clock domain first
reg[ADDR_BITS - 1:0]                write_len_d1;                //second
reg[ADDR_BITS - 1:0]                first_offset_d0, first_offset_d1;
reg[15:0]                           line_width_d0, line_width_d1;
reg[ADDR_BITS - 1:0]                line_jump_d0, line_jump_d1;
reg[15:0]                           line_width_latch;
reg[ADDR_BITS - 1:0]                line_jump_latch;
reg[ADDR_BITS - 1:0]                write_len_latch;             //lock write data length
reg[ADDR_BITS - 1:0]                write_remaining;             //length left at the next burst boundary
reg[ADDR_BITS - 1:0]                write_cnt;                   //write data counter
reg[1:0]                            write_addr_index_d0;
reg[1:0]                            write_addr_index_d1;
reg[3:0]                            state;                       //state machine
reg [ADDR_BITS - 1:0]	 App_wr_addr_r;
reg [15:0]                            wr_x;                       // current x position in one input row

reg [BURST_BITS - 1:0]				burst_cnt;
wire								wr_burst_finish;

reg App_wr_en_r;
reg App_wr_en_d0;
reg [BURST_BITS-1:0] burst_target;
reg [4:0] settle_count;
// This pilot has two fixed destination widths: 1280 for a background and
// 80 for a portrait. Both frame lengths are exact multiples of these bursts.

wire into_burst;
// Each SDRAM write burst stops at the image-row boundary.  This avoids
// changing a rectangular destination address during a running burst.
// Do not launch a request while the physical SDRAM is refreshing/busy.
assign into_burst = (rdusedw >= burst_target) && ~App_rd_busy &&
                    !Sdr_busy && !Sdr_init_ref_vld;

assign App_wr_addr = {App_wr_addr_r[ADDR_BITS - 1:0]};
//assign O_wr_busy = (state != S_IDLE || (S_IDLE && write_req_d2));
assign O_wr_busy = (state == S_WRITE_BURST || (state == S_CHECK_FIFO && into_burst));//在突发，或者将要突发，则显示busy
assign wr_burst_finish = (burst_cnt >= burst_target);
assign write_finish = (state == S_END) ? 1'b1 : 1'b0;            //write finish at state 'S_END'
assign App_wr_en = App_wr_en_d0;


always@(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		write_req_d0    <=  1'b0;
		write_req_d1    <=  1'b0;
		write_req_d2    <=  1'b0;
		write_len_d0    <=  ZERO[ADDR_BITS - 1:0];              //equivalent to write_len_d0 <= 0;
		write_len_d1    <=  ZERO[ADDR_BITS - 1:0];              //equivalent to write_len_d1 <= 0;
		first_offset_d0 <= ZERO[ADDR_BITS - 1:0];
		first_offset_d1 <= ZERO[ADDR_BITS - 1:0];
		line_width_d0 <= 16'd0;
		line_width_d1 <= 16'd0;
		line_jump_d0 <= ZERO[ADDR_BITS - 1:0];
		line_jump_d1 <= ZERO[ADDR_BITS - 1:0];
		write_addr_index_d0    <=  2'b00;
		write_addr_index_d1    <=  2'b00;
	end
	else
	begin
		write_req_d0    <=  write_req;
		write_req_d1    <=  write_req_d0;
		write_req_d2    <=  write_req_d1;
		write_len_d0    <=  write_len;
		write_len_d1    <=  write_len_d0;
		first_offset_d0 <= write_first_offset;
		first_offset_d1 <= first_offset_d0;
		line_width_d0 <= write_line_width;
		line_width_d1 <= line_width_d0;
		line_jump_d0 <= write_line_jump;
		line_jump_d1 <= line_jump_d0;
		write_addr_index_d0 <= write_addr_index;
		write_addr_index_d1 <= write_addr_index_d0;
	end 
end
always @(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		burst_cnt <= ZERO[BURST_BITS - 1:0];
		App_wr_addr_r <= ZERO[ADDR_BITS - 1:0];
		App_wr_en_d0 <= 1'b0;
		wr_x <= 16'd0;
	end
	else begin
	
		if(state == S_CHECK_FIFO)
			burst_cnt <= ZERO[BURST_BITS - 1:0];
		else if(App_wr_en)
			burst_cnt <= burst_cnt + 1'b1;
		else
			burst_cnt <= burst_cnt;
		//
		if(state == S_ACK)
			begin
				wr_x <= 16'd0;
				if(write_addr_index_d1 == 2'd0)
					App_wr_addr_r <= WRITE_V_FLIP ? (write_addr_0 + first_offset_d1) : write_addr_0;
				else if(write_addr_index_d1 == 2'd1)
					App_wr_addr_r <= WRITE_V_FLIP ? (write_addr_1 + first_offset_d1) : write_addr_1;
				else if(write_addr_index_d1 == 2'd2)
					App_wr_addr_r <= WRITE_V_FLIP ? (write_addr_2 + first_offset_d1) : write_addr_2;
				else if(write_addr_index_d1 == 2'd3)
					App_wr_addr_r <= WRITE_V_FLIP ? (write_addr_3 + first_offset_d1) : write_addr_3;
			end
		else if(App_wr_en)
			begin
				if(WRITE_V_FLIP)
				begin
					if(wr_x == line_width_latch - 16'd1)
					begin
						wr_x <= 16'd0;
						App_wr_addr_r <= App_wr_addr_r - line_jump_latch;
					end
					else
					begin
						wr_x <= wr_x + 1'b1;
						App_wr_addr_r <= App_wr_addr_r + 1'b1;
					end
				end
				else
					App_wr_addr_r <= App_wr_addr_r + 1'b1;
			end
		else
			App_wr_addr_r <= App_wr_addr_r;
		//
		if(App_wr_en_r && (burst_cnt + App_wr_en < burst_target))begin
            App_wr_en_d0 <= 1'b1;
        end
		else
			App_wr_en_d0 <= 1'b0;
	
	end		
end
always@(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		state <= S_IDLE;
		write_len_latch <= ZERO[ADDR_BITS - 1:0];
		write_remaining <= ZERO[ADDR_BITS - 1:0];
		line_width_latch <= 16'd0;
        burst_target <= {BURST_BITS{1'b0}};
        settle_count <= 5'd0;
		line_jump_latch <= ZERO[ADDR_BITS - 1:0];
		
		//wr_burst_addr <= ZERO[ADDR_BITS - 1:0];
		//wr_burst_req <= 1'b0;
		App_wr_en_r <= 1'b0;
		
		write_cnt <= ZERO[ADDR_BITS - 1:0];
		fifo_aclr <= 1'b0;
		write_req_ack <= 1'b0;
		//wr_burst_len <= ZERO[BURST_BITS - 1:0];
		
		
	end
	else 
		case(state)
			//idle state,waiting for write write_req_d2 == '1' goto the 'S_ACK'
			S_IDLE:
			begin
				if(write_req_d2 == 1'b1 && Sdr_init_done)
				begin
					state <= S_ACK;
				end
				write_req_ack <= 1'b0;
			end
			//'S_ACK' state completes the write request response, the FIFO reset, the address latch, and the data length latch
			S_ACK:
			begin
				//after write request revocation(write_req_d2 == '0'),goto 'S_CHECK_FIFO',write_req_ack goto '0'
				if(write_req_d2 == 1'b0)
				begin
					state <= S_CHECK_FIFO;
					fifo_aclr <= 1'b0;
					write_req_ack <= 1'b0;
				end
				else
				begin
					//write request response
					write_req_ack <= 1'b1;
					//FIFO reset
					fifo_aclr <= 1'b1;
					//select valid base address from write_addr_0 write_addr_1 write_addr_2 write_addr_3
					/*
					if(write_addr_index_d1 == 2'd0)
						wr_burst_addr <= write_addr_0;
					else if(write_addr_index_d1 == 2'd1)
						wr_burst_addr <= write_addr_1;
					else if(write_addr_index_d1 == 2'd2)
						wr_burst_addr <= write_addr_2;
					else if(write_addr_index_d1 == 2'd3)
						wr_burst_addr <= write_addr_3;
					*/
					//latch data length
					write_len_latch <= write_len_d1;                    
					write_remaining <= write_len_d1;
					line_width_latch <= line_width_d1;
                    burst_target <= (line_width_d1 == 16'd80) ? 10'd80 : 10'd256;
					line_jump_latch <= line_jump_d1;
				end
				//write data counter reset, write_cnt <= 0;
				write_cnt <= ZERO[ADDR_BITS - 1:0];
			end
			S_CHECK_FIFO:
			begin
				//if there is a write request at this time, enter the 'S_ACK' state
				if(write_req_d2 == 1'b1)
				begin
					state <= S_ACK;
				end
				//if the FIFO space is a burst write request, goto burst write state
				else if(into_burst)
				begin
					state <= S_WRITE_BURST;

					//wr_burst_len <= BURST_SIZE[BURST_BITS - 1:0];
					//wr_burst_req <= 1'b1;
					App_wr_en_r <= 1'b1;
				end
			end 
			
			S_WRITE_BURST:
			begin
				//burst finish
				if(wr_burst_finish == 1'b1)
				begin
					App_wr_en_r <= 1'b0;
					state <= S_WRITE_BURST_END;
					//write counter + burst length
                    write_cnt <= write_cnt + burst_target;
                    write_remaining <= write_remaining - burst_target;
                    settle_count <= 5'd0;
					//the next burst write address is generated
					//wr_burst_addr <= wr_burst_addr + BURST_SIZE[ADDR_BITS - 1:0];
				end     
			end
			S_WRITE_BURST_END:
			begin
                // Give the SDRAM interface time to retire the row before
                // starting another burst at a discontinuous address.
                // Portrait rows are 320 words with a 512-word destination stride.
                // Split 256+64 so a live request never jumps at the row end
                // or crosses to a different SDRAM page. Background (1280)
                // and 80-word thumbnails retain their original requests.
                burst_target <= (line_width_latch == 16'd80) ? 9'd80 :
                    (line_width_latch == 16'd320 && wr_x == 16'd256) ? 9'd64 : 9'd256;
                if (settle_count < 5'd10) settle_count <= settle_count + 5'd1;
                else if (write_req_d2) state <= S_ACK;
                else if (write_cnt < write_len_latch) state <= S_CHECK_FIFO;
                else state <= S_END;
			end
			S_END:
			begin
				state <= S_IDLE;
			end
			default:
				state <= S_IDLE;
		endcase
end
endmodule
