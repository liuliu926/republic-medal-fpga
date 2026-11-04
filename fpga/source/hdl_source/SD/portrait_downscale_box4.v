// 320x400 bottom-up RGB pixels -> 80x100 bottom-up RGB pixels.
// Preserve the full 4:5 portrait aspect ratio and average each 4x4 block.
// The previous 64x100 window cropped the sides of the face and made the
// portrait look narrow; the 80x100 result fits the source without cropping.
module portrait_downscale_box4 (
    input              clk,
    input              rst,
    input              start,
    output reg         input_ready,
    input              pixel_valid,
    input      [23:0]  pixel_data,
    output reg         out_valid,
    output reg [23:0]  out_pixel,
    output reg         done
);

reg [8:0] src_x;
reg [8:0] src_y;
reg [9:0] h_r, h_g, h_b;
reg [11:0] v_r [0:79];
reg [11:0] v_g [0:79];
reg [11:0] v_b [0:79];

wire group_end = (src_x[1:0] == 2'b11);
wire [6:0] group_index = src_x[8:2];
wire [11:0] h_total_r = {2'b00, h_r} + {4'b0000, pixel_data[23:16]};
wire [11:0] h_total_g = {2'b00, h_g} + {4'b0000, pixel_data[15:8]};
wire [11:0] h_total_b = {2'b00, h_b} + {4'b0000, pixel_data[7:0]};
wire [11:0] block_total_r = v_r[group_index] + h_total_r;
wire [11:0] block_total_g = v_g[group_index] + h_total_g;
wire [11:0] block_total_b = v_b[group_index] + h_total_b;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        src_x <= 9'd0;
        src_y <= 9'd0;
        h_r <= 10'd0;
        h_g <= 10'd0;
        h_b <= 10'd0;
        input_ready <= 1'b0;
        out_valid <= 1'b0;
        out_pixel <= 24'd0;
        done <= 1'b0;
    end else begin
        out_valid <= 1'b0;
        done <= 1'b0;
        if (start) begin
            src_x <= 9'd0;
            src_y <= 9'd0;
            h_r <= 10'd0;
            h_g <= 10'd0;
            h_b <= 10'd0;
            input_ready <= 1'b1;
        end else if (pixel_valid && input_ready) begin
            if (src_x[1:0] == 2'b00) begin
                h_r <= {2'b00, pixel_data[23:16]};
                h_g <= {2'b00, pixel_data[15:8]};
                h_b <= {2'b00, pixel_data[7:0]};
            end else if (!group_end) begin
                h_r <= h_r + {2'b00, pixel_data[23:16]};
                h_g <= h_g + {2'b00, pixel_data[15:8]};
                h_b <= h_b + {2'b00, pixel_data[7:0]};
            end else if (src_y[1:0] == 2'b00) begin
                v_r[group_index] <= h_total_r;
                v_g[group_index] <= h_total_g;
                v_b[group_index] <= h_total_b;
            end else if (src_y[1:0] == 2'b11) begin
                out_valid <= 1'b1;
                out_pixel <= {block_total_r[11:4],
                              block_total_g[11:4],
                              block_total_b[11:4]};
            end else begin
                v_r[group_index] <= block_total_r;
                v_g[group_index] <= block_total_g;
                v_b[group_index] <= block_total_b;
            end
            if (src_x == 9'd319) begin
                src_x <= 9'd0;
                if (src_y == 9'd399) begin
                    input_ready <= 1'b0;
                    done <= 1'b1;
                end else begin
                    src_y <= src_y + 9'd1;
                end
            end else begin
                src_x <= src_x + 9'd1;
            end
        end
    end
end

endmodule
