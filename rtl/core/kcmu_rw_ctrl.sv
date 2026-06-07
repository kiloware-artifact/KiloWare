`timescale 1ns/1ps
// ------------------------------------------------------------
// kcmu_rw_ctrl.sv
// Simple wrapper for SRAM controller (represents the "read/write" block).
// ------------------------------------------------------------
module kcmu_rw_ctrl #(
  parameter integer DATA_W     = 32,
  parameter integer LINES      = 4,
  parameter integer LINE_IDX_W = (LINES <= 1) ? 1 : $clog2(LINES)
)(
  input  logic                      clk,
  input  logic                      rst_n,

  input  logic                      sram_re,
  input  logic [LINE_IDX_W-1:0]     sram_raddr,
  output logic [DATA_W-1:0]         sram_rdata,

  input  logic                      sram_we,
  input  logic [LINE_IDX_W-1:0]     sram_waddr,
  input  logic [DATA_W-1:0]         sram_wdata
);

  kcmu_sram_ctrl #(
    .DATA_W(DATA_W),
    .LINES(LINES),
    .LINE_IDX_W(LINE_IDX_W)
  ) u_sram (
    .clk(clk),
    .rst_n(rst_n),
    .re(sram_re),
    .raddr(sram_raddr),
    .rdata(sram_rdata),
    .we(sram_we),
    .waddr(sram_waddr),
    .wdata(sram_wdata)
  );

endmodule
