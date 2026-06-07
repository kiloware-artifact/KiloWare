`timescale 1ns/1ps
`ifdef KCMU_CFG_FPGA_KILOSCORE_HV_OPT5_GLOBAL_WINNER
`ifndef KCMU_CFG_FPGA_KILOSCORE_TINY_ASYM_STRUCT_RESCUE_V722
`define KCMU_CFG_FPGA_KILOSCORE_TINY_ASYM_STRUCT_RESCUE_V722
`endif
`endif
// ------------------------------------------------------------
// kcmu_execute.sv
// Command/prefetch FSM and data movement.
// ------------------------------------------------------------
module kcmu_execute #(
  parameter integer ADDR_W     = 8,
  parameter integer DATA_W     = 32,
  parameter integer LINES      = 4,
  parameter integer SCORE_W    = 8,
  parameter integer TIME_W     = 16,
  parameter integer K_RECENT   = 1,
  parameter bit     H2O_V2_EN  = 1'b1,
  parameter bit     UTILITY_SCORE_REPL_EN = 1'b0,
  parameter bit     QMATCH_RECENT_COLD_TIEBREAK_EN = 1'b0,
  parameter bit     QMATCH_L1_QUERY_SEED_EN = 1'b0,
  parameter bit     QMATCH_L1_KEEP_TIEBREAK_EN = 1'b0,
  parameter integer HBM_Q_W = 3,
  parameter integer MEM_RD_LATENCY = 2,
  parameter integer L2_RD_LATENCY = 1,
  parameter bit     HIER_POLICY_EN = 1'b1,
  parameter logic [2:0] L1_BYPASS_QOS_TH = 3'd0,
  parameter logic [2:0] L1_DEMAND_FILL_QOS_TH = 3'd3,
  parameter logic [2:0] L1_PREFETCH_FILL_QOS_TH = 3'd4,
  parameter logic [2:0] L1_MISS_BYPASS_QOS_TH = 3'd7,
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
  parameter integer LINE_IDX_W = (LINES <= 1) ? 1 : $clog2(LINES)
)(
  input  logic                      clk,
  input  logic                      rst_n,

  // cmd stream
  input  logic                      cmd_valid,
  output logic                      cmd_ready,
  input  kcmu_pkg::kcmu_op_t        cmd_op,
  input  logic [ADDR_W-1:0]         cmd_addr,
  input  logic [DATA_W-1:0]         cmd_wdata,
  input  logic [2:0]                cmd_qos,
  input  logic                      cmd_sem_hot,
  input  logic                      cmd_fill_allow,
  input  logic                      cmd_victim_protect,
  input  logic                      cmd_compress_allow,
  input  logic                      cmd_hh_protect,
  input  logic                      cmd_recent_keep,
  input  logic [1:0]                cmd_h2o_class,
  input  logic                      cmd_l1_hh_protect,
  input  logic [1:0]                cmd_l1_h2o_class,
  input  logic [SCORE_W-1:0]        cmd_utility_score,
  input  logic [SCORE_W-1:0]        cmd_query_relevance,
  input  logic [kcmu_pkg::KCMU_HEAD_BUDGET_W-1:0] cmd_head_budget_class,
  input  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] cmd_temporal_persist_class,
  input  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] cmd_reuse_distance_class,
  input  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] cmd_query_structure_class,
  input  logic                      cmd_marginal_active,
  input  logic                      cmd_service_issue_boost,
  input  logic                      cmd_sched_query_take,
  input  logic                      cmd_sched_temporal_take,
  input  logic                      cmd_sched_query_bias_take,
  input  logic                      cmd_kv_sibling_keep,
  input  logic                      cmd_block_last,
  input  logic                      cmd_group_target_valid,
  input  logic [ADDR_W-1:0]         cmd_group_target_addr,
  input  logic                      cmd_group_v251gf_force,
  input  logic                      cmd_kiloscore_extra_cvr_hint,
  input  logic [2:0]                cmd_kiloscore_qsig_bucket,

  // prefetch request from prefetcher
  input  logic                      pf_valid,
  output logic                      pf_ready,
  input  logic [ADDR_W-1:0]         pf_addr,
  input  logic [2:0]                pf_qos,
  input  logic                      pf_sem_hot,
  input  logic                      pf_fill_allow,
  input  logic                      pf_victim_protect,
  input  logic                      pf_compress_allow,
  input  logic                      pf_hh_protect,
  input  logic                      pf_recent_keep,
  input  logic [1:0]                pf_h2o_class,
  input  logic [SCORE_W-1:0]        pf_utility_score,
  input  logic [SCORE_W-1:0]        pf_query_relevance,
  output logic                      pf_fill_pulse,
  output logic                      pf_useful_pulse,

  // response
  output logic                      resp_valid,
  input  logic                      resp_ready,
  output logic [DATA_W-1:0]         resp_rdata,
  output logic                      resp_hit,
  output logic                      resp_approx,

  // SRAM interface (to rw_ctrl)
  output logic                      sram_re,
  output logic [LINE_IDX_W-1:0]     sram_raddr,
  input  logic [DATA_W-1:0]         sram_rdata,

  output logic                      sram_we,
  output logic [LINE_IDX_W-1:0]     sram_waddr,
  output logic [DATA_W-1:0]         sram_wdata,

  // external memory interface
  output logic                      mem_re,
  output logic [ADDR_W-1:0]         mem_raddr,
  output logic                      mem_req_prefetch,
  output logic [2:0]                mem_req_qos,
  output logic                      mem_req_sem_hot,
  output logic                      mem_req_fill_allow,
  output logic                      mem_req_victim_protect,
  output logic                      mem_req_compress_allow,
  output logic                      mem_req_hh_protect,
  output logic                      mem_req_recent_keep,
  output logic [1:0]                mem_req_h2o_class,
  output logic [SCORE_W-1:0]        mem_req_utility_score,
  output logic [SCORE_W-1:0]        mem_req_query_relevance,
  output logic [kcmu_pkg::KCMU_HEAD_BUDGET_W-1:0] mem_req_head_budget_class,
  output logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] mem_req_temporal_persist_class,
  output logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] mem_req_reuse_distance_class,
  output logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] mem_req_query_structure_class,
  output logic                      mem_req_marginal_active,
  output logic                      mem_req_service_issue_boost,
  output logic                      mem_req_sched_query_take,
  output logic                      mem_req_sched_temporal_take,
  output logic                      mem_req_sched_query_bias_take,
  output logic                      mem_req_block_last,
  output logic                      mem_req_group_target_valid,
  output logic [ADDR_W-1:0]         mem_req_group_target_addr,
  output logic                      mem_req_group_v251gf_force,
  output logic                      mem_req_kiloscore_extra_cvr_hint,
  output logic [2:0]                mem_req_kiloscore_qsig_bucket,
  input  logic [DATA_W-1:0]         mem_rdata,
  input  logic                      mem_rvalid,
  input  logic                      mem_l2_hit,
  input  logic [2:0]                mem_rsource,
  input  logic                      mem_req_accepted,
  input  logic                      mem_r_lossy,
  input  logic [HBM_Q_W-1:0]        hbm_q_level,
  input  logic                      hbm_congested,
  input  logic                      hbm_prefetch_block,

  output logic                      mem_we,
  output logic [ADDR_W-1:0]         mem_waddr,
  output logic [DATA_W-1:0]         mem_wdata,
  output logic [31:0]               stat_demand_req_cnt,
  output logic [31:0]               stat_demand_miss_cnt,
  output logic [15:0]               stat_miss_rate_permille
);
  import kcmu_pkg::*;

  localparam integer MEM_RD_LAT = (MEM_RD_LATENCY < 1) ? 1 : MEM_RD_LATENCY;
  localparam integer L2_RD_LAT  = (L2_RD_LATENCY < 1) ? 1 : L2_RD_LATENCY;
  localparam integer MAX_MEM_LAT = (MEM_RD_LAT > L2_RD_LAT) ? MEM_RD_LAT : L2_RD_LAT;
  localparam integer HBM_CONGEST_COLD_EXTRA_LAT_SAFE = (HBM_CONGEST_COLD_EXTRA_LAT < 0) ? 0 : HBM_CONGEST_COLD_EXTRA_LAT;
  localparam integer HBM_CONGEST_HOT_EXTRA_LAT_SAFE = (HBM_CONGEST_HOT_EXTRA_LAT < 0) ? 0 : HBM_CONGEST_HOT_EXTRA_LAT;
  localparam integer HBM_CONGEST_PREFETCH_EXTRA_LAT_SAFE = (HBM_CONGEST_PREFETCH_EXTRA_LAT < 0) ? 0 : HBM_CONGEST_PREFETCH_EXTRA_LAT;
  localparam integer MAX_CONGEST_EXTRA_LAT_A = (HBM_CONGEST_COLD_EXTRA_LAT_SAFE > HBM_CONGEST_HOT_EXTRA_LAT_SAFE) ? HBM_CONGEST_COLD_EXTRA_LAT_SAFE : HBM_CONGEST_HOT_EXTRA_LAT_SAFE;
  localparam integer MAX_CONGEST_EXTRA_LAT = (MAX_CONGEST_EXTRA_LAT_A > HBM_CONGEST_PREFETCH_EXTRA_LAT_SAFE) ? MAX_CONGEST_EXTRA_LAT_A : HBM_CONGEST_PREFETCH_EXTRA_LAT_SAFE;
  localparam integer MAX_WAIT_CYCLES = MAX_MEM_LAT + MAX_CONGEST_EXTRA_LAT;
  localparam integer MEM_WAIT_W = (MAX_WAIT_CYCLES <= 1) ? 1 : $clog2(MAX_WAIT_CYCLES);
  localparam integer EXEC_CONGEST_Q_LEVEL_TH_SAFE = (EXEC_CONGEST_Q_LEVEL_TH < 0) ? 0 : EXEC_CONGEST_Q_LEVEL_TH;
  localparam logic [2:0] PREF_ADMIT_QOS_TH = 3'd2;

  localparam logic [2:0] ST_IDLE    = 3'd0;
  localparam logic [2:0] ST_MAIN    = 3'd1;
  localparam logic [2:0] ST_RESP    = 3'd2;
  localparam logic [2:0] ST_PREF    = 3'd3;
  localparam logic [2:0] ST_MEMWAIT = 3'd4;
  localparam logic [2:0] L1_PROV_UNKNOWN = 3'd0;
  localparam logic [2:0] L1_PROV_WRITE   = 3'd1;
  localparam logic [2:0] L1_PROV_BACKEND = 3'd2;
  localparam logic [2:0] L1_PROV_L2      = 3'd3;
  localparam logic [2:0] L1_PROV_CVR     = 3'd4;
  localparam logic [2:0] L1_PROV_GF      = 3'd5;
  localparam logic [2:0] L1_PROV_PREF    = 3'd6;
  localparam integer PF_TRACK_DEPTH = 8;
  localparam integer PF_TRACK_IDX_W = (PF_TRACK_DEPTH <= 1) ? 1 : $clog2(PF_TRACK_DEPTH);
  localparam bit KCMU_EXEC_STMAIN_L2_FAST_PATH_EN = 1'b1;

  logic [2:0] state;

  // current op
  kcmu_op_t cur_op;
  logic [ADDR_W-1:0] cur_addr;
  logic [DATA_W-1:0] cur_wdata;
  logic [2:0]        cur_qos;
  logic              cur_sem_hot;
  logic              cur_fill_allow;
  logic              cur_victim_protect;
  logic              cur_compress_allow;
  logic              cur_hh_protect;
  logic              cur_l1_hh_protect;
  logic              cur_recent_keep;
  logic [1:0]        cur_h2o_class;
  logic [1:0]        cur_l1_h2o_class;
  logic [SCORE_W-1:0] cur_utility_score;
  logic [SCORE_W-1:0] cur_query_relevance;
  logic [kcmu_pkg::KCMU_HEAD_BUDGET_W-1:0] cur_head_budget_class;
  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] cur_temporal_persist_class;
  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] cur_reuse_distance_class;
  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] cur_query_structure_class;
  logic              cur_marginal_active;
  logic              cur_service_issue_boost;
  logic              cur_sched_query_take;
  logic              cur_sched_temporal_take;
  logic              cur_sched_query_bias_take;
  logic              cur_kv_sibling_keep;
  logic              cur_block_last;
  logic              cur_group_target_valid;
  logic [ADDR_W-1:0] cur_group_target_addr;
  logic              cur_group_v251gf_force;
  logic              cur_kiloscore_extra_cvr_hint;
  logic [2:0]        cur_kiloscore_qsig_bucket;
  logic [ADDR_W-1:0] meta_lookup_addr;

  // metadata query
  logic hit;
  logic hit_from_prefetch;
  logic hit_is_lossy;
  logic [LINE_IDX_W-1:0] hit_idx;
  logic [LINE_IDX_W-1:0] victim_sel;
  logic victim_sel_is_invalid;
  logic [ADDR_W-1:0] victim_addr;
  logic victim_is_lossy;

  wire is_read  = (cur_op == KCMU_OP_RD);
  wire is_write = (cur_op == KCMU_OP_WR);

  // Metadata update is intentionally delayed by one cycle to cut the
  // valid->policy->metadata writeback timing loop.
  logic                  upd_en;
  logic                  upd_is_hit;
  logic                  upd_is_prefetch;
  logic                  upd_is_read;
  logic [2:0]            upd_qos;
  logic                  upd_hh_protect;
  logic                  upd_l1_hh_protect;
  logic                  upd_recent_keep;
  logic [1:0]            upd_h2o_class;
  logic [1:0]            upd_l1_h2o_class;
  logic [SCORE_W-1:0]    upd_utility_score;
  logic [SCORE_W-1:0]    upd_query_relevance;
  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] upd_temporal_persist_class;
  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] upd_reuse_distance_class;
  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] upd_query_structure_class;
  logic                  upd_kv_sibling_keep;
  logic [ADDR_W-1:0]     upd_addr;
  logic [LINE_IDX_W-1:0] upd_hit_idx;
  logic [LINE_IDX_W-1:0] upd_victim_idx;
  logic                  upd_fill_lossy;

  // One-cycle staged SRAM write request to shorten victim->WADR timing.
  logic                  sram_we_q;
  logic [LINE_IDX_W-1:0] sram_waddr_q;
  logic [DATA_W-1:0]     sram_wdata_q;

  // Pending external-memory read context.
  logic                  mem_pend_prefetch;
  logic [ADDR_W-1:0]     mem_pend_addr;
  logic [LINE_IDX_W-1:0] mem_pend_victim_idx;
  logic [DATA_W-1:0]     mem_pend_rdata;
  logic [2:0]            mem_pend_rsource;
  logic [2:0]            mem_pend_qos;
  logic                  mem_pend_lossy;
  logic                  mem_pend_rsp_valid;
  logic                  mem_pend_fill_l1;
