`timescale 1ns / 1ps

// ------------------------------------------------------------
// kcmu_top.sv
// Top-level of KCMU IP:
// - Trace stream in/out
// - Backward-compatible simple external memory interface
// - Optional AXI-like memory bridge (queued multi-outstanding)
// ------------------------------------------------------------
module kcmu_top #(
  parameter integer ADDR_W   = 8,
  parameter integer DATA_W   = 32,
  parameter integer LINES    = 4,
  parameter integer SCORE_W  = 8,
  parameter integer TIME_W   = 16,
  parameter integer K_RECENT = 1,
  parameter bit     H2O_V2_EN = 1'b1,
  parameter bit     TRUE_H2O_RECENT_EN = 1'b1,
  parameter bit     TRUE_H2O_HH_EN = 1'b1,
  parameter bit     TRUE_H2O_HH_EPOCH_DECAY_EN = 1'b0,
  parameter integer TRUE_H2O_HH_DECAY_LOG2 = 3,
  parameter integer TRUE_H2O_HH_DECAY_MAX_SHIFT = 2,
  parameter bit     TRUE_H2O_HH_VALIDATED_PROTECT_EN = 1'b0,
  parameter bit     TRUE_H2O_BACKEND_ADMISSION_EN = 1'b1,
  parameter bit     TRUE_H2O_SERVICE_PACING_ONLY_EN = 1'b0,
  parameter bit     TRUE_H2O_SPACED_PREFETCH_EN = 1'b0,
  parameter bit     TRUE_H2O_SPACED_PREFETCH_DIV8_EN = 1'b0,
  parameter bit     TRUE_H2O_IDLE_PREFETCH_EN = 1'b0,
  parameter bit     TRUE_H2O_OCCUPANCY_PREFETCH_EN = 1'b0,
  parameter integer TRUE_H2O_PREFETCH_QMAX = 1,
  parameter bit     TRUE_H2O_PREFETCH_WRITE_PRESSURE_GUARD_EN = 1'b0,
  parameter bit     TRUE_H2O_PREFETCH_DESC_GATE_EN = 1'b0,
  parameter bit     TRUE_H2O_PREFETCH_UTILITY_DESC_GATE_EN = 1'b0,
  parameter bit     TRUE_H2O_PREFETCH_BUDGET_EN = 1'b0,
  parameter logic [2:0] TRUE_H2O_PREFETCH_EPOCH_BUDGET = 3'd2,
  parameter bit     TRUE_H2O_PREFETCH_WRDOM_HHONLY_GATE_EN = 1'b0,
  parameter logic [4:0] TRUE_H2O_PREFETCH_WRDOM_HHONLY_TH = 5'd7,
  parameter bit     TRUE_H2O_UNCONGESTED_PREFETCH_EN = 1'b0,
  parameter bit     TRUE_H2O_PREFETCH_NO_SPECIAL_EN = 1'b0,
  parameter bit     TRUE_H2O_PREFETCH_USEFUL_CREDIT_EN = 1'b0,
  parameter bit     TRUE_H2O_PREFETCH_USEFUL_ACCEPT_DEBIT_EN = 1'b0,
  parameter bit     TRUE_H2O_PREFETCH_DEMAND_PREEMPT_EN = 1'b0,
  parameter bit     TRUE_H2O_MISS_CREDIT_PREFETCH_EN = 1'b0,
  parameter bit     TRUE_H2O_STRICT_MISS_CREDIT_PREFETCH_EN = 1'b0,
  parameter bit     TRUE_H2O_HH_PREFETCH_ONLY_EN = 1'b0,
  parameter bit     TRUE_H2O_SERVICE_HH_DIRECT_EN = 1'b0,
  parameter bit     TRUE_H2O_KSPU_EPOCH_SELECTOR_EN = 1'b0,
  parameter bit     TRUE_H2O_KSPU_WORKLOAD_SELECTOR_EN = 1'b0,
  parameter bit     TRUE_H2O_RECENT_VALID_SERVICE_EN = 1'b0,
  parameter bit     TRUE_H2O_L2_REUSE_PROMOTE_EN = 1'b0,
  parameter bit     TRUE_H2O_RETENTION_SERVICE_DECOUPLE_EN = 1'b0,
  parameter bit     TRUE_H2O_VALIDATED_OR_RECENT_RETENTION_EN = 1'b0,
  parameter bit     TRUE_H2O_L1_VALIDATED_OR_RECENT_RETENTION_EN = 1'b0,
  parameter bit     TRUE_H2O_VICTIM_VALIDATED_OR_RECENT_PROTECT_EN = 1'b0,
  parameter bit     TRUE_H2O_STORAGE_QOS_DECOUPLE_EN = 1'b0,
  parameter bit     PREFETCH_FORCE_DISABLE_EN = 1'b0,
  parameter logic [SCORE_W-1:0] TRUE_H2O_HH_SCORE_TH = SCORE_W'(8'hC0),
  parameter bit     UTILITY_HEAD_ADAPTIVE_EN = 1'b0,
  parameter bit     UTILITY_QUERY_AWARE_EN = 1'b0,
  parameter bit     UTILITY_COST_AWARE_EN = 1'b0,
  parameter bit     UTILITY_BACKEND_CRITICAL_EN = 1'b0,
  parameter logic [SCORE_W-1:0] BACKEND_CRITICAL_HOT_TH = SCORE_W'(8'hD8),
  parameter logic [SCORE_W-1:0] BACKEND_CRITICAL_WARM_TH = SCORE_W'(8'hB8),
  parameter integer UTILITY_ATTN_W = 3,
  parameter integer UTILITY_RECENT_W = 2,
  parameter integer UTILITY_HH_W = 2,
  parameter integer UTILITY_HEAD_W = 2,
  parameter integer UTILITY_QUERY_W = 4,
  parameter integer UTILITY_COMP_W = 1,
  parameter integer UTILITY_SPILL_W = 1,
  parameter bit     UTILITY_SERVICE_HH_EN = 1'b0,
  parameter logic [SCORE_W-1:0] UTILITY_SERVICE_HH_TH = SCORE_W'(8'hB8),
  parameter bit     UTILITY_SERVICE_RESCUE_EN = 1'b0,
  parameter logic [SCORE_W-1:0] SERVICE_FILL_RESCUE_TH = SCORE_W'(8'hB8),
  parameter bit     UTILITY_SERVICE_ISSUE_EN = 1'b0,
  parameter logic [SCORE_W-1:0] SERVICE_ISSUE_BOOST_TH = SCORE_W'(8'hD0),
  parameter logic [2:0] SERVICE_ISSUE_PRIO_TH = 3'd3,
  parameter bit     UTILITY_SERVICE_ISSUE_REQUIRE_FILLPROTECT = 1'b1,
  parameter bit     UTILITY_SERVICE_ISSUE_ALLOW_GUARDED = 1'b0,
  parameter bit     UTILITY_SERVICE_ISSUE_RESIDUAL_EN = 1'b0,
  parameter bit     UTILITY_SCHED_BACKEND_ISSUE_BRIDGE_EN = 1'b0,
  parameter bit     UTILITY_BACKEND_DEMAND_BRIDGE_EN = 1'b0,
  parameter bit     UTILITY_SCORE_REPL_EN = 1'b0,
  parameter bit     QMATCH_RECENT_COLD_TIEBREAK_EN = 1'b0,
  parameter bit     QMATCH_SERVICE_PLACEMENT_EN = 1'b0,
  parameter bit     QMATCH_SERVICE_ADMISSION_EN = 1'b0,
  parameter bit     QMATCH_L1_QUERY_SEED_EN = 1'b0,
  parameter bit     QMATCH_L1_KEEP_TIEBREAK_EN = 1'b0,
  parameter bit     QMATCH_SIG_SERVICE_ADMISSION_EN = 1'b0,
  parameter bit     QMATCH_SIG_L2_PLACEMENT_EN = 1'b0,
  parameter bit     QMATCH_SIG_RECENT_COLD_DEMOTE_EN = 1'b0,
  parameter bit     QMATCH_SIG_BOTH_COLD_TO_HH_EN = 1'b0,
  parameter bit     QMATCH_SIG_BOTH_NONHOT_TO_HH_EN = 1'b0,
  parameter bit     HASP_LRRB_L2_PLACEMENT_EN = 1'b0,
  parameter logic [SCORE_W-1:0] HASP_LRRB_QUERY_TH = SCORE_W'(8'h70),
  parameter logic [SCORE_W-1:0] HASP_LRRB_BOOST_SCORE = SCORE_W'(8'hB8),
  parameter integer HASP_LRRB_HEAD_BUDGET_TH = 1,
  parameter bit     UTILITY_MARGINAL_REPL_EN = 1'b0,
  parameter bit     UTILITY_POLICY_SELECT_EN = 1'b0,
  parameter logic [SCORE_W-1:0] POLICY_SELECT_CONSERVATIVE_BACKEND_HOT_TH = SCORE_W'(8'hD8),
  parameter logic [SCORE_W-1:0] POLICY_SELECT_CONSERVATIVE_BACKEND_WARM_TH = SCORE_W'(8'hB8),
  parameter integer HBM_SERVICE_ISSUE_MAX_WB = 1,
  parameter bit     HBM_SERVICE_ISSUE_WB_HOLD_EN = 1'b0,
  parameter integer HBM_SERVICE_ISSUE_WB_HOLD_CYCLES = 1,
  parameter bit     HBM_SERVICE_ISSUE_HOLD_WRITES_EN = 1'b0,
  parameter bit     HBM_SERVICE_BACKLOG_BOOST_EN = 1'b0,
  parameter integer HBM_SERVICE_BACKLOG_WAIT_MAX = 1,
  parameter integer MEM_RD_LATENCY = 2,
  parameter integer L2_RD_LATENCY = 1,
  parameter integer L2_LINES = 16,
  parameter integer L2_WAYS = 2,
  parameter integer L2_VB_LINES = 2,
  parameter bit     L2_VB_ENABLE = 1'b0,
  parameter bit     L2_VB_CLEAN_READONLY_EN = 1'b0,
  parameter bit     L2_GROUP_FETCH_TO_CVR_EN = 1'b0,
  parameter integer L2_GROUP_BUF_LINES = 4,
  parameter bit     L2_WRITE_ALLOCATE = 1'b1,
  parameter bit     L2_WRITE_THROUGH_EN = 1'b1,
  parameter bit     L2_BG_DIRTY_FLUSH_EN = 1'b1,
  parameter bit     L2_SERVICE_ISSUE_DEFER_DIRTY_FLUSH_EN = 1'b0,
  parameter bit     L2_SERVICE_ISSUE_CLEAN_VICTIM_RESCUE_EN = 1'b0,
  parameter logic [2:0] L2_SERVICE_ISSUE_CLEAN_VICTIM_MARGIN = 3'd2,
  parameter bit     L2_SCHED_OWNERSHIP_QUERY_BIAS_EN = 1'b0,
  parameter bit     L2_SCHED_OWNERSHIP_QUERY_STRONG_BIAS_EN = 1'b0,
  parameter logic [2:0] L2_WRITE_ALLOC_QOS_TH = 3'd2,
  parameter logic [2:0] L2_READ_FILL_QOS_TH = 3'd1,
  parameter logic [2:0] L2_PREFETCH_FILL_QOS_TH = 3'd3,
  parameter bit     L2_SEM_FILL_RELAX_EN = 1'b1,
  parameter bit     L2_SEM_HOT_VICTIM_PROTECT_EN = 1'b1,
  parameter logic [2:0] L2_SEM_HOT_SCORE_BONUS = 3'd3,
  parameter logic [2:0] L2_SEM_COLD_SCORE_PENALTY = 3'd2,
  parameter logic [7:0] L2_SEM_HOT_MAX_AGE = 8'd112,
  parameter logic [2:0] L2_REQ_HOT_SCORE_BONUS = 3'd2,
  parameter logic [2:0] L2_AGE_STALE_SCORE_PENALTY = 3'd2,
  parameter logic [2:0] L2_LOSSY_SCORE_PENALTY = 3'd3,
  parameter bit     L2_LOSSY_COMPRESS_EN = 1'b1,
  parameter integer L2_COMP_SHIFT = 4,
  parameter logic [2:0] L2_COMPRESS_QOS_TH = 3'd2,
  parameter logic [7:0] L2_COMP_ERR_CAP = 8'd63,
  parameter logic [2:0] L1_BYPASS_QOS_TH = 3'd1,
  parameter logic [2:0] L1_DEMAND_FILL_QOS_TH = 3'd3,
  parameter logic [2:0] L1_PREFETCH_FILL_QOS_TH = 3'd4,
  parameter logic [2:0] L1_MISS_BYPASS_QOS_TH = 3'd7,
  parameter bit     HIER_POLICY_EN = 1'b1,
  parameter logic [2:0] L1_CONGEST_BYPASS_QOS_TH = 3'd5,
  parameter logic [2:0] PREFETCH_CONGEST_QOS_TH = 3'd7,
  parameter logic [2:0] PREFETCH_HBM_ISSUE_QOS_TH = 3'd6,
  parameter bit     PREFETCH_HBM_ISSUE_RELAX_HOT = 1'b1,
  parameter integer EXEC_CONGEST_Q_LEVEL_TH = 1,
  parameter integer HBM_CONGEST_COLD_EXTRA_LAT = 3,
  parameter integer HBM_CONGEST_HOT_EXTRA_LAT = 1,
  parameter integer HBM_CONGEST_PREFETCH_EXTRA_LAT = 4,
  parameter bit     L1_FILL_ON_HBM_MISS = 1'b1,
  parameter bit     L2_HIT_REUSE_BUFFER_EN = 1'b0,
  parameter integer L2_HIT_REUSE_BUFFER_DEPTH = 4,
  parameter bit     PF_ADAPT_EN = 1'b1,
  parameter logic [2:0] PF_QOS_TH = 3'd2,
  parameter integer HBM_IF_Q_DEPTH = 4,
  parameter integer HBM_IF_SERVICE_CYCLES = 1,
  parameter bit     KV_MAP_ENABLE = 1'b1,
  parameter integer KV_BLOCK_OFF_BITS = 1,
  parameter integer KV_DIR_ENTRIES = 64,
  parameter bit     KV_REAL_LAYOUT_EN = 1'b1,
  parameter integer KV_TOKEN_BLOCK_BITS = 4,
  parameter integer KV_TYPE_ADDR_BIT = -1,
  parameter bit     KV_MAP_SCORE_REPL_EN = 1'b1,
  parameter integer KV_MAP_SCORE_REPL_HW_WIN = 2,
  parameter logic [3:0] KV_MAP_SCORE_PROTECT_TH = 4'd12,
  parameter bit     KV_MAP_SCORE_DECAY_EN = 1'b1,
  parameter integer KV_MAP_SCORE_DECAY_LOG2 = 5,
  parameter bit     ATTN_SCHED_EN = 1'b1,
  parameter bit     ATTN_SCHED_RELAX_REUSE_ONLY_PROTECT_UNDER_PRESSURE_EN = 1'b0,
  parameter logic [2:0] ATTN_SCHED_RELAX_REUSE_ONLY_PROTECT_QOS_TH = 3'd6,
  parameter bit     ATTN_SCHED_STEAL_REUSE_ONLY_OWNERSHIP_EN = 1'b0,
  parameter logic [2:0] ATTN_SCHED_STEAL_REUSE_ONLY_QOS_TH = 3'd4,
  parameter bit     ATTN_SCHED_OVERRIDE_FILL_BLOCK_WITH_UTILITY_EN = 1'b0,
  parameter logic [2:0] ATTN_SCHED_OVERRIDE_FILL_BLOCK_QOS_TH = 3'd5,
  parameter bit     ATTN_SCHED_BACKEND_ISSUE_OWNERSHIP_EN = 1'b0,
  parameter logic [2:0] ATTN_SCHED_BACKEND_ISSUE_OWNERSHIP_QOS_TH = 3'd5,
  parameter bit     ATTN_SCHED_BACKEND_ISSUE_RESCUE_EN = 1'b0,
  parameter logic [2:0] ATTN_SCHED_BACKEND_ISSUE_RESCUE_QOS_TH = 3'd5,
  parameter bit     ATTN_SCHED_PROMOTE_QUERY_TEMPORAL_PRIMARY_UTILITY_EN = 1'b0,
  parameter logic [2:0] ATTN_SCHED_PROMOTE_QUERY_TEMPORAL_QOS_TH = 3'd4,
  parameter bit     ATTN_SCHED_FORCE_QUERY_TEMPORAL_DIRECT_TAKE_EN = 1'b0,
  parameter bit     ATTN_SCHED_OWNERSHIP_QOS_FLOOR_EN = 1'b0,
  parameter logic [2:0] ATTN_SCHED_OWNERSHIP_QOS_FLOOR = 3'd5,
  parameter logic [2:0] ATTN_SCHED_OWNERSHIP_QOS_BACKEND_FLOOR = 3'd6,
  parameter bit     ATTN_SCHED_MASTER_OWNERSHIP_FILL_STEAL_EN = 1'b0,
  parameter bit     ATTN_SCHED_MASTER_OWNERSHIP_FILL_ONLY_EN = 1'b0,
  parameter bit     ATTN_SCHED_MASTER_OWNERSHIP_BLOCK_RESCUE_EN = 1'b0,
  parameter logic [2:0] ATTN_SCHED_MASTER_OWNERSHIP_FILL_STEAL_QOS_TH = 3'd6,
  parameter bit     ATTN_SCHED_MASTER_OUTPUT_RESCUE_EN = 1'b0,
  parameter logic [2:0] ATTN_SCHED_MASTER_OUTPUT_RESCUE_QOS_TH = 3'd5,
  parameter bit     ATTN_SCHED_MASTER_SLAVE_FILL_EN = 1'b0,
  parameter bit     ATTN_SCHED_MASTER_SLAVE_PROTECT_EN = 1'b0,
  parameter bit     ATTN_SCHED_MASTER_SLAVE_BACKEND_EN = 1'b0,
  parameter bit     ATTN_SCHED_MASTER_SLAVE_COMP_GUARD_EN = 1'b0,
  parameter bit     ATTN_SCHED_BACKEND_ISSUE_QOS_BOOST_EN = 1'b1,
  parameter bit     ATTN_SCHED_BACKEND_ISSUE_STRONG_QUERY_GATE_EN = 1'b0,
  parameter bit     ATTN_SCHED_BACKEND_ISSUE_OWNERSHIP_STRONG_QUERY_GATE_EN = 1'b0,
  parameter bit     ATTN_SCHED_BACKEND_ISSUE_HIGH_SERVICE_ESCAPE_EN = 1'b0,
  parameter logic [SCORE_W-1:0] ATTN_SCHED_BACKEND_ISSUE_HIGH_SERVICE_TH = SCORE_W'(8'hD0),
  parameter bit     ATTN_SCHED_BACKEND_ISSUE_ROI_PRESSURE_GATE_EN = 1'b0,
  parameter bit     ATTN_SCHED_SAFE_FALLBACK_EN = 1'b0,
  parameter bit     ATTN_SCHED_SAFE_FALLBACK_LOCAL_EN = 1'b0,
  parameter bit     ATTN_SCHED_SAFE_FALLBACK_LOCAL_AGGR_EN = 1'b0,
  parameter bit     ATTN_SCHED_SAFE_FALLBACK_EARLY_FLOOR_EN = 1'b0,
  parameter bit     ATTN_SCHED_L2BIAS_H2O_HOT_GUARD_EN = 1'b0,
  parameter bit     ATTN_SCHED_BACKEND_ISSUE_COUNTER_GATE_EN = 1'b0,
  parameter bit     ATTN_SCHED_BACKEND_ISSUE_SELECTIVE_STRONG_GATE_EN = 1'b0,
  parameter bit     ATTN_SCHED_PHASE_SELECTOR_EN = 1'b0,
  parameter bit     ATTN_SCHED_CAPACITY_PRESSURE_ADAPTIVE_EN = 1'b0,
  parameter bit     ATTN_SCHED_ROI_GUARD_EN = 1'b0,
  parameter bit     L2_SCHED_OWNERSHIP_QUERY_ADAPTIVE_BIAS_EN = 1'b0,
  parameter integer CMDQ_DEPTH = 1,
  parameter bit     CMDQ_LOOKAHEAD_GROUP_TARGET_EN = 1'b0,
  parameter integer CMDQ_LOOKAHEAD_MAX_DELTA = 8,
  parameter bit     CMDQ_DESCRIPTOR_GROUP_TARGET_EN = 1'b0,
  parameter integer CMDQ_DESCRIPTOR_GROUP_TARGET_DELTA = 2,
  parameter bit     CMDQ_DESCRIPTOR_GROUP_TARGET_ADAPTIVE_EN = 1'b0,
  parameter integer CMDQ_DESCRIPTOR_GROUP_TARGET_HIGH_DELTA = 3,
  parameter integer CMDQ_DESCRIPTOR_GROUP_TARGET_DENSITY_TH = 3,
  parameter bit     USE_AXI_IF = 1'b0
)(
  input  logic                 clk,
  input  logic                 rst_n,

  input  logic                 prefetch_enable,

  // Trace input
  input  logic                 trace_valid,
  output logic                 trace_ready,
  input  kcmu_pkg::kcmu_op_t   trace_op,
  input  logic [ADDR_W-1:0]    trace_addr,
  input  logic [DATA_W-1:0]    trace_wdata,
  input  logic                 trace_meta_valid,
  input  logic [kcmu_pkg::KCMU_SEQ_W-1:0] trace_seq_id,
  input  kcmu_pkg::kcmu_phase_t trace_phase,
  input  kcmu_pkg::kcmu_kv_kind_t trace_kv_kind,
  input  logic [2:0]           trace_layer,
  input  logic [1:0]           trace_head,
  input  logic [11:0]          trace_token,
  input  logic [2:0]           trace_prio,

  // Descriptor trace input
  input  logic                 trace_desc_valid,
  output logic                 trace_desc_ready,
  input  kcmu_pkg::kcmu_op_t   trace_desc_op,
  input  logic [ADDR_W-1:0]    trace_desc_base_addr,
  input  logic [7:0]           trace_desc_len,
  input  logic [SCORE_W-1:0]   trace_desc_score,
  input  logic [kcmu_pkg::KCMU_SEQ_W-1:0] trace_desc_seq_id,
  input  kcmu_pkg::kcmu_phase_t trace_desc_phase,
  input  kcmu_pkg::kcmu_kv_kind_t trace_desc_kv_kind,
  input  logic                 trace_desc_attn_valid,
  input  logic [SCORE_W-1:0]   trace_desc_attn_score,
  input  logic [kcmu_pkg::KCMU_ATTN_RANK_W-1:0] trace_desc_recent_rank,
  input  logic [kcmu_pkg::KCMU_TOKEN_BLOCK_W-1:0] trace_desc_token_block_id,
  input  logic [kcmu_pkg::KCMU_ATTN_EPOCH_W-1:0] trace_desc_attn_epoch,
  input  logic [kcmu_pkg::KCMU_HEAD_BUDGET_W-1:0] trace_desc_head_budget_class,
  input  logic [SCORE_W-1:0]   trace_desc_query_relevance,
  input  logic [kcmu_pkg::KCMU_COST_CLASS_W-1:0] trace_desc_compression_risk,
  input  logic [kcmu_pkg::KCMU_COST_CLASS_W-1:0] trace_desc_spill_cost,
  input  logic [SCORE_W-1:0]   trace_desc_service_criticality,
  input  logic                 trace_desc_policy_select_s5,
  input  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] trace_desc_temporal_persist_class,
  input  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] trace_desc_reuse_distance_class,
  input  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] trace_desc_query_structure_class,
  input  logic [kcmu_pkg::KCMU_SCHED_HINT_W-1:0] trace_desc_sched_urgency_hint,
  input  logic                 trace_desc_kiloscore_extra_cvr_hint,
  input  logic                 trace_desc_sig_valid,
  input  logic [5:0]           trace_desc_query_sig,
  input  logic [5:0]           trace_desc_key_sig,
  input  logic [1:0]           trace_desc_prefix_class,
  input  logic [1:0]           trace_desc_router_class,
  input  logic                 trace_desc_wvalid,
  output logic                 trace_desc_wready,
  input  logic [DATA_W-1:0]    trace_desc_wdata,

  // Response output
  output logic                 resp_valid,
  input  logic                 resp_ready,
  output logic [DATA_W-1:0]    resp_rdata,
  output logic                 resp_hit,
  output logic                 resp_approx,

  // Backward-compatible simple memory interface
  output logic                 mem_re,
  output logic [ADDR_W-1:0]    mem_raddr,
  input  logic [DATA_W-1:0]    mem_rdata,
  input  logic                 mem_rvalid,
  output logic                 mem_we,
  output logic [ADDR_W-1:0]    mem_waddr,
  output logic [DATA_W-1:0]    mem_wdata,

  // Optional AXI-like memory interface (used when USE_AXI_IF=1)
  output logic [ADDR_W-1:0]    m_axi_araddr,
  output logic                 m_axi_arvalid,
  input  logic                 m_axi_arready,
  input  logic [DATA_W-1:0]    m_axi_rdata,
  input  logic                 m_axi_rvalid,
  output logic                 m_axi_rready,
  output logic [ADDR_W-1:0]    m_axi_awaddr,
  output logic                 m_axi_awvalid,
  input  logic                 m_axi_awready,
  output logic [DATA_W-1:0]    m_axi_wdata,
  output logic [(DATA_W/8)-1:0] m_axi_wstrb,
  output logic                 m_axi_wvalid,
  input  logic                 m_axi_wready,
  input  logic                 m_axi_bvalid,
  output logic                 m_axi_bready,

  output logic [31:0]          stat_demand_req_cnt,
  output logic [31:0]          stat_demand_miss_cnt,
  output logic [15:0]          stat_miss_rate_permille
);

  localparam integer LINE_IDX_W = (LINES <= 1) ? 1 : $clog2(LINES);

  logic                 core_mem_re;
  logic [ADDR_W-1:0]    core_mem_raddr;
  logic [DATA_W-1:0]    core_mem_rdata;
  logic                 core_mem_rvalid;
  logic                 core_mem_we;
  logic [ADDR_W-1:0]    core_mem_waddr;
  logic [DATA_W-1:0]    core_mem_wdata;

  kcmu_mcu #(
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W),
    .LINES(LINES),
    .SCORE_W(SCORE_W),
    .TIME_W(TIME_W),
    .K_RECENT(K_RECENT),
    .H2O_V2_EN(H2O_V2_EN),
    .TRUE_H2O_RECENT_EN(TRUE_H2O_RECENT_EN),
    .TRUE_H2O_HH_EN(TRUE_H2O_HH_EN),
    .TRUE_H2O_HH_EPOCH_DECAY_EN(TRUE_H2O_HH_EPOCH_DECAY_EN),
    .TRUE_H2O_HH_DECAY_LOG2(TRUE_H2O_HH_DECAY_LOG2),
    .TRUE_H2O_HH_DECAY_MAX_SHIFT(TRUE_H2O_HH_DECAY_MAX_SHIFT),
    .TRUE_H2O_HH_VALIDATED_PROTECT_EN(TRUE_H2O_HH_VALIDATED_PROTECT_EN),
    .TRUE_H2O_BACKEND_ADMISSION_EN(TRUE_H2O_BACKEND_ADMISSION_EN),
    .TRUE_H2O_SERVICE_PACING_ONLY_EN(TRUE_H2O_SERVICE_PACING_ONLY_EN),
    .TRUE_H2O_SPACED_PREFETCH_EN(TRUE_H2O_SPACED_PREFETCH_EN),
    .TRUE_H2O_SPACED_PREFETCH_DIV8_EN(TRUE_H2O_SPACED_PREFETCH_DIV8_EN),
    .TRUE_H2O_IDLE_PREFETCH_EN(TRUE_H2O_IDLE_PREFETCH_EN),
    .TRUE_H2O_OCCUPANCY_PREFETCH_EN(TRUE_H2O_OCCUPANCY_PREFETCH_EN),
    .TRUE_H2O_PREFETCH_QMAX(TRUE_H2O_PREFETCH_QMAX),
    .TRUE_H2O_PREFETCH_WRITE_PRESSURE_GUARD_EN(TRUE_H2O_PREFETCH_WRITE_PRESSURE_GUARD_EN),
    .TRUE_H2O_PREFETCH_DESC_GATE_EN(TRUE_H2O_PREFETCH_DESC_GATE_EN),
    .TRUE_H2O_PREFETCH_UTILITY_DESC_GATE_EN(TRUE_H2O_PREFETCH_UTILITY_DESC_GATE_EN),
    .TRUE_H2O_PREFETCH_BUDGET_EN(TRUE_H2O_PREFETCH_BUDGET_EN),
    .TRUE_H2O_PREFETCH_EPOCH_BUDGET(TRUE_H2O_PREFETCH_EPOCH_BUDGET),
    .TRUE_H2O_PREFETCH_WRDOM_HHONLY_GATE_EN(TRUE_H2O_PREFETCH_WRDOM_HHONLY_GATE_EN),
    .TRUE_H2O_PREFETCH_WRDOM_HHONLY_TH(TRUE_H2O_PREFETCH_WRDOM_HHONLY_TH),
    .TRUE_H2O_UNCONGESTED_PREFETCH_EN(TRUE_H2O_UNCONGESTED_PREFETCH_EN),
    .TRUE_H2O_PREFETCH_NO_SPECIAL_EN(TRUE_H2O_PREFETCH_NO_SPECIAL_EN),
    .TRUE_H2O_PREFETCH_USEFUL_CREDIT_EN(TRUE_H2O_PREFETCH_USEFUL_CREDIT_EN),
    .TRUE_H2O_PREFETCH_USEFUL_ACCEPT_DEBIT_EN(TRUE_H2O_PREFETCH_USEFUL_ACCEPT_DEBIT_EN),
    .TRUE_H2O_PREFETCH_DEMAND_PREEMPT_EN(TRUE_H2O_PREFETCH_DEMAND_PREEMPT_EN),
    .TRUE_H2O_MISS_CREDIT_PREFETCH_EN(TRUE_H2O_MISS_CREDIT_PREFETCH_EN),
    .TRUE_H2O_STRICT_MISS_CREDIT_PREFETCH_EN(TRUE_H2O_STRICT_MISS_CREDIT_PREFETCH_EN),
    .TRUE_H2O_HH_PREFETCH_ONLY_EN(TRUE_H2O_HH_PREFETCH_ONLY_EN),
    .TRUE_H2O_SERVICE_HH_DIRECT_EN(TRUE_H2O_SERVICE_HH_DIRECT_EN),
    .TRUE_H2O_KSPU_EPOCH_SELECTOR_EN(TRUE_H2O_KSPU_EPOCH_SELECTOR_EN),
    .TRUE_H2O_KSPU_WORKLOAD_SELECTOR_EN(TRUE_H2O_KSPU_WORKLOAD_SELECTOR_EN),
    .TRUE_H2O_RECENT_VALID_SERVICE_EN(TRUE_H2O_RECENT_VALID_SERVICE_EN),
    .TRUE_H2O_L2_REUSE_PROMOTE_EN(TRUE_H2O_L2_REUSE_PROMOTE_EN),
    .TRUE_H2O_RETENTION_SERVICE_DECOUPLE_EN(TRUE_H2O_RETENTION_SERVICE_DECOUPLE_EN),
    .TRUE_H2O_VALIDATED_OR_RECENT_RETENTION_EN(TRUE_H2O_VALIDATED_OR_RECENT_RETENTION_EN),
    .TRUE_H2O_L1_VALIDATED_OR_RECENT_RETENTION_EN(TRUE_H2O_L1_VALIDATED_OR_RECENT_RETENTION_EN),
    .TRUE_H2O_VICTIM_VALIDATED_OR_RECENT_PROTECT_EN(TRUE_H2O_VICTIM_VALIDATED_OR_RECENT_PROTECT_EN),
    .TRUE_H2O_STORAGE_QOS_DECOUPLE_EN(TRUE_H2O_STORAGE_QOS_DECOUPLE_EN),
    .PREFETCH_FORCE_DISABLE_EN(PREFETCH_FORCE_DISABLE_EN),
    .TRUE_H2O_HH_SCORE_TH(TRUE_H2O_HH_SCORE_TH),
    .UTILITY_HEAD_ADAPTIVE_EN(UTILITY_HEAD_ADAPTIVE_EN),
    .UTILITY_QUERY_AWARE_EN(UTILITY_QUERY_AWARE_EN),
    .UTILITY_COST_AWARE_EN(UTILITY_COST_AWARE_EN),
    .UTILITY_BACKEND_CRITICAL_EN(UTILITY_BACKEND_CRITICAL_EN),
    .BACKEND_CRITICAL_HOT_TH(BACKEND_CRITICAL_HOT_TH),
    .BACKEND_CRITICAL_WARM_TH(BACKEND_CRITICAL_WARM_TH),
    .UTILITY_ATTN_W(UTILITY_ATTN_W),
    .UTILITY_RECENT_W(UTILITY_RECENT_W),
    .UTILITY_HH_W(UTILITY_HH_W),
    .UTILITY_HEAD_W(UTILITY_HEAD_W),
    .UTILITY_QUERY_W(UTILITY_QUERY_W),
    .UTILITY_COMP_W(UTILITY_COMP_W),
    .UTILITY_SPILL_W(UTILITY_SPILL_W),
    .UTILITY_SERVICE_HH_EN(UTILITY_SERVICE_HH_EN),
    .UTILITY_SERVICE_HH_TH(UTILITY_SERVICE_HH_TH),
    .UTILITY_SERVICE_RESCUE_EN(UTILITY_SERVICE_RESCUE_EN),
    .SERVICE_FILL_RESCUE_TH(SERVICE_FILL_RESCUE_TH),
    .UTILITY_SERVICE_ISSUE_EN(UTILITY_SERVICE_ISSUE_EN),
    .SERVICE_ISSUE_BOOST_TH(SERVICE_ISSUE_BOOST_TH),
    .SERVICE_ISSUE_PRIO_TH(SERVICE_ISSUE_PRIO_TH),
    .UTILITY_SERVICE_ISSUE_REQUIRE_FILLPROTECT(UTILITY_SERVICE_ISSUE_REQUIRE_FILLPROTECT),
    .UTILITY_SERVICE_ISSUE_ALLOW_GUARDED(UTILITY_SERVICE_ISSUE_ALLOW_GUARDED),
    .UTILITY_SERVICE_ISSUE_RESIDUAL_EN(UTILITY_SERVICE_ISSUE_RESIDUAL_EN),
    .UTILITY_SCHED_BACKEND_ISSUE_BRIDGE_EN(UTILITY_SCHED_BACKEND_ISSUE_BRIDGE_EN),
    .UTILITY_BACKEND_DEMAND_BRIDGE_EN(UTILITY_BACKEND_DEMAND_BRIDGE_EN),
    .UTILITY_SCORE_REPL_EN(UTILITY_SCORE_REPL_EN),
    .QMATCH_RECENT_COLD_TIEBREAK_EN(QMATCH_RECENT_COLD_TIEBREAK_EN),
    .QMATCH_SERVICE_PLACEMENT_EN(QMATCH_SERVICE_PLACEMENT_EN),
    .QMATCH_SERVICE_ADMISSION_EN(QMATCH_SERVICE_ADMISSION_EN),
    .QMATCH_L1_QUERY_SEED_EN(QMATCH_L1_QUERY_SEED_EN),
    .QMATCH_L1_KEEP_TIEBREAK_EN(QMATCH_L1_KEEP_TIEBREAK_EN),
    .QMATCH_SIG_SERVICE_ADMISSION_EN(QMATCH_SIG_SERVICE_ADMISSION_EN),
    .QMATCH_SIG_L2_PLACEMENT_EN(QMATCH_SIG_L2_PLACEMENT_EN),
    .QMATCH_SIG_RECENT_COLD_DEMOTE_EN(QMATCH_SIG_RECENT_COLD_DEMOTE_EN),
    .QMATCH_SIG_BOTH_COLD_TO_HH_EN(QMATCH_SIG_BOTH_COLD_TO_HH_EN),
    .QMATCH_SIG_BOTH_NONHOT_TO_HH_EN(QMATCH_SIG_BOTH_NONHOT_TO_HH_EN),
    .HASP_LRRB_L2_PLACEMENT_EN(HASP_LRRB_L2_PLACEMENT_EN),
    .HASP_LRRB_QUERY_TH(HASP_LRRB_QUERY_TH),
    .HASP_LRRB_BOOST_SCORE(HASP_LRRB_BOOST_SCORE),
    .HASP_LRRB_HEAD_BUDGET_TH(HASP_LRRB_HEAD_BUDGET_TH),
    .UTILITY_MARGINAL_REPL_EN(UTILITY_MARGINAL_REPL_EN),
    .UTILITY_POLICY_SELECT_EN(UTILITY_POLICY_SELECT_EN),
    .POLICY_SELECT_CONSERVATIVE_BACKEND_HOT_TH(POLICY_SELECT_CONSERVATIVE_BACKEND_HOT_TH),
    .POLICY_SELECT_CONSERVATIVE_BACKEND_WARM_TH(POLICY_SELECT_CONSERVATIVE_BACKEND_WARM_TH),
    .HBM_SERVICE_ISSUE_MAX_WB(HBM_SERVICE_ISSUE_MAX_WB),
    .HBM_SERVICE_ISSUE_WB_HOLD_EN(HBM_SERVICE_ISSUE_WB_HOLD_EN),
    .HBM_SERVICE_ISSUE_WB_HOLD_CYCLES(HBM_SERVICE_ISSUE_WB_HOLD_CYCLES),
    .HBM_SERVICE_ISSUE_HOLD_WRITES_EN(HBM_SERVICE_ISSUE_HOLD_WRITES_EN),
    .HBM_SERVICE_BACKLOG_BOOST_EN(HBM_SERVICE_BACKLOG_BOOST_EN),
    .HBM_SERVICE_BACKLOG_WAIT_MAX(HBM_SERVICE_BACKLOG_WAIT_MAX),
    .MEM_RD_LATENCY(MEM_RD_LATENCY),
    .L2_RD_LATENCY(L2_RD_LATENCY),
    .L2_LINES(L2_LINES),
    .L2_WAYS(L2_WAYS),
    .L2_VB_LINES(L2_VB_LINES),
    .L2_VB_ENABLE(L2_VB_ENABLE),
    .L2_VB_CLEAN_READONLY_EN(L2_VB_CLEAN_READONLY_EN),
    .L2_GROUP_FETCH_TO_CVR_EN(L2_GROUP_FETCH_TO_CVR_EN),
    .L2_GROUP_BUF_LINES(L2_GROUP_BUF_LINES),
    .L2_WRITE_ALLOCATE(L2_WRITE_ALLOCATE),
    .L2_WRITE_THROUGH_EN(L2_WRITE_THROUGH_EN),
    .L2_BG_DIRTY_FLUSH_EN(L2_BG_DIRTY_FLUSH_EN),
    .L2_SERVICE_ISSUE_DEFER_DIRTY_FLUSH_EN(L2_SERVICE_ISSUE_DEFER_DIRTY_FLUSH_EN),
    .L2_SERVICE_ISSUE_CLEAN_VICTIM_RESCUE_EN(L2_SERVICE_ISSUE_CLEAN_VICTIM_RESCUE_EN),
    .L2_SERVICE_ISSUE_CLEAN_VICTIM_MARGIN(L2_SERVICE_ISSUE_CLEAN_VICTIM_MARGIN),
    .L2_SCHED_OWNERSHIP_QUERY_BIAS_EN(L2_SCHED_OWNERSHIP_QUERY_BIAS_EN),
    .L2_SCHED_OWNERSHIP_QUERY_STRONG_BIAS_EN(L2_SCHED_OWNERSHIP_QUERY_STRONG_BIAS_EN),
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
    .L1_BYPASS_QOS_TH(L1_BYPASS_QOS_TH),
    .L1_DEMAND_FILL_QOS_TH(L1_DEMAND_FILL_QOS_TH),
    .L1_PREFETCH_FILL_QOS_TH(L1_PREFETCH_FILL_QOS_TH),
    .L1_MISS_BYPASS_QOS_TH(L1_MISS_BYPASS_QOS_TH),
    .HIER_POLICY_EN(HIER_POLICY_EN),
    .L1_CONGEST_BYPASS_QOS_TH(L1_CONGEST_BYPASS_QOS_TH),
    .PREFETCH_CONGEST_QOS_TH(PREFETCH_CONGEST_QOS_TH),
    .PREFETCH_HBM_ISSUE_QOS_TH(PREFETCH_HBM_ISSUE_QOS_TH),
    .PREFETCH_HBM_ISSUE_RELAX_HOT(PREFETCH_HBM_ISSUE_RELAX_HOT),
    .EXEC_CONGEST_Q_LEVEL_TH(EXEC_CONGEST_Q_LEVEL_TH),
    .HBM_CONGEST_COLD_EXTRA_LAT(HBM_CONGEST_COLD_EXTRA_LAT),
    .HBM_CONGEST_HOT_EXTRA_LAT(HBM_CONGEST_HOT_EXTRA_LAT),
    .HBM_CONGEST_PREFETCH_EXTRA_LAT(HBM_CONGEST_PREFETCH_EXTRA_LAT),
    .L1_FILL_ON_HBM_MISS(L1_FILL_ON_HBM_MISS),
    .L2_HIT_REUSE_BUFFER_EN(L2_HIT_REUSE_BUFFER_EN),
    .L2_HIT_REUSE_BUFFER_DEPTH(L2_HIT_REUSE_BUFFER_DEPTH),
    .PF_ADAPT_EN(PF_ADAPT_EN),
    .PF_QOS_TH(PF_QOS_TH),
    .HBM_IF_Q_DEPTH(HBM_IF_Q_DEPTH),
    .HBM_IF_SERVICE_CYCLES(HBM_IF_SERVICE_CYCLES),
    .KV_MAP_ENABLE(KV_MAP_ENABLE),
    .KV_BLOCK_OFF_BITS(KV_BLOCK_OFF_BITS),
    .KV_DIR_ENTRIES(KV_DIR_ENTRIES),
    .KV_REAL_LAYOUT_EN(KV_REAL_LAYOUT_EN),
    .KV_TOKEN_BLOCK_BITS(KV_TOKEN_BLOCK_BITS),
    .KV_TYPE_ADDR_BIT(KV_TYPE_ADDR_BIT),
    .KV_MAP_SCORE_REPL_EN(KV_MAP_SCORE_REPL_EN),
    .KV_MAP_SCORE_REPL_HW_WIN(KV_MAP_SCORE_REPL_HW_WIN),
    .KV_MAP_SCORE_PROTECT_TH(KV_MAP_SCORE_PROTECT_TH),
      .KV_MAP_SCORE_DECAY_EN(KV_MAP_SCORE_DECAY_EN),
      .KV_MAP_SCORE_DECAY_LOG2(KV_MAP_SCORE_DECAY_LOG2),
      .ATTN_SCHED_EN(ATTN_SCHED_EN),
      .ATTN_SCHED_RELAX_REUSE_ONLY_PROTECT_UNDER_PRESSURE_EN(ATTN_SCHED_RELAX_REUSE_ONLY_PROTECT_UNDER_PRESSURE_EN),
      .ATTN_SCHED_RELAX_REUSE_ONLY_PROTECT_QOS_TH(ATTN_SCHED_RELAX_REUSE_ONLY_PROTECT_QOS_TH),
      .ATTN_SCHED_STEAL_REUSE_ONLY_OWNERSHIP_EN(ATTN_SCHED_STEAL_REUSE_ONLY_OWNERSHIP_EN),
      .ATTN_SCHED_STEAL_REUSE_ONLY_QOS_TH(ATTN_SCHED_STEAL_REUSE_ONLY_QOS_TH),
      .ATTN_SCHED_OVERRIDE_FILL_BLOCK_WITH_UTILITY_EN(ATTN_SCHED_OVERRIDE_FILL_BLOCK_WITH_UTILITY_EN),
      .ATTN_SCHED_OVERRIDE_FILL_BLOCK_QOS_TH(ATTN_SCHED_OVERRIDE_FILL_BLOCK_QOS_TH),
      .ATTN_SCHED_BACKEND_ISSUE_OWNERSHIP_EN(ATTN_SCHED_BACKEND_ISSUE_OWNERSHIP_EN),
      .ATTN_SCHED_BACKEND_ISSUE_OWNERSHIP_QOS_TH(ATTN_SCHED_BACKEND_ISSUE_OWNERSHIP_QOS_TH),
       .ATTN_SCHED_BACKEND_ISSUE_RESCUE_EN(ATTN_SCHED_BACKEND_ISSUE_RESCUE_EN),
       .ATTN_SCHED_BACKEND_ISSUE_RESCUE_QOS_TH(ATTN_SCHED_BACKEND_ISSUE_RESCUE_QOS_TH),
       .ATTN_SCHED_PROMOTE_QUERY_TEMPORAL_PRIMARY_UTILITY_EN(ATTN_SCHED_PROMOTE_QUERY_TEMPORAL_PRIMARY_UTILITY_EN),
       .ATTN_SCHED_PROMOTE_QUERY_TEMPORAL_QOS_TH(ATTN_SCHED_PROMOTE_QUERY_TEMPORAL_QOS_TH),
       .ATTN_SCHED_FORCE_QUERY_TEMPORAL_DIRECT_TAKE_EN(ATTN_SCHED_FORCE_QUERY_TEMPORAL_DIRECT_TAKE_EN),
       .ATTN_SCHED_OWNERSHIP_QOS_FLOOR_EN(ATTN_SCHED_OWNERSHIP_QOS_FLOOR_EN),
      .ATTN_SCHED_OWNERSHIP_QOS_FLOOR(ATTN_SCHED_OWNERSHIP_QOS_FLOOR),
      .ATTN_SCHED_OWNERSHIP_QOS_BACKEND_FLOOR(ATTN_SCHED_OWNERSHIP_QOS_BACKEND_FLOOR),
      .ATTN_SCHED_MASTER_OWNERSHIP_FILL_STEAL_EN(ATTN_SCHED_MASTER_OWNERSHIP_FILL_STEAL_EN),
      .ATTN_SCHED_MASTER_OWNERSHIP_FILL_ONLY_EN(ATTN_SCHED_MASTER_OWNERSHIP_FILL_ONLY_EN),
      .ATTN_SCHED_MASTER_OWNERSHIP_BLOCK_RESCUE_EN(ATTN_SCHED_MASTER_OWNERSHIP_BLOCK_RESCUE_EN),
      .ATTN_SCHED_MASTER_OWNERSHIP_FILL_STEAL_QOS_TH(ATTN_SCHED_MASTER_OWNERSHIP_FILL_STEAL_QOS_TH),
      .ATTN_SCHED_MASTER_OUTPUT_RESCUE_EN(ATTN_SCHED_MASTER_OUTPUT_RESCUE_EN),
      .ATTN_SCHED_MASTER_OUTPUT_RESCUE_QOS_TH(ATTN_SCHED_MASTER_OUTPUT_RESCUE_QOS_TH),
      .ATTN_SCHED_MASTER_SLAVE_FILL_EN(ATTN_SCHED_MASTER_SLAVE_FILL_EN),
      .ATTN_SCHED_MASTER_SLAVE_PROTECT_EN(ATTN_SCHED_MASTER_SLAVE_PROTECT_EN),
      .ATTN_SCHED_MASTER_SLAVE_BACKEND_EN(ATTN_SCHED_MASTER_SLAVE_BACKEND_EN),
      .ATTN_SCHED_MASTER_SLAVE_COMP_GUARD_EN(ATTN_SCHED_MASTER_SLAVE_COMP_GUARD_EN),
      .ATTN_SCHED_BACKEND_ISSUE_QOS_BOOST_EN(ATTN_SCHED_BACKEND_ISSUE_QOS_BOOST_EN),
      .ATTN_SCHED_BACKEND_ISSUE_STRONG_QUERY_GATE_EN(ATTN_SCHED_BACKEND_ISSUE_STRONG_QUERY_GATE_EN),
      .ATTN_SCHED_BACKEND_ISSUE_OWNERSHIP_STRONG_QUERY_GATE_EN(ATTN_SCHED_BACKEND_ISSUE_OWNERSHIP_STRONG_QUERY_GATE_EN),
      .ATTN_SCHED_BACKEND_ISSUE_HIGH_SERVICE_ESCAPE_EN(ATTN_SCHED_BACKEND_ISSUE_HIGH_SERVICE_ESCAPE_EN),
      .ATTN_SCHED_BACKEND_ISSUE_HIGH_SERVICE_TH(ATTN_SCHED_BACKEND_ISSUE_HIGH_SERVICE_TH),
      .ATTN_SCHED_BACKEND_ISSUE_ROI_PRESSURE_GATE_EN(ATTN_SCHED_BACKEND_ISSUE_ROI_PRESSURE_GATE_EN),
      .ATTN_SCHED_SAFE_FALLBACK_EN(ATTN_SCHED_SAFE_FALLBACK_EN),
      .ATTN_SCHED_SAFE_FALLBACK_LOCAL_EN(ATTN_SCHED_SAFE_FALLBACK_LOCAL_EN),
      .ATTN_SCHED_SAFE_FALLBACK_LOCAL_AGGR_EN(ATTN_SCHED_SAFE_FALLBACK_LOCAL_AGGR_EN),
      .ATTN_SCHED_SAFE_FALLBACK_EARLY_FLOOR_EN(ATTN_SCHED_SAFE_FALLBACK_EARLY_FLOOR_EN),
      .ATTN_SCHED_L2BIAS_H2O_HOT_GUARD_EN(ATTN_SCHED_L2BIAS_H2O_HOT_GUARD_EN),
      .ATTN_SCHED_BACKEND_ISSUE_COUNTER_GATE_EN(ATTN_SCHED_BACKEND_ISSUE_COUNTER_GATE_EN),
      .ATTN_SCHED_BACKEND_ISSUE_SELECTIVE_STRONG_GATE_EN(ATTN_SCHED_BACKEND_ISSUE_SELECTIVE_STRONG_GATE_EN),
      .ATTN_SCHED_PHASE_SELECTOR_EN(ATTN_SCHED_PHASE_SELECTOR_EN),
      .ATTN_SCHED_CAPACITY_PRESSURE_ADAPTIVE_EN(ATTN_SCHED_CAPACITY_PRESSURE_ADAPTIVE_EN),
      .ATTN_SCHED_ROI_GUARD_EN(ATTN_SCHED_ROI_GUARD_EN),
      .L2_SCHED_OWNERSHIP_QUERY_ADAPTIVE_BIAS_EN(L2_SCHED_OWNERSHIP_QUERY_ADAPTIVE_BIAS_EN),
      .CMDQ_DEPTH(CMDQ_DEPTH),
      .CMDQ_LOOKAHEAD_GROUP_TARGET_EN(CMDQ_LOOKAHEAD_GROUP_TARGET_EN),
      .CMDQ_LOOKAHEAD_MAX_DELTA(CMDQ_LOOKAHEAD_MAX_DELTA),
      .CMDQ_DESCRIPTOR_GROUP_TARGET_EN(CMDQ_DESCRIPTOR_GROUP_TARGET_EN),
      .CMDQ_DESCRIPTOR_GROUP_TARGET_DELTA(CMDQ_DESCRIPTOR_GROUP_TARGET_DELTA),
      .CMDQ_DESCRIPTOR_GROUP_TARGET_ADAPTIVE_EN(CMDQ_DESCRIPTOR_GROUP_TARGET_ADAPTIVE_EN),
      .CMDQ_DESCRIPTOR_GROUP_TARGET_HIGH_DELTA(CMDQ_DESCRIPTOR_GROUP_TARGET_HIGH_DELTA),
      .CMDQ_DESCRIPTOR_GROUP_TARGET_DENSITY_TH(CMDQ_DESCRIPTOR_GROUP_TARGET_DENSITY_TH),
      .LINE_IDX_W(LINE_IDX_W)
      ) u_mcu (
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
    .trace_desc_kiloscore_extra_cvr_hint(trace_desc_kiloscore_extra_cvr_hint),
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

    .mem_re(core_mem_re),
    .mem_raddr(core_mem_raddr),
    .mem_rdata(core_mem_rdata),
    .mem_rvalid(core_mem_rvalid),
    .mem_we(core_mem_we),
    .mem_waddr(core_mem_waddr),
    .mem_wdata(core_mem_wdata),
    .stat_demand_req_cnt(stat_demand_req_cnt),
    .stat_demand_miss_cnt(stat_demand_miss_cnt),
    .stat_miss_rate_permille(stat_miss_rate_permille),
    .stat_map_overflow_cnt(),
    .stat_map_repl_cnt(),
    .stat_map_seq_reclaim_cnt(),
    .stat_l2_comp_fill_cnt(),
    .stat_l2_comp_readback_cnt(),
    .stat_l2_comp_spill_cnt(),
    .stat_l2_dirty_wb_req_cnt(),
    .stat_hbmif_burst_merge_cnt(),
    .stat_hbmif_wr_drain_cycle_cnt()
  );

  generate
    if (USE_AXI_IF) begin : GEN_AXI_BRIDGE
      // Keep legacy simple-memory outputs quiesced when AXI bridge is active.
      assign mem_re = 1'b0;
      assign mem_raddr = {ADDR_W{1'b0}};
      assign mem_we = 1'b0;
      assign mem_waddr = {ADDR_W{1'b0}};
      assign mem_wdata = {DATA_W{1'b0}};

      kcmu_axi_mem_bridge #(
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W)
      ) u_axi_bridge (
        .clk(clk),
        .rst_n(rst_n),
        .req_re(core_mem_re),
        .req_raddr(core_mem_raddr),
        .resp_rdata(core_mem_rdata),
        .resp_rvalid(core_mem_rvalid),
        .req_we(core_mem_we),
        .req_waddr(core_mem_waddr),
        .req_wdata(core_mem_wdata),
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
    end else begin : GEN_SIMPLE_MEM
      assign mem_re = core_mem_re;
      assign mem_raddr = core_mem_raddr;
      assign mem_we = core_mem_we;
      assign mem_waddr = core_mem_waddr;
      assign mem_wdata = core_mem_wdata;
      assign core_mem_rdata = mem_rdata;
      assign core_mem_rvalid = mem_rvalid;

      assign m_axi_araddr = {ADDR_W{1'b0}};
      assign m_axi_arvalid = 1'b0;
      assign m_axi_rready = 1'b0;
      assign m_axi_awaddr = {ADDR_W{1'b0}};
      assign m_axi_awvalid = 1'b0;
      assign m_axi_wdata = {DATA_W{1'b0}};
      assign m_axi_wstrb = {(DATA_W/8){1'b0}};
      assign m_axi_wvalid = 1'b0;
      assign m_axi_bready = 1'b0;
    end
  endgenerate

endmodule

module kcmu_axi_mem_bridge #(
  parameter integer ADDR_W = 8,
  parameter integer DATA_W = 32,
  parameter integer RD_QUEUE_DEPTH = 8,
  parameter integer WR_QUEUE_DEPTH = 8,
  parameter integer RD_MAX_OUTSTANDING = 4,
  parameter integer WR_MAX_OUTSTANDING = 4
)(
  input  logic                 clk,
  input  logic                 rst_n,

  input  logic                 req_re,
  input  logic [ADDR_W-1:0]    req_raddr,
  output logic [DATA_W-1:0]    resp_rdata,
  output logic                 resp_rvalid,

  input  logic                 req_we,
  input  logic [ADDR_W-1:0]    req_waddr,
  input  logic [DATA_W-1:0]    req_wdata,

  output logic [ADDR_W-1:0]    m_axi_araddr,
  output logic                 m_axi_arvalid,
  input  logic                 m_axi_arready,
  input  logic [DATA_W-1:0]    m_axi_rdata,
  input  logic                 m_axi_rvalid,
  output logic                 m_axi_rready,

  output logic [ADDR_W-1:0]    m_axi_awaddr,
  output logic                 m_axi_awvalid,
  input  logic                 m_axi_awready,
  output logic [DATA_W-1:0]    m_axi_wdata,
  output logic [(DATA_W/8)-1:0] m_axi_wstrb,
  output logic                 m_axi_wvalid,
  input  logic                 m_axi_wready,
  input  logic                 m_axi_bvalid,
  output logic                 m_axi_bready
);
  localparam integer RD_Q_DEPTH_SAFE = (RD_QUEUE_DEPTH < 1) ? 1 : RD_QUEUE_DEPTH;
  localparam integer WR_Q_DEPTH_SAFE = (WR_QUEUE_DEPTH < 1) ? 1 : WR_QUEUE_DEPTH;
  localparam integer RD_OS_MAX_SAFE  = (RD_MAX_OUTSTANDING < 1) ? 1 : RD_MAX_OUTSTANDING;
  localparam integer WR_OS_MAX_SAFE  = (WR_MAX_OUTSTANDING < 1) ? 1 : WR_MAX_OUTSTANDING;
  localparam integer RD_Q_PTR_W = (RD_Q_DEPTH_SAFE <= 1) ? 1 : $clog2(RD_Q_DEPTH_SAFE);
  localparam integer WR_Q_PTR_W = (WR_Q_DEPTH_SAFE <= 1) ? 1 : $clog2(WR_Q_DEPTH_SAFE);
  localparam integer RD_Q_CNT_W = (RD_Q_DEPTH_SAFE <= 1) ? 1 : $clog2(RD_Q_DEPTH_SAFE + 1);
  localparam integer WR_Q_CNT_W = (WR_Q_DEPTH_SAFE <= 1) ? 1 : $clog2(WR_Q_DEPTH_SAFE + 1);
  localparam integer RD_OS_W = (RD_OS_MAX_SAFE <= 1) ? 1 : $clog2(RD_OS_MAX_SAFE + 1);
  localparam integer WR_OS_W = (WR_OS_MAX_SAFE <= 1) ? 1 : $clog2(WR_OS_MAX_SAFE + 1);

  logic [ADDR_W-1:0] rd_q_addr [0:RD_Q_DEPTH_SAFE-1];
  logic [RD_Q_PTR_W-1:0] rd_q_head;
  logic [RD_Q_PTR_W-1:0] rd_q_tail;
  logic [RD_Q_CNT_W-1:0] rd_q_count;
  logic [RD_OS_W-1:0] rd_outstanding;
  logic rd_q_full;
  logic rd_issue_hs;
  logic rd_resp_hs;
  logic rd_enq;
  logic rd_deq;

  logic [ADDR_W-1:0] wr_q_addr [0:WR_Q_DEPTH_SAFE-1];
  logic [DATA_W-1:0] wr_q_data [0:WR_Q_DEPTH_SAFE-1];
  logic [WR_Q_PTR_W-1:0] wr_q_head;
  logic [WR_Q_PTR_W-1:0] wr_q_tail;
  logic [WR_Q_CNT_W-1:0] wr_q_count;
  logic wr_q_full;
  logic wr_enq;
  logic wr_load;

  logic wr_send_active;
  logic wr_aw_sent;
  logic wr_w_sent;
  logic [ADDR_W-1:0] wr_send_addr;
  logic [DATA_W-1:0] wr_send_data;
  logic [WR_OS_W-1:0] wr_b_outstanding;
  logic wr_aw_hs;
  logic wr_w_hs;
  logic wr_issue_done;
  logic wr_resp_hs;

  function automatic [RD_Q_PTR_W-1:0] rd_ptr_inc(
    input [RD_Q_PTR_W-1:0] ptr
  );
    begin
      if (RD_Q_DEPTH_SAFE <= 1) begin
        rd_ptr_inc = {RD_Q_PTR_W{1'b0}};
      end else if (ptr == RD_Q_PTR_W'(RD_Q_DEPTH_SAFE - 1)) begin
        rd_ptr_inc = {RD_Q_PTR_W{1'b0}};
      end else begin
        rd_ptr_inc = ptr + RD_Q_PTR_W'(1);
      end
    end
  endfunction

  function automatic [WR_Q_PTR_W-1:0] wr_ptr_inc(
    input [WR_Q_PTR_W-1:0] ptr
  );
    begin
      if (WR_Q_DEPTH_SAFE <= 1) begin
        wr_ptr_inc = {WR_Q_PTR_W{1'b0}};
      end else if (ptr == WR_Q_PTR_W'(WR_Q_DEPTH_SAFE - 1)) begin
        wr_ptr_inc = {WR_Q_PTR_W{1'b0}};
      end else begin
        wr_ptr_inc = ptr + WR_Q_PTR_W'(1);
      end
    end
  endfunction

`ifndef SYNTHESIS
  logic [31:0] stat_axi_rd_drop_cnt;
  logic [31:0] stat_axi_wr_drop_cnt;
  logic [31:0] stat_axi_rd_q_peak;
  logic [31:0] stat_axi_wr_q_peak;
  logic [31:0] stat_axi_rd_issue_cnt;
  logic [31:0] stat_axi_rd_resp_cnt;
  logic [31:0] stat_axi_wr_issue_cnt;
  logic [31:0] stat_axi_wr_resp_cnt;
