`timescale 1ns/1ps

// Writes a decoded bottom-up 24-bit BMP into a fixed-size SDRAM rectangle.
// The caller supplies a legal frame index and the first (bottom-left) pixel
// offset. The line jump uses the existing frame_fifo_write convention:
// next_row_start = current_row_last - line_jump (modulo ADDR_BITS).
// Pixel decoding is held at the BMP header until the SDRAM writer acknowledges
// the request, so no pixel is lost while the FIFO is being reset.
module fat32_asset_sdram_writer #(
    parameter integer ADDR_BITS = 21
)(
    input  wire                 clk,
    input  wire                 rst,
    input  wire                 start,
    input  wire [1:0]           target_frame_index,
    input  wire [ADDR_BITS-1:0] target_first_offset,
    input  wire [15:0]          target_width,
    input  wire [15:0]          target_height,
    input  wire [ADDR_BITS-1:0] target_length,
    input  wire [ADDR_BITS-1:0] target_line_jump,
    input  wire                 bmp_header_done,
    input  wire                 bmp_header_valid,
    input  wire [15:0]          bmp_width,
    input  wire [15:0]          bmp_height,
    input  wire                 bmp_pixel_valid,
    input  wire [23:0]          bmp_pixel_data,
    input  wire                 bmp_done,
    input  wire                 bmp_error,
    input  wire                 write_fifo_full,
    input  wire                 write_req_ack_stream,
    input  wire                 write_finish_stream,
    output wire                 bmp_pixel_enable,
    output wire                 bmp_pixel_ready,
    output wire                 write_req,
    output wire [1:0]           write_addr_index,
    output wire [ADDR_BITS-1:0] write_len,
    output wire [ADDR_BITS-1:0] write_first_offset,
    output wire [15:0]          write_line_width,
    output wire [ADDR_BITS-1:0] write_line_jump,
    output wire                 write_en,
    output wire [31:0]          write_data,
    output wire                 busy,
    output reg                  done,
    output reg                  error,
    output reg [2:0]            error_code,
    output reg [3:0]            debug_step
);
    localparam [2:0] ST_IDLE=3'd0, ST_HEADER=3'd1, ST_REQ=3'd2,
                     ST_PIXELS=3'd3, ST_DRAIN=3'd4, ST_FAIL=3'd5,
                     ST_DISCARD=3'd6, ST_FIFO_SETTLE=3'd7;
    reg [2:0] state;
    reg [1:0] frame_q;
    reg [ADDR_BITS-1:0] first_q, jump_q, length_q;
    reg [15:0] width_q, height_q;
    reg [ADDR_BITS-1:0] accepted;
    reg source_done_seen, write_done_seen;
    reg [3:0] settle_count;

    assign busy = state != ST_IDLE;
    assign bmp_pixel_enable = (state == ST_PIXELS) || (state == ST_DISCARD);
    assign bmp_pixel_ready = ((state == ST_PIXELS) && !write_fifo_full) ||
                             (state == ST_DISCARD);
    assign write_req = state == ST_REQ;
    assign write_addr_index = frame_q;
    assign write_len = length_q;
    assign write_first_offset = first_q;
    assign write_line_width = width_q;
    assign write_line_jump = jump_q;
    assign write_en = (state == ST_PIXELS) && bmp_pixel_valid && bmp_pixel_ready;
    // HDMI scanout consumes SDRAM bits [31:8] as RGB.
    assign write_data = {bmp_pixel_data, 8'd0};

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
            frame_q <= 2'd0;
            first_q <= {ADDR_BITS{1'b0}};
            jump_q <= {ADDR_BITS{1'b0}};
            length_q <= {ADDR_BITS{1'b0}};
            width_q <= 16'd0;
            height_q <= 16'd0;
            accepted <= {ADDR_BITS{1'b0}};
            source_done_seen <= 1'b0;
            write_done_seen <= 1'b0;
            settle_count <= 4'd0;
            done <= 1'b0;
            error <= 1'b0;
            error_code <= 3'd0;
            debug_step <= 4'd0;
        end else begin
            done <= 1'b0;
            error <= 1'b0;
            case (state)
                ST_IDLE: if (start) begin
                    debug_step <= 4'd1;
                    frame_q <= target_frame_index;
                    first_q <= target_first_offset;
                    jump_q <= target_line_jump;
                    width_q <= target_width;
                    height_q <= target_height;
                    length_q <= target_length;
                    accepted <= {ADDR_BITS{1'b0}};
                    source_done_seen <= 1'b0;
                    write_done_seen <= 1'b0;
                    settle_count <= 4'd0;
                    error_code <= 3'd0;
                    state <= ST_HEADER;
                end
                ST_HEADER: begin
                    if (bmp_error) begin
                        error <= 1'b1;
                        error_code <= 3'd1;
                        state <= ST_FAIL;
                    end else if (bmp_header_done) begin
                        debug_step <= 4'd2;
                        if (bmp_header_valid && bmp_width == width_q &&
                            bmp_height == height_q && width_q != 16'd0 &&
                            height_q != 16'd0)
                            state <= ST_REQ;
                        else begin
                            error <= 1'b1;
                            error_code <= 3'd2;
                            state <= ST_DISCARD;
                        end
                    end
                end
                ST_REQ: begin
                    if (bmp_error) begin
                        error <= 1'b1;
                        error_code <= 3'd3;
                        state <= ST_FAIL;
                    end else if (write_req_ack_stream)
                        begin
                        debug_step <= 4'd3;
                        settle_count <= 4'd0;
                        state <= ST_FIFO_SETTLE;
                        end
                end
                // The SDRAM writer keeps the async FIFO in reset while ACK is
                // held. Releasing pixels immediately on ACK loses the first
                // pixel, leaving the last partial burst one word short.
                ST_FIFO_SETTLE: begin
                    if (write_req_ack_stream)
                        settle_count <= 4'd0;
                    else if (settle_count == 4'd8)
                        state <= ST_PIXELS;
                    else
                        settle_count <= settle_count + 4'd1;
                end
                ST_PIXELS: begin
                    if (bmp_error) begin
                        error <= 1'b1;
                        error_code <= 3'd4;
                        state <= ST_FAIL;
                    end else if (write_en) begin
                        if (accepted == 0) debug_step <= 4'd4;
                        accepted <= accepted + {{(ADDR_BITS-1){1'b0}},1'b1};
                        if (accepted == length_q - {{(ADDR_BITS-1){1'b0}},1'b1}) begin
                            debug_step <= 4'd5;
                            state <= ST_DRAIN;
                        end
                    end
                    if (bmp_done) begin source_done_seen <= 1'b1; debug_step <= 4'd6; end
                    if (write_finish_stream) begin write_done_seen <= 1'b1; debug_step <= 4'd7; end
                end
                ST_DRAIN: begin
                    if (bmp_done) begin source_done_seen <= 1'b1; debug_step <= 4'd6; end
                    if (write_finish_stream) begin write_done_seen <= 1'b1; debug_step <= 4'd7; end
                    if (bmp_error) begin
                        error <= 1'b1;
                        error_code <= 3'd5;
                        state <= ST_FAIL;
                    end else if ((source_done_seen || bmp_done) &&
                                 (write_done_seen || write_finish_stream)) begin
                        debug_step <= 4'd8;
                        done <= 1'b1;
                        state <= ST_IDLE;
                    end
                end
                // An unexpected BMP size is a recoverable content error.
                // Drain its file so the shared SD owner can finish cleanly.
                ST_DISCARD: if (bmp_done || bmp_error) state <= ST_IDLE;
                ST_FAIL: state <= ST_IDLE;
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
