// TF-loaded home title/name atlas, 768x320 bottom-up monochrome BMP pixels.
// One bit per pixel is cached independently of the SDRAM portrait/background.
module home_text_mask (
    input wire write_clk, write_rst, pixel_start, pixel_valid,
    input wire [23:0] pixel_data,
    input wire video_clk, video_rst, vs, de,
    input wire intro_mode,
    input wire article_mode,
    input wire contribution_mode,
    input wire deeds_mode,
    input wire quiz_mode, quiz_revealed, quiz_correct,
    input wire [1:0] quiz_choice,
    input wire voice_active,
    input wire article_voice_active,
    input wire [9:0] article_body_limit,
    input wire voice_shen,
    input wire voice_generic,
    input wire [12:0] voice_step_samples,
    input wire [2:0] voice_line,
    input wire [31:0] voice_samples,
    input wire [2:0] reveal_step,
    input wire [23:0] rgb_in,
    output wire [23:0] rgb_out
);
    // Candidate: 16 subtitle bits per word in the device's dedicated 32K BRAM.
    // The TF bitmap and on-screen pixel mapping are unchanged.
    wire [17:0] addr;
    reg inside_r;
    reg [2:0] read_bank;
    reg [3:0] read_bit;
    wire [15:0] word_q [0:7];
    reg [14:0] pack_word;
    wire [15:0] write_word = {pixel_data[23], pack_word};
    reg [17:0] write_addr;
    reg ready;
    always @(posedge write_clk) begin
        if (pixel_valid && !ready && write_addr[3:0] != 4'd15)
            pack_word[write_addr[3:0]] <= pixel_data[23];
    end
    genvar b;
    generate for (b=0; b<8; b=b+1) begin: g_mask_bank
        wire we = pixel_valid && !ready && write_addr[3:0] == 4'd15 &&
                  write_addr[17:15] == b;
        EG_PHY_BRAM32K #(
            .MODE("DP16K"), .DATA_WIDTH_A("16"), .DATA_WIDTH_B("16"),
            .REGMODE_A("NOREG"), .REGMODE_B("NOREG")
        ) bits (
            .doa(), .dia(write_word), .addra(write_addr[14:4]),
            .bytea(1'b0), .bytewea(1'b0), .csa(we), .wea(we),
            .clka(write_clk), .rsta(1'b0), .ocea(1'b1),
            .dob(word_q[b]), .dib(16'd0), .addrb(addr[14:4]),
            .byteb(1'b0), .byteweb(1'b0), .csb(inside_r), .web(1'b0),
            .clkb(video_clk), .rstb(1'b0), .oceb(1'b1)
        );
    end endgenerate
    always @(posedge write_clk or posedge write_rst) begin
        if (write_rst) begin write_addr <= 0; ready <= 0; end
        else if (pixel_start) begin write_addr <= 0; ready <= 0; end
        else if (pixel_valid && !ready) begin
            if (write_addr == 18'd245759) ready <= 1;
            else write_addr <= write_addr + 1'b1;
        end
    end
    // Four audio phrases share a compact per-character timing generator.
    reg [9:0] voice_year_limit, voice_text_limit;
    reg [4:0] voice_index;
    reg [2:0] voice_line_q;
    reg [17:0] voice_next;
    // Select operands before a single 18-bit adder. All original cue
    // constants and update conditions are retained exactly.
    reg [17:0] next_base, next_delta;
    always @* begin
        next_base = voice_next; next_delta = 0;
        if (voice_generic) begin
          next_delta = {5'd0, voice_step_samples};
        end else if (voice_shen) begin
          next_delta = (voice_line == 3 ? 18'd3500 :
                         voice_line == 2 ? 18'd3900 : 18'd4000);
        end else if (voice_line == 4) begin
          if (voice_index == 3) begin next_base = 18'd33600; next_delta = 0; end
          else if (voice_index == 14) begin next_base = 18'd97120; next_delta = 0; end
          else if (voice_index < 3) next_delta = 18'd8400;
          else if (voice_index < 14) next_delta = 18'd5774;
          else next_delta = 18'd5110;
        end else if (voice_line == 3) begin
          if (voice_index == 3) begin next_base = 18'd33520; next_delta = 0; end
          else if (voice_index == 13) begin next_base = 18'd92960; next_delta = 0; end
          else if (voice_index < 3) next_delta = 18'd8380;
          else if (voice_index < 13) next_delta = 18'd5944;
          else next_delta = 18'd6373;
        end else if (voice_line == 2) begin
          if (voice_index == 3) begin next_base = 18'd34240; next_delta = 0; end
          else if (voice_index == 14) begin next_base = 18'd92560; next_delta = 0; end
          else if (voice_index == 18) begin next_base = 18'd124560; next_delta = 0; end
          else if (voice_index < 3) next_delta = 18'd8560;
          else if (voice_index < 14) next_delta = 18'd5302;
          else if (voice_index < 18) next_delta = 18'd8000;
          else next_delta = 18'd5634;
        end else begin
          if (voice_index == 3) begin next_base = 18'd34240; next_delta = 0; end
          else if (voice_index == 10) begin next_base = 18'd80080; next_delta = 0; end
          else if (voice_index == 14) begin next_base = 18'd110960; next_delta = 0; end
          else if (voice_index < 3) next_delta = 18'd8560;
          else if (voice_index < 10) next_delta = 18'd6548;
          else if (voice_index < 14) next_delta = 18'd7720;
          else next_delta = 18'd5960;
        end
    end
    always @(posedge video_clk or posedge video_rst) begin
      if (video_rst || !voice_active || voice_line_q != voice_line) begin
        voice_year_limit<=10'd2;
        voice_text_limit<=contribution_mode ? 10'd0 : 10'd183;
        voice_index<=0; voice_next<=0; voice_line_q<=voice_line;
      end else if (voice_index < (voice_generic || voice_shen ? 5'd26 : voice_line == 4 ? 5'd23 :
                                    voice_line == 3 ? 5'd20 :
                                    voice_line == 2 ? 5'd26 : 5'd21) &&
                   voice_samples[17:0] >= voice_next) begin
        if (voice_index < 4) voice_year_limit <= voice_year_limit + 10'd18;
        else if ((voice_generic || voice_shen) && voice_index == 5'd25)
          voice_text_limit <= 10'd768;
        else if (!voice_generic && !voice_shen && ((voice_line == 4 && voice_index == 22) ||
                 (voice_line == 3 && voice_index == 19)))
          voice_text_limit <= 10'd768;
        else voice_text_limit <= voice_text_limit + 10'd25;
        voice_next <= next_base + next_delta;
        voice_index <= voice_index + 1'b1;
      end
    end
    reg [10:0] x;
    reg [9:0] y;
    reg de_q, vs_q, ready_meta, ready_sync;
    // Two-cycle look-ahead covers coordinate registration and BRAM latency.
    wire [10:0] next_x = x + 2'd2;
    reg [9:0] atlas_x;
    reg [8:0] atlas_y;
    reg inside;
    reg [9:0] x_bias;
    reg [8:0] y_bias;
    reg [10:0] local_x;
    reg [9:0] local_y;
    reg [1:0] col, row;
    reg vertical_contribution;
    reg [5:0] vertical_local_x;
    reg [2:0] vertical_row;
    reg [9:0] vertical_char_index;
    always @* begin
        inside=0; x_bias=0; y_bias=0; local_x=0; local_y=0; col=0; row=0;
        vertical_contribution=0; vertical_local_x=0; vertical_row=0; vertical_char_index=0;
        if (article_mode && quiz_mode) begin
            if (de && next_x >= 80 && next_x < 480 && y >= 46 && y < 110) begin
                inside=1; x_bias=10'd944; y_bias=9'd466;
            end else if (quiz_revealed && de && next_x >= 520 && next_x < 650 && y >= 110 && y < 142) begin
                inside=1; x_bias=quiz_correct ? 10'd984 : 10'd100; y_bias=9'd402;
            end else if (de && next_x >= 520 && next_x < 1200 && y >= 184 && y < 248) begin
                inside=1; x_bias=10'd504; y_bias=9'd392;
            end else if (de && next_x >= 520 && next_x < 1200 && y >= 302 && y < 366) begin
                inside=1; x_bias=10'd504; y_bias=9'd338;
            end else if (de && next_x >= 520 && next_x < 1200 && y >= 420 && y < 484) begin
                inside=1; x_bias=10'd504; y_bias=9'd284;
            end else if (de && next_x >= 520 && next_x < 1200 && y >= 538 && y < 602) begin
                inside=1; x_bias=10'd504; y_bias=9'd230;
            end
        end else if (article_mode && deeds_mode) begin
            if (de && next_x >= 11'd80 && next_x < 11'd680 && y >= 10'd46 && y < 10'd110) begin
                inside=1; x_bias=10'd944; y_bias=9'd466;
            end else if (de && next_x >= 11'd64 && next_x < 11'd832) begin
                x_bias=10'd960;
                if (reveal_step >= 1 && y >= 10'd187 && y < 10'd251) begin inside=1; y_bias=9'd389; end
                else if (reveal_step >= 2 && y >= 10'd338 && y < 10'd402) begin inside=1; y_bias=9'd302; end
                else if (reveal_step >= 3 && y >= 10'd489 && y < 10'd553) begin inside=1; y_bias=9'd215; end
            end
        end else if (article_mode && contribution_mode) begin
            if (de && next_x >= 11'd80 && next_x < 11'd680 && y >= 10'd46 && y < 10'd110) begin
                inside=1; x_bias=10'd944; y_bias=9'd466;
            end else if (de && y >= 10'd150 && y < 10'd662) begin
                if (reveal_step >= 1 && next_x >= 11'd908 && next_x < 11'd972) begin
                    inside=1; vertical_contribution=1; vertical_row=1;
                    vertical_local_x=next_x-11'd908;
                end else if (reveal_step >= 2 && next_x >= 11'd693 && next_x < 11'd757) begin
                    inside=1; vertical_contribution=1; vertical_row=2;
                    vertical_local_x=next_x-11'd693;
                end else if (reveal_step >= 3 && next_x >= 11'd478 && next_x < 11'd542) begin
                    inside=1; vertical_contribution=1; vertical_row=3;
                    vertical_local_x=next_x-11'd478;
                end else if (reveal_step >= 4 && next_x >= 11'd263 && next_x < 11'd327) begin
                    inside=1; vertical_contribution=1; vertical_row=4;
                    vertical_local_x=next_x-11'd263;
                end
            end
        end else if (article_mode) begin
            if (de && next_x >= 11'd74 && next_x < 11'd674 &&
                y >= 10'd40 && y < 10'd104) begin
                inside=1; x_bias=10'd950; y_bias=9'd472;
            end else if (de && next_x >= 11'd55 && next_x < 11'd223 &&
                y >= 10'd380 && y < 10'd424) begin
                inside=1; x_bias=10'd545; y_bias=9'd132;
            end else if (de && next_x >= 11'd100 && next_x < 11'd228 &&
                y >= 10'd449 && y < 10'd467) begin
                inside=1; x_bias=10'd500;
                y_bias=9'd108;
            end else if (de && next_x >= 11'd342 && next_x < 11'd1110) begin
                x_bias=10'd682;
                if (reveal_step >= 3'd1 && y >= 10'd180 && y < 10'd244) begin
                    inside=1; y_bias=9'd396;

                end else if (reveal_step >= 3'd2 && y >= 10'd298 && y < 10'd362) begin
                    inside=1; y_bias=9'd342;

                end else if (reveal_step >= 3'd3 && y >= 10'd412 && y < 10'd476) begin
                    inside=1; y_bias=9'd292;

                end else if (reveal_step >= 3'd4 && y >= 10'd534 && y < 10'd598) begin
                    inside=1; y_bias=9'd234;

                end
            end
        end else if (intro_mode) begin
            if (de && next_x >= 11'd457 && next_x < 11'd1225) begin
                x_bias=10'd567;
                if (y >= 10'd160 && y < 10'd208) begin inside=1; y_bias=9'd352; end
                else if (y >= 10'd260 && y < 10'd308) begin inside=1; y_bias=9'd300; end
                else if (y >= 10'd316 && y < 10'd364) begin inside=1; y_bias=9'd292; end
                else if (y >= 10'd367 && y < 10'd415) begin inside=1; y_bias=9'd289; end
                else if (y >= 10'd478 && y < 10'd526) begin inside=1; y_bias=9'd226; end
                else if (y >= 10'd561 && y < 10'd609) begin inside=1; y_bias=9'd191; end
            end
        end else if (de && y >= 10'd18 && y < 10'd82 && next_x >= 11'd320 && next_x < 11'd832) begin
            inside=1; x_bias=10'd704; y_bias=9'd238;
        end else begin
            if (next_x >= 11'd151 && next_x < 11'd343) begin col=0; local_x=11'd873; end
            else if (next_x >= 11'd447 && next_x < 11'd639) begin col=1; local_x=11'd769; end
            else if (next_x >= 11'd743 && next_x < 11'd935) begin col=2; local_x=11'd665; end
            else if (next_x >= 11'd1039 && next_x < 11'd1231) begin col=3; local_x=11'd561; end
            else col=0;
            if (y >= 10'd180 && y < 10'd244) begin row=0; local_y=10'd332; end
            else if (y >= 10'd313 && y < 10'd377) begin row=1; local_y=10'd263; end
            else if (y >= 10'd446 && y < 10'd510) begin row=2; local_y=10'd194; end
            else if (y >= 10'd579 && y < 10'd643) begin row=3; local_y=10'd125; end
            else row=0;
            if (de && ((next_x >= 151 && next_x < 343) ||
                       (next_x >= 447 && next_x < 639) ||
                       (next_x >= 743 && next_x < 935) ||
                       (next_x >= 1039 && next_x < 1231)) &&
                      ((y >= 180 && y < 244) || (y >= 313 && y < 377) ||
                       (y >= 446 && y < 510) || (y >= 579 && y < 643))) begin
                inside=1;
                x_bias=local_x[9:0];
                y_bias=local_y[8:0];
            end
        end
        atlas_x=next_x[9:0]+x_bias;
        atlas_y=y[8:0]+y_bias;
        if (vertical_contribution) begin
            // The bitmap's 768-wide axis represents display y, while each
            // 64-high bank represents a 64-pixel-wide vertical text group.
            atlas_x=y;
            atlas_y={vertical_row,6'd0}+vertical_local_x;
            vertical_char_index=((atlas_x-10'd150)>>5) +
                                (vertical_local_x < 6'd22 ? 10'd16 : 10'd0);
        end
        if (article_mode && !quiz_mode && !contribution_mode && !deeds_mode &&
            voice_active && atlas_y[8:6] == voice_line &&
            ((atlas_x < 126 && atlas_x >= voice_year_limit) ||
             (atlas_x >= 183 && atlas_x >= voice_text_limit))) inside=0;
        // Each atlas row has a 32px heading band and a 32px body band.
        // In deeds, the date spans both bands at x<130 and remains visible.
        // Restrict the wipe to the current row; earlier rows stay complete.
        if (article_voice_active && vertical_contribution &&
            vertical_row == voice_line && vertical_local_x < 6'd44 &&
            vertical_char_index >= article_body_limit)
            inside=0;
        if (article_voice_active && deeds_mode &&
            atlas_y[8:6] == voice_line && atlas_y[5] &&
            atlas_x >= 130 && atlas_x >= article_body_limit)
            inside=0;
    end
    reg [9:0] atlas_x_r;
    reg [8:0] atlas_y_r;
    wire [8:0] bottom_row = 9'd319 - atlas_y_r;
    assign addr = ({9'd0,bottom_row} << 9) + ({9'd0,bottom_row} << 8) + atlas_x_r;
    wire mask_q = word_q[read_bank][read_bit];
    reg inside_q;
    always @(posedge video_clk) begin
        inside_r <= inside;
        atlas_x_r <= atlas_x;
        atlas_y_r <= atlas_y;
        if (inside_r) begin read_bank <= addr[17:15]; read_bit <= addr[3:0]; end
        inside_q <= inside_r;
    end
    always @(posedge video_clk or posedge video_rst) begin
        if (video_rst) begin x<=0; y<=0; de_q<=0; vs_q<=0; ready_meta<=0; ready_sync<=0; end
        else begin
            ready_meta<=ready; ready_sync<=ready_meta; de_q<=de; vs_q<=vs;
            if (vs != vs_q) begin x<=0; y<=0; end
            else begin
                if (de) x<=x+1'b1; else x<=0;
                if (de_q && !de) y<=y+1'b1;
            end
        end
    end
    wire quiz_frame = article_mode && quiz_mode && de && x >= 504 && x < 1208 &&
        ((quiz_choice == 0 && y >= 289 && y < 377 && (x < 508 || x >= 1204 || y < 293 || y >= 373)) ||
         (quiz_choice == 1 && y >= 407 && y < 495 && (x < 508 || x >= 1204 || y < 411 || y >= 491)) ||
         (quiz_choice == 2 && y >= 525 && y < 613 && (x < 508 || x >= 1204 || y < 529 || y >= 609)));
    assign rgb_out = quiz_frame ? 24'hFFD34E : (ready_sync && inside_q && mask_q) ?
        ((article_mode && contribution_mode && atlas_y_r[8:6] != 0 && atlas_y_r[5:0] >= 44)
            ? 24'hE7B430 : 24'hFFF1CD) : rgb_in;
endmodule