`endif

  assign rd_q_full = (rd_q_count == RD_Q_CNT_W'(RD_Q_DEPTH_SAFE));
  assign wr_q_full = (wr_q_count == WR_Q_CNT_W'(WR_Q_DEPTH_SAFE));
  assign rd_deq = rd_issue_hs;
  assign rd_enq = req_re && (!rd_q_full || rd_deq);
  assign wr_load = !wr_send_active &&
                   (wr_q_count != WR_Q_CNT_W'(0)) &&
                   (wr_b_outstanding < WR_OS_W'(WR_OS_MAX_SAFE));
  assign wr_enq = req_we && (!wr_q_full || wr_load);

  assign m_axi_araddr = rd_q_addr[rd_q_head];
  assign m_axi_arvalid = (rd_q_count != RD_Q_CNT_W'(0)) &&
                         (rd_outstanding < RD_OS_W'(RD_OS_MAX_SAFE));
  assign m_axi_rready = 1'b1;
  assign rd_issue_hs = m_axi_arvalid && m_axi_arready;
  assign rd_resp_hs = m_axi_rvalid && (rd_outstanding != RD_OS_W'(0));

  assign m_axi_awaddr = wr_send_addr;
  assign m_axi_awvalid = wr_send_active && !wr_aw_sent;
  assign m_axi_wdata = wr_send_data;
  assign m_axi_wstrb = {(DATA_W/8){1'b1}};
  assign m_axi_wvalid = wr_send_active && !wr_w_sent;
  assign m_axi_bready = (wr_b_outstanding != WR_OS_W'(0));
  assign wr_aw_hs = m_axi_awvalid && m_axi_awready;
  assign wr_w_hs = m_axi_wvalid && m_axi_wready;
  assign wr_issue_done = wr_send_active && (wr_aw_sent || wr_aw_hs) && (wr_w_sent || wr_w_hs);
  assign wr_resp_hs = m_axi_bvalid && m_axi_bready;

  always @(posedge clk) begin
    if (!rst_n) begin
      rd_q_head <= {RD_Q_PTR_W{1'b0}};
      rd_q_tail <= {RD_Q_PTR_W{1'b0}};
      rd_q_count <= {RD_Q_CNT_W{1'b0}};
      rd_outstanding <= {RD_OS_W{1'b0}};

      wr_q_head <= {WR_Q_PTR_W{1'b0}};
      wr_q_tail <= {WR_Q_PTR_W{1'b0}};
      wr_q_count <= {WR_Q_CNT_W{1'b0}};
      wr_send_active <= 1'b0;
      wr_aw_sent <= 1'b0;
      wr_w_sent <= 1'b0;
      wr_send_addr <= {ADDR_W{1'b0}};
      wr_send_data <= {DATA_W{1'b0}};
      wr_b_outstanding <= {WR_OS_W{1'b0}};

      resp_rdata <= {DATA_W{1'b0}};
      resp_rvalid <= 1'b0;
`ifndef SYNTHESIS
      stat_axi_rd_drop_cnt <= 32'd0;
      stat_axi_wr_drop_cnt <= 32'd0;
      stat_axi_rd_q_peak <= 32'd0;
      stat_axi_wr_q_peak <= 32'd0;
      stat_axi_rd_issue_cnt <= 32'd0;
      stat_axi_rd_resp_cnt <= 32'd0;
      stat_axi_wr_issue_cnt <= 32'd0;
      stat_axi_wr_resp_cnt <= 32'd0;
