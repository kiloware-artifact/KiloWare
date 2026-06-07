`timescale 1ns/1ps
// ------------------------------------------------------------
// kcmu_hbm_core.sv
// HBM-like backend service core.
// ------------------------------------------------------------
module kcmu_hbm_core #(
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
  parameter bit     SERVICE_BACKLOG_BOOST_EN = 1'b0
)(
  input  logic                 clk,
  input  logic                 rst_n,

  // request from L2
  input  logic                 req_re,
  input  logic [ADDR_W-1:0]    req_raddr,
  input  logic                 req_is_prefetch,
  input  logic                 req_service_issue_boost,
  input  logic                 req_we,
  input  logic [ADDR_W-1:0]    req_waddr,
  input  logic [DATA_W-1:0]    req_wdata,
  input  logic                 req_is_writeback,
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
  output logic [31:0]          stat_hbmif_wr_drain_cycle_cnt_o
);
  localparam integer SERVICE_CYCLES_SAFE = (SERVICE_CYCLES < 1) ? 1 : SERVICE_CYCLES;
  localparam integer RD_COST_SAFE = (READ_COST < 1) ? 1 : READ_COST;
  localparam integer WR_COST_SAFE = (WRITE_COST < 1) ? 1 : WRITE_COST;
  localparam integer MERGE_CREDIT_SAFE = (BURST_MERGE_CREDIT < 0) ? 0 : BURST_MERGE_CREDIT;
  localparam integer SERVICE_ISSUE_MAX_WB_SAFE =
    (SERVICE_ISSUE_MAX_WB < 0) ? 0 :
    ((SERVICE_ISSUE_MAX_WB > Q_DEPTH) ? Q_DEPTH : SERVICE_ISSUE_MAX_WB);
  localparam integer SERVICE_CNT_W = (SERVICE_CYCLES_SAFE <= 1) ? 1 : $clog2(SERVICE_CYCLES_SAFE);

  integer q_next;
  integer arrivals;
  integer service;
  integer burst_next;
  integer merge_credit;
  integer rd_arrivals;
  integer wr_arrivals;
  integer wb_arrivals;
  integer boost_rd_arrivals;
  integer rd_next;
  integer wr_next;
  integer wb_next;
  integer boosted_rd_next;
  logic [Q_W+1:0] total_q_est;

  logic [Q_W-1:0] rd_q_est;
  logic [Q_W-1:0] wr_q_est;
  logic [Q_W-1:0] wb_q_est;
  logic [Q_W-1:0] boosted_rd_q_est;
  logic [SERVICE_CNT_W-1:0] svc_wait_ctr;
  logic           req_valid_any;
  logic           req_single;
  logic           burst_merge;
  logic           last_req_valid;
  logic           last_req_we;
  logic           last_req_prefetch;
  logic           last_req_writeback;
  logic           rd_outstanding;
  logic           issue_re;
  logic           issue_we;
  logic           write_drain_mode;
  logic           service_grant;
  logic           service_rd;
  logic           service_wr;
  logic           service_wb;
  logic           service_wr_nominal;
  logic           service_wb_nominal;
  logic           service_issue_window;
  logic           service_issue_override;
  logic           service_backlog_window;
  logic           service_backlog_grant;
  logic [ADDR_W-1:0] last_req_addr;
  logic [2:0]     last_burst_len;

  // Stage-4 backend memory behavior core:
  // - queueing, burst merge, write drain, and backlog/congestion modeling
  // - no controller-side admission policy; that now lives in kcmu_backend_ctrl
  assign issue_re  = req_re;
  assign issue_we  = req_we;
  assign mem_re    = issue_re;
  assign mem_raddr = req_raddr;
  assign mem_we    = issue_we;
  assign mem_waddr = req_waddr;
  assign mem_wdata = req_wdata;
  assign resp_rdata = mem_rdata;
  assign resp_rvalid = mem_rvalid;
  assign total_q_est = rd_q_est + wr_q_est + wb_q_est;
  assign q_level = (total_q_est > Q_DEPTH) ? Q_W'(Q_DEPTH) : Q_W'(total_q_est);
  assign q_congested = (q_level >= Q_W'(CONGEST_TH));
  assign backlog_level = q_level;
  assign write_drain_mode = ((wr_q_est + wb_q_est) >= Q_W'(WRITE_DRAIN_TH));
  assign write_pressure = write_drain_mode || ((wr_q_est + wb_q_est) >= Q_W'(1));
  assign prefetch_block = q_congested || write_drain_mode || (wb_q_est >= Q_W'(1));
  assign service_backlog_window =
    SERVICE_BACKLOG_BOOST_EN &&
    (((boosted_rd_q_est != Q_W'(0)) && (rd_q_est != Q_W'(0))) ||
     (issue_re && req_service_issue_boost)) &&
    (write_pressure || issue_we) &&
    (svc_wait_ctr != SERVICE_CNT_W'(0)) &&
    (svc_wait_ctr <= SERVICE_CNT_W'(SERVICE_BACKLOG_WAIT_MAX)) &&
    (wb_q_est <= Q_W'(SERVICE_ISSUE_MAX_WB_SAFE));
  assign service_backlog_grant =
    service_backlog_window &&
    ((q_level != Q_W'(0)) || issue_re || issue_we);
  assign service_grant =
    ((svc_wait_ctr == {SERVICE_CNT_W{1'b0}}) || service_backlog_grant) &&
    (q_level != Q_W'(0));
  assign service_wb_nominal = service_grant && write_drain_mode && (wb_q_est != Q_W'(0));
  assign service_wr_nominal = service_grant &&
                              ((write_drain_mode && (wb_q_est == Q_W'(0)) && (wr_q_est != Q_W'(0))) ||
                               (!write_drain_mode && (rd_q_est == Q_W'(0)) && (wr_q_est != Q_W'(0))));
  assign service_issue_window =
    ((boosted_rd_q_est != Q_W'(0)) ||
     (issue_re && req_service_issue_boost)) &&
    write_pressure &&
    ((rd_q_est != Q_W'(0)) || issue_re) &&
    (wb_q_est <= Q_W'(SERVICE_ISSUE_MAX_WB_SAFE));
  assign service_issue_override =
    service_grant &&
    service_issue_window &&
    (service_wb_nominal || service_wr_nominal);
  assign service_wb = service_wb_nominal && !service_issue_override;
  assign service_wr = service_wr_nominal && !service_issue_override;
  assign service_rd =
    service_grant &&
    ((rd_q_est != Q_W'(0)) || issue_re) &&
    (service_issue_override || service_backlog_grant || (!service_wb_nominal && !service_wr_nominal));

  logic [31:0] stat_hbmif_burst_merge_cnt;
  logic [31:0] stat_hbmif_wr_drain_cycle_cnt;
  assign stat_hbmif_burst_merge_cnt_o = stat_hbmif_burst_merge_cnt;
  assign stat_hbmif_wr_drain_cycle_cnt_o = stat_hbmif_wr_drain_cycle_cnt;
`ifndef SYNTHESIS
  logic [31:0] stat_hbmif_demand_rd_req_cnt;
  logic [31:0] stat_hbmif_prefetch_rd_req_cnt;
  logic [31:0] stat_hbmif_rd_req_cnt;
  logic [31:0] stat_hbmif_wr_req_cnt;
  logic [31:0] stat_hbmif_writeback_wr_req_cnt;
  logic [31:0] stat_hbmif_conflict_cycle_cnt;
  logic [31:0] stat_hbmif_backlog_cycle_cnt;
  logic [31:0] stat_hbmif_congest_cycle_cnt;
  logic [31:0] stat_hbmif_q_peak;
  logic [31:0] stat_hbmif_rd_prio_cycle_cnt;
  logic [31:0] stat_hbmif_service_issue_boost_cnt;
  logic [31:0] stat_hbmif_service_issue_window_cnt;
  logic [31:0] stat_hbmif_service_issue_busy_cnt;
  logic [31:0] stat_hbmif_service_issue_rd_already_cnt;
  logic [31:0] stat_hbmif_service_issue_wr_nominal_cnt;
  logic [31:0] stat_hbmif_service_issue_wb_nominal_cnt;
  logic [31:0] stat_hbmif_service_issue_effective_cnt;
  logic [31:0] stat_hbmif_service_issue_wb_guard_cnt;
  logic [31:0] stat_hbmif_service_backlog_window_cnt;
  logic [31:0] stat_hbmif_service_backlog_effective_cnt;
  logic [31:0] stat_hbmif_service_backlog_boost_gate_cnt;
  logic [31:0] stat_hbmif_service_backlog_write_gate_cnt;
  logic [31:0] stat_hbmif_service_backlog_wait_gate_cnt;
  logic [31:0] stat_hbmif_service_backlog_wb_gate_cnt;
  logic [31:0] stat_hbmif_service_backlog_grant_gate_cnt;
  logic [31:0] stat_hbmif_service_backlog_wait0_cnt;
  logic [31:0] stat_hbmif_service_backlog_wait1_cnt;
  logic [31:0] stat_hbmif_service_backlog_wait2_cnt;
  logic [31:0] stat_hbmif_service_backlog_wait3p_cnt;
