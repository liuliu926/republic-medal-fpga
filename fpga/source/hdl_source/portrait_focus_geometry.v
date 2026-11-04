`timescale 1ns/1ps
module portrait_focus_geometry(input wire [5:0] step,
    output reg [10:0] left, right,
    output reg [9:0] top, bottom,
    output reg [16:0] source_step);
always @* begin
    left=100; right=420; top=160; bottom=560; source_step=65536;
    case(step)
    6'd0: begin left=11'd100; right=11'd420; top=10'd160; bottom=10'd560; source_step=17'd65536; end
    6'd1: begin left=11'd108; right=11'd436; top=10'd155; bottom=10'd565; source_step=17'd63937; end
    6'd2: begin left=11'd116; right=11'd452; top=10'd150; bottom=10'd570; source_step=17'd62415; end
    6'd3: begin left=11'd124; right=11'd468; top=10'd145; bottom=10'd575; source_step=17'd60963; end
    6'd4: begin left=11'd132; right=11'd484; top=10'd140; bottom=10'd580; source_step=17'd59578; end
    6'd5: begin left=11'd139; right=11'd499; top=10'd135; bottom=10'd585; source_step=17'd58254; end
    6'd6: begin left=11'd147; right=11'd515; top=10'd130; bottom=10'd590; source_step=17'd56987; end
    6'd7: begin left=11'd155; right=11'd531; top=10'd125; bottom=10'd595; source_step=17'd55775; end
    6'd8: begin left=11'd163; right=11'd547; top=10'd120; bottom=10'd600; source_step=17'd54613; end
    6'd9: begin left=11'd171; right=11'd563; top=10'd115; bottom=10'd605; source_step=17'd53498; end
    6'd10: begin left=11'd179; right=11'd579; top=10'd110; bottom=10'd610; source_step=17'd52428; end
    6'd11: begin left=11'd187; right=11'd595; top=10'd105; bottom=10'd615; source_step=17'd51400; end
    6'd12: begin left=11'd194; right=11'd610; top=10'd100; bottom=10'd620; source_step=17'd50412; end
    6'd13: begin left=11'd202; right=11'd626; top=10'd95; bottom=10'd625; source_step=17'd49461; end
    6'd14: begin left=11'd210; right=11'd642; top=10'd90; bottom=10'd630; source_step=17'd48545; end
    6'd15: begin left=11'd218; right=11'd658; top=10'd85; bottom=10'd635; source_step=17'd47662; end
    6'd16: begin left=11'd226; right=11'd674; top=10'd80; bottom=10'd640; source_step=17'd46811; end
    6'd17: begin left=11'd234; right=11'd690; top=10'd75; bottom=10'd645; source_step=17'd45990; end
    6'd18: begin left=11'd242; right=11'd706; top=10'd70; bottom=10'd650; source_step=17'd45197; end
    6'd19: begin left=11'd250; right=11'd722; top=10'd65; bottom=10'd655; source_step=17'd44431; end
    6'd20: begin left=11'd258; right=11'd738; top=10'd60; bottom=10'd660; source_step=17'd43690; end
    6'd21: begin left=11'd265; right=11'd753; top=10'd55; bottom=10'd665; source_step=17'd42974; end
    6'd22: begin left=11'd273; right=11'd769; top=10'd50; bottom=10'd670; source_step=17'd42281; end
    6'd23: begin left=11'd281; right=11'd785; top=10'd45; bottom=10'd675; source_step=17'd41610; end
    6'd24: begin left=11'd289; right=11'd801; top=10'd40; bottom=10'd680; source_step=17'd40960; end
    6'd25: begin left=11'd297; right=11'd817; top=10'd35; bottom=10'd685; source_step=17'd40329; end
    6'd26: begin left=11'd305; right=11'd833; top=10'd30; bottom=10'd690; source_step=17'd39718; end
    6'd27: begin left=11'd313; right=11'd849; top=10'd25; bottom=10'd695; source_step=17'd39125; end
    6'd28: begin left=11'd320; right=11'd864; top=10'd20; bottom=10'd700; source_step=17'd38550; end
    6'd29: begin left=11'd328; right=11'd880; top=10'd15; bottom=10'd705; source_step=17'd37991; end
    6'd30: begin left=11'd336; right=11'd896; top=10'd10; bottom=10'd710; source_step=17'd37449; end
    6'd31: begin left=11'd344; right=11'd912; top=10'd5; bottom=10'd715; source_step=17'd36921; end
    6'd32: begin left=11'd352; right=11'd928; top=10'd0; bottom=10'd720; source_step=17'd36408; end
    default: ;
    endcase
end
endmodule
