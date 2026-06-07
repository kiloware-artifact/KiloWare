`timescale 1ns/1ps
// ------------------------------------------------------------
// kcmu_execute.sv
// - kcmu_metadata_ctrl: metadata ownership (tag/valid/score/last + replacement)
// - kcmu_execute: command/prefetch FSM and data movement
// ------------------------------------------------------------

module kcmu_metadata_ctrl #(
  parameter integer ADDR_W     = 8,
  parameter integer LINES      = 4,
  parameter integer SCORE_W    = 8,
  parameter integer TIME_W     = 16,
  parameter integer K_RECENT   = 1,
  parameter bit     H2O_V2_EN  = 1'b1,
  parameter bit     UTILITY_SCORE_REPL_EN = 1'b0,
  parameter bit     QMATCH_RECENT_COLD_TIEBREAK_EN = 1'b0,
  parameter bit     QMATCH_L1_QUERY_SEED_EN = 1'b0,
  parameter bit     QMATCH_L1_KEEP_TIEBREAK_EN = 1'b0,
  parameter integer LINE_IDX_W = (LINES <= 1) ? 1 : $clog2(LINES)
)(
  input  logic                    clk,
  input  logic                    rst_n,

  // lookup interface
  input  logic [ADDR_W-1:0]       lookup_addr,
  output logic                    hit,
  output logic [LINE_IDX_W-1:0]   hit_idx,
  output logic [LINE_IDX_W-1:0]   victim_sel,
  output logic                    victim_sel_is_invalid,
  output logic [ADDR_W-1:0]       victim_addr,
  output logic                    victim_is_lossy,
  output logic                    hit_from_prefetch,
  output logic                    hit_is_lossy,

  // update interface
  input  logic                    access_update_en,
  input  logic                    access_is_hit,
  input  logic                    access_is_prefetch,
  input  logic                    access_is_read,
  input  logic [2:0]              access_qos,
  input  logic                    access_hh_protect,
  input  logic                    access_recent_keep,
  input  logic [1:0]              access_h2o_class,
  input  logic [SCORE_W-1:0]      access_utility_score,
  input  logic [SCORE_W-1:0]      access_query_relevance,
  input  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] access_temporal_persist_class,
  input  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] access_reuse_distance_class,
  input  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] access_query_structure_class,
  input  logic                    access_kv_sibling_keep,
  input  logic [ADDR_W-1:0]       access_addr,
  input  logic [LINE_IDX_W-1:0]   access_hit_idx,
  input  logic [LINE_IDX_W-1:0]   access_victim_idx,
  input  logic                    access_fill_lossy
);
  import kcmu_pkg::*;

`ifdef KCMU_CFG_FPGA_KILOSCORE_TRACE_SHAPE_L1_VALUE_V404
`define KCMU_KILOSCORE_L1_VALUE_ACTIVE
`elsif KCMU_CFG_FPGA_KILOSCORE_L1_WRITEPRESSURE_CVR_FRESH4_V405
`define KCMU_KILOSCORE_L1_VALUE_ACTIVE
`endif

  localparam logic [SCORE_W-1:0] HOT_PROMOTE_TH = SCORE_W'(5);
  localparam logic [SCORE_W-1:0] HOT_DEMOTE_TH  = SCORE_W'(1);
  localparam integer HOT_DEMOTE_MIN_AGE = 8;
  localparam logic [2:0] HOT_INSERT_QOS_TH = 3'd6;
  localparam integer DECAY_LOG2 = 4; // apply global score decay every 2^DECAY_LOG2 updates
  localparam integer HOT_BUDGET = (LINES > 1) ? (LINES - 1) : 1;
`ifdef KCMU_CFG_FPGA_KILOSCORE_NATIVE_STANDALONE
  localparam bit NATIVE_L1_POLICY_EN = 1'b1;
`else
  localparam bit NATIVE_L1_POLICY_EN = 1'b0;
`endif

  // metadata arrays
  logic [ADDR_W-1:0]  tag      [0:LINES-1];
  logic [SCORE_W-1:0] score [0:LINES-1];
  logic [TIME_W-1:0]  last  [0:LINES-1];
  logic [LINES-1:0]   valid;
  logic [LINES-1:0]   tier_hot;
  logic [LINES-1:0]   from_prefetch;
  logic [LINES-1:0]   line_lossy;
  logic [LINES-1:0]   line_lookahead_keep;
  logic [LINES-1:0]   line_recent_useful_probe;
  logic [LINES-1:0]   line_recent_useful_hit;

  // history
  logic [TIME_W-1:0] time_ctr;

  // policy flatten
  logic [LINES*ADDR_W-1:0]  tags_flat;
  logic [LINES*SCORE_W-1:0] score_flat;
  logic [LINES*TIME_W-1:0]  last_flat;

  // policy outputs
  logic                  hit_c;
  logic [LINE_IDX_W-1:0] hit_idx_c;
  logic [LINE_IDX_W-1:0] victim_idx_raw;
  logic                  victim_is_invalid_raw;
  logic [LINE_IDX_W-1:0] victim_sel_c;
  logic                  victim_sel_is_invalid_c;
  logic                  hit_post;
  logic [LINE_IDX_W-1:0] hit_idx_post;
  logic                  hit_from_prefetch_post;
  logic                  hit_is_lossy_post;
  logic [2:0]            access_step;
  logic [SCORE_W-1:0]    hit_score_next;
  logic [TIME_W-1:0]     hit_age;
  logic [2:0]            freq_b;
  logic [2:0]            recency_b;
  logic [4:0]            access_step_w;
  logic                  access_l1_next_use_local;
  logic                  access_l1_next_use_structured;
  logic                  access_l1_next_use_score_boost;
  logic                  access_l1_next_use_hot_seed;
  logic                  access_l1_structured_vip;
  logic                  access_l1_recent_anchor;
  logic                  access_l1_recent_soft_boost;
  logic [1:0]            access_l1_utility_conf_step;
  logic                  access_l1_prefetch_retain;
  logic [1:0]            recent_soft_credit;
  logic [1:0]            l1_roi_credit;
  logic [1:0]            l1_recent_phase_credit;
  logic [1:0]            l1_recent_useful_credit;
`ifdef KCMU_KILOSCORE_L1_VALUE_ACTIVE
  logic [7:0]            ks_l1_read_sat;
  logic [7:0]            ks_l1_write_sat;
  logic [2:0]            ks_l1_value_credit;
  logic                  ks_l1_read_dominant;
  logic                  ks_l1_write_pressure;
  logic                  ks_l1_shape_ready;
  logic                  ks_l1_local_value;
  logic                  ks_l1_high_value;
  logic                  ks_l1_low_value;
  logic                  ks_l1_write_demote;
`endif
  logic                  access_qmatch_like;
  logic                  access_qmatch_recent_cold_common;
  logic                  access_qmatch_l1_seed;
  logic                  access_qmatch_l1_keep;
  logic                  access_recent_cold;
  logic                  promote_to_hot;
  logic                  seed_hot;
  logic                  prefetch_retain_hot_seed;
  logic [LINE_IDX_W-1:0] access_update_idx;
  integer                hot_count;

`ifdef KCMU_ABL_KUS_KV_SIBLING_META_SCORE_V135
  localparam bit L1_LOOKAHEAD_KEEP_REPL_EN = 1'b1;
  localparam bit L1_LOOKAHEAD_STRUCT_REPL_EN = 1'b0;
`elsif KCMU_ABL_KUS_KV_SIBLING_META_KEEP_V134
  localparam bit L1_LOOKAHEAD_KEEP_REPL_EN = 1'b1;
  localparam bit L1_LOOKAHEAD_STRUCT_REPL_EN = 1'b0;
`elsif KCMU_ABL_L1_LOOKAHEAD_STRUCT_VICTIM_V65
  localparam bit L1_LOOKAHEAD_KEEP_REPL_EN = 1'b1;
  localparam bit L1_LOOKAHEAD_STRUCT_REPL_EN = 1'b1;
`elsif KCMU_ABL_L1_LOOKAHEAD_VICTIM_V64
  localparam bit L1_LOOKAHEAD_KEEP_REPL_EN = 1'b1;
  localparam bit L1_LOOKAHEAD_STRUCT_REPL_EN = 1'b0;
`elsif KCMU_KILOSCORE_L1_VALUE_ACTIVE
  localparam bit L1_LOOKAHEAD_KEEP_REPL_EN = 1'b1;
  localparam bit L1_LOOKAHEAD_STRUCT_REPL_EN = 1'b0;
