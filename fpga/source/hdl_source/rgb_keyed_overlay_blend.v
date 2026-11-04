// Pixel combiner for a full-colour background and a magenta-keyed BMP layer.
//
// This block expects the background and overlay pixels to be aligned to the
// same video pixel. A separate layer fetcher must provide overlay_rgb and
// overlay_valid for the current pixel. The 4-bit alpha input is frame-level
// state controlled by the UI; 0 keeps the background and 15 shows the layer.
// The magenta key is always transparent, independent of alpha.
module rgb_keyed_overlay_blend #(
    parameter [23:0] KEY_RGB = 24'hFF00FF
) (
    input  wire        pixel_valid,
    input  wire [23:0] background_rgb,
    input  wire        layer_enable,
    input  wire        overlay_valid,
    input  wire [23:0] overlay_rgb,
    input  wire [3:0]  alpha,
    output wire        output_valid,
    output reg  [23:0] output_rgb
);

wire use_overlay = layer_enable && overlay_valid && (overlay_rgb != KEY_RGB);

function [7:0] blend_channel;
    input [7:0] background;
    input [7:0] foreground;
    input [3:0] opacity;
    reg [4:0] background_weight;
    reg [12:0] weighted_sum;
    begin
        // Weights sum to 16. The full-opacity case is handled separately so
        // alpha=15 produces the exact foreground value, not a 15/16 blend.
        background_weight = 5'd16 - {1'b0, opacity};
        weighted_sum = background * background_weight + foreground * opacity + 13'd8;
        blend_channel = weighted_sum[11:4];
    end
endfunction

assign output_valid = pixel_valid;

always @* begin
    if (!pixel_valid) begin
        output_rgb = 24'd0;
    end else if (!use_overlay || (alpha == 4'd0)) begin
        output_rgb = background_rgb;
    end else if (alpha == 4'd15) begin
        output_rgb = overlay_rgb;
    end else begin
        output_rgb[23:16] = blend_channel(background_rgb[23:16], overlay_rgb[23:16], alpha);
        output_rgb[15:8]  = blend_channel(background_rgb[15:8],  overlay_rgb[15:8],  alpha);
        output_rgb[7:0]   = blend_channel(background_rgb[7:0],   overlay_rgb[7:0],   alpha);
    end
end

endmodule
