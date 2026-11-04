`timescale 1ns/1ps

// Transfers frame_read_write status from mem_clk into the SD/scaler/write-FIFO
// clock domain. write_req_ack is a held level handshake; write_finish is a
// one-cycle pulse and therefore crosses as a toggle event.
module frame_write_status_cdc (
    input  wire stream_clk,
    input  wire mem_clk,
    input  wire rst,
    input  wire write_req_ack_mem,
    input  wire write_finish_mem,
    output wire write_req_ack_stream,
    output wire write_finish_pulse_stream
);

    reg write_req_ack_meta;
    reg write_req_ack_sync;
    reg write_finish_toggle_mem;
    reg [2:0] write_finish_toggle_sync;

    always @(posedge mem_clk or posedge rst) begin
        if (rst)
            write_finish_toggle_mem <= 1'b0;
        else if (write_finish_mem)
            write_finish_toggle_mem <= ~write_finish_toggle_mem;
    end

    always @(posedge stream_clk or posedge rst) begin
        if (rst) begin
            write_req_ack_meta       <= 1'b0;
            write_req_ack_sync       <= 1'b0;
            write_finish_toggle_sync <= 3'b000;
        end else begin
            write_req_ack_meta       <= write_req_ack_mem;
            write_req_ack_sync       <= write_req_ack_meta;
            write_finish_toggle_sync <= {write_finish_toggle_sync[1:0],
                                         write_finish_toggle_mem};
        end
    end

    assign write_req_ack_stream = write_req_ack_sync;
    assign write_finish_pulse_stream = write_finish_toggle_sync[2] ^
                                       write_finish_toggle_sync[1];

endmodule