`ifdef KCMU_CFG_HASP_N04_L1_RECALL_V268
  logic                  mem_pend_victim_invalid;
  logic [ADDR_W-1:0]     mem_pend_victim_addr;
  logic                  mem_pend_victim_lossy;
  logic                  mem_pend_recall_eligible;
`endif
  logic                  mem_pend_sem_hot;
  logic                  mem_pend_hh_protect;
  logic                  mem_pend_l1_hh_protect;
  logic                  mem_pend_recent_keep;
  logic [1:0]            mem_pend_h2o_class;
  logic [1:0]            mem_pend_l1_h2o_class;
  logic [SCORE_W-1:0]    mem_pend_utility_score;
  logic [SCORE_W-1:0]    mem_pend_query_relevance;
  logic [kcmu_pkg::KCMU_HEAD_BUDGET_W-1:0] mem_pend_head_budget_class;
  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] mem_pend_temporal_persist_class;
  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] mem_pend_reuse_distance_class;
  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] mem_pend_query_structure_class;
  logic                  mem_pend_kv_sibling_keep;
  logic [2:0]            mem_pend_kiloscore_qsig_bucket;
  logic                  mem_wait_ignore_first;
  logic [MEM_WAIT_W-1:0] mem_wait_ctr;
  logic                  prefetch_admit_cur;
  logic                  prefetch_issue_allow_cur;
  logic [2:0]            cur_eff_qos;
  logic                  demand_base_fill_allow_cur;
  logic                  demand_fill_allow_cur;
  logic                  native_demand_fill_allow_cur;
  logic                  demand_reuse_admission_cur;
  logic                  demand_lowroi_bypass_cur;
  logic                  prefetch_fill_allow_cur;
  logic                  exec_congested;
  logic [PF_TRACK_DEPTH-1:0] pf_track_valid;
  logic [ADDR_W-1:0]         pf_track_addr [0:PF_TRACK_DEPTH-1];
  logic                      pf_track_hit_cur;
  logic [PF_TRACK_IDX_W-1:0] pf_track_hit_idx;
  logic                      pf_track_has_free;
  logic [PF_TRACK_IDX_W-1:0] pf_track_free_idx;
  logic                      demand_pf_useful_cur;