`endif

  assign req_valid_any = issue_re || issue_we;
  assign req_single = issue_re ^ issue_we;
  assign burst_merge =
    req_single &&
    last_req_valid &&
    (issue_we == last_req_we) &&
    ((!issue_re) || (req_is_prefetch == last_req_prefetch)) &&
    ((!issue_we) || (req_is_writeback == last_req_writeback)) &&
    (((issue_we ? req_waddr : req_raddr) == (last_req_addr + ADDR_W'(1)))) &&
    (last_burst_len < BURST_MAX);

  always @(posedge clk) begin
    if (!rst_n) begin
      rd_q_est <= {Q_W{1'b0}};
      wr_q_est <= {Q_W{1'b0}};
      wb_q_est <= {Q_W{1'b0}};
      boosted_rd_q_est <= {Q_W{1'b0}};
      svc_wait_ctr <= {SERVICE_CNT_W{1'b0}};
      last_req_valid <= 1'b0;
      last_req_we <= 1'b0;
      last_req_prefetch <= 1'b0;
      last_req_writeback <= 1'b0;
      rd_outstanding <= 1'b0;
      last_req_addr <= {ADDR_W{1'b0}};
      last_burst_len <= 3'd0;
`ifndef SYNTHESIS
      stat_hbmif_demand_rd_req_cnt <= 32'd0;
      stat_hbmif_prefetch_rd_req_cnt <= 32'd0;
      stat_hbmif_rd_req_cnt <= 32'd0;
      stat_hbmif_wr_req_cnt <= 32'd0;
      stat_hbmif_writeback_wr_req_cnt <= 32'd0;
      stat_hbmif_conflict_cycle_cnt <= 32'd0;
      stat_hbmif_backlog_cycle_cnt <= 32'd0;
      stat_hbmif_congest_cycle_cnt <= 32'd0;
      stat_hbmif_q_peak <= 32'd0;
      stat_hbmif_rd_prio_cycle_cnt <= 32'd0;
      stat_hbmif_service_issue_boost_cnt <= 32'd0;
      stat_hbmif_service_issue_window_cnt <= 32'd0;
      stat_hbmif_service_issue_busy_cnt <= 32'd0;
      stat_hbmif_service_issue_rd_already_cnt <= 32'd0;
      stat_hbmif_service_issue_wr_nominal_cnt <= 32'd0;
      stat_hbmif_service_issue_wb_nominal_cnt <= 32'd0;
      stat_hbmif_service_issue_effective_cnt <= 32'd0;
      stat_hbmif_service_issue_wb_guard_cnt <= 32'd0;
      stat_hbmif_service_backlog_window_cnt <= 32'd0;
      stat_hbmif_service_backlog_effective_cnt <= 32'd0;
      stat_hbmif_service_backlog_boost_gate_cnt <= 32'd0;
      stat_hbmif_service_backlog_write_gate_cnt <= 32'd0;
      stat_hbmif_service_backlog_wait_gate_cnt <= 32'd0;
      stat_hbmif_service_backlog_wb_gate_cnt <= 32'd0;
      stat_hbmif_service_backlog_grant_gate_cnt <= 32'd0;
      stat_hbmif_service_backlog_wait0_cnt <= 32'd0;
      stat_hbmif_service_backlog_wait1_cnt <= 32'd0;
      stat_hbmif_service_backlog_wait2_cnt <= 32'd0;
      stat_hbmif_service_backlog_wait3p_cnt <= 32'd0;
