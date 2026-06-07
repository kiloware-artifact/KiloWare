`timescale 1ns/1ps
// ------------------------------------------------------------
// kcmu_sync_sram_bank_ooc_wrapper.sv
// Small timing wrapper for standalone VCU128 implementation of
// the synchronous SRAM bank shell.  It creates internal
// register-to-BRAM-to-register paths so post-route timing is
// meaningful in out-of-context runs.
// ------------------------------------------------------------
module kcmu_sync_sram_bank_ooc_wrapper #(
  parameter integer DATA_W = 128,
  parameter integer DEPTH = 1024,
  parameter integer ADDR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
)(
  input  logic              clk,
  input  logic              rst_n,
  input  logic              enable,
  output logic [DATA_W-1:0] checksum_o,
  output logic [31:0]       op_count_o
);
  logic [ADDR_W-1:0] addr_ctr;
  logic [DATA_W-1:0] data_ctr;
  logic re;
  logic we;
  logic [ADDR_W-1:0] raddr;
  logic [ADDR_W-1:0] waddr;
  logic [DATA_W-1:0] wdata;
  logic rvalid;
  logic [DATA_W-1:0] rdata;
  logic [DATA_W-1:0] checksum;
  logic [31:0] op_count;

  function automatic logic [ADDR_W-1:0] dec2(input logic [ADDR_W-1:0] value);
    begin
      dec2 = value - ADDR_W'(2);
    end
  endfunction

  kcmu_sync_sram_bank #(
    .DATA_W(DATA_W),
    .DEPTH(DEPTH),
    .ADDR_W(ADDR_W),
    .WRITE_FIRST_BYPASS(1'b1)
  ) u_bank (
    .clk(clk),
    .rst_n(rst_n),
    .re(re),
    .raddr(raddr),
    .rvalid(rvalid),
    .rdata(rdata),
    .we(we),
    .waddr(waddr),
    .wdata(wdata)
  );

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      addr_ctr <= '0;
      data_ctr <= DATA_W'(64'h0123_4567_89ab_cdef);
      re <= 1'b0;
      we <= 1'b0;
      raddr <= '0;
      waddr <= '0;
      wdata <= '0;
      checksum <= '0;
      op_count <= '0;
      checksum_o <= '0;
      op_count_o <= '0;
    end else begin
      re <= enable;
      we <= enable;
      raddr <= dec2(addr_ctr);
      waddr <= addr_ctr;
      wdata <= data_ctr ^ DATA_W'(op_count);

      if (enable) begin
        addr_ctr <= addr_ctr + ADDR_W'(1);
        data_ctr <= {data_ctr[DATA_W-2:0], data_ctr[DATA_W-1] ^ data_ctr[6] ^ data_ctr[2] ^ data_ctr[1]};
        op_count <= op_count + 32'd1;
      end

      if (rvalid) begin
        checksum <= checksum ^ rdata ^ DATA_W'(op_count);
      end

      checksum_o <= checksum;
      op_count_o <= op_count;
    end
  end
endmodule
