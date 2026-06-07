`timescale 1ns/1ps

module kcmu_fpga_top #(
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
  parameter logic [SCORE_W-1:0] TRUE_H2O_HH_SCORE_TH = SCORE_W'(8'hC0),
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
  parameter bit     TRUE_H2O_RECENT_VALID_SERVICE_EN = 1'b0,
  parameter bit     TRUE_H2O_L2_REUSE_PROMOTE_EN = 1'b0,
  parameter bit     TRUE_H2O_RETENTION_SERVICE_DECOUPLE_EN = 1'b0,
  parameter bit     TRUE_H2O_VALIDATED_OR_RECENT_RETENTION_EN = 1'b0,
  parameter bit     TRUE_H2O_L1_VALIDATED_OR_RECENT_RETENTION_EN = 1'b0,
  parameter bit     TRUE_H2O_VICTIM_VALIDATED_OR_RECENT_PROTECT_EN = 1'b0,
  parameter bit     TRUE_H2O_STORAGE_QOS_DECOUPLE_EN = 1'b0,
  parameter bit     PREFETCH_FORCE_DISABLE_EN = 1'b0,
  parameter bit     UTILITY_HEAD_ADAPTIVE_EN = 1'b1,
  parameter bit     UTILITY_QUERY_AWARE_EN = 1'b1,
  parameter bit     UTILITY_COST_AWARE_EN = 1'b1,
  parameter bit     UTILITY_BACKEND_CRITICAL_EN = 1'b1,
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
  parameter logic [SCORE_W-1:0] BACKEND_CRITICAL_HOT_TH = SCORE_W'(8'hD8),
  parameter logic [SCORE_W-1:0] BACKEND_CRITICAL_WARM_TH = SCORE_W'(8'hB8),
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
  parameter integer L2_LINES = 32,
  parameter integer L2_WAYS = 1,
  parameter integer L2_VB_LINES = 2,
  parameter bit     L2_VB_ENABLE = 1'b1,
  parameter bit     L2_VB_CLEAN_READONLY_EN = 1'b0,
  parameter bit     L2_GROUP_FETCH_TO_CVR_EN = 1'b0,
  parameter bit     L2_WRITE_ALLOCATE = 1'b1,
  parameter bit     L2_WRITE_THROUGH_EN = 1'b1,
  parameter bit     L2_BG_DIRTY_FLUSH_EN = 1'b1,
  parameter bit     L2_SERVICE_ISSUE_DEFER_DIRTY_FLUSH_EN = 1'b0,
  parameter bit     L2_SERVICE_ISSUE_CLEAN_VICTIM_RESCUE_EN = 1'b0,
  parameter logic [2:0] L2_SERVICE_ISSUE_CLEAN_VICTIM_MARGIN = 3'd2,
  parameter bit     L2_SCHED_OWNERSHIP_QUERY_BIAS_EN = 1'b0,
  parameter bit     L2_SCHED_OWNERSHIP_QUERY_STRONG_BIAS_EN = 1'b0,
  parameter bit     L2_SCHED_OWNERSHIP_QUERY_ADAPTIVE_BIAS_EN = 1'b0,
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
  parameter integer KV_BLOCK_OFF_BITS = 2,
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
  parameter integer CMDQ_DEPTH = 1,
  parameter bit     CMDQ_LOOKAHEAD_GROUP_TARGET_EN = 1'b0,
  parameter integer CMDQ_LOOKAHEAD_MAX_DELTA = 8,
  parameter bit     CMDQ_DESCRIPTOR_GROUP_TARGET_EN = 1'b0,
  parameter integer CMDQ_DESCRIPTOR_GROUP_TARGET_DELTA = 2,
  parameter bit     CMDQ_DESCRIPTOR_GROUP_TARGET_ADAPTIVE_EN = 1'b0,
  parameter integer CMDQ_DESCRIPTOR_GROUP_TARGET_HIGH_DELTA = 3,
  parameter integer CMDQ_DESCRIPTOR_GROUP_TARGET_DENSITY_TH = 3,
  parameter integer AXIL_ADDR_W = 16,
  parameter integer TRACE_DEPTH = 256,
  parameter integer RESP_DEPTH = 256
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
  import kcmu_pkg::*;

  localparam integer LINE_IDX_W = (LINES <= 1) ? 1 : $clog2(LINES);
  localparam logic [AXIL_ADDR_W-1:0] REG_CONTROL       = AXIL_ADDR_W'(16'h0000);
  localparam logic [AXIL_ADDR_W-1:0] REG_STATUS        = AXIL_ADDR_W'(16'h0004);
  localparam logic [AXIL_ADDR_W-1:0] REG_TRACE_COUNT   = AXIL_ADDR_W'(16'h0008);
  localparam logic [AXIL_ADDR_W-1:0] REG_RESP_COUNT    = AXIL_ADDR_W'(16'h000C);
  localparam logic [AXIL_ADDR_W-1:0] REG_LAST_META     = AXIL_ADDR_W'(16'h0010);
  localparam logic [AXIL_ADDR_W-1:0] REG_LAST_RDATA    = AXIL_ADDR_W'(16'h0014);
  localparam logic [AXIL_ADDR_W-1:0] REG_ERROR_CODE    = AXIL_ADDR_W'(16'h0018);
  localparam logic [AXIL_ADDR_W-1:0] REG_CMD_W0        = AXIL_ADDR_W'(16'h0020);
  localparam logic [AXIL_ADDR_W-1:0] REG_CMD_W1        = AXIL_ADDR_W'(16'h0024);
  localparam logic [AXIL_ADDR_W-1:0] REG_CMD_W2        = AXIL_ADDR_W'(16'h0028);
  localparam logic [AXIL_ADDR_W-1:0] REG_STAT_KV_OVF   = AXIL_ADDR_W'(16'h0040);
  localparam logic [AXIL_ADDR_W-1:0] REG_STAT_KV_REPL  = AXIL_ADDR_W'(16'h0044);
  localparam logic [AXIL_ADDR_W-1:0] REG_STAT_KV_SEQRC = AXIL_ADDR_W'(16'h0048);
  localparam logic [AXIL_ADDR_W-1:0] REG_STAT_L2_CPF   = AXIL_ADDR_W'(16'h004C);
  localparam logic [AXIL_ADDR_W-1:0] REG_STAT_L2_CRB   = AXIL_ADDR_W'(16'h0050);
  localparam logic [AXIL_ADDR_W-1:0] REG_STAT_L2_CSP   = AXIL_ADDR_W'(16'h0054);
  localparam logic [AXIL_ADDR_W-1:0] REG_STAT_L2_WBENQ = AXIL_ADDR_W'(16'h0058);
  localparam logic [AXIL_ADDR_W-1:0] REG_STAT_HBM_BM   = AXIL_ADDR_W'(16'h005C);
  localparam logic [AXIL_ADDR_W-1:0] REG_STAT_HBM_WD   = AXIL_ADDR_W'(16'h0060);
  localparam logic [AXIL_ADDR_W-1:0] REG_CONFIG_ID      = AXIL_ADDR_W'(16'h001C);
  localparam logic [AXIL_ADDR_W-1:0] REG_CONFIG_L1      = AXIL_ADDR_W'(16'h0030);
  localparam logic [AXIL_ADDR_W-1:0] REG_CONFIG_L2      = AXIL_ADDR_W'(16'h0034);
  localparam logic [AXIL_ADDR_W-1:0] REG_CONFIG_BACKEND = AXIL_ADDR_W'(16'h0038);
  localparam logic [AXIL_ADDR_W-1:0] REG_CONFIG_FEATURE = AXIL_ADDR_W'(16'h003C);
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_DEMAND_REQ = AXIL_ADDR_W'(16'h0080);
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_L1_HIT    = AXIL_ADDR_W'(16'h0084);
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_L1_MISS   = AXIL_ADDR_W'(16'h0088);
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_L2_HIT    = AXIL_ADDR_W'(16'h008C);
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_L2_MISS   = AXIL_ADDR_W'(16'h0090);
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_MISS_RATE = AXIL_ADDR_W'(16'h0094);
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_RD_REQ    = AXIL_ADDR_W'(16'h0098);
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_WR_REQ    = AXIL_ADDR_W'(16'h009C);
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_RD_LAT    = AXIL_ADDR_W'(16'h00A0);
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_WR_LAT    = AXIL_ADDR_W'(16'h00A4);
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_MISS_PEN  = AXIL_ADDR_W'(16'h00A8);
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_POLICY_CYC = AXIL_ADDR_W'(16'h00AC);
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_PF_ACCEPT = AXIL_ADDR_W'(16'h00B0);
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_PF_FILL   = AXIL_ADDR_W'(16'h00B4);
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_PF_USEFUL = AXIL_ADDR_W'(16'h00B8);
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_PF_POLLUTE = AXIL_ADDR_W'(16'h00BC);
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_BACK_STALL = AXIL_ADDR_W'(16'h00C0);
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_BACK_QFULL = AXIL_ADDR_W'(16'h00C4);
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_STATUS    = AXIL_ADDR_W'(16'h00D0);
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_SEQ       = AXIL_ADDR_W'(16'h00D4);
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_FLAGS     = AXIL_ADDR_W'(16'h00D8);
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_DEMAND_REQ = AXIL_ADDR_W'(16'h0100);
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_L1_HIT    = AXIL_ADDR_W'(16'h0104);
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_L1_MISS   = AXIL_ADDR_W'(16'h0108);
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_L2_HIT    = AXIL_ADDR_W'(16'h010C);
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_L2_MISS   = AXIL_ADDR_W'(16'h0110);
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_RD_REQ    = AXIL_ADDR_W'(16'h0114);
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_WR_REQ    = AXIL_ADDR_W'(16'h0118);
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_RD_LAT    = AXIL_ADDR_W'(16'h011C);
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_WR_LAT    = AXIL_ADDR_W'(16'h0120);
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_MISS_PEN  = AXIL_ADDR_W'(16'h0124);
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_POLICY_CYC = AXIL_ADDR_W'(16'h0128);
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_PF_ACCEPT = AXIL_ADDR_W'(16'h012C);
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_PF_FILL   = AXIL_ADDR_W'(16'h0130);
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_PF_USEFUL = AXIL_ADDR_W'(16'h0134);
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_PF_POLLUTE = AXIL_ADDR_W'(16'h0138);
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_BACK_STALL = AXIL_ADDR_W'(16'h013C);
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_BACK_QFULL = AXIL_ADDR_W'(16'h0140);
  localparam logic [AXIL_ADDR_W-1:0] TRACE_BASE        = AXIL_ADDR_W'(16'h1000);
  localparam logic [AXIL_ADDR_W-1:0] RESP_BASE         = AXIL_ADDR_W'(16'h4000);
  localparam logic [31:0] ERR_NONE = 32'd0;
  localparam logic [31:0] ERR_BUSY = 32'd1;
  localparam logic [31:0] ERR_TRACE_RANGE = 32'd2;
  localparam logic [31:0] KILOWARE_CONFIG_ID = 32'h5634_3402; // "V44" + append-only CSR snapshot map rev 2
  localparam logic [31:0] KILOWARE_CONFIG_L1 = LINES;
  localparam logic [31:0] KILOWARE_CONFIG_L2 = {16'(L2_WAYS), 16'(L2_LINES)};
  localparam logic [31:0] KILOWARE_CONFIG_BACKEND = {16'(HBM_IF_Q_DEPTH), 16'(HBM_IF_SERVICE_CYCLES)};
  localparam logic [31:0] KILOWARE_CONFIG_FEATURES = {28'd0, HIER_POLICY_EN, PF_ADAPT_EN, TRUE_H2O_HH_EN, TRUE_H2O_RECENT_EN};
  localparam integer TRACE_STRIDE_BYTES = 16;
  localparam integer RESP_STRIDE_BYTES = 16;

  typedef enum logic [1:0] {
    FPGA_ST_IDLE      = 2'd0,
    FPGA_ST_ISSUE     = 2'd1,
    FPGA_ST_WAIT_RESP = 2'd2
  } fpga_state_t;

  logic                    axil_wr_en;
  logic [AXIL_ADDR_W-1:0]  axil_wr_addr;
  logic [DATA_W-1:0]       axil_wr_data;
  logic [(DATA_W/8)-1:0]   axil_wr_strb;
  logic                    axil_rd_en;
  logic [AXIL_ADDR_W-1:0]  axil_rd_addr;
  logic [DATA_W-1:0]       axil_rd_data;

  logic [31:0] trace_mem_w0 [0:TRACE_DEPTH-1];
  logic [31:0] trace_mem_w1 [0:TRACE_DEPTH-1];
  logic [31:0] trace_mem_w2 [0:TRACE_DEPTH-1];
  logic [31:0] resp_mem_w0 [0:RESP_DEPTH-1];
  logic [31:0] resp_mem_w1 [0:RESP_DEPTH-1];
  logic [31:0] resp_mem_w2 [0:RESP_DEPTH-1];
  logic [31:0] resp_mem_w3 [0:RESP_DEPTH-1];

  logic [31:0] trace_count_reg;
  logic [31:0] resp_count_reg;
  logic [31:0] cmd_reg_w0;
  logic [31:0] cmd_reg_w1;
  logic [31:0] cmd_reg_w2;
  logic [31:0] last_resp_meta_reg;
  logic [31:0] last_resp_rdata_reg;
  logic [31:0] error_code_reg;
  logic        done_sticky;
  logic        error_sticky;
  fpga_state_t fpga_state;
  logic        trace_mode_active;
  logic [31:0] trace_index_reg;
  logic [31:0] active_cmd_w0;
  logic [31:0] active_cmd_w1;
  logic [31:0] active_cmd_w2;
  logic [15:0] active_latency_ctr;

  logic                  core_trace_valid;
  logic                  core_trace_ready;
  kcmu_op_t              core_trace_op;
  logic [ADDR_W-1:0]     core_trace_addr;
  logic [DATA_W-1:0]     core_trace_wdata;
  logic                  core_trace_meta_valid;
  logic [KCMU_SEQ_W-1:0] core_trace_seq_id;
  kcmu_phase_t           core_trace_phase;
  kcmu_kv_kind_t         core_trace_kv_kind;
  logic [2:0]            core_trace_layer;
  logic [1:0]            core_trace_head;
  logic [11:0]           core_trace_token;
  logic [2:0]            core_trace_prio;

  logic                  core_resp_valid;
  logic [DATA_W-1:0]     core_resp_rdata;
  logic                  core_resp_hit;
  logic                  core_resp_approx;

  logic                  mem_re;
  logic [ADDR_W-1:0]     mem_raddr;
  logic [DATA_W-1:0]     mem_rdata;
  logic                  mem_rvalid;
  logic                  mem_we;
  logic [ADDR_W-1:0]     mem_waddr;
  logic [DATA_W-1:0]     mem_wdata;

  logic [31:0] stat_map_overflow_cnt;
  logic [31:0] stat_map_repl_cnt;
  logic [31:0] stat_map_seq_reclaim_cnt;
  logic [31:0] stat_l2_comp_fill_cnt;
  logic [31:0] stat_l2_comp_readback_cnt;
  logic [31:0] stat_l2_comp_spill_cnt;
  logic [31:0] stat_l2_dirty_wb_req_cnt;
  logic [31:0] stat_hbmif_burst_merge_cnt;
  logic [31:0] stat_hbmif_wr_drain_cycle_cnt;
  logic [31:0] stat_demand_req_cnt;
  logic [31:0] stat_demand_miss_cnt;
  logic [15:0] stat_miss_rate_permille;
  logic [31:0] stat_l2_demand_hit_cnt;
  logic [31:0] stat_l2_demand_miss_cnt;
  logic [31:0] stat_prefetch_accept_cnt;
  logic [31:0] stat_prefetch_fill_cnt;
  logic [31:0] stat_prefetch_useful_cnt;
  logic [31:0] stat_backend_stall_cycle_cnt;
  logic [31:0] stat_backend_queue_full_cycle_cnt;
  logic [31:0] ip_read_req_cnt;
  logic [31:0] ip_write_req_cnt;
  logic [31:0] ip_read_latency_cycle_sum;
  logic [31:0] ip_write_latency_cycle_sum;
  logic [31:0] ip_miss_penalty_cycle_sum;
  logic [31:0] ip_policy_decision_cycle_cnt;
  logic [31:0] base_demand_req_cnt;
  logic [31:0] base_demand_miss_cnt;
  logic [31:0] base_l2_demand_hit_cnt;
  logic [31:0] base_l2_demand_miss_cnt;
  logic [31:0] base_prefetch_accept_cnt;
  logic [31:0] base_prefetch_fill_cnt;
  logic [31:0] base_prefetch_useful_cnt;
  logic [31:0] base_backend_stall_cycle_cnt;
  logic [31:0] base_backend_queue_full_cycle_cnt;
  logic [31:0] base_read_req_cnt;
  logic [31:0] base_write_req_cnt;
  logic [31:0] base_read_latency_cycle_sum;
  logic [31:0] base_write_latency_cycle_sum;
  logic [31:0] base_miss_penalty_cycle_sum;
  logic [31:0] base_policy_decision_cycle_cnt;
  logic        snap_valid;
  logic        snap_overflow_seen;
  logic [31:0] snap_seq;
  logic [31:0] snap_demand_req_cnt;
  logic [31:0] snap_l1_hit_cnt;
  logic [31:0] snap_l1_miss_cnt;
  logic [31:0] snap_l2_hit_cnt;
  logic [31:0] snap_l2_miss_cnt;
  logic [31:0] snap_read_req_cnt;
  logic [31:0] snap_write_req_cnt;
  logic [31:0] snap_read_latency_cycle_sum;
  logic [31:0] snap_write_latency_cycle_sum;
  logic [31:0] snap_miss_penalty_cycle_sum;
  logic [31:0] snap_policy_decision_cycle_cnt;
  logic [31:0] snap_prefetch_accept_cnt;
  logic [31:0] snap_prefetch_fill_cnt;
  logic [31:0] snap_prefetch_useful_cnt;
  logic [31:0] snap_prefetch_pollute_cnt;
  logic [31:0] snap_backend_stall_cycle_cnt;
  logic [31:0] snap_backend_queue_full_cycle_cnt;

  logic [31:0] status_word;
  integer      idx_calc;
  integer      word_sel_calc;

  function automatic logic [31:0] apply_wstrb(
    input logic [31:0] curr,
    input logic [31:0] wr_data,
    input logic [3:0]  wr_strb
  );
    logic [31:0] merged;
    integer bi;
    begin
      merged = curr;
      for (bi = 0; bi < 4; bi = bi + 1) begin
        if (wr_strb[bi]) begin
          merged[bi*8 +: 8] = wr_data[bi*8 +: 8];
        end
      end
      apply_wstrb = merged;
    end
  endfunction

  function automatic logic [31:0] counter_delta(
    input logic [31:0] curr,
    input logic [31:0] base
  );
    begin
      counter_delta = curr - base;
    end
  endfunction

  function automatic logic [31:0] sat_sub32(
    input logic [31:0] a,
    input logic [31:0] b
  );
    begin
      sat_sub32 = (a >= b) ? (a - b) : 32'd0;
    end
  endfunction

  function automatic logic is_trace_addr(input logic [AXIL_ADDR_W-1:0] addr);
    begin
      is_trace_addr = (addr >= TRACE_BASE) && (addr < (TRACE_BASE + AXIL_ADDR_W'(TRACE_DEPTH * TRACE_STRIDE_BYTES)));
    end
  endfunction

  function automatic logic is_resp_addr(input logic [AXIL_ADDR_W-1:0] addr);
    begin
      is_resp_addr = (addr >= RESP_BASE) && (addr < (RESP_BASE + AXIL_ADDR_W'(RESP_DEPTH * RESP_STRIDE_BYTES)));
    end
  endfunction

  function automatic logic [31:0] trace_entry_word(
    input logic [AXIL_ADDR_W-1:0] addr
  );
    integer idx;
    integer word_sel;
    begin
      trace_entry_word = 32'd0;
      idx = (addr - TRACE_BASE) / TRACE_STRIDE_BYTES;
      word_sel = ((addr - TRACE_BASE) >> 2) & 32'h3;
      if ((idx >= 0) && (idx < TRACE_DEPTH)) begin
        case (word_sel)
          0: trace_entry_word = trace_mem_w0[idx];
          1: trace_entry_word = trace_mem_w1[idx];
          2: trace_entry_word = trace_mem_w2[idx];
          default: trace_entry_word = 32'd0;
        endcase
      end
    end
  endfunction

  function automatic logic [31:0] resp_entry_word(
    input logic [AXIL_ADDR_W-1:0] addr
  );
    integer idx;
    integer word_sel;
    begin
      resp_entry_word = 32'd0;
      idx = (addr - RESP_BASE) / RESP_STRIDE_BYTES;
      word_sel = ((addr - RESP_BASE) >> 2) & 32'h3;
      if ((idx >= 0) && (idx < RESP_DEPTH)) begin
        case (word_sel)
          0: resp_entry_word = resp_mem_w0[idx];
          1: resp_entry_word = resp_mem_w1[idx];
          2: resp_entry_word = resp_mem_w2[idx];
          3: resp_entry_word = resp_mem_w3[idx];
          default: resp_entry_word = 32'd0;
        endcase
      end
    end
  endfunction

  assign core_trace_valid      = (fpga_state == FPGA_ST_ISSUE);
  assign core_trace_op         = kcmu_op_t'(active_cmd_w0[1:0]);
  assign core_trace_meta_valid = active_cmd_w0[2];
  assign core_trace_phase      = kcmu_phase_t'(active_cmd_w0[3]);
  assign core_trace_kv_kind    = kcmu_kv_kind_t'(active_cmd_w0[4]);
  assign core_trace_layer      = active_cmd_w0[7:5];
  assign core_trace_head       = active_cmd_w0[9:8];
  assign core_trace_prio       = active_cmd_w0[12:10];
  assign core_trace_seq_id     = active_cmd_w0[20:13];
  assign core_trace_addr       = active_cmd_w1[ADDR_W-1:0];
  assign core_trace_token      = active_cmd_w1[27:16];
  assign core_trace_wdata      = active_cmd_w2;

  assign status_word = {
    27'd0,
    last_resp_meta_reg[0],
    trace_mode_active,
    error_sticky,
    done_sticky,
    (fpga_state != FPGA_ST_IDLE)
  };

  always_comb begin
    axil_rd_data = 32'd0;
    unique case (axil_rd_addr)
      REG_STATUS:        axil_rd_data = status_word;
      REG_TRACE_COUNT:   axil_rd_data = trace_count_reg;
      REG_RESP_COUNT:    axil_rd_data = resp_count_reg;
      REG_LAST_META:     axil_rd_data = last_resp_meta_reg;
      REG_LAST_RDATA:    axil_rd_data = last_resp_rdata_reg;
      REG_ERROR_CODE:    axil_rd_data = error_code_reg;
      REG_CONFIG_ID:     axil_rd_data = KILOWARE_CONFIG_ID;
      REG_CMD_W0:        axil_rd_data = cmd_reg_w0;
      REG_CMD_W1:        axil_rd_data = cmd_reg_w1;
      REG_CMD_W2:        axil_rd_data = cmd_reg_w2;
      REG_CONFIG_L1:     axil_rd_data = KILOWARE_CONFIG_L1;
      REG_CONFIG_L2:     axil_rd_data = KILOWARE_CONFIG_L2;
      REG_CONFIG_BACKEND: axil_rd_data = KILOWARE_CONFIG_BACKEND;
      REG_CONFIG_FEATURE: axil_rd_data = KILOWARE_CONFIG_FEATURES;
      REG_STAT_KV_OVF:   axil_rd_data = stat_map_overflow_cnt;
      REG_STAT_KV_REPL:  axil_rd_data = stat_map_repl_cnt;
      REG_STAT_KV_SEQRC: axil_rd_data = stat_map_seq_reclaim_cnt;
      REG_STAT_L2_CPF:   axil_rd_data = stat_l2_comp_fill_cnt;
      REG_STAT_L2_CRB:   axil_rd_data = stat_l2_comp_readback_cnt;
      REG_STAT_L2_CSP:   axil_rd_data = stat_l2_comp_spill_cnt;
      REG_STAT_L2_WBENQ: axil_rd_data = stat_l2_dirty_wb_req_cnt;
      REG_STAT_HBM_BM:   axil_rd_data = stat_hbmif_burst_merge_cnt;
      REG_STAT_HBM_WD:   axil_rd_data = stat_hbmif_wr_drain_cycle_cnt;
      REG_PERF_DEMAND_REQ: axil_rd_data = counter_delta(stat_demand_req_cnt, base_demand_req_cnt);
      REG_PERF_L1_HIT: begin
        axil_rd_data = sat_sub32(
          counter_delta(stat_demand_req_cnt, base_demand_req_cnt),
          counter_delta(stat_demand_miss_cnt, base_demand_miss_cnt)
        );
      end
      REG_PERF_L1_MISS: axil_rd_data = counter_delta(stat_demand_miss_cnt, base_demand_miss_cnt);
      REG_PERF_L2_HIT: axil_rd_data = counter_delta(stat_l2_demand_hit_cnt, base_l2_demand_hit_cnt);
      REG_PERF_L2_MISS: axil_rd_data = counter_delta(stat_l2_demand_miss_cnt, base_l2_demand_miss_cnt);
      REG_PERF_MISS_RATE: axil_rd_data = {16'd0, stat_miss_rate_permille};
      REG_PERF_RD_REQ: axil_rd_data = counter_delta(ip_read_req_cnt, base_read_req_cnt);
      REG_PERF_WR_REQ: axil_rd_data = counter_delta(ip_write_req_cnt, base_write_req_cnt);
      REG_PERF_RD_LAT: axil_rd_data = counter_delta(ip_read_latency_cycle_sum, base_read_latency_cycle_sum);
      REG_PERF_WR_LAT: axil_rd_data = counter_delta(ip_write_latency_cycle_sum, base_write_latency_cycle_sum);
      REG_PERF_MISS_PEN: axil_rd_data = counter_delta(ip_miss_penalty_cycle_sum, base_miss_penalty_cycle_sum);
      REG_PERF_POLICY_CYC: axil_rd_data = counter_delta(ip_policy_decision_cycle_cnt, base_policy_decision_cycle_cnt);
      REG_PERF_PF_ACCEPT: axil_rd_data = counter_delta(stat_prefetch_accept_cnt, base_prefetch_accept_cnt);
      REG_PERF_PF_FILL: axil_rd_data = counter_delta(stat_prefetch_fill_cnt, base_prefetch_fill_cnt);
      REG_PERF_PF_USEFUL: axil_rd_data = counter_delta(stat_prefetch_useful_cnt, base_prefetch_useful_cnt);
      REG_PERF_PF_POLLUTE: begin
        axil_rd_data = sat_sub32(
          counter_delta(stat_prefetch_fill_cnt, base_prefetch_fill_cnt),
          counter_delta(stat_prefetch_useful_cnt, base_prefetch_useful_cnt)
        );
      end
      REG_PERF_BACK_STALL: axil_rd_data = counter_delta(stat_backend_stall_cycle_cnt, base_backend_stall_cycle_cnt);
      REG_PERF_BACK_QFULL: axil_rd_data = counter_delta(stat_backend_queue_full_cycle_cnt, base_backend_queue_full_cycle_cnt);
      REG_SNAP_STATUS: axil_rd_data = {30'd0, snap_overflow_seen, snap_valid};
      REG_SNAP_SEQ: axil_rd_data = snap_seq;
      REG_SNAP_FLAGS: axil_rd_data = {31'd0, snap_overflow_seen};
      REG_SNAP_DEMAND_REQ: axil_rd_data = snap_demand_req_cnt;
      REG_SNAP_L1_HIT: axil_rd_data = snap_l1_hit_cnt;
      REG_SNAP_L1_MISS: axil_rd_data = snap_l1_miss_cnt;
      REG_SNAP_L2_HIT: axil_rd_data = snap_l2_hit_cnt;
      REG_SNAP_L2_MISS: axil_rd_data = snap_l2_miss_cnt;
      REG_SNAP_RD_REQ: axil_rd_data = snap_read_req_cnt;
      REG_SNAP_WR_REQ: axil_rd_data = snap_write_req_cnt;
      REG_SNAP_RD_LAT: axil_rd_data = snap_read_latency_cycle_sum;
      REG_SNAP_WR_LAT: axil_rd_data = snap_write_latency_cycle_sum;
      REG_SNAP_MISS_PEN: axil_rd_data = snap_miss_penalty_cycle_sum;
      REG_SNAP_POLICY_CYC: axil_rd_data = snap_policy_decision_cycle_cnt;
      REG_SNAP_PF_ACCEPT: axil_rd_data = snap_prefetch_accept_cnt;
      REG_SNAP_PF_FILL: axil_rd_data = snap_prefetch_fill_cnt;
      REG_SNAP_PF_USEFUL: axil_rd_data = snap_prefetch_useful_cnt;
      REG_SNAP_PF_POLLUTE: axil_rd_data = snap_prefetch_pollute_cnt;
      REG_SNAP_BACK_STALL: axil_rd_data = snap_backend_stall_cycle_cnt;
      REG_SNAP_BACK_QFULL: axil_rd_data = snap_backend_queue_full_cycle_cnt;
      default: begin
        if (is_trace_addr(axil_rd_addr)) begin
          axil_rd_data = trace_entry_word(axil_rd_addr);
        end else if (is_resp_addr(axil_rd_addr)) begin
          axil_rd_data = resp_entry_word(axil_rd_addr);
        end
      end
    endcase
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      trace_count_reg   <= 32'd0;
      resp_count_reg    <= 32'd0;
      cmd_reg_w0        <= 32'd0;
      cmd_reg_w1        <= 32'd0;
      cmd_reg_w2        <= 32'd0;
      last_resp_meta_reg <= 32'd0;
      last_resp_rdata_reg <= 32'd0;
      error_code_reg    <= ERR_NONE;
      done_sticky       <= 1'b0;
      error_sticky      <= 1'b0;
      fpga_state        <= FPGA_ST_IDLE;
      trace_mode_active <= 1'b0;
      trace_index_reg   <= 32'd0;
      active_cmd_w0     <= 32'd0;
      active_cmd_w1     <= 32'd0;
      active_cmd_w2     <= 32'd0;
      active_latency_ctr <= 16'd0;
      ip_read_req_cnt <= 32'd0;
      ip_write_req_cnt <= 32'd0;
      ip_read_latency_cycle_sum <= 32'd0;
      ip_write_latency_cycle_sum <= 32'd0;
      ip_miss_penalty_cycle_sum <= 32'd0;
      ip_policy_decision_cycle_cnt <= 32'd0;
      base_demand_req_cnt <= 32'd0;
      base_demand_miss_cnt <= 32'd0;
      base_l2_demand_hit_cnt <= 32'd0;
      base_l2_demand_miss_cnt <= 32'd0;
      base_prefetch_accept_cnt <= 32'd0;
      base_prefetch_fill_cnt <= 32'd0;
      base_prefetch_useful_cnt <= 32'd0;
      base_backend_stall_cycle_cnt <= 32'd0;
      base_backend_queue_full_cycle_cnt <= 32'd0;
      base_read_req_cnt <= 32'd0;
      base_write_req_cnt <= 32'd0;
      base_read_latency_cycle_sum <= 32'd0;
      base_write_latency_cycle_sum <= 32'd0;
      base_miss_penalty_cycle_sum <= 32'd0;
      base_policy_decision_cycle_cnt <= 32'd0;
      snap_valid <= 1'b0;
      snap_overflow_seen <= 1'b0;
      snap_seq <= 32'd0;
      snap_demand_req_cnt <= 32'd0;
      snap_l1_hit_cnt <= 32'd0;
      snap_l1_miss_cnt <= 32'd0;
      snap_l2_hit_cnt <= 32'd0;
      snap_l2_miss_cnt <= 32'd0;
      snap_read_req_cnt <= 32'd0;
      snap_write_req_cnt <= 32'd0;
      snap_read_latency_cycle_sum <= 32'd0;
      snap_write_latency_cycle_sum <= 32'd0;
      snap_miss_penalty_cycle_sum <= 32'd0;
      snap_policy_decision_cycle_cnt <= 32'd0;
      snap_prefetch_accept_cnt <= 32'd0;
      snap_prefetch_fill_cnt <= 32'd0;
      snap_prefetch_useful_cnt <= 32'd0;
      snap_prefetch_pollute_cnt <= 32'd0;
      snap_backend_stall_cycle_cnt <= 32'd0;
      snap_backend_queue_full_cycle_cnt <= 32'd0;
    end else begin
      if (axil_wr_en) begin
        unique case (axil_wr_addr)
          REG_CONTROL: begin
            if (axil_wr_data[2]) begin
              done_sticky <= 1'b0;
              error_sticky <= 1'b0;
              error_code_reg <= ERR_NONE;
              last_resp_meta_reg <= 32'd0;
              last_resp_rdata_reg <= 32'd0;
              resp_count_reg <= 32'd0;
              base_demand_req_cnt <= stat_demand_req_cnt;
              base_demand_miss_cnt <= stat_demand_miss_cnt;
              base_l2_demand_hit_cnt <= stat_l2_demand_hit_cnt;
              base_l2_demand_miss_cnt <= stat_l2_demand_miss_cnt;
              base_prefetch_accept_cnt <= stat_prefetch_accept_cnt;
              base_prefetch_fill_cnt <= stat_prefetch_fill_cnt;
              base_prefetch_useful_cnt <= stat_prefetch_useful_cnt;
              base_backend_stall_cycle_cnt <= stat_backend_stall_cycle_cnt;
              base_backend_queue_full_cycle_cnt <= stat_backend_queue_full_cycle_cnt;
              base_read_req_cnt <= ip_read_req_cnt;
              base_write_req_cnt <= ip_write_req_cnt;
              base_read_latency_cycle_sum <= ip_read_latency_cycle_sum;
              base_write_latency_cycle_sum <= ip_write_latency_cycle_sum;
              base_miss_penalty_cycle_sum <= ip_miss_penalty_cycle_sum;
              base_policy_decision_cycle_cnt <= ip_policy_decision_cycle_cnt;
              snap_valid <= 1'b0;
              snap_overflow_seen <= 1'b0;
            end

            if (axil_wr_data[3]) begin
              snap_valid <= 1'b1;
              snap_seq <= snap_seq + 32'd1;
              snap_demand_req_cnt <= counter_delta(stat_demand_req_cnt, base_demand_req_cnt);
              snap_l1_hit_cnt <= sat_sub32(
                counter_delta(stat_demand_req_cnt, base_demand_req_cnt),
                counter_delta(stat_demand_miss_cnt, base_demand_miss_cnt)
              );
              snap_l1_miss_cnt <= counter_delta(stat_demand_miss_cnt, base_demand_miss_cnt);
              snap_l2_hit_cnt <= counter_delta(stat_l2_demand_hit_cnt, base_l2_demand_hit_cnt);
              snap_l2_miss_cnt <= counter_delta(stat_l2_demand_miss_cnt, base_l2_demand_miss_cnt);
              snap_read_req_cnt <= counter_delta(ip_read_req_cnt, base_read_req_cnt);
              snap_write_req_cnt <= counter_delta(ip_write_req_cnt, base_write_req_cnt);
              snap_read_latency_cycle_sum <= counter_delta(ip_read_latency_cycle_sum, base_read_latency_cycle_sum);
              snap_write_latency_cycle_sum <= counter_delta(ip_write_latency_cycle_sum, base_write_latency_cycle_sum);
              snap_miss_penalty_cycle_sum <= counter_delta(ip_miss_penalty_cycle_sum, base_miss_penalty_cycle_sum);
              snap_policy_decision_cycle_cnt <= counter_delta(ip_policy_decision_cycle_cnt, base_policy_decision_cycle_cnt);
              snap_prefetch_accept_cnt <= counter_delta(stat_prefetch_accept_cnt, base_prefetch_accept_cnt);
              snap_prefetch_fill_cnt <= counter_delta(stat_prefetch_fill_cnt, base_prefetch_fill_cnt);
              snap_prefetch_useful_cnt <= counter_delta(stat_prefetch_useful_cnt, base_prefetch_useful_cnt);
              snap_prefetch_pollute_cnt <= sat_sub32(
                counter_delta(stat_prefetch_fill_cnt, base_prefetch_fill_cnt),
                counter_delta(stat_prefetch_useful_cnt, base_prefetch_useful_cnt)
              );
              snap_backend_stall_cycle_cnt <= counter_delta(stat_backend_stall_cycle_cnt, base_backend_stall_cycle_cnt);
              snap_backend_queue_full_cycle_cnt <= counter_delta(stat_backend_queue_full_cycle_cnt, base_backend_queue_full_cycle_cnt);
              snap_overflow_seen <= snap_overflow_seen
                | (stat_demand_req_cnt < base_demand_req_cnt)
                | (stat_demand_miss_cnt < base_demand_miss_cnt)
                | (stat_l2_demand_hit_cnt < base_l2_demand_hit_cnt)
                | (stat_l2_demand_miss_cnt < base_l2_demand_miss_cnt)
                | (stat_prefetch_accept_cnt < base_prefetch_accept_cnt)
                | (stat_prefetch_fill_cnt < base_prefetch_fill_cnt)
                | (stat_prefetch_useful_cnt < base_prefetch_useful_cnt)
                | (stat_backend_stall_cycle_cnt < base_backend_stall_cycle_cnt)
                | (stat_backend_queue_full_cycle_cnt < base_backend_queue_full_cycle_cnt)
                | (ip_read_req_cnt < base_read_req_cnt)
                | (ip_write_req_cnt < base_write_req_cnt)
                | (ip_read_latency_cycle_sum < base_read_latency_cycle_sum)
                | (ip_write_latency_cycle_sum < base_write_latency_cycle_sum)
                | (ip_miss_penalty_cycle_sum < base_miss_penalty_cycle_sum)
                | (ip_policy_decision_cycle_cnt < base_policy_decision_cycle_cnt);
            end

            if (axil_wr_data[0]) begin
              if (fpga_state != FPGA_ST_IDLE) begin
                error_sticky <= 1'b1;
                error_code_reg <= ERR_BUSY;
              end else begin
                done_sticky <= 1'b0;
                error_sticky <= 1'b0;
                error_code_reg <= ERR_NONE;
                trace_mode_active <= 1'b0;
                active_cmd_w0 <= cmd_reg_w0;
                active_cmd_w1 <= cmd_reg_w1;
                active_cmd_w2 <= cmd_reg_w2;
                active_latency_ctr <= 16'd0;
                fpga_state <= FPGA_ST_ISSUE;
              end
            end

            if (axil_wr_data[1]) begin
              if (fpga_state != FPGA_ST_IDLE) begin
                error_sticky <= 1'b1;
                error_code_reg <= ERR_BUSY;
              end else if ((trace_count_reg > TRACE_DEPTH) || (trace_count_reg > RESP_DEPTH)) begin
                error_sticky <= 1'b1;
                error_code_reg <= ERR_TRACE_RANGE;
              end else if (trace_count_reg == 32'd0) begin
                done_sticky <= 1'b1;
                error_sticky <= 1'b0;
                error_code_reg <= ERR_NONE;
                resp_count_reg <= 32'd0;
                last_resp_meta_reg <= 32'd0;
                last_resp_rdata_reg <= 32'd0;
              end else begin
                done_sticky <= 1'b0;
                error_sticky <= 1'b0;
                error_code_reg <= ERR_NONE;
                trace_mode_active <= 1'b1;
                trace_index_reg <= 32'd0;
                resp_count_reg <= 32'd0;
                last_resp_meta_reg <= 32'd0;
                last_resp_rdata_reg <= 32'd0;
                active_cmd_w0 <= trace_mem_w0[0];
                active_cmd_w1 <= trace_mem_w1[0];
                active_cmd_w2 <= trace_mem_w2[0];
                active_latency_ctr <= 16'd0;
                fpga_state <= FPGA_ST_ISSUE;
              end
            end
          end
          REG_TRACE_COUNT: begin
            trace_count_reg <= apply_wstrb(trace_count_reg, axil_wr_data, axil_wr_strb);
          end
          REG_CMD_W0: begin
            cmd_reg_w0 <= apply_wstrb(cmd_reg_w0, axil_wr_data, axil_wr_strb);
          end
          REG_CMD_W1: begin
            cmd_reg_w1 <= apply_wstrb(cmd_reg_w1, axil_wr_data, axil_wr_strb);
          end
          REG_CMD_W2: begin
            cmd_reg_w2 <= apply_wstrb(cmd_reg_w2, axil_wr_data, axil_wr_strb);
          end
          default: begin
            if (is_trace_addr(axil_wr_addr)) begin
              idx_calc = (axil_wr_addr - TRACE_BASE) / TRACE_STRIDE_BYTES;
              word_sel_calc = ((axil_wr_addr - TRACE_BASE) >> 2) & 32'h3;
              if ((idx_calc >= 0) && (idx_calc < TRACE_DEPTH)) begin
                unique case (word_sel_calc)
                  0: trace_mem_w0[idx_calc] <= apply_wstrb(trace_mem_w0[idx_calc], axil_wr_data, axil_wr_strb);
                  1: trace_mem_w1[idx_calc] <= apply_wstrb(trace_mem_w1[idx_calc], axil_wr_data, axil_wr_strb);
                  2: trace_mem_w2[idx_calc] <= apply_wstrb(trace_mem_w2[idx_calc], axil_wr_data, axil_wr_strb);
                  default: begin end
                endcase
              end
            end
          end
        endcase
      end

      unique case (fpga_state)
        FPGA_ST_IDLE: begin
          active_latency_ctr <= 16'd0;
        end
        FPGA_ST_ISSUE: begin
          if (core_trace_ready) begin
            if (core_trace_op == KCMU_OP_RD) begin
              ip_read_req_cnt <= ip_read_req_cnt + 32'd1;
            end else if (core_trace_op == KCMU_OP_WR) begin
              ip_write_req_cnt <= ip_write_req_cnt + 32'd1;
            end
            ip_policy_decision_cycle_cnt <= ip_policy_decision_cycle_cnt + 32'd1;
            active_latency_ctr <= 16'd0;
            fpga_state <= FPGA_ST_WAIT_RESP;
          end
        end
        FPGA_ST_WAIT_RESP: begin
          if (core_resp_valid) begin
            if (core_trace_op == KCMU_OP_RD) begin
              ip_read_latency_cycle_sum <= ip_read_latency_cycle_sum + {16'd0, (active_latency_ctr + 16'd1)};
              if (!core_resp_hit) begin
                ip_miss_penalty_cycle_sum <= ip_miss_penalty_cycle_sum + {16'd0, (active_latency_ctr + 16'd1)};
              end
            end else if (core_trace_op == KCMU_OP_WR) begin
              ip_write_latency_cycle_sum <= ip_write_latency_cycle_sum + {16'd0, (active_latency_ctr + 16'd1)};
            end
            last_resp_meta_reg <= {13'd0, (active_latency_ctr + 16'd1), core_resp_approx, core_resp_hit, 1'b1};
            last_resp_rdata_reg <= core_resp_rdata;
            if (trace_mode_active && (resp_count_reg < RESP_DEPTH)) begin
              resp_mem_w0[resp_count_reg] <= {13'd0, (active_latency_ctr + 16'd1), core_resp_approx, core_resp_hit, 1'b1};
              resp_mem_w1[resp_count_reg] <= core_resp_rdata;
              resp_mem_w2[resp_count_reg] <= active_cmd_w0;
              resp_mem_w3[resp_count_reg] <= active_cmd_w1;
              resp_count_reg <= resp_count_reg + 32'd1;
            end

            if (trace_mode_active && ((trace_index_reg + 32'd1) < trace_count_reg)) begin
              trace_index_reg <= trace_index_reg + 32'd1;
              active_cmd_w0 <= trace_mem_w0[trace_index_reg + 32'd1];
              active_cmd_w1 <= trace_mem_w1[trace_index_reg + 32'd1];
              active_cmd_w2 <= trace_mem_w2[trace_index_reg + 32'd1];
              active_latency_ctr <= 16'd0;
              fpga_state <= FPGA_ST_ISSUE;
            end else begin
              trace_mode_active <= 1'b0;
              done_sticky <= 1'b1;
              fpga_state <= FPGA_ST_IDLE;
              active_latency_ctr <= 16'd0;
            end
          end else begin
            active_latency_ctr <= active_latency_ctr + 16'd1;
          end
        end
        default: begin
          fpga_state <= FPGA_ST_IDLE;
        end
      endcase
    end
  end

  kcmu_axilite_slave #(
    .ADDR_W(AXIL_ADDR_W),
    .DATA_W(DATA_W)
  ) u_axil (
    .clk(clk),
    .rst_n(rst_n),
    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awprot(s_axi_awprot),
    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready),
    .s_axi_bresp(s_axi_bresp),
    .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr),
    .s_axi_arprot(s_axi_arprot),
    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),
    .s_axi_rdata(s_axi_rdata),
    .s_axi_rresp(s_axi_rresp),
    .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rready(s_axi_rready),
    .reg_wr_en(axil_wr_en),
    .reg_wr_addr(axil_wr_addr),
    .reg_wr_data(axil_wr_data),
    .reg_wr_strb(axil_wr_strb),
    .reg_rd_en(axil_rd_en),
    .reg_rd_addr(axil_rd_addr),
    .reg_rd_data(axil_rd_data)
  );

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
    .TRUE_H2O_HH_SCORE_TH(TRUE_H2O_HH_SCORE_TH),
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
    .TRUE_H2O_RECENT_VALID_SERVICE_EN(TRUE_H2O_RECENT_VALID_SERVICE_EN),
    .TRUE_H2O_L2_REUSE_PROMOTE_EN(TRUE_H2O_L2_REUSE_PROMOTE_EN),
    .TRUE_H2O_RETENTION_SERVICE_DECOUPLE_EN(TRUE_H2O_RETENTION_SERVICE_DECOUPLE_EN),
    .TRUE_H2O_VALIDATED_OR_RECENT_RETENTION_EN(TRUE_H2O_VALIDATED_OR_RECENT_RETENTION_EN),
    .TRUE_H2O_L1_VALIDATED_OR_RECENT_RETENTION_EN(TRUE_H2O_L1_VALIDATED_OR_RECENT_RETENTION_EN),
    .TRUE_H2O_VICTIM_VALIDATED_OR_RECENT_PROTECT_EN(TRUE_H2O_VICTIM_VALIDATED_OR_RECENT_PROTECT_EN),
    .TRUE_H2O_STORAGE_QOS_DECOUPLE_EN(TRUE_H2O_STORAGE_QOS_DECOUPLE_EN),
    .PREFETCH_FORCE_DISABLE_EN(PREFETCH_FORCE_DISABLE_EN),
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
    .L2_WRITE_ALLOCATE(L2_WRITE_ALLOCATE),
    .L2_WRITE_THROUGH_EN(L2_WRITE_THROUGH_EN),
    .L2_BG_DIRTY_FLUSH_EN(L2_BG_DIRTY_FLUSH_EN),
    .L2_SERVICE_ISSUE_DEFER_DIRTY_FLUSH_EN(L2_SERVICE_ISSUE_DEFER_DIRTY_FLUSH_EN),
    .L2_SERVICE_ISSUE_CLEAN_VICTIM_RESCUE_EN(L2_SERVICE_ISSUE_CLEAN_VICTIM_RESCUE_EN),
    .L2_SERVICE_ISSUE_CLEAN_VICTIM_MARGIN(L2_SERVICE_ISSUE_CLEAN_VICTIM_MARGIN),
    .L2_SCHED_OWNERSHIP_QUERY_BIAS_EN(L2_SCHED_OWNERSHIP_QUERY_BIAS_EN),
    .L2_SCHED_OWNERSHIP_QUERY_STRONG_BIAS_EN(L2_SCHED_OWNERSHIP_QUERY_STRONG_BIAS_EN),
    .L2_SCHED_OWNERSHIP_QUERY_ADAPTIVE_BIAS_EN(L2_SCHED_OWNERSHIP_QUERY_ADAPTIVE_BIAS_EN),
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
    .prefetch_enable(1'b1),
    .trace_valid(core_trace_valid),
    .trace_ready(core_trace_ready),
    .trace_op(core_trace_op),
    .trace_addr(core_trace_addr),
    .trace_wdata(core_trace_wdata),
    .trace_meta_valid(core_trace_meta_valid),
    .trace_seq_id(core_trace_seq_id),
    .trace_phase(core_trace_phase),
    .trace_kv_kind(core_trace_kv_kind),
    .trace_layer(core_trace_layer),
    .trace_head(core_trace_head),
    .trace_token(core_trace_token),
    .trace_prio(core_trace_prio),
    .trace_desc_valid(1'b0),
    .trace_desc_op(KCMU_OP_NOP),
    .trace_desc_base_addr('0),
    .trace_desc_len(8'd0),
    .trace_desc_score('0),
    .trace_desc_seq_id('0),
    .trace_desc_phase(KCMU_PHASE_PREFILL),
    .trace_desc_kv_kind(KCMU_KV_KIND_K),
    .trace_desc_attn_valid(1'b0),
    .trace_desc_attn_score('0),
    .trace_desc_recent_rank('0),
    .trace_desc_token_block_id('0),
    .trace_desc_attn_epoch('0),
    .trace_desc_head_budget_class('0),
    .trace_desc_query_relevance('0),
    .trace_desc_compression_risk('0),
    .trace_desc_spill_cost('0),
    .trace_desc_service_criticality('0),
    .trace_desc_policy_select_s5(1'b0),
    .trace_desc_temporal_persist_class('0),
    .trace_desc_reuse_distance_class('0),
    .trace_desc_query_structure_class('0),
    .trace_desc_sched_urgency_hint('0),
    .trace_desc_kiloscore_extra_cvr_hint(1'b0),
    .trace_desc_sig_valid(1'b0),
    .trace_desc_query_sig(6'd0),
    .trace_desc_key_sig(6'd0),
    .trace_desc_prefix_class(2'd0),
    .trace_desc_router_class(2'd0),
    .trace_desc_wvalid(1'b0),
    .trace_desc_wdata('0),
    .resp_valid(core_resp_valid),
    .resp_ready(1'b1),
    .resp_rdata(core_resp_rdata),
    .resp_hit(core_resp_hit),
    .resp_approx(core_resp_approx),
    .mem_re(mem_re),
    .mem_raddr(mem_raddr),
    .mem_rdata(mem_rdata),
    .mem_rvalid(mem_rvalid),
    .mem_we(mem_we),
    .mem_waddr(mem_waddr),
    .mem_wdata(mem_wdata),
    .stat_map_overflow_cnt(stat_map_overflow_cnt),
    .stat_map_repl_cnt(stat_map_repl_cnt),
    .stat_map_seq_reclaim_cnt(stat_map_seq_reclaim_cnt),
    .stat_l2_comp_fill_cnt(stat_l2_comp_fill_cnt),
    .stat_l2_comp_readback_cnt(stat_l2_comp_readback_cnt),
    .stat_l2_comp_spill_cnt(stat_l2_comp_spill_cnt),
    .stat_l2_dirty_wb_req_cnt(stat_l2_dirty_wb_req_cnt),
    .stat_hbmif_burst_merge_cnt(stat_hbmif_burst_merge_cnt),
    .stat_hbmif_wr_drain_cycle_cnt(stat_hbmif_wr_drain_cycle_cnt),
    .stat_demand_req_cnt(stat_demand_req_cnt),
    .stat_demand_miss_cnt(stat_demand_miss_cnt),
    .stat_miss_rate_permille(stat_miss_rate_permille),
    .stat_l2_demand_hit_cnt(stat_l2_demand_hit_cnt),
    .stat_l2_demand_miss_cnt(stat_l2_demand_miss_cnt),
    .stat_prefetch_accept_cnt(stat_prefetch_accept_cnt),
    .stat_prefetch_fill_cnt(stat_prefetch_fill_cnt),
    .stat_prefetch_useful_cnt(stat_prefetch_useful_cnt),
    .stat_backend_stall_cycle_cnt(stat_backend_stall_cycle_cnt),
    .stat_backend_queue_full_cycle_cnt(stat_backend_queue_full_cycle_cnt)
  );

  kcmu_ext_mem #(
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W),
    .RD_LATENCY(MEM_RD_LATENCY)
  ) u_mem (
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

endmodule

