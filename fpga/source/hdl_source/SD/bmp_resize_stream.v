// Resize one bottom-up 24-bit BMP pixel stream into an output frame.
// The SD reader supplies complete source rows.  Two line memories let the
// next row arrive while the previous row is being sampled.  Aspect ratio is
// preserved; pixels outside the fitted rectangle are black. BOX_TOP is the
// displayed top coordinate; frame_fifo_write later flips the BMP row order.
module bmp_resize_stream #(
    parameter integer ENABLE_OUTPUT_BACKPRESSURE = 0,
    parameter integer OUT_WIDTH = 640,
    parameter integer OUT_HEIGHT = 480,
    parameter integer BOX_LEFT = 0,
    parameter integer BOX_TOP = 0,
    parameter integer BOX_WIDTH = OUT_WIDTH,
    parameter integer BOX_HEIGHT = OUT_HEIGHT
) (
    input               clk,
    input               rst,
    input               start,
    input      [15:0]   source_width,
    input      [15:0]   source_height,
    output reg          input_ready,
    output wire         pixel_ready,
    input               pixel_valid,
    input      [23:0]   pixel_data,
    output reg          out_valid,
    input               out_ready,
    output reg [23:0]   out_pixel,
    output reg          done
);

localparam ST_IDLE       = 4'd0;
localparam ST_DIVIDE     = 4'd1;
localparam ST_PICK       = 4'd2;
localparam ST_BLACK      = 4'd3;
localparam ST_WAIT_ROW   = 4'd4;
localparam ST_FETCH      = 4'd5;
localparam ST_FETCH_WAIT = 4'd6;
localparam ST_EMIT       = 4'd7;
localparam ST_STEP       = 4'd8;
localparam ST_X_ADV      = 4'd9;
localparam ST_Y_ADV      = 4'd10;
localparam ST_DONE       = 4'd11;
localparam ST_PREP       = 4'd12;
localparam ST_OUTPUT_HOLD= 4'd13;
localparam integer BOX_STREAM_TOP = OUT_HEIGHT - BOX_TOP - BOX_HEIGHT;

reg [3:0]  state;
reg [15:0] src_w, src_h;
reg        width_limited;
reg [31:0] quotient_remainder;
reg [31:0] width_product, height_product;
reg [15:0] divisor;
reg [10:0] quotient;
wire [10:0] fitted_quotient = (quotient == 0) ? 11'd1 : quotient;
reg [10:0] box_w, box_h;
reg [10:0] pad_x, pad_y;

// PPT assets reach 1440 source pixels; 1536 entries leave safe headroom.
reg [23:0] line0 [0:1535];
reg [23:0] line1 [0:1535];
reg [23:0] sample0, sample1;
reg        producer_bank;
reg [10:0] producer_x;
reg [15:0] producer_y;
reg [15:0] line0_number, line1_number;
reg        read_bank;

reg [10:0] dst_x, dst_y;
reg [15:0] need_source_y;
reg [15:0] need_source_x;
reg [15:0] x_remainder, y_remainder;
wire output_accept = ENABLE_OUTPUT_BACKPRESSURE ? out_ready : 1'b1;