`ifdef KCMU_CFG_HASP_N04_L1_RECALL_V268
  logic                      l1_recall_valid;
  logic [ADDR_W-1:0]         l1_recall_addr;
  logic [DATA_W-1:0]         l1_recall_data;
  logic                      l1_recall_lossy;
  logic                      l1_recall_hit_cur;
  logic                      l1_recall_eligible_cur;
  logic                      demand_effective_hit_cur;
`endif
  logic [31:0]               stat_demand_req_cnt_next;
  logic [31:0]               stat_demand_miss_cnt_next;
  integer                    pi;

  function automatic logic [15:0] calc_miss_rate_permille(
    input logic [31:0] miss_cnt,
    input logic [31:0] req_cnt
  );
    logic [47:0] scaled_miss;
    begin
      if (req_cnt == 32'd0) begin
        calc_miss_rate_permille = 16'd0;
      end else begin
        scaled_miss = miss_cnt * 48'd1000;
        calc_miss_rate_permille = scaled_miss / req_cnt;
      end
    end
  endfunction

  // Visible counters for debug / TB introspection.
  // Excluded from synthesis to avoid unused-register warnings.
`ifndef SYNTHESIS
  logic [31:0] stat_demand_access_cnt;
  logic [31:0] stat_demand_hit_cnt;
  logic [31:0] stat_l1_hit_cnt;
  logic [31:0] stat_l1_demand_fill_cnt;
  logic [31:0] stat_l1_demand_bypass_cnt;
  logic [31:0] stat_l1_prefetch_fill_cnt;
  logic [31:0] stat_l1_prefetch_bypass_cnt;
  logic [31:0] stat_l2_demand_fill_cnt;
  logic [31:0] stat_l2_prefetch_fill_cnt;
  logic [31:0] stat_l1_recall_hit_cnt;
  logic [31:0] stat_l1_recall_capture_cnt;
  logic [31:0] stat_l1_recall_invalidate_cnt;
  logic [31:0] stat_prefetch_req_cnt;
  logic [31:0] stat_prefetch_fill_cnt;
  logic [31:0] stat_prefetch_useful_cnt;
  logic [31:0] stat_evict_cnt;
  logic [31:0] stat_mem_wait_cycle_cnt;
  logic [31:0] stat_exec_busy_cycle_cnt;
  logic [31:0] stat_l2_lossy_resp_cnt;
  logic [2:0]  l1_line_prov [0:LINES-1];
  logic [31:0] stat_l1_hit_prov_unknown_cnt;
  logic [31:0] stat_l1_hit_prov_write_cnt;
  logic [31:0] stat_l1_hit_prov_backend_cnt;
  logic [31:0] stat_l1_hit_prov_l2_cnt;
  logic [31:0] stat_l1_hit_prov_cvr_cnt;
  logic [31:0] stat_l1_hit_prov_gf_cnt;
  logic [31:0] stat_l1_hit_prov_prefetch_cnt;
  logic [31:0] stat_l1_fill_prov_unknown_cnt;
  logic [31:0] stat_l1_fill_prov_write_cnt;
  logic [31:0] stat_l1_fill_prov_backend_cnt;
  logic [31:0] stat_l1_fill_prov_l2_cnt;
  logic [31:0] stat_l1_fill_prov_cvr_cnt;
  logic [31:0] stat_l1_fill_prov_gf_cnt;
  logic [31:0] stat_l1_fill_prov_prefetch_cnt;

  function automatic logic [2:0] l1_prov_from_resp_source(input logic [2:0] source);
    begin
      case (source)
        3'd1: l1_prov_from_resp_source = L1_PROV_L2;
        3'd2: l1_prov_from_resp_source = L1_PROV_GF;
        3'd3: l1_prov_from_resp_source = L1_PROV_CVR;
        3'd4: l1_prov_from_resp_source = L1_PROV_BACKEND;
        default: l1_prov_from_resp_source = L1_PROV_UNKNOWN;
      endcase
    end
  endfunction

  task automatic record_l1_hit_prov(input logic [2:0] prov);
    begin
      case (prov)
        L1_PROV_WRITE:   stat_l1_hit_prov_write_cnt    <= stat_l1_hit_prov_write_cnt + 32'd1;
        L1_PROV_BACKEND: stat_l1_hit_prov_backend_cnt  <= stat_l1_hit_prov_backend_cnt + 32'd1;
        L1_PROV_L2:      stat_l1_hit_prov_l2_cnt       <= stat_l1_hit_prov_l2_cnt + 32'd1;
        L1_PROV_CVR:     stat_l1_hit_prov_cvr_cnt      <= stat_l1_hit_prov_cvr_cnt + 32'd1;
        L1_PROV_GF:      stat_l1_hit_prov_gf_cnt       <= stat_l1_hit_prov_gf_cnt + 32'd1;
        L1_PROV_PREF:    stat_l1_hit_prov_prefetch_cnt <= stat_l1_hit_prov_prefetch_cnt + 32'd1;
        default:         stat_l1_hit_prov_unknown_cnt  <= stat_l1_hit_prov_unknown_cnt + 32'd1;
      endcase
    end
  endtask

  task automatic record_l1_fill_prov(input logic [LINE_IDX_W-1:0] idx, input logic [2:0] prov);
    begin
      l1_line_prov[idx] <= prov;
      case (prov)
        L1_PROV_WRITE:   stat_l1_fill_prov_write_cnt    <= stat_l1_fill_prov_write_cnt + 32'd1;
        L1_PROV_BACKEND: stat_l1_fill_prov_backend_cnt  <= stat_l1_fill_prov_backend_cnt + 32'd1;
        L1_PROV_L2:      stat_l1_fill_prov_l2_cnt       <= stat_l1_fill_prov_l2_cnt + 32'd1;
        L1_PROV_CVR:     stat_l1_fill_prov_cvr_cnt      <= stat_l1_fill_prov_cvr_cnt + 32'd1;
        L1_PROV_GF:      stat_l1_fill_prov_gf_cnt       <= stat_l1_fill_prov_gf_cnt + 32'd1;
        L1_PROV_PREF:    stat_l1_fill_prov_prefetch_cnt <= stat_l1_fill_prov_prefetch_cnt + 32'd1;
        default:         stat_l1_fill_prov_unknown_cnt  <= stat_l1_fill_prov_unknown_cnt + 32'd1;
      endcase
    end
  endtask
`endif

  kcmu_metadata_ctrl #(
    .ADDR_W(ADDR_W),
    .LINES(LINES),
    .SCORE_W(SCORE_W),
    .TIME_W(TIME_W),
    .K_RECENT(K_RECENT),
    .H2O_V2_EN(H2O_V2_EN),
    .UTILITY_SCORE_REPL_EN(UTILITY_SCORE_REPL_EN),
    .QMATCH_RECENT_COLD_TIEBREAK_EN(QMATCH_RECENT_COLD_TIEBREAK_EN),
    .QMATCH_L1_QUERY_SEED_EN(QMATCH_L1_QUERY_SEED_EN),
    .QMATCH_L1_KEEP_TIEBREAK_EN(QMATCH_L1_KEEP_TIEBREAK_EN),
    .LINE_IDX_W(LINE_IDX_W)
  ) u_meta (
    .clk(clk),
    .rst_n(rst_n),
    .lookup_addr(meta_lookup_addr),
    .hit(hit),
    .hit_idx(hit_idx),
    .victim_sel(victim_sel),
    .victim_sel_is_invalid(victim_sel_is_invalid),
    .victim_addr(victim_addr),
    .victim_is_lossy(victim_is_lossy),
    .hit_from_prefetch(hit_from_prefetch),
    .hit_is_lossy(hit_is_lossy),
    .access_update_en(upd_en),
    .access_is_hit(upd_is_hit),
    .access_is_prefetch(upd_is_prefetch),
    .access_is_read(upd_is_read),
    .access_qos(upd_qos),
    .access_hh_protect(upd_l1_hh_protect),
    .access_recent_keep(upd_recent_keep),
    .access_h2o_class(upd_l1_h2o_class),
    .access_utility_score(upd_utility_score),
    .access_query_relevance(upd_query_relevance),
    .access_temporal_persist_class(upd_temporal_persist_class),
    .access_reuse_distance_class(upd_reuse_distance_class),
    .access_query_structure_class(upd_query_structure_class),
    .access_kv_sibling_keep(upd_kv_sibling_keep),
    .access_addr(upd_addr),
    .access_hit_idx(upd_hit_idx),
    .access_victim_idx(upd_victim_idx),
    .access_fill_lossy(upd_fill_lossy)
  );

  // Feed metadata with the address that will be accepted in this cycle when idle.
  // This allows one-cycle lookahead while keeping command latency unchanged.
  always @(*) begin
    meta_lookup_addr = cur_addr;
    if (state == ST_IDLE) begin
      if (cmd_valid) begin
        meta_lookup_addr = cmd_addr;
      end else if (pf_valid) begin
        meta_lookup_addr = pf_addr;
      end
    end
  end

  always @(*) begin
    pf_track_hit_cur = 1'b0;
    pf_track_hit_idx = {PF_TRACK_IDX_W{1'b0}};
    pf_track_has_free = 1'b0;
    pf_track_free_idx = {PF_TRACK_IDX_W{1'b0}};
    for (pi = 0; pi < PF_TRACK_DEPTH; pi = pi + 1) begin
      if (!pf_track_hit_cur && pf_track_valid[pi] && (pf_track_addr[pi] == cur_addr)) begin
        pf_track_hit_cur = 1'b1;
        pf_track_hit_idx = pi[PF_TRACK_IDX_W-1:0];
      end
      if (!pf_track_has_free && !pf_track_valid[pi]) begin
        pf_track_has_free = 1'b1;
        pf_track_free_idx = pi[PF_TRACK_IDX_W-1:0];
      end
    end
  end

  always @(*) begin
    demand_pf_useful_cur = 1'b0;
    if (is_read) begin
      if (hit_from_prefetch) begin
        demand_pf_useful_cur = 1'b1;
      end else if (pf_track_hit_cur && (hit || mem_l2_hit)) begin
        demand_pf_useful_cur = 1'b1;
      end
    end
  end

  function automatic logic allow_l1_fill_demand(
    input logic       victim_invalid,
    input logic [2:0] qos,
    input logic       l2_hit,
    input logic       sem_hot,
    input logic       congested
  );
    logic [2:0] eff_qos;
    begin
      eff_qos = qos;
      if (sem_hot && (eff_qos < 3'd7)) begin
        eff_qos = eff_qos + 3'd1;
      end
      if (HIER_POLICY_EN && congested && !sem_hot && (eff_qos > 3'd0)) begin
        eff_qos = eff_qos - 3'd1;
      end
      if (victim_invalid) begin
        allow_l1_fill_demand = 1'b1;
      end else if (HIER_POLICY_EN && congested && !l2_hit && !sem_hot && (eff_qos <= L1_MISS_BYPASS_QOS_TH)) begin
        allow_l1_fill_demand = 1'b0;
      end else if (HIER_POLICY_EN && congested && !sem_hot && (eff_qos <= L1_CONGEST_BYPASS_QOS_TH)) begin
        allow_l1_fill_demand = 1'b0;
      end else if (eff_qos <= L1_BYPASS_QOS_TH) begin
        allow_l1_fill_demand = 1'b0;
      end else if (L1_FILL_ON_HBM_MISS && !l2_hit) begin
        allow_l1_fill_demand = 1'b1;
      end else begin
        allow_l1_fill_demand = (eff_qos >= L1_DEMAND_FILL_QOS_TH);
      end
    end
  endfunction

  function automatic logic allow_l1_fill_prefetch(
    input logic       victim_invalid,
    input logic [2:0] qos,
    input logic       sem_hot,
    input logic       congested
  );
    logic [2:0] eff_qos;
    begin
      eff_qos = qos;
      if (sem_hot && (eff_qos < 3'd7)) begin
        eff_qos = eff_qos + 3'd1;
      end
      if (HIER_POLICY_EN) begin
        if (congested && !sem_hot && (eff_qos > 3'd0)) begin
          eff_qos = eff_qos - 3'd1;
        end
        if (eff_qos > 3'd0) begin
          eff_qos = eff_qos - 3'd1;
        end
      end
      if (victim_invalid) begin
        allow_l1_fill_prefetch = 1'b1;
      end else if (HIER_POLICY_EN && congested && !sem_hot && (eff_qos < PREFETCH_CONGEST_QOS_TH)) begin
        allow_l1_fill_prefetch = 1'b0;
      end else if (eff_qos <= L1_BYPASS_QOS_TH) begin
        allow_l1_fill_prefetch = 1'b0;
      end else begin
        allow_l1_fill_prefetch = (eff_qos >= L1_PREFETCH_FILL_QOS_TH);
      end
    end
  endfunction

  function automatic integer calc_mem_wait_cycles(
    input logic       l2_hit,
    input logic       is_prefetch,
    input logic       sem_hot,
    input logic [2:0] qos,
    input logic       congested
  );
    integer base_lat;
    integer extra_lat;
    begin
      base_lat = l2_hit ? L2_RD_LAT : MEM_RD_LAT;
      extra_lat = 0;
      if (!l2_hit && HIER_POLICY_EN && congested) begin
        if (sem_hot || (qos >= 3'd5)) begin
          extra_lat = HBM_CONGEST_HOT_EXTRA_LAT_SAFE;
        end else if (is_prefetch) begin
          extra_lat = HBM_CONGEST_PREFETCH_EXTRA_LAT_SAFE;
        end else if (qos <= 3'd2) begin
          extra_lat = HBM_CONGEST_COLD_EXTRA_LAT_SAFE;
        end else begin
          if (HBM_CONGEST_COLD_EXTRA_LAT_SAFE > 0) begin
            extra_lat = HBM_CONGEST_COLD_EXTRA_LAT_SAFE - 1;
          end else begin
            extra_lat = 0;
          end
        end
      end
      calc_mem_wait_cycles = base_lat + extra_lat;
    end
  endfunction

  always @(*) begin
    exec_congested = hbm_congested;
    if (EXEC_CONGEST_Q_LEVEL_TH_SAFE <= 0) begin
      if (hbm_q_level != {HBM_Q_W{1'b0}}) begin
        exec_congested = 1'b1;
      end
    end else begin
      if (hbm_q_level >= HBM_Q_W'(EXEC_CONGEST_Q_LEVEL_TH_SAFE)) begin
        exec_congested = 1'b1;
      end
    end
  end

  always @(*) begin
    cur_eff_qos = cur_qos;
    if (cur_sem_hot && (cur_eff_qos < 3'd7)) begin
      cur_eff_qos = cur_eff_qos + 3'd1;
    end
    if (HIER_POLICY_EN && exec_congested && !cur_sem_hot && (cur_eff_qos > 3'd0)) begin
      cur_eff_qos = cur_eff_qos - 3'd1;
    end
  end

  assign prefetch_admit_cur = victim_sel_is_invalid || (cur_eff_qos >= PREF_ADMIT_QOS_TH);
  assign prefetch_issue_allow_cur = !HIER_POLICY_EN ||
                                    ((!exec_congested &&
                                      !hbm_prefetch_block) ||
                                     (cur_eff_qos >= PREFETCH_HBM_ISSUE_QOS_TH) ||
                                     (PREFETCH_HBM_ISSUE_RELAX_HOT && cur_sem_hot));
`ifdef KCMU_ABL_L1_REUSE_ADMISSION_V50
  assign demand_reuse_admission_cur =
    HIER_POLICY_EN &&
    mem_l2_hit &&
    !victim_sel_is_invalid &&
    (cur_qos >= 3'd2) &&
    (cur_sched_temporal_take || cur_sched_query_take || cur_sched_query_bias_take);
`else
  assign demand_reuse_admission_cur = 1'b0;
`endif
  assign demand_base_fill_allow_cur = allow_l1_fill_demand(victim_sel_is_invalid, cur_qos, mem_l2_hit, cur_sem_hot, exec_congested);
`ifdef KCMU_CFG_FPGA_KILOSCORE_NATIVE_STANDALONE
  assign native_demand_fill_allow_cur =
    is_read &&
    (cur_fill_allow ||
     cur_l1_hh_protect ||
     cur_recent_keep ||
     (cur_l1_h2o_class != KCMU_H2O_NEITHER) ||
     (cur_utility_score >= SCORE_W'(8'h40)));
`else
  assign native_demand_fill_allow_cur = 1'b0;
`endif
`ifdef KCMU_ABL_L1_RECENT_LOWROI_BYPASS_V62
  assign demand_lowroi_bypass_cur =
    HIER_POLICY_EN &&
    is_read &&
    !victim_sel_is_invalid &&
    !mem_l2_hit &&
    !cur_sem_hot &&
    !cur_hh_protect &&
    !cur_service_issue_boost &&
    (cur_qos <= 3'd5) &&
    (cur_query_structure_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
    ((cur_h2o_class == KCMU_H2O_RECENT_ONLY) ||
     (cur_h2o_class == KCMU_H2O_NEITHER)) &&
    (cur_query_relevance <= SCORE_W'(8'h60)) &&
    (cur_utility_score <= SCORE_W'(8'h90));
`elsif KCMU_ABL_L1_LOWROI_BYPASS_V61
  assign demand_lowroi_bypass_cur =
    HIER_POLICY_EN &&
    is_read &&
    !victim_sel_is_invalid &&
    !mem_l2_hit &&
    !cur_sem_hot &&
    !cur_hh_protect &&
    !cur_recent_keep &&
    (cur_h2o_class == KCMU_H2O_NEITHER) &&
    !cur_service_issue_boost &&
    (cur_qos <= 3'd5) &&
    (cur_query_relevance <= SCORE_W'(8'h60)) &&
    (cur_utility_score <= SCORE_W'(8'h80));
`else
  assign demand_lowroi_bypass_cur = 1'b0;
`endif
  assign demand_fill_allow_cur =
    demand_reuse_admission_cur ||
    native_demand_fill_allow_cur ||
    (demand_base_fill_allow_cur && !demand_lowroi_bypass_cur);
  assign prefetch_fill_allow_cur = allow_l1_fill_prefetch(victim_sel_is_invalid, cur_qos, cur_sem_hot, exec_congested);

`ifdef KCMU_CFG_HASP_N04_L1_RECALL_V268
  assign l1_recall_eligible_cur = cur_block_last;
  assign l1_recall_hit_cur =
    l1_recall_valid &&
    l1_recall_eligible_cur &&
    is_read &&
    (cur_addr == l1_recall_addr);
  assign demand_effective_hit_cur = hit || l1_recall_hit_cur;
`endif

  // handshakes
  assign pf_ready  = (state == ST_IDLE) && (!cmd_valid);
  assign cmd_ready = (state == ST_IDLE);

  // memory control
  always @(*) begin
    sram_re    = 1'b0;
    sram_raddr = {LINE_IDX_W{1'b0}};
    sram_we    = sram_we_q;
    sram_waddr = sram_waddr_q;
    sram_wdata = sram_wdata_q;

    mem_re     = 1'b0;
    mem_raddr  = {ADDR_W{1'b0}};
    mem_req_prefetch = 1'b0;
    mem_req_qos = 3'd0;
    mem_req_sem_hot = 1'b0;
    mem_req_fill_allow = 1'b0;
    mem_req_victim_protect = 1'b0;
    mem_req_compress_allow = 1'b0;
    mem_req_hh_protect = 1'b0;
    mem_req_recent_keep = 1'b0;
    mem_req_h2o_class = 2'b00;
    mem_req_utility_score = {SCORE_W{1'b0}};
    mem_req_query_relevance = {SCORE_W{1'b0}};
    mem_req_head_budget_class = {kcmu_pkg::KCMU_HEAD_BUDGET_W{1'b0}};
    mem_req_temporal_persist_class = {kcmu_pkg::KCMU_DESC_CLASS_W{1'b0}};
    mem_req_reuse_distance_class = {kcmu_pkg::KCMU_DESC_CLASS_W{1'b0}};
    mem_req_query_structure_class = {kcmu_pkg::KCMU_DESC_CLASS_W{1'b0}};
    mem_req_marginal_active = 1'b0;
    mem_req_service_issue_boost = 1'b0;
    mem_req_sched_query_take = 1'b0;
    mem_req_sched_temporal_take = 1'b0;
    mem_req_sched_query_bias_take = 1'b0;
    mem_req_block_last = 1'b1;
    mem_req_group_target_valid = 1'b0;
    mem_req_group_target_addr = {ADDR_W{1'b0}};
    mem_req_group_v251gf_force = 1'b0;
    mem_req_kiloscore_extra_cvr_hint = 1'b0;
    mem_req_kiloscore_qsig_bucket = 3'd0;
    mem_we     = 1'b0;
    mem_waddr  = {ADDR_W{1'b0}};
    mem_wdata  = {DATA_W{1'b0}};

    case (state)
      ST_MAIN: begin
        if (is_read) begin
          if (hit) begin
            sram_re    = 1'b1;
            sram_raddr = hit_idx;
`ifdef KCMU_CFG_HASP_N04_L1_RECALL_V268
          end else if (l1_recall_hit_cur) begin
`endif
          end else begin
`ifdef KCMU_CFG_HASP_N04_L1_RECALL_V268
            if (mem_l2_hit && mem_rvalid && (L2_RD_LAT <= 1) &&
                demand_fill_allow_cur && !victim_sel_is_invalid) begin
              sram_re    = 1'b1;
              sram_raddr = victim_sel;
            end
`endif
            mem_re     = 1'b1;
            mem_raddr  = cur_addr;
            mem_req_prefetch = 1'b0;
            mem_req_qos = cur_eff_qos;
            mem_req_sem_hot = cur_sem_hot;
            mem_req_fill_allow = cur_fill_allow;
            mem_req_victim_protect = cur_victim_protect;
            mem_req_compress_allow = cur_compress_allow;
            mem_req_hh_protect = cur_hh_protect;
            mem_req_recent_keep = cur_recent_keep;
            mem_req_h2o_class = cur_h2o_class;
            mem_req_utility_score = cur_utility_score;
            mem_req_query_relevance = cur_query_relevance;
            mem_req_head_budget_class = cur_head_budget_class;
            mem_req_temporal_persist_class = cur_temporal_persist_class;
            mem_req_reuse_distance_class = cur_reuse_distance_class;
            mem_req_query_structure_class = cur_query_structure_class;
            mem_req_marginal_active = cur_marginal_active;
            mem_req_service_issue_boost = cur_service_issue_boost;
            mem_req_sched_query_take = cur_sched_query_take;
            mem_req_sched_temporal_take = cur_sched_temporal_take;
            mem_req_sched_query_bias_take = cur_sched_query_bias_take;
            mem_req_block_last = cur_block_last;
            mem_req_group_target_valid = cur_group_target_valid;
            mem_req_group_target_addr = cur_group_target_addr;
            mem_req_group_v251gf_force = cur_group_v251gf_force;
            mem_req_kiloscore_extra_cvr_hint = cur_kiloscore_extra_cvr_hint;
            mem_req_kiloscore_qsig_bucket = cur_kiloscore_qsig_bucket;
          end
        end else if (is_write) begin
`ifdef KCMU_CFG_HASP_N04_L1_RECALL_V268
          if (!hit && !victim_sel_is_invalid) begin
            sram_re    = 1'b1;
            sram_raddr = victim_sel;
          end
`endif
          mem_we     = 1'b1;
          mem_waddr  = cur_addr;
          mem_wdata  = cur_wdata;
          mem_req_prefetch = 1'b0;
          mem_req_qos = cur_eff_qos;
          mem_req_sem_hot = cur_sem_hot;
          mem_req_fill_allow = cur_fill_allow;
          mem_req_victim_protect = cur_victim_protect;
          mem_req_compress_allow = cur_compress_allow;
          mem_req_hh_protect = cur_hh_protect;
          mem_req_recent_keep = cur_recent_keep;
          mem_req_h2o_class = cur_h2o_class;
          mem_req_utility_score = cur_utility_score;
          mem_req_query_relevance = cur_query_relevance;
          mem_req_head_budget_class = cur_head_budget_class;
          mem_req_temporal_persist_class = cur_temporal_persist_class;
          mem_req_reuse_distance_class = cur_reuse_distance_class;
          mem_req_query_structure_class = cur_query_structure_class;
          mem_req_marginal_active = cur_marginal_active;
          mem_req_service_issue_boost = 1'b0;
          mem_req_sched_query_take = cur_sched_query_take;
          mem_req_sched_temporal_take = cur_sched_temporal_take;
          mem_req_sched_query_bias_take = cur_sched_query_bias_take;
          mem_req_block_last = cur_block_last;
          mem_req_group_target_valid = cur_group_target_valid;
          mem_req_group_target_addr = cur_group_target_addr;
          mem_req_group_v251gf_force = cur_group_v251gf_force;
          mem_req_kiloscore_extra_cvr_hint = cur_kiloscore_extra_cvr_hint;
          mem_req_kiloscore_qsig_bucket = cur_kiloscore_qsig_bucket;
        end
      end

      ST_PREF: begin
        if (!hit && prefetch_admit_cur && prefetch_issue_allow_cur) begin
`ifdef KCMU_CFG_HASP_N04_L1_RECALL_V268
          if (mem_l2_hit && mem_rvalid && (L2_RD_LAT <= 1) &&
              prefetch_fill_allow_cur && !victim_sel_is_invalid) begin
            sram_re    = 1'b1;
            sram_raddr = victim_sel;
          end
`endif
          mem_re     = 1'b1;
          mem_raddr  = cur_addr;
          mem_req_prefetch = 1'b1;
          mem_req_qos = cur_eff_qos;
          mem_req_sem_hot = cur_sem_hot;
          mem_req_fill_allow = cur_fill_allow;
          mem_req_victim_protect = cur_victim_protect;
          mem_req_compress_allow = cur_compress_allow;
          mem_req_hh_protect = cur_hh_protect;
          mem_req_recent_keep = cur_recent_keep;
          mem_req_h2o_class = cur_h2o_class;
          mem_req_utility_score = cur_utility_score;
          mem_req_query_relevance = cur_query_relevance;
          mem_req_query_structure_class = cur_query_structure_class;
          mem_req_marginal_active = 1'b0;
          mem_req_service_issue_boost = 1'b0;
          mem_req_sched_query_take = 1'b0;
          mem_req_sched_temporal_take = 1'b0;
          mem_req_sched_query_bias_take = 1'b0;
          mem_req_block_last = 1'b1;
          mem_req_group_target_valid = 1'b0;
          mem_req_group_target_addr = {ADDR_W{1'b0}};
          mem_req_group_v251gf_force = 1'b0;
          mem_req_kiloscore_extra_cvr_hint = 1'b0;
        end
      end

      ST_MEMWAIT: begin
        // Read request is issued in ST_MAIN/ST_PREF. Keep bus quiescent here
        // to avoid reissuing duplicated misses while waiting for rvalid.
`ifdef KCMU_CFG_HASP_N04_L1_RECALL_V268
        if ((mem_wait_ctr == {MEM_WAIT_W{1'b0}}) &&
            mem_pend_rsp_valid &&
            mem_pend_fill_l1 &&
            mem_pend_recall_eligible &&
            !mem_pend_victim_invalid) begin
          sram_re    = 1'b1;
          sram_raddr = mem_pend_victim_idx;
        end
`endif
      end

      default: begin
      end
    endcase
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      state      <= ST_IDLE;
      cur_op     <= KCMU_OP_NOP;
      cur_addr   <= {ADDR_W{1'b0}};
      cur_wdata  <= {DATA_W{1'b0}};
      cur_qos    <= 3'd0;
      cur_sem_hot <= 1'b0;
      cur_fill_allow <= 1'b0;
      cur_victim_protect <= 1'b0;
      cur_compress_allow <= 1'b0;
      cur_hh_protect <= 1'b0;
      cur_l1_hh_protect <= 1'b0;
      cur_recent_keep <= 1'b0;
      cur_h2o_class <= 2'b00;
      cur_l1_h2o_class <= 2'b00;
      cur_utility_score <= {SCORE_W{1'b0}};
      cur_query_relevance <= {SCORE_W{1'b0}};
      cur_head_budget_class <= {kcmu_pkg::KCMU_HEAD_BUDGET_W{1'b0}};
      cur_temporal_persist_class <= {kcmu_pkg::KCMU_DESC_CLASS_W{1'b0}};
      cur_reuse_distance_class <= {kcmu_pkg::KCMU_DESC_CLASS_W{1'b0}};
      cur_query_structure_class <= {kcmu_pkg::KCMU_DESC_CLASS_W{1'b0}};
      cur_marginal_active <= 1'b0;
      cur_service_issue_boost <= 1'b0;
      cur_sched_query_take <= 1'b0;
      cur_sched_temporal_take <= 1'b0;
      cur_sched_query_bias_take <= 1'b0;
      cur_kv_sibling_keep <= 1'b0;
      cur_block_last <= 1'b1;
      cur_group_target_valid <= 1'b0;
      cur_group_target_addr <= {ADDR_W{1'b0}};
      cur_group_v251gf_force <= 1'b0;
      cur_kiloscore_extra_cvr_hint <= 1'b0;
      cur_kiloscore_qsig_bucket <= 3'd0;
      upd_en         <= 1'b0;
      upd_is_hit     <= 1'b0;
      upd_is_prefetch<= 1'b0;
      upd_is_read    <= 1'b0;
      upd_qos        <= 3'd0;
      upd_hh_protect <= 1'b0;
      upd_l1_hh_protect <= 1'b0;
      upd_recent_keep <= 1'b0;
      upd_h2o_class  <= 2'b00;
      upd_l1_h2o_class <= 2'b00;
      upd_utility_score <= {SCORE_W{1'b0}};
      upd_query_relevance <= {SCORE_W{1'b0}};
      upd_temporal_persist_class <= {kcmu_pkg::KCMU_DESC_CLASS_W{1'b0}};
      upd_reuse_distance_class <= {kcmu_pkg::KCMU_DESC_CLASS_W{1'b0}};
      upd_query_structure_class <= {kcmu_pkg::KCMU_DESC_CLASS_W{1'b0}};
      upd_kv_sibling_keep <= 1'b0;
      upd_addr       <= {ADDR_W{1'b0}};
      upd_hit_idx    <= {LINE_IDX_W{1'b0}};
      upd_victim_idx <= {LINE_IDX_W{1'b0}};
      upd_fill_lossy <= 1'b0;
      sram_we_q      <= 1'b0;
      sram_waddr_q   <= {LINE_IDX_W{1'b0}};
      sram_wdata_q   <= {DATA_W{1'b0}};
      mem_pend_prefetch <= 1'b0;
      mem_pend_addr     <= {ADDR_W{1'b0}};
      mem_pend_victim_idx <= {LINE_IDX_W{1'b0}};
      mem_pend_rdata    <= {DATA_W{1'b0}};
      mem_pend_rsource  <= L1_PROV_UNKNOWN;
      mem_pend_qos      <= 3'd0;
      mem_pend_lossy    <= 1'b0;
      mem_pend_rsp_valid <= 1'b0;
      mem_pend_fill_l1  <= 1'b0;
`ifdef KCMU_CFG_HASP_N04_L1_RECALL_V268
      mem_pend_victim_invalid <= 1'b1;
      mem_pend_victim_addr <= {ADDR_W{1'b0}};
      mem_pend_victim_lossy <= 1'b0;
      mem_pend_recall_eligible <= 1'b0;
      l1_recall_valid <= 1'b0;
      l1_recall_addr <= {ADDR_W{1'b0}};
      l1_recall_data <= {DATA_W{1'b0}};
      l1_recall_lossy <= 1'b0;
`endif
      mem_pend_sem_hot  <= 1'b0;
      mem_pend_hh_protect <= 1'b0;
      mem_pend_l1_hh_protect <= 1'b0;
      mem_pend_recent_keep <= 1'b0;
      mem_pend_h2o_class <= 2'b00;
      mem_pend_l1_h2o_class <= 2'b00;
      mem_pend_utility_score <= {SCORE_W{1'b0}};
      mem_pend_query_relevance <= {SCORE_W{1'b0}};
      mem_pend_head_budget_class <= {kcmu_pkg::KCMU_HEAD_BUDGET_W{1'b0}};
      mem_pend_temporal_persist_class <= {kcmu_pkg::KCMU_DESC_CLASS_W{1'b0}};
      mem_pend_reuse_distance_class <= {kcmu_pkg::KCMU_DESC_CLASS_W{1'b0}};
      mem_pend_query_structure_class <= {kcmu_pkg::KCMU_DESC_CLASS_W{1'b0}};
      mem_pend_kv_sibling_keep <= 1'b0;
      mem_pend_kiloscore_qsig_bucket <= 3'd0;
      mem_wait_ignore_first <= 1'b0;
      mem_wait_ctr      <= {MEM_WAIT_W{1'b0}};
      pf_track_valid    <= {PF_TRACK_DEPTH{1'b0}};
      for (pi = 0; pi < PF_TRACK_DEPTH; pi = pi + 1) begin
        pf_track_addr[pi] <= {ADDR_W{1'b0}};
      end
      resp_valid <= 1'b0;
      resp_rdata <= {DATA_W{1'b0}};
      resp_hit   <= 1'b0;
      resp_approx<= 1'b0;
      pf_fill_pulse <= 1'b0;
      pf_useful_pulse <= 1'b0;
      stat_demand_req_cnt <= 32'd0;
      stat_demand_miss_cnt <= 32'd0;
      stat_miss_rate_permille <= 16'd0;

`ifndef SYNTHESIS
      stat_demand_access_cnt <= 32'd0;
      stat_demand_hit_cnt    <= 32'd0;
      stat_l1_hit_cnt        <= 32'd0;
      stat_l1_demand_fill_cnt <= 32'd0;
      stat_l1_demand_bypass_cnt <= 32'd0;
      stat_l1_prefetch_fill_cnt <= 32'd0;
      stat_l1_prefetch_bypass_cnt <= 32'd0;
      stat_l2_demand_fill_cnt<= 32'd0;
      stat_l2_prefetch_fill_cnt <= 32'd0;
      stat_l1_recall_hit_cnt <= 32'd0;
      stat_l1_recall_capture_cnt <= 32'd0;
      stat_l1_recall_invalidate_cnt <= 32'd0;
      stat_prefetch_req_cnt  <= 32'd0;
      stat_prefetch_fill_cnt <= 32'd0;
      stat_prefetch_useful_cnt <= 32'd0;
      stat_evict_cnt         <= 32'd0;
      stat_mem_wait_cycle_cnt<= 32'd0;
      stat_exec_busy_cycle_cnt <= 32'd0;
      stat_l2_lossy_resp_cnt <= 32'd0;
      stat_l1_hit_prov_unknown_cnt <= 32'd0;
      stat_l1_hit_prov_write_cnt <= 32'd0;
      stat_l1_hit_prov_backend_cnt <= 32'd0;
      stat_l1_hit_prov_l2_cnt <= 32'd0;
      stat_l1_hit_prov_cvr_cnt <= 32'd0;
      stat_l1_hit_prov_gf_cnt <= 32'd0;
      stat_l1_hit_prov_prefetch_cnt <= 32'd0;
      stat_l1_fill_prov_unknown_cnt <= 32'd0;
      stat_l1_fill_prov_write_cnt <= 32'd0;
      stat_l1_fill_prov_backend_cnt <= 32'd0;
      stat_l1_fill_prov_l2_cnt <= 32'd0;
      stat_l1_fill_prov_cvr_cnt <= 32'd0;
      stat_l1_fill_prov_gf_cnt <= 32'd0;
      stat_l1_fill_prov_prefetch_cnt <= 32'd0;
      for (pi = 0; pi < LINES; pi = pi + 1) begin
        l1_line_prov[pi] <= L1_PROV_UNKNOWN;
      end
`endif
    end else begin
      upd_en <= 1'b0;
      upd_fill_lossy <= 1'b0;
      upd_kv_sibling_keep <= 1'b0;
      sram_we_q <= 1'b0;
      pf_fill_pulse <= 1'b0;
      pf_useful_pulse <= 1'b0;
`ifndef SYNTHESIS
      if (state != ST_IDLE) begin
        stat_exec_busy_cycle_cnt <= stat_exec_busy_cycle_cnt + 32'd1;
      end
`endif

      case (state)
        ST_IDLE: begin
          resp_valid <= 1'b0;
          resp_approx <= 1'b0;

          if (cmd_valid) begin
`ifdef KCMU_V409_DEBUG
            if ((cmd_addr >= ADDR_W'(48)) && (cmd_addr <= ADDR_W'(120))) begin
              $display("V409_EX_LOAD cmd_addr=%0d state=%0d time=%0t", cmd_addr, state, $time);
            end
`endif
            cur_op    <= cmd_op;
            cur_addr  <= cmd_addr;
            cur_wdata <= cmd_wdata;
            cur_qos   <= cmd_qos;
            cur_sem_hot <= cmd_sem_hot;
            cur_fill_allow <= cmd_fill_allow;
            cur_victim_protect <= cmd_victim_protect;
            cur_compress_allow <= cmd_compress_allow;
            cur_hh_protect <= cmd_hh_protect;
            cur_l1_hh_protect <= cmd_l1_hh_protect;
            cur_recent_keep <= cmd_recent_keep;
            cur_h2o_class <= cmd_h2o_class;
            cur_l1_h2o_class <= cmd_l1_h2o_class;
            cur_utility_score <= cmd_utility_score;
            cur_query_relevance <= cmd_query_relevance;
            cur_head_budget_class <= cmd_head_budget_class;
            cur_temporal_persist_class <= cmd_temporal_persist_class;
            cur_reuse_distance_class <= cmd_reuse_distance_class;
            cur_query_structure_class <= cmd_query_structure_class;
            cur_marginal_active <= cmd_marginal_active;
            cur_service_issue_boost <= cmd_service_issue_boost;
            cur_sched_query_take <= cmd_sched_query_take;
            cur_sched_temporal_take <= cmd_sched_temporal_take;
            cur_sched_query_bias_take <= cmd_sched_query_bias_take;
            cur_kv_sibling_keep <= cmd_kv_sibling_keep;
            cur_block_last <= cmd_block_last;
            cur_group_target_valid <= cmd_group_target_valid;
            cur_group_target_addr <= cmd_group_target_addr;
            cur_group_v251gf_force <= cmd_group_v251gf_force;
            cur_kiloscore_extra_cvr_hint <= cmd_kiloscore_extra_cvr_hint;
            cur_kiloscore_qsig_bucket <= cmd_kiloscore_qsig_bucket;
            state     <= ST_MAIN;
          end else if (pf_valid) begin
            cur_op    <= KCMU_OP_RD;
            cur_addr  <= pf_addr;
            cur_wdata <= {DATA_W{1'b0}};
            cur_qos   <= pf_qos;
            cur_sem_hot <= pf_sem_hot;
            cur_fill_allow <= pf_fill_allow;
            cur_victim_protect <= pf_victim_protect;
            cur_compress_allow <= pf_compress_allow;
            cur_hh_protect <= pf_hh_protect;
            cur_l1_hh_protect <= pf_hh_protect;
            cur_recent_keep <= pf_recent_keep;
            cur_h2o_class <= pf_h2o_class;
            cur_l1_h2o_class <= pf_h2o_class;
            cur_utility_score <= pf_utility_score;
            cur_query_relevance <= pf_query_relevance;
            cur_head_budget_class <= {kcmu_pkg::KCMU_HEAD_BUDGET_W{1'b0}};
            cur_temporal_persist_class <= {kcmu_pkg::KCMU_DESC_CLASS_W{1'b0}};
            cur_reuse_distance_class <= {kcmu_pkg::KCMU_DESC_CLASS_W{1'b0}};
            cur_query_structure_class <= {kcmu_pkg::KCMU_DESC_CLASS_W{1'b0}};
            cur_marginal_active <= 1'b0;
            cur_service_issue_boost <= 1'b0;
            cur_sched_query_take <= 1'b0;
            cur_sched_temporal_take <= 1'b0;
            cur_sched_query_bias_take <= 1'b0;
            cur_kv_sibling_keep <= 1'b0;
            cur_block_last <= 1'b1;
            cur_group_target_valid <= 1'b0;
            cur_group_target_addr <= {ADDR_W{1'b0}};
            cur_group_v251gf_force <= 1'b0;
            cur_kiloscore_extra_cvr_hint <= 1'b0;
            cur_kiloscore_qsig_bucket <= 3'd0;
            state     <= ST_PREF;
`ifndef SYNTHESIS
            stat_prefetch_req_cnt <= stat_prefetch_req_cnt + 32'd1;
`endif
          end
        end

        ST_MAIN: begin
`ifdef KCMU_V409_DEBUG
          if ((cur_addr >= ADDR_W'(48)) && (cur_addr <= ADDR_W'(120))) begin
            $display("V409_EX_MAIN cur_addr=%0d is_read=%0d is_write=%0d hit=%0d hit_idx=%0d victim=%0d sram_rdata=%h mem_l2_hit=%0d mem_rvalid=%0d mem_rdata=%h state=%0d time=%0t",
                     cur_addr,
                     is_read,
                     is_write,
                     hit,
                     hit_idx,
                     victim_sel,
                     sram_rdata,
                     mem_l2_hit,
                     mem_rvalid,
                     mem_rdata,
                     state,
                     $time);
          end
`endif
          if (is_read) begin
            stat_demand_req_cnt_next = stat_demand_req_cnt + 32'd1;
`ifdef KCMU_CFG_HASP_N04_L1_RECALL_V268
            stat_demand_miss_cnt_next = stat_demand_miss_cnt + (demand_effective_hit_cur ? 32'd0 : 32'd1);
`else
            stat_demand_miss_cnt_next = stat_demand_miss_cnt + (hit ? 32'd0 : 32'd1);
`endif
            stat_demand_req_cnt <= stat_demand_req_cnt_next;
            stat_demand_miss_cnt <= stat_demand_miss_cnt_next;
`ifndef SYNTHESIS
            stat_miss_rate_permille <= calc_miss_rate_permille(
              stat_demand_miss_cnt_next,
              stat_demand_req_cnt_next
            );
`else
            // Hardware counter path: keep a useful rolling miss-rate estimate
            // without placing a divider on the read-hit critical path.
`ifdef KCMU_CFG_HASP_N04_L1_RECALL_V268
            if (demand_effective_hit_cur) begin
`else
            if (hit) begin
`endif
              if (stat_miss_rate_permille > 16'd62) begin
                stat_miss_rate_permille <= stat_miss_rate_permille - (stat_miss_rate_permille >> 4);
              end else begin
                stat_miss_rate_permille <= 16'd0;
              end
            end else if (stat_miss_rate_permille < 16'd938) begin
              stat_miss_rate_permille <= stat_miss_rate_permille + ((16'd1000 - stat_miss_rate_permille) >> 4);
            end else begin
              stat_miss_rate_permille <= 16'd1000;
            end
`endif
`ifndef SYNTHESIS
            stat_demand_access_cnt <= stat_demand_access_cnt + 32'd1;
`endif
            if (demand_pf_useful_cur) begin
              pf_useful_pulse <= 1'b1;
              if (pf_track_hit_cur) begin
                pf_track_valid[pf_track_hit_idx] <= 1'b0;
              end
`ifndef SYNTHESIS
              stat_prefetch_useful_cnt <= stat_prefetch_useful_cnt + 32'd1;
`endif
            end
            if (hit) begin
`ifndef SYNTHESIS
              stat_demand_hit_cnt <= stat_demand_hit_cnt + 32'd1;
              stat_l1_hit_cnt     <= stat_l1_hit_cnt + 32'd1;
              record_l1_hit_prov(l1_line_prov[hit_idx]);
`endif
              resp_rdata <= sram_rdata;
              resp_hit   <= 1'b1;
              resp_approx<= hit_is_lossy;
              resp_valid <= 1'b1;
              state      <= ST_RESP;
              upd_en         <= 1'b1;
              upd_is_hit     <= 1'b1;
              upd_is_prefetch<= 1'b0;
              upd_is_read    <= 1'b1;
              upd_qos        <= cur_qos;
              upd_hh_protect <= cur_hh_protect;
              upd_l1_hh_protect <= cur_l1_hh_protect;
              upd_recent_keep <= cur_recent_keep;
              upd_h2o_class  <= cur_h2o_class;
              upd_l1_h2o_class <= cur_l1_h2o_class;
              upd_utility_score <= cur_utility_score;
              upd_query_relevance <= cur_query_relevance;
              upd_temporal_persist_class <= cur_temporal_persist_class;
              upd_reuse_distance_class <= cur_reuse_distance_class;
              upd_query_structure_class <= cur_query_structure_class;
              upd_kv_sibling_keep <= cur_kv_sibling_keep;
              upd_addr       <= cur_addr;
              upd_hit_idx    <= hit_idx;
              upd_victim_idx <= victim_sel;
`ifndef SYNTHESIS
              if (hit_is_lossy) begin
                stat_l2_lossy_resp_cnt <= stat_l2_lossy_resp_cnt + 32'd1;
              end
`endif
`ifdef KCMU_CFG_HASP_N04_L1_RECALL_V268
            end else if (l1_recall_hit_cur) begin
`ifndef SYNTHESIS
              stat_demand_hit_cnt <= stat_demand_hit_cnt + 32'd1;
              stat_l1_hit_cnt     <= stat_l1_hit_cnt + 32'd1;
              stat_l1_recall_hit_cnt <= stat_l1_recall_hit_cnt + 32'd1;
              record_l1_hit_prov(L1_PROV_UNKNOWN);
`endif
              resp_rdata <= l1_recall_data;
              resp_hit   <= 1'b1;
              resp_approx<= l1_recall_lossy;
              resp_valid <= 1'b1;
              state      <= ST_RESP;
              l1_recall_valid <= 1'b0;
`endif
            end else begin
              // Fast path: if served from L2 with one-cycle latency budget, respond directly.
              if (KCMU_EXEC_STMAIN_L2_FAST_PATH_EN &&
                  mem_l2_hit && mem_rvalid && (L2_RD_LAT <= 1)) begin
                if (demand_fill_allow_cur) begin
                  sram_we_q    <= 1'b1;
                  sram_waddr_q <= victim_sel;
                  sram_wdata_q <= mem_rdata;
`ifdef KCMU_CFG_HASP_N04_L1_RECALL_V268
                  if (l1_recall_eligible_cur && !victim_sel_is_invalid) begin
                    l1_recall_valid <= 1'b1;
                    l1_recall_addr  <= victim_addr;
                    l1_recall_data  <= sram_rdata;
                    l1_recall_lossy <= victim_is_lossy;
`ifndef SYNTHESIS
                    stat_l1_recall_capture_cnt <= stat_l1_recall_capture_cnt + 32'd1;
`endif
                  end else if (l1_recall_valid && (l1_recall_addr == cur_addr)) begin
                    l1_recall_valid <= 1'b0;
                  end
`endif

                  upd_en         <= 1'b1;
                  upd_is_hit     <= 1'b0;
                  upd_is_prefetch<= 1'b0;
                  upd_is_read    <= 1'b1;
                  upd_qos        <= cur_qos;
                  upd_hh_protect <= cur_hh_protect;
                  upd_l1_hh_protect <= cur_l1_hh_protect;
                  upd_recent_keep <= cur_recent_keep;
                  upd_h2o_class  <= cur_h2o_class;
                  upd_l1_h2o_class <= cur_l1_h2o_class;
                  upd_utility_score <= cur_utility_score;
                  upd_query_relevance <= cur_query_relevance;
                  upd_temporal_persist_class <= cur_temporal_persist_class;
                  upd_reuse_distance_class <= cur_reuse_distance_class;
                  upd_query_structure_class <= cur_query_structure_class;
                  upd_kv_sibling_keep <= cur_kv_sibling_keep;
                  upd_addr       <= cur_addr;
                  upd_hit_idx    <= {LINE_IDX_W{1'b0}};
                  upd_victim_idx <= victim_sel;
                  upd_fill_lossy <= mem_r_lossy;
`ifndef SYNTHESIS
                  stat_l1_demand_fill_cnt <= stat_l1_demand_fill_cnt + 32'd1;
                  record_l1_fill_prov(victim_sel, l1_prov_from_resp_source(mem_rsource));
`endif
                end else begin
`ifndef SYNTHESIS
                  stat_l1_demand_bypass_cnt <= stat_l1_demand_bypass_cnt + 32'd1;
`endif
                end

                resp_rdata <= mem_rdata;
                resp_hit   <= 1'b0;
                resp_approx<= mem_r_lossy;
                resp_valid <= 1'b1;
                state      <= ST_RESP;
`ifndef SYNTHESIS
                stat_l2_demand_fill_cnt <= stat_l2_demand_fill_cnt + 32'd1;
                if (mem_r_lossy) begin
                  stat_l2_lossy_resp_cnt <= stat_l2_lossy_resp_cnt + 32'd1;
                end
`endif
              end else begin
                mem_pend_prefetch   <= 1'b0;
                mem_pend_addr       <= cur_addr;
                mem_pend_victim_idx <= victim_sel;
                mem_pend_rdata      <= {DATA_W{1'b0}};
                mem_pend_rsource    <= L1_PROV_UNKNOWN;
                mem_pend_qos        <= cur_eff_qos;
                mem_pend_lossy      <= 1'b0;
                mem_pend_rsp_valid  <= 1'b0;
                mem_pend_fill_l1    <= demand_fill_allow_cur;
`ifdef KCMU_CFG_HASP_N04_L1_RECALL_V268
                mem_pend_victim_invalid <= victim_sel_is_invalid;
                mem_pend_victim_addr <= victim_addr;
                mem_pend_victim_lossy <= victim_is_lossy;
                mem_pend_recall_eligible <= l1_recall_eligible_cur;
`endif
                mem_pend_sem_hot    <= cur_sem_hot;
                mem_pend_hh_protect <= cur_hh_protect;
                mem_pend_l1_hh_protect <= cur_l1_hh_protect;
                mem_pend_recent_keep <= cur_recent_keep;
                mem_pend_h2o_class <= cur_h2o_class;
                mem_pend_l1_h2o_class <= cur_l1_h2o_class;
                mem_pend_utility_score <= cur_utility_score;
                mem_pend_query_relevance <= cur_query_relevance;
                mem_pend_head_budget_class <= cur_head_budget_class;
                mem_pend_temporal_persist_class <= cur_temporal_persist_class;
                mem_pend_reuse_distance_class <= cur_reuse_distance_class;
                mem_pend_query_structure_class <= cur_query_structure_class;
                mem_pend_kv_sibling_keep <= cur_kv_sibling_keep;
                mem_pend_kiloscore_qsig_bucket <= cur_kiloscore_qsig_bucket;
                mem_wait_ignore_first <= 1'b1;
                mem_wait_ctr        <= MEM_WAIT_W'(calc_mem_wait_cycles(mem_l2_hit, 1'b0, cur_sem_hot, cur_eff_qos, exec_congested) - 1);
                state               <= ST_MEMWAIT;
              end
`ifndef SYNTHESIS
              if (!victim_sel_is_invalid) begin
                stat_evict_cnt <= stat_evict_cnt + 32'd1;
              end
`endif
            end
          end else if (is_write) begin
`ifndef SYNTHESIS
            stat_demand_access_cnt <= stat_demand_access_cnt + 32'd1;
`endif
`ifdef KCMU_CFG_HASP_N04_L1_RECALL_V268
            if (l1_recall_valid) begin
              l1_recall_valid <= 1'b0;
`ifndef SYNTHESIS
              stat_l1_recall_invalidate_cnt <= stat_l1_recall_invalidate_cnt + 32'd1;
`endif
            end
`endif
            if (hit) begin
`ifndef SYNTHESIS
              stat_demand_hit_cnt <= stat_demand_hit_cnt + 32'd1;
              stat_l1_hit_cnt     <= stat_l1_hit_cnt + 32'd1;
`endif
              resp_hit <= 1'b1;
              resp_approx <= 1'b0;
            end else begin
`ifndef SYNTHESIS
              if (!victim_sel_is_invalid) begin
                stat_evict_cnt <= stat_evict_cnt + 32'd1;
              end
`endif
              resp_hit <= 1'b0;
              resp_approx <= 1'b0;
            end
            sram_we_q    <= 1'b1;
            sram_waddr_q <= hit ? hit_idx : victim_sel;
            sram_wdata_q <= cur_wdata;
`ifndef SYNTHESIS
            record_l1_fill_prov(hit ? hit_idx : victim_sel, L1_PROV_WRITE);
`endif
            resp_rdata <= {DATA_W{1'b0}};
            resp_valid <= 1'b1;
            state      <= ST_RESP;
`ifdef KCMU_V409_DEBUG
            if ((cur_addr >= ADDR_W'(48)) && (cur_addr <= ADDR_W'(120))) begin
              $display("V409_EX_WR_RESP addr=%0d data=%h hit=%0d hit_idx=%0d victim=%0d time=%0t",
                       cur_addr,
                       cur_wdata,
                       hit,
                       hit_idx,
                       victim_sel,
                       $time);
            end
`endif
            upd_en         <= 1'b1;
            upd_is_hit     <= hit;
            upd_is_prefetch<= 1'b0;
            upd_is_read    <= 1'b0;
            upd_qos        <= cur_qos;
            upd_hh_protect <= cur_hh_protect;
            upd_l1_hh_protect <= cur_l1_hh_protect;
            upd_recent_keep <= cur_recent_keep;
            upd_h2o_class  <= cur_h2o_class;
            upd_l1_h2o_class <= cur_l1_h2o_class;
            upd_utility_score <= cur_utility_score;
            upd_query_relevance <= cur_query_relevance;
            upd_temporal_persist_class <= cur_temporal_persist_class;
            upd_reuse_distance_class <= cur_reuse_distance_class;
            upd_query_structure_class <= cur_query_structure_class;
            upd_kv_sibling_keep <= 1'b0;
            upd_addr       <= cur_addr;
            upd_hit_idx    <= hit_idx;
            upd_victim_idx <= victim_sel;
          end else begin
            resp_rdata <= {DATA_W{1'b0}};
            resp_hit   <= 1'b0;
            resp_approx<= 1'b0;
            resp_valid <= 1'b1;
            state      <= ST_RESP;
          end
        end

        ST_RESP: begin
          if (resp_valid && resp_ready) begin
            resp_valid <= 1'b0;
            resp_approx<= 1'b0;
            state      <= ST_IDLE;
          end
        end

        ST_PREF: begin
          if (!hit) begin
            if (!prefetch_admit_cur || !prefetch_issue_allow_cur) begin
              state <= ST_IDLE;
            end else begin
              if (KCMU_EXEC_STMAIN_L2_FAST_PATH_EN &&
                  mem_l2_hit && mem_rvalid && (L2_RD_LAT <= 1)) begin
                if (!pf_track_hit_cur) begin
                  if (pf_track_has_free) begin
                    pf_track_valid[pf_track_free_idx] <= 1'b1;
                    pf_track_addr[pf_track_free_idx] <= cur_addr;
                  end else begin
                    pf_track_valid[0] <= 1'b1;
                    pf_track_addr[0] <= cur_addr;
                  end
                end
                if (prefetch_fill_allow_cur) begin
                  sram_we_q    <= 1'b1;
                  sram_waddr_q <= victim_sel;
                  sram_wdata_q <= mem_rdata;
`ifdef KCMU_CFG_HASP_N04_L1_RECALL_V268
                  if (l1_recall_eligible_cur && !victim_sel_is_invalid) begin
                    l1_recall_valid <= 1'b1;
                    l1_recall_addr  <= victim_addr;
                    l1_recall_data  <= sram_rdata;
                    l1_recall_lossy <= victim_is_lossy;
`ifndef SYNTHESIS
                    stat_l1_recall_capture_cnt <= stat_l1_recall_capture_cnt + 32'd1;
`endif
                  end else if (l1_recall_valid && (l1_recall_addr == cur_addr)) begin
                    l1_recall_valid <= 1'b0;
                  end
`endif

                  upd_en         <= 1'b1;
                  upd_is_hit     <= 1'b0;
                  upd_is_prefetch<= 1'b1;
                  upd_is_read    <= 1'b0;
                  upd_qos        <= cur_qos;
                  upd_hh_protect <= cur_hh_protect;
                  upd_l1_hh_protect <= cur_l1_hh_protect;
                  upd_recent_keep <= cur_recent_keep;
                  upd_h2o_class  <= cur_h2o_class;
                  upd_l1_h2o_class <= cur_l1_h2o_class;
                  upd_utility_score <= cur_utility_score;
                  upd_query_relevance <= cur_query_relevance;
                  upd_temporal_persist_class <= {kcmu_pkg::KCMU_DESC_CLASS_W{1'b0}};
                  upd_reuse_distance_class <= {kcmu_pkg::KCMU_DESC_CLASS_W{1'b0}};
                  upd_query_structure_class <= {kcmu_pkg::KCMU_DESC_CLASS_W{1'b0}};
                  upd_kv_sibling_keep <= 1'b0;
                  upd_addr       <= cur_addr;
                  upd_hit_idx    <= {LINE_IDX_W{1'b0}};
                  upd_victim_idx <= victim_sel;
                  upd_fill_lossy <= mem_r_lossy;
                  pf_fill_pulse  <= 1'b1;
`ifndef SYNTHESIS
                  stat_l1_prefetch_fill_cnt <= stat_l1_prefetch_fill_cnt + 32'd1;
                  stat_prefetch_fill_cnt    <= stat_prefetch_fill_cnt + 32'd1;
                  stat_l2_prefetch_fill_cnt <= stat_l2_prefetch_fill_cnt + 32'd1;
                  record_l1_fill_prov(victim_sel, L1_PROV_PREF);
`endif
                end else begin
`ifndef SYNTHESIS
                  stat_l1_prefetch_bypass_cnt <= stat_l1_prefetch_bypass_cnt + 32'd1;
`endif
                end
                state <= ST_IDLE;
              end else if (mem_req_accepted) begin
                if (!pf_track_hit_cur) begin
                  if (pf_track_has_free) begin
                    pf_track_valid[pf_track_free_idx] <= 1'b1;
                    pf_track_addr[pf_track_free_idx] <= cur_addr;
                  end else begin
                    pf_track_valid[0] <= 1'b1;
                    pf_track_addr[0] <= cur_addr;
                  end
                end
                mem_pend_prefetch   <= 1'b1;
                mem_pend_addr       <= cur_addr;
                mem_pend_victim_idx <= victim_sel;
                mem_pend_rdata      <= {DATA_W{1'b0}};
                mem_pend_rsource    <= L1_PROV_UNKNOWN;
                mem_pend_qos        <= cur_eff_qos;
                mem_pend_lossy      <= 1'b0;
                mem_pend_rsp_valid  <= 1'b0;
                mem_pend_fill_l1    <= prefetch_fill_allow_cur;
`ifdef KCMU_CFG_HASP_N04_L1_RECALL_V268
                mem_pend_victim_invalid <= victim_sel_is_invalid;
                mem_pend_victim_addr <= victim_addr;
                mem_pend_victim_lossy <= victim_is_lossy;
                mem_pend_recall_eligible <= l1_recall_eligible_cur;
`endif
                mem_pend_sem_hot    <= cur_sem_hot;
                mem_pend_hh_protect <= cur_hh_protect;
                mem_pend_l1_hh_protect <= cur_l1_hh_protect;
                mem_pend_recent_keep <= cur_recent_keep;
                mem_pend_h2o_class <= cur_h2o_class;
                mem_pend_l1_h2o_class <= cur_l1_h2o_class;
                mem_pend_utility_score <= cur_utility_score;
                mem_pend_query_relevance <= cur_query_relevance;
                mem_pend_head_budget_class <= {kcmu_pkg::KCMU_HEAD_BUDGET_W{1'b0}};
                mem_pend_temporal_persist_class <= {kcmu_pkg::KCMU_DESC_CLASS_W{1'b0}};
                mem_pend_reuse_distance_class <= {kcmu_pkg::KCMU_DESC_CLASS_W{1'b0}};
                mem_pend_query_structure_class <= {kcmu_pkg::KCMU_DESC_CLASS_W{1'b0}};
                mem_pend_kv_sibling_keep <= 1'b0;
                mem_pend_kiloscore_qsig_bucket <= 3'd0;
                mem_wait_ignore_first <= 1'b1;
                mem_wait_ctr        <= MEM_WAIT_W'(calc_mem_wait_cycles(mem_l2_hit, 1'b1, cur_sem_hot, cur_eff_qos, exec_congested) - 1);
                state               <= ST_MEMWAIT;
              end else begin
                state <= ST_IDLE;
              end
`ifndef SYNTHESIS
              if (!victim_sel_is_invalid) begin
                stat_evict_cnt <= stat_evict_cnt + 32'd1;
              end
`endif
            end
          end else begin
`ifndef SYNTHESIS
            stat_l1_hit_cnt <= stat_l1_hit_cnt + 32'd1;
`endif
            state <= ST_IDLE;
          end
        end

        ST_MEMWAIT: begin
`ifndef SYNTHESIS
          stat_mem_wait_cycle_cnt <= stat_mem_wait_cycle_cnt + 32'd1;
          if (mem_rvalid) begin
            mem_pend_rsource <= l1_prov_from_resp_source(mem_rsource);
          end
`endif
          if (mem_wait_ignore_first) begin
            mem_wait_ignore_first <= 1'b0;
`ifdef KCMU_CFG_FPGA_KILOSCORE_NATIVE_STANDALONE
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_H2O_PLUS_SERVICE_CVR_GROUP_FILL_V251
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_TINY_SLIDE_GF_RESCUE_V723
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_TINY_ASYM_STRUCT_RESCUE_V722
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_TINY_WINDOW_STRUCT_RESCUE_V721
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_TINY_CVR_C0_STRUCT_RESCUE_V720
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_CAP_STRUCT_RESCUE_V719
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_CAP_Q1_GFCONF_GUARD_V718
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_L2CAP_ADJ_BASE_GUARD_V717
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_STRUCTONLY_ADJ_BASE_GUARD_V716
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_MIXPHASE_ADJ_BASE_ZERO_GUARD_V715
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_MIXPHASE_BASE_MID_HH_GUARD_V714
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_MIXPHASE_BASE_ZERO_HH_GUARD_V713
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_MIXPHASE_BASE_HH_GUARD_V712
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_TRIRAIL_ZERO_HH_BRAKE_V711
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_TRIRAIL_BASE_HH_BRAKE_V710
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_SPECIAL_BASE_HH_BRAKE_V709
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_SAFE_HH_BRAKE_V708
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_STRICT_HH_BRAKE_ONLY_V707
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_ULTRA_HH_BRAKE_EXTRA_CVR_V706
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_STRICT_HH_BRAKE_EXTRA_CVR_V705
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_DENSE_LATCH_THRESHOLD_EXTRA_CVR_V704
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_PHASE_THRESHOLD_EXTRA_CVR_V703
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_WINDOW_DENSE_PHASE_TINY_EXTRA_CVR_V702
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_WINDOW_DENSE_PHASE_EXTRA_CVR_V701
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_DENSE_PHASE_SHORT_EXTRA_CVR_V700
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_DENSE_PHASE_EXTRA_CVR_V699
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_FARSCAN_ESCAPE_EXTRA_CVR_V698
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_ESCAPE_EXTRA_CVR_V697
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_PROFILEBUCKET_SATGUARD_EXTRA_CVR_V696
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_PROFILEBUCKET_WRITEGUARD_EXTRA_CVR_V695
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_BP_QREL_CAPBRAKE_TARGET_DEBT_DESC_TARGET_EXTRA_CVR_V641
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_PRESSURE_CAPBRAKE_TARGET_DEBT_DESC_TARGET_EXTRA_CVR_V640
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_CAPBRAKE_TARGET_DEBT_DESC_TARGET_EXTRA_CVR_V639
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_TARGET_DEBT_DESC_TARGET_EXTRA_CVR_V638
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_NSA_LENSAFE_DESC_TARGET_EXTRA_CVR_V637
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_NSA_KV0_DESC_TARGET_EXTRA_CVR_V636
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_NSA_DESC_TARGET_EXTRA_CVR_V635
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_NSA_RAIL_QSIG1_EXTRA_CVR_V634
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_NSA_RAIL_EXTRA_CVR_V633
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_HOST_PROFILE_EXTRA_CVR_V632
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_HOST_PROFILE_EXTRA_CVR_V630
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`elsif KCMU_CFG_FPGA_KILOSCORE_CMDQ_LOOKAHEAD_GF_V409
            if (mem_l2_hit && mem_rvalid) begin
              mem_pend_rsp_valid <= 1'b1;
              mem_pend_rdata <= mem_rdata;
              mem_pend_lossy <= mem_r_lossy;
            end
`endif
          end else if (mem_rvalid) begin
            mem_pend_rsp_valid <= 1'b1;
            mem_pend_rdata <= mem_rdata;
            mem_pend_lossy <= mem_r_lossy;
          end

          if (mem_wait_ctr != {MEM_WAIT_W{1'b0}}) begin
            mem_wait_ctr <= mem_wait_ctr - MEM_WAIT_W'(1);
          end else if (!mem_pend_rsp_valid) begin
            // Hold until memory response is observed.
          end else begin
            if (mem_pend_fill_l1) begin
              sram_we_q    <= 1'b1;
              sram_waddr_q <= mem_pend_victim_idx;
              sram_wdata_q <= mem_pend_rdata;
`ifndef SYNTHESIS
              record_l1_fill_prov(mem_pend_victim_idx, mem_pend_prefetch ? L1_PROV_PREF : mem_pend_rsource);
`endif
`ifdef KCMU_CFG_HASP_N04_L1_RECALL_V268
              if (mem_pend_recall_eligible && !mem_pend_victim_invalid) begin
                l1_recall_valid <= 1'b1;
                l1_recall_addr  <= mem_pend_victim_addr;
                l1_recall_data  <= sram_rdata;
                l1_recall_lossy <= mem_pend_victim_lossy;
`ifndef SYNTHESIS
                stat_l1_recall_capture_cnt <= stat_l1_recall_capture_cnt + 32'd1;
`endif
              end else if (l1_recall_valid && (l1_recall_addr == mem_pend_addr)) begin
                l1_recall_valid <= 1'b0;
              end
`endif

              upd_en         <= 1'b1;
              upd_is_hit     <= 1'b0;
              upd_is_prefetch<= mem_pend_prefetch;
              upd_is_read    <= !mem_pend_prefetch;
              upd_qos        <= mem_pend_qos;
              upd_hh_protect <= mem_pend_hh_protect;
              upd_l1_hh_protect <= mem_pend_l1_hh_protect;
              upd_recent_keep <= mem_pend_recent_keep;
              upd_h2o_class  <= mem_pend_h2o_class;
              upd_l1_h2o_class <= mem_pend_l1_h2o_class;
              upd_utility_score <= mem_pend_utility_score;
              upd_query_relevance <= mem_pend_query_relevance;
              upd_temporal_persist_class <= mem_pend_temporal_persist_class;
              upd_reuse_distance_class <= mem_pend_reuse_distance_class;
              upd_query_structure_class <= mem_pend_query_structure_class;
              upd_kv_sibling_keep <= mem_pend_kv_sibling_keep;
              upd_addr       <= mem_pend_addr;
              upd_hit_idx    <= {LINE_IDX_W{1'b0}};
              upd_victim_idx <= mem_pend_victim_idx;
              upd_fill_lossy <= mem_pend_lossy;
            end

            if (mem_pend_prefetch) begin
              if (mem_pend_fill_l1) begin
                pf_fill_pulse <= 1'b1;
              end
`ifndef SYNTHESIS
              if (mem_pend_fill_l1) begin
                stat_l1_prefetch_fill_cnt <= stat_l1_prefetch_fill_cnt + 32'd1;
                stat_prefetch_fill_cnt    <= stat_prefetch_fill_cnt + 32'd1;
                stat_l2_prefetch_fill_cnt <= stat_l2_prefetch_fill_cnt + 32'd1;
              end else begin
                stat_l1_prefetch_bypass_cnt <= stat_l1_prefetch_bypass_cnt + 32'd1;
              end
`endif
              state <= ST_IDLE;
            end else begin
`ifndef SYNTHESIS
              if (mem_pend_fill_l1) begin
                stat_l1_demand_fill_cnt <= stat_l1_demand_fill_cnt + 32'd1;
              end else begin
                stat_l1_demand_bypass_cnt <= stat_l1_demand_bypass_cnt + 32'd1;
              end
              stat_l2_demand_fill_cnt <= stat_l2_demand_fill_cnt + 32'd1;
              if (mem_pend_lossy) begin
                stat_l2_lossy_resp_cnt <= stat_l2_lossy_resp_cnt + 32'd1;
              end
`endif
              resp_rdata <= mem_pend_rdata;
              resp_hit   <= 1'b0;
              resp_approx<= mem_pend_lossy;
              resp_valid <= 1'b1;
              state      <= ST_RESP;
            end
          end
        end

        default: begin
          state <= ST_IDLE;
        end
      endcase
    end
  end

endmodule

