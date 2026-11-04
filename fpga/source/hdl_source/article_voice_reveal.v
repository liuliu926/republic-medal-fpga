// Generated exact cue compaction. Canonical SHA256: c2294d3e04c2d92ddfc2d88b851115dd9b251aa7266e320c8ae1cbbe9cb8801b
// Fixed 32-word slots avoid a large combinational 91-clip timing multiplexer.
// All clocks and samples_played are in the pixel domain. PCM remains on TF.
module article_voice_reveal #(
    parameter CUE_FILE = "article_voice_cues.hex"
)(
    input wire clk, rst, active,
    input wire [6:0] slot,
    input wire [31:0] samples_played,
    output reg [9:0] body_limit,
    output reg finished
);
    reg [6:0] slot_q;
    reg [4:0] index;
    reg [1:0] state;
    wire [11:0] rom_addr = {slot_q,index};
    wire [23:0] cue;
    generate if(CUE_FILE == "article_voice_cues.hex") begin:g_compact
        reg [11:0] base;
        reg [5:0] length;
        reg [3:0] mode;
        always @* begin
            base=0; length=0; mode=0;
            case(rom_addr[11:5])
            7'd0: begin base=12'd0; length=6'd29; mode=4'd0; end
            7'd1: begin base=12'd29; length=6'd26; mode=4'd1; end
            7'd2: begin base=12'd55; length=6'd25; mode=4'd2; end
            7'd3: begin base=12'd80; length=6'd26; mode=4'd1; end
            7'd4: begin base=12'd106; length=6'd26; mode=4'd3; end
            7'd5: begin base=12'd132; length=6'd26; mode=4'd4; end
            7'd6: begin base=12'd158; length=6'd27; mode=4'd3; end
            7'd8: begin base=12'd185; length=6'd28; mode=4'd5; end
            7'd9: begin base=12'd213; length=6'd28; mode=4'd6; end
            7'd10: begin base=12'd241; length=6'd23; mode=4'd2; end
            7'd11: begin base=12'd264; length=6'd21; mode=4'd7; end
            7'd12: begin base=12'd285; length=6'd24; mode=4'd4; end
            7'd13: begin base=12'd309; length=6'd24; mode=4'd4; end
            7'd14: begin base=12'd333; length=6'd21; mode=4'd4; end
            7'd16: begin base=12'd354; length=6'd25; mode=4'd2; end
            7'd17: begin base=12'd379; length=6'd25; mode=4'd6; end
            7'd18: begin base=12'd404; length=6'd29; mode=4'd5; end
            7'd19: begin base=12'd433; length=6'd25; mode=4'd2; end
            7'd20: begin base=12'd458; length=6'd24; mode=4'd4; end
            7'd21: begin base=12'd482; length=6'd23; mode=4'd4; end
            7'd22: begin base=12'd505; length=6'd25; mode=4'd4; end
            7'd24: begin base=12'd530; length=6'd25; mode=4'd8; end
            7'd25: begin base=12'd555; length=6'd26; mode=4'd1; end
            7'd26: begin base=12'd581; length=6'd23; mode=4'd9; end
            7'd27: begin base=12'd604; length=6'd25; mode=4'd2; end
            7'd28: begin base=12'd629; length=6'd23; mode=4'd4; end
            7'd29: begin base=12'd652; length=6'd20; mode=4'd4; end
            7'd30: begin base=12'd672; length=6'd23; mode=4'd4; end
            7'd32: begin base=12'd695; length=6'd23; mode=4'd2; end
            7'd33: begin base=12'd718; length=6'd22; mode=4'd7; end
            7'd34: begin base=12'd740; length=6'd23; mode=4'd2; end
            7'd35: begin base=12'd763; length=6'd18; mode=4'd10; end
            7'd36: begin base=12'd781; length=6'd20; mode=4'd4; end
            7'd37: begin base=12'd801; length=6'd21; mode=4'd4; end
            7'd38: begin base=12'd822; length=6'd21; mode=4'd4; end
            7'd40: begin base=12'd843; length=6'd29; mode=4'd0; end
            7'd41: begin base=12'd872; length=6'd21; mode=4'd11; end
            7'd42: begin base=12'd893; length=6'd26; mode=4'd6; end
            7'd43: begin base=12'd919; length=6'd28; mode=4'd6; end
            7'd44: begin base=12'd947; length=6'd23; mode=4'd4; end
            7'd45: begin base=12'd970; length=6'd20; mode=4'd4; end
            7'd46: begin base=12'd990; length=6'd22; mode=4'd4; end
            7'd48: begin base=12'd1012; length=6'd22; mode=4'd7; end
            7'd49: begin base=12'd1034; length=6'd21; mode=4'd11; end
            7'd50: begin base=12'd1055; length=6'd20; mode=4'd10; end
            7'd51: begin base=12'd1075; length=6'd22; mode=4'd7; end
            7'd52: begin base=12'd1097; length=6'd21; mode=4'd4; end
            7'd53: begin base=12'd1118; length=6'd22; mode=4'd4; end
            7'd54: begin base=12'd1140; length=6'd25; mode=4'd4; end
            7'd56: begin base=12'd1165; length=6'd21; mode=4'd7; end
            7'd57: begin base=12'd1186; length=6'd24; mode=4'd2; end
            7'd58: begin base=12'd1210; length=6'd19; mode=4'd10; end
            7'd59: begin base=12'd1229; length=6'd19; mode=4'd10; end
            7'd60: begin base=12'd1248; length=6'd24; mode=4'd4; end
            7'd61: begin base=12'd1272; length=6'd22; mode=4'd4; end
            7'd62: begin base=12'd1294; length=6'd30; mode=4'd12; end
            7'd64: begin base=12'd1324; length=6'd25; mode=4'd13; end
            7'd65: begin base=12'd1349; length=6'd26; mode=4'd14; end
            7'd66: begin base=12'd1375; length=6'd26; mode=4'd2; end
            7'd67: begin base=12'd1401; length=6'd21; mode=4'd11; end
            7'd68: begin base=12'd1422; length=6'd22; mode=4'd4; end
            7'd69: begin base=12'd1444; length=6'd26; mode=4'd4; end
            7'd70: begin base=12'd1470; length=6'd24; mode=4'd4; end
            7'd72: begin base=12'd1494; length=6'd24; mode=4'd1; end
            7'd73: begin base=12'd1518; length=6'd21; mode=4'd11; end
            7'd74: begin base=12'd1539; length=6'd18; mode=4'd10; end
            7'd75: begin base=12'd1557; length=6'd23; mode=4'd9; end
            7'd76: begin base=12'd1580; length=6'd24; mode=4'd4; end
            7'd77: begin base=12'd1604; length=6'd28; mode=4'd15; end
            7'd78: begin base=12'd1632; length=6'd22; mode=4'd4; end
            7'd80: begin base=12'd1654; length=6'd26; mode=4'd6; end
            7'd81: begin base=12'd1680; length=6'd23; mode=4'd7; end
            7'd82: begin base=12'd1703; length=6'd21; mode=4'd11; end
            7'd83: begin base=12'd1724; length=6'd22; mode=4'd2; end
            7'd84: begin base=12'd1746; length=6'd27; mode=4'd3; end
            7'd85: begin base=12'd1773; length=6'd21; mode=4'd4; end
            7'd86: begin base=12'd1794; length=6'd19; mode=4'd4; end
            7'd88: begin base=12'd1813; length=6'd24; mode=4'd2; end
            7'd89: begin base=12'd1837; length=6'd22; mode=4'd2; end
            7'd90: begin base=12'd1859; length=6'd20; mode=4'd10; end
            7'd91: begin base=12'd1879; length=6'd24; mode=4'd2; end
            7'd92: begin base=12'd1903; length=6'd23; mode=4'd4; end
            7'd93: begin base=12'd1926; length=6'd23; mode=4'd4; end
            7'd94: begin base=12'd1949; length=6'd24; mode=4'd4; end
            7'd96: begin base=12'd1973; length=6'd24; mode=4'd2; end
            7'd97: begin base=12'd1997; length=6'd23; mode=4'd2; end
            7'd98: begin base=12'd2020; length=6'd21; mode=4'd11; end
            7'd99: begin base=12'd2041; length=6'd22; mode=4'd7; end
            7'd100: begin base=12'd2063; length=6'd23; mode=4'd4; end
            7'd101: begin base=12'd2086; length=6'd19; mode=4'd4; end
            7'd102: begin base=12'd2105; length=6'd20; mode=4'd4; end
                default: begin end
            endcase
        end
        wire [11:0] packed_addr=base+{7'd0,rom_addr[4:0]};
        reg [17:0] main_rom[0:2047]; /* fehdl force_ram=1, ram_style="bram" */
        reg [17:0] tail_rom[0:127]; /* fehdl force_ram=1, ram_style="bram" */
        initial begin
            $readmemh("article_cue_compact_main.hex",main_rom);
            $readmemh("article_cue_compact_tail.hex",tail_rom);
        end
        reg [17:0] main_word,tail_word;
        reg tail_select,padding;
        reg [3:0] mode_q;
        always @(posedge clk) begin
            main_word<=main_rom[packed_addr[10:0]];
            tail_word<=tail_rom[packed_addr[6:0]];
            tail_select<=packed_addr[11];
            padding<=({1'b0,rom_addr[4:0]}>=length);
            mode_q<=mode;
        end
        wire [17:0] packed_word=tail_select?tail_word:main_word;
        wire [9:0] count={5'd0,packed_word[4:0]};
        reg [9:0] decoded_body;
        always @* begin
            case(mode_q)
                4'd0:decoded_body=(count==0)?10'd768:(10'd2+(count<<4));
                4'd1:decoded_body=(count==0)?10'd768:(10'd2+(count<<1)+(count<<4));
                4'd2:decoded_body=(count==0)?10'd768:(10'd2+count+(count<<1)+(count<<4));
                4'd3:decoded_body=(count==0)?10'd768:(10'd130+(count<<1)+(count<<2)+(count<<4));
                4'd4:decoded_body=(count==0)?10'd768:(10'd130+count+(count<<1)+(count<<2)+(count<<4));
                4'd5:decoded_body=(count==0)?10'd768:(10'd2+count+(count<<1)+(count<<2)+(count<<3));
                4'd6:decoded_body=(count==0)?10'd768:(10'd2+count+(count<<4));
                4'd7:decoded_body=(count==0)?10'd768:(10'd2+count+(count<<2)+(count<<4));
                4'd8:begin case(count)
                    10'd1:decoded_body=10'd21;
                    10'd2:decoded_body=10'd40;
                    10'd3:decoded_body=10'd59;
                    10'd4:decoded_body=10'd84;
                    10'd5:decoded_body=10'd95;
                    10'd6:decoded_body=10'd106;
                    10'd7:decoded_body=10'd117;
                    10'd8:decoded_body=10'd122;
                    10'd9:decoded_body=10'd139;
                    10'd10:decoded_body=10'd158;
                    10'd11:decoded_body=10'd196;
                    10'd12:decoded_body=10'd215;
                    10'd13:decoded_body=10'd234;
                    10'd14:decoded_body=10'd253;
                    10'd15:decoded_body=10'd272;
                    10'd16:decoded_body=10'd291;
                    10'd17:decoded_body=10'd310;
                    10'd18:decoded_body=10'd329;
                    10'd19:decoded_body=10'd367;
                    10'd20:decoded_body=10'd386;
                    10'd21:decoded_body=10'd405;
                    10'd22:decoded_body=10'd424;
                    10'd23:decoded_body=10'd443;
                    10'd24:decoded_body=10'd481;
                    10'd25:decoded_body=10'd768;
                    default:decoded_body=10'd0; endcase end
                4'd9:decoded_body=(count==0)?10'd768:(10'd2+(count<<2)+(count<<4));
                4'd10:decoded_body=(count==0)?10'd768:(10'd2+count+(count<<1)+(count<<2)+(count<<4));
                4'd11:decoded_body=(count==0)?10'd768:(10'd2+(count<<1)+(count<<2)+(count<<4));
                4'd12:decoded_body=(count==0)?10'd768:(10'd130+(count<<2)+(count<<4));
                4'd13:begin case(count)
                    10'd1:decoded_body=10'd14;
                    10'd2:decoded_body=10'd26;
                    10'd3:decoded_body=10'd38;
                    10'd4:decoded_body=10'd56;
                    10'd5:decoded_body=10'd76;
                    10'd6:decoded_body=10'd96;
                    10'd7:decoded_body=10'd116;
                    10'd8:decoded_body=10'd136;
                    10'd9:decoded_body=10'd156;
                    10'd10:decoded_body=10'd176;
                    10'd11:decoded_body=10'd196;
                    10'd12:decoded_body=10'd216;
                    10'd13:decoded_body=10'd236;
                    10'd14:decoded_body=10'd256;
                    10'd15:decoded_body=10'd296;
                    10'd16:decoded_body=10'd316;
                    10'd17:decoded_body=10'd336;
                    10'd18:decoded_body=10'd356;
                    10'd19:decoded_body=10'd376;
                    10'd20:decoded_body=10'd396;
                    10'd21:decoded_body=10'd416;
                    10'd22:decoded_body=10'd436;
                    10'd23:decoded_body=10'd456;
                    10'd24:decoded_body=10'd496;
                    10'd25:decoded_body=10'd768;
                    default:decoded_body=10'd0; endcase end
                4'd14:begin case(count)
                    10'd1:decoded_body=10'd12;
                    10'd2:decoded_body=10'd22;
                    10'd3:decoded_body=10'd32;
                    10'd4:decoded_body=10'd47;
                    10'd5:decoded_body=10'd64;
                    10'd6:decoded_body=10'd81;
                    10'd7:decoded_body=10'd98;
                    10'd8:decoded_body=10'd115;
                    10'd9:decoded_body=10'd132;
                    10'd10:decoded_body=10'd149;
                    10'd11:decoded_body=10'd183;
                    10'd12:decoded_body=10'd200;
                    10'd13:decoded_body=10'd217;
                    10'd14:decoded_body=10'd268;
                    10'd15:decoded_body=10'd285;
                    10'd16:decoded_body=10'd302;
                    10'd17:decoded_body=10'd319;
                    10'd18:decoded_body=10'd336;
                    10'd19:decoded_body=10'd353;
                    10'd20:decoded_body=10'd370;
                    10'd21:decoded_body=10'd387;
                    10'd22:decoded_body=10'd404;
                    10'd23:decoded_body=10'd421;
                    10'd24:decoded_body=10'd438;
                    10'd25:decoded_body=10'd472;
                    10'd26:decoded_body=10'd768;
                    default:decoded_body=10'd0; endcase end
                4'd15:decoded_body=(count==0)?10'd768:(10'd130+count+(count<<2)+(count<<4));
                default:decoded_body=10'd0;
            endcase
        end
        assign cue=padding?24'h8003ff:{packed_word[17],1'b0,packed_word[16:5],decoded_body};
    end else begin:g_custom_file
        reg [23:0] cues[0:4095]; /* fehdl force_ram=1, ram_style="bram" */
        reg [23:0] custom_cue;
        initial $readmemh(CUE_FILE,cues);
        always @(posedge clk)custom_cue<=cues[rom_addr];
        assign cue=custom_cue;
    end endgenerate
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            slot_q<=0; index<=0; state<=0; body_limit<=0; finished<=0;
        end else if (!active || slot_q != slot) begin
            slot_q<=slot; index<=0; state<=0; body_limit<=0; finished<=0;
        end else case (state)
            // Do not interpret the preceding clip's counter after fast navigation.
            0: if (samples_played == 0) state<=1;
            1: state<=2; // Prime the synchronous ROM after address changes.
            2: if (samples_played[18:6] >= cue[22:10]) begin
                body_limit<=cue[9:0];
                if (cue[23]) begin finished<=1; state<=3; end
                else begin index<=index+1'b1; state<=1; end
            end
            3: begin end
        endcase
    end
endmodule