wire image_row = (dst_y >= pad_y) && (dst_y < pad_y + box_h);
wire image_col = (dst_x >= pad_x) && (dst_x < pad_x + box_w);
wire producer_bank_free = producer_bank
    ? ((line1_number == 16'hFFFF) || (line1_number < need_source_y))
    : ((line0_number == 16'hFFFF) || (line0_number < need_source_y));

// `input_ready` remains the legacy startup-ready indication used by bmp_read.
// New byte-stream loaders should use `pixel_ready` to avoid overwriting a line
// buffer while the scaler still needs that source row.
assign pixel_ready = input_ready && ((producer_x != 11'd0) || producer_bank_free);

// Synchronous line-memory reads are intentional: this maps to on-chip RAM.
always @(posedge clk) begin
    // The decoder holds pixel_valid while backpressured.  Only advance the
    // producer and write a source pixel on the actual valid/ready handshake;
    // otherwise a stalled pixel would be duplicated in the line RAM.
    if (pixel_valid && pixel_ready && producer_y < src_h) begin
        if (producer_bank == 1'b0)
            line0[producer_x] <= pixel_data;
        else
            line1[producer_x] <= pixel_data;
    end
    sample0 <= line0[need_source_x[10:0]];
    sample1 <= line1[need_source_x[10:0]];
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        producer_bank <= 1'b0;
        producer_x <= 11'd0;
        producer_y <= 16'd0;
        line0_number <= 16'hFFFF;
        line1_number <= 16'hFFFF;
    end else if (start) begin
        producer_bank <= 1'b0;
        producer_x <= 11'd0;
        producer_y <= 16'd0;
        line0_number <= 16'hFFFF;
        line1_number <= 16'hFFFF;
    end else if (pixel_valid && pixel_ready && producer_y < src_h) begin
        if (producer_x == src_w - 16'd1) begin
            producer_x <= 11'd0;
            if (producer_bank == 1'b0)
                line0_number <= producer_y;
            else
                line1_number <= producer_y;
            producer_bank <= ~producer_bank;
            producer_y <= producer_y + 16'd1;
        end else begin
            producer_x <= producer_x + 11'd1;
        end
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= ST_IDLE;
        src_w <= 16'd0;
        src_h <= 16'd0;
        width_limited <= 1'b0;
        quotient_remainder <= 32'd0;
        width_product <= 32'd0;
        height_product <= 32'd0;
        divisor <= 16'd1;
        quotient <= 11'd0;
        box_w <= 11'd0;
        box_h <= 11'd0;
        pad_x <= 11'd0;
        pad_y <= 11'd0;
        dst_x <= 11'd0;
        dst_y <= 11'd0;
        need_source_x <= 16'd0;
        need_source_y <= 16'd0;
        x_remainder <= 16'd0;
        y_remainder <= 16'd0;
        read_bank <= 1'b0;
        input_ready <= 1'b0;
        out_valid <= 1'b0;
        out_pixel <= 24'd0;
        done <= 1'b0;
    end else begin
        if (!out_valid || output_accept)
            out_valid <= 1'b0;
        done <= 1'b0;
        if (start) begin
            src_w <= source_width;
            src_h <= source_height;
            width_product <= source_width * BOX_HEIGHT;
            height_product <= source_height * BOX_WIDTH;
            quotient <= 11'd0;
            dst_x <= 11'd0;
            dst_y <= 11'd0;
            need_source_x <= 16'd0;
            need_source_y <= 16'd0;
            x_remainder <= 16'd0;
            y_remainder <= 16'd0;
            input_ready <= 1'b0;
            state <= ST_PREP;
        end else begin
            case (state)
                ST_IDLE: ;
                ST_PREP: begin
                    width_limited <= (width_product >= height_product);
                    quotient_remainder <= (width_product >= height_product)
                        ? height_product : width_product;
                    divisor <= (width_product >= height_product) ? src_w : src_h;
                    state <= ST_DIVIDE;
                end
                // The quotient is at most the selected output dimension.
                // Repeated subtraction costs
                // only startup cycles, rather than a large variable divider.
                ST_DIVIDE: begin
                    if (quotient_remainder >= divisor) begin
                        quotient_remainder <= quotient_remainder - divisor;
                        quotient <= quotient + 11'd1;
                    end else begin
                        if (width_limited) begin
                            box_w <= BOX_WIDTH;
                            box_h <= fitted_quotient;
                            pad_x <= BOX_LEFT;
                            pad_y <= BOX_STREAM_TOP + ((BOX_HEIGHT - fitted_quotient) >> 1);
                        end else begin
                            box_w <= fitted_quotient;
                            box_h <= BOX_HEIGHT;
                            pad_x <= BOX_LEFT + ((BOX_WIDTH - fitted_quotient) >> 1);
                            pad_y <= BOX_STREAM_TOP;
                        end
                        state <= ST_PICK;
                    end
                end
                ST_PICK: begin
                    if (dst_y == OUT_HEIGHT) begin
                        done <= 1'b1;
                        state <= ST_DONE;
                    end else begin
                        if (dst_y >= pad_y)
                            input_ready <= 1'b1;
                        if (!image_row || !image_col)
                            state <= ST_BLACK;
                        else
                            state <= ST_WAIT_ROW;
                    end
                end
                ST_BLACK: begin
                    out_valid <= 1'b1;
                    out_pixel <= 24'd0;
                    state <= ST_OUTPUT_HOLD;
                end
                ST_WAIT_ROW: begin
                    if (line0_number == need_source_y) begin
                        read_bank <= 1'b0;
                        state <= ST_FETCH;
                    end else if (line1_number == need_source_y) begin
                        read_bank <= 1'b1;
                        state <= ST_FETCH;
                    end
                end
                ST_FETCH: state <= ST_FETCH_WAIT;
                ST_FETCH_WAIT: state <= ST_EMIT;
                ST_EMIT: begin
                    out_valid <= 1'b1;
                    out_pixel <= read_bank ? sample1 : sample0;
                    state <= ST_OUTPUT_HOLD;
                end
                ST_OUTPUT_HOLD: begin
                    if (output_accept)
                        state <= ST_STEP;
                end
                ST_STEP: begin
                    if (dst_x == OUT_WIDTH - 1) begin
                        dst_x <= 11'd0;
                        dst_y <= dst_y + 11'd1;
                        need_source_x <= 16'd0;
                        x_remainder <= 16'd0;
                        if (image_row) begin
                            y_remainder <= y_remainder + src_h;
                            state <= ST_Y_ADV;
                        end else begin
                            state <= ST_PICK;
                        end
                    end else begin
                        dst_x <= dst_x + 11'd1;
                        if (image_row && image_col && dst_x + 11'd1 < pad_x + box_w) begin
                            x_remainder <= x_remainder + src_w;
                            state <= ST_X_ADV;
                        end else begin
                            state <= ST_PICK;
                        end
                    end
                end
                ST_X_ADV: begin
                    if (x_remainder >= box_w) begin
                        x_remainder <= x_remainder - box_w;
                        need_source_x <= need_source_x + 16'd1;
                    end else begin
                        state <= ST_PICK;
                    end
                end
                ST_Y_ADV: begin
                    if (y_remainder >= box_h) begin
                        y_remainder <= y_remainder - box_h;
                        need_source_y <= need_source_y + 16'd1;
                    end else begin
                        state <= ST_PICK;
                    end
                end
                ST_DONE: ;
                default: state <= ST_IDLE;
            endcase
        end
    end
end

endmodule
