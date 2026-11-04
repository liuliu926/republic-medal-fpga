`timescale 1ns/1ps
// Packs the opening file into the EXISTING GUI frame_read_write input FIFO.
// No storage/FIFO/memory controller is instantiated here.
// All ports are in clk, including the already-synchronized writer status.
// Parent holds start until done/error handling has drained the raw transaction.
// Parent may lower start only after it has made the shared writer safe to reset
// or re-request; lowering start is a local reset, not a physical writer abort.
module opening_stream_preload #(
    parameter integer EXPECTED_BYTES = 6480896,
    parameter integer PADDED_WORDS = 1620224,
    parameter integer SETTLE_CYCLES = 8
)(
    input wire clk,
    input wire rst,
    input wire start,
    input wire raw_active,
    input wire raw_done,
    input wire [7:0] raw_error,
    input wire raw_valid,
    input wire [7:0] raw_data,
    output wire raw_ready,
    output wire raw_start,
    output wire write_req,
    input wire write_ack,
    input wire write_finish,
    input wire fifo_full,
    output wire write_en,
    output wire [31:0] write_data,
    output wire done,
    output reg [7:0] error,
    output reg [20:0] word_count
);
    localparam [3:0] S_IDLE=0, S_REQ=1, S_ACK_LOW=2, S_SETTLE=3,
                     S_RAW_REQ=4, S_STREAM=5, S_TAIL=6, S_COMMIT=7,
                     S_DONE=8, S_DRAIN=9, S_ERROR=10;
    localparam [7:0] E_SHORT=8'he1, E_LONG=8'he2,
                     E_WORDS=8'he3, E_CONFIG=8'he4;
    reg [3:0] state;
    reg [3:0] settle_count;
    reg [1:0] byte_index;
    reg [23:0] packed_low;
    reg [23:0] byte_count;
    reg finish_seen;

    assign write_req = start && state == S_REQ;
    assign raw_start = start && state == S_RAW_REQ;
    // In TAIL, accepting any extra byte is an overlength error. In DRAIN the
    // parent/frontend must be allowed to release the shared SD interface.
    assign raw_ready = start && ((state == S_STREAM && !fifo_full) ||
                                 state == S_TAIL || state == S_COMMIT || state == S_DRAIN);
    wire take = raw_valid && raw_ready;
    // This strobe and data go straight into the existing synchronous write
    // port. They are sampled on the same edge as the fourth byte handshake,
    // so there is no pending registered word that could collide with full.
    assign write_en = start && state == S_STREAM && raw_error == 0 && take && byte_index == 2'd3;
    assign write_data = {raw_data, packed_low};
    assign done = start && state == S_DONE;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            settle_count <= 0;
            byte_index <= 0;
            packed_low <= 0;
            byte_count <= 0;
            word_count <= 0;
            finish_seen <= 0;
            error <= 0;
        end else if (!start) begin
            state <= S_IDLE;
            settle_count <= 0;
            byte_index <= 0;
            packed_low <= 0;
            byte_count <= 0;
            word_count <= 0;
            finish_seen <= 0;
            error <= 0;
        end else begin
            // Physical finish may precede raw_done by a few stream clocks.
            // It is accepted only after the exact number of words is queued.
            if ((state == S_TAIL || state == S_COMMIT) &&
                word_count == PADDED_WORDS && write_finish)
                finish_seen <= 1'b1;

            // Raw frontend errors preserve their code, then drain its stream.
            if (raw_error != 0 && state >= S_RAW_REQ && state <= S_COMMIT) begin
                error <= raw_error;
                state <= S_DRAIN;
            end else begin
                case (state)
                    S_IDLE: begin
                        if (EXPECTED_BYTES <= 0 || EXPECTED_BYTES >= 16777216 ||
                            (EXPECTED_BYTES % 4) != 0 || PADDED_WORDS != EXPECTED_BYTES / 4 ||
                            SETTLE_CYCLES < 1 || SETTLE_CYCLES > 16) begin
                            error <= E_CONFIG;
                            state <= S_ERROR;
                        end else state <= S_REQ;
                    end
                    S_REQ: if (write_ack) state <= S_ACK_LOW;
                    S_ACK_LOW: if (!write_ack) begin
                        settle_count <= 0;
                        state <= S_SETTLE;
                    end
                    S_SETTLE: begin
                        // ACK implies the actual writer is clearing its FIFO.
                        // Restart the settling interval if ACK returns high.
                        if (write_ack) settle_count <= 0;
                        else if (settle_count == SETTLE_CYCLES-1) state <= S_RAW_REQ;
                        else settle_count <= settle_count + 1'b1;
                    end
                    S_RAW_REQ: begin
                        if (raw_active) state <= S_STREAM;
                        else if (raw_done) begin
                            error <= E_SHORT;
                            state <= S_DRAIN;
                        end
                    end
                    S_STREAM: begin
                        if (take) begin
                            byte_count <= byte_count + 1'b1;
                            byte_index <= byte_index + 1'b1;
                            case (byte_index)
                                0: packed_low[7:0] <= raw_data;
                                1: packed_low[15:8] <= raw_data;
                                2: packed_low[23:16] <= raw_data;
                                3: word_count <= word_count + 1'b1;
                            endcase
                            if (byte_count == EXPECTED_BYTES-1) state <= S_TAIL;
                        end
                        if (raw_done) begin
                            // Account for a final byte and done on one edge.
                            if (byte_count + (take ? 24'd1 : 24'd0) != EXPECTED_BYTES) begin
                                error <= E_SHORT;
                                state <= S_DRAIN;
                            end else state <= S_COMMIT;
                        end
                    end
                    S_TAIL: begin
                        if (take) begin
                            error <= E_LONG;
                            state <= S_DRAIN;
                        end else if (raw_done) state <= S_COMMIT;
                    end
                    S_COMMIT: begin
                        if (take) begin
                            error <= E_LONG;
                            state <= S_DRAIN;
                        end else if (word_count != PADDED_WORDS) begin
                            error <= E_WORDS;
                            state <= S_DRAIN;
                        end else if (finish_seen || write_finish) state <= S_DONE;
                    end
                    S_DONE: state <= S_DONE;
                    S_DRAIN: if (raw_done || !raw_active) state <= S_ERROR;
                    S_ERROR: state <= S_ERROR;
                    default: begin
                        error <= E_CONFIG;
                        state <= S_DRAIN;
                    end
                endcase
            end
        end
    end
endmodule
