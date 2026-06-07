`timescale 1ns/1ps
// ------------------------------------------------------------
// kcmu_trace_player.sv
// Simple trace replay engine for simulation-oriented validation.
// - SW/TB writes commands into a tiny local table.
// - start triggers replay from entry 0.
// - issues one command when downstream trace_ready is high.
// ------------------------------------------------------------
module kcmu_trace_player #(
  parameter integer ADDR_W = 8,
  parameter integer DATA_W = 32,
  parameter integer DEPTH  = 32,
  parameter integer IDX_W  = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
)(
  input  logic                   clk,
  input  logic                   rst_n,

  // configuration write port
  input  logic                   cfg_clear,
  input  logic                   cfg_we,
  input  logic [IDX_W-1:0]       cfg_idx,
  input  kcmu_pkg::kcmu_op_t     cfg_op,
  input  logic [ADDR_W-1:0]      cfg_addr,
  input  logic [DATA_W-1:0]      cfg_wdata,
  input  logic                   cfg_last,

  // control
  input  logic                   start,
  output logic                   busy,
  output logic                   done,

  // replayed trace output
  output logic                   trace_valid,
  input  logic                   trace_ready,
  output kcmu_pkg::kcmu_op_t     trace_op,
  output logic [ADDR_W-1:0]      trace_addr,
  output logic [DATA_W-1:0]      trace_wdata
);
  import kcmu_pkg::*;

  kcmu_op_t             op_mem   [0:DEPTH-1];
  logic [ADDR_W-1:0]    addr_mem [0:DEPTH-1];
  logic [DATA_W-1:0]    wdata_mem[0:DEPTH-1];
  logic                 last_mem [0:DEPTH-1];

  logic [IDX_W-1:0] rd_ptr;

  integer i;

  assign trace_valid = busy;
  assign trace_op    = op_mem[rd_ptr];
  assign trace_addr  = addr_mem[rd_ptr];
  assign trace_wdata = wdata_mem[rd_ptr];

  always @(posedge clk) begin
    if (!rst_n) begin
      busy   <= 1'b0;
      done   <= 1'b0;
      rd_ptr <= {IDX_W{1'b0}};
      for (i = 0; i < DEPTH; i = i + 1) begin
        op_mem[i]    <= KCMU_OP_NOP;
        addr_mem[i]  <= {ADDR_W{1'b0}};
        wdata_mem[i] <= {DATA_W{1'b0}};
        last_mem[i]  <= 1'b0;
      end
    end else begin
      done <= 1'b0;

      if (cfg_clear) begin
        for (i = 0; i < DEPTH; i = i + 1) begin
          op_mem[i]    <= KCMU_OP_NOP;
          addr_mem[i]  <= {ADDR_W{1'b0}};
          wdata_mem[i] <= {DATA_W{1'b0}};
          last_mem[i]  <= 1'b0;
        end
      end

      if (cfg_we) begin
        op_mem[cfg_idx]    <= cfg_op;
        addr_mem[cfg_idx]  <= cfg_addr;
        wdata_mem[cfg_idx] <= cfg_wdata;
        last_mem[cfg_idx]  <= cfg_last;
      end

      if (start && !busy) begin
        busy   <= 1'b1;
        rd_ptr <= {IDX_W{1'b0}};
      end else if (busy && trace_valid && trace_ready) begin
        if (last_mem[rd_ptr] || (rd_ptr == IDX_W'(DEPTH - 1))) begin
          busy <= 1'b0;
          done <= 1'b1;
        end else begin
          rd_ptr <= rd_ptr + {{(IDX_W-1){1'b0}}, 1'b1};
        end
      end
    end
  end

endmodule
