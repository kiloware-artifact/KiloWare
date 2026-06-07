`timescale 1ns/1ps
// ------------------------------------------------------------
// kcmu_sync_sram_bank.sv
// Synchronous single-read/single-write SRAM bank shell.
//
// This module is intentionally kept outside the active v5
// zero-cycle L1/L2 datapath.  It documents and validates the
// BRAM-compatible latency contract for retargeted KCMU variants
// that choose a registered one-cycle SRAM bank interface.
// ------------------------------------------------------------
module kcmu_sync_sram_bank #(
  parameter integer DATA_W = 128,
  parameter integer DEPTH = 1024,
  parameter integer ADDR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH),
  parameter bit WRITE_FIRST_BYPASS = 1'b1
)(
  input  logic                  clk,
  input  logic                  rst_n,

  input  logic                  re,
  input  logic [ADDR_W-1:0]     raddr,
  output logic                  rvalid,
  output logic [DATA_W-1:0]     rdata,

  input  logic                  we,
  input  logic [ADDR_W-1:0]     waddr,
  input  logic [DATA_W-1:0]     wdata
);
  (* ram_style = "block" *) logic [DATA_W-1:0] mem [0:DEPTH-1];
  logic [DATA_W-1:0] rdata_mem;
  logic [DATA_W-1:0] bypass_data;
  logic bypass_valid;

  assign rdata = bypass_valid ? bypass_data : rdata_mem;

  initial begin
    if (DEPTH < 2) begin
      $error("kcmu_sync_sram_bank DEPTH must be at least 2");
    end
    if (DATA_W < 8) begin
      $error("kcmu_sync_sram_bank DATA_W must be at least 8");
    end
  end

  always_ff @(posedge clk) begin
    if (we) begin
      mem[waddr] <= wdata;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rvalid <= 1'b0;
      bypass_valid <= 1'b0;
      bypass_data <= '0;
    end else begin
      rvalid <= re;
      bypass_valid <= WRITE_FIRST_BYPASS && re && we && (waddr == raddr);
      bypass_data <= wdata;
      if (re) begin
        rdata_mem <= mem[raddr];
      end
    end
  end
endmodule
