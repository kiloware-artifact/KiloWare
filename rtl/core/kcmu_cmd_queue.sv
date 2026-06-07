`timescale 1ns/1ps
`ifdef KCMU_CFG_FPGA_KILOSCORE_HV_OPT5_GLOBAL_WINNER
`ifndef KCMU_CFG_FPGA_KILOSCORE_SEARCH_TINY_CVR16_DESC_TARGET_RESTORE_V1474
`define KCMU_CFG_FPGA_KILOSCORE_SEARCH_TINY_CVR16_DESC_TARGET_RESTORE_V1474
`endif
`ifndef KCMU_CFG_FPGA_KILOSCORE_SEARCH_CAPACITY_CORRIDOR_RESTORE_V1475
`define KCMU_CFG_FPGA_KILOSCORE_SEARCH_CAPACITY_CORRIDOR_RESTORE_V1475
`endif
`ifndef KCMU_CFG_FPGA_KILOSCORE_SEARCH_LARGECAP_QSTRUCT_DESC_RESTORE_V1479
`define KCMU_CFG_FPGA_KILOSCORE_SEARCH_LARGECAP_QSTRUCT_DESC_RESTORE_V1479
`endif
`ifndef KCMU_CFG_FPGA_KILOSCORE_SEARCH_LARGECAP_Q1_HISVC_TARGET_RESTORE_V1486
`define KCMU_CFG_FPGA_KILOSCORE_SEARCH_LARGECAP_Q1_HISVC_TARGET_RESTORE_V1486
`endif
`ifndef KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_MIDBURST_Q1_BRAKE_VLONG_D3_V860
`define KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_MIDBURST_Q1_BRAKE_VLONG_D3_V860
`endif
`ifndef KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_MIDBURST_Q1_BRAKE_V856
`define KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_MIDBURST_Q1_BRAKE_V856
`endif
`ifndef KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_POLICY_D1D2_WRBURST30_D2_V829
`define KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_POLICY_D1D2_WRBURST30_D2_V829
`endif
`endif
// ------------------------------------------------------------
// kcmu_cmd_queue.sv
// Front-end command queue.
// ------------------------------------------------------------
module kcmu_cmd_queue #(
  parameter integer ADDR_W = 8,
  parameter integer DATA_W = 32,
  parameter integer SCORE_W = 8,
  parameter integer DEPTH = 4,
  parameter bit     REORDER_EN = 1'b0,
  parameter bit     LOOKAHEAD_TARGET_EN = 1'b0,
  parameter integer LOOKAHEAD_MAX_DELTA = 8,
  parameter bit     DESC_TARGET_EN = 1'b0,
  parameter integer DESC_TARGET_DELTA = 2,
  parameter bit     DESC_TARGET_ADAPTIVE_EN = 1'b0,
  parameter integer DESC_TARGET_HIGH_DELTA = 3,
  parameter integer DESC_TARGET_DENSITY_TH = 3,
  parameter integer L1_LINES = 16,
  parameter integer L2_LINES = 64,
  parameter integer VB_LINES = 4,
  parameter integer GROUP_BUF_LINES = 4,
  parameter integer IDX_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH),
  parameter integer LVL_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1)
)(
  input  logic                  clk,
  input  logic                  rst_n,

  input  logic                  in_valid,
  output logic                  in_ready,
  input  kcmu_pkg::kcmu_op_t    in_op,
  input  logic [ADDR_W-1:0]     in_addr,
  input  logic [DATA_W-1:0]     in_wdata,
  input  logic                  in_meta_valid,
  input  logic [kcmu_pkg::KCMU_SEQ_W-1:0] in_seq_id,
  input  kcmu_pkg::kcmu_phase_t in_phase,
  input  kcmu_pkg::kcmu_kv_kind_t in_kv_kind,
  input  logic [2:0]            in_layer,
  input  logic [1:0]            in_head,
  input  logic [11:0]           in_token,
  input  logic [2:0]            in_prio,
  input  logic [SCORE_W-1:0]    in_score,
  input  logic                  in_attn_valid,
  input  logic [SCORE_W-1:0]    in_attn_score,
  input  logic [kcmu_pkg::KCMU_ATTN_RANK_W-1:0] in_recent_rank,
  input  logic [kcmu_pkg::KCMU_TOKEN_BLOCK_W-1:0] in_token_block_id,
  input  logic [kcmu_pkg::KCMU_ATTN_EPOCH_W-1:0] in_attn_epoch,
  input  logic [kcmu_pkg::KCMU_HEAD_BUDGET_W-1:0] in_head_budget_class,
  input  logic [SCORE_W-1:0]    in_query_relevance,
  input  logic [kcmu_pkg::KCMU_COST_CLASS_W-1:0] in_compression_risk,
  input  logic [kcmu_pkg::KCMU_COST_CLASS_W-1:0] in_spill_cost,
  input  logic [SCORE_W-1:0]    in_service_criticality,
  input  logic                  in_policy_select_s5,
  input  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] in_temporal_persist_class,
  input  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] in_reuse_distance_class,
  input  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] in_query_structure_class,
  input  logic [kcmu_pkg::KCMU_SCHED_HINT_W-1:0] in_sched_urgency_hint,
  input  logic                  in_sig_valid,
  input  logic [5:0]            in_query_sig,
  input  logic [5:0]            in_key_sig,
  input  logic [1:0]            in_prefix_class,
  input  logic [1:0]            in_router_class,
  input  logic                  in_block_last,

  output logic                  out_valid,
  input  logic                  out_ready,
  output kcmu_pkg::kcmu_op_t    out_op,
  output logic [ADDR_W-1:0]     out_addr,
  output logic [DATA_W-1:0]     out_wdata,
  output logic                  out_meta_valid,
  output logic [kcmu_pkg::KCMU_SEQ_W-1:0] out_seq_id,
  output kcmu_pkg::kcmu_phase_t out_phase,
  output kcmu_pkg::kcmu_kv_kind_t out_kv_kind,
  output logic [2:0]            out_layer,
  output logic [1:0]            out_head,
  output logic [11:0]           out_token,
  output logic [2:0]            out_prio,
  output logic [SCORE_W-1:0]    out_score,
  output logic                  out_attn_valid,
  output logic [SCORE_W-1:0]    out_attn_score,
  output logic [kcmu_pkg::KCMU_ATTN_RANK_W-1:0] out_recent_rank,
  output logic [kcmu_pkg::KCMU_TOKEN_BLOCK_W-1:0] out_token_block_id,
  output logic [kcmu_pkg::KCMU_ATTN_EPOCH_W-1:0] out_attn_epoch,
  output logic [kcmu_pkg::KCMU_HEAD_BUDGET_W-1:0] out_head_budget_class,
  output logic [SCORE_W-1:0]    out_query_relevance,
  output logic [kcmu_pkg::KCMU_COST_CLASS_W-1:0] out_compression_risk,
  output logic [kcmu_pkg::KCMU_COST_CLASS_W-1:0] out_spill_cost,
  output logic [SCORE_W-1:0]    out_service_criticality,
  output logic                  out_policy_select_s5,
  output logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] out_temporal_persist_class,
  output logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] out_reuse_distance_class,
  output logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] out_query_structure_class,
  output logic [kcmu_pkg::KCMU_SCHED_HINT_W-1:0] out_sched_urgency_hint,
  output logic                  out_sig_valid,
  output logic [5:0]            out_query_sig,
  output logic [5:0]            out_key_sig,
  output logic [1:0]            out_prefix_class,
  output logic [1:0]            out_router_class,
  output logic                  out_block_last,
  output logic                  out_group_target_valid,
  output logic [ADDR_W-1:0]     out_group_target_addr,
  output logic [LVL_W-1:0]      q_level
);
  import kcmu_pkg::*;

  kcmu_op_t           q_op [0:DEPTH-1];
  logic [ADDR_W-1:0]  q_addr [0:DEPTH-1];
  logic [DATA_W-1:0]  q_wdata [0:DEPTH-1];
  logic               q_meta_valid [0:DEPTH-1];
  logic [kcmu_pkg::KCMU_SEQ_W-1:0] q_seq_id [0:DEPTH-1];
  kcmu_pkg::kcmu_phase_t q_phase [0:DEPTH-1];
  kcmu_pkg::kcmu_kv_kind_t q_kv_kind [0:DEPTH-1];
  logic [2:0]         q_layer [0:DEPTH-1];
  logic [1:0]         q_head [0:DEPTH-1];
  logic [11:0]        q_token [0:DEPTH-1];
  logic [2:0]         q_prio [0:DEPTH-1];
  logic [SCORE_W-1:0] q_score [0:DEPTH-1];
  logic               q_attn_valid [0:DEPTH-1];
  logic [SCORE_W-1:0] q_attn_score [0:DEPTH-1];
  logic [kcmu_pkg::KCMU_ATTN_RANK_W-1:0] q_recent_rank [0:DEPTH-1];
  logic [kcmu_pkg::KCMU_TOKEN_BLOCK_W-1:0] q_token_block_id [0:DEPTH-1];
  logic [kcmu_pkg::KCMU_ATTN_EPOCH_W-1:0] q_attn_epoch [0:DEPTH-1];
  logic [kcmu_pkg::KCMU_HEAD_BUDGET_W-1:0] q_head_budget_class [0:DEPTH-1];
  logic [SCORE_W-1:0] q_query_relevance [0:DEPTH-1];
  logic [kcmu_pkg::KCMU_COST_CLASS_W-1:0] q_compression_risk [0:DEPTH-1];
  logic [kcmu_pkg::KCMU_COST_CLASS_W-1:0] q_spill_cost [0:DEPTH-1];
  logic [SCORE_W-1:0] q_service_criticality [0:DEPTH-1];
  logic               q_policy_select_s5 [0:DEPTH-1];
  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] q_temporal_persist_class [0:DEPTH-1];
  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] q_reuse_distance_class [0:DEPTH-1];
  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] q_query_structure_class [0:DEPTH-1];
  logic [kcmu_pkg::KCMU_SCHED_HINT_W-1:0] q_sched_urgency_hint [0:DEPTH-1];
  logic               q_sig_valid [0:DEPTH-1];
  logic [5:0]         q_query_sig [0:DEPTH-1];
  logic [5:0]         q_key_sig [0:DEPTH-1];
  logic [1:0]         q_prefix_class [0:DEPTH-1];
  logic [1:0]         q_router_class [0:DEPTH-1];
  logic               q_block_last [0:DEPTH-1];
  logic [LVL_W-1:0]   q_count;
  logic [31:0]        stat_cmdq_lookahead_eval_cnt;
  logic [31:0]        stat_cmdq_lookahead_emit_cnt;
  logic [31:0]        stat_cmdq_lookahead_queue_cnt;
  logic [31:0]        stat_cmdq_lookahead_incoming_cnt;
  logic [31:0]        stat_cmdq_lookahead_barrier_cnt;
  logic [31:0]        stat_cmdq_lookahead_diff_stride_cnt;
  logic [31:0]        stat_cmdq_lookahead_same_stride_cnt;
  logic [31:0]        stat_cmdq_lookahead_same_stride_skip_cnt;
  logic [31:0]        stat_cmdq_descriptor_target_cnt;
  logic [31:0]        stat_cmdq_descriptor_target_high_cnt;
  logic [7:0]         desc_target_q1_hist;
  logic [3:0]         desc_target_q1_density;
  logic               desc_target_use_high_delta;
  logic               desc_target_tiny_cvr16_restore_v1474;
  logic [5:0]         desc_write_burst_cnt;
  logic               desc_write_burst_high;
  logic               desc_write_burst_long;
  logic               desc_write_burst_very_long;
  logic [1:0]         desc_group_len_cnt;
  logic               desc_prev_multiblock;

  kcmu_op_t           q_op_n [0:DEPTH-1];
  logic [ADDR_W-1:0]  q_addr_n [0:DEPTH-1];
  logic [DATA_W-1:0]  q_wdata_n [0:DEPTH-1];
  logic               q_meta_valid_n [0:DEPTH-1];
  logic [kcmu_pkg::KCMU_SEQ_W-1:0] q_seq_id_n [0:DEPTH-1];
  kcmu_pkg::kcmu_phase_t q_phase_n [0:DEPTH-1];
  kcmu_pkg::kcmu_kv_kind_t q_kv_kind_n [0:DEPTH-1];
  logic [2:0]         q_layer_n [0:DEPTH-1];
  logic [1:0]         q_head_n [0:DEPTH-1];
  logic [11:0]        q_token_n [0:DEPTH-1];
  logic [2:0]         q_prio_n [0:DEPTH-1];
  logic [SCORE_W-1:0] q_score_n [0:DEPTH-1];
  logic               q_attn_valid_n [0:DEPTH-1];
  logic [SCORE_W-1:0] q_attn_score_n [0:DEPTH-1];
  logic [kcmu_pkg::KCMU_ATTN_RANK_W-1:0] q_recent_rank_n [0:DEPTH-1];
  logic [kcmu_pkg::KCMU_TOKEN_BLOCK_W-1:0] q_token_block_id_n [0:DEPTH-1];
  logic [kcmu_pkg::KCMU_ATTN_EPOCH_W-1:0] q_attn_epoch_n [0:DEPTH-1];
  logic [kcmu_pkg::KCMU_HEAD_BUDGET_W-1:0] q_head_budget_class_n [0:DEPTH-1];
  logic [SCORE_W-1:0] q_query_relevance_n [0:DEPTH-1];
  logic [kcmu_pkg::KCMU_COST_CLASS_W-1:0] q_compression_risk_n [0:DEPTH-1];
  logic [kcmu_pkg::KCMU_COST_CLASS_W-1:0] q_spill_cost_n [0:DEPTH-1];
  logic [SCORE_W-1:0] q_service_criticality_n [0:DEPTH-1];
  logic               q_policy_select_s5_n [0:DEPTH-1];
  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] q_temporal_persist_class_n [0:DEPTH-1];
  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] q_reuse_distance_class_n [0:DEPTH-1];
  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] q_query_structure_class_n [0:DEPTH-1];
  logic [kcmu_pkg::KCMU_SCHED_HINT_W-1:0] q_sched_urgency_hint_n [0:DEPTH-1];
  logic               q_sig_valid_n [0:DEPTH-1];
  logic [5:0]         q_query_sig_n [0:DEPTH-1];
  logic [5:0]         q_key_sig_n [0:DEPTH-1];
  logic [1:0]         q_prefix_class_n [0:DEPTH-1];
  logic [1:0]         q_router_class_n [0:DEPTH-1];
  logic               q_block_last_n [0:DEPTH-1];
  logic [LVL_W-1:0]   q_count_n;

  logic [IDX_W-1:0] sel_idx;
  logic [2:0]       sel_class;
  logic [2:0]       cls_i;
  logic             has_write_barrier;
  logic [IDX_W-1:0] write_barrier_idx;
  logic             do_pop;
  logic             do_push;
  logic             bypass_fire;
  logic             lookahead_barrier;
  logic             lookahead_from_queue;
  logic             lookahead_from_incoming;
  logic             lookahead_from_descriptor;
  logic             lookahead_same_stride_candidate;
  logic [ADDR_W:0]  descriptor_delta_ext;
  logic [ADDR_W:0]  descriptor_target_ext;
  logic [ADDR_W-1:0] out_addr_sel;
  logic [2:0]       out_layer_sel;
  logic [1:0]       out_head_sel;
  kcmu_pkg::kcmu_kv_kind_t out_kv_kind_sel;
  integer           qi;
  integer           qj;

  function automatic logic [2:0] entry_class(
    input kcmu_op_t      op,
    input logic          meta_valid,
    input logic [2:0]    layer,
    input logic [1:0]    head,
    input logic [11:0]   token,
    input logic [2:0]    prio
  );
    logic [2:0] c;
    begin
      c = 3'd0;
      if (op == KCMU_OP_RD) begin
        c = 3'd1;
      end
      if (meta_valid) begin
        if (layer <= 3'd1 && c < 3'd7) begin
          c = c + 3'd1;
        end
        if (head == 2'd0 && c < 3'd7) begin
          c = c + 3'd1;
        end
        if ((token[2:0] >= 3'd5) && c < 3'd7) begin
          c = c + 3'd1;
        end
      end
      if (prio >= 3'd6 && c < 3'd7) begin
        c = c + 3'd1;
      end
      entry_class = c;
    end
  endfunction

  function automatic logic addr_within_delta(
    input logic [ADDR_W-1:0] a,
    input logic [ADDR_W-1:0] b
  );
    logic [ADDR_W:0] diff_ab;
    logic [ADDR_W:0] diff_ba;
    begin
      diff_ab = {1'b0, a} - {1'b0, b};
      diff_ba = {1'b0, b} - {1'b0, a};
      if (a >= b) begin
        addr_within_delta = (diff_ab != {(ADDR_W+1){1'b0}}) &&
                            (diff_ab <= (ADDR_W+1)'(LOOKAHEAD_MAX_DELTA));
      end else begin
        addr_within_delta = (diff_ba != {(ADDR_W+1){1'b0}}) &&
                            (diff_ba <= (ADDR_W+1)'(LOOKAHEAD_MAX_DELTA));
      end
    end
  endfunction

  function automatic logic addr_is_default_next(
    input logic [ADDR_W-1:0] a,
    input logic [ADDR_W-1:0] b
  );
    begin
      addr_is_default_next = ({1'b0, a} == ({1'b0, b} + {{ADDR_W{1'b0}}, 1'b1}));
    end
  endfunction

  function automatic logic descriptor_target_ok(
    input kcmu_pkg::kcmu_op_t op_i,
    input logic meta_valid_i,
    input logic block_last_i,
    input logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] query_structure_i,
    input logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] temporal_persist_i,
    input logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] reuse_distance_i,
    input logic kv_kind_i,
    input logic [SCORE_W-1:0] query_relevance_i,
    input logic prev_multiblock_i
  );
    logic descriptor_class_ok;
    begin
`ifdef KCMU_CFG_FPGA_KILOSCORE_ULTRA_HH_BRAKE_EXTRA_CVR_V706
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_STRICT_HH_BRAKE_EXTRA_CVR_V705
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_DENSE_LATCH_THRESHOLD_EXTRA_CVR_V704
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_PHASE_THRESHOLD_EXTRA_CVR_V703
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_WINDOW_DENSE_PHASE_TINY_EXTRA_CVR_V702
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_WINDOW_DENSE_PHASE_EXTRA_CVR_V701
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_DENSE_PHASE_SHORT_EXTRA_CVR_V700
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_DENSE_PHASE_EXTRA_CVR_V699
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_FARSCAN_ESCAPE_EXTRA_CVR_V698
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_ESCAPE_EXTRA_CVR_V697
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_PROFILEBUCKET_SATGUARD_EXTRA_CVR_V696
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_PROFILEBUCKET_WRITEGUARD_EXTRA_CVR_V695
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_BP_QREL_CAPBRAKE_TARGET_DEBT_DESC_TARGET_EXTRA_CVR_V641
      descriptor_class_ok =
        ((query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (query_relevance_i >= SCORE_W'(8'h70))) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_PRESSURE_CAPBRAKE_TARGET_DEBT_DESC_TARGET_EXTRA_CVR_V640
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_CAPBRAKE_TARGET_DEBT_DESC_TARGET_EXTRA_CVR_V639
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_TARGET_DEBT_DESC_TARGET_EXTRA_CVR_V638
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_SIGRISK_GF_DESC_RESTORE_V811
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_ONLY_V812
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_DEBT_BALANCED_V820
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_DEBT_STRICT_V819
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_DEBT_BRAKE_V818
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_POLICY_D1D2_WRBURST30_D2_V829
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_POLICY_D1D2_WRBURST_STRUCTSPLIT_V828
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_POLICY_D1D2_WRBURST_BLOCK_V827
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_POLICY_D1D2_WRBURST_D2_V826
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_POLICY_D1D2_ROIGUARD_V825
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_POLICY_D1D2_V824
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_ADAPT_D2D4_V823
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_D3_V822
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_D1_V821
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_D2_V813
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_Q1_V814
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_QREL_V815
      descriptor_class_ok =
        ((query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (query_relevance_i >= SCORE_W'(8'h70))) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_HIGHONLY_V816
      descriptor_class_ok =
        (query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
        (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
        (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
        (kv_kind_i == 1'b0);
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_QREL_HIGHSTRICT_V817
      descriptor_class_ok =
        ((query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (query_relevance_i >= SCORE_W'(8'h70))) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_NSA_LENSAFE_DESC_TARGET_EXTRA_CVR_V637
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0) &&
         prev_multiblock_i);
`elsif KCMU_CFG_FPGA_KILOSCORE_NSA_KV0_DESC_TARGET_EXTRA_CVR_V636
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
         (kv_kind_i == 1'b0));
`elsif KCMU_CFG_FPGA_KILOSCORE_NSA_DESC_TARGET_EXTRA_CVR_V635
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
        ((query_structure_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
         (temporal_persist_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
         (reuse_distance_i >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)));
`else
      descriptor_class_ok =
        (query_structure_i == kcmu_pkg::KCMU_DESC_CLASS_W'(1));
`endif
      descriptor_target_ok =
        DESC_TARGET_EN &&
        (op_i == KCMU_OP_RD) &&
        meta_valid_i &&
        block_last_i &&
        descriptor_class_ok;
    end
  endfunction

  function automatic logic [3:0] popcount8(
    input logic [7:0] v
  );
    begin
      popcount8 =
        {3'b000, v[0]} + {3'b000, v[1]} +
        {3'b000, v[2]} + {3'b000, v[3]} +
        {3'b000, v[4]} + {3'b000, v[5]} +
        {3'b000, v[6]} + {3'b000, v[7]};
    end
  endfunction

  always @(*) begin
    sel_idx = {IDX_W{1'b0}};
    sel_class = 3'd0;
    has_write_barrier = 1'b0;
    write_barrier_idx = {IDX_W{1'b0}};
    if (REORDER_EN) begin
      for (qi = 0; qi < DEPTH; qi = qi + 1) begin
        if (!has_write_barrier && (qi < q_count) && (q_op[qi] == KCMU_OP_WR)) begin
          has_write_barrier = 1'b1;
          write_barrier_idx = qi[IDX_W-1:0];
        end
      end
      for (qi = 0; qi < DEPTH; qi = qi + 1) begin
        if ((qi < q_count) && (!has_write_barrier || (qi <= write_barrier_idx))) begin
          cls_i = entry_class(
            q_op[qi],
            q_meta_valid[qi],
            q_layer[qi],
            q_head[qi],
            q_token[qi],
            q_prio[qi]
          );
          if ((qi == 0) || (cls_i > sel_class)) begin
            sel_class = cls_i;
            sel_idx = qi[IDX_W-1:0];
          end
        end
      end
    end
  end

  assign out_valid = (q_count != LVL_W'(0)) || ((q_count == LVL_W'(0)) && in_valid);
  assign in_ready  = (q_count < LVL_W'(DEPTH)) || ((q_count == LVL_W'(DEPTH)) && out_ready);
  assign q_level   = q_count;

  assign out_addr_sel = (q_count != LVL_W'(0)) ? q_addr[sel_idx] : in_addr;
  assign out_layer_sel = (q_count != LVL_W'(0)) ? q_layer[sel_idx] : in_layer;
  assign out_head_sel = (q_count != LVL_W'(0)) ? q_head[sel_idx] : in_head;
  assign out_kv_kind_sel = (q_count != LVL_W'(0)) ? q_kv_kind[sel_idx] : in_kv_kind;

  assign out_op         = (q_count != LVL_W'(0)) ? q_op[sel_idx] : in_op;
  assign out_addr       = out_addr_sel;
  assign out_wdata      = (q_count != LVL_W'(0)) ? q_wdata[sel_idx] : in_wdata;
  assign out_meta_valid = (q_count != LVL_W'(0)) ? q_meta_valid[sel_idx] : in_meta_valid;
  assign out_seq_id     = (q_count != LVL_W'(0)) ? q_seq_id[sel_idx] : in_seq_id;
  assign out_phase      = (q_count != LVL_W'(0)) ? q_phase[sel_idx] : in_phase;
  assign out_kv_kind    = (q_count != LVL_W'(0)) ? q_kv_kind[sel_idx] : in_kv_kind;
  assign out_layer      = (q_count != LVL_W'(0)) ? q_layer[sel_idx] : in_layer;
  assign out_head       = (q_count != LVL_W'(0)) ? q_head[sel_idx] : in_head;
  assign out_token      = (q_count != LVL_W'(0)) ? q_token[sel_idx] : in_token;
  assign out_prio       = (q_count != LVL_W'(0)) ? q_prio[sel_idx] : in_prio;
  assign out_score      = (q_count != LVL_W'(0)) ? q_score[sel_idx] : in_score;
  assign out_attn_valid = (q_count != LVL_W'(0)) ? q_attn_valid[sel_idx] : in_attn_valid;
  assign out_attn_score = (q_count != LVL_W'(0)) ? q_attn_score[sel_idx] : in_attn_score;
  assign out_recent_rank = (q_count != LVL_W'(0)) ? q_recent_rank[sel_idx] : in_recent_rank;
  assign out_token_block_id = (q_count != LVL_W'(0)) ? q_token_block_id[sel_idx] : in_token_block_id;
  assign out_attn_epoch = (q_count != LVL_W'(0)) ? q_attn_epoch[sel_idx] : in_attn_epoch;
  assign out_head_budget_class = (q_count != LVL_W'(0)) ? q_head_budget_class[sel_idx] : in_head_budget_class;
  assign out_query_relevance = (q_count != LVL_W'(0)) ? q_query_relevance[sel_idx] : in_query_relevance;
  assign out_compression_risk = (q_count != LVL_W'(0)) ? q_compression_risk[sel_idx] : in_compression_risk;
  assign out_spill_cost = (q_count != LVL_W'(0)) ? q_spill_cost[sel_idx] : in_spill_cost;
  assign out_service_criticality = (q_count != LVL_W'(0)) ? q_service_criticality[sel_idx] : in_service_criticality;
  assign out_policy_select_s5 = (q_count != LVL_W'(0)) ? q_policy_select_s5[sel_idx] : in_policy_select_s5;
  assign out_temporal_persist_class = (q_count != LVL_W'(0)) ? q_temporal_persist_class[sel_idx] : in_temporal_persist_class;
  assign out_reuse_distance_class = (q_count != LVL_W'(0)) ? q_reuse_distance_class[sel_idx] : in_reuse_distance_class;
  assign out_query_structure_class = (q_count != LVL_W'(0)) ? q_query_structure_class[sel_idx] : in_query_structure_class;
  assign out_sched_urgency_hint = (q_count != LVL_W'(0)) ? q_sched_urgency_hint[sel_idx] : in_sched_urgency_hint;
  assign out_sig_valid = (q_count != LVL_W'(0)) ? q_sig_valid[sel_idx] : in_sig_valid;
  assign out_query_sig = (q_count != LVL_W'(0)) ? q_query_sig[sel_idx] : in_query_sig;
  assign out_key_sig = (q_count != LVL_W'(0)) ? q_key_sig[sel_idx] : in_key_sig;
  assign out_prefix_class = (q_count != LVL_W'(0)) ? q_prefix_class[sel_idx] : in_prefix_class;
  assign out_router_class = (q_count != LVL_W'(0)) ? q_router_class[sel_idx] : in_router_class;
  assign out_block_last = (q_count != LVL_W'(0)) ? q_block_last[sel_idx] : in_block_last;
  assign desc_target_q1_density = popcount8(desc_target_q1_hist);
  assign desc_target_use_high_delta =
    DESC_TARGET_ADAPTIVE_EN &&
    (desc_target_q1_density >= DESC_TARGET_DENSITY_TH);
  assign desc_target_tiny_cvr16_restore_v1474 =
`ifdef KCMU_CFG_FPGA_KILOSCORE_SEARCH_TINY_CVR16_DESC_TARGET_RESTORE_V1474
    (L1_LINES <= 8) &&
    (L2_LINES <= 16) &&
    (VB_LINES >= 16) &&
    (GROUP_BUF_LINES <= 2);
`else
    1'b0;
`endif
  logic desc_target_capacity_corridor_restore_v1475;
  logic desc_target_largecap_qstruct_restore_v1479;
  logic desc_target_largecap_q1_hisvc_restore_v1486;
  logic desc_target_largecap_q1_hiqrel_restore_v1487;
  assign desc_target_capacity_corridor_restore_v1475 =
`ifdef KCMU_CFG_FPGA_KILOSCORE_SEARCH_CAPACITY_CORRIDOR_RESTORE_V1475
    (((L1_LINES == 16) && (L2_LINES == 16) && (VB_LINES == 8) &&
      (GROUP_BUF_LINES <= 2)) ||
     ((L1_LINES == 32) && (L2_LINES == 64) && (VB_LINES == 32) &&
      ((GROUP_BUF_LINES == 4) || (GROUP_BUF_LINES == 8))));
`else
    1'b0;
`endif
  assign desc_target_largecap_qstruct_restore_v1479 =
`ifdef KCMU_CFG_FPGA_KILOSCORE_SEARCH_LARGECAP_QSTRUCT_DESC_RESTORE_V1479
    (L1_LINES >= 64) &&
    (L2_LINES >= 128) &&
    (VB_LINES >= 64) &&
    (out_query_structure_class >= kcmu_pkg::KCMU_DESC_CLASS_W'(3));
`else
    1'b0;
`endif
  assign desc_target_largecap_q1_hisvc_restore_v1486 =
`ifdef KCMU_CFG_FPGA_KILOSCORE_SEARCH_LARGECAP_Q1_HISVC_TARGET_RESTORE_V1486
    (L1_LINES >= 64) &&
    (L2_LINES >= 128) &&
    (VB_LINES >= 64) &&
    (out_query_structure_class == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
    (out_service_criticality >= SCORE_W'(8'h80));
`else
    1'b0;
`endif
  assign desc_target_largecap_q1_hiqrel_restore_v1487 =
`ifdef KCMU_CFG_FPGA_KILOSCORE_SEARCH_LARGECAP_Q1_HIQREL_TARGET_RESTORE_V1487
    (L1_LINES >= 64) &&
    (L2_LINES >= 128) &&
    (VB_LINES >= 64) &&
    (out_query_structure_class == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
    (out_query_relevance >= SCORE_W'(8'h78));
`else
    1'b0;
`endif

  always @(*) begin
    out_group_target_valid = 1'b0;
    out_group_target_addr = {ADDR_W{1'b0}};
    lookahead_barrier = 1'b0;
    lookahead_from_queue = 1'b0;
    lookahead_from_incoming = 1'b0;
    lookahead_from_descriptor = 1'b0;
    lookahead_same_stride_candidate = 1'b0;
`ifdef KCMU_CFG_FPGA_KILOSCORE_SEARCH_LARGECAP_Q1_HISVC_D2_V1484
    descriptor_delta_ext = (out_policy_select_s5 && desc_write_burst_high &&
                            desc_write_burst_very_long &&
                            (L1_LINES >= 64) &&
                            (L2_LINES >= 128) &&
                            (VB_LINES >= 64) &&
                            (out_query_structure_class == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
                            (out_service_criticality >= SCORE_W'(8'h80))) ?
      (ADDR_W+1)'(2) :
      ((out_policy_select_s5 && desc_write_burst_high &&
        desc_write_burst_very_long &&
        (out_query_structure_class == kcmu_pkg::KCMU_DESC_CLASS_W'(1))) ?
        (ADDR_W+1)'(3) :
        ((out_policy_select_s5 && desc_write_burst_high) ?
          (ADDR_W+1)'(2) :
          (out_policy_select_s5 ?
            (ADDR_W+1)'(1) :
            (ADDR_W+1)'(2))));
`elsif KCMU_CFG_FPGA_KILOSCORE_SEARCH_LARGECAP_Q1_HISVC_D1_V1485
    descriptor_delta_ext = (out_policy_select_s5 && desc_write_burst_high &&
                            desc_write_burst_very_long &&
                            (L1_LINES >= 64) &&
                            (L2_LINES >= 128) &&
                            (VB_LINES >= 64) &&
                            (out_query_structure_class == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
                            (out_service_criticality >= SCORE_W'(8'h80))) ?
      (ADDR_W+1)'(1) :
      ((out_policy_select_s5 && desc_write_burst_high &&
        desc_write_burst_very_long &&
        (out_query_structure_class == kcmu_pkg::KCMU_DESC_CLASS_W'(1))) ?
        (ADDR_W+1)'(3) :
        ((out_policy_select_s5 && desc_write_burst_high) ?
          (ADDR_W+1)'(2) :
          (out_policy_select_s5 ?
            (ADDR_W+1)'(1) :
            (ADDR_W+1)'(2))));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_MIDBURST_Q1_BRAKE_VLONG_D3_V860
    // v860: keep the v856 mid-burst q1/local target brake, but use the
    // v859 positive signal only in the very-long descriptor burst phase.
    descriptor_delta_ext = (out_policy_select_s5 && desc_write_burst_high &&
                            desc_write_burst_very_long &&
                            (out_query_structure_class == kcmu_pkg::KCMU_DESC_CLASS_W'(1))) ?
      (ADDR_W+1)'(3) :
      ((out_policy_select_s5 && desc_write_burst_high) ?
        (ADDR_W+1)'(2) :
        (out_policy_select_s5 ?
          (ADDR_W+1)'(1) :
          (ADDR_W+1)'(2)));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_MIDBURST_Q1_D1_V858
    // v858: keep the descriptor-target path active, but shorten q1/local
    // targets in the mid-burst phase that v856 identified as risky.  Very
    // long descriptor bursts retain v829's delta-2 behavior.
    descriptor_delta_ext = (out_policy_select_s5 && desc_write_burst_high &&
                            desc_write_burst_long &&
                            !desc_write_burst_very_long &&
                            (out_query_structure_class == kcmu_pkg::KCMU_DESC_CLASS_W'(1))) ?
      (ADDR_W+1)'(1) :
      ((out_policy_select_s5 && desc_write_burst_high) ?
        (ADDR_W+1)'(2) :
        (out_policy_select_s5 ?
          (ADDR_W+1)'(1) :
          (ADDR_W+1)'(2)));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_MIDBURST_Q1_D1_VLONG_D3_V859
    // v859: same mid-burst short target as v858, with a farther q1/local
    // target once the descriptor write burst is very long.
    descriptor_delta_ext = (out_policy_select_s5 && desc_write_burst_high &&
                            desc_write_burst_long &&
                            !desc_write_burst_very_long &&
                            (out_query_structure_class == kcmu_pkg::KCMU_DESC_CLASS_W'(1))) ?
      (ADDR_W+1)'(1) :
      ((out_policy_select_s5 && desc_write_burst_high &&
        desc_write_burst_very_long &&
        (out_query_structure_class == kcmu_pkg::KCMU_DESC_CLASS_W'(1))) ?
        (ADDR_W+1)'(3) :
        ((out_policy_select_s5 && desc_write_burst_high) ?
          (ADDR_W+1)'(2) :
          (out_policy_select_s5 ?
            (ADDR_W+1)'(1) :
            (ADDR_W+1)'(2))));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_Q1SVC_WRBURST30_V842
    descriptor_delta_ext = (out_policy_select_s5 && desc_write_burst_high &&
                            (out_query_structure_class == kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
                            (out_service_criticality >= SCORE_W'(8'hB8))) ?
      (ADDR_W+1)'(2) :
      (out_policy_select_s5 ?
        (ADDR_W+1)'(1) :
        (ADDR_W+1)'(2));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_SVC_WRBURST30_V841
    descriptor_delta_ext = (out_policy_select_s5 && desc_write_burst_high &&
                            (out_service_criticality >= SCORE_W'(8'hB8))) ?
      (ADDR_W+1)'(2) :
      (out_policy_select_s5 ?
        (ADDR_W+1)'(1) :
        (ADDR_W+1)'(2));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_Q1_WRBURST30_V840
    descriptor_delta_ext = (out_policy_select_s5 && desc_write_burst_high &&
                            (out_query_structure_class == kcmu_pkg::KCMU_DESC_CLASS_W'(1))) ?
      (ADDR_W+1)'(2) :
      (out_policy_select_s5 ?
        (ADDR_W+1)'(1) :
        (ADDR_W+1)'(2));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_POLICY_D1D2_WRBURST30_D2_V829
    descriptor_delta_ext = (out_policy_select_s5 && desc_write_burst_high) ?
      (ADDR_W+1)'(2) :
      (out_policy_select_s5 ?
        (ADDR_W+1)'(1) :
        (ADDR_W+1)'(2));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_POLICY_D1D2_WRBURST_STRUCTSPLIT_V828
    descriptor_delta_ext = (out_policy_select_s5 && desc_write_burst_high &&
                            (out_query_structure_class == kcmu_pkg::KCMU_DESC_CLASS_W'(1))) ?
      (ADDR_W+1)'(2) :
      (out_policy_select_s5 ?
        (ADDR_W+1)'(1) :
        (ADDR_W+1)'(2));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_POLICY_D1D2_WRBURST_BLOCK_V827
    descriptor_delta_ext = out_policy_select_s5 ?
      (ADDR_W+1)'(1) :
      (ADDR_W+1)'(2);
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_POLICY_D1D2_WRBURST_D2_V826
    descriptor_delta_ext = (out_policy_select_s5 && desc_write_burst_high) ?
      (ADDR_W+1)'(2) :
      (out_policy_select_s5 ?
        (ADDR_W+1)'(1) :
        (ADDR_W+1)'(2));
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_POLICY_D1D2_ROIGUARD_V825
    descriptor_delta_ext = out_policy_select_s5 ?
      (ADDR_W+1)'(1) :
      (ADDR_W+1)'(2);
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_POLICY_D1D2_V824
    descriptor_delta_ext = out_policy_select_s5 ?
      (ADDR_W+1)'(1) :
      (ADDR_W+1)'(2);
`else
    descriptor_delta_ext = desc_target_use_high_delta ?
      (ADDR_W+1)'(DESC_TARGET_HIGH_DELTA) :
      (ADDR_W+1)'(DESC_TARGET_DELTA);
`endif
    descriptor_target_ext = {1'b0, out_addr_sel} + descriptor_delta_ext;
    if (LOOKAHEAD_TARGET_EN && (q_count > LVL_W'(1))) begin
      for (qj = 0; qj < DEPTH; qj = qj + 1) begin
        if ((qj < q_count) && (qj > sel_idx) && !lookahead_barrier && !out_group_target_valid) begin
          if (q_op[qj] == KCMU_OP_WR) begin
            lookahead_barrier = 1'b1;
          end else if ((q_op[qj] == KCMU_OP_RD) &&
                       (q_kv_kind[qj] == out_kv_kind_sel) &&
                       (q_layer[qj] == out_layer_sel) &&
                       (q_head[qj] == out_head_sel) &&
                       addr_within_delta(q_addr[qj], out_addr_sel)) begin
          if (addr_is_default_next(q_addr[qj], out_addr_sel)) begin
            lookahead_same_stride_candidate = 1'b1;
`ifdef KCMU_CFG_FPGA_H2O_PLUS_SERVICE_CVR_GF_CMDQ_LOOKAHEAD_SAMESTRIDE_V366
            out_group_target_valid = 1'b1;
            out_group_target_addr = q_addr[qj];
            lookahead_from_queue = 1'b1;
`elsif KCMU_CFG_FPGA_KILOSCORE_CMDQ_LOOKAHEAD_GF_V409
            out_group_target_valid = 1'b1;
            out_group_target_addr = q_addr[qj];
            lookahead_from_queue = 1'b1;
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_CMDQ_LOOKAHEAD_V848
            out_group_target_valid = 1'b1;
            out_group_target_addr = q_addr[qj];
            lookahead_from_queue = 1'b1;
`elsif KCMU_CFG_FPGA_H2O_PLUS_SERVICE_CVR_GF_CMDQ_LOOKAHEAD_QUEUEONLY_V367
            out_group_target_valid = 1'b1;
            out_group_target_addr = q_addr[qj];
            lookahead_from_queue = 1'b1;
`endif
          end else begin
`ifndef KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_CMDQ_LOOKAHEAD_V848
            out_group_target_valid = 1'b1;
            out_group_target_addr = q_addr[qj];
            lookahead_from_queue = 1'b1;
`endif
            end
          end
        end
      end
    end
    if (descriptor_target_ok(out_op, out_meta_valid, out_block_last,
                             out_query_structure_class,
                             out_temporal_persist_class,
                             out_reuse_distance_class,
                             out_kv_kind_sel,
                             out_query_relevance,
                             desc_prev_multiblock) &&
        !desc_target_tiny_cvr16_restore_v1474 &&
        !desc_target_capacity_corridor_restore_v1475 &&
        !desc_target_largecap_qstruct_restore_v1479 &&
        !desc_target_largecap_q1_hisvc_restore_v1486 &&
        !desc_target_largecap_q1_hiqrel_restore_v1487 &&
`ifdef KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_LONG_WRBURST_VETO_V853
        !desc_write_burst_long &&
`endif
`ifdef KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_LONG_WRBURST_HIGH_V854
        !(desc_write_burst_long &&
          (out_query_structure_class >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) &&
          (out_kv_kind_sel == 1'b0)) &&
`endif
`ifdef KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_LONG_WRBURST_Q1_V855
        !(desc_write_burst_long &&
          (out_query_structure_class == kcmu_pkg::KCMU_DESC_CLASS_W'(1))) &&
`endif
`ifdef KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_MIDBURST_Q1_BRAKE_V856
        !(desc_write_burst_long &&
          !desc_write_burst_very_long &&
          (out_query_structure_class == kcmu_pkg::KCMU_DESC_CLASS_W'(1))) &&
`endif
`ifdef KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_POLICY_D1D2_WRBURST_BLOCK_V827
        !(out_policy_select_s5 && desc_write_burst_high) &&
`endif
`ifdef KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_POLICY_D1D2_WRBURST_STRUCTSPLIT_V828
        !(out_policy_select_s5 && desc_write_burst_high &&
          (out_query_structure_class >= kcmu_pkg::KCMU_DESC_CLASS_W'(3))) &&
`endif
        !lookahead_barrier && !out_group_target_valid && !descriptor_target_ext[ADDR_W]) begin
      out_group_target_valid = 1'b1;
      out_group_target_addr = descriptor_target_ext[ADDR_W-1:0];
      lookahead_from_descriptor = 1'b1;
    end
    if (LOOKAHEAD_TARGET_EN && (q_count != LVL_W'(0)) && in_valid &&
        !lookahead_barrier && !out_group_target_valid) begin
      if (in_op == KCMU_OP_WR) begin
        lookahead_barrier = 1'b1;
      end else if ((in_op == KCMU_OP_RD) &&
                   (in_kv_kind == out_kv_kind_sel) &&
                   (in_layer == out_layer_sel) &&
                   (in_head == out_head_sel) &&
                   addr_within_delta(in_addr, out_addr_sel)) begin
        if (addr_is_default_next(in_addr, out_addr_sel)) begin
          lookahead_same_stride_candidate = 1'b1;
`ifdef KCMU_CFG_FPGA_H2O_PLUS_SERVICE_CVR_GF_CMDQ_LOOKAHEAD_SAMESTRIDE_V366
          out_group_target_valid = 1'b1;
          out_group_target_addr = in_addr;
          lookahead_from_incoming = 1'b1;
`elsif KCMU_CFG_FPGA_KILOSCORE_CMDQ_LOOKAHEAD_GF_V409
          out_group_target_valid = 1'b1;
          out_group_target_addr = in_addr;
          lookahead_from_incoming = 1'b1;
`elsif KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_CMDQ_LOOKAHEAD_V848
          out_group_target_valid = 1'b1;
          out_group_target_addr = in_addr;
          lookahead_from_incoming = 1'b1;
`endif
        end else begin
`ifndef KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_CMDQ_LOOKAHEAD_V848
          out_group_target_valid = 1'b1;
          out_group_target_addr = in_addr;
          lookahead_from_incoming = 1'b1;
`endif
        end
      end
    end
  end

  always @(*) begin
    for (qi = 0; qi < DEPTH; qi = qi + 1) begin
      q_op_n[qi] = q_op[qi];
      q_addr_n[qi] = q_addr[qi];
      q_wdata_n[qi] = q_wdata[qi];
      q_meta_valid_n[qi] = q_meta_valid[qi];
      q_seq_id_n[qi] = q_seq_id[qi];
      q_phase_n[qi] = q_phase[qi];
      q_kv_kind_n[qi] = q_kv_kind[qi];
      q_layer_n[qi] = q_layer[qi];
      q_head_n[qi] = q_head[qi];
      q_token_n[qi] = q_token[qi];
      q_prio_n[qi] = q_prio[qi];
      q_score_n[qi] = q_score[qi];
      q_attn_valid_n[qi] = q_attn_valid[qi];
      q_attn_score_n[qi] = q_attn_score[qi];
      q_recent_rank_n[qi] = q_recent_rank[qi];
      q_token_block_id_n[qi] = q_token_block_id[qi];
      q_attn_epoch_n[qi] = q_attn_epoch[qi];
      q_head_budget_class_n[qi] = q_head_budget_class[qi];
      q_query_relevance_n[qi] = q_query_relevance[qi];
      q_compression_risk_n[qi] = q_compression_risk[qi];
      q_spill_cost_n[qi] = q_spill_cost[qi];
      q_service_criticality_n[qi] = q_service_criticality[qi];
      q_policy_select_s5_n[qi] = q_policy_select_s5[qi];
      q_temporal_persist_class_n[qi] = q_temporal_persist_class[qi];
      q_reuse_distance_class_n[qi] = q_reuse_distance_class[qi];
      q_query_structure_class_n[qi] = q_query_structure_class[qi];
      q_sched_urgency_hint_n[qi] = q_sched_urgency_hint[qi];
      q_sig_valid_n[qi] = q_sig_valid[qi];
      q_query_sig_n[qi] = q_query_sig[qi];
      q_key_sig_n[qi] = q_key_sig[qi];
      q_prefix_class_n[qi] = q_prefix_class[qi];
      q_router_class_n[qi] = q_router_class[qi];
      q_block_last_n[qi] = q_block_last[qi];
    end
    q_count_n = q_count;

    bypass_fire = (q_count == LVL_W'(0)) && in_valid && out_ready;
    do_pop = (q_count != LVL_W'(0)) && out_ready;
    if (do_pop) begin
      for (qi = 0; qi < DEPTH-1; qi = qi + 1) begin
        if ((qi >= sel_idx) && (qi < (q_count - LVL_W'(1)))) begin
          q_op_n[qi] = q_op[qi+1];
          q_addr_n[qi] = q_addr[qi+1];
          q_wdata_n[qi] = q_wdata[qi+1];
          q_meta_valid_n[qi] = q_meta_valid[qi+1];
          q_seq_id_n[qi] = q_seq_id[qi+1];
          q_phase_n[qi] = q_phase[qi+1];
          q_kv_kind_n[qi] = q_kv_kind[qi+1];
          q_layer_n[qi] = q_layer[qi+1];
          q_head_n[qi] = q_head[qi+1];
          q_token_n[qi] = q_token[qi+1];
          q_prio_n[qi] = q_prio[qi+1];
          q_score_n[qi] = q_score[qi+1];
          q_attn_valid_n[qi] = q_attn_valid[qi+1];
          q_attn_score_n[qi] = q_attn_score[qi+1];
          q_recent_rank_n[qi] = q_recent_rank[qi+1];
          q_token_block_id_n[qi] = q_token_block_id[qi+1];
          q_attn_epoch_n[qi] = q_attn_epoch[qi+1];
          q_head_budget_class_n[qi] = q_head_budget_class[qi+1];
          q_query_relevance_n[qi] = q_query_relevance[qi+1];
          q_compression_risk_n[qi] = q_compression_risk[qi+1];
          q_spill_cost_n[qi] = q_spill_cost[qi+1];
          q_service_criticality_n[qi] = q_service_criticality[qi+1];
          q_policy_select_s5_n[qi] = q_policy_select_s5[qi+1];
          q_temporal_persist_class_n[qi] = q_temporal_persist_class[qi+1];
          q_reuse_distance_class_n[qi] = q_reuse_distance_class[qi+1];
          q_query_structure_class_n[qi] = q_query_structure_class[qi+1];
          q_sched_urgency_hint_n[qi] = q_sched_urgency_hint[qi+1];
          q_sig_valid_n[qi] = q_sig_valid[qi+1];
          q_query_sig_n[qi] = q_query_sig[qi+1];
          q_key_sig_n[qi] = q_key_sig[qi+1];
          q_prefix_class_n[qi] = q_prefix_class[qi+1];
          q_router_class_n[qi] = q_router_class[qi+1];
          q_block_last_n[qi] = q_block_last[qi+1];
        end
      end
      q_op_n[q_count - LVL_W'(1)] = KCMU_OP_NOP;
      q_addr_n[q_count - LVL_W'(1)] = {ADDR_W{1'b0}};
      q_wdata_n[q_count - LVL_W'(1)] = {DATA_W{1'b0}};
      q_meta_valid_n[q_count - LVL_W'(1)] = 1'b0;
      q_seq_id_n[q_count - LVL_W'(1)] = {kcmu_pkg::KCMU_SEQ_W{1'b0}};
      q_phase_n[q_count - LVL_W'(1)] = kcmu_pkg::KCMU_PHASE_PREFILL;
      q_kv_kind_n[q_count - LVL_W'(1)] = kcmu_pkg::KCMU_KV_KIND_K;
      q_layer_n[q_count - LVL_W'(1)] = 3'd0;
      q_head_n[q_count - LVL_W'(1)] = 2'd0;
      q_token_n[q_count - LVL_W'(1)] = 12'd0;
      q_prio_n[q_count - LVL_W'(1)] = 3'd0;
      q_score_n[q_count - LVL_W'(1)] = {SCORE_W{1'b0}};
      q_attn_valid_n[q_count - LVL_W'(1)] = 1'b0;
      q_attn_score_n[q_count - LVL_W'(1)] = {SCORE_W{1'b0}};
      q_recent_rank_n[q_count - LVL_W'(1)] = {kcmu_pkg::KCMU_ATTN_RANK_W{1'b0}};
      q_token_block_id_n[q_count - LVL_W'(1)] = {kcmu_pkg::KCMU_TOKEN_BLOCK_W{1'b0}};
      q_attn_epoch_n[q_count - LVL_W'(1)] = {kcmu_pkg::KCMU_ATTN_EPOCH_W{1'b0}};
      q_head_budget_class_n[q_count - LVL_W'(1)] = {kcmu_pkg::KCMU_HEAD_BUDGET_W{1'b0}};
      q_query_relevance_n[q_count - LVL_W'(1)] = {SCORE_W{1'b0}};
      q_compression_risk_n[q_count - LVL_W'(1)] = {kcmu_pkg::KCMU_COST_CLASS_W{1'b0}};
      q_spill_cost_n[q_count - LVL_W'(1)] = {kcmu_pkg::KCMU_COST_CLASS_W{1'b0}};
      q_service_criticality_n[q_count - LVL_W'(1)] = {SCORE_W{1'b0}};
      q_policy_select_s5_n[q_count - LVL_W'(1)] = 1'b1;
      q_temporal_persist_class_n[q_count - LVL_W'(1)] = {kcmu_pkg::KCMU_DESC_CLASS_W{1'b0}};
      q_reuse_distance_class_n[q_count - LVL_W'(1)] = {kcmu_pkg::KCMU_DESC_CLASS_W{1'b0}};
      q_query_structure_class_n[q_count - LVL_W'(1)] = {kcmu_pkg::KCMU_DESC_CLASS_W{1'b0}};
      q_sched_urgency_hint_n[q_count - LVL_W'(1)] = {kcmu_pkg::KCMU_SCHED_HINT_W{1'b0}};
      q_sig_valid_n[q_count - LVL_W'(1)] = 1'b0;
      q_query_sig_n[q_count - LVL_W'(1)] = 6'd0;
      q_key_sig_n[q_count - LVL_W'(1)] = 6'd0;
      q_prefix_class_n[q_count - LVL_W'(1)] = 2'd0;
      q_router_class_n[q_count - LVL_W'(1)] = 2'd0;
      q_block_last_n[q_count - LVL_W'(1)] = 1'b1;
      q_count_n = q_count - LVL_W'(1);
    end

    do_push = in_valid && !bypass_fire && (q_count_n < LVL_W'(DEPTH));
    if (do_push) begin
      q_op_n[q_count_n] = in_op;
      q_addr_n[q_count_n] = in_addr;
      q_wdata_n[q_count_n] = in_wdata;
      q_meta_valid_n[q_count_n] = in_meta_valid;
      q_seq_id_n[q_count_n] = in_seq_id;
      q_phase_n[q_count_n] = in_phase;
      q_kv_kind_n[q_count_n] = in_kv_kind;
      q_layer_n[q_count_n] = in_layer;
      q_head_n[q_count_n] = in_head;
      q_token_n[q_count_n] = in_token;
      q_prio_n[q_count_n] = in_prio;
      q_score_n[q_count_n] = in_score;
      q_attn_valid_n[q_count_n] = in_attn_valid;
      q_attn_score_n[q_count_n] = in_attn_score;
      q_recent_rank_n[q_count_n] = in_recent_rank;
      q_token_block_id_n[q_count_n] = in_token_block_id;
      q_attn_epoch_n[q_count_n] = in_attn_epoch;
      q_head_budget_class_n[q_count_n] = in_head_budget_class;
      q_query_relevance_n[q_count_n] = in_query_relevance;
      q_compression_risk_n[q_count_n] = in_compression_risk;
      q_spill_cost_n[q_count_n] = in_spill_cost;
      q_service_criticality_n[q_count_n] = in_service_criticality;
      q_policy_select_s5_n[q_count_n] = in_policy_select_s5;
      q_temporal_persist_class_n[q_count_n] = in_temporal_persist_class;
      q_reuse_distance_class_n[q_count_n] = in_reuse_distance_class;
      q_query_structure_class_n[q_count_n] = in_query_structure_class;
      q_sched_urgency_hint_n[q_count_n] = in_sched_urgency_hint;
      q_sig_valid_n[q_count_n] = in_sig_valid;
      q_query_sig_n[q_count_n] = in_query_sig;
      q_key_sig_n[q_count_n] = in_key_sig;
      q_prefix_class_n[q_count_n] = in_prefix_class;
      q_router_class_n[q_count_n] = in_router_class;
      q_block_last_n[q_count_n] = in_block_last;
      q_count_n = q_count_n + LVL_W'(1);
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      q_count <= LVL_W'(0);
      stat_cmdq_lookahead_eval_cnt <= 32'd0;
      stat_cmdq_lookahead_emit_cnt <= 32'd0;
      stat_cmdq_lookahead_queue_cnt <= 32'd0;
      stat_cmdq_lookahead_incoming_cnt <= 32'd0;
      stat_cmdq_lookahead_barrier_cnt <= 32'd0;
      stat_cmdq_lookahead_diff_stride_cnt <= 32'd0;
      stat_cmdq_lookahead_same_stride_cnt <= 32'd0;
      stat_cmdq_lookahead_same_stride_skip_cnt <= 32'd0;
      stat_cmdq_descriptor_target_cnt <= 32'd0;
      stat_cmdq_descriptor_target_high_cnt <= 32'd0;
      desc_target_q1_hist <= 8'd0;
      desc_write_burst_cnt <= 6'd0;
      desc_write_burst_high <= 1'b0;
      desc_write_burst_long <= 1'b0;
      desc_write_burst_very_long <= 1'b0;
      desc_group_len_cnt <= 2'd0;
      desc_prev_multiblock <= 1'b0;
      for (qi = 0; qi < DEPTH; qi = qi + 1) begin
        q_op[qi] <= KCMU_OP_NOP;
        q_addr[qi] <= {ADDR_W{1'b0}};
        q_wdata[qi] <= {DATA_W{1'b0}};
        q_meta_valid[qi] <= 1'b0;
        q_seq_id[qi] <= {kcmu_pkg::KCMU_SEQ_W{1'b0}};
        q_phase[qi] <= kcmu_pkg::KCMU_PHASE_PREFILL;
        q_kv_kind[qi] <= kcmu_pkg::KCMU_KV_KIND_K;
        q_layer[qi] <= 3'd0;
        q_head[qi] <= 2'd0;
        q_token[qi] <= 12'd0;
        q_prio[qi] <= 3'd0;
        q_score[qi] <= {SCORE_W{1'b0}};
        q_attn_valid[qi] <= 1'b0;
        q_attn_score[qi] <= {SCORE_W{1'b0}};
        q_recent_rank[qi] <= {kcmu_pkg::KCMU_ATTN_RANK_W{1'b0}};
        q_token_block_id[qi] <= {kcmu_pkg::KCMU_TOKEN_BLOCK_W{1'b0}};
        q_attn_epoch[qi] <= {kcmu_pkg::KCMU_ATTN_EPOCH_W{1'b0}};
        q_head_budget_class[qi] <= {kcmu_pkg::KCMU_HEAD_BUDGET_W{1'b0}};
        q_query_relevance[qi] <= {SCORE_W{1'b0}};
        q_compression_risk[qi] <= {kcmu_pkg::KCMU_COST_CLASS_W{1'b0}};
        q_spill_cost[qi] <= {kcmu_pkg::KCMU_COST_CLASS_W{1'b0}};
        q_service_criticality[qi] <= {SCORE_W{1'b0}};
        q_policy_select_s5[qi] <= 1'b1;
        q_temporal_persist_class[qi] <= {kcmu_pkg::KCMU_DESC_CLASS_W{1'b0}};
        q_reuse_distance_class[qi] <= {kcmu_pkg::KCMU_DESC_CLASS_W{1'b0}};
        q_query_structure_class[qi] <= {kcmu_pkg::KCMU_DESC_CLASS_W{1'b0}};
        q_sched_urgency_hint[qi] <= {kcmu_pkg::KCMU_SCHED_HINT_W{1'b0}};
        q_sig_valid[qi] <= 1'b0;
        q_query_sig[qi] <= 6'd0;
        q_key_sig[qi] <= 6'd0;
        q_prefix_class[qi] <= 2'd0;
        q_router_class[qi] <= 2'd0;
        q_block_last[qi] <= 1'b1;
      end
    end else begin
      q_count <= q_count_n;
      if ((LOOKAHEAD_TARGET_EN || DESC_TARGET_EN) && out_valid && out_ready && (out_op == KCMU_OP_RD)) begin
        stat_cmdq_lookahead_eval_cnt <= stat_cmdq_lookahead_eval_cnt + 32'd1;
        if (lookahead_barrier) begin
          stat_cmdq_lookahead_barrier_cnt <= stat_cmdq_lookahead_barrier_cnt + 32'd1;
        end
        if (lookahead_same_stride_candidate) begin
          stat_cmdq_lookahead_same_stride_skip_cnt <= stat_cmdq_lookahead_same_stride_skip_cnt + 32'd1;
        end
        if (out_group_target_valid) begin
          stat_cmdq_lookahead_emit_cnt <= stat_cmdq_lookahead_emit_cnt + 32'd1;
          if (lookahead_from_queue) begin
            stat_cmdq_lookahead_queue_cnt <= stat_cmdq_lookahead_queue_cnt + 32'd1;
          end
          if (lookahead_from_incoming) begin
            stat_cmdq_lookahead_incoming_cnt <= stat_cmdq_lookahead_incoming_cnt + 32'd1;
          end
          if (lookahead_from_descriptor) begin
            stat_cmdq_descriptor_target_cnt <= stat_cmdq_descriptor_target_cnt + 32'd1;
            if (desc_target_use_high_delta) begin
              stat_cmdq_descriptor_target_high_cnt <= stat_cmdq_descriptor_target_high_cnt + 32'd1;
            end
          end
          if ({1'b0, out_group_target_addr} != ({1'b0, out_addr_sel} + {{ADDR_W{1'b0}}, 1'b1})) begin
            stat_cmdq_lookahead_diff_stride_cnt <= stat_cmdq_lookahead_diff_stride_cnt + 32'd1;
          end else begin
            stat_cmdq_lookahead_same_stride_cnt <= stat_cmdq_lookahead_same_stride_cnt + 32'd1;
          end
        end
      end
      if (out_valid && out_ready && out_meta_valid && out_block_last) begin
        desc_target_q1_hist <= {
          desc_target_q1_hist[6:0],
          (out_query_structure_class == kcmu_pkg::KCMU_DESC_CLASS_W'(1))
        };
        if (out_op == KCMU_OP_WR) begin
          if (desc_write_burst_cnt != 6'h3f) begin
            desc_write_burst_cnt <= desc_write_burst_cnt + 6'd1;
          end
`ifdef KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_POLICY_D1D2_WRBURST30_D2_V829
          if (desc_write_burst_cnt >= 6'd29) begin
`else
          if (desc_write_burst_cnt >= 6'd33) begin
`endif
            desc_write_burst_high <= 1'b1;
          end
`ifdef KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_LONG_WRBURST_VETO_V853
          if (desc_write_burst_cnt >= 6'd33) begin
            desc_write_burst_long <= 1'b1;
          end
`endif
`ifdef KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_LONG_WRBURST_HIGH_V854
          if (desc_write_burst_cnt >= 6'd33) begin
            desc_write_burst_long <= 1'b1;
          end
`endif
`ifdef KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_LONG_WRBURST_Q1_V855
          if (desc_write_burst_cnt >= 6'd33) begin
            desc_write_burst_long <= 1'b1;
          end
`endif
`ifdef KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_MIDBURST_Q1_BRAKE_V856
          if (desc_write_burst_cnt >= 6'd33) begin
            desc_write_burst_long <= 1'b1;
          end
          if (desc_write_burst_cnt >= 6'd37) begin
            desc_write_burst_very_long <= 1'b1;
          end
`endif
`ifdef KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_MIDBURST_Q1_D1_V858
          if (desc_write_burst_cnt >= 6'd33) begin
            desc_write_burst_long <= 1'b1;
          end
          if (desc_write_burst_cnt >= 6'd37) begin
            desc_write_burst_very_long <= 1'b1;
          end
`endif
`ifdef KCMU_CFG_FPGA_KILOSCORE_DESC_TARGET_MIDBURST_Q1_D1_VLONG_D3_V859
          if (desc_write_burst_cnt >= 6'd33) begin
            desc_write_burst_long <= 1'b1;
          end
          if (desc_write_burst_cnt >= 6'd37) begin
            desc_write_burst_very_long <= 1'b1;
          end
`endif
        end else if (out_op == KCMU_OP_RD) begin
          desc_write_burst_cnt <= 6'd0;
        end
      end
      if (out_valid && out_ready && out_meta_valid && (out_op == KCMU_OP_RD)) begin
        if (out_block_last) begin
          desc_prev_multiblock <= (desc_group_len_cnt != 2'd0);
          desc_group_len_cnt <= 2'd0;
        end else if (desc_group_len_cnt != 2'd3) begin
          desc_group_len_cnt <= desc_group_len_cnt + 2'd1;
        end
      end
      for (qi = 0; qi < DEPTH; qi = qi + 1) begin
        q_op[qi] <= q_op_n[qi];
        q_addr[qi] <= q_addr_n[qi];
        q_wdata[qi] <= q_wdata_n[qi];
        q_meta_valid[qi] <= q_meta_valid_n[qi];
        q_seq_id[qi] <= q_seq_id_n[qi];
        q_phase[qi] <= q_phase_n[qi];
        q_kv_kind[qi] <= q_kv_kind_n[qi];
        q_layer[qi] <= q_layer_n[qi];
        q_head[qi] <= q_head_n[qi];
        q_token[qi] <= q_token_n[qi];
        q_prio[qi] <= q_prio_n[qi];
        q_score[qi] <= q_score_n[qi];
        q_attn_valid[qi] <= q_attn_valid_n[qi];
        q_attn_score[qi] <= q_attn_score_n[qi];
        q_recent_rank[qi] <= q_recent_rank_n[qi];
        q_token_block_id[qi] <= q_token_block_id_n[qi];
        q_attn_epoch[qi] <= q_attn_epoch_n[qi];
        q_head_budget_class[qi] <= q_head_budget_class_n[qi];
        q_query_relevance[qi] <= q_query_relevance_n[qi];
        q_compression_risk[qi] <= q_compression_risk_n[qi];
        q_spill_cost[qi] <= q_spill_cost_n[qi];
        q_service_criticality[qi] <= q_service_criticality_n[qi];
        q_policy_select_s5[qi] <= q_policy_select_s5_n[qi];
        q_temporal_persist_class[qi] <= q_temporal_persist_class_n[qi];
        q_reuse_distance_class[qi] <= q_reuse_distance_class_n[qi];
        q_query_structure_class[qi] <= q_query_structure_class_n[qi];
        q_sched_urgency_hint[qi] <= q_sched_urgency_hint_n[qi];
        q_sig_valid[qi] <= q_sig_valid_n[qi];
        q_query_sig[qi] <= q_query_sig_n[qi];
        q_key_sig[qi] <= q_key_sig_n[qi];
        q_prefix_class[qi] <= q_prefix_class_n[qi];
        q_router_class[qi] <= q_router_class_n[qi];
        q_block_last[qi] <= q_block_last_n[qi];
      end
    end
  end
endmodule

