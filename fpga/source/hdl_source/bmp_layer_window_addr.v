// Convert a current HDMI pixel position into a row-major address inside a
// pre-scaled BMP layer held in SDRAM. The layer can be any size and is clipped
// to its destination rectangle; layer_row_stride is the stored image width.
//
// The layer reader must return the addressed RGB pixel on a later cycle. Delay
// the background RGB and pixel_active signal by the same memory-read latency
// before passing them to rgb_keyed_overlay_blend.
module bmp_layer_window_addr (
    input  wire        pixel_active,
    input  wire [10:0] pixel_x,
    input  wire [9:0]  pixel_y,
    input  wire [10:0] layer_x,
    input  wire [9:0]  layer_y,
    input  wire [10:0] layer_width,
    input  wire [9:0]  layer_height,
    input  wire [10:0] layer_row_stride,
    output wire        layer_read_req,
    output wire [19:0] layer_pixel_addr,
    output wire [10:0] local_x,
    output wire [9:0]  local_y
);

wire [11:0] layer_x_end = {1'b0, layer_x} + {1'b0, layer_width};
wire [10:0] layer_y_end = {1'b0, layer_y} + {1'b0, layer_height};

assign layer_read_req = pixel_active &&
    (layer_width != 11'd0) && (layer_height != 10'd0) &&
    (pixel_x >= layer_x) && ({1'b0, pixel_x} < layer_x_end) &&
    (pixel_y >= layer_y) && ({1'b0, pixel_y} < layer_y_end);

assign local_x = layer_read_req ? pixel_x - layer_x : 11'd0;
assign local_y = layer_read_req ? pixel_y - layer_y : 10'd0;
assign layer_pixel_addr = layer_read_req
    ? (local_y * layer_row_stride + local_x)
    : 20'd0;

endmodule
