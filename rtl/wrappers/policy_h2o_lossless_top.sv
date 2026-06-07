`timescale 1ns/1ps

// H2O-derived lossless metadata top for the paper comparison table.
//
// This wrapper reuses H2O heavy-hitter/recency metadata for replacement, but it
// keeps the KV hierarchy lossless: it does not drop KV tokens or implement the
// original lossy H2O eviction objective.
module policy_h2o_lossless_top #(
  parameter integer AXIL_ADDR_W = 16,
  parameter integer DATA_W      = 32,
  parameter integer TRACE_DEPTH = 256,
  parameter integer RESP_DEPTH  = 256
)(
  input  logic                     clk,
  input  logic                     rst_n,
  input  logic [AXIL_ADDR_W-1:0]   s_axi_awaddr,
  input  logic [2:0]               s_axi_awprot,
  input  logic                     s_axi_awvalid,
  output logic                     s_axi_awready,
  input  logic [DATA_W-1:0]        s_axi_wdata,
  input  logic [(DATA_W/8)-1:0]    s_axi_wstrb,
  input  logic                     s_axi_wvalid,
  output logic                     s_axi_wready,
  output logic [1:0]               s_axi_bresp,
  output logic                     s_axi_bvalid,
  input  logic                     s_axi_bready,
  input  logic [AXIL_ADDR_W-1:0]   s_axi_araddr,
  input  logic [2:0]               s_axi_arprot,
  input  logic                     s_axi_arvalid,
  output logic                     s_axi_arready,
  output logic [DATA_W-1:0]        s_axi_rdata,
  output logic [1:0]               s_axi_rresp,
  output logic                     s_axi_rvalid,
  input  logic                     s_axi_rready
);
  kcmu_fpga_top #(
    .ADDR_W(8),
    .DATA_W(DATA_W),
    .LINES(16),
    .SCORE_W(8),
    .TIME_W(16),
    .K_RECENT(1),
    .H2O_V2_EN(1'b1),
    .TRUE_H2O_RECENT_EN(1'b1),
    .TRUE_H2O_HH_EN(1'b1),
    .TRUE_H2O_HH_SCORE_TH(8'h00),
    .TRUE_H2O_BACKEND_ADMISSION_EN(1'b1),
    .UTILITY_HEAD_ADAPTIVE_EN(1'b0),
    .UTILITY_QUERY_AWARE_EN(1'b0),
    .UTILITY_COST_AWARE_EN(1'b0),
    .UTILITY_BACKEND_CRITICAL_EN(1'b1),
    .MEM_RD_LATENCY(3),
    .L2_RD_LATENCY(1),
    .L2_LINES(32),
    .L2_WAYS(2),
    .L2_VB_LINES(2),
    .L2_VB_ENABLE(1'b0),
    .L2_WRITE_ALLOCATE(1'b1),
    .L2_WRITE_THROUGH_EN(1'b1),
    .L2_BG_DIRTY_FLUSH_EN(1'b1),
    .L2_PREFETCH_FILL_QOS_TH(3'd3),
    .L2_LOSSY_COMPRESS_EN(1'b0),
    .L2_COMP_SHIFT(4),
    .L2_COMP_ERR_CAP(8'd63),
    .L1_BYPASS_QOS_TH(3'd1),
    .L1_DEMAND_FILL_QOS_TH(3'd3),
    .L1_PREFETCH_FILL_QOS_TH(3'd4),
    .L1_MISS_BYPASS_QOS_TH(3'd7),
    .HIER_POLICY_EN(1'b1),
    .PF_ADAPT_EN(1'b0),
    .PF_QOS_TH(3'd2),
    .HBM_IF_Q_DEPTH(4),
    .HBM_IF_SERVICE_CYCLES(1),
    .KV_MAP_ENABLE(1'b1),
    .KV_BLOCK_OFF_BITS(1),
    .KV_DIR_ENTRIES(64),
    .KV_REAL_LAYOUT_EN(1'b1),
    .KV_TOKEN_BLOCK_BITS(4),
    .KV_TYPE_ADDR_BIT(-1),
    .KV_MAP_SCORE_REPL_EN(1'b1),
    .KV_MAP_SCORE_REPL_HW_WIN(2),
    .KV_MAP_SCORE_PROTECT_TH(4'd12),
    .KV_MAP_SCORE_DECAY_EN(1'b1),
    .KV_MAP_SCORE_DECAY_LOG2(5),
    .ATTN_SCHED_EN(1'b0),
    .AXIL_ADDR_W(AXIL_ADDR_W),
    .TRACE_DEPTH(TRACE_DEPTH),
    .RESP_DEPTH(RESP_DEPTH)
  ) u_kcmu_fpga_top (
    .*
  );
endmodule
