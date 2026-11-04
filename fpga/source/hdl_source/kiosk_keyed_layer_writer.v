// Turn a pre-sized bottom-up BMP layer into sparse framebuffer writes.
// Transparent magenta pixels are consumed without a write, retaining the
// existing background. Always draw into a non-visible frame buffer.
// The write interface requires a random-address-capable memory arbiter; it is
// NOT directly compatible with the existing contiguous frame FIFO writer.
// done only means all pixels were accepted, not that downstream memory has
// drained. The page compositor must wait for the memory completion signal.
module kiosk_keyed_layer_writer #(
    parameter integer SCREEN_WIDTH=1280,
    parameter integer SCREEN_HEIGHT=720,
    parameter integer ADDR_BITS=21,
    parameter [23:0] TRANSPARENT=24'hff00ff
)(
    input wire clk, input wire rst,
    input wire start, input wire [ADDR_BITS-1:0] frame_base,
    input wire [10:0] dest_x, input wire [9:0] dest_y,
    input wire [10:0] image_width, input wire [9:0] image_height,
    input wire pixel_valid, output wire pixel_ready, input wire [23:0] pixel_rgb,
    input wire source_error, input wire source_done,
    output wire write_valid, input wire write_ready,
    output wire [ADDR_BITS-1:0] write_addr, output wire [31:0] write_data,
    output reg busy, output reg done, output reg error
);
    reg [10:0] width_q, x_q;
    reg [9:0] height_q, y_q;
    reg [ADDR_BITS-1:0] row_addr;
    wire [11:0] x_end={1'b0,dest_x}+{1'b0,image_width};
    wire [10:0] y_end={1'b0,dest_y}+{1'b0,image_height};
    wire [ADDR_BITS:0] last_frame_addr={1'b0,frame_base}+SCREEN_WIDTH*SCREEN_HEIGHT-1;
    wire transparent_pixel=(pixel_rgb==TRANSPARENT);
    wire last_pixel_now=pixel_valid && pixel_ready && (x_q==width_q-1) && (y_q==height_q-1);
    assign write_valid=busy && !source_error && pixel_valid && !transparent_pixel;
    assign pixel_ready=busy && !source_error && (transparent_pixel || write_ready);
    assign write_addr=row_addr+x_q;
    assign write_data={pixel_rgb,8'h00};
    always @(posedge clk) begin
        if(rst) begin
            width_q<=0; height_q<=0; x_q<=0; y_q<=0; row_addr<=0;
            busy<=0; done<=0; error<=0;
        end else begin
            done<=0;
            if(start && !busy) begin
                error<=0;
                if(image_width==0 || image_height==0 || x_end>SCREEN_WIDTH ||
                   y_end>SCREEN_HEIGHT || last_frame_addr[ADDR_BITS]) begin
                    error<=1; done<=1;
                end else begin
                    width_q<=image_width; height_q<=image_height; x_q<=0; y_q<=0;
                    row_addr<=frame_base+(dest_y+image_height-1)*SCREEN_WIDTH+dest_x;
                    busy<=1;
                end
            end else if(busy && (source_error || (source_done && !last_pixel_now))) begin
                busy<=0; done<=1; error<=1;
            end else if(pixel_valid && pixel_ready) begin
                if(x_q==width_q-1) begin
                    x_q<=0;
                    if(y_q==height_q-1) begin busy<=0;done<=1;end
                    else begin y_q<=y_q+1'b1;row_addr<=row_addr-SCREEN_WIDTH;end
                end else x_q<=x_q+1'b1;
            end
        end
    end
endmodule
