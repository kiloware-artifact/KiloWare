`timescale 1ns/1ps
// ------------------------------------------------------------
// kcmu_sram_ctrl.sv
// On-chip SRAM model for cache lines (data array).
// - sync write
// - combinational read (simple baseline; easy to upgrade to sync read later)
// ------------------------------------------------------------
module kcmu_sram_ctrl #(
  parameter integer DATA_W     = 32,
  parameter integer LINES      = 4,
  parameter integer LINE_IDX_W = (LINES <= 1) ? 1 : $clog2(LINES)
)(
  input  logic                      clk,
  input  logic                      rst_n,

  input  logic                      re,
  input  logic [LINE_IDX_W-1:0]     raddr,
  output logic [DATA_W-1:0]         rdata,

  input  logic                      we,
  input  logic [LINE_IDX_W-1:0]     waddr,
  input  logic [DATA_W-1:0]         wdata
);

  // Zero-cycle read for the L1 data array. On VCU128 this is intentionally
  // inferred as distributed SRAM/LUTRAM; a BRAM-backed variant needs an
  // explicit synchronous-read latency contract at the caller boundary.
  (* ram_style = "distributed" *) logic [DATA_W-1:0] mem [0:LINES-1];

  // sync write
  always @(posedge clk) begin
    if (!rst_n) begin
      // do not clear mem here (cache validity handled by valid bits)
    end else begin
      if (we) begin
        mem[waddr] <= wdata;
      end
    end
  end

  // combinational read (gated by re)
  always @(*) begin
    if (re) rdata = mem[raddr];
    else    rdata = {DATA_W{1'b0}};
  end

endmodule
