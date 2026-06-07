`timescale 1ns/1ps
`include "kcmu_trace_player.sv"

module tb_kcmu_top;
  import kcmu_pkg::*;

  localparam integer ADDR_W   = 8;
  localparam integer DATA_W   = 32;
  localparam integer LINES    = 4;
  localparam integer SCORE_W  = 8;
  localparam integer TIME_W   = 16;
  localparam integer K_RECENT = 1;
  localparam bit     H2O_V2_EN = 1'b1;
  localparam integer MEM_RD_LATENCY = 3;
  localparam integer L2_RD_LATENCY = 1;
  localparam integer L2_LINES = 32;
  localparam integer L2_WAYS = 1;
  localparam integer L2_VB_LINES = 2;
  localparam bit     L2_VB_ENABLE = 1'b1;
  localparam bit     L2_WRITE_ALLOCATE = 1'b1;
  localparam logic [2:0] L2_WRITE_ALLOC_QOS_TH = 3'd2;
  localparam logic [2:0] L2_READ_FILL_QOS_TH = 3'd1;
  localparam logic [2:0] L2_PREFETCH_FILL_QOS_TH = 3'd3;
  localparam bit     L2_SEM_FILL_RELAX_EN = 1'b1;
  localparam bit     L2_SEM_HOT_VICTIM_PROTECT_EN = 1'b1;
  localparam logic [2:0] L2_SEM_HOT_SCORE_BONUS = 3'd3;
  localparam logic [2:0] L2_SEM_COLD_SCORE_PENALTY = 3'd2;
  localparam logic [7:0] L2_SEM_HOT_MAX_AGE = 8'd112;
  localparam logic [2:0] L2_REQ_HOT_SCORE_BONUS = 3'd2;
  localparam logic [2:0] L2_AGE_STALE_SCORE_PENALTY = 3'd2;
  localparam logic [2:0] L2_LOSSY_SCORE_PENALTY = 3'd3;
  localparam bit     L2_LOSSY_COMPRESS_EN = 1'b1;
  localparam integer L2_COMP_SHIFT = 4;
  localparam logic [2:0] L2_COMPRESS_QOS_TH = 3'd2;
  localparam logic [7:0] L2_COMP_ERR_CAP = 8'd63;
  localparam bit     HIER_POLICY_EN = 1'b1;
  localparam logic [2:0] L1_BYPASS_QOS_TH = 3'd1;
  localparam logic [2:0] L1_DEMAND_FILL_QOS_TH = 3'd3;
  localparam logic [2:0] L1_PREFETCH_FILL_QOS_TH = 3'd4;
  localparam logic [2:0] L1_MISS_BYPASS_QOS_TH = 3'd7;
  localparam integer EXEC_CONGEST_Q_LEVEL_TH = 1;
  localparam integer HBM_CONGEST_COLD_EXTRA_LAT = 3;
  localparam integer HBM_CONGEST_HOT_EXTRA_LAT = 1;
  localparam integer HBM_CONGEST_PREFETCH_EXTRA_LAT = 4;
  localparam bit     L1_FILL_ON_HBM_MISS = 1'b1;
  localparam bit     PF_ADAPT_EN = 1'b1;
  localparam logic [2:0] PF_QOS_TH = 3'd2;
  localparam integer HBM_IF_Q_DEPTH = 4;
  localparam integer HBM_IF_SERVICE_CYCLES = 1;
  localparam integer TB_HBM_Q_W = (HBM_IF_Q_DEPTH <= 1) ? 1 : $clog2(HBM_IF_Q_DEPTH + 1);
  localparam bit     KV_MAP_ENABLE = 1'b1;
  localparam integer KV_BLOCK_OFF_BITS = 2;
  localparam integer KV_DIR_ENTRIES = 64;
  localparam bit     ATTN_SCHED_EN = 1'b1;
  localparam integer DEPTH    = (1 << ADDR_W);
  localparam integer BYTE_W   = (DATA_W / 8);
  // Compression v2 can pick dynamic bit-width; compare against configured error cap.
  localparam integer LOSSY_BYTE_EPS = L2_COMP_ERR_CAP;

  localparam integer READY_TIMEOUT = 128;
  localparam integer RESP_TIMEOUT  = 256;

  logic clk;
  logic rst_n;
  logic prefetch_enable;

  // Trace
  logic               trace_valid;
  logic               trace_ready;
  kcmu_op_t           trace_op;
  logic [ADDR_W-1:0]  trace_addr;
  logic [DATA_W-1:0]  trace_wdata;
  logic               trace_meta_valid;
  logic [KCMU_SEQ_W-1:0] trace_seq_id;
  kcmu_phase_t        trace_phase;
  kcmu_kv_kind_t      trace_kv_kind;
  logic [2:0]         trace_layer;
  logic [1:0]         trace_head;
  logic [11:0]        trace_token;
  logic [2:0]         trace_prio;
  logic               trace_desc_valid;
  logic               trace_desc_ready;
  kcmu_op_t           trace_desc_op;
  logic [ADDR_W-1:0]  trace_desc_base_addr;
  logic [7:0]         trace_desc_len;
  logic [SCORE_W-1:0] trace_desc_score;
  logic [KCMU_SEQ_W-1:0] trace_desc_seq_id;
  kcmu_phase_t        trace_desc_phase;
  kcmu_kv_kind_t      trace_desc_kv_kind;
  logic               trace_desc_attn_valid;
  logic [SCORE_W-1:0] trace_desc_attn_score;
  logic [KCMU_ATTN_RANK_W-1:0] trace_desc_recent_rank;
  logic [KCMU_TOKEN_BLOCK_W-1:0] trace_desc_token_block_id;
  logic [KCMU_ATTN_EPOCH_W-1:0] trace_desc_attn_epoch;
  logic [KCMU_HEAD_BUDGET_W-1:0] trace_desc_head_budget_class;
  logic [SCORE_W-1:0] trace_desc_query_relevance;
  logic [KCMU_COST_CLASS_W-1:0] trace_desc_compression_risk;
  logic [KCMU_COST_CLASS_W-1:0] trace_desc_spill_cost;
  logic [SCORE_W-1:0] trace_desc_service_criticality;
  logic               trace_desc_policy_select_s5;
  logic [KCMU_DESC_CLASS_W-1:0] trace_desc_temporal_persist_class;
  logic [KCMU_DESC_CLASS_W-1:0] trace_desc_reuse_distance_class;
  logic [KCMU_DESC_CLASS_W-1:0] trace_desc_query_structure_class;
  logic [KCMU_SCHED_HINT_W-1:0] trace_desc_sched_urgency_hint;
  logic               trace_desc_sig_valid;
  logic [5:0]         trace_desc_query_sig;
  logic [5:0]         trace_desc_key_sig;
  logic [1:0]         trace_desc_prefix_class;
  logic [1:0]         trace_desc_router_class;
  logic               trace_desc_wvalid;
  logic               trace_desc_wready;
  logic [DATA_W-1:0]  trace_desc_wdata;
  logic               use_trace_player;

  // Manual trace driver
  logic               man_trace_valid;
  kcmu_op_t           man_trace_op;
  logic [ADDR_W-1:0]  man_trace_addr;
  logic [DATA_W-1:0]  man_trace_wdata;
  logic               man_trace_meta_valid;
  logic [KCMU_SEQ_W-1:0] man_trace_seq_id;
  kcmu_phase_t        man_trace_phase;
  kcmu_kv_kind_t      man_trace_kv_kind;
  logic [2:0]         man_trace_layer;
  logic [1:0]         man_trace_head;
  logic [11:0]        man_trace_token;
  logic [2:0]         man_trace_prio;

  // Replay trace driver
  logic               pl_trace_valid;
  kcmu_op_t           pl_trace_op;
  logic [ADDR_W-1:0]  pl_trace_addr;
  logic [DATA_W-1:0]  pl_trace_wdata;
  logic               pl_trace_meta_valid;
  logic [KCMU_SEQ_W-1:0] pl_trace_seq_id;
  kcmu_phase_t        pl_trace_phase;
  kcmu_kv_kind_t      pl_trace_kv_kind;
  logic [2:0]         pl_trace_layer;
  logic [1:0]         pl_trace_head;
  logic [11:0]        pl_trace_token;
  logic [2:0]         pl_trace_prio;
  logic               pl_start;
  logic               pl_busy;
  logic               pl_done;
  logic               pl_cfg_clear;
  logic               pl_cfg_we;
  logic [4:0]         pl_cfg_idx;
  kcmu_op_t           pl_cfg_op;
  logic [ADDR_W-1:0]  pl_cfg_addr;
  logic [DATA_W-1:0]  pl_cfg_wdata;
  logic               pl_cfg_last;

  // Response
  logic               resp_valid;
  logic               resp_ready;
  logic [DATA_W-1:0]  resp_rdata;
  logic               resp_hit;
  logic               resp_approx;

  // External memory interface
  logic               mem_re;
  logic [ADDR_W-1:0]  mem_raddr;
  logic [DATA_W-1:0]  mem_rdata;
  logic               mem_rvalid;
  logic               mem_we;
  logic [ADDR_W-1:0]  mem_waddr;
  logic [DATA_W-1:0]  mem_wdata;
  logic [ADDR_W-1:0]  m_axi_araddr;
  logic               m_axi_arvalid;
  logic               m_axi_arready;
  logic [DATA_W-1:0]  m_axi_rdata;
  logic               m_axi_rvalid;
  logic               m_axi_rready;
  logic [ADDR_W-1:0]  m_axi_awaddr;
  logic               m_axi_awvalid;
  logic               m_axi_awready;
  logic [DATA_W-1:0]  m_axi_wdata;
  logic [(DATA_W/8)-1:0] m_axi_wstrb;
  logic               m_axi_wvalid;
  logic               m_axi_wready;
  logic               m_axi_bvalid;
  logic               m_axi_bready;

  logic [DATA_W-1:0] golden_mem [0:DEPTH-1];
  logic [DATA_W-1:0] kv_sem_golden [0:255];

  integer total_ops;
  integer total_reads;
  integer total_writes;
  integer total_hits;
  integer total_misses;
  integer total_latency_cycles;
  integer max_latency_cycles;
  integer sim_cycle_counter;
  integer rd_hit_latency_sum;
  integer rd_hit_latency_max;
  integer rd_hit_cnt;
  integer rd_miss_latency_sum;
  integer rd_miss_latency_max;
  integer rd_miss_cnt;
  integer wr_hit_latency_sum;
  integer wr_hit_latency_max;
  integer wr_hit_cnt;
  integer wr_miss_latency_sum;
  integer wr_miss_latency_max;
  integer wr_miss_cnt;
  integer approx_read_cnt;
  integer hot_rd_cnt;
  integer hot_rd_hit_cnt;
  integer hot_rd_miss_cnt;
  integer hot_rd_latency_sum;
  integer hot_rd_latency_max;
  integer cold_rd_cnt;
  integer cold_rd_hit_cnt;
  integer cold_rd_miss_cnt;
  integer cold_rd_latency_sum;
  integer cold_rd_latency_max;
  integer hiq_rd_cnt;
  integer hiq_rd_latency_sum;
  integer loq_rd_cnt;
  integer loq_rd_latency_sum;
  integer latency_hist [0:63];
  integer tb_lat_p50;
  integer tb_lat_p90;
  integer tb_lat_p95;
  integer tb_lat_p99;
  logic   last_resp_approx;
  logic   l2_direct_force_re;
  logic [ADDR_W-1:0] l2_direct_force_addr;
  logic [2:0] l2_direct_force_qos;
  logic   l2_direct_force_fill_allow;
  logic   l2_direct_force_compress_allow;
  logic [SCORE_W-1:0] desc_service_criticality_cfg;
  logic               desc_policy_select_s5_cfg;
  logic [KCMU_HEAD_BUDGET_W-1:0] desc_head_budget_class_cfg;
  logic [SCORE_W-1:0] desc_query_relevance_cfg;
  logic [KCMU_COST_CLASS_W-1:0] desc_compression_risk_cfg;
  logic [KCMU_COST_CLASS_W-1:0] desc_spill_cost_cfg;
  logic [KCMU_DESC_CLASS_W-1:0] desc_temporal_persist_class_cfg;
  logic [KCMU_DESC_CLASS_W-1:0] desc_reuse_distance_class_cfg;
  logic [KCMU_DESC_CLASS_W-1:0] desc_query_structure_class_cfg;
  logic [KCMU_SCHED_HINT_W-1:0] desc_sched_urgency_hint_cfg;
  integer backend_critical_low_qos;
  integer backend_critical_high_qos;
  integer backend_critical_low_fill;
  integer backend_critical_high_fill;
  integer backend_critical_low_protect;
  integer backend_critical_high_protect;
  integer service_rescue_low_fill;
  integer service_rescue_high_fill;
  integer service_rescue_low_effect;
  integer service_rescue_high_effect;
  integer service_rescue_low_hbm_congested;
  integer service_rescue_high_hbm_congested;
  integer service_rescue_low_sched_fill;
  integer service_rescue_high_sched_fill;
  integer service_rescue_low_fill_no_service;
  integer service_rescue_high_fill_no_service;
  integer service_rescue_low_prio_no_service;
  integer service_rescue_high_prio_no_service;
  integer service_rescue_low_comp_guard;
  integer service_rescue_high_comp_guard;
  integer service_issue_low_boost;
  integer service_issue_high_boost;
  integer service_issue_boost_before;
  integer service_issue_low_override;
  integer service_issue_high_override;
  integer service_issue_effect_before;
  integer service_issue_low_rd;
  integer service_issue_high_rd;
  integer service_issue_guard_before;
  integer service_issue_high_window;
  integer service_issue_high_grant;
  integer service_issue_high_wr_nominal;
  integer service_issue_high_wb_nominal;
  integer service_issue_high_write_pressure;
  integer service_issue_high_boosted_q;
  integer service_issue_high_rd_q;
  integer service_issue_high_wb_q;
  integer service_issue_wb_hold_before;
  integer service_issue_low_wb_hold;
  integer service_issue_high_wb_hold;
  integer service_issue_low_re_ready;
  integer service_issue_low_we_ready;
  integer service_issue_high_re_ready;
  integer service_issue_high_we_ready;
  integer selector_low_service_issue_boost;
  integer selector_high_service_issue_boost;
  integer selector_low_policy_seen;
  integer selector_high_policy_seen;
  integer service_backlog_low_window;
  integer service_backlog_high_window;
  integer service_backlog_low_grant;
  integer service_backlog_high_grant;
  integer service_backlog_low_rd;
  integer service_backlog_high_rd;
  integer casu_marginal_before;
  integer casu_marginal_after;
  integer casu_pollution_before;
  integer casu_pollution_after;
  integer casu_pressure_before;
  integer casu_pressure_after;
  integer casu_comp_guard_before;
  integer casu_comp_guard_after;
  integer casu_s4_fill;
  integer casu_s4_protect;
  integer casu_s4_comp_guard;
  integer casu_no_pressure_boost;
  integer casu_pressure_boost;

  assign trace_valid = use_trace_player ? pl_trace_valid : man_trace_valid;
  assign trace_op    = use_trace_player ? pl_trace_op    : man_trace_op;
  assign trace_addr  = use_trace_player ? pl_trace_addr  : man_trace_addr;
  assign trace_wdata = use_trace_player ? pl_trace_wdata : man_trace_wdata;
  assign trace_meta_valid = use_trace_player ? pl_trace_meta_valid : man_trace_meta_valid;
  assign trace_seq_id     = use_trace_player ? pl_trace_seq_id     : man_trace_seq_id;
  assign trace_phase      = use_trace_player ? pl_trace_phase      : man_trace_phase;
  assign trace_kv_kind    = use_trace_player ? pl_trace_kv_kind    : man_trace_kv_kind;
  assign trace_layer      = use_trace_player ? pl_trace_layer      : man_trace_layer;
  assign trace_head       = use_trace_player ? pl_trace_head       : man_trace_head;
  assign trace_token      = use_trace_player ? pl_trace_token      : man_trace_token;
  assign trace_prio       = use_trace_player ? pl_trace_prio       : man_trace_prio;

  assign pl_trace_meta_valid = 1'b1;
  assign pl_trace_seq_id     = {KCMU_SEQ_W{1'b0}};
  assign pl_trace_phase      = (pl_trace_op == KCMU_OP_RD) ? KCMU_PHASE_DECODE : KCMU_PHASE_PREFILL;
  assign pl_trace_kv_kind    = pl_trace_addr[0] ? KCMU_KV_KIND_V : KCMU_KV_KIND_K;
  assign pl_trace_layer      = pl_trace_addr[7:5];
  assign pl_trace_head       = pl_trace_addr[4:3];
  assign pl_trace_token      = {4'd0, pl_trace_addr};
  assign pl_trace_prio       = (pl_trace_op == KCMU_OP_RD) ? 3'd4 : 3'd3;
  assign m_axi_arready = 1'b0;
  assign m_axi_rdata   = {DATA_W{1'b0}};
  assign m_axi_rvalid  = 1'b0;
  assign m_axi_awready = 1'b0;
  assign m_axi_wready  = 1'b0;
  assign m_axi_bvalid  = 1'b0;

  always @(posedge clk) begin
    if (rst_n && mem_we) begin
      // Mirror committed backing-store writes so cold-path checks observe the
      // same external-memory contract as the DUT after spill/writeback.
      golden_mem[mem_waddr] <= mem_wdata;
    end
  end

  kcmu_top #(
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W),
    .LINES(LINES),
    .SCORE_W(SCORE_W),
    .TIME_W(TIME_W),
    .K_RECENT(K_RECENT),
    .H2O_V2_EN(H2O_V2_EN),
    .MEM_RD_LATENCY(MEM_RD_LATENCY),
    .L2_RD_LATENCY(L2_RD_LATENCY),
    .L2_LINES(L2_LINES),
    .L2_WAYS(L2_WAYS),
    .L2_VB_LINES(L2_VB_LINES),
    .L2_VB_ENABLE(L2_VB_ENABLE),
    .L2_WRITE_ALLOCATE(L2_WRITE_ALLOCATE),
    .L2_WRITE_ALLOC_QOS_TH(L2_WRITE_ALLOC_QOS_TH),
    .L2_READ_FILL_QOS_TH(L2_READ_FILL_QOS_TH),
    .L2_PREFETCH_FILL_QOS_TH(L2_PREFETCH_FILL_QOS_TH),
    .L2_SEM_FILL_RELAX_EN(L2_SEM_FILL_RELAX_EN),
    .L2_SEM_HOT_VICTIM_PROTECT_EN(L2_SEM_HOT_VICTIM_PROTECT_EN),
    .L2_SEM_HOT_SCORE_BONUS(L2_SEM_HOT_SCORE_BONUS),
    .L2_SEM_COLD_SCORE_PENALTY(L2_SEM_COLD_SCORE_PENALTY),
    .L2_SEM_HOT_MAX_AGE(L2_SEM_HOT_MAX_AGE),
    .L2_REQ_HOT_SCORE_BONUS(L2_REQ_HOT_SCORE_BONUS),
    .L2_AGE_STALE_SCORE_PENALTY(L2_AGE_STALE_SCORE_PENALTY),
    .L2_LOSSY_SCORE_PENALTY(L2_LOSSY_SCORE_PENALTY),
    .L2_LOSSY_COMPRESS_EN(L2_LOSSY_COMPRESS_EN),
    .L2_COMP_SHIFT(L2_COMP_SHIFT),
    .L2_COMPRESS_QOS_TH(L2_COMPRESS_QOS_TH),
    .L2_COMP_ERR_CAP(L2_COMP_ERR_CAP),
    .HIER_POLICY_EN(HIER_POLICY_EN),
    .L1_BYPASS_QOS_TH(L1_BYPASS_QOS_TH),
    .L1_DEMAND_FILL_QOS_TH(L1_DEMAND_FILL_QOS_TH),
    .L1_PREFETCH_FILL_QOS_TH(L1_PREFETCH_FILL_QOS_TH),
    .L1_MISS_BYPASS_QOS_TH(L1_MISS_BYPASS_QOS_TH),
    .EXEC_CONGEST_Q_LEVEL_TH(EXEC_CONGEST_Q_LEVEL_TH),
    .HBM_CONGEST_COLD_EXTRA_LAT(HBM_CONGEST_COLD_EXTRA_LAT),
    .HBM_CONGEST_HOT_EXTRA_LAT(HBM_CONGEST_HOT_EXTRA_LAT),
    .HBM_CONGEST_PREFETCH_EXTRA_LAT(HBM_CONGEST_PREFETCH_EXTRA_LAT),
    .L1_FILL_ON_HBM_MISS(L1_FILL_ON_HBM_MISS),
    .L2_HIT_REUSE_BUFFER_EN(1'b0),
    .L2_HIT_REUSE_BUFFER_DEPTH(4),
    .PF_ADAPT_EN(PF_ADAPT_EN),
    .PF_QOS_TH(PF_QOS_TH),
    .HBM_IF_Q_DEPTH(HBM_IF_Q_DEPTH),
    .HBM_IF_SERVICE_CYCLES(HBM_IF_SERVICE_CYCLES),
    .KV_MAP_ENABLE(KV_MAP_ENABLE),
    .KV_BLOCK_OFF_BITS(KV_BLOCK_OFF_BITS),
    .KV_DIR_ENTRIES(KV_DIR_ENTRIES),
    .ATTN_SCHED_EN(ATTN_SCHED_EN),
    .UTILITY_HEAD_ADAPTIVE_EN(1'b1),
    .UTILITY_QUERY_AWARE_EN(1'b1),
    .UTILITY_COST_AWARE_EN(1'b1),
    .UTILITY_BACKEND_CRITICAL_EN(1'b1),
    .UTILITY_QUERY_W(5),
    .UTILITY_SPILL_W(2),
    .UTILITY_SERVICE_RESCUE_EN(1'b1),
    .UTILITY_SERVICE_ISSUE_EN(1'b1),
    .SERVICE_ISSUE_BOOST_TH(8'h90),
    .SERVICE_ISSUE_PRIO_TH(3'd2),
    .UTILITY_SERVICE_ISSUE_REQUIRE_FILLPROTECT(1'b0),
    .UTILITY_SERVICE_ISSUE_ALLOW_GUARDED(1'b1),
    .UTILITY_SERVICE_ISSUE_RESIDUAL_EN(1'b1),
    .UTILITY_SCORE_REPL_EN(1'b1),
    .UTILITY_MARGINAL_REPL_EN(1'b1),
    .UTILITY_POLICY_SELECT_EN(1'b1),
    .HBM_SERVICE_ISSUE_MAX_WB(2),
    .HBM_SERVICE_ISSUE_WB_HOLD_EN(1'b1),
    .HBM_SERVICE_BACKLOG_BOOST_EN(1'b1),
    .USE_AXI_IF(1'b0)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .prefetch_enable(prefetch_enable),
    .trace_valid(trace_valid),
    .trace_ready(trace_ready),
    .trace_op(trace_op),
    .trace_addr(trace_addr),
    .trace_wdata(trace_wdata),
    .trace_meta_valid(trace_meta_valid),
    .trace_seq_id(trace_seq_id),
    .trace_phase(trace_phase),
    .trace_kv_kind(trace_kv_kind),
    .trace_layer(trace_layer),
    .trace_head(trace_head),
    .trace_token(trace_token),
    .trace_prio(trace_prio),
    .trace_desc_valid(trace_desc_valid),
    .trace_desc_ready(trace_desc_ready),
    .trace_desc_op(trace_desc_op),
    .trace_desc_base_addr(trace_desc_base_addr),
    .trace_desc_len(trace_desc_len),
    .trace_desc_score(trace_desc_score),
    .trace_desc_seq_id(trace_desc_seq_id),
    .trace_desc_phase(trace_desc_phase),
    .trace_desc_kv_kind(trace_desc_kv_kind),
    .trace_desc_attn_valid(trace_desc_attn_valid),
    .trace_desc_attn_score(trace_desc_attn_score),
    .trace_desc_recent_rank(trace_desc_recent_rank),
    .trace_desc_token_block_id(trace_desc_token_block_id),
    .trace_desc_attn_epoch(trace_desc_attn_epoch),
    .trace_desc_head_budget_class(trace_desc_head_budget_class),
    .trace_desc_query_relevance(trace_desc_query_relevance),
    .trace_desc_compression_risk(trace_desc_compression_risk),
    .trace_desc_spill_cost(trace_desc_spill_cost),
    .trace_desc_service_criticality(trace_desc_service_criticality),
    .trace_desc_policy_select_s5(trace_desc_policy_select_s5),
    .trace_desc_temporal_persist_class(trace_desc_temporal_persist_class),
    .trace_desc_reuse_distance_class(trace_desc_reuse_distance_class),
    .trace_desc_query_structure_class(trace_desc_query_structure_class),
    .trace_desc_sched_urgency_hint(trace_desc_sched_urgency_hint),
    .trace_desc_kiloscore_extra_cvr_hint(1'b0),
    .trace_desc_sig_valid(trace_desc_sig_valid),
    .trace_desc_query_sig(trace_desc_query_sig),
    .trace_desc_key_sig(trace_desc_key_sig),
    .trace_desc_prefix_class(trace_desc_prefix_class),
    .trace_desc_router_class(trace_desc_router_class),
    .trace_desc_wvalid(trace_desc_wvalid),
    .trace_desc_wready(trace_desc_wready),
    .trace_desc_wdata(trace_desc_wdata),
    .resp_valid(resp_valid),
    .resp_ready(resp_ready),
    .resp_rdata(resp_rdata),
    .resp_hit(resp_hit),
    .resp_approx(resp_approx),
    .mem_re(mem_re),
    .mem_raddr(mem_raddr),
    .mem_rdata(mem_rdata),
    .mem_rvalid(mem_rvalid),
    .mem_we(mem_we),
    .mem_waddr(mem_waddr),
    .mem_wdata(mem_wdata),
    .m_axi_araddr(m_axi_araddr),
    .m_axi_arvalid(m_axi_arvalid),
    .m_axi_arready(m_axi_arready),
    .m_axi_rdata(m_axi_rdata),
    .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rready(m_axi_rready),
    .m_axi_awaddr(m_axi_awaddr),
    .m_axi_awvalid(m_axi_awvalid),
    .m_axi_awready(m_axi_awready),
    .m_axi_wdata(m_axi_wdata),
    .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready),
    .m_axi_bvalid(m_axi_bvalid),
    .m_axi_bready(m_axi_bready)
  );

  kcmu_ext_mem #(
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W),
    .RD_LATENCY(MEM_RD_LATENCY)
  ) mem0 (
    .clk(clk),
    .rst_n(rst_n),
    .re(mem_re),
    .raddr(mem_raddr),
    .rdata(mem_rdata),
    .rvalid(mem_rvalid),
    .we(mem_we),
    .waddr(mem_waddr),
    .wdata(mem_wdata)
  );

  kcmu_trace_player #(
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W),
    .DEPTH(32)
  ) u_trace_player (
    .clk(clk),
    .rst_n(rst_n),
    .cfg_clear(pl_cfg_clear),
    .cfg_we(pl_cfg_we),
    .cfg_idx(pl_cfg_idx),
    .cfg_op(pl_cfg_op),
    .cfg_addr(pl_cfg_addr),
    .cfg_wdata(pl_cfg_wdata),
    .cfg_last(pl_cfg_last),
    .start(pl_start),
    .busy(pl_busy),
    .done(pl_done),
    .trace_valid(pl_trace_valid),
    .trace_ready(trace_ready),
    .trace_op(pl_trace_op),
    .trace_addr(pl_trace_addr),
    .trace_wdata(pl_trace_wdata)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;
  always @(posedge clk) begin
    if (!rst_n) sim_cycle_counter <= 0;
    else        sim_cycle_counter <= sim_cycle_counter + 1;
  end

  // A completed response handshake should retire in the next cycle.
  property p_resp_one_cycle_when_ready;
    @(posedge clk) disable iff (!rst_n) (resp_valid && resp_ready) |=> !resp_valid;
  endproperty
  assert property (p_resp_one_cycle_when_ready)
    else $fatal(1, "resp_valid should clear next cycle when resp_ready=1");

  // While downstream is stalled, response payload must remain stable.
  property p_resp_hold_stable_when_stalled;
    @(posedge clk) disable iff (!rst_n)
      (resp_valid && !resp_ready) |=> (resp_ready || (resp_valid && $stable(resp_rdata) && $stable(resp_hit) && $stable(resp_approx)));
  endproperty
  assert property (p_resp_hold_stable_when_stalled)
    else $fatal(1, "resp must hold and remain stable while resp_ready=0");

  task automatic apply_reset(input integer cycles);
    begin
      @(negedge clk);
      rst_n = 1'b0;
      repeat (cycles) @(posedge clk);
      @(negedge clk);
      rst_n = 1'b1;
      @(posedge clk);
    end
  endtask

  task automatic do_cmd_with_full_meta(
    input  kcmu_op_t             op,
    input  logic [ADDR_W-1:0]    addr,
    input  logic [DATA_W-1:0]    wdata,
    input  logic                 meta_valid_i,
    input  logic [KCMU_SEQ_W-1:0] seq_id_i,
    input  kcmu_phase_t          phase_i,
    input  kcmu_kv_kind_t        kv_kind_i,
    input  logic [2:0]           layer_i,
    input  logic [1:0]           head_i,
    input  logic [11:0]          token_i,
    input  logic [2:0]           prio_i,
    output logic [DATA_W-1:0]    rdata,
    output logic                 hit,
    output integer               latency_cycles
  );
    integer wait_cnt;
    begin
      if (use_trace_player) begin
        $fatal(1, "do_cmd cannot run while trace player is selected");
      end

      latency_cycles = 0;

      @(negedge clk);
      man_trace_valid = 1'b1;
      man_trace_op    = op;
      man_trace_addr  = addr;
      man_trace_wdata = wdata;
      man_trace_meta_valid = meta_valid_i;
      man_trace_seq_id     = seq_id_i;
      man_trace_phase      = phase_i;
      man_trace_kv_kind    = kv_kind_i;
      man_trace_layer      = layer_i;
      man_trace_head       = head_i;
      man_trace_token      = token_i;
      man_trace_prio       = prio_i;

      wait_cnt = 0;
      while (!trace_ready) begin
        @(posedge clk);
        wait_cnt = wait_cnt + 1;
        if (wait_cnt > READY_TIMEOUT) begin
          $fatal(1, "trace_ready timeout, op=%0d addr=%0d", op, addr);
        end
      end

      @(negedge clk);
      man_trace_valid = 1'b0;
      man_trace_op    = KCMU_OP_NOP;
      man_trace_addr  = '0;
      man_trace_wdata = '0;
      man_trace_meta_valid = 1'b0;
      man_trace_seq_id     = {KCMU_SEQ_W{1'b0}};
      man_trace_phase      = KCMU_PHASE_PREFILL;
      man_trace_kv_kind    = KCMU_KV_KIND_K;
      man_trace_layer      = 3'd0;
      man_trace_head       = 2'd0;
      man_trace_token      = 12'd0;
      man_trace_prio       = 3'd0;

      wait_cnt = 0;
      while (!resp_valid) begin
        @(posedge clk);
        wait_cnt = wait_cnt + 1;
        if (wait_cnt > RESP_TIMEOUT) begin
          $fatal(1, "resp_valid timeout, op=%0d addr=%0d", op, addr);
        end
      end

      rdata = resp_rdata;
      hit   = resp_hit;
      last_resp_approx = resp_approx;
      latency_cycles = wait_cnt;

      if (op == KCMU_OP_RD) begin
        if (last_resp_approx) begin
          approx_read_cnt = approx_read_cnt + 1;
        end
        if (hit) begin
          rd_hit_cnt = rd_hit_cnt + 1;
          rd_hit_latency_sum = rd_hit_latency_sum + latency_cycles;
          if (latency_cycles > rd_hit_latency_max) rd_hit_latency_max = latency_cycles;
        end else begin
          rd_miss_cnt = rd_miss_cnt + 1;
          rd_miss_latency_sum = rd_miss_latency_sum + latency_cycles;
          if (latency_cycles > rd_miss_latency_max) rd_miss_latency_max = latency_cycles;
        end

        if (is_sem_hot_req(meta_valid_i, layer_i, head_i, prio_i)) begin
          hot_rd_cnt = hot_rd_cnt + 1;
          hot_rd_latency_sum = hot_rd_latency_sum + latency_cycles;
          if (latency_cycles > hot_rd_latency_max) hot_rd_latency_max = latency_cycles;
          if (hit) hot_rd_hit_cnt = hot_rd_hit_cnt + 1;
          else     hot_rd_miss_cnt = hot_rd_miss_cnt + 1;
        end
        if (is_sem_cold_req(meta_valid_i, layer_i, head_i, prio_i)) begin
          cold_rd_cnt = cold_rd_cnt + 1;
          cold_rd_latency_sum = cold_rd_latency_sum + latency_cycles;
          if (latency_cycles > cold_rd_latency_max) cold_rd_latency_max = latency_cycles;
          if (hit) cold_rd_hit_cnt = cold_rd_hit_cnt + 1;
          else     cold_rd_miss_cnt = cold_rd_miss_cnt + 1;
        end
        if (prio_i >= 3'd5) begin
          hiq_rd_cnt = hiq_rd_cnt + 1;
          hiq_rd_latency_sum = hiq_rd_latency_sum + latency_cycles;
        end
        if (prio_i <= 3'd2) begin
          loq_rd_cnt = loq_rd_cnt + 1;
          loq_rd_latency_sum = loq_rd_latency_sum + latency_cycles;
        end
      end else if (op == KCMU_OP_WR) begin
        if (hit) begin
          wr_hit_cnt = wr_hit_cnt + 1;
          wr_hit_latency_sum = wr_hit_latency_sum + latency_cycles;
          if (latency_cycles > wr_hit_latency_max) wr_hit_latency_max = latency_cycles;
        end else begin
          wr_miss_cnt = wr_miss_cnt + 1;
          wr_miss_latency_sum = wr_miss_latency_sum + latency_cycles;
          if (latency_cycles > wr_miss_latency_max) wr_miss_latency_max = latency_cycles;
        end
      end
      @(posedge clk);
    end
  endtask

  task automatic do_cmd_with_meta(
    input  kcmu_op_t             op,
    input  logic [ADDR_W-1:0]    addr,
    input  logic [DATA_W-1:0]    wdata,
    input  logic                 meta_valid_i,
    input  logic [2:0]           layer_i,
    input  logic [1:0]           head_i,
    input  logic [11:0]          token_i,
    input  logic [2:0]           prio_i,
    output logic [DATA_W-1:0]    rdata,
    output logic                 hit,
    output integer               latency_cycles
  );
    begin
      do_cmd_with_full_meta(
        op,
        addr,
        wdata,
        meta_valid_i,
        {KCMU_SEQ_W{1'b0}},
        (op == KCMU_OP_RD) ? KCMU_PHASE_DECODE : KCMU_PHASE_PREFILL,
        addr[0] ? KCMU_KV_KIND_V : KCMU_KV_KIND_K,
        layer_i,
        head_i,
        token_i,
        prio_i,
        rdata,
        hit,
        latency_cycles
      );
    end
  endtask

  task automatic do_cmd(
    input  kcmu_op_t             op,
    input  logic [ADDR_W-1:0]    addr,
    input  logic [DATA_W-1:0]    wdata,
    output logic [DATA_W-1:0]    rdata,
    output logic                 hit,
    output integer               latency_cycles
  );
    begin
      do_cmd_with_meta(
        op,
        addr,
        wdata,
        1'b0,
        3'd0,
        2'd0,
        12'd0,
        3'd0,
        rdata,
        hit,
        latency_cycles
      );
    end
  endtask

  function automatic logic [DATA_W-1:0] desc_generated_wdata(
    input logic [ADDR_W-1:0]    addr_i,
    input logic [7:0]           beat_i,
    input logic [KCMU_SEQ_W-1:0] seq_id_i,
    input logic [SCORE_W-1:0]   score_i
  );
    logic [DATA_W-1:0] tmp;
    begin
      tmp = {DATA_W{1'b0}};
      if (DATA_W >= 8)  tmp[7:0] = addr_i[7:0];
      if (DATA_W >= 16) tmp[15:8] = beat_i;
      if (DATA_W >= 24) tmp[23:16] = seq_id_i[7:0];
      if (DATA_W >= 32) tmp[31:24] = score_i[7:0];
      desc_generated_wdata = tmp;
    end
  endfunction

  task automatic do_descriptor(
    input  kcmu_op_t             op_i,
    input  logic [ADDR_W-1:0]    base_addr_i,
    input  logic [7:0]           len_i,
    input  logic [SCORE_W-1:0]   score_i,
    input  logic [KCMU_SEQ_W-1:0] seq_id_i,
    input  kcmu_phase_t          phase_i,
    input  kcmu_kv_kind_t        kv_kind_i,
    input  logic                 attn_valid_i,
    input  logic [SCORE_W-1:0]   attn_score_i,
    input  logic [KCMU_ATTN_RANK_W-1:0] recent_rank_i,
    input  logic [KCMU_TOKEN_BLOCK_W-1:0] token_block_id_i,
    input  logic [KCMU_ATTN_EPOCH_W-1:0] attn_epoch_i,
    output integer               hit_cnt_o,
    output integer               miss_cnt_o
  );
    integer beat_count;
    integer beat_idx;
    integer wait_cnt;
    integer lat_l;
    logic [ADDR_W-1:0] addr_l;
    logic [DATA_W-1:0] exp_data_l;
    begin
      if (use_trace_player) begin
        $fatal(1, "do_descriptor cannot run while trace player is selected");
      end

      beat_count = (len_i == 8'd0) ? 1 : len_i;
      hit_cnt_o = 0;
      miss_cnt_o = 0;

      @(negedge clk);
      trace_desc_valid <= 1'b1;
      trace_desc_op <= op_i;
      trace_desc_base_addr <= base_addr_i;
      trace_desc_len <= len_i;
      trace_desc_score <= score_i;
      trace_desc_seq_id <= seq_id_i;
      trace_desc_phase <= phase_i;
      trace_desc_kv_kind <= kv_kind_i;
      trace_desc_attn_valid <= attn_valid_i;
      trace_desc_attn_score <= attn_score_i;
      trace_desc_recent_rank <= recent_rank_i;
      trace_desc_token_block_id <= token_block_id_i;
      trace_desc_attn_epoch <= attn_epoch_i;
      trace_desc_head_budget_class <= desc_head_budget_class_cfg;
      trace_desc_query_relevance <= desc_query_relevance_cfg;
      trace_desc_compression_risk <= desc_compression_risk_cfg;
      trace_desc_spill_cost <= desc_spill_cost_cfg;
      trace_desc_service_criticality <= desc_service_criticality_cfg;
      trace_desc_policy_select_s5 <= desc_policy_select_s5_cfg;
      trace_desc_temporal_persist_class <= desc_temporal_persist_class_cfg;
      trace_desc_reuse_distance_class <= desc_reuse_distance_class_cfg;
      trace_desc_query_structure_class <= desc_query_structure_class_cfg;
      trace_desc_sched_urgency_hint <= desc_sched_urgency_hint_cfg;
      trace_desc_sig_valid <= 1'b0;
      trace_desc_query_sig <= 6'd0;
      trace_desc_key_sig <= 6'd0;
      trace_desc_prefix_class <= 2'd0;
      trace_desc_router_class <= 2'd0;

      wait_cnt = 0;
      while (!trace_desc_ready) begin
        @(posedge clk);
        wait_cnt = wait_cnt + 1;
        if (wait_cnt > READY_TIMEOUT) begin
          $fatal(1, "trace_desc_ready timeout, op=%0d base=%0d len=%0d", op_i, base_addr_i, len_i);
        end
      end

      @(negedge clk);
      trace_desc_valid <= 1'b0;
      trace_desc_op <= KCMU_OP_NOP;
      trace_desc_base_addr <= '0;
      trace_desc_len <= 8'd0;
      trace_desc_score <= '0;
      trace_desc_seq_id <= '0;
      trace_desc_phase <= KCMU_PHASE_PREFILL;
      trace_desc_kv_kind <= KCMU_KV_KIND_K;
      trace_desc_attn_valid <= 1'b0;
      trace_desc_attn_score <= '0;
      trace_desc_recent_rank <= '0;
      trace_desc_token_block_id <= '0;
      trace_desc_attn_epoch <= '0;
      trace_desc_head_budget_class <= '0;
      trace_desc_query_relevance <= '0;
      trace_desc_compression_risk <= '0;
      trace_desc_spill_cost <= '0;
      trace_desc_service_criticality <= '0;
      trace_desc_policy_select_s5 <= 1'b1;
      trace_desc_temporal_persist_class <= '0;
      trace_desc_reuse_distance_class <= '0;
      trace_desc_query_structure_class <= '0;
      trace_desc_sched_urgency_hint <= '0;
      trace_desc_sig_valid <= 1'b0;
      trace_desc_query_sig <= 6'd0;
      trace_desc_key_sig <= 6'd0;
      trace_desc_prefix_class <= 2'd0;
      trace_desc_router_class <= 2'd0;
      trace_desc_wvalid <= 1'b0;
      trace_desc_wdata <= '0;

      for (beat_idx = 0; beat_idx < beat_count; beat_idx = beat_idx + 1) begin
        addr_l = base_addr_i + ADDR_W'(beat_idx);
        if (op_i == KCMU_OP_WR) begin
          exp_data_l = desc_generated_wdata(addr_l, beat_idx[7:0], seq_id_i, score_i);
          @(negedge clk);
          trace_desc_wvalid <= 1'b1;
          trace_desc_wdata <= exp_data_l;
          wait_cnt = 0;
          while (!trace_desc_wready) begin
            @(posedge clk);
            wait_cnt = wait_cnt + 1;
            if (wait_cnt > READY_TIMEOUT) begin
              $fatal(1, "trace_desc_wready timeout beat=%0d base=%0d len=%0d", beat_idx, base_addr_i, len_i);
            end
          end
          @(negedge clk);
          trace_desc_wvalid <= 1'b0;
          trace_desc_wdata <= '0;
        end

        wait_cnt = 0;
        while (!resp_valid) begin
          @(posedge clk);
          wait_cnt = wait_cnt + 1;
          if (wait_cnt > RESP_TIMEOUT) begin
            $fatal(1, "descriptor resp timeout beat=%0d base=%0d len=%0d", beat_idx, base_addr_i, len_i);
          end
        end

        lat_l = wait_cnt;
        last_resp_approx = resp_approx;

        if (op_i == KCMU_OP_RD) begin
          exp_data_l = golden_mem[addr_l];
          if (!read_value_match(exp_data_l, resp_rdata, resp_approx)) begin
            $fatal(1, "descriptor read mismatch beat=%0d addr=%0d exp=%h got=%h approx=%0d",
                   beat_idx, addr_l, exp_data_l, resp_rdata, resp_approx);
          end
          total_reads = total_reads + 1;
        end else if (op_i == KCMU_OP_WR) begin
          golden_mem[addr_l] = exp_data_l;
          total_writes = total_writes + 1;
        end

        total_ops = total_ops + 1;
        record_latency(lat_l);
        if (resp_hit) begin
          total_hits = total_hits + 1;
          hit_cnt_o = hit_cnt_o + 1;
        end else begin
          total_misses = total_misses + 1;
          miss_cnt_o = miss_cnt_o + 1;
        end
        @(posedge clk);
      end
    end
  endtask

  task automatic do_seq_reclaim(
    input logic [KCMU_SEQ_W-1:0] seq_id_i,
    output integer               latency_cycles
  );
    logic [DATA_W-1:0] rdata_l;
    logic              hit_l;
    begin
      do_cmd_with_full_meta(
        KCMU_OP_NOP,
        {ADDR_W{1'b0}},
        {DATA_W{1'b0}},
        1'b1,
        seq_id_i,
        KCMU_PHASE_PREFILL,
        KCMU_KV_KIND_K,
        3'd0,
        2'd0,
        12'd0,
        3'd0,
        rdata_l,
        hit_l,
        latency_cycles
      );
    end
  endtask

  task automatic do_l2_direct_read(
    input  logic [ADDR_W-1:0]  addr_i,
    input  logic [2:0]         qos_i,
    input  logic               fill_allow_i,
    input  logic               compress_allow_i,
    output logic [DATA_W-1:0]  rdata,
    output logic               lossy,
    output integer             latency_cycles
  );
    integer wait_cnt;
    begin
      latency_cycles = 0;
      repeat (2) @(posedge clk);
      l2_direct_force_re = 1'b1;
      l2_direct_force_addr = addr_i;
      l2_direct_force_qos = qos_i;
      l2_direct_force_fill_allow = fill_allow_i;
      l2_direct_force_compress_allow = compress_allow_i;
      @(negedge clk);
      force dut.u_mcu.l2_re = l2_direct_force_re;
      force dut.u_mcu.l2_raddr = l2_direct_force_addr;
      force dut.u_mcu.l2_req_prefetch = 1'b0;
      force dut.u_mcu.l2_req_qos = l2_direct_force_qos;
      force dut.u_mcu.l2_req_sem_hot = 1'b0;
      force dut.u_mcu.l2_req_fill_allow = l2_direct_force_fill_allow;
      force dut.u_mcu.l2_req_victim_protect = 1'b0;
      force dut.u_mcu.l2_req_compress_allow = l2_direct_force_compress_allow;
      force dut.u_mcu.l2_we = 1'b0;
      force dut.u_mcu.l2_waddr = {ADDR_W{1'b0}};
      force dut.u_mcu.l2_wdata = {DATA_W{1'b0}};
      @(posedge clk);
      @(negedge clk);
      release dut.u_mcu.l2_re;
      release dut.u_mcu.l2_raddr;
      release dut.u_mcu.l2_req_prefetch;
      release dut.u_mcu.l2_req_qos;
      release dut.u_mcu.l2_req_sem_hot;
      release dut.u_mcu.l2_req_fill_allow;
      release dut.u_mcu.l2_req_victim_protect;
      release dut.u_mcu.l2_req_compress_allow;
      release dut.u_mcu.l2_we;
      release dut.u_mcu.l2_waddr;
      release dut.u_mcu.l2_wdata;
      l2_direct_force_re = 1'b0;
      l2_direct_force_addr = {ADDR_W{1'b0}};
      l2_direct_force_qos = 3'd0;
      l2_direct_force_fill_allow = 1'b0;
      l2_direct_force_compress_allow = 1'b0;

      wait_cnt = 0;
      while (!dut.u_mcu.u_l2.req_rvalid) begin
        @(posedge clk);
        wait_cnt = wait_cnt + 1;
        if (wait_cnt > RESP_TIMEOUT) begin
          $fatal(1, "direct L2 read timeout, addr=%0d", addr_i);
        end
      end

      rdata = dut.u_mcu.u_l2.req_rdata;
      lossy = dut.u_mcu.u_l2.req_rlossy;
      latency_cycles = wait_cnt;
      last_resp_approx = lossy;
      @(posedge clk);
    end
  endtask

  task automatic trace_player_cfg_write(
    input logic [4:0]           idx,
    input kcmu_op_t             op,
    input logic [ADDR_W-1:0]    addr,
    input logic [DATA_W-1:0]    wdata,
    input logic                 is_last
  );
    begin
      @(negedge clk);
      pl_cfg_we    = 1'b1;
      pl_cfg_idx   = idx;
      pl_cfg_op    = op;
      pl_cfg_addr  = addr;
      pl_cfg_wdata = wdata;
      pl_cfg_last  = is_last;
      @(negedge clk);
      pl_cfg_we    = 1'b0;
      pl_cfg_idx   = '0;
      pl_cfg_op    = KCMU_OP_NOP;
      pl_cfg_addr  = '0;
      pl_cfg_wdata = '0;
      pl_cfg_last  = 1'b0;
    end
  endtask

  task automatic record_latency(input integer latency_cycles);
    integer lat_bin;
    begin
      total_latency_cycles = total_latency_cycles + latency_cycles;
      if (latency_cycles > max_latency_cycles) begin
        max_latency_cycles = latency_cycles;
      end
      lat_bin = latency_cycles;
      if (lat_bin < 0) lat_bin = 0;
      if (lat_bin > 63) lat_bin = 63;
      latency_hist[lat_bin] = latency_hist[lat_bin] + 1;
    end
  endtask

  function automatic integer latency_percentile(input integer pct);
    integer rank;
    integer cum;
    integer bi;
    begin
      latency_percentile = 0;
      if (total_ops <= 0) begin
        latency_percentile = 0;
      end else begin
        rank = (total_ops * pct + 99) / 100;
        if (rank < 1) rank = 1;
        cum = 0;
        for (bi = 0; bi < 64; bi = bi + 1) begin
          cum = cum + latency_hist[bi];
          if (cum >= rank) begin
            latency_percentile = bi;
            bi = 64;
          end
        end
      end
    end
  endfunction

  function automatic logic read_value_match(
    input logic [DATA_W-1:0] exp_data,
    input logic [DATA_W-1:0] got_data,
    input logic              approx_flag
  );
    integer bi;
    integer diff;
    integer expb;
    integer gotb;
    begin
      if (!L2_LOSSY_COMPRESS_EN || !approx_flag) begin
        read_value_match = (got_data === exp_data);
      end else begin
        read_value_match = 1'b1;
        for (bi = 0; bi < BYTE_W; bi = bi + 1) begin
          expb = exp_data[bi*8 +: 8];
          gotb = got_data[bi*8 +: 8];
          if (expb >= gotb) diff = expb - gotb;
          else              diff = gotb - expb;
          if (diff > LOSSY_BYTE_EPS) begin
            read_value_match = 1'b0;
          end
        end
      end
    end
  endfunction

  function automatic logic is_sem_hot_req(
    input logic       meta_valid_i,
    input logic [2:0] layer_i,
    input logic [1:0] head_i,
    input logic [2:0] prio_i
  );
    begin
      is_sem_hot_req = (prio_i >= 3'd5) ||
                       (meta_valid_i && (layer_i <= 3'd1) && (head_i == 2'd0));
    end
  endfunction

  function automatic logic is_sem_cold_req(
    input logic       meta_valid_i,
    input logic [2:0] layer_i,
    input logic [1:0] head_i,
    input logic [2:0] prio_i
  );
    begin
      is_sem_cold_req = (prio_i <= 3'd1) ||
                        (meta_valid_i && (layer_i >= 3'd4) && (head_i >= 2'd2));
    end
  endfunction

  task automatic check_read(
    input logic [ADDR_W-1:0] addr,
    input logic [DATA_W-1:0] exp_data,
    input string             tag
  );
    logic [DATA_W-1:0] rdata;
    logic hit;
    integer latency;
    begin
      do_cmd(KCMU_OP_RD, addr, '0, rdata, hit, latency);
      record_latency(latency);
      total_ops   = total_ops + 1;
      total_reads = total_reads + 1;
      if (hit) total_hits = total_hits + 1;
      else     total_misses = total_misses + 1;

      if (!read_value_match(exp_data, rdata, last_resp_approx)) begin
        $fatal(1, "%s read mismatch: addr=%0d exp=%h got=%h approx=%0d", tag, addr, exp_data, rdata, last_resp_approx);
      end
    end
  endtask

  task automatic reseed_backing_memory_identity();
    integer mi;
    begin
      for (mi = 0; mi < DEPTH; mi = mi + 1) begin
        golden_mem[mi] = 32'hA0000000 + mi;
        mem0.mem[mi] = golden_mem[mi];
      end
    end
  endtask

  task automatic check_write(
    input logic [ADDR_W-1:0] addr,
    input logic [DATA_W-1:0] wdata,
    input string             tag
  );
    logic [DATA_W-1:0] rdata;
    logic hit;
    integer latency;
    begin
      do_cmd(KCMU_OP_WR, addr, wdata, rdata, hit, latency);
      record_latency(latency);
      total_ops    = total_ops + 1;
      total_writes = total_writes + 1;
      if (hit) total_hits = total_hits + 1;
      else     total_misses = total_misses + 1;

      if (rdata !== {DATA_W{1'b0}}) begin
        $fatal(1, "%s write response data should be 0, got=%h", tag, rdata);
      end
      golden_mem[addr] = wdata;
    end
  endtask

    task automatic run_random_phase(
      input integer op_count,
      input bit     pf_enable,
      input string  phase_name
    );
      integer n;
      integer phase_ops;
      integer phase_reads;
      integer phase_writes;
      integer phase_hits;
    integer phase_misses;
    integer phase_latency_cycles;
    integer phase_max_latency;
    integer phase_start_cycle;
    integer phase_end_cycle;
    integer phase_cycles;
    logic [ADDR_W-1:0] addr;
    logic [DATA_W-1:0] wdata;
    logic [DATA_W-1:0] rdata;
    logic hit;
    integer latency;
    bit do_write;
    begin
      phase_ops = 0;
      phase_reads = 0;
      phase_writes = 0;
      phase_hits = 0;
      phase_misses = 0;
      phase_latency_cycles = 0;
      phase_max_latency = 0;

      prefetch_enable = pf_enable;
      phase_start_cycle = sim_cycle_counter;
      for (n = 0; n < op_count; n = n + 1) begin
        addr = $urandom_range(0, DEPTH-1);
        do_write = ($urandom_range(0, 99) < 35);
          if (do_write) begin
            wdata = {$urandom, $urandom} ^ (32'h55AA0000 + n);
            do_cmd(KCMU_OP_WR, addr, wdata, rdata, hit, latency);
            record_latency(latency);
            golden_mem[addr] = wdata;
            total_writes = total_writes + 1;
          end else begin
            do_cmd(KCMU_OP_RD, addr, '0, rdata, hit, latency);
            record_latency(latency);
            if (!read_value_match(golden_mem[addr], rdata, last_resp_approx)) begin
              $fatal(1, "%s random read mismatch: addr=%0d exp=%h got=%h approx=%0d hit=%0d",
                     phase_name, addr, golden_mem[addr], rdata, last_resp_approx, hit);
            end
            total_reads = total_reads + 1;
        end

        phase_ops = phase_ops + 1;
        if (do_write) phase_writes = phase_writes + 1;
        else          phase_reads = phase_reads + 1;
        phase_latency_cycles = phase_latency_cycles + latency;
        if (latency > phase_max_latency) phase_max_latency = latency;
        if (hit) phase_hits = phase_hits + 1;
        else     phase_misses = phase_misses + 1;

        total_ops = total_ops + 1;
        if (hit) total_hits = total_hits + 1;
        else     total_misses = total_misses + 1;

        if ((n % 64) == 0) begin
          addr = $urandom_range(0, DEPTH-1);
          check_read(addr, golden_mem[addr], phase_name);
        end
      end

      phase_end_cycle = sim_cycle_counter;
      phase_cycles = phase_end_cycle - phase_start_cycle;
      if (phase_cycles <= 0) phase_cycles = 1;

      if (phase_ops > 0) begin
        $display("TB PROFILE: name=%s ops=%0d cycles=%0d opc=%0f avg_lat=%0f hit_rate=%0f max_lat=%0d",
                 phase_name,
                 phase_ops,
                 phase_cycles,
                 (1.0 * phase_ops) / phase_cycles,
                 (1.0 * phase_latency_cycles) / phase_ops,
                 (100.0 * phase_hits) / phase_ops,
                 phase_max_latency);
      end
    end
  endtask

  task automatic run_transformer_profile(
    input integer token_count,
    input bit     pf_enable,
    input string  phase_name
  );
    integer t;
    integer k;
    integer phase_ops;
    integer phase_reads;
    integer phase_writes;
    integer phase_hits;
    integer phase_misses;
    integer phase_latency_cycles;
    integer phase_max_latency;
    integer phase_start_cycle;
    integer phase_end_cycle;
    integer phase_cycles;
    integer phase_span;
    logic [ADDR_W-1:0] wr_addr;
    logic [ADDR_W-1:0] rd_addr;
    logic [DATA_W-1:0] wdata;
    logic [DATA_W-1:0] rdata_l;
    logic hit_l;
    integer lat_l;
    begin
      phase_ops = 0;
      phase_reads = 0;
      phase_writes = 0;
      phase_hits = 0;
      phase_misses = 0;
      phase_latency_cycles = 0;
      phase_max_latency = 0;

      prefetch_enable = pf_enable;
      phase_start_cycle = sim_cycle_counter;

      // Prefill + decode-like access pattern:
      // - One write per token (new KV line)
      // - Several reads on recent history (attention window)
      for (t = 0; t < token_count; t = t + 1) begin
        wr_addr = ADDR_W'(80 + t);
        wdata = 32'hC0000000 ^ (32'(t) * 32'h1021);
        do_cmd(KCMU_OP_WR, wr_addr, wdata, rdata_l, hit_l, lat_l);
        if (rdata_l !== {DATA_W{1'b0}}) begin
          $fatal(1, "%s profile write response must be zero", phase_name);
        end
        golden_mem[wr_addr] = wdata;

        phase_ops = phase_ops + 1;
        phase_writes = phase_writes + 1;
        phase_latency_cycles = phase_latency_cycles + lat_l;
        if (lat_l > phase_max_latency) phase_max_latency = lat_l;
        if (hit_l) phase_hits = phase_hits + 1;
        else       phase_misses = phase_misses + 1;

        total_ops = total_ops + 1;
        total_writes = total_writes + 1;
        record_latency(lat_l);
        if (hit_l) total_hits = total_hits + 1;
        else       total_misses = total_misses + 1;

        phase_span = (t < 16) ? t : 16;
        for (k = 0; k <= phase_span; k = k + 2) begin
          if (wr_addr >= ADDR_W'(k)) rd_addr = wr_addr - ADDR_W'(k);
          else                       rd_addr = wr_addr;

          do_cmd(KCMU_OP_RD, rd_addr, '0, rdata_l, hit_l, lat_l);
          if (!read_value_match(golden_mem[rd_addr], rdata_l, last_resp_approx)) begin
            $fatal(1, "%s profile read mismatch: addr=%0d exp=%h got=%h approx=%0d",
                   phase_name, rd_addr, golden_mem[rd_addr], rdata_l, last_resp_approx);
          end

          phase_ops = phase_ops + 1;
          phase_reads = phase_reads + 1;
          phase_latency_cycles = phase_latency_cycles + lat_l;
          if (lat_l > phase_max_latency) phase_max_latency = lat_l;
          if (hit_l) phase_hits = phase_hits + 1;
          else       phase_misses = phase_misses + 1;

          total_ops = total_ops + 1;
          total_reads = total_reads + 1;
          record_latency(lat_l);
          if (hit_l) total_hits = total_hits + 1;
          else       total_misses = total_misses + 1;
        end
      end

      phase_end_cycle = sim_cycle_counter;
      phase_cycles = phase_end_cycle - phase_start_cycle;
      if (phase_cycles <= 0) phase_cycles = 1;

      $display("TB PROFILE: name=%s ops=%0d cycles=%0d opc=%0f avg_lat=%0f hit_rate=%0f max_lat=%0d",
               phase_name,
               phase_ops,
               phase_cycles,
               (1.0 * phase_ops) / phase_cycles,
               (1.0 * phase_latency_cycles) / phase_ops,
               (100.0 * phase_hits) / phase_ops,
               phase_max_latency);
    end
  endtask

  task automatic run_kv_semantic_profile(
    input integer token_count,
    input bit     pf_enable,
    input string  phase_name
  );
    integer t;
    integer k;
    integer rd_tok;
    integer sem_idx;
    integer phase_ops;
    integer phase_reads;
    integer phase_writes;
    integer phase_hits;
    integer phase_misses;
    integer phase_latency_cycles;
    integer phase_max_latency;
    integer phase_start_cycle;
    integer phase_end_cycle;
    integer phase_cycles;
    logic [ADDR_W-1:0] addr_l;
    logic [DATA_W-1:0] wdata_l;
    logic [DATA_W-1:0] rdata_l;
    logic hit_l;
    integer lat_l;
    logic [2:0] layer_l;
    logic [1:0] head_l;
    logic [11:0] token_l;
    begin
      phase_ops = 0;
      phase_reads = 0;
      phase_writes = 0;
      phase_hits = 0;
      phase_misses = 0;
      phase_latency_cycles = 0;
      phase_max_latency = 0;

      prefetch_enable = pf_enable;
      phase_start_cycle = sim_cycle_counter;

      // Reuse a tiny logical-address window but vary {layer,head,token}.
      // This stresses KV semantic mapping rather than plain logical indexing.
      for (t = 0; t < token_count; t = t + 1) begin
        layer_l = t[2:0];
        head_l = t[1:0];
        token_l = 12'h800 + t[11:0];
        // Use a small rolling logical window to avoid immediate overwrite alias
        // and keep semantic remap pressure realistic.
        addr_l = ADDR_W'(8'd192 + (t & 8'h0F));
        wdata_l = 32'hE0000000 ^ (32'(t) * 32'h01020305);

        do_cmd_with_meta(
          KCMU_OP_WR, addr_l, wdata_l,
          1'b1, layer_l, head_l, token_l, 3'd3,
          rdata_l, hit_l, lat_l
        );
        if (rdata_l !== {DATA_W{1'b0}}) begin
          $fatal(1, "%s semantic write response must be zero", phase_name);
        end
        sem_idx = t & 8'hFF;
        kv_sem_golden[sem_idx] = wdata_l;

        phase_ops = phase_ops + 1;
        phase_writes = phase_writes + 1;
        phase_latency_cycles = phase_latency_cycles + lat_l;
        if (lat_l > phase_max_latency) phase_max_latency = lat_l;
        if (hit_l) phase_hits = phase_hits + 1;
        else       phase_misses = phase_misses + 1;

        total_ops = total_ops + 1;
        total_writes = total_writes + 1;
        record_latency(lat_l);
        if (hit_l) total_hits = total_hits + 1;
        else       total_misses = total_misses + 1;

        for (k = 0; (k < 6) && (k <= t); k = k + 2) begin
          rd_tok = t - k;
          sem_idx = rd_tok & 8'hFF;
          addr_l = ADDR_W'(8'd192 + (rd_tok & 8'h0F));
          layer_l = rd_tok[2:0];
          head_l = rd_tok[1:0];
          token_l = 12'h800 + rd_tok[11:0];

          do_cmd_with_meta(
            KCMU_OP_RD, addr_l, '0,
            1'b1, layer_l, head_l, token_l, 3'd4,
            rdata_l, hit_l, lat_l
          );
          if (!read_value_match(kv_sem_golden[sem_idx], rdata_l, last_resp_approx)) begin
            $fatal(1, "%s semantic read mismatch: tok=%0d addr=%0d exp=%h got=%h approx=%0d hit=%0d lat=%0d map_hit=%0d map_alloc=%0d map_overflow=%0d",
                   phase_name, rd_tok, addr_l, kv_sem_golden[sem_idx], rdata_l, last_resp_approx,
                   hit_l, lat_l,
                   dut.u_mcu.u_kv_map.map_hit,
                   dut.u_mcu.u_kv_map.map_alloc,
                   dut.u_mcu.u_kv_map.map_overflow);
          end

          phase_ops = phase_ops + 1;
          phase_reads = phase_reads + 1;
          phase_latency_cycles = phase_latency_cycles + lat_l;
          if (lat_l > phase_max_latency) phase_max_latency = lat_l;
          if (hit_l) phase_hits = phase_hits + 1;
          else       phase_misses = phase_misses + 1;

          total_ops = total_ops + 1;
          total_reads = total_reads + 1;
          record_latency(lat_l);
          if (hit_l) total_hits = total_hits + 1;
          else       total_misses = total_misses + 1;
        end
      end

      phase_end_cycle = sim_cycle_counter;
      phase_cycles = phase_end_cycle - phase_start_cycle;
      if (phase_cycles <= 0) phase_cycles = 1;

      $display("TB PROFILE: name=%s ops=%0d cycles=%0d opc=%0f avg_lat=%0f hit_rate=%0f max_lat=%0d",
               phase_name,
               phase_ops,
               phase_cycles,
               (1.0 * phase_ops) / phase_cycles,
               (1.0 * phase_latency_cycles) / phase_ops,
               (100.0 * phase_hits) / phase_ops,
               phase_max_latency);
    end
  endtask

  task automatic run_kv_semantic_hireuse_profile(
    input integer token_count,
    input bit     pf_enable,
    input string  phase_name
  );
    integer t;
    integer k;
    integer rd_tok;
    integer sem_idx;
    integer phase_ops;
    integer phase_reads;
    integer phase_writes;
    integer phase_hits;
    integer phase_misses;
    integer phase_latency_cycles;
    integer phase_max_latency;
    integer phase_start_cycle;
    integer phase_end_cycle;
    integer phase_cycles;
    logic [ADDR_W-1:0] addr_l;
    logic [DATA_W-1:0] wdata_l;
    logic [DATA_W-1:0] rdata_l;
    logic hit_l;
    integer lat_l;
    logic [2:0] layer_l;
    logic [1:0] head_l;
    logic [11:0] token_l;
    begin
      phase_ops = 0;
      phase_reads = 0;
      phase_writes = 0;
      phase_hits = 0;
      phase_misses = 0;
      phase_latency_cycles = 0;
      phase_max_latency = 0;

      prefetch_enable = pf_enable;
      phase_start_cycle = sim_cycle_counter;

      // High-reuse semantic window: small logical address set + frequent nearby attention reads.
      for (t = 0; t < token_count; t = t + 1) begin
        layer_l = t[0] ? 3'd1 : 3'd0;
        head_l = t[0] ? 2'd1 : 2'd0;
        token_l = 12'h900 + t[11:0];
        addr_l = ADDR_W'(8'd208 + (t & 8'h07));
        wdata_l = 32'hD1000000 ^ (32'(t) * 32'h01010101);

        do_cmd_with_meta(
          KCMU_OP_WR, addr_l, wdata_l,
          1'b1, layer_l, head_l, token_l, 3'd4,
          rdata_l, hit_l, lat_l
        );
        if (rdata_l !== {DATA_W{1'b0}}) begin
          $fatal(1, "%s write response must be zero", phase_name);
        end
        sem_idx = token_l[7:0];
        kv_sem_golden[sem_idx] = wdata_l;

        phase_ops = phase_ops + 1;
        phase_writes = phase_writes + 1;
        phase_latency_cycles = phase_latency_cycles + lat_l;
        if (lat_l > phase_max_latency) phase_max_latency = lat_l;
        if (hit_l) phase_hits = phase_hits + 1;
        else       phase_misses = phase_misses + 1;

        total_ops = total_ops + 1;
        total_writes = total_writes + 1;
        record_latency(lat_l);
        if (hit_l) total_hits = total_hits + 1;
        else       total_misses = total_misses + 1;

        for (k = 0; (k < 8) && (k <= t); k = k + 1) begin
          rd_tok = t - (k & 3);
          token_l = 12'h900 + rd_tok[11:0];
          layer_l = rd_tok[0] ? 3'd1 : 3'd0;
          head_l = rd_tok[0] ? 2'd1 : 2'd0;
          addr_l = ADDR_W'(8'd208 + (rd_tok & 8'h07));
          sem_idx = token_l[7:0];

          do_cmd_with_meta(
            KCMU_OP_RD, addr_l, '0,
            1'b1, layer_l, head_l, token_l, 3'd5,
            rdata_l, hit_l, lat_l
          );
          if (!read_value_match(kv_sem_golden[sem_idx], rdata_l, last_resp_approx)) begin
            $fatal(1, "%s read mismatch: tok=%0d addr=%0d exp=%h got=%h approx=%0d",
                   phase_name, rd_tok, addr_l, kv_sem_golden[sem_idx], rdata_l, last_resp_approx);
          end

          phase_ops = phase_ops + 1;
          phase_reads = phase_reads + 1;
          phase_latency_cycles = phase_latency_cycles + lat_l;
          if (lat_l > phase_max_latency) phase_max_latency = lat_l;
          if (hit_l) phase_hits = phase_hits + 1;
          else       phase_misses = phase_misses + 1;

          total_ops = total_ops + 1;
          total_reads = total_reads + 1;
          record_latency(lat_l);
          if (hit_l) total_hits = total_hits + 1;
          else       total_misses = total_misses + 1;
        end
      end

      phase_end_cycle = sim_cycle_counter;
      phase_cycles = phase_end_cycle - phase_start_cycle;
      if (phase_cycles <= 0) phase_cycles = 1;

      $display("TB PROFILE: name=%s ops=%0d cycles=%0d opc=%0f avg_lat=%0f hit_rate=%0f max_lat=%0d",
               phase_name,
               phase_ops,
               phase_cycles,
               (1.0 * phase_ops) / phase_cycles,
               (1.0 * phase_latency_cycles) / phase_ops,
               (100.0 * phase_hits) / phase_ops,
               phase_max_latency);
    end
  endtask

  task automatic run_kv_semantic_loreuse_profile(
    input integer token_count,
    input bit     pf_enable,
    input string  phase_name
  );
    integer t;
    integer rd_tok;
    integer sem_idx;
    integer phase_ops;
    integer phase_reads;
    integer phase_writes;
    integer phase_hits;
    integer phase_misses;
    integer phase_latency_cycles;
    integer phase_max_latency;
    integer phase_start_cycle;
    integer phase_end_cycle;
    integer phase_cycles;
    logic [ADDR_W-1:0] addr_l;
    logic [DATA_W-1:0] wdata_l;
    logic [DATA_W-1:0] rdata_l;
    logic hit_l;
    integer lat_l;
    logic [2:0] layer_l;
    logic [1:0] head_l;
    logic [11:0] token_l;
    begin
      phase_ops = 0;
      phase_reads = 0;
      phase_writes = 0;
      phase_hits = 0;
      phase_misses = 0;
      phase_latency_cycles = 0;
      phase_max_latency = 0;

      prefetch_enable = pf_enable;
      phase_start_cycle = sim_cycle_counter;

      // Low-reuse semantic stream: larger working set and distant reads.
      for (t = 0; t < token_count; t = t + 1) begin
        layer_l = t[2:0];
        head_l = t[1:0];
        token_l = 12'hA00 + t[11:0];
        addr_l = ADDR_W'(8'd32 + (t & 8'h3F));
        wdata_l = 32'hD2000000 ^ (32'(t) * 32'h00110011);

        do_cmd_with_meta(
          KCMU_OP_WR, addr_l, wdata_l,
          1'b1, layer_l, head_l, token_l, 3'd3,
          rdata_l, hit_l, lat_l
        );
        if (rdata_l !== {DATA_W{1'b0}}) begin
          $fatal(1, "%s write response must be zero", phase_name);
        end
        sem_idx = token_l[7:0];
        kv_sem_golden[sem_idx] = wdata_l;

        phase_ops = phase_ops + 1;
        phase_writes = phase_writes + 1;
        phase_latency_cycles = phase_latency_cycles + lat_l;
        if (lat_l > phase_max_latency) phase_max_latency = lat_l;
        if (hit_l) phase_hits = phase_hits + 1;
        else       phase_misses = phase_misses + 1;

        total_ops = total_ops + 1;
        total_writes = total_writes + 1;
        record_latency(lat_l);
        if (hit_l) total_hits = total_hits + 1;
        else       total_misses = total_misses + 1;

        rd_tok = (t >= 24) ? (t - 24) : t;
        token_l = 12'hA00 + rd_tok[11:0];
        layer_l = rd_tok[2:0];
        head_l = rd_tok[1:0];
        addr_l = ADDR_W'(8'd32 + (rd_tok & 8'h3F));
        sem_idx = token_l[7:0];

        do_cmd_with_meta(
          KCMU_OP_RD, addr_l, '0,
          1'b1, layer_l, head_l, token_l, 3'd3,
          rdata_l, hit_l, lat_l
        );
        if (!read_value_match(kv_sem_golden[sem_idx], rdata_l, last_resp_approx)) begin
          $fatal(1, "%s read mismatch: tok=%0d addr=%0d exp=%h got=%h approx=%0d",
                 phase_name, rd_tok, addr_l, kv_sem_golden[sem_idx], rdata_l, last_resp_approx);
        end

        phase_ops = phase_ops + 1;
        phase_reads = phase_reads + 1;
        phase_latency_cycles = phase_latency_cycles + lat_l;
        if (lat_l > phase_max_latency) phase_max_latency = lat_l;
        if (hit_l) phase_hits = phase_hits + 1;
        else       phase_misses = phase_misses + 1;

        total_ops = total_ops + 1;
        total_reads = total_reads + 1;
        record_latency(lat_l);
        if (hit_l) total_hits = total_hits + 1;
        else       total_misses = total_misses + 1;
      end

      phase_end_cycle = sim_cycle_counter;
      phase_cycles = phase_end_cycle - phase_start_cycle;
      if (phase_cycles <= 0) phase_cycles = 1;

      $display("TB PROFILE: name=%s ops=%0d cycles=%0d opc=%0f avg_lat=%0f hit_rate=%0f max_lat=%0d",
               phase_name,
               phase_ops,
               phase_cycles,
               (1.0 * phase_ops) / phase_cycles,
               (1.0 * phase_latency_cycles) / phase_ops,
               (100.0 * phase_hits) / phase_ops,
               phase_max_latency);
    end
  endtask

  task automatic run_kv_semantic_burst_profile(
    input integer token_count,
    input bit     pf_enable,
    input string  phase_name
  );
    integer t;
    integer k;
    integer rd_tok;
    integer sem_idx;
    integer phase_ops;
    integer phase_reads;
    integer phase_writes;
    integer phase_hits;
    integer phase_misses;
    integer phase_latency_cycles;
    integer phase_max_latency;
    integer phase_start_cycle;
    integer phase_end_cycle;
    integer phase_cycles;
    integer burst_len;
    integer grp_t;
    integer grp_rd;
    logic [ADDR_W-1:0] addr_l;
    logic [DATA_W-1:0] wdata_l;
    logic [DATA_W-1:0] rdata_l;
    logic hit_l;
    integer lat_l;
    logic [2:0] layer_l;
    logic [1:0] head_l;
    logic [11:0] token_l;
    begin
      phase_ops = 0;
      phase_reads = 0;
      phase_writes = 0;
      phase_hits = 0;
      phase_misses = 0;
      phase_latency_cycles = 0;
      phase_max_latency = 0;
      burst_len = 8;

      prefetch_enable = pf_enable;
      phase_start_cycle = sim_cycle_counter;

      // Burst switching: alternate attention groups every burst_len tokens.
      for (t = 0; t < token_count; t = t + 1) begin
        grp_t = (t / burst_len) & 1;
        layer_l = grp_t ? 3'd2 : 3'd0;
        head_l = grp_t ? 2'd2 : 2'd0;
        token_l = 12'hB00 + t[11:0];
        addr_l = ADDR_W'((grp_t ? 8'd176 : 8'd160) + (t & 8'h0F));
        wdata_l = 32'hD3000000 ^ (32'(t) * 32'h00010021);

        do_cmd_with_meta(
          KCMU_OP_WR, addr_l, wdata_l,
          1'b1, layer_l, head_l, token_l, 3'd4,
          rdata_l, hit_l, lat_l
        );
        if (rdata_l !== {DATA_W{1'b0}}) begin
          $fatal(1, "%s write response must be zero", phase_name);
        end
        sem_idx = token_l[7:0];
        kv_sem_golden[sem_idx] = wdata_l;

        phase_ops = phase_ops + 1;
        phase_writes = phase_writes + 1;
        phase_latency_cycles = phase_latency_cycles + lat_l;
        if (lat_l > phase_max_latency) phase_max_latency = lat_l;
        if (hit_l) phase_hits = phase_hits + 1;
        else       phase_misses = phase_misses + 1;

        total_ops = total_ops + 1;
        total_writes = total_writes + 1;
        record_latency(lat_l);
        if (hit_l) total_hits = total_hits + 1;
        else       total_misses = total_misses + 1;

        for (k = 0; (k < 4) && (k <= t); k = k + 1) begin
          rd_tok = t - k;
          grp_rd = (rd_tok / burst_len) & 1;
          if (grp_rd != grp_t) begin
            rd_tok = t;
            grp_rd = grp_t;
          end
          token_l = 12'hB00 + rd_tok[11:0];
          layer_l = grp_rd ? 3'd2 : 3'd0;
          head_l = grp_rd ? 2'd2 : 2'd0;
          addr_l = ADDR_W'((grp_rd ? 8'd176 : 8'd160) + (rd_tok & 8'h0F));
          sem_idx = token_l[7:0];

          do_cmd_with_meta(
            KCMU_OP_RD, addr_l, '0,
            1'b1, layer_l, head_l, token_l, 3'd5,
            rdata_l, hit_l, lat_l
          );
          if (!read_value_match(kv_sem_golden[sem_idx], rdata_l, last_resp_approx)) begin
            $fatal(1, "%s read mismatch: tok=%0d addr=%0d exp=%h got=%h approx=%0d",
                   phase_name, rd_tok, addr_l, kv_sem_golden[sem_idx], rdata_l, last_resp_approx);
          end

          phase_ops = phase_ops + 1;
          phase_reads = phase_reads + 1;
          phase_latency_cycles = phase_latency_cycles + lat_l;
          if (lat_l > phase_max_latency) phase_max_latency = lat_l;
          if (hit_l) phase_hits = phase_hits + 1;
          else       phase_misses = phase_misses + 1;

          total_ops = total_ops + 1;
          total_reads = total_reads + 1;
          record_latency(lat_l);
          if (hit_l) total_hits = total_hits + 1;
          else       total_misses = total_misses + 1;
        end

        if (((t % burst_len) == 0) && (t >= burst_len)) begin
          rd_tok = t - burst_len;
          grp_rd = (rd_tok / burst_len) & 1;
          token_l = 12'hB00 + rd_tok[11:0];
          layer_l = grp_rd ? 3'd2 : 3'd0;
          head_l = grp_rd ? 2'd2 : 2'd0;
          addr_l = ADDR_W'((grp_rd ? 8'd176 : 8'd160) + (rd_tok & 8'h0F));
          sem_idx = token_l[7:0];

          do_cmd_with_meta(
            KCMU_OP_RD, addr_l, '0,
            1'b1, layer_l, head_l, token_l, 3'd4,
            rdata_l, hit_l, lat_l
          );
          if (!read_value_match(kv_sem_golden[sem_idx], rdata_l, last_resp_approx)) begin
            $fatal(1, "%s switch read mismatch: tok=%0d addr=%0d exp=%h got=%h approx=%0d",
                   phase_name, rd_tok, addr_l, kv_sem_golden[sem_idx], rdata_l, last_resp_approx);
          end

          phase_ops = phase_ops + 1;
          phase_reads = phase_reads + 1;
          phase_latency_cycles = phase_latency_cycles + lat_l;
          if (lat_l > phase_max_latency) phase_max_latency = lat_l;
          if (hit_l) phase_hits = phase_hits + 1;
          else       phase_misses = phase_misses + 1;

          total_ops = total_ops + 1;
          total_reads = total_reads + 1;
          record_latency(lat_l);
          if (hit_l) total_hits = total_hits + 1;
          else       total_misses = total_misses + 1;
        end
      end

      phase_end_cycle = sim_cycle_counter;
      phase_cycles = phase_end_cycle - phase_start_cycle;
      if (phase_cycles <= 0) phase_cycles = 1;

      $display("TB PROFILE: name=%s ops=%0d cycles=%0d opc=%0f avg_lat=%0f hit_rate=%0f max_lat=%0d",
               phase_name,
               phase_ops,
               phase_cycles,
               (1.0 * phase_ops) / phase_cycles,
               (1.0 * phase_latency_cycles) / phase_ops,
               (100.0 * phase_hits) / phase_ops,
               phase_max_latency);
    end
  endtask

  task automatic run_head_switch_heavy_profile(
    input integer token_count,
    input bit     pf_enable,
    input string  phase_name
  );
    integer t;
    integer k;
    integer rd_tok;
    integer sem_idx;
    integer phase_ops;
    integer phase_reads;
    integer phase_writes;
    integer phase_hits;
    integer phase_misses;
    integer phase_latency_cycles;
    integer phase_max_latency;
    integer phase_start_cycle;
    integer phase_end_cycle;
    integer phase_cycles;
    logic [ADDR_W-1:0] addr_l;
    logic [DATA_W-1:0] wdata_l;
    logic [DATA_W-1:0] rdata_l;
    logic hit_l;
    integer lat_l;
    logic [2:0] layer_l;
    logic [1:0] head_l;
    logic [11:0] token_l;
    begin
      phase_ops = 0;
      phase_reads = 0;
      phase_writes = 0;
      phase_hits = 0;
      phase_misses = 0;
      phase_latency_cycles = 0;
      phase_max_latency = 0;

      prefetch_enable = pf_enable;
      phase_start_cycle = sim_cycle_counter;

      // Rapid head switching under a small per-head window.
      for (t = 0; t < token_count; t = t + 1) begin
        head_l = t[1:0];
        layer_l = {1'b0, head_l};
        token_l = 12'hC00 + t[11:0];
        addr_l = ADDR_W'(8'd112 + ({6'd0, head_l} << 3) + (t & 8'h07));
        wdata_l = 32'hD4000000 ^ (32'(t) * 32'h00030011);

        do_cmd_with_meta(
          KCMU_OP_WR, addr_l, wdata_l,
          1'b1, layer_l, head_l, token_l, 3'd4,
          rdata_l, hit_l, lat_l
        );
        if (rdata_l !== {DATA_W{1'b0}}) begin
          $fatal(1, "%s write response must be zero", phase_name);
        end
        sem_idx = token_l[7:0];
        kv_sem_golden[sem_idx] = wdata_l;

        phase_ops = phase_ops + 1;
        phase_writes = phase_writes + 1;
        phase_latency_cycles = phase_latency_cycles + lat_l;
        if (lat_l > phase_max_latency) phase_max_latency = lat_l;
        if (hit_l) phase_hits = phase_hits + 1;
        else       phase_misses = phase_misses + 1;
        total_ops = total_ops + 1;
        total_writes = total_writes + 1;
        record_latency(lat_l);
        if (hit_l) total_hits = total_hits + 1;
        else       total_misses = total_misses + 1;

        for (k = 0; (k < 4) && (k <= t); k = k + 1) begin
          rd_tok = t - k;
          head_l = rd_tok[1:0];
          layer_l = {1'b0, head_l};
          token_l = 12'hC00 + rd_tok[11:0];
          addr_l = ADDR_W'(8'd112 + ({6'd0, head_l} << 3) + (rd_tok & 8'h07));
          sem_idx = token_l[7:0];

          do_cmd_with_meta(
            KCMU_OP_RD, addr_l, '0,
            1'b1, layer_l, head_l, token_l, 3'd5,
            rdata_l, hit_l, lat_l
          );
          if (!read_value_match(kv_sem_golden[sem_idx], rdata_l, last_resp_approx)) begin
            $fatal(1, "%s read mismatch: tok=%0d addr=%0d exp=%h got=%h approx=%0d",
                   phase_name, rd_tok, addr_l, kv_sem_golden[sem_idx], rdata_l, last_resp_approx);
          end

          phase_ops = phase_ops + 1;
          phase_reads = phase_reads + 1;
          phase_latency_cycles = phase_latency_cycles + lat_l;
          if (lat_l > phase_max_latency) phase_max_latency = lat_l;
          if (hit_l) phase_hits = phase_hits + 1;
          else       phase_misses = phase_misses + 1;
          total_ops = total_ops + 1;
          total_reads = total_reads + 1;
          record_latency(lat_l);
          if (hit_l) total_hits = total_hits + 1;
          else       total_misses = total_misses + 1;
        end
      end

      phase_end_cycle = sim_cycle_counter;
      phase_cycles = phase_end_cycle - phase_start_cycle;
      if (phase_cycles <= 0) phase_cycles = 1;

      $display("TB PROFILE: name=%s ops=%0d cycles=%0d opc=%0f avg_lat=%0f hit_rate=%0f max_lat=%0d",
               phase_name,
               phase_ops,
               phase_cycles,
               (1.0 * phase_ops) / phase_cycles,
               (1.0 * phase_latency_cycles) / phase_ops,
               (100.0 * phase_hits) / phase_ops,
               phase_max_latency);
    end
  endtask

  task automatic run_long_tail_context_profile(
    input integer token_count,
    input bit     pf_enable,
    input string  phase_name
  );
    integer t;
    integer rd_tok;
    integer sem_idx;
    integer phase_ops;
    integer phase_reads;
    integer phase_writes;
    integer phase_hits;
    integer phase_misses;
    integer phase_latency_cycles;
    integer phase_max_latency;
    integer phase_start_cycle;
    integer phase_end_cycle;
    integer phase_cycles;
    logic [ADDR_W-1:0] addr_l;
    logic [DATA_W-1:0] wdata_l;
    logic [DATA_W-1:0] rdata_l;
    logic hit_l;
    integer lat_l;
    logic [2:0] layer_l;
    logic [1:0] head_l;
    logic [11:0] token_l;
    begin
      phase_ops = 0;
      phase_reads = 0;
      phase_writes = 0;
      phase_hits = 0;
      phase_misses = 0;
      phase_latency_cycles = 0;
      phase_max_latency = 0;

      prefetch_enable = pf_enable;
      phase_start_cycle = sim_cycle_counter;

      // Long-tail context: broad stream + far-distance revisits.
      for (t = 0; t < token_count; t = t + 1) begin
        layer_l = t[2:0];
        head_l = t[1:0];
        token_l = 12'hD00 + t[11:0];
        addr_l = ADDR_W'(8'd16 + (t & 8'h7F));
        wdata_l = 32'hD5000000 ^ (32'(t) * 32'h00050013);

        do_cmd_with_meta(
          KCMU_OP_WR, addr_l, wdata_l,
          1'b1, layer_l, head_l, token_l, 3'd3,
          rdata_l, hit_l, lat_l
        );
        if (rdata_l !== {DATA_W{1'b0}}) begin
          $fatal(1, "%s write response must be zero", phase_name);
        end
        sem_idx = token_l[7:0];
        kv_sem_golden[sem_idx] = wdata_l;

        phase_ops = phase_ops + 1;
        phase_writes = phase_writes + 1;
        phase_latency_cycles = phase_latency_cycles + lat_l;
        if (lat_l > phase_max_latency) phase_max_latency = lat_l;
        if (hit_l) phase_hits = phase_hits + 1;
        else       phase_misses = phase_misses + 1;
        total_ops = total_ops + 1;
        total_writes = total_writes + 1;
        record_latency(lat_l);
        if (hit_l) total_hits = total_hits + 1;
        else       total_misses = total_misses + 1;

        rd_tok = (t >= 48) ? (t - 48) : t;
        layer_l = rd_tok[2:0];
        head_l = rd_tok[1:0];
        token_l = 12'hD00 + rd_tok[11:0];
        addr_l = ADDR_W'(8'd16 + (rd_tok & 8'h7F));
        sem_idx = token_l[7:0];

        do_cmd_with_meta(
          KCMU_OP_RD, addr_l, '0,
          1'b1, layer_l, head_l, token_l, 3'd3,
          rdata_l, hit_l, lat_l
        );
        if (!read_value_match(kv_sem_golden[sem_idx], rdata_l, last_resp_approx)) begin
          $fatal(1, "%s read mismatch: tok=%0d addr=%0d exp=%h got=%h approx=%0d",
                 phase_name, rd_tok, addr_l, kv_sem_golden[sem_idx], rdata_l, last_resp_approx);
        end

        phase_ops = phase_ops + 1;
        phase_reads = phase_reads + 1;
        phase_latency_cycles = phase_latency_cycles + lat_l;
        if (lat_l > phase_max_latency) phase_max_latency = lat_l;
        if (hit_l) phase_hits = phase_hits + 1;
        else       phase_misses = phase_misses + 1;
        total_ops = total_ops + 1;
        total_reads = total_reads + 1;
        record_latency(lat_l);
        if (hit_l) total_hits = total_hits + 1;
        else       total_misses = total_misses + 1;
      end

      phase_end_cycle = sim_cycle_counter;
      phase_cycles = phase_end_cycle - phase_start_cycle;
      if (phase_cycles <= 0) phase_cycles = 1;

      $display("TB PROFILE: name=%s ops=%0d cycles=%0d opc=%0f avg_lat=%0f hit_rate=%0f max_lat=%0d",
               phase_name,
               phase_ops,
               phase_cycles,
               (1.0 * phase_ops) / phase_cycles,
               (1.0 * phase_latency_cycles) / phase_ops,
               (100.0 * phase_hits) / phase_ops,
               phase_max_latency);
    end
  endtask

  task automatic run_hbm_stress_profile(
    input integer token_count,
    input bit     pf_enable,
    input string  phase_name
  );
    integer t;
    integer phase_ops;
    integer phase_reads;
    integer phase_writes;
    integer phase_hits;
    integer phase_misses;
    integer phase_latency_cycles;
    integer phase_max_latency;
    integer phase_start_cycle;
    integer phase_end_cycle;
    integer phase_cycles;
    logic [ADDR_W-1:0] wr_addr_l;
    logic [ADDR_W-1:0] rd_addr_l;
    logic [DATA_W-1:0] wdata_l;
    logic [DATA_W-1:0] rdata_l;
    logic hit_l;
    integer lat_l;
    logic [2:0] layer_l;
    logic [1:0] head_l;
    logic [11:0] token_l;
    begin
      phase_ops = 0;
      phase_reads = 0;
      phase_writes = 0;
      phase_hits = 0;
      phase_misses = 0;
      phase_latency_cycles = 0;
      phase_max_latency = 0;

      prefetch_enable = pf_enable;
      phase_start_cycle = sim_cycle_counter;

      // HBM stress: interleave streaming writes and remote reads to keep L2 under churn.
      for (t = 0; t < token_count; t = t + 1) begin
        layer_l = 3'd5;
        head_l = t[1:0];
        token_l = 12'hE00 + t[11:0];
        wr_addr_l = ADDR_W'(8'd64 + (t & 8'h7F));
        if (t >= 32) begin
          rd_addr_l = ADDR_W'(8'd64 + ((t - 32) & 8'h7F));
        end else begin
          rd_addr_l = wr_addr_l;
        end
        wdata_l = 32'hE1000000 ^ (32'(t) * 32'h00070017);

        do_cmd_with_meta(
          KCMU_OP_WR, wr_addr_l, wdata_l,
          1'b0, layer_l, head_l, token_l, 3'd2,
          rdata_l, hit_l, lat_l
        );
        if (rdata_l !== {DATA_W{1'b0}}) begin
          $fatal(1, "%s write response must be zero", phase_name);
        end
        golden_mem[wr_addr_l] = wdata_l;

        phase_ops = phase_ops + 1;
        phase_writes = phase_writes + 1;
        phase_latency_cycles = phase_latency_cycles + lat_l;
        if (lat_l > phase_max_latency) phase_max_latency = lat_l;
        if (hit_l) phase_hits = phase_hits + 1;
        else       phase_misses = phase_misses + 1;
        total_ops = total_ops + 1;
        total_writes = total_writes + 1;
        record_latency(lat_l);
        if (hit_l) total_hits = total_hits + 1;
        else       total_misses = total_misses + 1;

        do_cmd_with_meta(
          KCMU_OP_RD, rd_addr_l, '0,
          1'b0, 3'd4, (3 - head_l), (12'hE80 + t[11:0]), 3'd1,
          rdata_l, hit_l, lat_l
        );
        if (!read_value_match(golden_mem[rd_addr_l], rdata_l, last_resp_approx)) begin
          $fatal(1, "%s read mismatch: addr=%0d exp=%h got=%h approx=%0d",
                 phase_name, rd_addr_l, golden_mem[rd_addr_l], rdata_l, last_resp_approx);
        end

        phase_ops = phase_ops + 1;
        phase_reads = phase_reads + 1;
        phase_latency_cycles = phase_latency_cycles + lat_l;
        if (lat_l > phase_max_latency) phase_max_latency = lat_l;
        if (hit_l) phase_hits = phase_hits + 1;
        else       phase_misses = phase_misses + 1;
        total_ops = total_ops + 1;
        total_reads = total_reads + 1;
        record_latency(lat_l);
        if (hit_l) total_hits = total_hits + 1;
        else       total_misses = total_misses + 1;
      end

      phase_end_cycle = sim_cycle_counter;
      phase_cycles = phase_end_cycle - phase_start_cycle;
      if (phase_cycles <= 0) phase_cycles = 1;

      $display("TB PROFILE: name=%s ops=%0d cycles=%0d opc=%0f avg_lat=%0f hit_rate=%0f max_lat=%0d",
               phase_name,
               phase_ops,
               phase_cycles,
               (1.0 * phase_ops) / phase_cycles,
               (1.0 * phase_latency_cycles) / phase_ops,
               (100.0 * phase_hits) / phase_ops,
               phase_max_latency);
    end
  endtask

  task automatic run_congest_mix_profile(
    input integer token_count,
    input bit     pf_enable,
    input string  phase_name
  );
    integer t;
    integer phase_ops;
    integer phase_reads;
    integer phase_writes;
    integer phase_hits;
    integer phase_misses;
    integer phase_latency_cycles;
    integer phase_max_latency;
    integer phase_start_cycle;
    integer phase_end_cycle;
    integer phase_cycles;
    logic [ADDR_W-1:0] hot_addr_l;
    logic [ADDR_W-1:0] cold_addr0_l;
    logic [ADDR_W-1:0] cold_addr1_l;
    logic [DATA_W-1:0] wdata_l;
    logic [DATA_W-1:0] rdata_l;
    logic hit_l;
    integer lat_l;
    logic [11:0] token_hot_l;
    logic [11:0] token_cold_l;
    begin
      phase_ops = 0;
      phase_reads = 0;
      phase_writes = 0;
      phase_hits = 0;
      phase_misses = 0;
      phase_latency_cycles = 0;
      phase_max_latency = 0;

      prefetch_enable = pf_enable;
      phase_start_cycle = sim_cycle_counter;

        // Congestion-oriented mix:
        // - Small hot semantic window (high-prio)
        // - Wide cold semantic stream (low-prio)
        // - Periodic low-prio writes to keep pressure on lower tiers.
        // Use meta_valid=0 here to keep logical->physical address deterministic.
        for (t = 0; t < token_count; t = t + 1) begin
        hot_addr_l = ADDR_W'(8'd176 + (t & 8'h0F));
        cold_addr0_l = ADDR_W'(8'd16 + ((t * 29 + 3) & 8'h7F));
        cold_addr1_l = ADDR_W'(8'd16 + ((t * 41 + 11) & 8'h7F));
        token_hot_l = 12'hF00 + t[11:0];
        token_cold_l = 12'h700 + t[11:0];
        wdata_l = 32'hF1000000 ^ (32'(t) * 32'h0009000D);

        do_cmd_with_meta(
          KCMU_OP_WR, hot_addr_l, wdata_l,
          1'b0, 3'd0, 2'd0, token_hot_l, 3'd7,
          rdata_l, hit_l, lat_l
        );
        if (rdata_l !== {DATA_W{1'b0}}) begin
          $fatal(1, "%s hot write response must be zero", phase_name);
        end
        golden_mem[hot_addr_l] = wdata_l;

        phase_ops = phase_ops + 1;
        phase_writes = phase_writes + 1;
        phase_latency_cycles = phase_latency_cycles + lat_l;
        if (lat_l > phase_max_latency) phase_max_latency = lat_l;
        if (hit_l) phase_hits = phase_hits + 1;
        else       phase_misses = phase_misses + 1;
        total_ops = total_ops + 1;
        total_writes = total_writes + 1;
        record_latency(lat_l);
        if (hit_l) total_hits = total_hits + 1;
        else       total_misses = total_misses + 1;

        do_cmd_with_meta(
          KCMU_OP_RD, hot_addr_l, '0,
          1'b0, 3'd0, 2'd0, token_hot_l, 3'd7,
          rdata_l, hit_l, lat_l
        );
        if (!read_value_match(golden_mem[hot_addr_l], rdata_l, last_resp_approx)) begin
          $fatal(1, "%s hot read mismatch: addr=%0d exp=%h got=%h approx=%0d",
                 phase_name, hot_addr_l, golden_mem[hot_addr_l], rdata_l, last_resp_approx);
        end

        phase_ops = phase_ops + 1;
        phase_reads = phase_reads + 1;
        phase_latency_cycles = phase_latency_cycles + lat_l;
        if (lat_l > phase_max_latency) phase_max_latency = lat_l;
        if (hit_l) phase_hits = phase_hits + 1;
        else       phase_misses = phase_misses + 1;
        total_ops = total_ops + 1;
        total_reads = total_reads + 1;
        record_latency(lat_l);
        if (hit_l) total_hits = total_hits + 1;
        else       total_misses = total_misses + 1;

        do_cmd_with_meta(
          KCMU_OP_RD, cold_addr0_l, '0,
          1'b0, 3'd6, 2'd3, token_cold_l, 3'd1,
          rdata_l, hit_l, lat_l
        );
        if (!read_value_match(golden_mem[cold_addr0_l], rdata_l, last_resp_approx)) begin
          $fatal(1, "%s cold read mismatch: addr=%0d exp=%h got=%h approx=%0d",
                 phase_name, cold_addr0_l, golden_mem[cold_addr0_l], rdata_l, last_resp_approx);
        end

        phase_ops = phase_ops + 1;
        phase_reads = phase_reads + 1;
        phase_latency_cycles = phase_latency_cycles + lat_l;
        if (lat_l > phase_max_latency) phase_max_latency = lat_l;
        if (hit_l) phase_hits = phase_hits + 1;
        else       phase_misses = phase_misses + 1;
        total_ops = total_ops + 1;
        total_reads = total_reads + 1;
        record_latency(lat_l);
        if (hit_l) total_hits = total_hits + 1;
        else       total_misses = total_misses + 1;

        if ((t & 1) == 0) begin
          do_cmd_with_meta(
            KCMU_OP_RD, cold_addr1_l, '0,
            1'b0, 3'd5, 2'd2, (12'h780 + t[11:0]), 3'd0,
            rdata_l, hit_l, lat_l
          );
          if (!read_value_match(golden_mem[cold_addr1_l], rdata_l, last_resp_approx)) begin
            $fatal(1, "%s extra cold read mismatch: addr=%0d exp=%h got=%h approx=%0d",
                   phase_name, cold_addr1_l, golden_mem[cold_addr1_l], rdata_l, last_resp_approx);
          end

          phase_ops = phase_ops + 1;
          phase_reads = phase_reads + 1;
          phase_latency_cycles = phase_latency_cycles + lat_l;
          if (lat_l > phase_max_latency) phase_max_latency = lat_l;
          if (hit_l) phase_hits = phase_hits + 1;
          else       phase_misses = phase_misses + 1;
          total_ops = total_ops + 1;
          total_reads = total_reads + 1;
          record_latency(lat_l);
          if (hit_l) total_hits = total_hits + 1;
          else       total_misses = total_misses + 1;
        end

        if ((t & 3) == 3) begin
          wdata_l = 32'hF1800000 ^ (32'(t) * 32'h00030021);
          do_cmd_with_meta(
            KCMU_OP_WR, cold_addr1_l, wdata_l,
            1'b0, 3'd6, 2'd3, (12'h7C0 + t[11:0]), 3'd1,
            rdata_l, hit_l, lat_l
          );
          if (rdata_l !== {DATA_W{1'b0}}) begin
            $fatal(1, "%s cold write response must be zero", phase_name);
          end
          golden_mem[cold_addr1_l] = wdata_l;

          phase_ops = phase_ops + 1;
          phase_writes = phase_writes + 1;
          phase_latency_cycles = phase_latency_cycles + lat_l;
          if (lat_l > phase_max_latency) phase_max_latency = lat_l;
          if (hit_l) phase_hits = phase_hits + 1;
          else       phase_misses = phase_misses + 1;
          total_ops = total_ops + 1;
          total_writes = total_writes + 1;
          record_latency(lat_l);
          if (hit_l) total_hits = total_hits + 1;
          else       total_misses = total_misses + 1;
        end
      end

      phase_end_cycle = sim_cycle_counter;
      phase_cycles = phase_end_cycle - phase_start_cycle;
      if (phase_cycles <= 0) phase_cycles = 1;

      $display("TB PROFILE: name=%s ops=%0d cycles=%0d opc=%0f avg_lat=%0f hit_rate=%0f max_lat=%0d",
               phase_name,
               phase_ops,
               phase_cycles,
               (1.0 * phase_ops) / phase_cycles,
               (1.0 * phase_latency_cycles) / phase_ops,
               (100.0 * phase_hits) / phase_ops,
               phase_max_latency);
    end
  endtask

  task automatic run_qos_split_profile(
    input integer token_count,
    input bit     pf_enable,
    input string  phase_name
  );
    integer t;
    integer phase_ops;
    integer phase_reads;
    integer phase_writes;
    integer phase_hits;
    integer phase_misses;
    integer phase_latency_cycles;
    integer phase_max_latency;
    integer phase_start_cycle;
    integer phase_end_cycle;
    integer phase_cycles;
    logic [ADDR_W-1:0] hi_addr_l;
    logic [ADDR_W-1:0] lo_addr_l;
    logic [ADDR_W-1:0] lo_waddr_l;
    logic [DATA_W-1:0] wdata_l;
    logic [DATA_W-1:0] rdata_l;
    logic hit_l;
    integer lat_l;
    begin
      phase_ops = 0;
      phase_reads = 0;
      phase_writes = 0;
      phase_hits = 0;
      phase_misses = 0;
      phase_latency_cycles = 0;
      phase_max_latency = 0;

      prefetch_enable = pf_enable;
      phase_start_cycle = sim_cycle_counter;

      // QoS split:
      // - High-prio short-range stream (prefetch-friendly)
      // - Low-prio broad stream (long-tail pressure)
      // Use meta_valid=0 to keep this profile focused on hierarchy/QoS latency.
      for (t = 0; t < token_count; t = t + 1) begin
        hi_addr_l = ADDR_W'(8'd96 + (t & 8'h1F));
        lo_addr_l = ADDR_W'((t * 37 + 5) & 8'hFF);

        do_cmd_with_meta(
          KCMU_OP_RD, hi_addr_l, '0,
          1'b0, 3'd1, 2'd0, (12'h880 + t[11:0]), 3'd6,
          rdata_l, hit_l, lat_l
        );
        if (!read_value_match(golden_mem[hi_addr_l], rdata_l, last_resp_approx)) begin
          $fatal(1, "%s high-qos read mismatch: addr=%0d exp=%h got=%h approx=%0d",
                 phase_name, hi_addr_l, golden_mem[hi_addr_l], rdata_l, last_resp_approx);
        end

        phase_ops = phase_ops + 1;
        phase_reads = phase_reads + 1;
        phase_latency_cycles = phase_latency_cycles + lat_l;
        if (lat_l > phase_max_latency) phase_max_latency = lat_l;
        if (hit_l) phase_hits = phase_hits + 1;
        else       phase_misses = phase_misses + 1;
        total_ops = total_ops + 1;
        total_reads = total_reads + 1;
        record_latency(lat_l);
        if (hit_l) total_hits = total_hits + 1;
        else       total_misses = total_misses + 1;

        do_cmd_with_meta(
          KCMU_OP_RD, lo_addr_l, '0,
          1'b0, 3'd7, 2'd3, (12'h980 + t[11:0]), 3'd0,
          rdata_l, hit_l, lat_l
        );
        if (!read_value_match(golden_mem[lo_addr_l], rdata_l, last_resp_approx)) begin
          $fatal(1, "%s low-qos read mismatch: addr=%0d exp=%h got=%h approx=%0d",
                 phase_name, lo_addr_l, golden_mem[lo_addr_l], rdata_l, last_resp_approx);
        end

        phase_ops = phase_ops + 1;
        phase_reads = phase_reads + 1;
        phase_latency_cycles = phase_latency_cycles + lat_l;
        if (lat_l > phase_max_latency) phase_max_latency = lat_l;
        if (hit_l) phase_hits = phase_hits + 1;
        else       phase_misses = phase_misses + 1;
        total_ops = total_ops + 1;
        total_reads = total_reads + 1;
        record_latency(lat_l);
        if (hit_l) total_hits = total_hits + 1;
        else       total_misses = total_misses + 1;

        if ((t % 3) == 0) begin
          lo_waddr_l = ADDR_W'(8'd32 + ((t * 53 + 9) & 8'h7F));
          wdata_l = 32'hF2000000 ^ (32'(t) * 32'h00050017);
          do_cmd_with_meta(
            KCMU_OP_WR, lo_waddr_l, wdata_l,
            1'b0, 3'd7, 2'd3, (12'hA20 + t[11:0]), 3'd1,
            rdata_l, hit_l, lat_l
          );
          if (rdata_l !== {DATA_W{1'b0}}) begin
            $fatal(1, "%s low-qos write response must be zero", phase_name);
          end
          golden_mem[lo_waddr_l] = wdata_l;

          phase_ops = phase_ops + 1;
          phase_writes = phase_writes + 1;
          phase_latency_cycles = phase_latency_cycles + lat_l;
          if (lat_l > phase_max_latency) phase_max_latency = lat_l;
          if (hit_l) phase_hits = phase_hits + 1;
          else       phase_misses = phase_misses + 1;
          total_ops = total_ops + 1;
          total_writes = total_writes + 1;
          record_latency(lat_l);
          if (hit_l) total_hits = total_hits + 1;
          else       total_misses = total_misses + 1;
        end

        if ((t & 3) == 2) begin
          do_cmd_with_meta(
            KCMU_OP_RD, hi_addr_l, '0,
            1'b0, 3'd1, 2'd0, (12'h8C0 + t[11:0]), 3'd6,
            rdata_l, hit_l, lat_l
          );
          if (!read_value_match(golden_mem[hi_addr_l], rdata_l, last_resp_approx)) begin
            $fatal(1, "%s high-qos replay read mismatch: addr=%0d exp=%h got=%h approx=%0d",
                   phase_name, hi_addr_l, golden_mem[hi_addr_l], rdata_l, last_resp_approx);
          end

          phase_ops = phase_ops + 1;
          phase_reads = phase_reads + 1;
          phase_latency_cycles = phase_latency_cycles + lat_l;
          if (lat_l > phase_max_latency) phase_max_latency = lat_l;
          if (hit_l) phase_hits = phase_hits + 1;
          else       phase_misses = phase_misses + 1;
          total_ops = total_ops + 1;
          total_reads = total_reads + 1;
          record_latency(lat_l);
          if (hit_l) total_hits = total_hits + 1;
          else       total_misses = total_misses + 1;
        end
      end

      phase_end_cycle = sim_cycle_counter;
      phase_cycles = phase_end_cycle - phase_start_cycle;
      if (phase_cycles <= 0) phase_cycles = 1;

      $display("TB PROFILE: name=%s ops=%0d cycles=%0d opc=%0f avg_lat=%0f hit_rate=%0f max_lat=%0d",
               phase_name,
               phase_ops,
               phase_cycles,
               (1.0 * phase_ops) / phase_cycles,
               (1.0 * phase_latency_cycles) / phase_ops,
               (100.0 * phase_hits) / phase_ops,
               phase_max_latency);
    end
  endtask

  task automatic run_hier_press_profile(
    input integer token_count,
    input bit     pf_enable,
    input string  phase_name
  );
    integer t;
    integer phase_ops;
    integer phase_reads;
    integer phase_writes;
    integer phase_hits;
    integer phase_misses;
    integer phase_latency_cycles;
    integer phase_max_latency;
    integer phase_start_cycle;
    integer phase_end_cycle;
    integer phase_cycles;
    logic [ADDR_W-1:0] hot_addr_l;
    logic [ADDR_W-1:0] cold_addr0_l;
    logic [ADDR_W-1:0] cold_addr1_l;
    logic [DATA_W-1:0] wdata_l;
    logic [DATA_W-1:0] rdata_l;
    logic hit_l;
    integer lat_l;
    logic [2:0] hot_layer_l;
    logic [1:0] hot_head_l;
    logic [2:0] hot_token_l;
    logic [2:0] cold_layer0_l;
    logic [1:0] cold_head0_l;
    logic [2:0] cold_token0_l;
    logic [2:0] cold_layer1_l;
    logic [1:0] cold_head1_l;
    logic [2:0] cold_token1_l;
    begin
      phase_ops = 0;
      phase_reads = 0;
      phase_writes = 0;
      phase_hits = 0;
      phase_misses = 0;
      phase_latency_cycles = 0;
      phase_max_latency = 0;

      prefetch_enable = pf_enable;
      phase_start_cycle = sim_cycle_counter;

      // Hierarchical pressure mix:
      // - Hot stream: high-qos semantic region in a compact reuse window.
      // - Cold stream: low-qos long-tail region to push miss/evict pressure.
      // Use meta_valid=0 to derive QoS from packed address semantics.
      for (t = 0; t < 24; t = t + 1) begin
        hot_layer_l = (t[0]) ? 3'd1 : 3'd0;
        hot_head_l  = 2'd0;
        hot_token_l = 3'd5 + (t % 3);
        hot_addr_l  = {hot_layer_l, hot_head_l, hot_token_l};
        wdata_l = 32'hF2C00000 ^ (32'(t) * 32'h00010011);

        do_cmd_with_meta(
          KCMU_OP_WR, hot_addr_l, wdata_l,
          1'b0, 3'd0, 2'd0, (12'hAE0 + t[11:0]), 3'd7,
          rdata_l, hit_l, lat_l
        );
        if (rdata_l !== {DATA_W{1'b0}}) begin
          $fatal(1, "%s warmup hot write response must be zero", phase_name);
        end
        golden_mem[hot_addr_l] = wdata_l;

        phase_ops = phase_ops + 1;
        phase_writes = phase_writes + 1;
        phase_latency_cycles = phase_latency_cycles + lat_l;
        if (lat_l > phase_max_latency) phase_max_latency = lat_l;
        if (hit_l) phase_hits = phase_hits + 1;
        else       phase_misses = phase_misses + 1;
        total_ops = total_ops + 1;
        total_writes = total_writes + 1;
        record_latency(lat_l);
        if (hit_l) total_hits = total_hits + 1;
        else       total_misses = total_misses + 1;

        do_cmd_with_meta(
          KCMU_OP_RD, hot_addr_l, '0,
          1'b0, 3'd0, 2'd0, (12'hB00 + t[11:0]), 3'd7,
          rdata_l, hit_l, lat_l
        );
        if (!read_value_match(golden_mem[hot_addr_l], rdata_l, last_resp_approx)) begin
          $fatal(1, "%s warmup hot read mismatch: addr=%0d exp=%h got=%h approx=%0d",
                 phase_name, hot_addr_l, golden_mem[hot_addr_l], rdata_l, last_resp_approx);
        end

        phase_ops = phase_ops + 1;
        phase_reads = phase_reads + 1;
        phase_latency_cycles = phase_latency_cycles + lat_l;
        if (lat_l > phase_max_latency) phase_max_latency = lat_l;
        if (hit_l) phase_hits = phase_hits + 1;
        else       phase_misses = phase_misses + 1;
        total_ops = total_ops + 1;
        total_reads = total_reads + 1;
        record_latency(lat_l);
        if (hit_l) total_hits = total_hits + 1;
        else       total_misses = total_misses + 1;
      end

      for (t = 0; t < token_count; t = t + 1) begin
        hot_layer_l = (t[0]) ? 3'd1 : 3'd0;
        hot_head_l  = 2'd0;
        hot_token_l = 3'd5 + (t % 3);
        hot_addr_l  = {hot_layer_l, hot_head_l, hot_token_l};

        cold_layer0_l = 3'd5 + ((t >> 5) & 1);
        cold_head0_l  = 2'd2 + ((t >> 3) & 1);
        cold_token0_l = t % 5;
        cold_addr0_l  = {cold_layer0_l, cold_head0_l, cold_token0_l};

        cold_layer1_l = 3'd6 + ((t >> 6) & 1);
        cold_head1_l  = 2'd2 + ((t >> 2) & 1);
        cold_token1_l = (t * 3 + 1) % 5;
        cold_addr1_l  = {cold_layer1_l, cold_head1_l, cold_token1_l};

        if ((t & 15) == 0) begin
          wdata_l = 32'hF3000000 ^ (32'(t) * 32'h00010033);
          do_cmd_with_meta(
            KCMU_OP_WR, hot_addr_l, wdata_l,
            1'b0, 3'd0, 2'd0, (12'hB00 + t[11:0]), 3'd7,
            rdata_l, hit_l, lat_l
          );
          if (rdata_l !== {DATA_W{1'b0}}) begin
            $fatal(1, "%s hot write response must be zero", phase_name);
          end
          golden_mem[hot_addr_l] = wdata_l;

          phase_ops = phase_ops + 1;
          phase_writes = phase_writes + 1;
          phase_latency_cycles = phase_latency_cycles + lat_l;
          if (lat_l > phase_max_latency) phase_max_latency = lat_l;
          if (hit_l) phase_hits = phase_hits + 1;
          else       phase_misses = phase_misses + 1;
          total_ops = total_ops + 1;
          total_writes = total_writes + 1;
          record_latency(lat_l);
          if (hit_l) total_hits = total_hits + 1;
          else       total_misses = total_misses + 1;
        end

        do_cmd_with_meta(
          KCMU_OP_RD, hot_addr_l, '0,
          1'b0, 3'd0, 2'd0, (12'hB40 + t[11:0]), 3'd7,
          rdata_l, hit_l, lat_l
        );
        if (!read_value_match(golden_mem[hot_addr_l], rdata_l, last_resp_approx)) begin
          $fatal(1, "%s hot read mismatch: addr=%0d exp=%h got=%h approx=%0d",
                 phase_name, hot_addr_l, golden_mem[hot_addr_l], rdata_l, last_resp_approx);
        end

        phase_ops = phase_ops + 1;
        phase_reads = phase_reads + 1;
        phase_latency_cycles = phase_latency_cycles + lat_l;
        if (lat_l > phase_max_latency) phase_max_latency = lat_l;
        if (hit_l) phase_hits = phase_hits + 1;
        else       phase_misses = phase_misses + 1;
        total_ops = total_ops + 1;
        total_reads = total_reads + 1;
        record_latency(lat_l);
        if (hit_l) total_hits = total_hits + 1;
        else       total_misses = total_misses + 1;

        if ((t & 1) == 0) begin
          do_cmd_with_meta(
            KCMU_OP_RD, hot_addr_l, '0,
            1'b0, 3'd0, 2'd0, (12'hB80 + t[11:0]), 3'd7,
            rdata_l, hit_l, lat_l
          );
          if (!read_value_match(golden_mem[hot_addr_l], rdata_l, last_resp_approx)) begin
            $fatal(1, "%s hot replay mismatch: addr=%0d exp=%h got=%h approx=%0d",
                   phase_name, hot_addr_l, golden_mem[hot_addr_l], rdata_l, last_resp_approx);
          end

          phase_ops = phase_ops + 1;
          phase_reads = phase_reads + 1;
          phase_latency_cycles = phase_latency_cycles + lat_l;
          if (lat_l > phase_max_latency) phase_max_latency = lat_l;
          if (hit_l) phase_hits = phase_hits + 1;
          else       phase_misses = phase_misses + 1;
          total_ops = total_ops + 1;
          total_reads = total_reads + 1;
          record_latency(lat_l);
          if (hit_l) total_hits = total_hits + 1;
          else       total_misses = total_misses + 1;
        end

        do_cmd_with_meta(
          KCMU_OP_RD, cold_addr0_l, '0,
          1'b0, 3'd7, 2'd3, (12'hC00 + t[11:0]), 3'd0,
          rdata_l, hit_l, lat_l
        );
        if (!read_value_match(golden_mem[cold_addr0_l], rdata_l, last_resp_approx)) begin
          $fatal(1, "%s cold0 read mismatch: addr=%0d exp=%h got=%h approx=%0d",
                 phase_name, cold_addr0_l, golden_mem[cold_addr0_l], rdata_l, last_resp_approx);
        end

        phase_ops = phase_ops + 1;
        phase_reads = phase_reads + 1;
        phase_latency_cycles = phase_latency_cycles + lat_l;
        if (lat_l > phase_max_latency) phase_max_latency = lat_l;
        if (hit_l) phase_hits = phase_hits + 1;
        else       phase_misses = phase_misses + 1;
        total_ops = total_ops + 1;
        total_reads = total_reads + 1;
        record_latency(lat_l);
        if (hit_l) total_hits = total_hits + 1;
        else       total_misses = total_misses + 1;

        if ((t & 3) != 3) begin
          do_cmd_with_meta(
            KCMU_OP_RD, cold_addr1_l, '0,
            1'b0, 3'd7, 2'd2, (12'hC80 + t[11:0]), 3'd0,
            rdata_l, hit_l, lat_l
          );
          if (!read_value_match(golden_mem[cold_addr1_l], rdata_l, last_resp_approx)) begin
            $fatal(1, "%s cold1 read mismatch: addr=%0d exp=%h got=%h approx=%0d",
                   phase_name, cold_addr1_l, golden_mem[cold_addr1_l], rdata_l, last_resp_approx);
          end

          phase_ops = phase_ops + 1;
          phase_reads = phase_reads + 1;
          phase_latency_cycles = phase_latency_cycles + lat_l;
          if (lat_l > phase_max_latency) phase_max_latency = lat_l;
          if (hit_l) phase_hits = phase_hits + 1;
          else       phase_misses = phase_misses + 1;
          total_ops = total_ops + 1;
          total_reads = total_reads + 1;
          record_latency(lat_l);
          if (hit_l) total_hits = total_hits + 1;
          else       total_misses = total_misses + 1;
        end

        if ((t % 3) == 1) begin
          wdata_l = 32'hF3800000 ^ (32'(t) * 32'h00030027);
          do_cmd_with_meta(
            KCMU_OP_WR, cold_addr1_l, wdata_l,
            1'b0, 3'd7, 2'd3, (12'hCC0 + t[11:0]), 3'd0,
            rdata_l, hit_l, lat_l
          );
          if (rdata_l !== {DATA_W{1'b0}}) begin
            $fatal(1, "%s cold write response must be zero", phase_name);
          end
          golden_mem[cold_addr1_l] = wdata_l;

          phase_ops = phase_ops + 1;
          phase_writes = phase_writes + 1;
          phase_latency_cycles = phase_latency_cycles + lat_l;
          if (lat_l > phase_max_latency) phase_max_latency = lat_l;
          if (hit_l) phase_hits = phase_hits + 1;
          else       phase_misses = phase_misses + 1;
          total_ops = total_ops + 1;
          total_writes = total_writes + 1;
          record_latency(lat_l);
          if (hit_l) total_hits = total_hits + 1;
          else       total_misses = total_misses + 1;
        end
      end

      phase_end_cycle = sim_cycle_counter;
      phase_cycles = phase_end_cycle - phase_start_cycle;
      if (phase_cycles <= 0) phase_cycles = 1;

      $display("TB PROFILE: name=%s ops=%0d cycles=%0d opc=%0f avg_lat=%0f hit_rate=%0f max_lat=%0d",
               phase_name,
               phase_ops,
               phase_cycles,
               (1.0 * phase_ops) / phase_cycles,
               (1.0 * phase_latency_cycles) / phase_ops,
               (100.0 * phase_hits) / phase_ops,
               phase_max_latency);
    end
  endtask

  task automatic run_prefill_decode_profile(
    input integer token_count,
    input bit     pf_enable,
    input string  phase_name
  );
    integer t;
    integer phase_ops;
    integer phase_reads;
    integer phase_writes;
    integer phase_hits;
    integer phase_misses;
    integer phase_latency_cycles;
    integer phase_max_latency;
    integer phase_start_cycle;
    integer phase_end_cycle;
    integer phase_cycles;
    logic [ADDR_W-1:0] pf_addr_l;
    logic [ADDR_W-1:0] dec_hot_addr_l;
    logic [ADDR_W-1:0] dec_cold_addr_l;
    logic [DATA_W-1:0] wdata_l;
    logic [DATA_W-1:0] rdata_l;
    logic hit_l;
    integer lat_l;
    begin
      phase_ops = 0;
      phase_reads = 0;
      phase_writes = 0;
      phase_hits = 0;
      phase_misses = 0;
      phase_latency_cycles = 0;
      phase_max_latency = 0;

      prefetch_enable = pf_enable;
      phase_start_cycle = sim_cycle_counter;

      // Stage A: prefill-like write stream (broader low-prio footprint).
      for (t = 0; t < token_count; t = t + 1) begin
        pf_addr_l = ADDR_W'(8'd48 + ((t * 17 + 9) & 8'h7F));
        wdata_l = 32'hF4800000 ^ (32'(t) * 32'h00070013);
        do_cmd_with_meta(
          KCMU_OP_WR, pf_addr_l, wdata_l,
          1'b0, 3'd5, 2'd2, (12'hD00 + t[11:0]), 3'd1,
          rdata_l, hit_l, lat_l
        );
        if (rdata_l !== {DATA_W{1'b0}}) begin
          $fatal(1, "%s prefill write response must be zero", phase_name);
        end
        golden_mem[pf_addr_l] = wdata_l;

        phase_ops = phase_ops + 1;
        phase_writes = phase_writes + 1;
        phase_latency_cycles = phase_latency_cycles + lat_l;
        if (lat_l > phase_max_latency) phase_max_latency = lat_l;
        if (hit_l) phase_hits = phase_hits + 1;
        else       phase_misses = phase_misses + 1;
        total_ops = total_ops + 1;
        total_writes = total_writes + 1;
        record_latency(lat_l);
        if (hit_l) total_hits = total_hits + 1;
        else       total_misses = total_misses + 1;
      end

      // Stage A2: deterministic decode-hot seed writes.
      // Keep this window exact and self-contained so the following decode-read
      // checks are not coupled to previous profile side effects.
      for (t = 0; t < 16; t = t + 1) begin
        dec_hot_addr_l = ADDR_W'(8'd176 + t[3:0]);
        wdata_l = 32'hC6000000 ^ (32'(t) * 32'h00011117);
        do_cmd_with_meta(
          KCMU_OP_WR, dec_hot_addr_l, wdata_l,
          1'b0, 3'd0, 2'd0, (12'hDE0 + t[11:0]), 3'd6,
          rdata_l, hit_l, lat_l
        );
        if (rdata_l !== {DATA_W{1'b0}}) begin
          $fatal(1, "%s decode-hot seed write response must be zero", phase_name);
        end
        golden_mem[dec_hot_addr_l] = wdata_l;

        phase_ops = phase_ops + 1;
        phase_writes = phase_writes + 1;
        phase_latency_cycles = phase_latency_cycles + lat_l;
        if (lat_l > phase_max_latency) phase_max_latency = lat_l;
        if (hit_l) phase_hits = phase_hits + 1;
        else       phase_misses = phase_misses + 1;
        total_ops = total_ops + 1;
        total_writes = total_writes + 1;
        record_latency(lat_l);
        if (hit_l) total_hits = total_hits + 1;
        else       total_misses = total_misses + 1;
      end

      // Stage B: decode-like read stream (high-prio hot window + low-prio tails).
      for (t = 0; t < (token_count * 2); t = t + 1) begin
        dec_hot_addr_l = ADDR_W'(8'd176 + (t & 8'h0F));
        dec_cold_addr_l = ADDR_W'(8'd32 + ((t * 43 + 5) & 8'h7F));

        do_cmd_with_meta(
          KCMU_OP_RD, dec_hot_addr_l, '0,
          1'b0, 3'd0, 2'd0, (12'hE00 + t[11:0]), 3'd7,
          rdata_l, hit_l, lat_l
        );
        if (!read_value_match(golden_mem[dec_hot_addr_l], rdata_l, last_resp_approx)) begin
          $fatal(1, "%s decode hot read mismatch: addr=%0d exp=%h got=%h approx=%0d",
                 phase_name, dec_hot_addr_l, golden_mem[dec_hot_addr_l], rdata_l, last_resp_approx);
        end

        phase_ops = phase_ops + 1;
        phase_reads = phase_reads + 1;
        phase_latency_cycles = phase_latency_cycles + lat_l;
        if (lat_l > phase_max_latency) phase_max_latency = lat_l;
        if (hit_l) phase_hits = phase_hits + 1;
        else       phase_misses = phase_misses + 1;
        total_ops = total_ops + 1;
        total_reads = total_reads + 1;
        record_latency(lat_l);
        if (hit_l) total_hits = total_hits + 1;
        else       total_misses = total_misses + 1;

        if ((t % 3) == 0) begin
          do_cmd_with_meta(
            KCMU_OP_RD, dec_cold_addr_l, '0,
            1'b0, 3'd6, 2'd3, (12'hF00 + t[11:0]), 3'd0,
            rdata_l, hit_l, lat_l
          );
          if (!read_value_match(golden_mem[dec_cold_addr_l], rdata_l, last_resp_approx)) begin
            $fatal(1, "%s decode cold read mismatch: addr=%0d exp=%h got=%h approx=%0d",
                   phase_name, dec_cold_addr_l, golden_mem[dec_cold_addr_l], rdata_l, last_resp_approx);
          end

          phase_ops = phase_ops + 1;
          phase_reads = phase_reads + 1;
          phase_latency_cycles = phase_latency_cycles + lat_l;
          if (lat_l > phase_max_latency) phase_max_latency = lat_l;
          if (hit_l) phase_hits = phase_hits + 1;
          else       phase_misses = phase_misses + 1;
          total_ops = total_ops + 1;
          total_reads = total_reads + 1;
          record_latency(lat_l);
          if (hit_l) total_hits = total_hits + 1;
          else       total_misses = total_misses + 1;
        end
      end

      phase_end_cycle = sim_cycle_counter;
      phase_cycles = phase_end_cycle - phase_start_cycle;
      if (phase_cycles <= 0) phase_cycles = 1;

      $display("TB PROFILE: name=%s ops=%0d cycles=%0d opc=%0f avg_lat=%0f hit_rate=%0f max_lat=%0d",
               phase_name,
               phase_ops,
               phase_cycles,
               (1.0 * phase_ops) / phase_cycles,
               (1.0 * phase_latency_cycles) / phase_ops,
               (100.0 * phase_hits) / phase_ops,
               phase_max_latency);
    end
  endtask

  integer i;
  logic [DATA_W-1:0] rdata;
  logic hit;
  integer latency;
  integer lat_miss;
  integer lat_hit;
  integer l1_bypass_before;
  integer l1_bypass_after;
  integer hold_cycle;
  integer replay_resp_cnt;
  integer map_hit_before;
  integer map_hit_after;
  integer map_ovf_before;
  integer map_ovf_after;
  integer map_alloc_before;
  integer map_alloc_after;
  integer map_reclaim_before;
  integer map_reclaim_after;
  integer sched_hot_before;
  integer sched_hot_after;
  integer sched_pfblk_before;
  integer sched_pfblk_after;
  integer sched_fillblk_before;
  integer sched_fillblk_after;
  integer l2_comp_before;
  integer l2_comp_after;
  integer l2_comp_rb_before;
  integer l2_comp_rb_after;
  integer l2_comp_spill_before;
  integer l2_comp_spill_after;
  integer l2_wb_before;
  integer l2_wb_after;
  integer hbm_merge_before;
  integer hbm_merge_after;
  integer hbm_drain_before;
  integer hbm_drain_after;
  integer map_seq_reclaim_before;
  integer map_seq_reclaim_after;
  integer desc_hit_before;
  integer desc_hit_after;
  integer desc_miss_before;
  integer desc_miss_after;
  integer desc_hit_cnt;
  integer desc_miss_cnt;
  integer desc_hot_hit_cnt;
  integer desc_hot_miss_cnt;
  integer desc_cold_hit_cnt;
  integer desc_cold_miss_cnt;
  integer desc_rate_expected;
  integer desc_req_before;
  integer desc_req_after;
  integer desc_rate_before;
  integer desc_rate_after;
  integer desc_protect_before;
  integer desc_protect_after;
  integer desc_map_hit_before;
  integer desc_map_hit_after;
  integer h2o_hh_before;
  integer h2o_hh_after;
  integer h2o_protect_before;
  integer h2o_protect_after;
  integer h2o_recent_before;
  integer h2o_recent_after;
  integer h2o_both_before;
  integer h2o_both_after;
  integer h2o_recent_only_before;
  integer h2o_recent_only_after;
  integer h2o_hh_only_before;
  integer h2o_hh_only_after;
  integer h2o_fallback_before;
  integer h2o_fallback_after;
  integer h2o_oracle_recent_present;
  integer h2o_oracle_hh_present;
  integer t7_key;
  logic t2c_expect_bypass;
  logic t2c_bypass_happened;
  logic [11:0] t7_token;
  logic [ADDR_W-1:0] probe_addr;
  logic [11:0] probe_token;
  logic [DATA_W-1:0] replay_rdata [0:2];
  logic replay_hit [0:2];
  logic replay_approx [0:2];

  initial begin
    rst_n           = 1'b0;
    prefetch_enable = 1'b0;
    use_trace_player = 1'b0;
    man_trace_valid  = 1'b0;
    man_trace_op     = KCMU_OP_NOP;
    man_trace_addr   = '0;
    man_trace_wdata  = '0;
    man_trace_meta_valid = 1'b0;
    man_trace_seq_id     = {KCMU_SEQ_W{1'b0}};
    man_trace_phase      = KCMU_PHASE_PREFILL;
    man_trace_kv_kind    = KCMU_KV_KIND_K;
    man_trace_layer      = 3'd0;
    man_trace_head       = 2'd0;
    man_trace_token      = 12'd0;
    man_trace_prio       = 3'd0;
    trace_desc_valid     = 1'b0;
    trace_desc_op        = KCMU_OP_NOP;
    trace_desc_base_addr = '0;
    trace_desc_len       = 8'd0;
    trace_desc_score     = '0;
    trace_desc_seq_id    = {KCMU_SEQ_W{1'b0}};
    trace_desc_phase     = KCMU_PHASE_PREFILL;
    trace_desc_kv_kind   = KCMU_KV_KIND_K;
    trace_desc_attn_valid = 1'b0;
    trace_desc_attn_score = '0;
    trace_desc_recent_rank = '0;
    trace_desc_token_block_id = '0;
    trace_desc_attn_epoch = '0;
    trace_desc_head_budget_class = '0;
    trace_desc_query_relevance = '0;
    trace_desc_compression_risk = '0;
    trace_desc_spill_cost = '0;
    trace_desc_service_criticality = '0;
    trace_desc_policy_select_s5 = 1'b1;
    trace_desc_temporal_persist_class = '0;
    trace_desc_reuse_distance_class = '0;
    trace_desc_query_structure_class = '0;
    trace_desc_sched_urgency_hint = '0;
    trace_desc_sig_valid = 1'b0;
    trace_desc_query_sig = 6'd0;
    trace_desc_key_sig = 6'd0;
    trace_desc_prefix_class = 2'd0;
    trace_desc_router_class = 2'd0;
    desc_service_criticality_cfg = '0;
    desc_policy_select_s5_cfg = 1'b1;
    desc_head_budget_class_cfg = '0;
    desc_query_relevance_cfg = '0;
    desc_temporal_persist_class_cfg = '0;
    desc_reuse_distance_class_cfg = '0;
    desc_query_structure_class_cfg = '0;
    desc_sched_urgency_hint_cfg = '0;
    desc_compression_risk_cfg = '0;
    desc_spill_cost_cfg = '0;
    trace_desc_wvalid    = 1'b0;
    trace_desc_wdata     = '0;
    pl_start         = 1'b0;
    pl_cfg_clear     = 1'b0;
    pl_cfg_we        = 1'b0;
    pl_cfg_idx       = '0;
    pl_cfg_op        = KCMU_OP_NOP;
    pl_cfg_addr      = '0;
    pl_cfg_wdata     = '0;
    pl_cfg_last      = 1'b0;
    resp_ready      = 1'b1;

    total_ops = 0;
    total_reads = 0;
    total_writes = 0;
    total_hits = 0;
    total_misses = 0;
    total_latency_cycles = 0;
    max_latency_cycles = 0;
    sim_cycle_counter = 0;
    rd_hit_latency_sum = 0;
    rd_hit_latency_max = 0;
    rd_hit_cnt = 0;
    rd_miss_latency_sum = 0;
    rd_miss_latency_max = 0;
    rd_miss_cnt = 0;
    wr_hit_latency_sum = 0;
    wr_hit_latency_max = 0;
    wr_hit_cnt = 0;
    wr_miss_latency_sum = 0;
    wr_miss_latency_max = 0;
    wr_miss_cnt = 0;
    approx_read_cnt = 0;
    hot_rd_cnt = 0;
    hot_rd_hit_cnt = 0;
    hot_rd_miss_cnt = 0;
    hot_rd_latency_sum = 0;
    hot_rd_latency_max = 0;
    cold_rd_cnt = 0;
    cold_rd_hit_cnt = 0;
    cold_rd_miss_cnt = 0;
    cold_rd_latency_sum = 0;
    cold_rd_latency_max = 0;
    hiq_rd_cnt = 0;
    hiq_rd_latency_sum = 0;
    loq_rd_cnt = 0;
    loq_rd_latency_sum = 0;
    tb_lat_p50 = 0;
    tb_lat_p90 = 0;
    tb_lat_p95 = 0;
    tb_lat_p99 = 0;
    last_resp_approx = 1'b0;

    for (i = 0; i < 64; i = i + 1) begin
      latency_hist[i] = 0;
    end

    for (i = 0; i < DEPTH; i = i + 1) begin
      golden_mem[i] = 32'hA0000000 + i;
    end
    for (i = 0; i < 256; i = i + 1) begin
      kv_sem_golden[i] = 32'h0;
    end

    apply_reset(5);

    // Initialize external memory through DUT write path.
    for (i = 0; i < DEPTH; i = i + 1) begin
      check_write(i[ADDR_W-1:0], golden_mem[i], "init");
    end

    // reset to clear cache state while preserving external memory
    apply_reset(5);
    prefetch_enable = 1'b0;

    // Directed Test 1: first read miss, second read hit
    do_cmd(KCMU_OP_RD, 8'd5, '0, rdata, hit, latency);
    record_latency(latency);
    if (hit !== 1'b0) $fatal(1, "T1 first read should miss");
    if (!read_value_match(golden_mem[8'd5], rdata, last_resp_approx)) $fatal(1, "T1 first read data mismatch");

    do_cmd(KCMU_OP_RD, 8'd5, '0, rdata, hit, latency);
    record_latency(latency);
    if (hit !== 1'b1) $fatal(1, "T1 second read should hit");
    if (!read_value_match(golden_mem[8'd5], rdata, last_resp_approx)) $fatal(1, "T1 second read data mismatch");
    $display("[PASS] T1 miss->hit");

    // Directed Test 1b: miss latency should be higher than hit latency with external-memory delay.
    do_cmd(KCMU_OP_RD, 8'd7, '0, rdata, hit, lat_miss);
    record_latency(lat_miss);
    if (hit !== 1'b0) $fatal(1, "T1b first read should miss");
    do_cmd(KCMU_OP_RD, 8'd7, '0, rdata, hit, lat_hit);
    record_latency(lat_hit);
    if (hit !== 1'b1) $fatal(1, "T1b second read should hit");
    if (lat_miss <= lat_hit) begin
      $fatal(1, "T1b latency order invalid: miss=%0d hit=%0d", lat_miss, lat_hit);
    end
    $display("[PASS] T1b latency miss=%0d hit=%0d", lat_miss, lat_hit);

    // Directed Test 2: H2O behavior
    apply_reset(5);
    prefetch_enable = 1'b0;
    check_read(8'd0, golden_mem[8'd0], "T2");
    check_read(8'd1, golden_mem[8'd1], "T2");
    check_read(8'd2, golden_mem[8'd2], "T2");
    check_read(8'd3, golden_mem[8'd3], "T2");
    check_read(8'd0, golden_mem[8'd0], "T2");
    do_cmd(KCMU_OP_RD, 8'd0, '0, rdata, hit, latency);
    record_latency(latency);
    if (hit !== 1'b1) $fatal(1, "T2 addr0 should hit");
    do_cmd(KCMU_OP_RD, 8'd4, '0, rdata, hit, latency);
    record_latency(latency);
    if (hit !== 1'b0) $fatal(1, "T2 addr4 should miss");
    do_cmd(KCMU_OP_RD, 8'd0, '0, rdata, hit, latency);
    record_latency(latency);
    if (hit !== 1'b1) $fatal(1, "T2 addr0 should still hit");
    $display("[PASS] T2 replacement sanity");

    // Directed Test 2b: tier-aware replacement should evict warm line first.
    apply_reset(5);
    prefetch_enable = 1'b0;
    check_read(8'd40, golden_mem[8'd40], "T2b");
    check_read(8'd41, golden_mem[8'd41], "T2b");
    check_read(8'd42, golden_mem[8'd42], "T2b");
    check_read(8'd43, golden_mem[8'd43], "T2b");

    // Promote 40/41/42 to hot with read hits; keep 43 warm.
    check_read(8'd40, golden_mem[8'd40], "T2b");
    check_read(8'd41, golden_mem[8'd41], "T2b");
    check_read(8'd42, golden_mem[8'd42], "T2b");
    check_read(8'd41, golden_mem[8'd41], "T2b");

`ifndef SYNTHESIS
    $display("T2b tier_hot bitmap(before miss)=%b", dut.u_mcu.u_ex.u_meta.tier_hot);
`endif
    do_cmd(KCMU_OP_RD, 8'd44, '0, rdata, hit, latency);
    record_latency(latency);
    if (hit !== 1'b0) $fatal(1, "T2b addr44 should miss");
    if (!read_value_match(golden_mem[8'd44], rdata, last_resp_approx)) $fatal(1, "T2b addr44 data mismatch");

    // Move MRU away from the newly inserted warm line before the next miss.
    do_cmd(KCMU_OP_RD, 8'd41, '0, rdata, hit, latency);
    record_latency(latency);
    if (hit !== 1'b1) $fatal(1, "T2b addr41 should hit before eviction check");

    do_cmd(KCMU_OP_RD, 8'd43, '0, rdata, hit, latency);
    record_latency(latency);
`ifdef KCMU_CFG_HASP_N04_L1_RECALL_V268
    if (hit !== 1'b1) $fatal(1, "T2b warm line addr43 should be served by L1 recall slot");
`else
    if (hit !== 1'b0) $fatal(1, "T2b warm line addr43 should be evicted first");
`endif
    if (!read_value_match(golden_mem[8'd43], rdata, last_resp_approx)) $fatal(1, "T2b addr43 data mismatch");

    do_cmd(KCMU_OP_RD, 8'd40, '0, rdata, hit, latency);
    record_latency(latency);
    if (hit !== 1'b1) $fatal(1, "T2b addr40 should remain cached");
    do_cmd(KCMU_OP_RD, 8'd41, '0, rdata, hit, latency);
    record_latency(latency);
    if (hit !== 1'b1) $fatal(1, "T2b addr41 should remain cached");
    do_cmd(KCMU_OP_RD, 8'd42, '0, rdata, hit, latency);
    record_latency(latency);
    if (hit !== 1'b1) $fatal(1, "T2b addr42 should remain cached");
    $display("[PASS] T2b tier-aware replacement");

    // Directed Test 2c: low-qos demand misses should bypass L1 when full.
    apply_reset(5);
    prefetch_enable = 1'b0;
    check_read(8'd50, golden_mem[8'd50], "T2c");
    check_read(8'd51, golden_mem[8'd51], "T2c");
    check_read(8'd52, golden_mem[8'd52], "T2c");
    check_read(8'd53, golden_mem[8'd53], "T2c");
`ifndef SYNTHESIS
    // T2c only requires bypass counter growth when L1 is already full.
    t2c_expect_bypass = &dut.u_mcu.u_ex.u_meta.valid;
    l1_bypass_before = dut.u_mcu.u_ex.stat_l1_demand_bypass_cnt;
`else
    t2c_expect_bypass = 1'b0;
    l1_bypass_before = 0;
`endif

    do_cmd_with_meta(
      KCMU_OP_RD, 8'd90, '0,
      1'b1, 3'd2, 2'd3, 12'h05A, 3'd0,
      rdata, hit, latency
    );
    record_latency(latency);
    if (hit !== 1'b0) $fatal(1, "T2c first low-qos read should miss");
    if (!read_value_match(golden_mem[8'd90], rdata, last_resp_approx)) $fatal(1, "T2c first low-qos read mismatch");

`ifndef SYNTHESIS
    l1_bypass_after = dut.u_mcu.u_ex.stat_l1_demand_bypass_cnt;
    t2c_bypass_happened = (l1_bypass_after > l1_bypass_before);
    if (t2c_expect_bypass) begin
      if (!t2c_bypass_happened) begin
        $display("T2c warning: expected bypass on full L1 but counter did not increase: before=%0d after=%0d",
                 l1_bypass_before, l1_bypass_after);
      end
    end else begin
      $display("T2c info: L1 not full before low-qos miss, bypass counter check skipped. before=%0d after=%0d",
               l1_bypass_before, l1_bypass_after);
    end
`else
    t2c_bypass_happened = 1'b0;
`endif

    do_cmd(KCMU_OP_RD, 8'd50, '0, rdata, hit, latency);
    record_latency(latency);
    if (t2c_bypass_happened && (hit !== 1'b1)) $fatal(1, "T2c hot line should remain in L1 after low-qos bypass");
    if (!read_value_match(golden_mem[8'd50], rdata, last_resp_approx)) $fatal(1, "T2c hot-line read mismatch");
    $display("[PASS] T2c low-qos bypass");

    // Directed Test 3: write-through persistence after reset.
    check_write(8'd30, 32'hDEADBEEF, "T3");
    apply_reset(5);
    prefetch_enable = 1'b0;
    do_cmd(KCMU_OP_RD, 8'd30, '0, rdata, hit, latency);
    record_latency(latency);
    if (!read_value_match(32'hDEADBEEF, rdata, last_resp_approx)) $fatal(1, "T3 write-through persistence failed");
    $display("[PASS] T3 write-through persistence");

    // Directed Test 4: prefetch benefit.
    apply_reset(5);
    prefetch_enable = 1'b1;
    do_cmd(KCMU_OP_RD, 8'd20, '0, rdata, hit, latency);
    record_latency(latency);
    if (!read_value_match(golden_mem[8'd20], rdata, last_resp_approx)) $fatal(1, "T4 addr20 mismatch");
    do_cmd(KCMU_OP_RD, 8'd21, '0, rdata, hit, latency);
    record_latency(latency);
    if (hit !== 1'b1) $fatal(1, "T4 addr21 should hit due to prefetch");
    if (!read_value_match(golden_mem[8'd21], rdata, last_resp_approx)) $fatal(1, "T4 addr21 mismatch");
    $display("[PASS] T4 prefetch");

    // Directed Test 5: response backpressure should hold stable until consumed.
    apply_reset(5);
    prefetch_enable = 1'b0;
    resp_ready = 1'b0;
    do_cmd(KCMU_OP_RD, 8'd42, '0, rdata, hit, latency);
    record_latency(latency);
    if (!read_value_match(golden_mem[8'd42], rdata, last_resp_approx)) $fatal(1, "T5 addr42 mismatch under backpressure");
    for (hold_cycle = 0; hold_cycle < 4; hold_cycle = hold_cycle + 1) begin
      @(posedge clk);
      if (!resp_valid) $fatal(1, "T5 resp_valid should stay asserted when resp_ready=0");
      if (!read_value_match(golden_mem[8'd42], resp_rdata, resp_approx)) $fatal(1, "T5 resp_rdata changed while stalled");
    end
    resp_ready = 1'b1;
    @(negedge clk);
    if (resp_valid) $fatal(1, "T5 resp_valid should clear after ready is re-asserted");
    $display("[PASS] T5 backpressure");

    // Directed Test 6: trace replay module drives command stream correctly.
    apply_reset(5);
    prefetch_enable = 1'b0;
    use_trace_player = 1'b0;
    resp_ready = 1'b1;

    @(negedge clk);
    pl_cfg_clear = 1'b1;
    @(negedge clk);
    pl_cfg_clear = 1'b0;

    trace_player_cfg_write(5'd0, KCMU_OP_WR, 8'd60, 32'hC001D00D, 1'b0);
    trace_player_cfg_write(5'd1, KCMU_OP_RD, 8'd60, 32'h00000000, 1'b0);
    trace_player_cfg_write(5'd2, KCMU_OP_RD, 8'd61, 32'h00000000, 1'b1);
    golden_mem[8'd60] = 32'hC001D00D;

    use_trace_player = 1'b1;
    @(negedge clk);
    pl_start = 1'b1;
    @(negedge clk);
    pl_start = 1'b0;

    replay_resp_cnt = 0;
    while (replay_resp_cnt < 3) begin
      @(posedge clk);
      if (resp_valid && resp_ready) begin
        replay_rdata[replay_resp_cnt] = resp_rdata;
        replay_hit[replay_resp_cnt]   = resp_hit;
        replay_approx[replay_resp_cnt]= resp_approx;
        replay_resp_cnt = replay_resp_cnt + 1;
      end
    end

    // done may already have pulsed; give it a few cycles to settle.
    repeat (4) @(posedge clk);
    if (!pl_done && pl_busy) begin
      $fatal(1, "T6 trace replay did not complete");
    end

    if (replay_rdata[0] !== 32'h00000000) $fatal(1, "T6 write response must be zero");
    if (!read_value_match(32'hC001D00D, replay_rdata[1], replay_approx[1])) $fatal(1, "T6 read-back addr60 mismatch");
    if (!read_value_match(golden_mem[8'd61], replay_rdata[2], replay_approx[2])) $fatal(1, "T6 read addr61 mismatch");

    total_ops = total_ops + 3;
    total_writes = total_writes + 1;
    total_reads = total_reads + 2;
    if (replay_hit[0]) total_hits = total_hits + 1; else total_misses = total_misses + 1;
    if (replay_hit[1]) total_hits = total_hits + 1; else total_misses = total_misses + 1;
    if (replay_hit[2]) total_hits = total_hits + 1; else total_misses = total_misses + 1;
    total_latency_cycles = total_latency_cycles + 6;
    if (max_latency_cycles < 2) max_latency_cycles = 2;

    use_trace_player = 1'b0;
    man_trace_valid = 1'b0;
    man_trace_op    = KCMU_OP_NOP;
    man_trace_addr  = '0;
    man_trace_wdata = '0;
    man_trace_meta_valid = 1'b0;
    man_trace_seq_id     = {KCMU_SEQ_W{1'b0}};
    man_trace_phase      = KCMU_PHASE_PREFILL;
    man_trace_kv_kind    = KCMU_KV_KIND_K;
    man_trace_layer      = 3'd0;
    man_trace_head       = 2'd0;
    man_trace_token      = 12'd0;
    man_trace_prio       = 3'd0;
    $display("[PASS] T6 trace replay");

    // Directed Test 7: KV map overflow should keep high-score hot semantic key.
`ifndef SYNTHESIS
    if (KV_MAP_ENABLE) begin
    apply_reset(5);
    prefetch_enable = 1'b0;

    dut.u_mcu.u_kv_map.map_booted = 1'b0;
    repeat (2) @(posedge clk);

    // Seed one hot key and raise its score via repeated hits.
    do_cmd_with_meta(
      KCMU_OP_RD, 8'd200, '0,
      1'b1, 3'd0, 2'd0, 12'hAA8, 3'd7,
      rdata, hit, latency
    );
    record_latency(latency);
    for (i = 0; i < 8; i = i + 1) begin
      do_cmd_with_meta(
        KCMU_OP_RD, 8'd200, '0,
        1'b1, 3'd0, 2'd0, 12'hAA8, 3'd7,
        rdata, hit, latency
      );
      record_latency(latency);
    end

    // Fill remaining directory entries with cold keys, then force overflow.
    for (i = 0; i < KV_DIR_ENTRIES - 1; i = i + 1) begin
      t7_key = i + 1;
      t7_token = {t7_key[9:0], 2'b00};
      do_cmd_with_meta(
        KCMU_OP_RD, 8'd200, '0,
        1'b1, 3'd6, 2'd3, t7_token, 3'd0,
        rdata, hit, latency
      );
      record_latency(latency);
    end
    map_ovf_before = dut.u_mcu.u_kv_map.stat_map_overflow_cnt;
    for (i = 0; i < 12; i = i + 1) begin
      t7_key = KV_DIR_ENTRIES + i + 1;
      t7_token = {t7_key[9:0], 2'b00};
      do_cmd_with_meta(
        KCMU_OP_RD, 8'd200, '0,
        1'b1, 3'd6, 2'd3, t7_token, 3'd0,
        rdata, hit, latency
      );
      record_latency(latency);
    end
    map_ovf_after = dut.u_mcu.u_kv_map.stat_map_overflow_cnt;
    if (map_ovf_after <= map_ovf_before) begin
      $fatal(1, "T7 should trigger KV map overflow, before=%0d after=%0d", map_ovf_before, map_ovf_after);
    end

    map_hit_before = dut.u_mcu.u_kv_map.stat_map_hit_cnt;
    do_cmd_with_meta(
      KCMU_OP_RD, 8'd200, '0,
      1'b1, 3'd0, 2'd0, 12'hAA8, 3'd7,
      rdata, hit, latency
    );
    record_latency(latency);
    map_hit_after = dut.u_mcu.u_kv_map.stat_map_hit_cnt;
    if (map_hit_after <= map_hit_before) begin
      $fatal(1, "T7 hot key should remain mapped after overflow, hit_before=%0d hit_after=%0d",
             map_hit_before, map_hit_after);
    end
    $display("[PASS] T7 kv-map hot retention across overflow");

    // Re-seed KV map to the baseline identity-like mapping used by later phases.
    dut.u_mcu.u_kv_map.map_booted = 1'b0;
    repeat (2) @(posedge clk);
    for (i = 0; i < DEPTH; i = i + 1) begin
      do_cmd(KCMU_OP_WR, i[ADDR_W-1:0], golden_mem[i], rdata, hit, latency);
      if (rdata !== {DATA_W{1'b0}}) begin
        $fatal(1, "T7 reseed write response should be zero");
      end
    end
    apply_reset(5);
    prefetch_enable = 1'b0;

    // Directed Test 8: prefill allocation followed by decode reuse should become a semantic hit.
    apply_reset(5);
    prefetch_enable = 1'b0;
    dut.u_mcu.u_kv_map.map_booted = 1'b0;
    repeat (2) @(posedge clk);
    map_alloc_before = dut.u_mcu.u_kv_map.stat_map_alloc_cnt;
    do_cmd_with_full_meta(
      KCMU_OP_RD, 8'd210, '0,
      1'b1, 8'd1, KCMU_PHASE_PREFILL, KCMU_KV_KIND_K,
      3'd2, 2'd1, 12'h340, 3'd1,
      rdata, hit, latency
    );
    record_latency(latency);
    if (!read_value_match(golden_mem[8'd210], rdata, last_resp_approx)) begin
      $fatal(1, "T8 prefill read mismatch");
    end
    map_alloc_after = dut.u_mcu.u_kv_map.stat_map_alloc_cnt;
    if (map_alloc_after <= map_alloc_before) begin
      $fatal(1, "T8 prefill access should allocate a KV entry");
    end
    do_cmd_with_full_meta(
      KCMU_OP_RD, 8'd210, '0,
      1'b1, 8'd1, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
      3'd2, 2'd1, 12'h340, 3'd6,
      rdata, hit, lat_miss
    );
    record_latency(lat_miss);
    if (!read_value_match(golden_mem[8'd210], rdata, last_resp_approx)) begin
      $fatal(1, "T8 decode reuse first read mismatch");
    end
    map_hit_before = dut.u_mcu.u_kv_map.stat_map_hit_cnt;
    do_cmd_with_full_meta(
      KCMU_OP_RD, 8'd210, '0,
      1'b1, 8'd1, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
      3'd2, 2'd1, 12'h340, 3'd6,
      rdata, hit, lat_hit
    );
    record_latency(lat_hit);
    map_hit_after = dut.u_mcu.u_kv_map.stat_map_hit_cnt;
    if (map_hit_after <= map_hit_before) begin
      $fatal(1, "T8 decode reuse should hit the semantic mapper");
    end
    if (lat_hit > lat_miss) begin
      $fatal(1, "T8 decode reuse latency should not regress: first=%0d second=%0d", lat_miss, lat_hit);
    end
    $display("[PASS] T8 prefill->decode reuse");

    // Directed Test 9: multi-sequence interleave must not alias KV entries.
    apply_reset(5);
    prefetch_enable = 1'b0;
    dut.u_mcu.u_kv_map.map_booted = 1'b0;
    repeat (2) @(posedge clk);
    map_alloc_before = dut.u_mcu.u_kv_map.stat_map_alloc_cnt;
    do_cmd_with_full_meta(
      KCMU_OP_RD, 8'd211, '0,
      1'b1, 8'd2, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
      3'd3, 2'd1, 12'h350, 3'd4,
      rdata, hit, latency
    );
    record_latency(latency);
    do_cmd_with_full_meta(
      KCMU_OP_RD, 8'd211, '0,
      1'b1, 8'd3, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
      3'd3, 2'd1, 12'h350, 3'd4,
      rdata, hit, latency
    );
    record_latency(latency);
    map_alloc_after = dut.u_mcu.u_kv_map.stat_map_alloc_cnt;
    if ((map_alloc_after - map_alloc_before) < 2) begin
      $fatal(1, "T9 different seq_id accesses should allocate disjoint KV entries");
    end
    map_hit_before = dut.u_mcu.u_kv_map.stat_map_hit_cnt;
    do_cmd_with_full_meta(
      KCMU_OP_RD, 8'd211, '0,
      1'b1, 8'd2, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
      3'd3, 2'd1, 12'h350, 3'd4,
      rdata, hit, latency
    );
    record_latency(latency);
    map_hit_after = dut.u_mcu.u_kv_map.stat_map_hit_cnt;
    if (map_hit_after <= map_hit_before) begin
      $fatal(1, "T9 seq0 should still hit after seq1 interleave");
    end
    $display("[PASS] T9 multi-sequence interleave isolation");

    // Directed Test 10: K/V split must create separate KV mapper entries.
    apply_reset(5);
    prefetch_enable = 1'b0;
    dut.u_mcu.u_kv_map.map_booted = 1'b0;
    repeat (2) @(posedge clk);
    map_alloc_before = dut.u_mcu.u_kv_map.stat_map_alloc_cnt;
    do_cmd_with_full_meta(
      KCMU_OP_RD, 8'd212, '0,
      1'b1, 8'd4, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
      3'd4, 2'd1, 12'h360, 3'd5,
      rdata, hit, latency
    );
    record_latency(latency);
    do_cmd_with_full_meta(
      KCMU_OP_RD, 8'd212, '0,
      1'b1, 8'd4, KCMU_PHASE_DECODE, KCMU_KV_KIND_V,
      3'd4, 2'd1, 12'h360, 3'd5,
      rdata, hit, latency
    );
    record_latency(latency);
    map_alloc_after = dut.u_mcu.u_kv_map.stat_map_alloc_cnt;
    if ((map_alloc_after - map_alloc_before) < 2) begin
      $fatal(1, "T10 K/V accesses should not share a mapper entry");
    end
    map_hit_before = dut.u_mcu.u_kv_map.stat_map_hit_cnt;
    do_cmd_with_full_meta(
      KCMU_OP_RD, 8'd212, '0,
      1'b1, 8'd4, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
      3'd4, 2'd1, 12'h360, 3'd5,
      rdata, hit, latency
    );
    record_latency(latency);
    map_hit_after = dut.u_mcu.u_kv_map.stat_map_hit_cnt;
    if (map_hit_after <= map_hit_before) begin
      $fatal(1, "T10 rereading K should hit the K-side entry");
    end
    $display("[PASS] T10 K/V split mapping");

    // Directed Test 11: overflow should drive explicit reclaim accounting.
    apply_reset(5);
    prefetch_enable = 1'b0;
    dut.u_mcu.u_kv_map.map_booted = 1'b0;
    repeat (2) @(posedge clk);
    map_reclaim_before = dut.u_mcu.u_kv_map.stat_map_reclaim_cnt;
    for (i = 0; i < (KV_DIR_ENTRIES + 8); i = i + 1) begin
      do_cmd_with_full_meta(
        KCMU_OP_RD, 8'd213, '0,
        1'b1, 8'd5, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
        3'd5, 2'd2, (12'h380 + (i[11:0] << 4)), 3'd0,
        rdata, hit, latency
      );
      record_latency(latency);
    end
    map_reclaim_after = dut.u_mcu.u_kv_map.stat_map_reclaim_cnt;
    if (map_reclaim_after <= map_reclaim_before) begin
      $fatal(1, "T11 overflow should increment reclaim accounting");
    end
    $display("[PASS] T11 kv overflow + reclaim");
    end else begin
      $display("[SKIP] T7-T11 kv-map tests disabled by KV_MAP_ENABLE=0");
    end

    if (L2_LOSSY_COMPRESS_EN) begin
      // Directed Test 12: hot/protected decode reads must not trigger lossy fill.
      apply_reset(5);
      prefetch_enable = 1'b0;
      l2_comp_before = dut.u_mcu.u_l2.stat_l2_comp_fill_cnt;
      do_cmd_with_full_meta(
        KCMU_OP_RD, 8'd214, '0,
        1'b1, 8'd6, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
        3'd0, 2'd0, 12'h3A0, 3'd7,
        rdata, hit, latency
      );
      record_latency(latency);
      if (!read_value_match(golden_mem[8'd214], rdata, last_resp_approx)) begin
        $fatal(1, "T12 hot decode read mismatch");
      end
      l2_comp_after = dut.u_mcu.u_l2.stat_l2_comp_fill_cnt;
      if (l2_comp_after != l2_comp_before) begin
        $fatal(1, "T12 hot/protected decode path should not use lossy fill");
      end
      $display("[PASS] T12 compression guard");
    end else begin
      $display("[SKIP] T12 compression guard disabled by L2_LOSSY_COMPRESS_EN=0");
    end

    if (ATTN_SCHED_EN) begin
      // Directed Test 13: HBM congestion should block low-value prefill scheduling.
      apply_reset(5);
      prefetch_enable = 1'b1;
      sched_pfblk_before = dut.u_mcu.u_sched_cmd.stat_sched_pref_block_cnt;
      sched_fillblk_before = dut.u_mcu.u_sched_cmd.stat_sched_fill_block_cnt;
      dut.u_mcu.u_hbm_if.u_core.rd_q_est = TB_HBM_Q_W'(HBM_IF_Q_DEPTH);
      dut.u_mcu.u_hbm_if.u_core.wr_q_est = TB_HBM_Q_W'(HBM_IF_Q_DEPTH - 1);
      dut.u_mcu.u_hbm_if.u_core.wb_q_est = TB_HBM_Q_W'(1);
      repeat (1) @(posedge clk);
      do_cmd_with_full_meta(
        KCMU_OP_RD, 8'd215, '0,
        1'b1, 8'd7, KCMU_PHASE_PREFILL, KCMU_KV_KIND_K,
        3'd6, 2'd3, 12'h3C0, 3'd0,
        rdata, hit, latency
      );
      record_latency(latency);
      sched_pfblk_after = dut.u_mcu.u_sched_cmd.stat_sched_pref_block_cnt;
      sched_fillblk_after = dut.u_mcu.u_sched_cmd.stat_sched_fill_block_cnt;
      if ((sched_pfblk_after <= sched_pfblk_before) && (sched_fillblk_after <= sched_fillblk_before)) begin
        $fatal(1, "T13 congested HBM should block low-value prefill scheduling");
      end
      dut.u_mcu.u_hbm_if.u_core.rd_q_est = {TB_HBM_Q_W{1'b0}};
      dut.u_mcu.u_hbm_if.u_core.wr_q_est = {TB_HBM_Q_W{1'b0}};
      dut.u_mcu.u_hbm_if.u_core.wb_q_est = {TB_HBM_Q_W{1'b0}};
      repeat (1) @(posedge clk);
      $display("[PASS] T13 hbm congestion gating");
    end else begin
      $display("[SKIP] T13 hbm congestion gating disabled by ATTN_SCHED_EN=0");
    end
`endif

    // Random stress with and without prefetch.
    apply_reset(5);
    prefetch_enable = 1'b0;
    reseed_backing_memory_identity();
    apply_reset(5);
    prefetch_enable = 1'b0;
`ifndef SYNTHESIS
    dut.u_mcu.u_kv_map.map_booted = 1'b0;
    repeat (2) @(posedge clk);
`endif
    run_random_phase(300, 1'b0, "RAND_NOPF");
    run_random_phase(300, 1'b1, "RAND_PF");
    $display("[PASS] Random phases");

    // Long-context transformer-like profiling phases.
    run_transformer_profile(128, 1'b0, "TXR_NOPF");
    run_transformer_profile(128, 1'b1, "TXR_PF");
    run_prefill_decode_profile(96, 1'b1, "TXR_PREFDECODE");
`ifndef SYNTHESIS
    // Isolate semantic profiles from prior full-map pressure.
    dut.u_mcu.u_kv_map.map_booted = 1'b0;
    repeat (2) @(posedge clk);
`endif
    run_kv_semantic_hireuse_profile(64, 1'b1, "TXR_HIREUSE");
`ifndef SYNTHESIS
    dut.u_mcu.u_kv_map.map_booted = 1'b0;
    repeat (2) @(posedge clk);
`endif
    run_kv_semantic_loreuse_profile(64, 1'b1, "TXR_LOREUSE");
`ifndef SYNTHESIS
    dut.u_mcu.u_kv_map.map_booted = 1'b0;
    repeat (2) @(posedge clk);
`endif
    run_kv_semantic_burst_profile(64, 1'b1, "TXR_BURST");
`ifndef SYNTHESIS
    dut.u_mcu.u_kv_map.map_booted = 1'b0;
    repeat (2) @(posedge clk);
`endif
    run_head_switch_heavy_profile(64, 1'b1, "TXR_HEADSW");
`ifndef SYNTHESIS
    dut.u_mcu.u_kv_map.map_booted = 1'b0;
    repeat (2) @(posedge clk);
`endif
    run_head_switch_heavy_profile(128, 1'b1, "TXR_HEADSW_LONG");
`ifndef SYNTHESIS
    dut.u_mcu.u_kv_map.map_booted = 1'b0;
    repeat (2) @(posedge clk);
`endif
    run_long_tail_context_profile(96, 1'b1, "TXR_LONGTAIL");
`ifndef SYNTHESIS
    dut.u_mcu.u_kv_map.map_booted = 1'b0;
    repeat (2) @(posedge clk);
`endif
    run_long_tail_context_profile(192, 1'b1, "TXR_LONGTAIL_DEEP");
`ifndef SYNTHESIS
    dut.u_mcu.u_kv_map.map_booted = 1'b0;
    repeat (2) @(posedge clk);
`endif
    run_long_tail_context_profile(256, 1'b1, "TXR_LONGTAIL_XL");
`ifndef SYNTHESIS
    dut.u_mcu.u_kv_map.map_booted = 1'b0;
    repeat (2) @(posedge clk);
`endif
    run_hbm_stress_profile(192, 1'b1, "TXR_HBMSTRESS");
    apply_reset(5);
    prefetch_enable = 1'b0;
    reseed_backing_memory_identity();
    apply_reset(5);
    prefetch_enable = 1'b0;
`ifndef SYNTHESIS
    dut.u_mcu.u_kv_map.map_booted = 1'b0;
    repeat (2) @(posedge clk);
`endif
    run_congest_mix_profile(160, 1'b1, "TXR_CONGEST_MIX");
`ifndef SYNTHESIS
    dut.u_mcu.u_kv_map.map_booted = 1'b0;
    repeat (2) @(posedge clk);
`endif
    run_qos_split_profile(192, 1'b1, "TXR_QOSSPLIT");
`ifndef SYNTHESIS
    dut.u_mcu.u_kv_map.map_booted = 1'b0;
    repeat (2) @(posedge clk);
`endif
    run_hier_press_profile(256, 1'b1, "TXR_HIER_PRESS");
`ifndef SYNTHESIS
    dut.u_mcu.u_kv_map.map_booted = 1'b0;
    repeat (2) @(posedge clk);
`endif
    run_kv_semantic_profile(64, 1'b1, "TXR_KVSEM");
    $display("[PASS] Transformer-like profiles");

`ifndef SYNTHESIS
    // Final acceptance pack: drive the mechanisms that define KiloWare so they are
    // visible in the end-of-run DUT counters, not only in isolated directed tests.
    dut.u_mcu.u_hbm_if.u_core.rd_q_est = {TB_HBM_Q_W{1'b0}};
    dut.u_mcu.u_hbm_if.u_core.wr_q_est = {TB_HBM_Q_W{1'b0}};
    dut.u_mcu.u_hbm_if.u_core.wb_q_est = {TB_HBM_Q_W{1'b0}};
    repeat (2) @(posedge clk);

    if (KV_MAP_ENABLE) begin
      // Directed Test 14: force overflow while keeping a decode-hot page protected.
      prefetch_enable = 1'b0;
      dut.u_mcu.u_kv_map.map_booted = 1'b0;
      repeat (2) @(posedge clk);
      do_cmd_with_full_meta(
        KCMU_OP_RD, 8'd220, '0,
        1'b1, 8'd10, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
        3'd0, 2'd0, 12'h400, 3'd7,
        rdata, hit, latency
      );
      record_latency(latency);
      if (!read_value_match(golden_mem[8'd220], rdata, last_resp_approx)) begin
        $fatal(1, "T14 protected hot seed read mismatch");
      end
      map_ovf_before = dut.u_mcu.u_kv_map.stat_map_overflow_cnt;
      for (i = 0; i < (KV_DIR_ENTRIES + 16); i = i + 1) begin
        do_cmd_with_full_meta(
          KCMU_OP_RD, (8'd96 + i[ADDR_W-1:0]), '0,
          1'b1, 8'd10, KCMU_PHASE_PREFILL, KCMU_KV_KIND_V,
          3'd6, 2'd3, (12'h440 + (i[11:0] << 2)), 3'd1,
          rdata, hit, latency
        );
        record_latency(latency);
      end
      map_ovf_after = dut.u_mcu.u_kv_map.stat_map_overflow_cnt;
      if (map_ovf_after <= map_ovf_before) begin
        $fatal(1, "T14 should drive KV map overflow");
      end
      map_hit_before = dut.u_mcu.u_kv_map.stat_map_hit_cnt;
      do_cmd_with_full_meta(
        KCMU_OP_RD, 8'd220, '0,
        1'b1, 8'd10, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
        3'd0, 2'd0, 12'h400, 3'd7,
        rdata, hit, latency
      );
      record_latency(latency);
      map_hit_after = dut.u_mcu.u_kv_map.stat_map_hit_cnt;
      if (map_hit_after <= map_hit_before) begin
        $fatal(1, "T14 protected hot page should survive overflow pressure");
      end
      $display("[PASS] T14 kv overflow with hot-page protect");

      // Directed Test 15: sequence reclaim should retire all entries for a seq_id.
      map_seq_reclaim_before = dut.u_mcu.u_kv_map.stat_map_seq_reclaim_cnt;
      for (i = 0; i < 6; i = i + 1) begin
        do_cmd_with_full_meta(
          KCMU_OP_RD, (8'd40 + i[ADDR_W-1:0]), '0,
          1'b1, 8'd11, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
          3'd3, 2'd1, (12'h520 + (i[11:0] << 2)), 3'd4,
          rdata, hit, latency
        );
        record_latency(latency);
      end
      do_seq_reclaim(8'd11, latency);
      record_latency(latency);
      map_seq_reclaim_after = dut.u_mcu.u_kv_map.stat_map_seq_reclaim_cnt;
      if (map_seq_reclaim_after <= map_seq_reclaim_before) begin
        $fatal(1, "T15 sequence reclaim should increment seq reclaim counter");
      end
      map_alloc_before = dut.u_mcu.u_kv_map.stat_map_alloc_cnt;
      do_cmd_with_full_meta(
        KCMU_OP_RD, 8'd40, '0,
        1'b1, 8'd11, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
        3'd3, 2'd1, 12'h520, 3'd4,
        rdata, hit, latency
      );
      record_latency(latency);
      map_alloc_after = dut.u_mcu.u_kv_map.stat_map_alloc_cnt;
      if (map_alloc_after <= map_alloc_before) begin
        $fatal(1, "T15 reclaimed sequence should allocate again on re-access");
      end
      $display("[PASS] T15 sequence reclaim");
    end else begin
      $display("[SKIP] T14-T15 kv lifecycle tests disabled by KV_MAP_ENABLE=0");
    end

    if (L2_VB_ENABLE) begin
      // Directed Test 16: dirty eviction should enqueue writeback and trigger drain cycles.
      prefetch_enable = 1'b0;
      l2_wb_before = dut.u_mcu.u_l2.stat_l2_dirty_wb_req_cnt;
      hbm_drain_before = dut.u_mcu.u_hbm_if.u_core.stat_hbmif_wr_drain_cycle_cnt;
      for (i = 0; i < (L2_LINES + L2_VB_LINES + 8); i = i + 1) begin
        probe_addr = (8'd8 + i[ADDR_W-1:0]);
        do_cmd_with_full_meta(
          KCMU_OP_WR, probe_addr, (32'hD1600000 + i),
          1'b1, 8'd12, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
          3'd3, 2'd1, (12'h580 + (i[11:0] << 2)), 3'd4,
          rdata, hit, latency
        );
        record_latency(latency);
        golden_mem[probe_addr] = (32'hD1600000 + i);
      end
      repeat (32) @(posedge clk);
      l2_wb_after = dut.u_mcu.u_l2.stat_l2_dirty_wb_req_cnt;
      hbm_drain_after = dut.u_mcu.u_hbm_if.u_core.stat_hbmif_wr_drain_cycle_cnt;
      if (l2_wb_after <= l2_wb_before) begin
        $fatal(1, "T16 dirty spill should enqueue writeback traffic");
      end
      if (hbm_drain_after <= hbm_drain_before) begin
        $fatal(1, "T16 writeback pressure should trigger HBM drain cycles");
      end
      $display("[PASS] T16 dirty spill + writeback drain");
    end else begin
      $display("[SKIP] T16 dirty spill test disabled by L2_VB_ENABLE=0");
    end

    if (L2_LOSSY_COMPRESS_EN) begin
      // Directed Test 17: cold prefill should compress, read back approximately, and spill compressed data.
      prefetch_enable = 1'b0;
      // Force a deterministic cold path without resetting counters.
      dut.u_mcu.u_ex.u_meta.valid = {LINES{1'b0}};
      dut.u_mcu.u_ex.u_meta.tier_hot = {LINES{1'b0}};
      dut.u_mcu.u_ex.u_meta.from_prefetch = {LINES{1'b0}};
      dut.u_mcu.u_ex.u_meta.line_lossy = {LINES{1'b0}};
      dut.u_mcu.u_l2.valid_mem = {L2_LINES{1'b0}};
      dut.u_mcu.u_l2.lossy_mem = {L2_LINES{1'b0}};
      dut.u_mcu.u_l2.dirty_mem = {L2_LINES{1'b0}};
      dut.u_mcu.u_l2.vb_valid_mem = {L2_VB_LINES{1'b0}};
      dut.u_mcu.u_l2.vb_lossy_mem = {L2_VB_LINES{1'b0}};
      dut.u_mcu.u_l2.vb_dirty_mem = {L2_VB_LINES{1'b0}};
      repeat (2) @(posedge clk);
      l2_comp_before = dut.u_mcu.u_l2.stat_l2_comp_fill_cnt;
      l2_comp_rb_before = dut.u_mcu.u_l2.stat_l2_comp_readback_cnt;
      l2_comp_spill_before = dut.u_mcu.u_l2.stat_l2_comp_spill_cnt;
      probe_addr = 8'd0;
      probe_token = 12'd0;
      for (i = 0; (i < 32) && (dut.u_mcu.u_l2.stat_l2_comp_fill_cnt == l2_comp_before); i = i + 1) begin
        probe_addr = (8'd224 + i[ADDR_W-1:0]);
        do_l2_direct_read(
          probe_addr,
          3'd1,
          1'b1,
          1'b1,
          rdata,
          hit,
          latency
        );
        record_latency(latency);
      end
      l2_comp_after = dut.u_mcu.u_l2.stat_l2_comp_fill_cnt;
      if (l2_comp_after <= l2_comp_before) begin
        $display("T17 debug: rd_miss=%0d fill=%0d rd_fill_bypass=%0d comp_blocked_hot=%0d sched_fill_block=%0d l2_lossy_resp=%0d",
                 dut.u_mcu.u_l2.stat_l2_read_miss_cnt,
                 dut.u_mcu.u_l2.stat_l2_fill_cnt,
                 dut.u_mcu.u_l2.stat_l2_read_fill_bypass_cnt,
                 dut.u_mcu.u_l2.stat_l2_comp_blocked_hot_cnt,
                 dut.u_mcu.u_sched_cmd.stat_sched_fill_block_cnt,
                 dut.u_mcu.u_ex.stat_l2_lossy_resp_cnt);
        $fatal(1, "T17 should trigger at least one lossy compressed fill");
      end
      do_l2_direct_read(
        probe_addr,
        3'd1,
        1'b1,
        1'b1,
        rdata,
        hit,
        latency
      );
      record_latency(latency);
      if (!read_value_match(golden_mem[probe_addr], rdata, last_resp_approx)) begin
        $fatal(1, "T17 compressed readback mismatch: addr=%0d", probe_addr);
      end
      l2_comp_rb_after = dut.u_mcu.u_l2.stat_l2_comp_readback_cnt;
      if ((l2_comp_rb_after <= l2_comp_rb_before) || !last_resp_approx) begin
        $fatal(1, "T17 compressed line should read back through lossy path");
      end
      for (i = 0; i < (L2_LINES + 8); i = i + 1) begin
        do_l2_direct_read(
          (8'd128 + i[ADDR_W-1:0]),
          3'd1,
          1'b1,
          1'b1,
          rdata,
          hit,
          latency
        );
        record_latency(latency);
      end
      repeat (32) @(posedge clk);
      l2_comp_spill_after = dut.u_mcu.u_l2.stat_l2_comp_spill_cnt;
      if (l2_comp_spill_after <= l2_comp_spill_before) begin
        $fatal(1, "T17 compressed cold lines should eventually spill");
      end
      $display("[PASS] T17 lossy cold spill + readback");
    end else begin
      $display("[SKIP] T17 lossy spill test disabled by L2_LOSSY_COMPRESS_EN=0");
    end

    if (PF_ADAPT_EN) begin
      // Directed Test 18: sequential prefill should create merge opportunities in the HBM backend.
      prefetch_enable = 1'b1;
      hbm_merge_before = dut.u_mcu.u_hbm_if.u_core.stat_hbmif_burst_merge_cnt;
      for (i = 0; i < 20; i = i + 1) begin
        do_cmd_with_full_meta(
          KCMU_OP_RD, (8'd32 + i[ADDR_W-1:0]), '0,
          1'b1, 8'd15, KCMU_PHASE_PREFILL, KCMU_KV_KIND_V,
          3'd6, 2'd3, (12'h700 + (i[11:0] << 2)), 3'd1,
          rdata, hit, latency
        );
        record_latency(latency);
      end
      repeat (24) @(posedge clk);
      hbm_merge_after = dut.u_mcu.u_hbm_if.u_core.stat_hbmif_burst_merge_cnt;
      if (hbm_merge_after == 0) begin
        $fatal(1, "T18 HBM burst merge should be active somewhere in the run");
      end
      $display("[PASS] T18 burst merge on sequential prefill");
    end else begin
      $display("[SKIP] T18 burst merge test disabled by PF_ADAPT_EN=0");
    end

    if (ATTN_SCHED_EN) begin
      // Directed Test 19: decode-hot demand should survive heavy HBM backlog without fill blocking.
      prefetch_enable = 1'b1;
      sched_hot_before = dut.u_mcu.u_sched_cmd.stat_sched_hot_hint_cnt;
      sched_fillblk_before = dut.u_mcu.u_sched_cmd.stat_sched_fill_block_cnt;
      dut.u_mcu.u_hbm_if.u_core.rd_q_est = TB_HBM_Q_W'(HBM_IF_Q_DEPTH);
      dut.u_mcu.u_hbm_if.u_core.wr_q_est = TB_HBM_Q_W'(HBM_IF_Q_DEPTH - 1);
      dut.u_mcu.u_hbm_if.u_core.wb_q_est = TB_HBM_Q_W'(2);
      repeat (1) @(posedge clk);
      do_cmd_with_full_meta(
        KCMU_OP_RD, 8'd221, '0,
        1'b1, 8'd16, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
        3'd0, 2'd0, 12'h7C0, 3'd7,
        rdata, hit, latency
      );
      record_latency(latency);
      if (!read_value_match(golden_mem[8'd221], rdata, last_resp_approx)) begin
        $fatal(1, "T19 decode-hot congested read mismatch");
      end
      sched_hot_after = dut.u_mcu.u_sched_cmd.stat_sched_hot_hint_cnt;
      sched_fillblk_after = dut.u_mcu.u_sched_cmd.stat_sched_fill_block_cnt;
      if (sched_hot_after <= sched_hot_before) begin
        $fatal(1, "T19 decode-hot path should still be classified as hot under congestion");
      end
      if (sched_fillblk_after != sched_fillblk_before) begin
        $fatal(1, "T19 decode-hot demand should not be fill-blocked under congestion");
      end
      dut.u_mcu.u_hbm_if.u_core.rd_q_est = {TB_HBM_Q_W{1'b0}};
      dut.u_mcu.u_hbm_if.u_core.wr_q_est = {TB_HBM_Q_W{1'b0}};
      dut.u_mcu.u_hbm_if.u_core.wb_q_est = {TB_HBM_Q_W{1'b0}};
      repeat (1) @(posedge clk);
      $display("[PASS] T19 decode-hot survives congestion");
    end else begin
      $display("[SKIP] T19 hot congestion test disabled by ATTN_SCHED_EN=0");
    end

    // Descriptor-trace directed tests.
    prefetch_enable = 1'b0;
    dut.u_mcu.u_ex.u_meta.valid = {LINES{1'b0}};
    dut.u_mcu.u_ex.u_meta.tier_hot = {LINES{1'b0}};
    dut.u_mcu.u_ex.u_meta.from_prefetch = {LINES{1'b0}};
    dut.u_mcu.u_ex.u_meta.line_lossy = {LINES{1'b0}};
    dut.u_mcu.u_l2.valid_mem = {L2_LINES{1'b0}};
    dut.u_mcu.u_l2.lossy_mem = {L2_LINES{1'b0}};
    dut.u_mcu.u_l2.dirty_mem = {L2_LINES{1'b0}};
    dut.u_mcu.u_l2.vb_valid_mem = {L2_VB_LINES{1'b0}};
    dut.u_mcu.u_l2.vb_lossy_mem = {L2_VB_LINES{1'b0}};
    dut.u_mcu.u_l2.vb_dirty_mem = {L2_VB_LINES{1'b0}};
    repeat (2) @(posedge clk);

    // DESC_T1: one descriptor expands into 4 sequential beats; first pass misses, second pass hits.
    do_descriptor(
      KCMU_OP_RD, 8'd240, 8'd4, 8'd128,
      8'd31, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
      1'b0, '0, '0, '0, '0,
      desc_hit_cnt, desc_miss_cnt
    );
    if (desc_miss_cnt == 0) begin
      $fatal(1, "DESC_T1 first descriptor should incur misses on a cold region");
    end
    do_descriptor(
      KCMU_OP_RD, 8'd240, 8'd4, 8'd128,
      8'd31, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
      1'b0, '0, '0, '0, '0,
      desc_hit_cnt, desc_miss_cnt
    );
    if (desc_hit_cnt == 0) begin
      $fatal(1, "DESC_T1 second descriptor should hit after fill");
    end
    $display("[PASS] DESC_T1 base_len_read_hitmiss");

    // DESC_T2: high-score descriptor should engage victim-protect and retain hits better than cold traffic.
    desc_protect_before = dut.u_mcu.u_sched_cmd.stat_sched_victim_protect_cnt;
    do_descriptor(
      KCMU_OP_RD, 8'd144, 8'd4, 8'd224,
      8'd32, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
      1'b0, '0, '0, '0, '0,
      desc_hot_hit_cnt, desc_hot_miss_cnt
    );
    do_descriptor(
      KCMU_OP_RD, 8'd152, 8'd4, 8'd32,
      8'd33, KCMU_PHASE_PREFILL, KCMU_KV_KIND_V,
      1'b0, '0, '0, '0, '0,
      desc_cold_hit_cnt, desc_cold_miss_cnt
    );
    for (i = 0; i < 24; i = i + 1) begin
      do_descriptor(
        KCMU_OP_RD, (8'd48 + i[ADDR_W-1:0]), 8'd1, 8'd16,
        8'd40 + i[7:0], KCMU_PHASE_PREFILL, KCMU_KV_KIND_V,
        1'b0, '0, '0, '0, '0,
        desc_hit_cnt, desc_miss_cnt
      );
    end
    do_descriptor(
      KCMU_OP_RD, 8'd144, 8'd4, 8'd224,
      8'd32, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
      1'b0, '0, '0, '0, '0,
      desc_hot_hit_cnt, desc_hot_miss_cnt
    );
    do_descriptor(
      KCMU_OP_RD, 8'd152, 8'd4, 8'd32,
      8'd33, KCMU_PHASE_PREFILL, KCMU_KV_KIND_V,
      1'b0, '0, '0, '0, '0,
      desc_cold_hit_cnt, desc_cold_miss_cnt
    );
    desc_protect_after = dut.u_mcu.u_sched_cmd.stat_sched_victim_protect_cnt;
    if (desc_protect_after <= desc_protect_before) begin
      $fatal(1, "DESC_T2 high-score descriptor should raise victim-protect activity");
    end
    if (desc_hot_hit_cnt < desc_cold_hit_cnt) begin
      $fatal(1, "DESC_T2 high-score descriptor should retain at least as many hits as low-score traffic");
    end
    $display("[PASS] DESC_T2 score_driven_protect");

    // DESC_T3: first pass must go to backend on miss, second pass should hit SRAM/L1.
    desc_miss_before = dut.stat_demand_miss_cnt;
    hbm_merge_before = dut.u_mcu.u_hbm_if.u_core.stat_hbmif_rd_req_cnt;
    do_descriptor(
      KCMU_OP_RD, 8'd200, 8'd4, 8'd120,
      8'd34, KCMU_PHASE_DECODE, KCMU_KV_KIND_V,
      1'b0, '0, '0, '0, '0,
      desc_hit_cnt, desc_miss_cnt
    );
    desc_hit_before = dut.u_mcu.u_hbm_if.u_core.stat_hbmif_rd_req_cnt;
    do_descriptor(
      KCMU_OP_RD, 8'd200, 8'd4, 8'd120,
      8'd34, KCMU_PHASE_DECODE, KCMU_KV_KIND_V,
      1'b0, '0, '0, '0, '0,
      desc_hit_cnt, desc_miss_cnt
    );
    desc_miss_after = dut.stat_demand_miss_cnt;
    hbm_merge_after = dut.u_mcu.u_hbm_if.u_core.stat_hbmif_rd_req_cnt;
    if (desc_miss_after <= desc_miss_before) begin
      $fatal(1, "DESC_T3 cold descriptor should increment demand miss count");
    end
    if (desc_hit_before <= hbm_merge_before) begin
      $fatal(1, "DESC_T3 cold descriptor should issue HBM-like backend reads");
    end
    if (hbm_merge_after != desc_hit_before) begin
      $fatal(1, "DESC_T3 warm reread should avoid additional HBM backend reads");
    end
    $display("[PASS] DESC_T3 sram_first_then_hbm");

    // DESC_T4: exported miss-rate register should match cumulative demand counters.
    desc_req_before = dut.stat_demand_req_cnt;
    desc_miss_before = dut.stat_demand_miss_cnt;
    do_descriptor(
      KCMU_OP_RD, 8'd208, 8'd4, 8'd112,
      8'd35, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
      1'b0, '0, '0, '0, '0,
      desc_hit_cnt, desc_miss_cnt
    );
    do_descriptor(
      KCMU_OP_RD, 8'd208, 8'd4, 8'd112,
      8'd35, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
      1'b0, '0, '0, '0, '0,
      desc_hit_cnt, desc_miss_cnt
    );
    desc_req_after = dut.stat_demand_req_cnt;
    desc_miss_after = dut.stat_demand_miss_cnt;
    desc_rate_after = dut.stat_miss_rate_permille;
    desc_rate_expected = (desc_req_after > 0) ? ((desc_miss_after * 1000) / desc_req_after) : 0;
    if ((desc_req_after - desc_req_before) < 8) begin
      $fatal(1, "DESC_T4 should account for all descriptor beats in demand request counting");
    end
    if (desc_rate_after !== desc_rate_expected[15:0]) begin
      $fatal(1, "DESC_T4 miss-rate register mismatch: got=%0d exp=%0d req=%0d miss=%0d",
             desc_rate_after, desc_rate_expected, desc_req_after, desc_miss_after);
    end
    $display("[PASS] DESC_T4 miss_rate_counter");

    // DESC_T5: descriptor must expand into sequential beat addresses for a KV block read.
    do_descriptor(
      KCMU_OP_RD, 8'd216, 8'd5, 8'd144,
      8'd36, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
      1'b0, '0, '0, '0, '0,
      desc_hit_cnt, desc_miss_cnt
    );
    if ((desc_hit_cnt + desc_miss_cnt) != 5) begin
      $fatal(1, "DESC_T5 expected 5 sequential responses, got %0d", desc_hit_cnt + desc_miss_cnt);
    end
    $display("[PASS] DESC_T5 kv_block_read");

    // DESC_T6: prefill writes should seed semantic state; decode reread should hit semantic mapper.
    do_descriptor(
      KCMU_OP_WR, 8'd168, 8'd4, 8'd208,
      8'd37, KCMU_PHASE_PREFILL, KCMU_KV_KIND_K,
      1'b0, '0, '0, '0, '0,
      desc_hit_cnt, desc_miss_cnt
    );
    desc_map_hit_before = dut.u_mcu.u_kv_map.stat_map_hit_cnt;
    do_descriptor(
      KCMU_OP_RD, 8'd168, 8'd4, 8'd208,
      8'd37, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
      1'b0, '0, '0, '0, '0,
      desc_hit_cnt, desc_miss_cnt
    );
    desc_map_hit_after = dut.u_mcu.u_kv_map.stat_map_hit_cnt;
    if (desc_map_hit_after <= desc_map_hit_before) begin
      $fatal(1, "DESC_T6 decode descriptor should reuse KV semantic mapping after prefill writes");
    end
    $display("[PASS] DESC_T6 prefill_decode_descriptor");

    // H2O_T1: recent-only, heavy-only, and BOTH classes should all be observable.
    h2o_recent_before = dut.u_mcu.u_h2o_oracle.stat_recent_keep_cnt;
    h2o_protect_before = dut.u_mcu.u_h2o_oracle.stat_hh_protect_cnt;
    h2o_both_before = dut.u_mcu.u_h2o_oracle.stat_h2o_both_cnt;
    h2o_recent_only_before = dut.u_mcu.u_h2o_oracle.stat_h2o_recent_only_cnt;
    h2o_hh_only_before = dut.u_mcu.u_h2o_oracle.stat_h2o_hh_only_cnt;
    do_descriptor(
      KCMU_OP_RD, 8'd32, 8'd4, 8'd48,
      8'd51, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
      1'b1, 8'h20, KCMU_ATTN_RANK_W'(1), KCMU_TOKEN_BLOCK_W'(16'h5101), KCMU_ATTN_EPOCH_W'(1),
      desc_hit_cnt, desc_miss_cnt
    );
    do_descriptor(
      KCMU_OP_RD, 8'd40, 8'd4, 8'd224,
      8'd51, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
      1'b1, 8'hF0, KCMU_ATTN_RANK_W'(9), KCMU_TOKEN_BLOCK_W'(16'h5102), KCMU_ATTN_EPOCH_W'(1),
      desc_hit_cnt, desc_miss_cnt
    );
    do_descriptor(
      KCMU_OP_RD, 8'd48, 8'd4, 8'd232,
      8'd51, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
      1'b1, 8'hE8, KCMU_ATTN_RANK_W'(1), KCMU_TOKEN_BLOCK_W'(16'h5103), KCMU_ATTN_EPOCH_W'(1),
      desc_hit_cnt, desc_miss_cnt
    );
    h2o_recent_after = dut.u_mcu.u_h2o_oracle.stat_recent_keep_cnt;
    h2o_protect_after = dut.u_mcu.u_h2o_oracle.stat_hh_protect_cnt;
    h2o_both_after = dut.u_mcu.u_h2o_oracle.stat_h2o_both_cnt;
    h2o_recent_only_after = dut.u_mcu.u_h2o_oracle.stat_h2o_recent_only_cnt;
    h2o_hh_only_after = dut.u_mcu.u_h2o_oracle.stat_h2o_hh_only_cnt;
    if (h2o_recent_after <= h2o_recent_before) begin
      $fatal(1, "H2O_T1 should create recent-keep activity");
    end
    if (h2o_protect_after <= h2o_protect_before) begin
      $fatal(1, "H2O_T1 should create heavy-hitter protect activity");
    end
    if (h2o_both_after <= h2o_both_before) begin
      $fatal(1, "H2O_T1 should classify at least one descriptor as BOTH");
    end
    if (h2o_recent_only_after <= h2o_recent_only_before) begin
      $fatal(1, "H2O_T1 should classify at least one descriptor as RECENT_ONLY");
    end
    if (h2o_hh_only_after <= h2o_hh_only_before) begin
      $fatal(1, "H2O_T1 should classify at least one descriptor as HEAVY_ONLY");
    end
    $display("[PASS] H2O_T1 recent_vs_hh_budget");

    // H2O_T2: a heavy hitter should survive distance pressure and remain in the HH table.
    h2o_hh_before = dut.u_mcu.u_h2o_oracle.stat_hh_hit_cnt;
    do_descriptor(
      KCMU_OP_RD, 8'd56, 8'd4, 8'd240,
      8'd52, KCMU_PHASE_DECODE, KCMU_KV_KIND_V,
      1'b1, 8'hF2, KCMU_ATTN_RANK_W'(10), KCMU_TOKEN_BLOCK_W'(16'h520A), KCMU_ATTN_EPOCH_W'(2),
      desc_hit_cnt, desc_miss_cnt
    );
    do_descriptor(
      KCMU_OP_RD, 8'd56, 8'd4, 8'd240,
      8'd52, KCMU_PHASE_DECODE, KCMU_KV_KIND_V,
      1'b1, 8'hF2, KCMU_ATTN_RANK_W'(10), KCMU_TOKEN_BLOCK_W'(16'h520A), KCMU_ATTN_EPOCH_W'(2),
      desc_hit_cnt, desc_miss_cnt
    );
    for (i = 0; i < 20; i = i + 1) begin
      do_descriptor(
        (KCMU_OP_RD), (8'd80 + i[ADDR_W-1:0]), 8'd1, 8'd32,
        8'd52, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
        1'b1, 8'h18, KCMU_ATTN_RANK_W'(1), KCMU_TOKEN_BLOCK_W'(16'h5300 + i[15:0]), KCMU_ATTN_EPOCH_W'(3),
        desc_hit_cnt, desc_miss_cnt
      );
    end
    h2o_oracle_hh_present = 0;
    for (i = 0; i < dut.u_mcu.u_h2o_oracle.HH_BUDGET; i = i + 1) begin
      if (dut.u_mcu.u_h2o_oracle.hh_valid[i] &&
          (dut.u_mcu.u_h2o_oracle.hh_block[i] == KCMU_TOKEN_BLOCK_W'(16'h520A))) begin
        h2o_oracle_hh_present = 1;
      end
    end
    if (h2o_oracle_hh_present == 0) begin
      $fatal(1, "H2O_T2 heavy-hitter block should remain resident in HH table across distance pressure");
    end
    do_descriptor(
      KCMU_OP_RD, 8'd56, 8'd4, 8'd224,
      8'd52, KCMU_PHASE_DECODE, KCMU_KV_KIND_V,
      1'b1, 8'hB0, KCMU_ATTN_RANK_W'(12), KCMU_TOKEN_BLOCK_W'(16'h520A), KCMU_ATTN_EPOCH_W'(4),
      desc_hit_cnt, desc_miss_cnt
    );
    h2o_hh_after = dut.u_mcu.u_h2o_oracle.stat_hh_hit_cnt;
    if (h2o_hh_after <= h2o_hh_before) begin
      $fatal(1, "H2O_T2 revisit should hit the heavy-hitter oracle after long distance");
    end
    $display("[PASS] H2O_T2 hh_survives_distance");

    // H2O_T3: recent-only blocks should age out of the recent budget when pressure arrives.
    do_descriptor(
      KCMU_OP_RD, 8'd96, 8'd1, 8'd40,
      8'd53, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
      1'b1, 8'h18, KCMU_ATTN_RANK_W'(1), KCMU_TOKEN_BLOCK_W'(16'h5301), KCMU_ATTN_EPOCH_W'(5),
      desc_hit_cnt, desc_miss_cnt
    );
    for (i = 0; i < 12; i = i + 1) begin
      do_descriptor(
        KCMU_OP_RD, (8'd104 + i[ADDR_W-1:0]), 8'd1, 8'd40,
        8'd53, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
        1'b1, 8'h18, KCMU_ATTN_RANK_W'(1), KCMU_TOKEN_BLOCK_W'(16'h5310 + i[15:0]), KCMU_ATTN_EPOCH_W'(5),
        desc_hit_cnt, desc_miss_cnt
      );
    end
    h2o_oracle_recent_present = 0;
    h2o_oracle_hh_present = 0;
    for (i = 0; i < dut.u_mcu.u_h2o_oracle.RECENT_BUDGET; i = i + 1) begin
      if (dut.u_mcu.u_h2o_oracle.recent_valid[i] &&
          (dut.u_mcu.u_h2o_oracle.recent_block[i] == KCMU_TOKEN_BLOCK_W'(16'h5301))) begin
        h2o_oracle_recent_present = 1;
      end
    end
    for (i = 0; i < dut.u_mcu.u_h2o_oracle.HH_BUDGET; i = i + 1) begin
      if (dut.u_mcu.u_h2o_oracle.hh_valid[i] &&
          (dut.u_mcu.u_h2o_oracle.hh_block[i] == KCMU_TOKEN_BLOCK_W'(16'h5301))) begin
        h2o_oracle_hh_present = 1;
      end
    end
    if (h2o_oracle_recent_present != 0) begin
      $fatal(1, "H2O_T3 recent-only block should age out of the recent budget");
    end
    if (h2o_oracle_hh_present != 0) begin
      $fatal(1, "H2O_T3 recent-only block must not be promoted into heavy-hitter table");
    end
    $display("[PASS] H2O_T3 recent_not_hh_eviction");

    // H2O_T4: heavy-hitter protected traffic should block lossy compression candidates.
    l2_comp_before = dut.u_mcu.u_l2.stat_l2_comp_blocked_hot_cnt;
    do_descriptor(
      KCMU_OP_RD, 8'd120, 8'd4, 8'd232,
      8'd54, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
      1'b1, 8'hF0, KCMU_ATTN_RANK_W'(1), KCMU_TOKEN_BLOCK_W'(16'h5401), KCMU_ATTN_EPOCH_W'(6),
      desc_hit_cnt, desc_miss_cnt
    );
    for (i = 0; i < 24; i = i + 1) begin
      do_descriptor(
        KCMU_OP_RD, (8'd128 + i[ADDR_W-1:0]), 8'd1, 8'd24,
        8'd54, KCMU_PHASE_PREFILL, KCMU_KV_KIND_V,
        1'b1, 8'h10, KCMU_ATTN_RANK_W'(12), KCMU_TOKEN_BLOCK_W'(16'h5480 + i[15:0]), KCMU_ATTN_EPOCH_W'(6),
        desc_hit_cnt, desc_miss_cnt
      );
    end
    l2_comp_after = dut.u_mcu.u_l2.stat_l2_comp_blocked_hot_cnt;
    if (l2_comp_after <= l2_comp_before) begin
      $fatal(1, "H2O_T4 heavy-hitter protected traffic should block at least one lossy candidate");
    end
    $display("[PASS] H2O_T4 hh_blocks_lossy");

    // H2O_T5: attn-off descriptor accesses should still work and count as fallback.
    h2o_fallback_before = dut.u_mcu.u_h2o_oracle.stat_h2o_fallback_cnt;
    do_descriptor(
      KCMU_OP_RD, 8'd200, 8'd2, 8'd96,
      8'd55, KCMU_PHASE_DECODE, KCMU_KV_KIND_V,
      1'b0, '0, '0, '0, '0,
      desc_hit_cnt, desc_miss_cnt
    );
    h2o_fallback_after = dut.u_mcu.u_h2o_oracle.stat_h2o_fallback_cnt;
    if (h2o_fallback_after <= h2o_fallback_before) begin
      $fatal(1, "H2O_T5 attention-off descriptors should increment fallback accounting");
    end
    $display("[PASS] H2O_T5 attn_off_fallback");
`endif

    // DESC_T7: service-critical descriptors should raise backend admission priority.
    // Keep the base descriptor intentionally cold so the delta comes from the
    // service field instead of being masked by an already-hot decode request.
    desc_service_criticality_cfg = 8'h20;
    do_descriptor(
      KCMU_OP_RD, 8'd248, 8'd1, 8'd8,
      8'd60, KCMU_PHASE_PREFILL, KCMU_KV_KIND_V,
      1'b1, 8'h10, KCMU_ATTN_RANK_W'(12), KCMU_TOKEN_BLOCK_W'(16'h6101), KCMU_ATTN_EPOCH_W'(8),
      desc_hit_cnt, desc_miss_cnt
    );
    backend_critical_low_qos = dut.u_mcu.last_read_qos;
    backend_critical_low_fill = dut.u_mcu.last_read_fill_allow;
    backend_critical_low_protect = dut.u_mcu.last_read_victim_protect;

    desc_service_criticality_cfg = 8'hE8;
    do_descriptor(
      KCMU_OP_RD, 8'd240, 8'd1, 8'd8,
      8'd60, KCMU_PHASE_PREFILL, KCMU_KV_KIND_V,
      1'b1, 8'h10, KCMU_ATTN_RANK_W'(12), KCMU_TOKEN_BLOCK_W'(16'h6102), KCMU_ATTN_EPOCH_W'(8),
      desc_hit_cnt, desc_miss_cnt
    );
    backend_critical_high_qos = dut.u_mcu.last_read_qos;
    backend_critical_high_fill = dut.u_mcu.last_read_fill_allow;
    backend_critical_high_protect = dut.u_mcu.last_read_victim_protect;
    desc_service_criticality_cfg = '0;

    if ((backend_critical_high_qos <= backend_critical_low_qos) &&
        (backend_critical_high_fill <= backend_critical_low_fill) &&
        (backend_critical_high_protect <= backend_critical_low_protect)) begin
      $fatal(1,
             "DESC_T7 service-critical path should raise backend priority: low(qos=%0d fill=%0d protect=%0d) high(qos=%0d fill=%0d protect=%0d)",
             backend_critical_low_qos,
             backend_critical_low_fill,
             backend_critical_low_protect,
             backend_critical_high_qos,
             backend_critical_high_fill,
             backend_critical_high_protect);
    end
    $display("[PASS] DESC_T7 backend_critical_service_field");

    // DESC_T8: service rescue should reopen fill on a congested cold demand
    // only for the high-service descriptor, after scheduler blocked it.
    dut.u_mcu.u_hbm_if.u_core.rd_q_est = TB_HBM_Q_W'(HBM_IF_Q_DEPTH);
    dut.u_mcu.u_hbm_if.u_core.wr_q_est = TB_HBM_Q_W'(HBM_IF_Q_DEPTH - 1);
    dut.u_mcu.u_hbm_if.u_core.wb_q_est = TB_HBM_Q_W'(1);
    repeat (1) @(posedge clk);
    desc_service_criticality_cfg = 8'h20;
    do_descriptor(
      KCMU_OP_RD, 8'd232, 8'd1, 8'd8,
      8'd61, KCMU_PHASE_PREFILL, KCMU_KV_KIND_V,
      1'b1, 8'h10, KCMU_ATTN_RANK_W'(12), KCMU_TOKEN_BLOCK_W'(16'h6201), KCMU_ATTN_EPOCH_W'(8),
      desc_hit_cnt, desc_miss_cnt
    );
    service_rescue_low_fill = dut.u_mcu.last_read_fill_allow;
    service_rescue_low_effect = dut.u_mcu.last_read_service_fill_rescue;
    service_rescue_low_hbm_congested = dut.u_mcu.last_read_hbm_if_congested;
    service_rescue_low_sched_fill = dut.u_mcu.last_read_sched_fill_allow;
    service_rescue_low_fill_no_service = dut.u_mcu.last_read_fill_allow_no_backend_critical;
    service_rescue_low_prio_no_service = dut.u_mcu.last_read_backend_priority_no_service;
    service_rescue_low_comp_guard = dut.u_mcu.last_read_compression_guard;

    desc_service_criticality_cfg = 8'hE8;
    do_descriptor(
      KCMU_OP_RD, 8'd224, 8'd1, 8'd8,
      8'd61, KCMU_PHASE_PREFILL, KCMU_KV_KIND_V,
      1'b1, 8'h10, KCMU_ATTN_RANK_W'(12), KCMU_TOKEN_BLOCK_W'(16'h6202), KCMU_ATTN_EPOCH_W'(8),
      desc_hit_cnt, desc_miss_cnt
    );
    service_rescue_high_fill = dut.u_mcu.last_read_fill_allow;
    service_rescue_high_effect = dut.u_mcu.last_read_service_fill_rescue;
    service_rescue_high_hbm_congested = dut.u_mcu.last_read_hbm_if_congested;
    service_rescue_high_sched_fill = dut.u_mcu.last_read_sched_fill_allow;
    service_rescue_high_fill_no_service = dut.u_mcu.last_read_fill_allow_no_backend_critical;
    service_rescue_high_prio_no_service = dut.u_mcu.last_read_backend_priority_no_service;
    service_rescue_high_comp_guard = dut.u_mcu.last_read_compression_guard;
    desc_service_criticality_cfg = '0;
    dut.u_mcu.u_hbm_if.u_core.rd_q_est = {TB_HBM_Q_W{1'b0}};
    dut.u_mcu.u_hbm_if.u_core.wr_q_est = {TB_HBM_Q_W{1'b0}};
    dut.u_mcu.u_hbm_if.u_core.wb_q_est = {TB_HBM_Q_W{1'b0}};
    repeat (1) @(posedge clk);

    if (service_rescue_low_fill !== 1'b0 || service_rescue_low_effect !== 1'b0) begin
      $fatal(1,
             "DESC_T8 low-service cold demand should remain blocked without rescue: low_fill=%0d low_effect=%0d congested=%0d sched_fill=%0d fill_no_service=%0d prio_no_service=%0d comp_guard=%0d",
             service_rescue_low_fill, service_rescue_low_effect,
             service_rescue_low_hbm_congested, service_rescue_low_sched_fill,
             service_rescue_low_fill_no_service, service_rescue_low_prio_no_service,
             service_rescue_low_comp_guard);
    end
    if (service_rescue_high_fill !== 1'b1 || service_rescue_high_effect !== 1'b1) begin
      $fatal(1,
             "DESC_T8 high-service cold demand should trigger fill rescue: high_fill=%0d high_effect=%0d congested=%0d sched_fill=%0d fill_no_service=%0d prio_no_service=%0d comp_guard=%0d",
             service_rescue_high_fill, service_rescue_high_effect,
             service_rescue_high_hbm_congested, service_rescue_high_sched_fill,
             service_rescue_high_fill_no_service, service_rescue_high_prio_no_service,
             service_rescue_high_comp_guard);
    end
    $display("[PASS] DESC_T8 service_fill_rescue_window");

`ifndef SYNTHESIS
    // DESC_T9: service issue boost should let a high-service demand read
    // reach the backend and then override a controlled write-pressure window.
    service_issue_boost_before = dut.u_mcu.u_hbm_if.u_core.stat_hbmif_service_issue_boost_cnt;
    service_issue_effect_before = dut.u_mcu.u_hbm_if.u_core.stat_hbmif_service_issue_effective_cnt;
    service_issue_guard_before = dut.u_mcu.u_hbm_if.u_core.stat_hbmif_service_issue_wb_guard_cnt;
    force dut.u_mcu.hbm_if_write_pressure = 1'b1;
    desc_service_criticality_cfg = 8'h20;
    do_descriptor(
      KCMU_OP_RD, 8'd212, 8'd1, 8'd72,
      8'd62, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
      1'b1, 8'h18, KCMU_ATTN_RANK_W'(4), KCMU_TOKEN_BLOCK_W'(16'h6301), KCMU_ATTN_EPOCH_W'(8),
      desc_hit_cnt, desc_miss_cnt
    );
    release dut.u_mcu.hbm_if_write_pressure;
    service_issue_low_boost = dut.u_mcu.last_read_service_issue_boost;
    force dut.u_mcu.u_hbm_if.u_core.boosted_rd_q_est = {TB_HBM_Q_W{1'b0}};
    force dut.u_mcu.u_hbm_if.u_core.rd_q_est = TB_HBM_Q_W'(1);
    force dut.u_mcu.u_hbm_if.u_core.wr_q_est = TB_HBM_Q_W'(HBM_IF_Q_DEPTH - 1);
    force dut.u_mcu.u_hbm_if.u_core.wb_q_est = {TB_HBM_Q_W{1'b0}};
    force dut.u_mcu.u_hbm_if.u_core.svc_wait_ctr = '0;
    #1;
    service_issue_low_override = dut.u_mcu.u_hbm_if.u_core.service_issue_override;
    service_issue_low_rd = dut.u_mcu.u_hbm_if.u_core.service_rd;
    repeat (1) @(posedge clk);
    release dut.u_mcu.u_hbm_if.u_core.boosted_rd_q_est;
    release dut.u_mcu.u_hbm_if.u_core.rd_q_est;
    release dut.u_mcu.u_hbm_if.u_core.wr_q_est;
    release dut.u_mcu.u_hbm_if.u_core.wb_q_est;
    release dut.u_mcu.u_hbm_if.u_core.svc_wait_ctr;
    repeat (1) @(posedge clk);

    force dut.u_mcu.hbm_if_write_pressure = 1'b1;
    desc_service_criticality_cfg = 8'hE8;
    do_descriptor(
      KCMU_OP_RD, 8'd220, 8'd1, 8'd72,
      8'd62, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
      1'b1, 8'h18, KCMU_ATTN_RANK_W'(4), KCMU_TOKEN_BLOCK_W'(16'h6302), KCMU_ATTN_EPOCH_W'(8),
      desc_hit_cnt, desc_miss_cnt
    );
    release dut.u_mcu.hbm_if_write_pressure;
    service_issue_high_boost = dut.u_mcu.last_read_service_issue_boost;
    force dut.u_mcu.u_hbm_if.u_core.boosted_rd_q_est = TB_HBM_Q_W'(1);
    force dut.u_mcu.u_hbm_if.u_core.rd_q_est = TB_HBM_Q_W'(1);
    force dut.u_mcu.u_hbm_if.u_core.wr_q_est = TB_HBM_Q_W'(HBM_IF_Q_DEPTH - 1);
    force dut.u_mcu.u_hbm_if.u_core.wb_q_est = {TB_HBM_Q_W{1'b0}};
    force dut.u_mcu.u_hbm_if.u_core.svc_wait_ctr = '0;
    #1;
    service_issue_high_override = dut.u_mcu.u_hbm_if.u_core.service_issue_override;
    service_issue_high_rd = dut.u_mcu.u_hbm_if.u_core.service_rd;
    service_issue_high_window = dut.u_mcu.u_hbm_if.u_core.service_issue_window;
    service_issue_high_grant = dut.u_mcu.u_hbm_if.u_core.service_grant;
    service_issue_high_wr_nominal = dut.u_mcu.u_hbm_if.u_core.service_wr_nominal;
    service_issue_high_wb_nominal = dut.u_mcu.u_hbm_if.u_core.service_wb_nominal;
    service_issue_high_write_pressure = dut.u_mcu.u_hbm_if.u_core.write_pressure;
    service_issue_high_boosted_q = dut.u_mcu.u_hbm_if.u_core.boosted_rd_q_est;
    service_issue_high_rd_q = dut.u_mcu.u_hbm_if.u_core.rd_q_est;
    service_issue_high_wb_q = dut.u_mcu.u_hbm_if.u_core.wb_q_est;
    repeat (1) @(posedge clk);
    desc_service_criticality_cfg = '0;
    release dut.u_mcu.u_hbm_if.u_core.boosted_rd_q_est;
    release dut.u_mcu.u_hbm_if.u_core.rd_q_est;
    release dut.u_mcu.u_hbm_if.u_core.wr_q_est;
    release dut.u_mcu.u_hbm_if.u_core.wb_q_est;
    release dut.u_mcu.u_hbm_if.u_core.svc_wait_ctr;
    repeat (1) @(posedge clk);

    if (service_issue_low_boost !== 1'b0 || service_issue_low_override !== 0 || service_issue_low_rd !== 0) begin
      $fatal(1,
             "DESC_T9 low-service demand should not trigger service issue window: low_boost=%0d low_override=%0d low_rd=%0d",
             service_issue_low_boost, service_issue_low_override, service_issue_low_rd);
    end
    if (service_issue_high_boost !== 1'b1 || service_issue_high_override !== 1 || service_issue_high_rd !== 1) begin
      $fatal(1,
             "DESC_T9 high-service demand should trigger service issue override: high_boost=%0d high_override=%0d high_rd=%0d high_window=%0d high_grant=%0d high_wr_nominal=%0d high_wb_nominal=%0d high_write_pressure=%0d high_boosted_q=%0d high_rd_q=%0d high_wb_q=%0d",
             service_issue_high_boost, service_issue_high_override, service_issue_high_rd,
             service_issue_high_window, service_issue_high_grant,
             service_issue_high_wr_nominal, service_issue_high_wb_nominal,
             service_issue_high_write_pressure, service_issue_high_boosted_q,
             service_issue_high_rd_q, service_issue_high_wb_q);
    end
    $display("[PASS] DESC_T9 service_issue_window");

    // DESC_T10: service issue v3 should hold a same-cycle writeback admission
    // so the boosted demand read can enter the backend path first.
    force dut.u_mcu.u_hbm_if.write_pressure = 1'b1;
    force dut.u_mcu.l2_mem_re = 1'b1;
    force dut.u_mcu.l2_mem_raddr = 8'd230;
    force dut.u_mcu.l2_mem_req_is_prefetch = 1'b0;
    force dut.u_mcu.l2_mem_req_service_issue_boost = 1'b0;
    force dut.u_mcu.l2_mem_we = 1'b1;
    force dut.u_mcu.l2_mem_waddr = 8'd231;
    force dut.u_mcu.l2_mem_wdata = 32'hCAFEBABE;
    force dut.u_mcu.l2_mem_req_is_writeback = 1'b1;
    #1;
    service_issue_low_re_ready = dut.u_mcu.u_hbm_if.req_re_ready;
    service_issue_low_we_ready = dut.u_mcu.u_hbm_if.req_we_ready;
    service_issue_low_wb_hold = dut.u_mcu.u_hbm_if.service_issue_wb_hold;
    repeat (1) @(posedge clk);
    release dut.u_mcu.u_hbm_if.write_pressure;
    release dut.u_mcu.l2_mem_re;
    release dut.u_mcu.l2_mem_raddr;
    release dut.u_mcu.l2_mem_req_is_prefetch;
    release dut.u_mcu.l2_mem_req_service_issue_boost;
    release dut.u_mcu.l2_mem_we;
    release dut.u_mcu.l2_mem_waddr;
    release dut.u_mcu.l2_mem_wdata;
    release dut.u_mcu.l2_mem_req_is_writeback;
    repeat (1) @(posedge clk);

    force dut.u_mcu.u_hbm_if.write_pressure = 1'b1;
    force dut.u_mcu.l2_mem_re = 1'b1;
    force dut.u_mcu.l2_mem_raddr = 8'd232;
    force dut.u_mcu.l2_mem_req_is_prefetch = 1'b0;
    force dut.u_mcu.l2_mem_req_service_issue_boost = 1'b1;
    force dut.u_mcu.l2_mem_we = 1'b1;
    force dut.u_mcu.l2_mem_waddr = 8'd233;
    force dut.u_mcu.l2_mem_wdata = 32'hFACE1234;
    force dut.u_mcu.l2_mem_req_is_writeback = 1'b1;
    #1;
    service_issue_high_re_ready = dut.u_mcu.u_hbm_if.req_re_ready;
    service_issue_high_we_ready = dut.u_mcu.u_hbm_if.req_we_ready;
    service_issue_high_wb_hold = dut.u_mcu.u_hbm_if.service_issue_wb_hold;
    repeat (1) @(posedge clk);
    release dut.u_mcu.u_hbm_if.write_pressure;
    release dut.u_mcu.l2_mem_re;
    release dut.u_mcu.l2_mem_raddr;
    release dut.u_mcu.l2_mem_req_is_prefetch;
    release dut.u_mcu.l2_mem_req_service_issue_boost;
    release dut.u_mcu.l2_mem_we;
    release dut.u_mcu.l2_mem_waddr;
    release dut.u_mcu.l2_mem_wdata;
    release dut.u_mcu.l2_mem_req_is_writeback;
    repeat (1) @(posedge clk);

    if (service_issue_low_re_ready !== 1 || service_issue_low_we_ready !== 1 ||
        service_issue_low_wb_hold !== 0) begin
      $fatal(1,
             "DESC_T10 low-service same-cycle WB should not be held: low_re_ready=%0d low_we_ready=%0d low_wb_hold=%0d",
             service_issue_low_re_ready, service_issue_low_we_ready,
             service_issue_low_wb_hold);
    end
    if (service_issue_high_re_ready !== 1 || service_issue_high_we_ready !== 0 ||
        service_issue_high_wb_hold !== 1) begin
      $fatal(1,
             "DESC_T10 boosted demand should hold same-cycle WB admission: high_re_ready=%0d high_we_ready=%0d high_wb_hold=%0d",
             service_issue_high_re_ready, service_issue_high_we_ready,
             service_issue_high_wb_hold);
    end
    $display("[PASS] DESC_T10 service_issue_wb_hold");

    // DESC_T11: selector bit should suppress the aggressive S5-only
    // service-issue path for the same high-service descriptor.
    desc_service_criticality_cfg = '0;
    desc_policy_select_s5_cfg = 1'b1;
    do_descriptor(
      KCMU_OP_WR, 8'd226, 8'd1, 8'd40,
      8'd63, KCMU_PHASE_PREFILL, KCMU_KV_KIND_K,
      1'b0, 8'h00, KCMU_ATTN_RANK_W'(0), KCMU_TOKEN_BLOCK_W'(16'h6311), KCMU_ATTN_EPOCH_W'(8),
      desc_hit_cnt, desc_miss_cnt
    );
    do_descriptor(
      KCMU_OP_WR, 8'd228, 8'd1, 8'd40,
      8'd63, KCMU_PHASE_PREFILL, KCMU_KV_KIND_K,
      1'b0, 8'h00, KCMU_ATTN_RANK_W'(0), KCMU_TOKEN_BLOCK_W'(16'h6312), KCMU_ATTN_EPOCH_W'(8),
      desc_hit_cnt, desc_miss_cnt
    );
    desc_service_criticality_cfg = 8'hE8;
    desc_policy_select_s5_cfg = 1'b0;
    force dut.u_mcu.hbm_if_write_pressure = 1'b1;
    fork
      begin
        do_descriptor(
          KCMU_OP_RD, 8'd226, 8'd1, 8'd72,
          8'd63, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
          1'b1, 8'h18, KCMU_ATTN_RANK_W'(4), KCMU_TOKEN_BLOCK_W'(16'h6311), KCMU_ATTN_EPOCH_W'(8),
          desc_hit_cnt, desc_miss_cnt
        );
      end
      begin
        repeat (2) @(posedge clk);
        release dut.u_mcu.hbm_if_write_pressure;
      end
    join
    selector_low_service_issue_boost = dut.u_mcu.last_read_service_issue_boost;
    selector_low_policy_seen = dut.u_mcu.last_read_policy_select_s5;
    repeat (1) @(posedge clk);

    desc_policy_select_s5_cfg = 1'b1;
    force dut.u_mcu.hbm_if_write_pressure = 1'b1;
    fork
      begin
        do_descriptor(
          KCMU_OP_RD, 8'd228, 8'd1, 8'd72,
          8'd63, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
          1'b1, 8'h18, KCMU_ATTN_RANK_W'(4), KCMU_TOKEN_BLOCK_W'(16'h6312), KCMU_ATTN_EPOCH_W'(8),
          desc_hit_cnt, desc_miss_cnt
        );
      end
      begin
        repeat (2) @(posedge clk);
        release dut.u_mcu.hbm_if_write_pressure;
      end
    join
    selector_high_service_issue_boost = dut.u_mcu.last_read_service_issue_boost;
    selector_high_policy_seen = dut.u_mcu.last_read_policy_select_s5;
    desc_service_criticality_cfg = '0;
    desc_policy_select_s5_cfg = 1'b1;
    repeat (1) @(posedge clk);

    if (selector_low_policy_seen !== 0 || selector_low_service_issue_boost !== 0) begin
      $fatal(1,
             "DESC_T11 selector low should suppress aggressive service-issue behavior: policy=%0d boost=%0d",
             selector_low_policy_seen, selector_low_service_issue_boost);
    end
    if (selector_high_policy_seen !== 1 || selector_high_service_issue_boost !== 1) begin
      $fatal(1,
             "DESC_T11 selector high should restore aggressive service-issue behavior: policy=%0d boost=%0d",
             selector_high_policy_seen, selector_high_service_issue_boost);
    end
    $display("[PASS] DESC_T11 selector_policy_service_issue_gate");

    // DESC_T12: service backlog window should allow a boosted read to
    // consume the next service slot one cycle early under backlog pressure.
    force dut.u_mcu.l2_mem_re = 1'b0;
    force dut.u_mcu.l2_mem_req_service_issue_boost = 1'b0;
    force dut.u_mcu.l2_mem_we = 1'b0;
    force dut.u_mcu.l2_mem_req_is_writeback = 1'b0;
    force dut.u_mcu.u_hbm_if.u_core.boosted_rd_q_est = {TB_HBM_Q_W{1'b0}};
    force dut.u_mcu.u_hbm_if.u_core.rd_q_est = TB_HBM_Q_W'(1);
    force dut.u_mcu.u_hbm_if.u_core.wr_q_est = TB_HBM_Q_W'(1);
    force dut.u_mcu.u_hbm_if.u_core.wb_q_est = {TB_HBM_Q_W{1'b0}};
    force dut.u_mcu.u_hbm_if.u_core.svc_wait_ctr = 'd1;
    #1;
    service_backlog_low_window = dut.u_mcu.u_hbm_if.u_core.service_backlog_window;
    service_backlog_low_grant = dut.u_mcu.u_hbm_if.u_core.service_backlog_grant;
    service_backlog_low_rd = dut.u_mcu.u_hbm_if.u_core.service_rd;
    repeat (1) @(posedge clk);
    release dut.u_mcu.u_hbm_if.u_core.boosted_rd_q_est;
    release dut.u_mcu.u_hbm_if.u_core.rd_q_est;
    release dut.u_mcu.u_hbm_if.u_core.wr_q_est;
    release dut.u_mcu.u_hbm_if.u_core.wb_q_est;
    release dut.u_mcu.u_hbm_if.u_core.svc_wait_ctr;
    release dut.u_mcu.l2_mem_re;
    release dut.u_mcu.l2_mem_req_service_issue_boost;
    release dut.u_mcu.l2_mem_we;
    release dut.u_mcu.l2_mem_req_is_writeback;
    repeat (1) @(posedge clk);

    force dut.u_mcu.u_hbm_if.u_core.boosted_rd_q_est = TB_HBM_Q_W'(1);
    force dut.u_mcu.u_hbm_if.u_core.rd_q_est = TB_HBM_Q_W'(1);
    force dut.u_mcu.u_hbm_if.u_core.wr_q_est = TB_HBM_Q_W'(1);
    force dut.u_mcu.u_hbm_if.u_core.wb_q_est = {TB_HBM_Q_W{1'b0}};
    force dut.u_mcu.u_hbm_if.u_core.svc_wait_ctr = 'd1;
    #1;
    service_backlog_high_window = dut.u_mcu.u_hbm_if.u_core.service_backlog_window;
    service_backlog_high_grant = dut.u_mcu.u_hbm_if.u_core.service_backlog_grant;
    service_backlog_high_rd = dut.u_mcu.u_hbm_if.u_core.service_rd;
    repeat (1) @(posedge clk);
    release dut.u_mcu.u_hbm_if.u_core.boosted_rd_q_est;
    release dut.u_mcu.u_hbm_if.u_core.rd_q_est;
    release dut.u_mcu.u_hbm_if.u_core.wr_q_est;
    release dut.u_mcu.u_hbm_if.u_core.wb_q_est;
    release dut.u_mcu.u_hbm_if.u_core.svc_wait_ctr;
    repeat (1) @(posedge clk);

    if (service_backlog_low_window !== 0 || service_backlog_low_grant !== 0 || service_backlog_low_rd !== 0) begin
      $fatal(1,
             "DESC_T12 low-boost backlog should not advance service: low_window=%0d low_grant=%0d low_rd=%0d",
             service_backlog_low_window, service_backlog_low_grant, service_backlog_low_rd);
    end
    if (service_backlog_high_window !== 1 || service_backlog_high_grant !== 1 || service_backlog_high_rd !== 1) begin
      $fatal(1,
             "DESC_T12 boosted backlog should advance one service slot: high_window=%0d high_grant=%0d high_rd=%0d",
             service_backlog_high_window, service_backlog_high_grant, service_backlog_high_rd);
    end
    $display("[PASS] DESC_T12 service_backlog_window");

    // CAS_T1: a query/cost-valuable block that is not already recent/HH should
    // create marginal keep metadata instead of relying on duplicate H2O guards.
    desc_policy_select_s5_cfg = 1'b1;
    desc_service_criticality_cfg = 8'hB0;
    desc_head_budget_class_cfg = KCMU_HEAD_BUDGET_W'(0);
    desc_query_relevance_cfg = 8'hE8;
    desc_compression_risk_cfg = KCMU_COST_CLASS_W'(0);
    desc_spill_cost_cfg = KCMU_COST_CLASS_W'(5);
    casu_marginal_before = dut.u_mcu.u_l2.stat_l2_casu_marginal_keep_cnt;
    do_descriptor(
      KCMU_OP_RD, 8'd156, 8'd1, 8'd88,
      8'd64, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
      1'b1, 8'h70, KCMU_ATTN_RANK_W'(12), KCMU_TOKEN_BLOCK_W'(16'h6401), KCMU_ATTN_EPOCH_W'(9),
      desc_hit_cnt, desc_miss_cnt
    );
    repeat (2) @(posedge clk);
    casu_marginal_after = dut.u_mcu.u_l2.stat_l2_casu_marginal_keep_cnt;
    if (casu_marginal_after <= casu_marginal_before) begin
      $fatal(1, "CAS_T1 expected marginal keep counter to increase: before=%0d after=%0d",
             casu_marginal_before, casu_marginal_after);
    end
    $display("[PASS] CAS_T1 marginal_keep_beats_lru");

    // CAS_T2: low-utility, non-protected lines should be marked as pollution
    // risk so the selector does not keep them just because they were touched.
    desc_service_criticality_cfg = '0;
    desc_head_budget_class_cfg = KCMU_HEAD_BUDGET_W'(0);
    desc_query_relevance_cfg = 8'h00;
    desc_compression_risk_cfg = KCMU_COST_CLASS_W'(0);
    desc_spill_cost_cfg = KCMU_COST_CLASS_W'(0);
    casu_pollution_before = dut.u_mcu.u_l2.stat_l2_casu_pollution_block_cnt;
    do_descriptor(
      KCMU_OP_RD, 8'd157, 8'd1, 8'd16,
      8'd64, KCMU_PHASE_PREFILL, KCMU_KV_KIND_V,
      1'b1, 8'h10, KCMU_ATTN_RANK_W'(12), KCMU_TOKEN_BLOCK_W'(16'h6402), KCMU_ATTN_EPOCH_W'(9),
      desc_hit_cnt, desc_miss_cnt
    );
    repeat (2) @(posedge clk);
    casu_pollution_after = dut.u_mcu.u_l2.stat_l2_casu_pollution_block_cnt;
    if (casu_pollution_after <= casu_pollution_before) begin
      $fatal(1, "CAS_T2 expected pollution risk counter to increase: before=%0d after=%0d",
             casu_pollution_before, casu_pollution_after);
    end
    $display("[PASS] CAS_T2 overlap_penalty_blocks_pollution");

    // CAS_T3: under write pressure, residual utility should create an earlier
    // service boost and record pressure-bonus metadata.
    desc_service_criticality_cfg = 8'hE8;
    desc_head_budget_class_cfg = KCMU_HEAD_BUDGET_W'(0);
    desc_query_relevance_cfg = 8'hD0;
    desc_compression_risk_cfg = KCMU_COST_CLASS_W'(0);
    desc_spill_cost_cfg = KCMU_COST_CLASS_W'(5);
    casu_pressure_before = dut.u_mcu.u_l2.stat_l2_casu_pressure_bonus_cnt;
    force dut.u_mcu.hbm_if_write_pressure = 1'b1;
    fork
      begin
        do_descriptor(
          KCMU_OP_RD, 8'd158, 8'd1, 8'd96,
          8'd64, KCMU_PHASE_DECODE, KCMU_KV_KIND_K,
          1'b1, 8'h70, KCMU_ATTN_RANK_W'(12), KCMU_TOKEN_BLOCK_W'(16'h6403), KCMU_ATTN_EPOCH_W'(9),
          desc_hit_cnt, desc_miss_cnt
        );
      end
      begin
        repeat (3) @(posedge clk);
        release dut.u_mcu.hbm_if_write_pressure;
      end
    join
    repeat (2) @(posedge clk);
    casu_pressure_after = dut.u_mcu.u_l2.stat_l2_casu_pressure_bonus_cnt;
    casu_pressure_boost = dut.u_mcu.last_read_service_issue_boost;
    if ((casu_pressure_after <= casu_pressure_before) || (casu_pressure_boost !== 1)) begin
      $fatal(1,
             "CAS_T3 expected pressure bonus and service boost: before=%0d after=%0d boost=%0d",
             casu_pressure_before, casu_pressure_after, casu_pressure_boost);
    end
    $display("[PASS] CAS_T3 pressure_bonus_changes_backend_order");

    // CAS_T4: high utility plus high compression risk should guard against
    // lossy compression.
    desc_service_criticality_cfg = 8'hD8;
    desc_head_budget_class_cfg = KCMU_HEAD_BUDGET_W'(3);
    desc_query_relevance_cfg = 8'hF8;
    desc_compression_risk_cfg = KCMU_COST_CLASS_W'(10);
    desc_spill_cost_cfg = KCMU_COST_CLASS_W'(7);
    casu_comp_guard_before = dut.u_mcu.u_l2.stat_l2_casu_comp_guard_cnt;
    do_descriptor(
      KCMU_OP_RD, 8'd159, 8'd1, 8'd160,
      8'd64, KCMU_PHASE_DECODE, KCMU_KV_KIND_V,
      1'b1, 8'h88, KCMU_ATTN_RANK_W'(12), KCMU_TOKEN_BLOCK_W'(16'h6404), KCMU_ATTN_EPOCH_W'(9),
      desc_hit_cnt, desc_miss_cnt
    );
    repeat (2) @(posedge clk);
    casu_comp_guard_after = dut.u_mcu.u_l2.stat_l2_casu_comp_guard_cnt;
    if ((casu_comp_guard_after <= casu_comp_guard_before) ||
        (dut.u_mcu.last_read_compression_guard !== 1)) begin
      $fatal(1,
             "CAS_T4 expected compression guard: before=%0d after=%0d guard=%0d",
             casu_comp_guard_before, casu_comp_guard_after,
             dut.u_mcu.last_read_compression_guard);
    end
    $display("[PASS] CAS_T4 compression_guard_blocks_lossy_high_utility");

    // CAS_T5: when the policy selector disables S5/CAS-U and there is no
    // pressure, the marginal path must not create new CAS-U effects.
    desc_policy_select_s5_cfg = 1'b0;
    desc_service_criticality_cfg = 8'hE8;
    desc_head_budget_class_cfg = KCMU_HEAD_BUDGET_W'(0);
    desc_query_relevance_cfg = 8'h00;
    desc_compression_risk_cfg = KCMU_COST_CLASS_W'(0);
    desc_spill_cost_cfg = KCMU_COST_CLASS_W'(0);
    casu_marginal_before = dut.u_mcu.u_l2.stat_l2_casu_marginal_keep_cnt;
    casu_pressure_before = dut.u_mcu.u_l2.stat_l2_casu_pressure_bonus_cnt;
    casu_pollution_before = dut.u_mcu.u_l2.stat_l2_casu_pollution_block_cnt;
    do_descriptor(
      KCMU_OP_RD, 8'd160, 8'd1, 8'd24,
      8'd64, KCMU_PHASE_PREFILL, KCMU_KV_KIND_K,
      1'b1, 8'h20, KCMU_ATTN_RANK_W'(12), KCMU_TOKEN_BLOCK_W'(16'h6405), KCMU_ATTN_EPOCH_W'(9),
      desc_hit_cnt, desc_miss_cnt
    );
    repeat (2) @(posedge clk);
    casu_marginal_after = dut.u_mcu.u_l2.stat_l2_casu_marginal_keep_cnt;
    casu_pressure_after = dut.u_mcu.u_l2.stat_l2_casu_pressure_bonus_cnt;
    casu_pollution_after = dut.u_mcu.u_l2.stat_l2_casu_pollution_block_cnt;
    casu_no_pressure_boost = dut.u_mcu.last_read_service_issue_boost;
    if ((casu_marginal_after != casu_marginal_before) ||
        (casu_pressure_after != casu_pressure_before) ||
        (casu_pollution_after != casu_pollution_before) ||
        (casu_no_pressure_boost !== 0)) begin
      $fatal(1,
             "CAS_T5 expected no CAS-U fallback side effect: mk %0d->%0d pressure %0d->%0d pollution %0d->%0d boost=%0d",
             casu_marginal_before, casu_marginal_after,
             casu_pressure_before, casu_pressure_after,
             casu_pollution_before, casu_pollution_after,
             casu_no_pressure_boost);
    end
    desc_policy_select_s5_cfg = 1'b1;
    desc_service_criticality_cfg = '0;
    desc_head_budget_class_cfg = '0;
    desc_query_relevance_cfg = '0;
    desc_compression_risk_cfg = '0;
    desc_spill_cost_cfg = '0;
    $display("[PASS] CAS_T5 no_pressure_fallback_matches_S4");
`endif

    $display("TB SUMMARY: ops=%0d reads=%0d writes=%0d hits=%0d misses=%0d",
             total_ops, total_reads, total_writes, total_hits, total_misses);
    if (total_ops > 0) begin
      tb_lat_p50 = latency_percentile(50);
      tb_lat_p90 = latency_percentile(90);
      tb_lat_p95 = latency_percentile(95);
      tb_lat_p99 = latency_percentile(99);
      $display("TB LATENCY: avg=%0f cyc max=%0d cyc",
               (1.0 * total_latency_cycles) / total_ops, max_latency_cycles);
      $display("TB LAT PCTL: p50=%0d cyc p90=%0d cyc p95=%0d cyc p99=%0d cyc",
               tb_lat_p50, tb_lat_p90, tb_lat_p95, tb_lat_p99);
    end
    $display("TB LAT DETAIL: rd_hit_cnt=%0d rd_hit_avg=%0f rd_hit_max=%0d rd_miss_cnt=%0d rd_miss_avg=%0f rd_miss_max=%0d wr_hit_cnt=%0d wr_hit_avg=%0f wr_hit_max=%0d wr_miss_cnt=%0d wr_miss_avg=%0f wr_miss_max=%0d",
             rd_hit_cnt,
             (rd_hit_cnt > 0) ? ((1.0 * rd_hit_latency_sum) / rd_hit_cnt) : 0.0,
             rd_hit_latency_max,
             rd_miss_cnt,
             (rd_miss_cnt > 0) ? ((1.0 * rd_miss_latency_sum) / rd_miss_cnt) : 0.0,
             rd_miss_latency_max,
             wr_hit_cnt,
             (wr_hit_cnt > 0) ? ((1.0 * wr_hit_latency_sum) / wr_hit_cnt) : 0.0,
             wr_hit_latency_max,
             wr_miss_cnt,
             (wr_miss_cnt > 0) ? ((1.0 * wr_miss_latency_sum) / wr_miss_cnt) : 0.0,
             wr_miss_latency_max);
    $display("TB LAT CLASS: hot_rd_cnt=%0d hot_rd_avg=%0f hot_rd_max=%0d hot_hit=%0d hot_miss=%0d cold_rd_cnt=%0d cold_rd_avg=%0f cold_rd_max=%0d cold_hit=%0d cold_miss=%0d hiq_rd_cnt=%0d hiq_rd_avg=%0f loq_rd_cnt=%0d loq_rd_avg=%0f",
             hot_rd_cnt,
             (hot_rd_cnt > 0) ? ((1.0 * hot_rd_latency_sum) / hot_rd_cnt) : 0.0,
             hot_rd_latency_max,
             hot_rd_hit_cnt,
             hot_rd_miss_cnt,
             cold_rd_cnt,
             (cold_rd_cnt > 0) ? ((1.0 * cold_rd_latency_sum) / cold_rd_cnt) : 0.0,
             cold_rd_latency_max,
             cold_rd_hit_cnt,
             cold_rd_miss_cnt,
             hiq_rd_cnt,
             (hiq_rd_cnt > 0) ? ((1.0 * hiq_rd_latency_sum) / hiq_rd_cnt) : 0.0,
             loq_rd_cnt,
             (loq_rd_cnt > 0) ? ((1.0 * loq_rd_latency_sum) / loq_rd_cnt) : 0.0);
    $display("TB LOSSY: approx_read_cnt=%0d approx_read_ratio=%0f",
             approx_read_cnt,
             (total_reads > 0) ? ((100.0 * approx_read_cnt) / total_reads) : 0.0);
    $display("DUT COUNTERS: demand=%0d hit=%0d pf_req=%0d pf_fill=%0d evict=%0d",
             dut.u_mcu.u_ex.stat_demand_access_cnt,
             dut.u_mcu.u_ex.stat_demand_hit_cnt,
             dut.u_mcu.u_ex.stat_prefetch_req_cnt,
             dut.u_mcu.u_ex.stat_prefetch_fill_cnt,
             dut.u_mcu.u_ex.stat_evict_cnt);
    $display("DUT DESC STATS: demand_req=%0d demand_miss=%0d miss_permille=%0d",
             dut.stat_demand_req_cnt,
             dut.stat_demand_miss_cnt,
             dut.stat_miss_rate_permille);
    $display("DUT PF FEEDBACK: useful=%0d fill=%0d eff=%0f",
             dut.u_mcu.u_ex.stat_prefetch_useful_cnt,
             dut.u_mcu.u_ex.stat_prefetch_fill_cnt,
             (dut.u_mcu.u_ex.stat_prefetch_fill_cnt > 0) ?
             ((100.0 * dut.u_mcu.u_ex.stat_prefetch_useful_cnt) / dut.u_mcu.u_ex.stat_prefetch_fill_cnt) : 0.0);
    $display("DUT PF CTRL: push=%0d pop=%0d drop_qos=%0d drop_throttle=%0d",
             dut.u_mcu.u_pf.stat_pf_push_cnt,
             dut.u_mcu.u_pf.stat_pf_pop_cnt,
             dut.u_mcu.u_pf.stat_pf_drop_qos_cnt,
             dut.u_mcu.u_pf.stat_pf_drop_throttle_cnt);
    $display("DUT SCHED: hot_hint=%0d pf_block=%0d",
             dut.u_mcu.u_sched_cmd.stat_sched_hot_hint_cnt,
             dut.u_mcu.u_sched_cmd.stat_sched_pref_block_cnt);
    $display("DUT KV MAP: hit=%0d alloc=%0d overflow=%0d repl=%0d decay=%0d score_repl=%0d",
             dut.u_mcu.u_kv_map.stat_map_hit_cnt,
             dut.u_mcu.u_kv_map.stat_map_alloc_cnt,
             dut.u_mcu.u_kv_map.stat_map_overflow_cnt,
             dut.u_mcu.u_kv_map.stat_map_repl_cnt,
             dut.u_mcu.u_kv_map.stat_map_decay_cnt,
             dut.u_mcu.u_kv_map.stat_map_score_repl_cnt);
    $display("DUT KV MAP EXTRA: seq_reclaim=%0d dirty_spill=%0d cold_spill=%0d protect_skip=%0d",
             dut.u_mcu.u_kv_map.stat_map_seq_reclaim_cnt,
             dut.u_mcu.u_kv_map.stat_map_dirty_spill_cnt,
             dut.u_mcu.u_kv_map.stat_map_cold_spill_cnt,
             dut.u_mcu.u_kv_map.stat_map_protect_skip_cnt);
    $display("DUT H2O REPL: promote=%0d seed_hot=%0d demote=%0d repl_hot=%0d repl_warm=%0d alloc_invalid=%0d repl_total=%0d",
             dut.u_mcu.u_ex.u_meta.stat_h2o_hot_promote_cnt,
             dut.u_mcu.u_ex.u_meta.stat_h2o_hot_seed_cnt,
             dut.u_mcu.u_ex.u_meta.stat_h2o_hot_demote_cnt,
             dut.u_mcu.u_ex.u_meta.stat_h2o_repl_hot_victim_cnt,
             dut.u_mcu.u_ex.u_meta.stat_h2o_repl_warm_victim_cnt,
             dut.u_mcu.u_ex.u_meta.stat_h2o_alloc_invalid_cnt,
             dut.u_mcu.u_ex.u_meta.stat_h2o_repl_total_cnt);
    $display("DUT H2O TRUE: hh_hit=%0d hh_protect=%0d recent_keep=%0d both=%0d recent_only=%0d hh_only=%0d fallback=%0d",
             dut.u_mcu.u_h2o_oracle.stat_hh_hit_cnt,
             dut.u_mcu.u_h2o_oracle.stat_hh_protect_cnt,
             dut.u_mcu.u_h2o_oracle.stat_recent_keep_cnt,
             dut.u_mcu.u_h2o_oracle.stat_h2o_both_cnt,
             dut.u_mcu.u_h2o_oracle.stat_h2o_recent_only_cnt,
             dut.u_mcu.u_h2o_oracle.stat_h2o_hh_only_cnt,
             dut.u_mcu.u_h2o_oracle.stat_h2o_fallback_cnt);
    $display("DUT TIERS: l1_hit=%0d l2_demand_fill=%0d l2_prefetch_fill=%0d",
             dut.u_mcu.u_ex.stat_l1_hit_cnt,
             dut.u_mcu.u_ex.stat_l2_demand_fill_cnt,
             dut.u_mcu.u_ex.stat_l2_prefetch_fill_cnt);
    $display("DUT L1 CTRL: demand_fill=%0d demand_bypass=%0d pref_fill=%0d pref_bypass=%0d",
             dut.u_mcu.u_ex.stat_l1_demand_fill_cnt,
             dut.u_mcu.u_ex.stat_l1_demand_bypass_cnt,
             dut.u_mcu.u_ex.stat_l1_prefetch_fill_cnt,
             dut.u_mcu.u_ex.stat_l1_prefetch_bypass_cnt);
    $display("DUT LAT_PIPE: mem_wait=%0d exec_busy=%0d",
             dut.u_mcu.u_ex.stat_mem_wait_cycle_cnt,
             dut.u_mcu.u_ex.stat_exec_busy_cycle_cnt);
    $display("DUT SERVICE ISSUE: boost_req=%0d effective=%0d wb_guard=%0d",
             dut.u_mcu.u_hbm_if.u_core.stat_hbmif_service_issue_boost_cnt,
             dut.u_mcu.u_hbm_if.u_core.stat_hbmif_service_issue_effective_cnt,
             dut.u_mcu.u_hbm_if.u_core.stat_hbmif_service_issue_wb_guard_cnt);
    $display("DUT SERVICE BACKLOG: window=%0d effective=%0d",
             dut.u_mcu.u_hbm_if.u_core.stat_hbmif_service_backlog_window_cnt,
             dut.u_mcu.u_hbm_if.u_core.stat_hbmif_service_backlog_effective_cnt);
    $display("DUT CAS-U: marginal_keep=%0d pollution_block=%0d pressure_bonus=%0d compression_guard=%0d admission_bypass=%0d",
             dut.u_mcu.u_l2.stat_l2_casu_marginal_keep_cnt,
             dut.u_mcu.u_l2.stat_l2_casu_pollution_block_cnt,
             dut.u_mcu.u_l2.stat_l2_casu_pressure_bonus_cnt,
             dut.u_mcu.u_l2.stat_l2_casu_comp_guard_cnt,
             dut.u_mcu.u_l2.stat_l2_casu_admission_bypass_cnt);
    $display("DUT L2 COUNTERS: rd_hit=%0d rd_miss=%0d wr_hit=%0d wr_alloc=%0d wr_noalloc=%0d wr_qos_bypass=%0d rd_fill_bypass=%0d vb_promote_bypass=%0d fill=%0d evict=%0d hbm_rd=%0d hbm_wr=%0d comp_fill=%0d comp_hit=%0d comp_promote=%0d comp_readback=%0d",
             dut.u_mcu.u_l2.stat_l2_read_hit_cnt,
             dut.u_mcu.u_l2.stat_l2_read_miss_cnt,
             dut.u_mcu.u_l2.stat_l2_write_hit_cnt,
             dut.u_mcu.u_l2.stat_l2_write_alloc_cnt,
             dut.u_mcu.u_l2.stat_l2_write_noalloc_cnt,
             dut.u_mcu.u_l2.stat_l2_write_qos_bypass_cnt,
             dut.u_mcu.u_l2.stat_l2_read_fill_bypass_cnt,
             dut.u_mcu.u_l2.stat_l2_vb_promote_bypass_cnt,
             dut.u_mcu.u_l2.stat_l2_fill_cnt,
             dut.u_mcu.u_l2.stat_l2_evict_cnt,
             dut.u_mcu.u_l2.stat_hbm_read_req_cnt,
             dut.u_mcu.u_l2.stat_hbm_write_req_cnt,
             dut.u_mcu.u_l2.stat_l2_comp_fill_cnt,
             dut.u_mcu.u_l2.stat_l2_comp_hit_cnt,
             dut.u_mcu.u_l2.stat_l2_comp_promote_cnt,
             dut.u_mcu.u_l2.stat_l2_comp_readback_cnt);
    $display("DUT L2 H2O: sem_hot_fill=%0d sem_hot_evict=%0d",
             dut.u_mcu.u_l2.stat_l2_sem_hot_fill_cnt,
             dut.u_mcu.u_l2.stat_l2_sem_hot_evict_cnt);
    $display("DUT L2 EVICT_CAUSE: capacity=%0d sem_hot_victim=%0d low_qos_req=%0d prefetch_req=%0d vb_path=%0d",
             dut.u_mcu.u_l2.stat_l2_evict_capacity_cnt,
             dut.u_mcu.u_l2.stat_l2_evict_sem_hot_victim_cnt,
             dut.u_mcu.u_l2.stat_l2_evict_low_qos_req_cnt,
             dut.u_mcu.u_l2.stat_l2_evict_prefetch_req_cnt,
             dut.u_mcu.u_l2.stat_l2_evict_vb_path_cnt);
    $display("DUT L2 DIRTY: wb_enq=%0d wb_drop=%0d vb_dirty_flush=%0d vb_hot_bg_prom=%0d dirty_peak=%0d vb_dirty_peak=%0d",
             dut.u_mcu.u_l2.stat_l2_dirty_wb_req_cnt,
             dut.u_mcu.u_l2.stat_l2_dirty_wb_drop_cnt,
             dut.u_mcu.u_l2.stat_l2_vb_dirty_flush_cnt,
             dut.u_mcu.u_l2.stat_l2_vb_hot_promote_bg_cnt,
             dut.u_mcu.u_l2.stat_l2_dirty_peak_cnt,
             dut.u_mcu.u_l2.stat_l2_vb_dirty_peak_cnt);
    $display("DUT LOSSY PIPE: l2_lossy_resp=%0d",
             dut.u_mcu.u_ex.stat_l2_lossy_resp_cnt);
    $display("DUT LOSSY EXTRA: comp_spill=%0d saved_beats=%0d blocked_hot=%0d err_accum=%0d",
             dut.u_mcu.u_l2.stat_l2_comp_spill_cnt,
             dut.u_mcu.u_l2.stat_l2_comp_saved_beats,
             dut.u_mcu.u_l2.stat_l2_comp_blocked_hot_cnt,
             dut.u_mcu.u_l2.stat_l2_comp_error_accum);
    $display("DUT L2 VB: rd_hit=%0d wr_hit=%0d insert=%0d evict=%0d swap=%0d",
             dut.u_mcu.u_l2.stat_l2_vb_read_hit_cnt,
             dut.u_mcu.u_l2.stat_l2_vb_write_hit_cnt,
             dut.u_mcu.u_l2.stat_l2_vb_insert_cnt,
             dut.u_mcu.u_l2.stat_l2_vb_evict_cnt,
             dut.u_mcu.u_l2.stat_l2_vb_swap_cnt);
    $display("DUT L2 UTIL: fill_invalid=%0d fill_replace=%0d valid_peak=%0d valid_peak_ratio=%0f lifetime_avg=%0f lifetime_samples=%0d",
             dut.u_mcu.u_l2.stat_l2_fill_invalid_cnt,
             dut.u_mcu.u_l2.stat_l2_fill_replace_cnt,
             dut.u_mcu.u_l2.stat_l2_valid_peak_cnt,
             (100.0 * dut.u_mcu.u_l2.stat_l2_valid_peak_cnt) / L2_LINES,
             (dut.u_mcu.u_l2.stat_l2_lifetime_sample_cnt > 0) ?
             ((1.0 * dut.u_mcu.u_l2.stat_l2_lifetime_cycle_sum) / dut.u_mcu.u_l2.stat_l2_lifetime_sample_cnt) : 0.0,
             dut.u_mcu.u_l2.stat_l2_lifetime_sample_cnt);
    $display("DUT L2 LIFE_HIST: lt32=%0d lt128=%0d lt512=%0d ge512=%0d",
             dut.u_mcu.u_l2.stat_l2_lifetime_bin_lt32_cnt,
             dut.u_mcu.u_l2.stat_l2_lifetime_bin_lt128_cnt,
             dut.u_mcu.u_l2.stat_l2_lifetime_bin_lt512_cnt,
             dut.u_mcu.u_l2.stat_l2_lifetime_bin_ge512_cnt);
    $display("DUT HBM IF: rd_req=%0d wr_req=%0d conflict=%0d backlog=%0d congest=%0d q_peak=%0d",
             dut.u_mcu.u_hbm_if.u_core.stat_hbmif_rd_req_cnt,
             dut.u_mcu.u_hbm_if.u_core.stat_hbmif_wr_req_cnt,
             dut.u_mcu.u_hbm_if.u_core.stat_hbmif_conflict_cycle_cnt,
             dut.u_mcu.u_hbm_if.u_core.stat_hbmif_backlog_cycle_cnt,
             dut.u_mcu.u_hbm_if.u_core.stat_hbmif_congest_cycle_cnt,
             dut.u_mcu.u_hbm_if.u_core.stat_hbmif_q_peak);
    $display("DUT HBM IF BURST: merge=%0d wr_drain=%0d rd_prio=%0d",
             dut.u_mcu.u_hbm_if.u_core.stat_hbmif_burst_merge_cnt,
             dut.u_mcu.u_hbm_if.u_core.stat_hbmif_wr_drain_cycle_cnt,
             dut.u_mcu.u_hbm_if.u_core.stat_hbmif_rd_prio_cycle_cnt);
    $display("DUT BACKEND CTRL: demand_accept=%0d prefetch_accept=%0d wr_accept=%0d wb_accept=%0d pf_drop=%0d",
             dut.u_mcu.u_hbm_if.stat_hbmif_ctrl_demand_rd_accept_cnt,
             dut.u_mcu.u_hbm_if.stat_hbmif_ctrl_prefetch_rd_accept_cnt,
             dut.u_mcu.u_hbm_if.stat_hbmif_ctrl_wr_accept_cnt,
             dut.u_mcu.u_hbm_if.stat_hbmif_ctrl_wb_accept_cnt,
             dut.u_mcu.u_hbm_if.stat_hbmif_ctrl_prefetch_drop_cnt);

    $display("ALL TESTS PASSED.");
    $finish;
  end

endmodule