`else
  localparam bit L1_LOOKAHEAD_KEEP_REPL_EN =
    QMATCH_RECENT_COLD_TIEBREAK_EN || QMATCH_L1_KEEP_TIEBREAK_EN;
  localparam bit L1_LOOKAHEAD_STRUCT_REPL_EN = 1'b0;
`endif

`ifdef KCMU_CFG_FPGA_H2O_PLUS_SERVICE_CVR_GF_L1_AGEDECAY_V284
  localparam bit L1_AGE_DECAY_REPL_EN = 1'b1;
`else
  localparam bit L1_AGE_DECAY_REPL_EN = 1'b0;
`endif
  localparam integer L1_AGE_DECAY_TH = 8;
  localparam logic [SCORE_W-1:0] L1_AGE_DECAY_PENALTY = SCORE_W'(4);

  integer             i;

`ifndef SYNTHESIS
  // Simulation-visible counters for H2O explainability.
  logic [31:0] stat_h2o_hot_promote_cnt;
  logic [31:0] stat_h2o_hot_seed_cnt;
  logic [31:0] stat_h2o_hot_demote_cnt;
  logic [31:0] stat_h2o_repl_hot_victim_cnt;
  logic [31:0] stat_h2o_repl_warm_victim_cnt;
  logic [31:0] stat_h2o_alloc_invalid_cnt;
  logic [31:0] stat_h2o_repl_total_cnt;