`endif
    end else begin
      resp_rvalid <= 1'b0;

      // Read request enqueue/dequeue.
      if (rd_enq) begin
        rd_q_addr[rd_q_tail] <= req_raddr;
        rd_q_tail <= rd_ptr_inc(rd_q_tail);
      end
      if (rd_deq) begin
        rd_q_head <= rd_ptr_inc(rd_q_head);
      end
      case ({rd_enq, rd_deq})
        2'b10: rd_q_count <= rd_q_count + RD_Q_CNT_W'(1);
        2'b01: rd_q_count <= rd_q_count - RD_Q_CNT_W'(1);
        default: rd_q_count <= rd_q_count;
      endcase

      // Read outstanding bookkeeping and response return.
      if (rd_resp_hs) begin
        resp_rdata <= m_axi_rdata;
        resp_rvalid <= 1'b1;
      end
      case ({rd_issue_hs, rd_resp_hs})
        2'b10: rd_outstanding <= rd_outstanding + RD_OS_W'(1);
        2'b01: rd_outstanding <= rd_outstanding - RD_OS_W'(1);
        default: rd_outstanding <= rd_outstanding;
      endcase

      // Write request enqueue.
      if (wr_enq) begin
        wr_q_addr[wr_q_tail] <= req_waddr;
        wr_q_data[wr_q_tail] <= req_wdata;
        wr_q_tail <= wr_ptr_inc(wr_q_tail);
      end
      if (wr_load) begin
        wr_send_addr <= wr_q_addr[wr_q_head];
        wr_send_data <= wr_q_data[wr_q_head];
        wr_q_head <= wr_ptr_inc(wr_q_head);
      end
      case ({wr_enq, wr_load})
        2'b10: wr_q_count <= wr_q_count + WR_Q_CNT_W'(1);
        2'b01: wr_q_count <= wr_q_count - WR_Q_CNT_W'(1);
        default: wr_q_count <= wr_q_count;
      endcase

      // Write AW/W channel progress.
      if (wr_load) begin
        wr_send_active <= 1'b1;
        wr_aw_sent <= 1'b0;
        wr_w_sent <= 1'b0;
      end else if (wr_send_active) begin
        if (wr_issue_done) begin
          wr_send_active <= 1'b0;
          wr_aw_sent <= 1'b0;
          wr_w_sent <= 1'b0;
        end else begin
          if (wr_aw_hs) begin
            wr_aw_sent <= 1'b1;
          end
          if (wr_w_hs) begin
            wr_w_sent <= 1'b1;
          end
        end
      end

      // Write response bookkeeping.
      case ({wr_issue_done, wr_resp_hs})
        2'b10: wr_b_outstanding <= wr_b_outstanding + WR_OS_W'(1);
        2'b01: wr_b_outstanding <= wr_b_outstanding - WR_OS_W'(1);
        default: wr_b_outstanding <= wr_b_outstanding;
      endcase

`ifndef SYNTHESIS
      if (req_re && !rd_enq) begin
        stat_axi_rd_drop_cnt <= stat_axi_rd_drop_cnt + 32'd1;
      end
      if (req_we && !wr_enq) begin
        stat_axi_wr_drop_cnt <= stat_axi_wr_drop_cnt + 32'd1;
      end
      if (rd_q_count > stat_axi_rd_q_peak) stat_axi_rd_q_peak <= rd_q_count;
      if (wr_q_count > stat_axi_wr_q_peak) stat_axi_wr_q_peak <= wr_q_count;
      if (rd_issue_hs) stat_axi_rd_issue_cnt <= stat_axi_rd_issue_cnt + 32'd1;
      if (rd_resp_hs) stat_axi_rd_resp_cnt <= stat_axi_rd_resp_cnt + 32'd1;
      if (wr_issue_done) stat_axi_wr_issue_cnt <= stat_axi_wr_issue_cnt + 32'd1;
      if (wr_resp_hs) stat_axi_wr_resp_cnt <= stat_axi_wr_resp_cnt + 32'd1;
`endif
    end
  end
endmodule
