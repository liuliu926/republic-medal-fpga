// Draw a small gold selection outline over the four PPT intro-page choices.
// The underlying labels and artwork remain independent TF-card layers.
module intro_section_highlight (
    input wire clk,
    input wire rst,
    input wire vs,
    input wire de,
    input wire active,
    input wire [2:0] section_index,
    input wire [23:0] rgb_in,
    output wire [23:0] rgb_out
);
    reg [10:0] x;
    reg [9:0] y;
    reg de_q, vs_q;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            x <= 0;
            y <= 0;
            de_q <= 0;
            vs_q <= 0;
        end else begin
            de_q <= de;
            vs_q <= vs;
            if (vs != vs_q) begin
                x <= 0;
                y <= 0;
            end else begin
                if (de) x <= x + 1'b1;
                else x <= 0;
                if (de_q && !de) y <= y + 1'b1;
            end
        end
    end

    wire right_column = section_index[0];
    wire lower_row = section_index[1];
    wire [10:0] left = right_column ? 11'd815 : 11'd469;
    wire [10:0] right = right_column ? 11'd1146 : 11'd800;
    wire [9:0] top = lower_row ? 10'd545 : 10'd461;
    wire [9:0] bottom = lower_row ? 10'd617 : 10'd533;
    wire in_box = x >= left && x < right && y >= top && y < bottom;
    wire outline = in_box && (x < left + 11'd3 || x >= right - 11'd3 ||
                              y < top + 10'd3 || y >= bottom - 10'd3);
    wire col0=x>=469 && x<800;
    wire col1=x>=815 && x<1146;
    wire row0=y>=461 && y<533;
    wire row1=y>=545 && y<617;
    wire vertical_edge=(x>=469 && x<471) || (x>=798 && x<800) ||
                       (x>=815 && x<817) || (x>=1144 && x<1146);
    wire horizontal_edge=(y>=461 && y<463) || (y>=531 && y<533) ||
                         (y>=545 && y<547) || (y>=615 && y<617);
    wire menu_outline=((row0 || row1) && vertical_edge) ||
                      ((col0 || col1) && horizontal_edge);
    assign rgb_out = (active && de && outline) ? 24'hFFE27C :
                     (active && de && menu_outline) ? 24'hC99F64 : rgb_in;
endmodule
