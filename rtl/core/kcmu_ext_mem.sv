`timescale 1ns/1ps
// ------------------------------------------------------------
// kcmu_ext_mem.sv
// External memory model (backing store).
// - sync write
// - read-valid handshake with configurable latency
// NOTE: memory contents are NOT cleared on rst_n.
// ------------------------------------------------------------
module kcmu_ext_mem #(
  parameter integer ADDR_W = 8,
  parameter integer DATA_W = 32,
  parameter integer RD_LATENCY = 1
)(
  input  logic                 clk,
  input  logic                 rst_n,

  input  logic                 re,
  input  logic [ADDR_W-1:0]    raddr,
  output logic [DATA_W-1:0]    rdata,
  output logic                 rvalid,

  input  logic                 we,
  input  logic [ADDR_W-1:0]    waddr,
  input  logic [DATA_W-1:0]    wdata
);

  localparam integer DEPTH = (1 << ADDR_W);
  localparam integer RD_LAT_SAFE = (RD_LATENCY < 1) ? 1 : RD_LATENCY;

  logic [DATA_W-1:0] mem [0:DEPTH-1];
  logic [RD_LAT_SAFE-1:0] rd_pipe_valid;
  logic [ADDR_W-1:0]      rd_pipe_addr [0:RD_LAT_SAFE-1];
  integer                 ri;

  // sync write
  always @(posedge clk) begin
    if (!rst_n) begin
      // keep memory content
    end else begin
      if (we) begin
        mem[waddr] <= wdata;
      end
    end
  end

  // read request pipeline (valid + addr)
  always @(posedge clk) begin
    if (!rst_n) begin
      rd_pipe_valid <= {RD_LAT_SAFE{1'b0}};
      for (ri = 0; ri < RD_LAT_SAFE; ri = ri + 1) begin
        rd_pipe_addr[ri] <= {ADDR_W{1'b0}};
      end
      rdata <= {DATA_W{1'b0}};
      rvalid <= 1'b0;
    end else begin
      rd_pipe_valid[0] <= re;
      rd_pipe_addr[0] <= raddr;
      for (ri = 1; ri < RD_LAT_SAFE; ri = ri + 1) begin
        rd_pipe_valid[ri] <= rd_pipe_valid[ri-1];
        rd_pipe_addr[ri] <= rd_pipe_addr[ri-1];
      end

      rvalid <= rd_pipe_valid[RD_LAT_SAFE-1];
      if (rd_pipe_valid[RD_LAT_SAFE-1]) begin
        rdata <= mem[rd_pipe_addr[RD_LAT_SAFE-1]];
      end
    end
  end

endmodule
