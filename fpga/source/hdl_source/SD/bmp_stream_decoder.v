`timescale 1ns/1ps

// Streaming decoder for uncompressed 24-bit Windows BMP files.
// The byte stream is little-endian BMP order (B, G, R), bottom-up rows.
// Pixel bytes are backpressured until the downstream scaler accepts each pixel.
module bmp_stream_decoder (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [31:0] file_size_bytes,

    input  wire        stream_valid,
    output reg         stream_ready,
    input  wire [7:0]  stream_data,

    input  wire        pixel_enable,
    output reg         header_done,
    output reg         header_valid,
    output reg  [15:0] source_width,
    output reg  [15:0] source_height,

    output reg         pixel_valid,
    input  wire        pixel_ready,
    output reg  [23:0] pixel_data,

    output reg         image_done,
    output reg         image_error
);

    localparam [2:0] ST_IDLE       = 3'd0;
    localparam [2:0] ST_HEADER     = 3'd1;
    localparam [2:0] ST_HEADER_EXT = 3'd2;
    localparam [2:0] ST_WAIT_PIXEL = 3'd3;
    localparam [2:0] ST_PIXELS     = 3'd4;
    localparam [2:0] ST_TRAILER    = 3'd5;
    localparam [2:0] ST_DONE       = 3'd6;
    localparam [2:0] ST_ERROR      = 3'd7;

    reg [2:0]  state;
    reg [31:0] stream_pos;
    reg [31:0] actual_file_size;

    reg [31:0] bmp_file_size;
    reg [31:0] pixel_offset;
    // Keep every relevant bit of valid dimensions. Nonzero discarded high
    // bits are latched separately, so malformed fields cannot alias valid ones.
    reg [10:0] width_field;
    reg [9:0] height_field;
    reg [12:0] dib_header_size;
    reg width_high_nonzero, height_high_nonzero, dib_high_nonzero;
    // These fields are used only for equality checks; validate each byte.
    reg [1:0] planes_bytes_valid, bpp_bytes_valid;
    reg compression_nonzero;

    reg [12:0] row_pixel_bytes;
    reg [12:0] row_stride_bytes;
    reg [12:0] row_byte_pos;
    reg [15:0] source_row;
    reg [1:0]  component_index;
    reg [15:0] pixel_bgr_low;

    // Fields are received by byte 33; header validation occurs at byte 53.
    // Pipeline the arithmetic while the remaining header bytes arrive so the
    // 100 MHz clock does not have to pass through two multipliers and a
    // wide addition/comparison in a single cycle.
    // Upper dimension bits are validated through the sticky reject flags.
    // An accepted width is at most 1440, hence RGB row bytes and four-byte
    // padded stride are at most 4320. Thirteen bits preserve both exactly.
    // Invalid dimensions remain rejected through low bits plus high flags;
    // these arithmetic pipeline values are consumed only at header byte 53.
    reg [12:0] width_times_three;
    reg [12:0] stride_rounded;
    // Bounds above constrain stride to 13 bits and height to 10 bits; keeping
    // this multiply narrow avoids inferring an unnecessary 32x32-bit unit.
    reg [22:0] raster_bytes;
    reg [32:0] required_file_bytes;
    reg [12:0] minimum_pixel_offset;
    reg header_fields_valid;
    always @(posedge clk) begin
        width_times_three <= ({2'd0, width_field[10:0]} << 1) +
                             {2'd0, width_field[10:0]};
        stride_rounded <= (width_times_three + 13'd3) & 13'h1ffc;
        raster_bytes <= {10'd0, stride_rounded[12:0]} * {13'd0, height_field[9:0]};
        required_file_bytes <= {1'b0, pixel_offset} + {10'd0, raster_bytes};
        minimum_pixel_offset <= 13'd14 + dib_header_size;
        header_fields_valid <=
        (bmp_file_size > pixel_offset) &&
        (bmp_file_size <= actual_file_size) &&
        !dib_high_nonzero &&
        (dib_header_size >= 13'd40) && (dib_header_size <= 13'd4096) &&
        ({1'b0, pixel_offset} >= {20'd0, minimum_pixel_offset}) &&
        (&planes_bytes_valid) &&
        !width_high_nonzero &&
        (width_field >= 11'd1) && (width_field <= 11'd1440) &&
        !height_high_nonzero &&
        (height_field >= 10'd1) && (height_field <= 10'd810) &&
        (&bpp_bytes_valid) && !compression_nonzero &&
        // width_field <= 1440 above guarantees stride <= 4320.
        (required_file_bytes <= {1'b0, bmp_file_size});
    end

    always @* begin
        stream_ready = 1'b0;
        case (state)
            ST_HEADER,
            ST_HEADER_EXT: stream_ready = 1'b1;
            ST_PIXELS:     stream_ready = pixel_enable && !pixel_valid;
            ST_TRAILER:    stream_ready = !pixel_valid;
            default:       stream_ready = 1'b0;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= ST_IDLE;
            stream_pos         <= 32'd0;
            actual_file_size   <= 32'd0;
            bmp_file_size      <= 32'd0;
            pixel_offset       <= 32'd0;
            width_field        <= 11'd0;
            height_field       <= 10'd0;
            dib_header_size    <= 13'd0;
            width_high_nonzero <= 1'b0;
            height_high_nonzero <= 1'b0;
            dib_high_nonzero <= 1'b0;
            planes_bytes_valid <= 2'b00;
            bpp_bytes_valid <= 2'b00;
            compression_nonzero <= 1'b0;
            row_pixel_bytes    <= 13'd0;
            row_stride_bytes   <= 13'd0;
            row_byte_pos       <= 13'd0;
            source_row         <= 16'd0;
            component_index    <= 2'd0;
            pixel_bgr_low      <= 16'd0;
            header_done        <= 1'b0;
            header_valid       <= 1'b0;
            source_width       <= 16'd0;
            source_height      <= 16'd0;
            pixel_valid        <= 1'b0;
            pixel_data         <= 24'd0;
            image_done         <= 1'b0;
            image_error        <= 1'b0;
        end else begin
            header_done <= 1'b0;
            image_done  <= 1'b0;

            if (pixel_valid && pixel_ready)
                pixel_valid <= 1'b0;

            if ((state == ST_IDLE) && start) begin
                stream_pos       <= 32'd0;
                actual_file_size <= file_size_bytes;
                bmp_file_size    <= 32'd0;
                pixel_offset     <= 32'd0;
                width_field      <= 11'd0;
                height_field     <= 10'd0;
                dib_header_size  <= 13'd0;
                width_high_nonzero <= 1'b0;
                height_high_nonzero <= 1'b0;
                dib_high_nonzero <= 1'b0;
                planes_bytes_valid <= 2'b00;
                bpp_bytes_valid <= 2'b00;
                compression_nonzero <= 1'b0;
                row_pixel_bytes  <= 13'd0;
                row_stride_bytes <= 13'd0;
                row_byte_pos     <= 13'd0;
                source_row       <= 16'd0;
                component_index  <= 2'd0;
                pixel_bgr_low    <= 16'd0;
                header_done      <= 1'b0;
                header_valid     <= 1'b0;
                source_width     <= 16'd0;
                source_height    <= 16'd0;
                pixel_valid      <= 1'b0;
                image_error      <= 1'b0;
                if (file_size_bytes >= 32'd54)
                    state <= ST_HEADER;
                else begin
                    image_error <= 1'b1;
                    state <= ST_ERROR;
                end
            end else if (stream_valid && stream_ready) begin
                stream_pos <= stream_pos + 32'd1;

                case (state)
                    ST_HEADER: begin
                        case (stream_pos)
                            32'd0: if (stream_data != 8'h42) begin image_error <= 1'b1; state <= ST_ERROR; end
                            32'd1: if (stream_data != 8'h4d) begin image_error <= 1'b1; state <= ST_ERROR; end
                            32'd2: bmp_file_size[7:0]   <= stream_data;
                            32'd3: bmp_file_size[15:8]  <= stream_data;
                            32'd4: bmp_file_size[23:16] <= stream_data;
                            32'd5: bmp_file_size[31:24] <= stream_data;
                            32'd10: pixel_offset[7:0]   <= stream_data;
                            32'd11: pixel_offset[15:8]  <= stream_data;
                            32'd12: pixel_offset[23:16] <= stream_data;
                            32'd13: pixel_offset[31:24] <= stream_data;
                            32'd14: dib_header_size[7:0]   <= stream_data;
                            32'd15: begin
                                dib_header_size[12:8] <= stream_data[4:0];
                                dib_high_nonzero <= |stream_data[7:5];
                            end
                            32'd16, 32'd17: dib_high_nonzero <= dib_high_nonzero | (|stream_data);
                            32'd18: width_field[7:0]    <= stream_data;
                            32'd19: begin
                                width_field[10:8] <= stream_data[2:0];
                                width_high_nonzero <= |stream_data[7:3];
                            end
                            32'd20, 32'd21: width_high_nonzero <= width_high_nonzero | (|stream_data);
                            32'd22: height_field[7:0]   <= stream_data;
                            32'd23: begin
                                height_field[9:8] <= stream_data[1:0];
                                height_high_nonzero <= |stream_data[7:2];
                            end
                            32'd24, 32'd25: height_high_nonzero <= height_high_nonzero | (|stream_data);
                            32'd26: planes_bytes_valid[0] <= (stream_data == 8'd1);
                            32'd27: planes_bytes_valid[1] <= (stream_data == 8'd0);
                            32'd28: bpp_bytes_valid[0] <= (stream_data == 8'd24);
                            32'd29: bpp_bytes_valid[1] <= (stream_data == 8'd0);
                            32'd30, 32'd31, 32'd32, 32'd33:
                                compression_nonzero <= compression_nonzero | (|stream_data);
                            default: begin end
                        endcase

                        if (stream_pos == 32'd53) begin
                            if (header_fields_valid) begin
                                source_width      <= {5'd0, width_field};
                                source_height     <= {6'd0, height_field};
                                row_pixel_bytes   <= width_times_three[12:0];
                                row_stride_bytes  <= stride_rounded[12:0];
                                header_valid      <= 1'b1;
                                header_done       <= 1'b1;
                                if (pixel_offset == 32'd54)
                                    state <= ST_WAIT_PIXEL;
                                else
                                    state <= ST_HEADER_EXT;
                            end else begin
                                image_error <= 1'b1;
                                state <= ST_ERROR;
                            end
                        end
                    end

                    ST_HEADER_EXT: begin
                        if ((stream_pos + 32'd1) >= pixel_offset)
                            state <= ST_WAIT_PIXEL;
                    end

                    ST_WAIT_PIXEL: begin
                        // This state cannot accept bytes. Kept for defensive completeness.
                    end

                    ST_PIXELS: begin
                        if (row_byte_pos < row_pixel_bytes) begin
                            case (component_index)
                                2'd0: begin
                                    pixel_bgr_low[7:0] <= stream_data;
                                    component_index <= 2'd1;
                                end
                                2'd1: begin
                                    pixel_bgr_low[15:8] <= stream_data;
                                    component_index <= 2'd2;
                                end
                                default: begin
                                    pixel_data  <= {stream_data, pixel_bgr_low};
                                    pixel_valid <= 1'b1;
                                    component_index <= 2'd0;
                                end
                            endcase
                        end

                        if (row_byte_pos == (row_stride_bytes - 13'd1)) begin
                            row_byte_pos <= 13'd0;
                            if (source_row == (source_height - 16'd1)) begin
                                state <= ST_TRAILER;
                            end else begin
                                source_row <= source_row + 16'd1;
                            end
                        end else begin
                            row_byte_pos <= row_byte_pos + 13'd1;
                        end
                    end

                    ST_TRAILER: begin
                        if ((stream_pos + 32'd1) >= actual_file_size)
                            state <= ST_DONE;
                    end

                    default: begin end
                endcase

                // The FAT directory size is the authoritative stream boundary.
                if ((stream_pos + 32'd1) >= actual_file_size)
                    state <= ST_DONE;
            end

            if (state == ST_WAIT_PIXEL && pixel_enable)
                state <= ST_PIXELS;

            if (state == ST_DONE) begin
                if (!pixel_valid) begin
                    image_done <= 1'b1;
                    state <= ST_IDLE;
                end
            end

            if (state == ST_ERROR) begin
                image_done <= 1'b1;
                state <= ST_IDLE;
            end
        end
    end

endmodule
