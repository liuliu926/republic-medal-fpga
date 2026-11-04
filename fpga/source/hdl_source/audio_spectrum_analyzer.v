`timescale 1ns/1ps
// True 256-point real-input DFT, positive bins 1..127 grouped into 8 bands.
// Bins are 187.5Hz apart at the HDMI mixed PCM rate of48kHz. DC is excluded.
// Uses one shared signed12x12 multiplication expression; no audio-path writes.
// A Bartlett triangular window reduces leakage. Accumulator arrays hold31-bit
// real/imaginary sums. First-sample replacement initializes RAM without reset.
// 4 cycles/bin +3windowcycles; the compact frame reduction takes643 cycles.
// Worst busy interval is1158 clocks; HDMI audio supplies1562/1563 clocks.
// Four transforms feed one21.33ms peak update. Decay is1level/update.
// Level is log2 of peak-bin |real|+|imag| within each frequency band. Every
// positive bin participates; this is peak amplitude, not integrated band power.
module audio_spectrum_analyzer (
    input wire clk,
    input wire rst,
    input wire audio_valid,
    input wire signed [23:0] audio_sample,
    output wire [31:0] levels,
    output reg levels_valid
);
    localparam [3:0] IDLE=0, WINDOW_COEF=1, WINDOW_MUL=2, WINDOW_USE=3,
        BIN_READ=4, BIN_MUL=5, BIN_REAL=6, BIN_WRITE=7,
        REDUCE_READ=8, REDUCE_ABS=9, REDUCE_MAG=10,
        REDUCE_LOG=13, REDUCE_ACCUM=14, REDUCE_PUBLISH=15;
    reg [3:0] state;
    reg [7:0] sample_index, phase;
    reg [6:0] bin_index;
    reg [1:0] block_index;
    reg [2:0] band_index;
    reg signed [11:0] sample_hold;
    reg signed [11:0] coefficient_hold, sine_hold;
    reg signed [23:0] product;
    reg signed [30:0] real_memory [0:127];
    reg signed [30:0] imag_memory [0:127];
    reg signed [30:0] real_hold, imag_hold, real_result;
    reg signed [11:0] cosine_rom [0:255];
    reg [31:0] magnitude_reg;
    reg [3:0] current_level_reg, band_peak;
    reg [3:0] peak_levels [0:7];
    reg [3:0] smooth_levels [0:7];
    integer i;
    initial begin
        cosine_rom[0]=12'sd1024;
        cosine_rom[1]=12'sd1024;
        cosine_rom[2]=12'sd1023;
        cosine_rom[3]=12'sd1021;
        cosine_rom[4]=12'sd1019;
        cosine_rom[5]=12'sd1016;
        cosine_rom[6]=12'sd1013;
        cosine_rom[7]=12'sd1009;
        cosine_rom[8]=12'sd1004;
        cosine_rom[9]=12'sd999;
        cosine_rom[10]=12'sd993;
        cosine_rom[11]=12'sd987;
        cosine_rom[12]=12'sd980;
        cosine_rom[13]=12'sd972;
        cosine_rom[14]=12'sd964;
        cosine_rom[15]=12'sd955;
        cosine_rom[16]=12'sd946;
        cosine_rom[17]=12'sd936;
        cosine_rom[18]=12'sd926;
        cosine_rom[19]=12'sd915;
        cosine_rom[20]=12'sd903;
        cosine_rom[21]=12'sd891;
        cosine_rom[22]=12'sd878;
        cosine_rom[23]=12'sd865;
        cosine_rom[24]=12'sd851;
        cosine_rom[25]=12'sd837;
        cosine_rom[26]=12'sd822;
        cosine_rom[27]=12'sd807;
        cosine_rom[28]=12'sd792;
        cosine_rom[29]=12'sd775;
        cosine_rom[30]=12'sd759;
        cosine_rom[31]=12'sd742;
        cosine_rom[32]=12'sd724;
        cosine_rom[33]=12'sd706;
        cosine_rom[34]=12'sd688;
        cosine_rom[35]=12'sd669;
        cosine_rom[36]=12'sd650;
        cosine_rom[37]=12'sd630;
        cosine_rom[38]=12'sd610;
        cosine_rom[39]=12'sd590;
        cosine_rom[40]=12'sd569;
        cosine_rom[41]=12'sd548;
        cosine_rom[42]=12'sd526;
        cosine_rom[43]=12'sd505;
        cosine_rom[44]=12'sd483;
        cosine_rom[45]=12'sd460;
        cosine_rom[46]=12'sd438;
        cosine_rom[47]=12'sd415;
        cosine_rom[48]=12'sd392;
        cosine_rom[49]=12'sd369;
        cosine_rom[50]=12'sd345;
        cosine_rom[51]=12'sd321;
        cosine_rom[52]=12'sd297;
        cosine_rom[53]=12'sd273;
        cosine_rom[54]=12'sd249;
        cosine_rom[55]=12'sd224;
        cosine_rom[56]=12'sd200;
        cosine_rom[57]=12'sd175;
        cosine_rom[58]=12'sd150;
        cosine_rom[59]=12'sd125;
        cosine_rom[60]=12'sd100;
        cosine_rom[61]=12'sd75;
        cosine_rom[62]=12'sd50;
        cosine_rom[63]=12'sd25;
        cosine_rom[64]=12'sd0;
        cosine_rom[65]=-12'sd25;
        cosine_rom[66]=-12'sd50;
        cosine_rom[67]=-12'sd75;
        cosine_rom[68]=-12'sd100;
        cosine_rom[69]=-12'sd125;
        cosine_rom[70]=-12'sd150;
        cosine_rom[71]=-12'sd175;
        cosine_rom[72]=-12'sd200;
        cosine_rom[73]=-12'sd224;
        cosine_rom[74]=-12'sd249;
        cosine_rom[75]=-12'sd273;
        cosine_rom[76]=-12'sd297;
        cosine_rom[77]=-12'sd321;
        cosine_rom[78]=-12'sd345;
        cosine_rom[79]=-12'sd369;
        cosine_rom[80]=-12'sd392;
        cosine_rom[81]=-12'sd415;
        cosine_rom[82]=-12'sd438;
        cosine_rom[83]=-12'sd460;
        cosine_rom[84]=-12'sd483;
        cosine_rom[85]=-12'sd505;
        cosine_rom[86]=-12'sd526;
        cosine_rom[87]=-12'sd548;
        cosine_rom[88]=-12'sd569;
        cosine_rom[89]=-12'sd590;
        cosine_rom[90]=-12'sd610;
        cosine_rom[91]=-12'sd630;
        cosine_rom[92]=-12'sd650;
        cosine_rom[93]=-12'sd669;
        cosine_rom[94]=-12'sd688;
        cosine_rom[95]=-12'sd706;
        cosine_rom[96]=-12'sd724;
        cosine_rom[97]=-12'sd742;
        cosine_rom[98]=-12'sd759;
        cosine_rom[99]=-12'sd775;
        cosine_rom[100]=-12'sd792;
        cosine_rom[101]=-12'sd807;
        cosine_rom[102]=-12'sd822;
        cosine_rom[103]=-12'sd837;
        cosine_rom[104]=-12'sd851;
        cosine_rom[105]=-12'sd865;
        cosine_rom[106]=-12'sd878;
        cosine_rom[107]=-12'sd891;
        cosine_rom[108]=-12'sd903;
        cosine_rom[109]=-12'sd915;
        cosine_rom[110]=-12'sd926;
        cosine_rom[111]=-12'sd936;
        cosine_rom[112]=-12'sd946;
        cosine_rom[113]=-12'sd955;
        cosine_rom[114]=-12'sd964;
        cosine_rom[115]=-12'sd972;
        cosine_rom[116]=-12'sd980;
        cosine_rom[117]=-12'sd987;
        cosine_rom[118]=-12'sd993;
        cosine_rom[119]=-12'sd999;
        cosine_rom[120]=-12'sd1004;
        cosine_rom[121]=-12'sd1009;
        cosine_rom[122]=-12'sd1013;
        cosine_rom[123]=-12'sd1016;
        cosine_rom[124]=-12'sd1019;
        cosine_rom[125]=-12'sd1021;
        cosine_rom[126]=-12'sd1023;
        cosine_rom[127]=-12'sd1024;
        cosine_rom[128]=-12'sd1024;
        cosine_rom[129]=-12'sd1024;
        cosine_rom[130]=-12'sd1023;
        cosine_rom[131]=-12'sd1021;
        cosine_rom[132]=-12'sd1019;
        cosine_rom[133]=-12'sd1016;
        cosine_rom[134]=-12'sd1013;
        cosine_rom[135]=-12'sd1009;
        cosine_rom[136]=-12'sd1004;
        cosine_rom[137]=-12'sd999;
        cosine_rom[138]=-12'sd993;
        cosine_rom[139]=-12'sd987;
        cosine_rom[140]=-12'sd980;
        cosine_rom[141]=-12'sd972;
        cosine_rom[142]=-12'sd964;
        cosine_rom[143]=-12'sd955;
        cosine_rom[144]=-12'sd946;
        cosine_rom[145]=-12'sd936;
        cosine_rom[146]=-12'sd926;
        cosine_rom[147]=-12'sd915;
        cosine_rom[148]=-12'sd903;
        cosine_rom[149]=-12'sd891;
        cosine_rom[150]=-12'sd878;
        cosine_rom[151]=-12'sd865;
        cosine_rom[152]=-12'sd851;
        cosine_rom[153]=-12'sd837;
        cosine_rom[154]=-12'sd822;
        cosine_rom[155]=-12'sd807;
        cosine_rom[156]=-12'sd792;
        cosine_rom[157]=-12'sd775;
        cosine_rom[158]=-12'sd759;
        cosine_rom[159]=-12'sd742;
        cosine_rom[160]=-12'sd724;
        cosine_rom[161]=-12'sd706;
        cosine_rom[162]=-12'sd688;
        cosine_rom[163]=-12'sd669;
        cosine_rom[164]=-12'sd650;
        cosine_rom[165]=-12'sd630;
        cosine_rom[166]=-12'sd610;
        cosine_rom[167]=-12'sd590;
        cosine_rom[168]=-12'sd569;
        cosine_rom[169]=-12'sd548;
        cosine_rom[170]=-12'sd526;
        cosine_rom[171]=-12'sd505;
        cosine_rom[172]=-12'sd483;
        cosine_rom[173]=-12'sd460;
        cosine_rom[174]=-12'sd438;
        cosine_rom[175]=-12'sd415;
        cosine_rom[176]=-12'sd392;
        cosine_rom[177]=-12'sd369;
        cosine_rom[178]=-12'sd345;
        cosine_rom[179]=-12'sd321;
        cosine_rom[180]=-12'sd297;
        cosine_rom[181]=-12'sd273;
        cosine_rom[182]=-12'sd249;
        cosine_rom[183]=-12'sd224;
        cosine_rom[184]=-12'sd200;
        cosine_rom[185]=-12'sd175;
        cosine_rom[186]=-12'sd150;
        cosine_rom[187]=-12'sd125;
        cosine_rom[188]=-12'sd100;
        cosine_rom[189]=-12'sd75;
        cosine_rom[190]=-12'sd50;
        cosine_rom[191]=-12'sd25;
        cosine_rom[192]=12'sd0;
        cosine_rom[193]=12'sd25;
        cosine_rom[194]=12'sd50;
        cosine_rom[195]=12'sd75;
        cosine_rom[196]=12'sd100;
        cosine_rom[197]=12'sd125;
        cosine_rom[198]=12'sd150;
        cosine_rom[199]=12'sd175;
        cosine_rom[200]=12'sd200;
        cosine_rom[201]=12'sd224;
        cosine_rom[202]=12'sd249;
        cosine_rom[203]=12'sd273;
        cosine_rom[204]=12'sd297;
        cosine_rom[205]=12'sd321;
        cosine_rom[206]=12'sd345;
        cosine_rom[207]=12'sd369;
        cosine_rom[208]=12'sd392;
        cosine_rom[209]=12'sd415;
        cosine_rom[210]=12'sd438;
        cosine_rom[211]=12'sd460;
        cosine_rom[212]=12'sd483;
        cosine_rom[213]=12'sd505;
        cosine_rom[214]=12'sd526;
        cosine_rom[215]=12'sd548;
        cosine_rom[216]=12'sd569;
        cosine_rom[217]=12'sd590;
        cosine_rom[218]=12'sd610;
        cosine_rom[219]=12'sd630;
        cosine_rom[220]=12'sd650;
        cosine_rom[221]=12'sd669;
        cosine_rom[222]=12'sd688;
        cosine_rom[223]=12'sd706;
        cosine_rom[224]=12'sd724;
        cosine_rom[225]=12'sd742;
        cosine_rom[226]=12'sd759;
        cosine_rom[227]=12'sd775;
        cosine_rom[228]=12'sd792;
        cosine_rom[229]=12'sd807;
        cosine_rom[230]=12'sd822;
        cosine_rom[231]=12'sd837;
        cosine_rom[232]=12'sd851;
        cosine_rom[233]=12'sd865;
        cosine_rom[234]=12'sd878;
        cosine_rom[235]=12'sd891;
        cosine_rom[236]=12'sd903;
        cosine_rom[237]=12'sd915;
        cosine_rom[238]=12'sd926;
        cosine_rom[239]=12'sd936;
        cosine_rom[240]=12'sd946;
        cosine_rom[241]=12'sd955;
        cosine_rom[242]=12'sd964;
        cosine_rom[243]=12'sd972;
        cosine_rom[244]=12'sd980;
        cosine_rom[245]=12'sd987;
        cosine_rom[246]=12'sd993;
        cosine_rom[247]=12'sd999;
        cosine_rom[248]=12'sd1004;
        cosine_rom[249]=12'sd1009;
        cosine_rom[250]=12'sd1013;
        cosine_rom[251]=12'sd1016;
        cosine_rom[252]=12'sd1019;
        cosine_rom[253]=12'sd1021;
        cosine_rom[254]=12'sd1023;
        cosine_rom[255]=12'sd1024;
    end

    // One syntactic12x12 multiplication and registered result encourage one DSP.
    always @(posedge clk)
        product <= sample_hold * coefficient_hold;
    // RAM has no reset or asynchronous control. First sample replaces every
    // address, so power-up contents cannot enter a published spectrum.
    always @(posedge clk) begin
        if(state==BIN_READ || state==REDUCE_READ) begin
            real_hold<=real_memory[bin_index];
            imag_hold<=imag_memory[bin_index];
        end
        if(state==BIN_WRITE) begin
            real_memory[bin_index]<=real_result;
            imag_memory[bin_index]<=sample_index==0 ? product_extended :
                imag_hold+product_extended;
        end
    end
    wire signed [30:0] product_extended = {{7{product[23]}},product};
    wire [30:0] abs_real = real_hold[30] ? (~real_hold+31'd1) : real_hold;
    wire [30:0] abs_imag = imag_hold[30] ? (~imag_hold+31'd1) : imag_hold;
    // Existing real_result stores abs(real) between transforms; a32-bit
    // magnitude register stores abs(imag), then |real|+|imag|. No wide band
    // summation, normalization shifter, or leading-bit42-bit encoder is needed.
    wire [6:0] triangle_index=sample_index[7] ?
        ~sample_index[6:0]:sample_index[6:0];

    function band_end;
        input [6:0] bin;
        begin
            case(bin)
                1,2,4,8,16,32,64,127:band_end=1'b1;
                default:band_end=1'b0;
            endcase
        end
    endfunction
    // Bands contain1,1,2,4,8,16,32,63bins, and display their strongest bin.
    function [3:0] log_level;
        input [31:0] value;
        integer j;
        begin
            log_level=0;
            if(value >= 32'd16384) begin
                for(j=14;j<=26;j=j+1)
                    if(value[j])log_level=j-12;
                if(|value[31:27])log_level=15;
            end
        end
    endfunction
    wire [3:0] band_combined=current_level_reg>band_peak ?
        current_level_reg:band_peak;
    wire [3:0] peak_combined=current_level_reg>peak_levels[band_index] ?
        current_level_reg:peak_levels[band_index];

    genvar g;
    generate for(g=0;g<8;g=g+1) begin: g_levels
        assign levels[g*4+:4]=smooth_levels[g];
    end endgenerate

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state<=IDLE;sample_index<=0;phase<=0;bin_index<=0;
            block_index<=0;band_index<=0;sample_hold<=0;
            coefficient_hold<=0;sine_hold<=0;
            real_result<=0;
            levels_valid<=0;
            magnitude_reg<=0;current_level_reg<=0;band_peak<=0;
            for(i=0;i<8;i=i+1) begin peak_levels[i]<=0;smooth_levels[i]<=0;end
        end else begin
            levels_valid<=0;
            case(state)
                IDLE: if(audio_valid) begin
                    sample_hold<=audio_sample[23:12];
                    state<=WINDOW_COEF;
                end
                WINDOW_COEF: begin
                    coefficient_hold<={1'b0,triangle_index,4'd0};
                    state<=WINDOW_MUL;
                end
                WINDOW_MUL:state<=WINDOW_USE;
                WINDOW_USE:begin
                    sample_hold<=product>>>11;
                    bin_index<=0;phase<=0;state<=BIN_READ;
                end
                BIN_READ:begin
                    coefficient_hold<=cosine_rom[phase];
                    sine_hold<=cosine_rom[phase-8'd64];
                    state<=BIN_MUL;
                end
                BIN_MUL:begin coefficient_hold<=sine_hold;state<=BIN_REAL;end
                BIN_REAL:begin
                    real_result<=sample_index==0 ? product_extended :
                        real_hold+product_extended;
                    state<=BIN_WRITE;
                end
                BIN_WRITE:begin
                    if(bin_index==127) begin
                        if(sample_index==255) begin
                            bin_index<=1;band_index<=0;band_peak<=0;
                            state<=REDUCE_READ;
                        end else begin sample_index<=sample_index+1'b1;state<=IDLE;end
                    end else begin
                        bin_index<=bin_index+1'b1;
                        phase<=phase+sample_index;
                        state<=BIN_READ;
                    end
                end
                REDUCE_READ:begin
                    state<=REDUCE_ABS;
                end
                REDUCE_ABS:begin
                    real_result<=abs_real;
                    magnitude_reg<={1'b0,abs_imag};
                    state<=REDUCE_MAG;
                end
                REDUCE_MAG:begin
                    magnitude_reg<={1'b0,real_result}+magnitude_reg;
                    state<=REDUCE_LOG;
                end
                REDUCE_LOG:begin
                    current_level_reg<=log_level(magnitude_reg);
                    state<=REDUCE_ACCUM;
                end
                REDUCE_ACCUM:begin
                    if(band_end(bin_index)) begin
                        current_level_reg<=band_combined;band_peak<=0;
                        state<=REDUCE_PUBLISH;
                    end else begin
                        band_peak<=band_combined;
                        bin_index<=bin_index+1'b1;state<=REDUCE_READ;
                    end
                end
                REDUCE_PUBLISH:begin
                    if(block_index==3) begin
                        peak_levels[band_index]<=0;
                        if(peak_combined>=smooth_levels[band_index])
                            smooth_levels[band_index]<=peak_combined;
                        else if(smooth_levels[band_index]!=0)
                            smooth_levels[band_index]<=smooth_levels[band_index]-1'b1;
                    end else peak_levels[band_index]<=peak_combined;
                    band_index<=band_index+1'b1;
                    if(bin_index==127) begin
                        sample_index<=0;state<=IDLE;
                        block_index<=block_index+1'b1;
                        if(block_index==3)levels_valid<=1;
                    end else begin bin_index<=bin_index+1'b1;state<=REDUCE_READ;end
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule

