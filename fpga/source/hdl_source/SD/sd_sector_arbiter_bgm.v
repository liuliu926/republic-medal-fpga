`timescale 1ns/1ps
// Latch legacy one-cycle requests while a music sector is on the wire.
// A complete sector is atomic; the old file-level owner remains unchanged.
module sd_sector_arbiter_bgm (
    input wire clk, rst, sector_ready,
    // Preserve a pending cursor request during opening. An already dispatched
    // sector must finish atomically; legacy traffic remains serviceable.
    input wire bgm_enable,
    input wire legacy_req, input wire [31:0] legacy_addr,
    input wire bgm_req, input wire [31:0] bgm_addr,
    output reg sd_req, output wire [31:0] sd_addr,
    input wire sd_valid, sd_end,
    output wire legacy_valid, legacy_end,
    output wire bgm_valid, bgm_end
);
    reg legacy_pending, bgm_pending;
    reg [31:0] legacy_addr_q, bgm_addr_q;
    reg in_flight, owner_bgm, cooldown;
    // The selected pending address remains stable for the whole transaction;
    // no third 32-bit address copy is needed at the physical interface.
    assign sd_addr = owner_bgm ? bgm_addr_q : legacy_addr_q;
    assign legacy_valid = in_flight && !owner_bgm && sd_valid;
    assign legacy_end = in_flight && !owner_bgm && sd_end;
    assign bgm_valid = in_flight && owner_bgm && sd_valid;
    assign bgm_end = in_flight && owner_bgm && sd_end;
    always @(posedge clk) begin
        if (rst) begin
            legacy_pending <= 0; bgm_pending <= 0;
            legacy_addr_q <= 0; bgm_addr_q <= 0;
            in_flight <= 0; owner_bgm <= 0; cooldown <= 0;
            sd_req <= 0;
        end else begin
            sd_req <= 0;
            cooldown <= 0;
            if (legacy_req) begin legacy_pending <= 1; legacy_addr_q <= legacy_addr; end
            if (bgm_req) begin bgm_pending <= 1; bgm_addr_q <= bgm_addr; end
            if (in_flight) begin
                if (sd_end) begin in_flight <= 0; cooldown <= 1; end
            end else if (sector_ready && !cooldown) begin
                if (bgm_pending && bgm_enable) begin
                    bgm_pending <= 0; owner_bgm <= 1;
                    in_flight <= 1; sd_req <= 1;
                end else if (legacy_pending) begin
                    legacy_pending <= 0; owner_bgm <= 0;
                    in_flight <= 1; sd_req <= 1;
                end
            end
        end
    end
endmodule