`endif

  genvar gi;
  generate
    for (gi = 0; gi < LINES; gi = gi + 1) begin : GEN_META_FLAT
      assign tags_flat [gi*ADDR_W  +: ADDR_W ] = tag[gi];
      assign score_flat[gi*SCORE_W +: SCORE_W] = score[gi];
      assign last_flat [gi*TIME_W  +: TIME_W ] = last[gi];
    end
  endgenerate

  kcmu_policy #(
    .ADDR_W(ADDR_W),
    .LINES(LINES),
    .SCORE_W(SCORE_W),
    .TIME_W(TIME_W),
    .K_RECENT(K_RECENT),
    .LOOKAHEAD_KEEP_REPL_EN(L1_LOOKAHEAD_KEEP_REPL_EN),
    .AGE_DECAY_REPL_EN(L1_AGE_DECAY_REPL_EN),
    .AGE_DECAY_TH(L1_AGE_DECAY_TH),
    .AGE_DECAY_PENALTY(L1_AGE_DECAY_PENALTY),
    .LINE_IDX_W(LINE_IDX_W)
  ) u_policy (
    .addr(lookup_addr),
    .valid(valid),
    .tier_hot(tier_hot),
    .lookahead_keep(line_lookahead_keep),
    .tags_flat(tags_flat),
    .score_flat(score_flat),
    .last_flat(last_flat),
    .time_now(time_ctr),
    .hit(hit_c),
    .hit_idx(hit_idx_c),
    .victim_idx(victim_idx_raw),
    .victim_is_invalid(victim_is_invalid_raw)
  );

  // Base victim select from policy (no extra MRU redirection in this timing-first phase).
  always @(*) begin
    victim_sel_c            = victim_idx_raw;
    victim_sel_is_invalid_c = victim_is_invalid_raw;
  end

  // Forward pending metadata write to lookup result so back-to-back requests
  // observe the post-update state without inserting an execution bubble.
  always @(*) begin
    hit_post     = hit_c;
    hit_idx_post = hit_idx_c;
    hit_from_prefetch_post = hit_c ? from_prefetch[hit_idx_c] : 1'b0;
    hit_is_lossy_post = hit_c ? line_lossy[hit_idx_c] : 1'b0;

    if (access_update_en && !access_is_hit) begin
      if (lookup_addr == access_addr) begin
        hit_post     = 1'b1;
        hit_idx_post = access_victim_idx;
        hit_from_prefetch_post = access_is_prefetch;
        hit_is_lossy_post = access_fill_lossy;
      end else if (hit_c && (hit_idx_c == access_victim_idx)) begin
        hit_post     = 1'b0;
        hit_idx_post = {LINE_IDX_W{1'b0}};
        hit_from_prefetch_post = 1'b0;
        hit_is_lossy_post = 1'b0;
      end
    end
  end

  function automatic logic [SCORE_W-1:0] sat_add(
    input logic [SCORE_W-1:0] in,
    input logic [2:0]         addv
  );
    logic [SCORE_W:0] tmp;
    begin
      tmp = {1'b0, in} + {{(SCORE_W-3){1'b0}}, addv};
      if (tmp[SCORE_W]) sat_add = {SCORE_W{1'b1}};
      else              sat_add = tmp[SCORE_W-1:0];
    end
  endfunction

  function automatic logic [2:0] semantic_boost(
    input logic [2:0]        qos,
    input logic              is_prefetch,
    input logic              is_read
  );
    logic [2:0] boost;
    begin
      if (qos >= 3'd6)      boost = 3'd3;
      else if (qos >= 3'd4) boost = 3'd2;
      else if (qos >= 3'd2) boost = 3'd1;
      else                  boost = 3'd0;
      if (is_prefetch && (boost != 3'd0)) boost = boost - 3'd1;
      semantic_boost = boost;
    end
  endfunction

  function automatic logic [2:0] freq_bonus(
    input logic [SCORE_W-1:0] s
  );
    begin
      if (s >= SCORE_W'(8))      freq_bonus = 3'd2;
      else if (s >= SCORE_W'(4)) freq_bonus = 3'd1;
      else                       freq_bonus = 3'd0;
    end
  endfunction

  function automatic logic [2:0] recency_bonus(
    input logic [TIME_W-1:0] age
  );
    begin
      if (age <= TIME_W'(2))      recency_bonus = 3'd2;
      else if (age <= TIME_W'(8)) recency_bonus = 3'd1;
      else                        recency_bonus = 3'd0;
    end
  endfunction

  function automatic logic [SCORE_W-1:0] sat_sub(
    input logic [SCORE_W-1:0] v,
    input logic [2:0]         dec
  );
    begin
      if (v > SCORE_W'(dec)) sat_sub = v - SCORE_W'(dec);
      else                  sat_sub = {SCORE_W{1'b0}};
    end
  endfunction

  assign access_qmatch_recent_cold_common =
    !access_is_prefetch &&
    access_is_read &&
    (access_h2o_class == KCMU_H2O_RECENT_ONLY) &&
    !access_hh_protect &&
    (access_query_relevance < SCORE_W'(8'h80)) &&
    (access_query_structure_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
    (access_reuse_distance_class >= kcmu_pkg::KCMU_DESC_CLASS_W'(2));

  assign access_recent_cold =
    QMATCH_RECENT_COLD_TIEBREAK_EN &&
    access_qmatch_recent_cold_common;

  assign access_update_idx = access_is_hit ? access_hit_idx : access_victim_idx;

  assign access_qmatch_like =
    QMATCH_RECENT_COLD_TIEBREAK_EN &&
    !access_is_prefetch &&
    access_is_read &&
    !access_recent_cold &&
    ((access_query_relevance >= SCORE_W'(8'hB0)) ||
     ((access_query_relevance >= SCORE_W'(8'h80)) &&
      (access_hh_protect ||
       (access_h2o_class == KCMU_H2O_BOTH) ||
       (access_h2o_class == KCMU_H2O_HEAVY_ONLY))) ||
     ((access_query_structure_class >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
      (access_temporal_persist_class >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
      (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1))));

  assign access_qmatch_l1_seed =
    QMATCH_L1_QUERY_SEED_EN &&
    !access_is_prefetch &&
    access_is_read &&
    !access_qmatch_recent_cold_common &&
    (access_query_relevance >= SCORE_W'(8'h40)) &&
    (access_utility_score >= SCORE_W'(8'h40)) &&
    ((access_hh_protect ||
      (access_h2o_class == KCMU_H2O_BOTH) ||
      (access_h2o_class == KCMU_H2O_HEAVY_ONLY)) ||
     ((access_h2o_class == KCMU_H2O_RECENT_ONLY) &&
      (access_query_relevance >= SCORE_W'(8'h80)) &&
      (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1))) ||
     ((access_query_structure_class >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
      (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1))));

  assign access_qmatch_l1_keep =
    QMATCH_L1_KEEP_TIEBREAK_EN &&
    !access_is_prefetch &&
    access_is_read &&
    !access_qmatch_recent_cold_common &&
    (access_utility_score >= SCORE_W'(8'h40)) &&
    (((access_query_relevance >= SCORE_W'(8'h80)) &&
      (access_hh_protect ||
       (access_h2o_class == KCMU_H2O_BOTH) ||
       (access_h2o_class == KCMU_H2O_HEAVY_ONLY) ||
       (access_query_structure_class >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)))) ||
     ((access_query_relevance >= SCORE_W'(8'hA0)) &&
      (access_h2o_class == KCMU_H2O_RECENT_ONLY) &&
      (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1))));

`ifdef KCMU_KILOSCORE_L1_VALUE_ACTIVE
  assign ks_l1_read_dominant =
    ({2'b00, ks_l1_read_sat} >= ({ks_l1_write_sat, 2'b00}));
  assign ks_l1_write_pressure =
    ({1'b0, ks_l1_write_sat} >= {2'b00, ks_l1_read_sat[7:1]});
  assign ks_l1_shape_ready =
    (ks_l1_read_sat >= 8'd24) &&
    (ks_l1_value_credit >= 3'd2) &&
    (ks_l1_read_dominant || !ks_l1_write_pressure);
  assign ks_l1_local_value =
    !access_is_prefetch &&
    access_is_read &&
    (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
    ((access_query_structure_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
     (access_temporal_persist_class >= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) ||
     access_recent_keep);
  assign ks_l1_high_value =
    !access_is_prefetch &&
    access_is_read &&
    (access_hh_protect ||
     (access_h2o_class == KCMU_H2O_BOTH) ||
     (access_h2o_class == KCMU_H2O_HEAVY_ONLY) ||
     (access_utility_score >= SCORE_W'(8'hB8)) ||
     (access_query_relevance >= SCORE_W'(8'hA0)));
  assign ks_l1_low_value =
    !access_is_prefetch &&
    access_is_read &&
    !access_hh_protect &&
    !access_recent_keep &&
    (access_h2o_class != KCMU_H2O_BOTH) &&
    (access_h2o_class != KCMU_H2O_HEAVY_ONLY) &&
    (access_utility_score < SCORE_W'(8'h80)) &&
    (access_query_structure_class == kcmu_pkg::KCMU_DESC_CLASS_W'(0)) &&
    (access_reuse_distance_class >= kcmu_pkg::KCMU_DESC_CLASS_W'(2));
  assign ks_l1_write_demote =
    !access_is_prefetch &&
    !access_is_read &&
    !access_hh_protect &&
    !access_recent_keep;
`endif

`ifdef KCMU_ABL_KUS_KV_SIBLING_META_SCORE_V135
  assign access_l1_next_use_local =
    !access_is_prefetch &&
    access_is_read &&
    access_kv_sibling_keep;
  assign access_l1_next_use_structured = access_l1_next_use_local;
  assign access_l1_next_use_score_boost = access_l1_next_use_local;
  assign access_l1_next_use_hot_seed = 1'b0;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor = 1'b0;
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step = access_l1_next_use_local ? 2'd1 : 2'd0;
`elsif KCMU_ABL_KUS_KV_SIBLING_META_KEEP_V134
  assign access_l1_next_use_local =
    !access_is_prefetch &&
    access_is_read &&
    access_kv_sibling_keep;
  assign access_l1_next_use_structured = access_l1_next_use_local;
  assign access_l1_next_use_score_boost = 1'b0;
  assign access_l1_next_use_hot_seed = 1'b0;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor = 1'b0;
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step = 2'd0;
`elsif KCMU_ABL_L1_STRUCTURED_VIP_V52
  assign access_l1_next_use_local =
    1'b0;
  assign access_l1_next_use_structured =
    !access_is_prefetch &&
    access_is_read &&
    (access_query_structure_class >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
    (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1));
  assign access_l1_next_use_score_boost =
    access_l1_next_use_structured;
  assign access_l1_next_use_hot_seed =
    access_l1_next_use_structured;
  assign access_l1_structured_vip =
    access_l1_next_use_structured;
  assign access_l1_recent_anchor = 1'b0;
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step = 2'd0;
`elsif KCMU_ABL_L1_LOOKAHEAD_STRUCT_VICTIM_V65
  assign access_l1_next_use_local =
    !access_is_prefetch &&
    access_is_read &&
    (access_reuse_distance_class == kcmu_pkg::KCMU_DESC_CLASS_W'(0));
  assign access_l1_next_use_structured =
    access_l1_next_use_local &&
    (access_query_structure_class >= kcmu_pkg::KCMU_DESC_CLASS_W'(1));
  assign access_l1_next_use_score_boost = 1'b0;
  assign access_l1_next_use_hot_seed = 1'b0;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor = 1'b0;
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step = 2'd0;
`elsif KCMU_ABL_L1_LOOKAHEAD_VICTIM_V64
  assign access_l1_next_use_local =
    !access_is_prefetch &&
    access_is_read &&
    (access_reuse_distance_class == kcmu_pkg::KCMU_DESC_CLASS_W'(0));
  assign access_l1_next_use_structured =
    access_l1_next_use_local &&
    (access_query_structure_class >= kcmu_pkg::KCMU_DESC_CLASS_W'(1));
  assign access_l1_next_use_score_boost = 1'b0;
  assign access_l1_next_use_hot_seed = 1'b0;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor = 1'b0;
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step = 2'd0;
`elsif KCMU_ABL_L1_LOOKAHEAD_KEEP_V63
  assign access_l1_next_use_local =
    !access_is_prefetch &&
    access_is_read &&
    (access_reuse_distance_class == kcmu_pkg::KCMU_DESC_CLASS_W'(0));
  assign access_l1_next_use_structured =
    access_l1_next_use_local &&
    (access_query_structure_class >= kcmu_pkg::KCMU_DESC_CLASS_W'(1));
  assign access_l1_next_use_score_boost =
    access_l1_next_use_local;
  assign access_l1_next_use_hot_seed =
    access_l1_next_use_local;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor = 1'b0;
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step =
    access_l1_next_use_local ? 2'd1 : 2'd0;
`elsif KCMU_ABL_SOFT_NSA_TINY_BIAS_V70
  assign access_l1_next_use_local =
    !access_is_prefetch &&
    access_is_read &&
    (access_reuse_distance_class == kcmu_pkg::KCMU_DESC_CLASS_W'(0));
  assign access_l1_next_use_structured =
    !access_is_prefetch &&
    access_is_read &&
    (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1));
  assign access_l1_next_use_score_boost = 1'b0;
  assign access_l1_next_use_hot_seed = 1'b0;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor = 1'b0;
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step =
    access_l1_next_use_structured ? 2'd1 : 2'd0;
`elsif KCMU_ABL_SOFT_NSA_QUERY_SAFE_BIAS_V71
  assign access_l1_next_use_local =
    !access_is_prefetch &&
    access_is_read &&
    (access_reuse_distance_class == kcmu_pkg::KCMU_DESC_CLASS_W'(0));
  assign access_l1_next_use_structured =
    !access_is_prefetch &&
    access_is_read &&
    (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1));
  assign access_l1_next_use_score_boost = 1'b0;
  assign access_l1_next_use_hot_seed = 1'b0;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor = 1'b0;
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step =
    access_l1_next_use_structured ? 2'd1 : 2'd0;
`elsif KCMU_ABL_SOFT_NSA_HH_ONLY_BIAS_V72
  assign access_l1_next_use_local =
    !access_is_prefetch &&
    access_is_read &&
    (access_reuse_distance_class == kcmu_pkg::KCMU_DESC_CLASS_W'(0));
  assign access_l1_next_use_structured =
    !access_is_prefetch &&
    access_is_read &&
    (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1));
  assign access_l1_next_use_score_boost = 1'b0;
  assign access_l1_next_use_hot_seed = 1'b0;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor = 1'b0;
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step =
    access_l1_next_use_structured ? 2'd1 : 2'd0;
`elsif KCMU_ABL_SOFT_NSA_L1_ONLY_BIAS_V73
  assign access_l1_next_use_local =
    !access_is_prefetch &&
    access_is_read &&
    (access_reuse_distance_class == kcmu_pkg::KCMU_DESC_CLASS_W'(0));
  assign access_l1_next_use_structured =
    !access_is_prefetch &&
    access_is_read &&
    (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1));
  assign access_l1_next_use_score_boost = 1'b0;
  assign access_l1_next_use_hot_seed = 1'b0;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor = 1'b0;
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step =
    access_l1_next_use_structured ? 2'd1 : 2'd0;
`elsif KCMU_ABL_SOFT_NSA_SKEW_GUARD_L1_BIAS_V74
  assign access_l1_next_use_local =
    !access_is_prefetch &&
    access_is_read &&
    (access_reuse_distance_class == kcmu_pkg::KCMU_DESC_CLASS_W'(0));
  assign access_l1_next_use_structured =
    !access_is_prefetch &&
    access_is_read &&
    (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
    (access_hh_protect ||
     (access_h2o_class == KCMU_H2O_BOTH) ||
     (access_h2o_class == KCMU_H2O_HEAVY_ONLY) ||
     (access_utility_score >= SCORE_W'(8'hB8)));
  assign access_l1_next_use_score_boost = 1'b0;
  assign access_l1_next_use_hot_seed = 1'b0;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor = 1'b0;
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step =
    access_l1_next_use_structured ? 2'd1 : 2'd0;
`elsif KCMU_ABL_L1_LOCAL_TEMPORAL_BIAS_V75
  assign access_l1_next_use_local =
    !access_is_prefetch &&
    access_is_read &&
    (access_temporal_persist_class >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
    (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
    (access_query_structure_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1));
  assign access_l1_next_use_structured = access_l1_next_use_local;
  assign access_l1_next_use_score_boost = 1'b0;
  assign access_l1_next_use_hot_seed = 1'b0;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor = 1'b0;
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step =
    access_l1_next_use_local ? 2'd1 : 2'd0;
`elsif KCMU_ABL_L1_ROI_CREDIT_BIAS_V76
  assign access_l1_next_use_local =
    !access_is_prefetch &&
    access_is_read &&
    (access_reuse_distance_class == kcmu_pkg::KCMU_DESC_CLASS_W'(0));
  assign access_l1_next_use_structured =
    !access_is_prefetch &&
    access_is_read &&
    (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1));
  assign access_l1_next_use_score_boost = 1'b0;
  assign access_l1_next_use_hot_seed = 1'b0;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor = 1'b0;
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step =
    (access_l1_next_use_structured && (access_is_hit || l1_roi_credit[1])) ? 2'd1 : 2'd0;
`elsif KCMU_ABL_L1_HIT_ROI_BIAS_V77
  assign access_l1_next_use_local =
    !access_is_prefetch &&
    access_is_read &&
    (access_reuse_distance_class == kcmu_pkg::KCMU_DESC_CLASS_W'(0));
  assign access_l1_next_use_structured =
    !access_is_prefetch &&
    access_is_read &&
    (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1));
  assign access_l1_next_use_score_boost = 1'b0;
  assign access_l1_next_use_hot_seed = 1'b0;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor = 1'b0;
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step =
    (access_l1_next_use_structured && access_is_hit) ? 2'd2 : 2'd0;
`elsif KCMU_ABL_L1_RECENT_MISS_ROI_V78
  assign access_l1_next_use_local =
    !access_is_prefetch &&
    access_is_read &&
    (access_h2o_class == KCMU_H2O_RECENT_ONLY) &&
    (access_reuse_distance_class == kcmu_pkg::KCMU_DESC_CLASS_W'(0));
  assign access_l1_next_use_structured =
    !access_is_prefetch &&
    access_is_read &&
    (access_h2o_class == KCMU_H2O_RECENT_ONLY) &&
    (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1));
  assign access_l1_next_use_score_boost = 1'b0;
  assign access_l1_next_use_hot_seed = 1'b0;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor = 1'b0;
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step =
    (access_l1_next_use_structured && !access_is_hit) ? 2'd1 : 2'd0;
`elsif KCMU_ABL_L1_RECENT_PHASE_CREDIT_V79
  assign access_l1_next_use_local =
    !access_is_prefetch &&
    access_is_read &&
    (access_h2o_class == KCMU_H2O_RECENT_ONLY) &&
    (access_reuse_distance_class == kcmu_pkg::KCMU_DESC_CLASS_W'(0));
  assign access_l1_next_use_structured =
    !access_is_prefetch &&
    access_is_read &&
    (access_h2o_class == KCMU_H2O_RECENT_ONLY) &&
    (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1));
  assign access_l1_next_use_score_boost = 1'b0;
  assign access_l1_next_use_hot_seed = 1'b0;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor = 1'b0;
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step =
    (access_l1_next_use_structured && !access_is_hit && l1_recent_phase_credit[1]) ? 2'd1 : 2'd0;
`elsif KCMU_ABL_L1_RECENT_PHASE_QUERY_COLD_V80
  assign access_l1_next_use_local =
    !access_is_prefetch &&
    access_is_read &&
    (access_h2o_class == KCMU_H2O_RECENT_ONLY) &&
    (access_query_structure_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
    (access_reuse_distance_class == kcmu_pkg::KCMU_DESC_CLASS_W'(0));
  assign access_l1_next_use_structured =
    !access_is_prefetch &&
    access_is_read &&
    (access_h2o_class == KCMU_H2O_RECENT_ONLY) &&
    (access_query_structure_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
    (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1));
  assign access_l1_next_use_score_boost = 1'b0;
  assign access_l1_next_use_hot_seed = 1'b0;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor = 1'b0;
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step =
    (access_l1_next_use_structured && !access_is_hit && l1_recent_phase_credit[1]) ? 2'd1 : 2'd0;
`elsif KCMU_CFG_FPGA_H2O_PLUS_SERVICE_CVR_GF_L1_RECENTKEEP_ANCHOR_V287
  assign access_l1_next_use_local =
    !access_is_prefetch &&
    access_is_read &&
    access_recent_keep &&
    (access_reuse_distance_class == kcmu_pkg::KCMU_DESC_CLASS_W'(0));
  assign access_l1_next_use_structured =
    !access_is_prefetch &&
    access_is_read &&
    access_recent_keep &&
    (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1));
  assign access_l1_next_use_score_boost = access_l1_next_use_structured;
  assign access_l1_next_use_hot_seed = access_l1_next_use_structured;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor = access_l1_next_use_structured;
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step = 2'd0;
`elsif KCMU_KILOSCORE_L1_VALUE_ACTIVE
  assign access_l1_next_use_local =
    ks_l1_shape_ready &&
    ks_l1_local_value &&
    !ks_l1_low_value;
  assign access_l1_next_use_structured =
    ks_l1_shape_ready &&
    (ks_l1_local_value || ks_l1_high_value || access_recent_keep) &&
    !ks_l1_low_value;
  assign access_l1_next_use_score_boost =
    access_l1_next_use_structured &&
    (access_is_hit || ks_l1_value_credit[1] || ks_l1_high_value);
  assign access_l1_next_use_hot_seed =
    access_l1_next_use_structured &&
    ks_l1_high_value &&
    (access_is_hit || ks_l1_value_credit[2]);
  assign access_l1_structured_vip =
    access_l1_next_use_structured &&
    ks_l1_high_value &&
    !ks_l1_write_pressure &&
    (access_query_structure_class >= kcmu_pkg::KCMU_DESC_CLASS_W'(1));
  assign access_l1_recent_anchor =
    access_l1_next_use_structured &&
    access_recent_keep &&
    (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1));
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step =
    (access_l1_next_use_structured && ks_l1_high_value &&
     (access_is_hit || ks_l1_value_credit[2])) ? 2'd2 :
    (access_l1_next_use_structured &&
     (ks_l1_local_value || access_recent_keep || ks_l1_value_credit[1])) ? 2'd1 :
    2'd0;
`elsif KCMU_CFG_FPGA_H2O_PLUS_SERVICE_CVR_GF_L1_RECENTKEEP_HITCREDIT_V286
  assign access_l1_next_use_local =
    !access_is_prefetch &&
    access_is_read &&
    access_recent_keep &&
    (access_reuse_distance_class == kcmu_pkg::KCMU_DESC_CLASS_W'(0));
  assign access_l1_next_use_structured =
    !access_is_prefetch &&
    access_is_read &&
    access_recent_keep &&
    (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1));
  assign access_l1_next_use_score_boost = 1'b0;
  assign access_l1_next_use_hot_seed = 1'b0;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor = 1'b0;
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step =
    (access_l1_next_use_structured && !access_is_hit && l1_recent_useful_credit[1]) ? 2'd1 : 2'd0;
`elsif KCMU_CFG_FPGA_H2O_PLUS_SERVICE_CVR_GF_L1_RECENT_HITCREDIT_V285
  assign access_l1_next_use_local =
    !access_is_prefetch &&
    access_is_read &&
    (access_h2o_class == KCMU_H2O_RECENT_ONLY) &&
    (access_reuse_distance_class == kcmu_pkg::KCMU_DESC_CLASS_W'(0));
  assign access_l1_next_use_structured =
    !access_is_prefetch &&
    access_is_read &&
    (access_h2o_class == KCMU_H2O_RECENT_ONLY) &&
    (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1));
  assign access_l1_next_use_score_boost = 1'b0;
  assign access_l1_next_use_hot_seed = 1'b0;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor = 1'b0;
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step =
    (access_l1_next_use_structured && !access_is_hit && l1_recent_useful_credit[1]) ? 2'd1 : 2'd0;
`elsif KCMU_ABL_L1_RECENT_USEFUL_FEEDBACK_V81
  assign access_l1_next_use_local =
    !access_is_prefetch &&
    access_is_read &&
    (LINES <= 4) &&
    (access_h2o_class == KCMU_H2O_RECENT_ONLY) &&
    (access_reuse_distance_class == kcmu_pkg::KCMU_DESC_CLASS_W'(0));
  assign access_l1_next_use_structured =
    !access_is_prefetch &&
    access_is_read &&
    (LINES <= 4) &&
    (access_h2o_class == KCMU_H2O_RECENT_ONLY) &&
    (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1));
  assign access_l1_next_use_score_boost = 1'b0;
  assign access_l1_next_use_hot_seed = 1'b0;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor = 1'b0;
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step =
    (access_l1_next_use_structured && !access_is_hit && l1_recent_useful_credit[1]) ? 2'd1 : 2'd0;
`elsif KCMU_ABL_L1_RECENT_STRICT_FEEDBACK_V82
  assign access_l1_next_use_local =
    !access_is_prefetch &&
    access_is_read &&
    (LINES <= 8) &&
    (access_h2o_class == KCMU_H2O_RECENT_ONLY) &&
    (access_reuse_distance_class == kcmu_pkg::KCMU_DESC_CLASS_W'(0));
  assign access_l1_next_use_structured =
    !access_is_prefetch &&
    access_is_read &&
    (LINES <= 8) &&
    (access_h2o_class == KCMU_H2O_RECENT_ONLY) &&
    (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1));
  assign access_l1_next_use_score_boost = 1'b0;
  assign access_l1_next_use_hot_seed = 1'b0;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor = 1'b0;
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step =
    (access_l1_next_use_structured && !access_is_hit && (l1_recent_useful_credit == 2'd3)) ? 2'd1 : 2'd0;
`elsif KCMU_ABL_QMATCH_RECENT_COLD_TIEBREAK_V200
  assign access_l1_next_use_local = access_qmatch_like;
  assign access_l1_next_use_structured = access_qmatch_like;
  assign access_l1_next_use_score_boost = access_qmatch_like;
  assign access_l1_next_use_hot_seed = 1'b0;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor = 1'b0;
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step = access_qmatch_like ? 2'd1 : 2'd0;
`elsif KCMU_ABL_L1_QUERY_KEEP_SEED_V60
  assign access_l1_next_use_local = 1'b0;
  assign access_l1_next_use_structured = 1'b0;
  assign access_l1_next_use_score_boost = 1'b0;
  assign access_l1_next_use_hot_seed = 1'b0;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor =
    !access_is_prefetch &&
    access_is_read &&
    !access_hh_protect &&
    (access_query_relevance >= SCORE_W'(8'hA8));
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step = access_l1_recent_anchor ? 2'd1 : 2'd0;
`elsif KCMU_ABL_L1_BELADY_KEEP_SEED_V59
  assign access_l1_next_use_local = 1'b0;
  assign access_l1_next_use_structured = 1'b0;
  assign access_l1_next_use_score_boost = 1'b0;
  assign access_l1_next_use_hot_seed = 1'b0;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor =
    !access_is_prefetch &&
    access_is_read &&
    !access_hh_protect &&
    !access_recent_keep &&
    (access_h2o_class == KCMU_H2O_NEITHER) &&
    (access_utility_score >= SCORE_W'(8'hB8));
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step = access_l1_recent_anchor ? 2'd1 : 2'd0;
`elsif KCMU_ABL_L1_UTILITY_RETENTION_V57
  assign access_l1_next_use_local = 1'b0;
  assign access_l1_next_use_structured = 1'b0;
  assign access_l1_next_use_score_boost = 1'b0;
  assign access_l1_next_use_hot_seed = 1'b0;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor = 1'b0;
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step =
    (!access_is_prefetch && access_is_read && (access_utility_score >= SCORE_W'(8'hD8))) ? 2'd2 :
    (!access_is_prefetch && access_is_read && (access_utility_score >= SCORE_W'(8'hB8))) ? 2'd1 :
    2'd0;
`elsif KCMU_ABL_L1_RECENT_SPECIAL_V55
  assign access_l1_next_use_local = 1'b0;
  assign access_l1_next_use_structured = 1'b0;
  assign access_l1_next_use_score_boost = 1'b0;
  assign access_l1_next_use_hot_seed = 1'b0;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor = 1'b0;
  assign access_l1_recent_soft_boost =
    !access_is_prefetch &&
    access_is_read &&
    (access_h2o_class == KCMU_H2O_RECENT_ONLY) &&
    (access_query_structure_class >= kcmu_pkg::KCMU_DESC_CLASS_W'(3));
  assign access_l1_utility_conf_step = 2'd0;
`elsif KCMU_ABL_L1_RECENT_FEEDBACK_V56
  assign access_l1_next_use_local = 1'b0;
  assign access_l1_next_use_structured = 1'b0;
  assign access_l1_next_use_score_boost = 1'b0;
  assign access_l1_next_use_hot_seed = 1'b0;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor = 1'b0;
  assign access_l1_recent_soft_boost =
    !access_is_prefetch &&
    access_is_read &&
    (access_h2o_class == KCMU_H2O_RECENT_ONLY) &&
    recent_soft_credit[1];
  assign access_l1_utility_conf_step = 2'd0;
`elsif KCMU_ABL_L1_RECENT_SOFT_V54
  assign access_l1_next_use_local = 1'b0;
  assign access_l1_next_use_structured = 1'b0;
  assign access_l1_next_use_score_boost = 1'b0;
  assign access_l1_next_use_hot_seed = 1'b0;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor = 1'b0;
  assign access_l1_recent_soft_boost =
    !access_is_prefetch &&
    access_is_read &&
    (access_h2o_class == KCMU_H2O_RECENT_ONLY);
  assign access_l1_utility_conf_step = 2'd0;
`elsif KCMU_ABL_L1_RECENT_SEED_V53
  assign access_l1_next_use_local = 1'b0;
  assign access_l1_next_use_structured = 1'b0;
  assign access_l1_next_use_score_boost = 1'b0;
  assign access_l1_next_use_hot_seed = 1'b0;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor =
    !access_is_prefetch &&
    access_is_read &&
    (access_h2o_class == KCMU_H2O_RECENT_ONLY);
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step = 2'd0;
`elsif KCMU_ABL_L1_NEXT_USE_SCORE_V51
  assign access_l1_next_use_local =
    1'b0;
  assign access_l1_next_use_structured =
    !access_is_prefetch &&
    access_is_read &&
    (access_query_structure_class >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) &&
    (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1));
  assign access_l1_next_use_score_boost =
    access_l1_next_use_local || access_l1_next_use_structured;
  assign access_l1_next_use_hot_seed =
    access_l1_next_use_structured;
  assign access_l1_structured_vip = 1'b0;
  assign access_l1_recent_anchor = 1'b0;
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step = 2'd0;
`else
  assign access_l1_next_use_local =
    access_qmatch_like || access_qmatch_l1_seed || access_qmatch_l1_keep;
  assign access_l1_next_use_structured =
    access_qmatch_like || access_qmatch_l1_seed || access_qmatch_l1_keep;
  assign access_l1_next_use_score_boost = access_qmatch_like || access_qmatch_l1_seed;
  assign access_l1_next_use_hot_seed = access_qmatch_l1_seed;
  assign access_l1_structured_vip =
    access_qmatch_l1_seed &&
    (access_query_structure_class >= kcmu_pkg::KCMU_DESC_CLASS_W'(2));
  assign access_l1_recent_anchor =
    access_qmatch_l1_seed &&
    (access_h2o_class == KCMU_H2O_RECENT_ONLY) &&
    (access_query_relevance >= SCORE_W'(8'h80));
  assign access_l1_recent_soft_boost = 1'b0;
  assign access_l1_utility_conf_step =
    access_qmatch_l1_seed ? 2'd2 :
    (access_qmatch_like ? 2'd1 : 2'd0);
`endif

`ifdef KCMU_ABL_KUS_PREFETCH_RETAIN_V58
  assign access_l1_prefetch_retain =
    access_is_prefetch &&
    (access_qos >= 3'd7) &&
    !access_hh_protect &&
    !access_recent_keep &&
    (access_h2o_class == KCMU_H2O_NEITHER);
`else
  assign access_l1_prefetch_retain = 1'b0;
`endif

  always @(*) begin
    hot_count = 0;
    for (i = 0; i < LINES; i = i + 1) begin
      if (tier_hot[i]) begin
        hot_count = hot_count + 1;
      end
    end

    // H2O scoring: semantic priority + frequency + recency.
    // Keep bucketized bonuses to avoid a deep arithmetic path.
    hit_age = {TIME_W{1'b0}};
    freq_b = 3'd0;
    recency_b = 3'd0;
    access_step_w = 5'd0;
    access_step = 3'd0;
    if (!access_is_prefetch) begin
      if (access_is_hit) begin
        hit_age = time_ctr - last[access_hit_idx];
        freq_b = freq_bonus(score[access_hit_idx]);
        if (H2O_V2_EN || NATIVE_L1_POLICY_EN) begin
          recency_b = recency_bonus(hit_age);
        end
      end
      access_step_w = {2'b00, (access_is_read ? 3'd2 : 3'd1)} +
                      {2'b00, semantic_boost(access_qos, access_is_prefetch, access_is_read)} +
                      {2'b00, freq_b} +
                      {2'b00, recency_b};
      if (H2O_V2_EN || NATIVE_L1_POLICY_EN) begin
        unique case (access_h2o_class)
          KCMU_H2O_BOTH:        access_step_w = access_step_w + 5'd3;
          KCMU_H2O_HEAVY_ONLY:  access_step_w = access_step_w + 5'd2;
          KCMU_H2O_RECENT_ONLY: access_step_w = access_step_w + 5'd1;
          default: begin end
        endcase
        if (access_hh_protect) begin
          access_step_w = access_step_w + 5'd1;
        end
      end
      if (UTILITY_SCORE_REPL_EN) begin
        if (access_utility_score >= SCORE_W'(8'hD8)) begin
          access_step_w = access_step_w + 5'd2;
        end else if (access_utility_score >= SCORE_W'(8'hB8)) begin
          access_step_w = access_step_w + 5'd1;
        end
      end
`ifdef KCMU_CFG_FPGA_KILOSCORE_NATIVE_STANDALONE
      // Native KiloScore intentionally uses a lower hardware-value range than
      // the legacy H2O utility path; feed that range into L1 metadata directly.
      if (!H2O_V2_EN && access_is_read && (LINES >= 64)) begin
        if (access_hh_protect || (access_utility_score >= SCORE_W'(8'h60))) begin
          access_step_w = access_step_w + 5'd2;
        end else if (access_utility_score >= SCORE_W'(8'h40)) begin
          access_step_w = access_step_w + 5'd1;
        end
      end
`endif
      if (access_l1_next_use_score_boost) begin
        if (access_l1_structured_vip) begin
          access_step_w = access_step_w + 5'd5;
        end else if (access_l1_next_use_structured) begin
          access_step_w = access_step_w + 5'd2;
        end else begin
          access_step_w = access_step_w + 5'd1;
        end
      end
      if (access_l1_recent_anchor) begin
        access_step_w = access_step_w + 5'd2;
      end
      if (access_l1_recent_soft_boost) begin
        access_step_w = access_step_w + 5'd1;
      end
      if (access_l1_utility_conf_step != 2'd0) begin
        access_step_w = access_step_w + {3'b000, access_l1_utility_conf_step};
      end
`ifdef KCMU_KILOSCORE_L1_VALUE_ACTIVE
      if (ks_l1_low_value && (access_step_w > 5'd1)) begin
        access_step_w = access_step_w - 5'd2;
      end else if (ks_l1_low_value && (access_step_w != 5'd0)) begin
        access_step_w = access_step_w - 5'd1;
      end
`ifdef KCMU_CFG_FPGA_KILOSCORE_L1_WRITEPRESSURE_CVR_FRESH4_V405
      if (ks_l1_write_demote) begin
        access_step_w = 5'd0;
      end
`endif
      if (ks_l1_write_pressure &&
          !access_is_hit &&
          !ks_l1_high_value &&
          (access_step_w != 5'd0)) begin
        access_step_w = access_step_w - 5'd1;
      end
`endif
`ifdef KCMU_ABL_L1_QUERY_COLD_EVICT_V88
      // Trace-side v88: query-cold lines are disproportionately Belady victims.
      // Apply only a one-step L1 metadata demotion; do not change prefetch,
      // backend ownership, or HAQU/KUS base utility.
      if (access_is_read &&
          (access_query_structure_class == kcmu_pkg::KCMU_DESC_CLASS_W'(0)) &&
          (access_step_w != 5'd0)) begin
        access_step_w = access_step_w - 5'd1;
      end
`endif
      if (access_recent_cold && (access_step_w != 5'd0)) begin
        access_step_w = access_step_w - 5'd1;
      end
      // On miss, lower insertion step to suppress one-touch pollution.
      if ((H2O_V2_EN || NATIVE_L1_POLICY_EN) && !access_is_hit && (access_step_w != 5'd0)) begin
        access_step_w = access_step_w - 5'd1;
      end
      if (access_step_w > 5'd7) begin
        access_step = 3'd7;
      end else begin
        access_step = access_step_w[2:0];
      end
    end
`ifdef KCMU_CFG_FPGA_KILOSCORE_L1_WRITEPRESSURE_CVR_FRESH4_V405
    hit_score_next =
      (ks_l1_write_demote && access_is_hit) ?
        sat_sub(score[access_hit_idx], 3'd2) :
        sat_add(score[access_hit_idx], access_step);
`else
    hit_score_next = sat_add(score[access_hit_idx], access_step);
`endif
    if (H2O_V2_EN) begin
      promote_to_hot = (access_hh_protect ||
                       (access_h2o_class == KCMU_H2O_BOTH) ||
                       (access_h2o_class == KCMU_H2O_HEAVY_ONLY) ||
                       access_l1_recent_anchor ||
                        (hit_score_next >= HOT_PROMOTE_TH)) &&
                       (tier_hot[access_hit_idx] || (hot_count < HOT_BUDGET) ||
                        access_l1_structured_vip);
      seed_hot = ((access_qos >= HOT_INSERT_QOS_TH) ||
                  access_hh_protect ||
                  (access_h2o_class == KCMU_H2O_BOTH) ||
                  (access_h2o_class == KCMU_H2O_HEAVY_ONLY) ||
                  access_l1_recent_anchor ||
                  access_l1_next_use_hot_seed ||
                  (UTILITY_SCORE_REPL_EN &&
                   (access_utility_score >= SCORE_W'(8'hB8)))) &&
                  ((hot_count < HOT_BUDGET) || access_l1_structured_vip);
    end else begin
`ifdef KCMU_CFG_FPGA_KILOSCORE_NATIVE_STANDALONE
      promote_to_hot =
        ((hit_score_next >= HOT_PROMOTE_TH) ||
         access_hh_protect ||
         (access_utility_score >= SCORE_W'(8'h60))) &&
        (tier_hot[access_hit_idx] || (hot_count < HOT_BUDGET));
      seed_hot =
        (access_hh_protect ||
         (access_utility_score >= SCORE_W'(8'h60))) &&
        (hot_count < HOT_BUDGET);
`else
      promote_to_hot = (hit_score_next >= HOT_PROMOTE_TH);
      seed_hot = 1'b0;
`endif
    end
`ifdef KCMU_CFG_FPGA_KILOSCORE_L1_WRITEPRESSURE_CVR_FRESH4_V405
    if (ks_l1_write_demote) begin
      promote_to_hot = 1'b0;
      seed_hot = 1'b0;
    end
`endif
    prefetch_retain_hot_seed =
      access_l1_prefetch_retain &&
      ((hot_count < HOT_BUDGET) || tier_hot[access_victim_idx]);
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      hit       <= 1'b0;
      hit_idx   <= {LINE_IDX_W{1'b0}};
      victim_sel <= {LINE_IDX_W{1'b0}};
      victim_sel_is_invalid <= 1'b1;
      victim_addr <= {ADDR_W{1'b0}};
      victim_is_lossy <= 1'b0;
      hit_from_prefetch <= 1'b0;
      hit_is_lossy <= 1'b0;

      time_ctr  <= {TIME_W{1'b0}};
      valid     <= {LINES{1'b0}};
      tier_hot  <= {LINES{1'b0}};
      recent_soft_credit <= 2'd2;
      l1_roi_credit <= 2'd2;
      l1_recent_phase_credit <= 2'd1;
      l1_recent_useful_credit <= 2'd2;
`ifdef KCMU_KILOSCORE_L1_VALUE_ACTIVE
      ks_l1_read_sat <= 8'd0;
      ks_l1_write_sat <= 8'd0;
      ks_l1_value_credit <= 3'd2;
`endif
      for (i = 0; i < LINES; i = i + 1) begin
        tag[i]   <= {ADDR_W{1'b0}};
        score[i] <= {SCORE_W{1'b0}};
            last[i]  <= {TIME_W{1'b0}};
            from_prefetch[i] <= 1'b0;
            line_lossy[i] <= 1'b0;
            line_lookahead_keep[i] <= 1'b0;
            line_recent_useful_probe[i] <= 1'b0;
            line_recent_useful_hit[i] <= 1'b0;
      end
`ifndef SYNTHESIS
      stat_h2o_hot_promote_cnt <= 32'd0;
      stat_h2o_hot_seed_cnt <= 32'd0;
      stat_h2o_hot_demote_cnt <= 32'd0;
      stat_h2o_repl_hot_victim_cnt <= 32'd0;
      stat_h2o_repl_warm_victim_cnt <= 32'd0;
      stat_h2o_alloc_invalid_cnt <= 32'd0;
      stat_h2o_repl_total_cnt <= 32'd0;
`endif
    end else begin
      // Register lookup results to cut long score->victim->execute timing path.
      hit                 <= hit_post;
      hit_idx             <= hit_idx_post;
      victim_sel          <= victim_sel_c;
      victim_sel_is_invalid <= victim_sel_is_invalid_c;
      victim_addr         <= victim_sel_is_invalid_c ? {ADDR_W{1'b0}} : tag[victim_sel_c];
      victim_is_lossy     <= victim_sel_is_invalid_c ? 1'b0 : line_lossy[victim_sel_c];
      hit_from_prefetch   <= hit_from_prefetch_post;
      hit_is_lossy        <= hit_is_lossy_post;

      if (access_update_en) begin
        time_ctr <= time_ctr + {{(TIME_W-1){1'b0}}, 1'b1};

`ifdef KCMU_ABL_L1_RECENT_FEEDBACK_V56
        if (!access_is_prefetch &&
            access_is_read &&
            (access_h2o_class == KCMU_H2O_RECENT_ONLY)) begin
          if (access_is_hit) begin
            if (recent_soft_credit != 2'd3) begin
              recent_soft_credit <= recent_soft_credit + 2'd1;
            end
          end else if (recent_soft_credit != 2'd0) begin
            recent_soft_credit <= recent_soft_credit - 2'd1;
          end
        end
`endif

`ifdef KCMU_ABL_L1_ROI_CREDIT_BIAS_V76
        if (!access_is_prefetch &&
            access_is_read &&
            (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1))) begin
          if (access_is_hit) begin
            if (l1_roi_credit != 2'd3) begin
              l1_roi_credit <= l1_roi_credit + 2'd1;
            end
          end else if (l1_roi_credit != 2'd0) begin
            l1_roi_credit <= l1_roi_credit - 2'd1;
          end
        end
`endif

`ifdef KCMU_ABL_L1_RECENT_PHASE_CREDIT_V79
        if (!access_is_prefetch &&
            access_is_read &&
            (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1))) begin
          if (access_h2o_class == KCMU_H2O_RECENT_ONLY) begin
            if (l1_recent_phase_credit != 2'd3) begin
              l1_recent_phase_credit <= l1_recent_phase_credit + 2'd1;
            end
          end else if ((access_h2o_class == KCMU_H2O_BOTH) ||
                       (access_h2o_class == KCMU_H2O_HEAVY_ONLY) ||
                       access_hh_protect) begin
            if (l1_recent_phase_credit != 2'd0) begin
              l1_recent_phase_credit <= l1_recent_phase_credit - 2'd1;
            end
          end
        end
`elsif KCMU_ABL_L1_RECENT_PHASE_QUERY_COLD_V80
        if (!access_is_prefetch &&
            access_is_read &&
            (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1))) begin
          if (access_h2o_class == KCMU_H2O_RECENT_ONLY) begin
            if (l1_recent_phase_credit != 2'd3) begin
              l1_recent_phase_credit <= l1_recent_phase_credit + 2'd1;
            end
          end else if ((access_h2o_class == KCMU_H2O_BOTH) ||
                       (access_h2o_class == KCMU_H2O_HEAVY_ONLY) ||
                       access_hh_protect) begin
            if (l1_recent_phase_credit != 2'd0) begin
              l1_recent_phase_credit <= l1_recent_phase_credit - 2'd1;
            end
          end
        end
`endif

`ifdef KCMU_CFG_FPGA_H2O_PLUS_SERVICE_CVR_GF_L1_RECENTKEEP_HITCREDIT_V286
        if (!access_is_prefetch && access_is_read) begin
          if (access_is_hit) begin
            if (line_recent_useful_probe[access_hit_idx]) begin
              line_recent_useful_hit[access_hit_idx] <= 1'b1;
            end
            if (access_recent_keep &&
                (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
                (l1_recent_useful_credit != 2'd3)) begin
              l1_recent_useful_credit <= l1_recent_useful_credit + 2'd1;
            end
          end else if (valid[access_victim_idx] &&
                       line_recent_useful_probe[access_victim_idx]) begin
            if (line_recent_useful_hit[access_victim_idx]) begin
              if (l1_recent_useful_credit != 2'd3) begin
                l1_recent_useful_credit <= l1_recent_useful_credit + 2'd1;
              end
            end else if (l1_recent_useful_credit != 2'd0) begin
              l1_recent_useful_credit <= l1_recent_useful_credit - 2'd1;
            end
          end
        end
`elsif KCMU_KILOSCORE_L1_VALUE_ACTIVE
        if (!access_is_prefetch) begin
          if (access_is_read) begin
            if (ks_l1_read_sat != 8'hff) begin
              ks_l1_read_sat <= ks_l1_read_sat + 8'd1;
            end
            if (access_is_hit && (ks_l1_local_value || ks_l1_high_value)) begin
              if (ks_l1_value_credit != 3'd7) begin
                ks_l1_value_credit <= ks_l1_value_credit + 3'd1;
              end
            end else if ((!access_is_hit && ks_l1_low_value) ||
                         (valid[access_victim_idx] &&
                          line_recent_useful_probe[access_victim_idx] &&
                          !line_recent_useful_hit[access_victim_idx])) begin
              if (ks_l1_value_credit != 3'd0) begin
                ks_l1_value_credit <= ks_l1_value_credit - 3'd1;
              end
            end
          end else begin
            if (ks_l1_write_sat != 8'hff) begin
              ks_l1_write_sat <= ks_l1_write_sat + 8'd1;
            end
            if (ks_l1_value_credit != 3'd0) begin
              ks_l1_value_credit <= ks_l1_value_credit - 3'd1;
            end
          end
        end
`elsif KCMU_CFG_FPGA_H2O_PLUS_SERVICE_CVR_GF_L1_RECENT_HITCREDIT_V285
        if (!access_is_prefetch && access_is_read) begin
          if (access_is_hit) begin
            if (line_recent_useful_probe[access_hit_idx]) begin
              line_recent_useful_hit[access_hit_idx] <= 1'b1;
            end
            if ((access_h2o_class == KCMU_H2O_RECENT_ONLY) &&
                (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
                (l1_recent_useful_credit != 2'd3)) begin
              l1_recent_useful_credit <= l1_recent_useful_credit + 2'd1;
            end
          end else if (valid[access_victim_idx] &&
                       line_recent_useful_probe[access_victim_idx]) begin
            if (line_recent_useful_hit[access_victim_idx]) begin
              if (l1_recent_useful_credit != 2'd3) begin
                l1_recent_useful_credit <= l1_recent_useful_credit + 2'd1;
              end
            end else if (l1_recent_useful_credit != 2'd0) begin
              l1_recent_useful_credit <= l1_recent_useful_credit - 2'd1;
            end
          end
        end
`elsif KCMU_ABL_L1_RECENT_USEFUL_FEEDBACK_V81
        if (!access_is_prefetch && access_is_read) begin
          if (access_is_hit) begin
            if (line_recent_useful_probe[access_hit_idx]) begin
              line_recent_useful_hit[access_hit_idx] <= 1'b1;
              if (l1_recent_useful_credit != 2'd3) begin
                l1_recent_useful_credit <= l1_recent_useful_credit + 2'd1;
              end
            end
          end else if (valid[access_victim_idx] &&
                       line_recent_useful_probe[access_victim_idx]) begin
            if (line_recent_useful_hit[access_victim_idx]) begin
              if (l1_recent_useful_credit != 2'd3) begin
                l1_recent_useful_credit <= l1_recent_useful_credit + 2'd1;
              end
            end else if (l1_recent_useful_credit != 2'd0) begin
              l1_recent_useful_credit <= l1_recent_useful_credit - 2'd1;
            end
          end
        end
`elsif KCMU_ABL_L1_RECENT_STRICT_FEEDBACK_V82
        if (!access_is_prefetch && access_is_read) begin
          if (access_is_hit) begin
            if (line_recent_useful_probe[access_hit_idx]) begin
              line_recent_useful_hit[access_hit_idx] <= 1'b1;
            end
            if ((access_h2o_class == KCMU_H2O_RECENT_ONLY) &&
                (access_reuse_distance_class <= kcmu_pkg::KCMU_DESC_CLASS_W'(1)) &&
                (l1_recent_useful_credit != 2'd3)) begin
              l1_recent_useful_credit <= l1_recent_useful_credit + 2'd1;
            end
          end else if (valid[access_victim_idx] &&
                       line_recent_useful_probe[access_victim_idx]) begin
            if (line_recent_useful_hit[access_victim_idx]) begin
              if (l1_recent_useful_credit != 2'd3) begin
                l1_recent_useful_credit <= l1_recent_useful_credit + 2'd1;
              end
            end else if (l1_recent_useful_credit != 2'd0) begin
              l1_recent_useful_credit <= l1_recent_useful_credit - 2'd1;
            end
          end
        end
`endif

        // Global score decay keeps history bounded and allows hot->warm demotion.
        if ((H2O_V2_EN || NATIVE_L1_POLICY_EN) &&
            (time_ctr[DECAY_LOG2-1:0] == {DECAY_LOG2{1'b1}})) begin
          for (i = 0; i < LINES; i = i + 1) begin
            if (score[i] != {SCORE_W{1'b0}}) begin
              score[i] <= score[i] - {{(SCORE_W-1){1'b0}}, 1'b1};
            end
            if (tier_hot[i] &&
                (score[i] <= HOT_DEMOTE_TH) &&
                ((time_ctr - last[i]) >= TIME_W'(HOT_DEMOTE_MIN_AGE))) begin
              tier_hot[i] <= 1'b0;
`ifndef SYNTHESIS
              stat_h2o_hot_demote_cnt <= stat_h2o_hot_demote_cnt + 32'd1;
`endif
            end
          end
        end

        if (access_is_prefetch) begin
          if (!access_is_hit) begin
            tag[access_victim_idx]   <= access_addr;
            valid[access_victim_idx] <= 1'b1;
            score[access_victim_idx] <= access_l1_prefetch_retain ?
                                         sat_add({SCORE_W{1'b0}}, 3'd3) :
                                         {SCORE_W{1'b0}};
            tier_hot[access_victim_idx] <= prefetch_retain_hot_seed;
            from_prefetch[access_victim_idx] <= 1'b1;
            line_lossy[access_victim_idx] <= access_fill_lossy;
            line_lookahead_keep[access_victim_idx] <= 1'b0;
            line_recent_useful_probe[access_victim_idx] <= 1'b0;
            line_recent_useful_hit[access_victim_idx] <= 1'b0;
            last[access_victim_idx]  <= time_ctr + {{(TIME_W-1){1'b0}}, 1'b1};
          end
        end else begin
          if (access_is_hit) begin
            last[access_hit_idx]  <= time_ctr + {{(TIME_W-1){1'b0}}, 1'b1};
            score[access_hit_idx] <= hit_score_next;
            from_prefetch[access_hit_idx] <= 1'b0;
            line_lookahead_keep[access_hit_idx] <=
              L1_LOOKAHEAD_KEEP_REPL_EN &&
              (L1_LOOKAHEAD_STRUCT_REPL_EN ? access_l1_next_use_structured : access_l1_next_use_local);
            if (!access_is_read) begin
              line_lossy[access_hit_idx] <= 1'b0;
            end
            if (promote_to_hot) begin
              tier_hot[access_hit_idx] <= 1'b1;
            end
          end else begin
            tag[access_victim_idx]   <= access_addr;
            valid[access_victim_idx] <= 1'b1;
            score[access_victim_idx] <= sat_add({SCORE_W{1'b0}}, access_step);
            tier_hot[access_victim_idx] <= seed_hot;
            from_prefetch[access_victim_idx] <= 1'b0;
            line_lossy[access_victim_idx] <= access_fill_lossy;
            line_lookahead_keep[access_victim_idx] <=
              L1_LOOKAHEAD_KEEP_REPL_EN &&
              (L1_LOOKAHEAD_STRUCT_REPL_EN ? access_l1_next_use_structured : access_l1_next_use_local);
            line_recent_useful_probe[access_victim_idx] <=
              access_l1_next_use_structured &&
              l1_recent_useful_credit[1] &&
              (access_l1_utility_conf_step != 2'd0);
            line_recent_useful_hit[access_victim_idx] <= 1'b0;
            last[access_victim_idx]  <= time_ctr + {{(TIME_W-1){1'b0}}, 1'b1};
          end
        end

        for (i = 0; i < LINES; i = i + 1) begin
          if (valid[i] &&
              (tag[i] == access_addr) &&
              (i[LINE_IDX_W-1:0] != access_update_idx)) begin
            valid[i] <= 1'b0;
            score[i] <= {SCORE_W{1'b0}};
            last[i] <= {TIME_W{1'b0}};
            tier_hot[i] <= 1'b0;
            from_prefetch[i] <= 1'b0;
            line_lossy[i] <= 1'b0;
            line_lookahead_keep[i] <= 1'b0;
            line_recent_useful_probe[i] <= 1'b0;
            line_recent_useful_hit[i] <= 1'b0;
          end
        end

`ifndef SYNTHESIS
        if (!access_is_hit) begin
          if (valid[access_victim_idx]) begin
            stat_h2o_repl_total_cnt <= stat_h2o_repl_total_cnt + 32'd1;
            if (tier_hot[access_victim_idx]) begin
              stat_h2o_repl_hot_victim_cnt <= stat_h2o_repl_hot_victim_cnt + 32'd1;
            end else begin
              stat_h2o_repl_warm_victim_cnt <= stat_h2o_repl_warm_victim_cnt + 32'd1;
            end
          end else begin
            stat_h2o_alloc_invalid_cnt <= stat_h2o_alloc_invalid_cnt + 32'd1;
          end
          if (!access_is_prefetch && seed_hot) begin
            stat_h2o_hot_seed_cnt <= stat_h2o_hot_seed_cnt + 32'd1;
          end
        end else if (!access_is_prefetch && promote_to_hot && !tier_hot[access_hit_idx]) begin
          stat_h2o_hot_promote_cnt <= stat_h2o_hot_promote_cnt + 32'd1;
        end
`endif
      end
    end
  end

endmodule

`ifdef KCMU_KILOSCORE_L1_VALUE_ACTIVE
`undef KCMU_KILOSCORE_L1_VALUE_ACTIVE
`endif
