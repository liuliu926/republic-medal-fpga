// Lower-right waveform of the exact mixed PCM samples sent to HDMI.
// Audio input is read-only: no change to the playback path or TF assets.
module audio_waveform_overlay_720p (
    input wire clk,
    input wire rst,
    input wire de,
    input wire [10:0] pixel_x,
    input wire [9:0] pixel_y,
    input wire audio_valid,
    input wire signed [23:0] audio_sample,
    input wire [23:0] rgb_in,
    output wire [23:0] rgb_out
);
    localparam [10:0] LEFT = 11'd992;
    localparam [10:0] RIGHT = 11'd1248;
    localparam [9:0] MIDDLE = 10'd674;
    // Eight captured peaks, each covering 2048 mixed audio samples (~43 ms),
    // span about a third of a second. Two slim bars render each peak.
    reg [3:0] history [0:7];
    reg [2:0] write_ptr;
    reg [10:0] sample_count;
    reg [3:0] peak;
    reg [3:0] display_height;
    integer i;

    // Ones' complement is enough at this display resolution and avoids a
    // 24-bit absolute-value adder on the live audio path.
    wire [23:0] magnitude = audio_sample[23] ? ~audio_sample : audio_sample;
    // Fourfold visual sensitivity; saturate without changing audio or overlay bounds.
    wire [3:0] scaled = magnitude[19:16];
    wire [3:0] height_now = (|magnitude[23:20]) ?
        4'd15 : scaled[3:0];
    wire [3:0] next_peak = height_now > peak ? height_now : peak;
    // The RGB coordinate counters advance on this edge. Read one pixel ahead
    // to align the registered history lookup to the outgoing RGB pixel.
    wire [10:0] lookahead_x = pixel_x + 11'd1;
    wire [2:0] read_index = write_ptr +
        ((lookahead_x - LEFT) >> 5);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            write_ptr <= 0;
            sample_count <= 0;
            peak <= 0;
            display_height <= 0;
            for (i = 0; i < 8; i = i + 1)
                history[i] <= 0;
        end else begin
            display_height <= history[read_index];
            if (audio_valid) begin
                if (sample_count == 11'd2047) begin
                    sample_count <= 0;
                    history[write_ptr] <= next_peak;
                    write_ptr <= write_ptr + 1'b1;
                    peak <= 0;
                end else begin
                    sample_count <= sample_count + 1'b1;
                    peak <= next_peak;
                end
            end
        end
    end

    wire in_area = de && pixel_x >= LEFT && pixel_x < RIGHT &&
                   pixel_y >= MIDDLE - 10'd16 && pixel_y <= MIDDLE + 10'd16;
    wire bar_pixel = in_area &&
        (pixel_y >= MIDDLE - {6'd0, display_height}) &&
        (pixel_y <= MIDDLE + {6'd0, display_height}) &&
        ((pixel_x[4:0] >= 5'd5 && pixel_x[4:0] <= 5'd11) ||
         (pixel_x[4:0] >= 5'd19 && pixel_x[4:0] <= 5'd25));
    wire center_line = in_area && pixel_y == MIDDLE;
    assign rgb_out = bar_pixel ? 24'hFFE7AE :
                     center_line ? 24'hD99243 : rgb_in;
endmodule

