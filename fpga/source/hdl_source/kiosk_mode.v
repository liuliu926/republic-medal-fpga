// SW3 selects autoplay. Any key pressed while autoplay is active only shows
// an exit hint; the top level may pause page advances while prompt_visible=1.
module kiosk_mode #(
    parameter integer DEBOUNCE_CYCLES = 500_000,     // 10 ms at 50 MHz
    parameter integer PROMPT_CYCLES   = 250_000_000  // 5 s at 50 MHz
)(
    input  wire clk,
    input  wire rst,
    input  wire sw3_raw,
    input  wire key_any_pulse,
    output reg  auto_mode,
    output reg  exit_to_home_pulse,
    output reg  prompt_visible
);

reg [1:0]  sw_sync;
reg [31:0] debounce_count;
reg [31:0] prompt_count;
wire switch_change_accepted = (sw_sync[1] != auto_mode) &&
                              (debounce_count >= DEBOUNCE_CYCLES - 1);

always @(posedge clk) begin
    if (rst) begin
        sw_sync           <= 2'b00;
        debounce_count    <= 32'd0;
        prompt_count      <= 32'd0;
        auto_mode         <= 1'b0;
        exit_to_home_pulse <= 1'b0;
        prompt_visible    <= 1'b0;
    end else begin
        sw_sync <= {sw_sync[0], sw3_raw};
        exit_to_home_pulse <= 1'b0;

        if (sw_sync[1] == auto_mode) begin
            debounce_count <= 32'd0;
        end else if (switch_change_accepted) begin
            debounce_count <= 32'd0;
            auto_mode <= sw_sync[1];
            prompt_visible <= 1'b0;
            prompt_count <= 32'd0;
            if (!sw_sync[1])
                exit_to_home_pulse <= 1'b1;
        end else begin
            debounce_count <= debounce_count + 32'd1;
        end

        if (switch_change_accepted) begin
            // The switch transition above clears the prompt and takes priority.
        end else if (auto_mode && key_any_pulse) begin
            prompt_visible <= 1'b1;
            prompt_count <= 32'd0;
        end else if (prompt_visible) begin
            if (prompt_count >= PROMPT_CYCLES - 1) begin
                prompt_visible <= 1'b0;
                prompt_count <= 32'd0;
            end else begin
                prompt_count <= prompt_count + 32'd1;
            end
        end
    end
end

endmodule
