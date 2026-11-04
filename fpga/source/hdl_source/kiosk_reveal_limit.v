// Generated from prepared_resource_catalog/catalog.json; do not edit manually.
module kiosk_reveal_limit(input wire [5:0] slide_number,
    output reg slide_valid, output reg [2:0] max_reveal_step);
always @* begin
    slide_valid=1; max_reveal_step=0;
    case (slide_number)
        6'd1: max_reveal_step=3'd0;
        6'd2: max_reveal_step=3'd0;
        6'd3: max_reveal_step=3'd4;
        6'd4: max_reveal_step=3'd4;
        6'd5: max_reveal_step=3'd3;
        6'd6: max_reveal_step=3'd0;
        6'd7: max_reveal_step=3'd5;
        6'd8: max_reveal_step=3'd4;
        6'd9: max_reveal_step=3'd4;
        6'd10: max_reveal_step=3'd0;
        6'd11: max_reveal_step=3'd4;
        6'd12: max_reveal_step=3'd4;
        6'd13: max_reveal_step=3'd3;
        6'd14: max_reveal_step=3'd0;
        6'd15: max_reveal_step=3'd4;
        6'd16: max_reveal_step=3'd4;
        6'd17: max_reveal_step=3'd3;
        6'd18: max_reveal_step=3'd0;
        6'd19: max_reveal_step=3'd4;
        6'd20: max_reveal_step=3'd4;
        6'd21: max_reveal_step=3'd3;
        6'd22: max_reveal_step=3'd0;
        6'd23: max_reveal_step=3'd4;
        6'd24: max_reveal_step=3'd4;
        6'd25: max_reveal_step=3'd3;
        6'd26: max_reveal_step=3'd0;
        6'd27: max_reveal_step=3'd4;
        6'd28: max_reveal_step=3'd4;
        6'd29: max_reveal_step=3'd3;
        6'd30: max_reveal_step=3'd0;
        6'd31: max_reveal_step=3'd4;
        6'd32: max_reveal_step=3'd4;
        6'd33: max_reveal_step=3'd3;
        6'd34: max_reveal_step=3'd0;
        6'd35: max_reveal_step=3'd4;
        6'd36: max_reveal_step=3'd4;
        6'd37: max_reveal_step=3'd3;
        6'd38: max_reveal_step=3'd0;
        6'd39: max_reveal_step=3'd4;
        6'd40: max_reveal_step=3'd4;
        6'd41: max_reveal_step=3'd3;
        6'd42: max_reveal_step=3'd0;
        6'd43: max_reveal_step=3'd4;
        6'd44: max_reveal_step=3'd4;
        6'd45: max_reveal_step=3'd3;
        6'd46: max_reveal_step=3'd0;
        6'd47: max_reveal_step=3'd4;
        6'd48: max_reveal_step=3'd4;
        6'd49: max_reveal_step=3'd3;
        6'd50: max_reveal_step=3'd0;
        6'd51: max_reveal_step=3'd4;
        6'd52: max_reveal_step=3'd4;
        6'd53: max_reveal_step=3'd3;
        default: begin slide_valid=0; max_reveal_step=0; end
    endcase
end
endmodule