`endif
      stat_hbmif_burst_merge_cnt <= 32'd0;
      stat_hbmif_wr_drain_cycle_cnt <= 32'd0;
    end else begin
      rd_arrivals = issue_re ? RD_COST_SAFE : 0;
      wr_arrivals = (issue_we && !req_is_writeback) ? WR_COST_SAFE : 0;
      wb_arrivals = (issue_we && req_is_writeback) ? WR_COST_SAFE : 0;
      boost_rd_arrivals = (issue_re && req_service_issue_boost) ? RD_COST_SAFE : 0;
      arrivals = rd_arrivals + wr_arrivals + wb_arrivals;
      merge_credit = MERGE_CREDIT_SAFE;
      if (merge_credit > arrivals) begin
        merge_credit = arrivals;
      end
      if (burst_merge) begin
        arrivals = arrivals - merge_credit;
        if (rd_arrivals != 0) begin
          rd_arrivals = rd_arrivals - merge_credit;
          if (boost_rd_arrivals > merge_credit) begin
            boost_rd_arrivals = boost_rd_arrivals - merge_credit;
          end else begin
            boost_rd_arrivals = 0;
          end
        end else if (wb_arrivals != 0) begin
          wb_arrivals = wb_arrivals - merge_credit;
        end else if (wr_arrivals != 0) begin
          wr_arrivals = wr_arrivals - merge_credit;
        end
      end

      service = service_grant ? 1 : 0;
      q_next = q_level + arrivals - service;
      if (q_next > Q_DEPTH) q_next = Q_DEPTH;
      if (q_next < 0) q_next = 0;
      rd_next = rd_q_est + rd_arrivals - (service_rd ? 1 : 0);
      wr_next = wr_q_est + wr_arrivals - (service_wr ? 1 : 0);
      wb_next = wb_q_est + wb_arrivals - (service_wb ? 1 : 0);
      boosted_rd_next = boosted_rd_q_est + boost_rd_arrivals -
                        ((service_rd && (boosted_rd_q_est != Q_W'(0))) ? 1 : 0);
      if (rd_next > Q_DEPTH) rd_next = Q_DEPTH;
      if (rd_next < 0) rd_next = 0;
      if (wr_next > Q_DEPTH) wr_next = Q_DEPTH;
      if (wr_next < 0) wr_next = 0;
      if (wb_next > Q_DEPTH) wb_next = Q_DEPTH;
      if (wb_next < 0) wb_next = 0;
      if (boosted_rd_next > Q_DEPTH) boosted_rd_next = Q_DEPTH;
      if (boosted_rd_next < 0) boosted_rd_next = 0;
      rd_q_est <= Q_W'(rd_next);
      wr_q_est <= Q_W'(wr_next);
      wb_q_est <= Q_W'(wb_next);
      boosted_rd_q_est <= Q_W'(boosted_rd_next);

      if (service_grant) begin
        if (SERVICE_CYCLES_SAFE <= 1) begin
          svc_wait_ctr <= {SERVICE_CNT_W{1'b0}};
        end else begin
          svc_wait_ctr <= SERVICE_CNT_W'(SERVICE_CYCLES_SAFE - 1);
        end
      end else if (svc_wait_ctr != {SERVICE_CNT_W{1'b0}}) begin
        svc_wait_ctr <= svc_wait_ctr - SERVICE_CNT_W'(1);
      end

      if (issue_re) begin
        rd_outstanding <= 1'b1;
      end
      if (mem_rvalid) begin
        rd_outstanding <= 1'b0;
      end

      if (req_single) begin
        if (burst_merge) begin
          burst_next = last_burst_len + 1;
        end else begin
          burst_next = 1;
        end

        last_req_valid <= 1'b1;
        last_req_we <= issue_we;
        last_req_prefetch <= req_is_prefetch;
        last_req_writeback <= req_is_writeback;
        last_req_addr <= issue_we ? req_waddr : req_raddr;
        if (burst_next > BURST_MAX) begin
          last_burst_len <= BURST_MAX[2:0];
        end else begin
          last_burst_len <= burst_next[2:0];
        end
      end else if (req_valid_any) begin
        // Mixed read+write requests in the same cycle are not burst-merged.
        last_req_valid <= 1'b0;
        last_burst_len <= 3'd0;
      end else begin
        last_req_valid <= 1'b0;
        last_burst_len <= 3'd0;
      end
`ifndef SYNTHESIS
      if (issue_re && !req_is_prefetch) stat_hbmif_demand_rd_req_cnt <= stat_hbmif_demand_rd_req_cnt + 32'd1;
      if (issue_re && req_is_prefetch) stat_hbmif_prefetch_rd_req_cnt <= stat_hbmif_prefetch_rd_req_cnt + 32'd1;
      if (issue_re) stat_hbmif_rd_req_cnt <= stat_hbmif_rd_req_cnt + 32'd1;
      if (issue_we) stat_hbmif_wr_req_cnt <= stat_hbmif_wr_req_cnt + 32'd1;
      if (issue_we && req_is_writeback) stat_hbmif_writeback_wr_req_cnt <= stat_hbmif_writeback_wr_req_cnt + 32'd1;
      if (issue_re && issue_we) stat_hbmif_conflict_cycle_cnt <= stat_hbmif_conflict_cycle_cnt + 32'd1;
      if ((q_level + Q_W'(arrivals)) > 1) stat_hbmif_backlog_cycle_cnt <= stat_hbmif_backlog_cycle_cnt + 32'd1;
      if (q_congested) stat_hbmif_congest_cycle_cnt <= stat_hbmif_congest_cycle_cnt + 32'd1;
      if (q_next > stat_hbmif_q_peak) stat_hbmif_q_peak <= q_next;
`endif
      if (burst_merge) stat_hbmif_burst_merge_cnt <= stat_hbmif_burst_merge_cnt + 32'd1;
      if (write_drain_mode && (issue_we || service_wb || service_wr)) begin
        stat_hbmif_wr_drain_cycle_cnt <= stat_hbmif_wr_drain_cycle_cnt + 32'd1;
      end
`ifndef SYNTHESIS
      if (!write_drain_mode && (issue_re || service_rd)) begin
        stat_hbmif_rd_prio_cycle_cnt <= stat_hbmif_rd_prio_cycle_cnt + 32'd1;
      end
      if (issue_re && req_service_issue_boost) begin
        stat_hbmif_service_issue_boost_cnt <= stat_hbmif_service_issue_boost_cnt + 32'd1;
      end
      if (service_issue_window) begin
        stat_hbmif_service_issue_window_cnt <= stat_hbmif_service_issue_window_cnt + 32'd1;
      end
      if (service_issue_window && !service_grant) begin
        stat_hbmif_service_issue_busy_cnt <= stat_hbmif_service_issue_busy_cnt + 32'd1;
      end
      if (service_issue_window && service_grant && service_wb_nominal) begin
        stat_hbmif_service_issue_wb_nominal_cnt <= stat_hbmif_service_issue_wb_nominal_cnt + 32'd1;
      end
      if (service_issue_window && service_grant && service_wr_nominal) begin
        stat_hbmif_service_issue_wr_nominal_cnt <= stat_hbmif_service_issue_wr_nominal_cnt + 32'd1;
      end
      if (service_issue_window && service_grant &&
          !service_wb_nominal && !service_wr_nominal &&
          ((rd_q_est != Q_W'(0)) || issue_re)) begin
        stat_hbmif_service_issue_rd_already_cnt <= stat_hbmif_service_issue_rd_already_cnt + 32'd1;
      end
      if (service_issue_override) begin
        stat_hbmif_service_issue_effective_cnt <= stat_hbmif_service_issue_effective_cnt + 32'd1;
      end
      if (service_grant &&
          (boosted_rd_q_est != Q_W'(0)) &&
          write_pressure &&
          (rd_q_est != Q_W'(0)) &&
          (wb_q_est > Q_W'(SERVICE_ISSUE_MAX_WB_SAFE))) begin
        stat_hbmif_service_issue_wb_guard_cnt <= stat_hbmif_service_issue_wb_guard_cnt + 32'd1;
      end
      if (service_backlog_window) begin
        stat_hbmif_service_backlog_window_cnt <= stat_hbmif_service_backlog_window_cnt + 32'd1;
      end
      if (service_backlog_grant) begin
        stat_hbmif_service_backlog_effective_cnt <= stat_hbmif_service_backlog_effective_cnt + 32'd1;
      end
      if (SERVICE_BACKLOG_BOOST_EN &&
          ((((boosted_rd_q_est != Q_W'(0)) && (rd_q_est != Q_W'(0))) ||
            (issue_re && req_service_issue_boost)))) begin
        stat_hbmif_service_backlog_boost_gate_cnt <= stat_hbmif_service_backlog_boost_gate_cnt + 32'd1;
        if (svc_wait_ctr == SERVICE_CNT_W'(0)) begin
          stat_hbmif_service_backlog_wait0_cnt <= stat_hbmif_service_backlog_wait0_cnt + 32'd1;
        end else if (svc_wait_ctr == SERVICE_CNT_W'(1)) begin
          stat_hbmif_service_backlog_wait1_cnt <= stat_hbmif_service_backlog_wait1_cnt + 32'd1;
        end else if (svc_wait_ctr == SERVICE_CNT_W'(2)) begin
          stat_hbmif_service_backlog_wait2_cnt <= stat_hbmif_service_backlog_wait2_cnt + 32'd1;
        end else begin
          stat_hbmif_service_backlog_wait3p_cnt <= stat_hbmif_service_backlog_wait3p_cnt + 32'd1;
        end
      end
      if (SERVICE_BACKLOG_BOOST_EN &&
          ((((boosted_rd_q_est != Q_W'(0)) && (rd_q_est != Q_W'(0))) ||
            (issue_re && req_service_issue_boost))) &&
          (write_pressure || issue_we)) begin
        stat_hbmif_service_backlog_write_gate_cnt <= stat_hbmif_service_backlog_write_gate_cnt + 32'd1;
      end
      if (SERVICE_BACKLOG_BOOST_EN &&
          ((((boosted_rd_q_est != Q_W'(0)) && (rd_q_est != Q_W'(0))) ||
            (issue_re && req_service_issue_boost))) &&
          (write_pressure || issue_we) &&
          (svc_wait_ctr != SERVICE_CNT_W'(0)) &&
          (svc_wait_ctr <= SERVICE_CNT_W'(SERVICE_BACKLOG_WAIT_MAX))) begin
        stat_hbmif_service_backlog_wait_gate_cnt <= stat_hbmif_service_backlog_wait_gate_cnt + 32'd1;
      end
      if (SERVICE_BACKLOG_BOOST_EN &&
          ((((boosted_rd_q_est != Q_W'(0)) && (rd_q_est != Q_W'(0))) ||
            (issue_re && req_service_issue_boost))) &&
          (write_pressure || issue_we) &&
          (svc_wait_ctr != SERVICE_CNT_W'(0)) &&
          (svc_wait_ctr <= SERVICE_CNT_W'(SERVICE_BACKLOG_WAIT_MAX)) &&
          (wb_q_est <= Q_W'(SERVICE_ISSUE_MAX_WB_SAFE))) begin
        stat_hbmif_service_backlog_wb_gate_cnt <= stat_hbmif_service_backlog_wb_gate_cnt + 32'd1;
      end
      if (service_backlog_grant) begin
        stat_hbmif_service_backlog_grant_gate_cnt <= stat_hbmif_service_backlog_grant_gate_cnt + 32'd1;
      end
`endif
    end
  end
endmodule

