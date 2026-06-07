module kcmu_backend_ctrl #(
  parameter integer ADDR_W = 8,
  parameter integer DATA_W = 32,
  parameter integer Q_DEPTH = 4,
  parameter integer Q_W = (Q_DEPTH <= 1) ? 1 : $clog2(Q_DEPTH + 1),
  parameter integer CONGEST_TH = (Q_DEPTH <= 2) ? 1 : (Q_DEPTH / 2),
  parameter integer SERVICE_CYCLES = 2,
  parameter integer READ_COST = 1,
  parameter integer WRITE_COST = 2,
  parameter integer BURST_MERGE_CREDIT = 1,
  parameter integer BURST_MAX = 4,
  parameter integer WRITE_DRAIN_TH = (Q_DEPTH <= 2) ? 1 : (Q_DEPTH - 1),
  parameter integer SERVICE_ISSUE_MAX_WB = 1,
  parameter integer SERVICE_BACKLOG_WAIT_MAX = 1,
  parameter bit     SERVICE_ISSUE_WB_HOLD_EN = 1'b0,
  parameter integer SERVICE_ISSUE_WB_HOLD_CYCLES = 1,
  parameter bit     SERVICE_ISSUE_HOLD_WRITES_EN = 1'b0,
  parameter bit     SERVICE_BACKLOG_BOOST_EN = 1'b0
)(
  input  logic                 clk,
  input  logic                 rst_n,

  // request from L2
  input  logic                 req_re,
  input  logic [ADDR_W-1:0]    req_raddr,
  input  logic                 req_is_prefetch,
  input  logic                 req_is_group,
  input  logic                 req_service_issue_boost,
  input  logic                 req_we,
  input  logic [ADDR_W-1:0]    req_waddr,
  input  logic [DATA_W-1:0]    req_wdata,
  input  logic                 req_is_writeback,
  output logic                 req_re_ready,
  output logic                 req_we_ready,
  output logic [DATA_W-1:0]    resp_rdata,
  output logic                 resp_rvalid,

  // external memory side
  output logic                 mem_re,
  output logic [ADDR_W-1:0]    mem_raddr,
  input  logic [DATA_W-1:0]    mem_rdata,
  input  logic                 mem_rvalid,
  output logic                 mem_we,
  output logic [ADDR_W-1:0]    mem_waddr,
  output logic [DATA_W-1:0]    mem_wdata,
  output logic [Q_W-1:0]       q_level,
  output logic                 q_congested,
  output logic [Q_W-1:0]       backlog_level,
  output logic                 write_pressure,
  output logic                 prefetch_block,
  output logic [31:0]          stat_hbmif_burst_merge_cnt_o,
  output logic [31:0]          stat_hbmif_wr_drain_cycle_cnt_o,
  output logic [31:0]          stat_hbmif_ctrl_demand_rd_accept_cnt_o,
  output logic [31:0]          stat_hbmif_ctrl_prefetch_rd_accept_cnt_o,
  output logic [31:0]          stat_hbmif_ctrl_group_rd_accept_cnt_o,
  output logic [31:0]          stat_hbmif_ctrl_wr_accept_cnt_o,
  output logic [31:0]          stat_hbmif_ctrl_wb_accept_cnt_o,
  output logic [31:0]          stat_hbmif_ctrl_prefetch_drop_cnt_o
);
  logic prefetch_gate_q;
  logic prefetch_drop;

  logic [31:0] stat_hbmif_ctrl_demand_rd_accept_cnt;
  logic [31:0] stat_hbmif_ctrl_prefetch_rd_accept_cnt;
  logic [31:0] stat_hbmif_ctrl_group_rd_accept_cnt;
  logic [31:0] stat_hbmif_ctrl_wr_accept_cnt;
  logic [31:0] stat_hbmif_ctrl_wb_accept_cnt;
  logic [31:0] stat_hbmif_ctrl_prefetch_drop_cnt;
  logic [31:0] stat_hbmif_ctrl_service_issue_wb_hold_cnt;
  logic [31:0] stat_hbmif_ctrl_service_issue_wb_candidate_cnt;
  logic [31:0] stat_hbmif_ctrl_service_issue_wb_nopressure_cnt;
  logic [31:0] stat_hbmif_ctrl_service_issue_wr_hold_cnt;
  logic [31:0] stat_hbmif_ctrl_service_issue_wr_candidate_cnt;
  logic [31:0] stat_hbmif_ctrl_service_issue_wr_nopressure_cnt;
  logic base_req_ready;
  localparam integer SERVICE_ISSUE_WB_HOLD_CYCLES_SAFE =
    (SERVICE_ISSUE_WB_HOLD_CYCLES < 0) ? 0 : SERVICE_ISSUE_WB_HOLD_CYCLES;
  localparam integer SERVICE_ISSUE_HOLD_W =
    (SERVICE_ISSUE_WB_HOLD_CYCLES_SAFE <= 0) ? 1 : $clog2(SERVICE_ISSUE_WB_HOLD_CYCLES_SAFE + 1);
  logic [SERVICE_ISSUE_HOLD_W-1:0] service_issue_hold_ctr;
  logic service_issue_hold_seed;
  logic service_issue_hold_active;
  logic service_issue_wb_candidate;
  logic service_issue_wb_hold;
  logic service_issue_wr_candidate;
  logic service_issue_wr_hold;
  logic core_req_re;
  logic core_req_we;

  assign base_req_ready = (q_level < Q_DEPTH[Q_W-1:0]);
  assign service_issue_hold_seed =
    SERVICE_ISSUE_WB_HOLD_EN &&
    core_req_re &&
    !req_is_prefetch &&
    !req_is_group &&
    req_service_issue_boost;
  assign service_issue_hold_active = (service_issue_hold_ctr != {SERVICE_ISSUE_HOLD_W{1'b0}});
  assign service_issue_wb_candidate =
    base_req_ready &&
    req_we &&
    req_is_writeback &&
    ((req_re && !req_is_prefetch && !req_is_group && req_service_issue_boost) ||
     service_issue_hold_active);
  assign service_issue_wr_candidate =
    SERVICE_ISSUE_HOLD_WRITES_EN &&
    base_req_ready &&
    req_we &&
    !req_is_writeback &&
    ((req_re && !req_is_prefetch && !req_is_group && req_service_issue_boost) ||
     service_issue_hold_active);
  assign service_issue_wb_hold =
    SERVICE_ISSUE_WB_HOLD_EN &&
    service_issue_wb_candidate &&
    (write_pressure || q_congested || (backlog_level >= Q_W'(1)));
  assign service_issue_wr_hold =
    SERVICE_ISSUE_WB_HOLD_EN &&
    service_issue_wr_candidate &&
    (write_pressure || q_congested || (backlog_level >= Q_W'(1)));
  assign req_re_ready = base_req_ready;
  assign req_we_ready = base_req_ready && !service_issue_wb_hold && !service_issue_wr_hold;
  assign core_req_re = req_re && req_re_ready;
  assign core_req_we = req_we && req_we_ready;
  assign prefetch_drop = req_re && req_is_prefetch && prefetch_gate_q && !req_re_ready;
  assign stat_hbmif_ctrl_demand_rd_accept_cnt_o = stat_hbmif_ctrl_demand_rd_accept_cnt;
  assign stat_hbmif_ctrl_prefetch_rd_accept_cnt_o = stat_hbmif_ctrl_prefetch_rd_accept_cnt;
  assign stat_hbmif_ctrl_group_rd_accept_cnt_o = stat_hbmif_ctrl_group_rd_accept_cnt;
  assign stat_hbmif_ctrl_wr_accept_cnt_o = stat_hbmif_ctrl_wr_accept_cnt;
  assign stat_hbmif_ctrl_wb_accept_cnt_o = stat_hbmif_ctrl_wb_accept_cnt;
  assign stat_hbmif_ctrl_prefetch_drop_cnt_o = stat_hbmif_ctrl_prefetch_drop_cnt;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      prefetch_gate_q <= 1'b0;
      service_issue_hold_ctr <= {SERVICE_ISSUE_HOLD_W{1'b0}};
      stat_hbmif_ctrl_demand_rd_accept_cnt <= 32'd0;
      stat_hbmif_ctrl_prefetch_rd_accept_cnt <= 32'd0;
      stat_hbmif_ctrl_group_rd_accept_cnt <= 32'd0;
      stat_hbmif_ctrl_wr_accept_cnt <= 32'd0;
      stat_hbmif_ctrl_wb_accept_cnt <= 32'd0;
      stat_hbmif_ctrl_prefetch_drop_cnt <= 32'd0;
      stat_hbmif_ctrl_service_issue_wb_hold_cnt <= 32'd0;
      stat_hbmif_ctrl_service_issue_wb_candidate_cnt <= 32'd0;
      stat_hbmif_ctrl_service_issue_wb_nopressure_cnt <= 32'd0;
      stat_hbmif_ctrl_service_issue_wr_hold_cnt <= 32'd0;
      stat_hbmif_ctrl_service_issue_wr_candidate_cnt <= 32'd0;
      stat_hbmif_ctrl_service_issue_wr_nopressure_cnt <= 32'd0;
    end else begin
      prefetch_gate_q <= prefetch_block;
      if (service_issue_hold_seed) begin
        service_issue_hold_ctr <= SERVICE_ISSUE_HOLD_W'(SERVICE_ISSUE_WB_HOLD_CYCLES_SAFE);
      end else if (service_issue_hold_active) begin
        service_issue_hold_ctr <= service_issue_hold_ctr - SERVICE_ISSUE_HOLD_W'(1);
      end
      if (prefetch_drop) stat_hbmif_ctrl_prefetch_drop_cnt <= stat_hbmif_ctrl_prefetch_drop_cnt + 32'd1;
      if (core_req_re && !req_is_prefetch && !req_is_group) stat_hbmif_ctrl_demand_rd_accept_cnt <= stat_hbmif_ctrl_demand_rd_accept_cnt + 32'd1;
      if (core_req_re && req_is_prefetch) stat_hbmif_ctrl_prefetch_rd_accept_cnt <= stat_hbmif_ctrl_prefetch_rd_accept_cnt + 32'd1;
      if (core_req_re && req_is_group) stat_hbmif_ctrl_group_rd_accept_cnt <= stat_hbmif_ctrl_group_rd_accept_cnt + 32'd1;
      if (core_req_we && !req_is_writeback) stat_hbmif_ctrl_wr_accept_cnt <= stat_hbmif_ctrl_wr_accept_cnt + 32'd1;
      if (core_req_we && req_is_writeback) stat_hbmif_ctrl_wb_accept_cnt <= stat_hbmif_ctrl_wb_accept_cnt + 32'd1;
      if (service_issue_wb_hold) stat_hbmif_ctrl_service_issue_wb_hold_cnt <= stat_hbmif_ctrl_service_issue_wb_hold_cnt + 32'd1;
      if (service_issue_wb_candidate) stat_hbmif_ctrl_service_issue_wb_candidate_cnt <= stat_hbmif_ctrl_service_issue_wb_candidate_cnt + 32'd1;
      if (service_issue_wb_candidate && !service_issue_wb_hold) stat_hbmif_ctrl_service_issue_wb_nopressure_cnt <= stat_hbmif_ctrl_service_issue_wb_nopressure_cnt + 32'd1;
      if (service_issue_wr_hold) stat_hbmif_ctrl_service_issue_wr_hold_cnt <= stat_hbmif_ctrl_service_issue_wr_hold_cnt + 32'd1;
      if (service_issue_wr_candidate) stat_hbmif_ctrl_service_issue_wr_candidate_cnt <= stat_hbmif_ctrl_service_issue_wr_candidate_cnt + 32'd1;
      if (service_issue_wr_candidate && !service_issue_wr_hold) stat_hbmif_ctrl_service_issue_wr_nopressure_cnt <= stat_hbmif_ctrl_service_issue_wr_nopressure_cnt + 32'd1;
    end
  end

  kcmu_hbm_core #(
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W),
    .Q_DEPTH(Q_DEPTH),
    .Q_W(Q_W),
    .CONGEST_TH(CONGEST_TH),
    .SERVICE_CYCLES(SERVICE_CYCLES),
    .READ_COST(READ_COST),
    .WRITE_COST(WRITE_COST),
    .BURST_MERGE_CREDIT(BURST_MERGE_CREDIT),
    .BURST_MAX(BURST_MAX),
    .WRITE_DRAIN_TH(WRITE_DRAIN_TH),
    .SERVICE_ISSUE_MAX_WB(SERVICE_ISSUE_MAX_WB),
    .SERVICE_BACKLOG_WAIT_MAX(SERVICE_BACKLOG_WAIT_MAX),
    .SERVICE_BACKLOG_BOOST_EN(SERVICE_BACKLOG_BOOST_EN)
  ) u_core (
    .clk(clk),
    .rst_n(rst_n),
    .req_re(core_req_re),
    .req_raddr(req_raddr),
    .req_is_prefetch(req_is_prefetch),
    .req_service_issue_boost(req_service_issue_boost),
    .req_we(core_req_we),
    .req_waddr(req_waddr),
    .req_wdata(req_wdata),
    .req_is_writeback(req_is_writeback),
    .resp_rdata(resp_rdata),
    .resp_rvalid(resp_rvalid),
    .mem_re(mem_re),
    .mem_raddr(mem_raddr),
    .mem_rdata(mem_rdata),
    .mem_rvalid(mem_rvalid),
    .mem_we(mem_we),
    .mem_waddr(mem_waddr),
    .mem_wdata(mem_wdata),
    .q_level(q_level),
    .q_congested(q_congested),
    .backlog_level(backlog_level),
    .write_pressure(write_pressure),
    .prefetch_block(prefetch_block),
    .stat_hbmif_burst_merge_cnt_o(stat_hbmif_burst_merge_cnt_o),
    .stat_hbmif_wr_drain_cycle_cnt_o(stat_hbmif_wr_drain_cycle_cnt_o)
  );
endmodule
