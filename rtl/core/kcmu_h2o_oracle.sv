`timescale 1ns/1ps
// ------------------------------------------------------------
// kcmu_h2o_oracle.sv
// Attention/utility oracle with H2O-compatible outputs.
// ------------------------------------------------------------
module kcmu_h2o_oracle #(
  parameter integer SCORE_W = 8,
  parameter integer RECENT_BUDGET = 8,
  parameter integer HH_BUDGET = 8,
  parameter integer HH_COUNT_W = 16,
  parameter bit     HH_EPOCH_DECAY_EN = 1'b0,
  parameter integer HH_DECAY_LOG2 = 3,
  parameter integer HH_DECAY_MAX_SHIFT = 2,
  parameter bit     HH_VALIDATED_PROTECT_EN = 1'b0,
  parameter bit     RECENT_EN = 1'b1,
  parameter bit     HEAVY_HITTER_EN = 1'b1,
  parameter bit     HEAD_ADAPTIVE_EN = 1'b0,
  parameter bit     QUERY_AWARE_EN = 1'b0,
  parameter bit     COST_AWARE_EN = 1'b0,
  parameter bit     BACKEND_CRITICAL_EN = 1'b0,
  parameter logic [SCORE_W-1:0] HH_SCORE_TH = SCORE_W'(8'hC0),
  parameter logic [kcmu_pkg::KCMU_ATTN_RANK_W-1:0] RECENT_RANK_TH = kcmu_pkg::KCMU_ATTN_RANK_W'(3),
  parameter integer UTILITY_ATTN_W = 3,
  parameter integer UTILITY_RECENT_W = 2,
  parameter integer UTILITY_HH_W = 2,
  parameter integer UTILITY_HEAD_W = 2,
  parameter integer UTILITY_QUERY_W = 4,
  parameter integer UTILITY_COMP_W = 1,
  parameter integer UTILITY_SPILL_W = 1,
  parameter bit     UTILITY_SERVICE_HH_EN = 1'b0,
  parameter logic [SCORE_W-1:0] UTILITY_SERVICE_HH_TH = SCORE_W'(8'hB8)
)(
  input  logic clk,
  input  logic rst_n,
  input  logic access_valid,
  input  logic access_ready,
  input  logic access_is_demand,
  input  logic access_meta_valid,
  input  logic access_attn_valid,
  input  logic [SCORE_W-1:0] access_attn_score,
  input  logic [SCORE_W-1:0] access_hh_score_th,
  input  logic [kcmu_pkg::KCMU_ATTN_RANK_W-1:0] access_recent_rank,
  input  logic [kcmu_pkg::KCMU_TOKEN_BLOCK_W-1:0] access_token_block_id,
  input  logic [kcmu_pkg::KCMU_ATTN_EPOCH_W-1:0] access_attn_epoch,
  input  logic [kcmu_pkg::KCMU_HEAD_BUDGET_W-1:0] access_head_budget_class,
  input  logic [SCORE_W-1:0] access_query_relevance,
  input  logic [kcmu_pkg::KCMU_COST_CLASS_W-1:0] access_compression_risk,
  input  logic [kcmu_pkg::KCMU_COST_CLASS_W-1:0] access_spill_cost,
  input  logic [SCORE_W-1:0] access_service_criticality,
  output logic hh_hit,
  output logic hh_protect,
  output logic [SCORE_W-1:0] hh_score,
  output logic recent_keep,
  output kcmu_pkg::kcmu_h2o_class_t h2o_class,
  output logic [SCORE_W-1:0] utility_score,
  output logic [kcmu_pkg::KCMU_HEAD_BUDGET_W-1:0] budget_class,
  output logic compression_guard,
  output logic [2:0] backend_priority_no_service,
  output logic [2:0] backend_priority
);
  import kcmu_pkg::*;

  localparam integer RECENT_IDX_W = (RECENT_BUDGET <= 1) ? 1 : $clog2(RECENT_BUDGET);
  localparam integer HH_IDX_W = (HH_BUDGET <= 1) ? 1 : $clog2(HH_BUDGET);
  localparam integer UTILITY_ACC_W = SCORE_W + 8;
  logic [KCMU_TOKEN_BLOCK_W-1:0] recent_block [0:RECENT_BUDGET-1];
  logic                          recent_valid [0:RECENT_BUDGET-1];
  logic [KCMU_ATTN_EPOCH_W-1:0]  recent_epoch [0:RECENT_BUDGET-1];

  logic [KCMU_TOKEN_BLOCK_W-1:0] hh_block [0:HH_BUDGET-1];
  logic                          hh_valid [0:HH_BUDGET-1];
  logic [HH_COUNT_W-1:0]         hh_accum [0:HH_BUDGET-1];
  logic [HH_COUNT_W-1:0]         hh_accum_eff [0:HH_BUDGET-1];
  logic [KCMU_ATTN_EPOCH_W-1:0]  hh_epoch [0:HH_BUDGET-1];

  logic [31:0] stat_hh_hit_cnt;
  logic [31:0] stat_hh_protect_cnt;
  logic [31:0] stat_recent_keep_cnt;
  logic [31:0] stat_h2o_both_cnt;
  logic [31:0] stat_h2o_recent_only_cnt;
  logic [31:0] stat_h2o_hh_only_cnt;
  logic [31:0] stat_h2o_fallback_cnt;
  logic [31:0] stat_hh_candidate_cnt;
  logic [31:0] stat_hh_candidate_attn_cnt;
  logic [31:0] stat_hh_candidate_query_cnt;
  logic [31:0] stat_hh_candidate_head_cnt;
  logic [31:0] stat_hh_candidate_service_cnt;
  logic [31:0] stat_hh_insert_free_cnt;
  logic [31:0] stat_hh_replace_weak_cnt;
  logic [31:0] stat_hh_reject_weak_cnt;

  logic fire;
  logic recent_found;
  logic [RECENT_IDX_W-1:0] recent_hit_idx;
  logic hh_found;
  logic [HH_IDX_W-1:0] hh_hit_idx;
  logic hh_has_free;
  logic [HH_IDX_W-1:0] hh_free_idx;
  logic [HH_IDX_W-1:0] hh_weak_idx;
  logic [HH_COUNT_W-1:0] hh_weak_score;
  logic hh_candidate;
  logic hh_candidate_attn;
  logic hh_candidate_query;
  logic hh_candidate_head;
  logic service_hh_candidate;
  logic [SCORE_W-1:0] effective_hh_score_th;
  logic [SCORE_W-1:0] effective_query_relevance;
  logic [SCORE_W-1:0] effective_service_criticality;
  integer i;

  function automatic logic [SCORE_W-1:0] sat_score(input integer value_i);
    integer tmp;
    begin
      tmp = value_i;
      if (tmp < 0) tmp = 0;
      if (tmp > ((1 << SCORE_W) - 1)) tmp = ((1 << SCORE_W) - 1);
      sat_score = SCORE_W'(tmp);
    end
  endfunction

  function automatic logic [2:0] sat_prio3(input integer value_i);
    integer tmp;
    begin
      tmp = value_i;
      if (tmp < 0) tmp = 0;
      if (tmp > 7) tmp = 7;
      sat_prio3 = 3'(tmp);
    end
  endfunction

  function automatic logic [SCORE_W-1:0] sat_score_acc(
    input logic signed [UTILITY_ACC_W-1:0] value_i
  );
    begin
      if (value_i < '0) begin
        sat_score_acc = {SCORE_W{1'b0}};
      end else if (value_i > $signed(UTILITY_ACC_W'((1 << SCORE_W) - 1))) begin
        sat_score_acc = {SCORE_W{1'b1}};
      end else begin
        sat_score_acc = value_i[SCORE_W-1:0];
      end
    end
  endfunction

  function automatic logic [2:0] sat_prio3_acc(
    input logic signed [UTILITY_ACC_W-1:0] value_i
  );
    begin
      if (value_i < '0) begin
        sat_prio3_acc = 3'd0;
      end else if (value_i > $signed(UTILITY_ACC_W'(7))) begin
        sat_prio3_acc = 3'd7;
      end else begin
        sat_prio3_acc = value_i[2:0];
      end
    end
  endfunction

  function automatic logic [HH_COUNT_W-1:0] decay_hh_score(
    input logic [HH_COUNT_W-1:0] score_i,
    input logic [KCMU_ATTN_EPOCH_W-1:0] score_epoch_i,
    input logic [KCMU_ATTN_EPOCH_W-1:0] now_epoch_i
  );
    logic [KCMU_ATTN_EPOCH_W-1:0] delta;
    integer delta_i;
    integer shift_i;
    integer base_gap;
    begin
      delta = now_epoch_i - score_epoch_i;
      delta_i = delta;
      shift_i = 0;
      base_gap = (HH_DECAY_LOG2 <= 0) ? 1 : (1 << HH_DECAY_LOG2);
      if (HH_EPOCH_DECAY_EN && (delta_i >= base_gap)) begin
        shift_i = delta_i / base_gap;
        if (shift_i > HH_DECAY_MAX_SHIFT) shift_i = HH_DECAY_MAX_SHIFT;
      end
      decay_hh_score = score_i >> shift_i;
    end
  endfunction

  integer decay_i;
  always @(*) begin
    for (decay_i = 0; decay_i < HH_BUDGET; decay_i = decay_i + 1) begin
      hh_accum_eff[decay_i] = decay_hh_score(hh_accum[decay_i], hh_epoch[decay_i], access_attn_epoch);
    end
  end

  always @(*) begin
    recent_found = 1'b0;
    recent_hit_idx = '0;
    for (i = 0; i < RECENT_BUDGET; i = i + 1) begin
      if (recent_valid[i] && (recent_block[i] == access_token_block_id)) begin
        recent_found = 1'b1;
        recent_hit_idx = RECENT_IDX_W'(i);
      end
    end
  end

  always @(*) begin
    hh_found = 1'b0;
    hh_hit_idx = '0;
    hh_has_free = 1'b0;
    hh_free_idx = '0;
    hh_weak_idx = '0;
    hh_weak_score = {HH_COUNT_W{1'b1}};
    for (i = 0; i < HH_BUDGET; i = i + 1) begin
      if (hh_valid[i] && (hh_block[i] == access_token_block_id)) begin
        hh_found = 1'b1;
        hh_hit_idx = HH_IDX_W'(i);
      end
      if (!hh_valid[i] && !hh_has_free) begin
        hh_has_free = 1'b1;
        hh_free_idx = HH_IDX_W'(i);
      end
      if (!hh_valid[i]) begin
        hh_weak_idx = HH_IDX_W'(i);
        hh_weak_score = '0;
      end else if ((HH_EPOCH_DECAY_EN ? hh_accum_eff[i] : hh_accum[i]) < hh_weak_score) begin
        hh_weak_idx = HH_IDX_W'(i);
        hh_weak_score = HH_EPOCH_DECAY_EN ? hh_accum_eff[i] : hh_accum[i];
      end
    end
  end

  assign fire = access_valid && access_ready && access_is_demand && access_meta_valid;
  assign effective_hh_score_th = access_hh_score_th;
  assign effective_query_relevance = QUERY_AWARE_EN ? access_query_relevance : access_attn_score;
  assign effective_service_criticality = BACKEND_CRITICAL_EN ? access_service_criticality : {SCORE_W{1'b0}};
  assign service_hh_candidate =
    BACKEND_CRITICAL_EN && UTILITY_SERVICE_HH_EN && access_attn_valid &&
    (effective_service_criticality >= UTILITY_SERVICE_HH_TH) &&
    ((access_attn_score >= SCORE_W'(8'h70)) ||
     (effective_query_relevance >= SCORE_W'(8'h70)) ||
     (access_head_budget_class >= kcmu_pkg::KCMU_HEAD_BUDGET_W'(1)));
  assign hh_candidate_attn =
    HEAVY_HITTER_EN && access_attn_valid &&
    (access_attn_score >= effective_hh_score_th);
  assign hh_candidate_query =
    HEAVY_HITTER_EN && access_attn_valid &&
    QUERY_AWARE_EN &&
    (effective_query_relevance >= SCORE_W'(8'hB8)) &&
    ((access_attn_score >= SCORE_W'(8'h88)) ||
     (access_head_budget_class >= kcmu_pkg::KCMU_HEAD_BUDGET_W'(2)));
  assign hh_candidate_head =
    HEAVY_HITTER_EN && access_attn_valid &&
    HEAD_ADAPTIVE_EN &&
    (access_head_budget_class >= kcmu_pkg::KCMU_HEAD_BUDGET_W'(2)) &&
    (access_attn_score >= SCORE_W'(8'h90));
  assign hh_candidate = hh_candidate_attn ||
                        hh_candidate_query ||
                        hh_candidate_head ||
                        service_hh_candidate;
  assign recent_keep = RECENT_EN && access_attn_valid && (recent_found || (access_recent_rank <= RECENT_RANK_TH));
  assign hh_hit = HEAVY_HITTER_EN && access_attn_valid && hh_found;
  assign hh_protect = HEAVY_HITTER_EN && access_attn_valid &&
                      (hh_found || (!HH_VALIDATED_PROTECT_EN && hh_candidate));
  assign hh_score = hh_found ? (HH_EPOCH_DECAY_EN ? hh_accum_eff[hh_hit_idx][SCORE_W-1:0] : hh_accum[hh_hit_idx][SCORE_W-1:0]) :
                     (hh_candidate ? access_attn_score : {SCORE_W{1'b0}});
  assign budget_class = HEAD_ADAPTIVE_EN ? access_head_budget_class : {kcmu_pkg::KCMU_HEAD_BUDGET_W{1'b0}};

  always @(*) begin
    logic signed [UTILITY_ACC_W-1:0] utility_raw;
    logic signed [UTILITY_ACC_W-1:0] backend_raw_no_service;
    logic signed [UTILITY_ACC_W-1:0] backend_raw;
    logic signed [UTILITY_ACC_W-1:0] attn_term;
    logic signed [UTILITY_ACC_W-1:0] recent_term;
    logic signed [UTILITY_ACC_W-1:0] hh_term;
    logic signed [UTILITY_ACC_W-1:0] head_term;
    logic signed [UTILITY_ACC_W-1:0] query_term;
    logic signed [UTILITY_ACC_W-1:0] query_bonus;
    logic signed [UTILITY_ACC_W-1:0] spill_term;
    logic signed [UTILITY_ACC_W-1:0] comp_penalty;
    logic signed [UTILITY_ACC_W-1:0] recent_strength;
    logic signed [UTILITY_ACC_W-1:0] utility_bucket;
    logic signed [UTILITY_ACC_W-1:0] backend_critical_bonus;
    logic signed [UTILITY_ACC_W-1:0] utility_sum;
    recent_strength = recent_keep ?
                      (($signed(UTILITY_ACC_W'(16)) - $signed(UTILITY_ACC_W'(access_recent_rank))) <<< 3) :
                      '0;
    attn_term = $signed(UTILITY_ACC_W'(access_attn_score)) * $signed(UTILITY_ACC_W'(UTILITY_ATTN_W));
    recent_term = recent_strength * $signed(UTILITY_ACC_W'(UTILITY_RECENT_W));
    hh_term = hh_protect ?
              ($signed(UTILITY_ACC_W'(hh_hit ? 24 : 16)) * $signed(UTILITY_ACC_W'(UTILITY_HH_W))) :
              '0;
    head_term = HEAD_ADAPTIVE_EN ?
                ($signed(UTILITY_ACC_W'(access_head_budget_class)) * $signed(UTILITY_ACC_W'(20 * UTILITY_HEAD_W))) :
                '0;
    query_term = QUERY_AWARE_EN ?
                 ($signed(UTILITY_ACC_W'(effective_query_relevance)) * $signed(UTILITY_ACC_W'(UTILITY_QUERY_W))) :
                 '0;
    query_bonus = '0;
    if (QUERY_AWARE_EN) begin
      if (effective_query_relevance >= SCORE_W'(8'hD8)) begin
        query_bonus = $signed(UTILITY_ACC_W'(32));
      end else if (effective_query_relevance >= SCORE_W'(8'hC8)) begin
        query_bonus = $signed(UTILITY_ACC_W'(20));
      end else if ((effective_query_relevance >= SCORE_W'(8'hB8)) &&
                   (recent_keep || (access_head_budget_class >= kcmu_pkg::KCMU_HEAD_BUDGET_W'(2)))) begin
        query_bonus = $signed(UTILITY_ACC_W'(12));
      end
    end
    spill_term = COST_AWARE_EN ?
                 ($signed(UTILITY_ACC_W'(access_spill_cost)) * $signed(UTILITY_ACC_W'(14 * UTILITY_SPILL_W))) :
                 '0;
    comp_penalty = COST_AWARE_EN ?
                   ($signed(UTILITY_ACC_W'(access_compression_risk)) * $signed(UTILITY_ACC_W'(12 * UTILITY_COMP_W))) :
                   '0;

    utility_sum = attn_term +
                  recent_term +
                  hh_term +
                  head_term +
                  query_term +
                  query_bonus +
                  spill_term -
                  comp_penalty +
                  $signed(UTILITY_ACC_W'(4));
    utility_raw = utility_sum >>> 3;
    utility_score = sat_score_acc(utility_raw);

    utility_bucket = utility_raw >>> 5;
    backend_critical_bonus = '0;
    if (BACKEND_CRITICAL_EN) begin
      if (effective_service_criticality >= SCORE_W'(8'hD8)) begin
        backend_critical_bonus = $signed(UTILITY_ACC_W'(5));
      end else if (effective_service_criticality >= SCORE_W'(8'hB8)) begin
        backend_critical_bonus = $signed(UTILITY_ACC_W'(3));
      end else if (effective_service_criticality >= SCORE_W'(8'h90)) begin
        backend_critical_bonus = $signed(UTILITY_ACC_W'(2));
      end
    end
    backend_raw_no_service = utility_bucket +
                             (hh_protect ? $signed(UTILITY_ACC_W'(2)) : '0) +
                             (recent_keep ? $signed(UTILITY_ACC_W'(1)) : '0) +
                             (HEAD_ADAPTIVE_EN ? $signed(UTILITY_ACC_W'(access_head_budget_class)) : '0) +
                             ((QUERY_AWARE_EN && (effective_query_relevance >= SCORE_W'(8'hB8))) ?
                               $signed(UTILITY_ACC_W'(1)) : '0) +
                             (COST_AWARE_EN ? ($signed(UTILITY_ACC_W'(access_spill_cost)) >>> 1) : '0);
    backend_raw = backend_raw_no_service + backend_critical_bonus;
    backend_priority_no_service = sat_prio3_acc(backend_raw_no_service);
    backend_priority = sat_prio3_acc(backend_raw);

    compression_guard = hh_protect ||
                        service_hh_candidate ||
                        (utility_score >= SCORE_W'(8'hB8)) ||
                        (QUERY_AWARE_EN &&
                         ((effective_query_relevance >= SCORE_W'(8'hD8)) ||
                          ((effective_query_relevance >= SCORE_W'(8'hB8)) &&
                           (recent_keep || (access_head_budget_class >= kcmu_pkg::KCMU_HEAD_BUDGET_W'(2))) &&
                           (utility_score >= SCORE_W'(8'hA0))))) ||
                        (HEAD_ADAPTIVE_EN &&
                         (access_head_budget_class >= kcmu_pkg::KCMU_HEAD_BUDGET_W'(3)) &&
                         (utility_score >= SCORE_W'(8'h98))) ||
                        (COST_AWARE_EN &&
                         (access_compression_risk >= kcmu_pkg::KCMU_COST_CLASS_W'(10)) &&
                         ((effective_query_relevance >= SCORE_W'(8'h90)) ||
                          (utility_score >= SCORE_W'(8'hA8))));
  end

  always @(*) begin
    if (!access_attn_valid) begin
      h2o_class = KCMU_H2O_NEITHER;
    end else if (recent_keep && hh_protect) begin
      h2o_class = KCMU_H2O_BOTH;
    end else if (hh_protect) begin
      h2o_class = KCMU_H2O_HEAVY_ONLY;
    end else if (recent_keep) begin
      h2o_class = KCMU_H2O_RECENT_ONLY;
    end else begin
      h2o_class = KCMU_H2O_NEITHER;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    integer j;
    if (!rst_n) begin
      stat_hh_hit_cnt <= 32'd0;
      stat_hh_protect_cnt <= 32'd0;
      stat_recent_keep_cnt <= 32'd0;
      stat_h2o_both_cnt <= 32'd0;
      stat_h2o_recent_only_cnt <= 32'd0;
      stat_h2o_hh_only_cnt <= 32'd0;
      stat_h2o_fallback_cnt <= 32'd0;
      stat_hh_candidate_cnt <= 32'd0;
      stat_hh_candidate_attn_cnt <= 32'd0;
      stat_hh_candidate_query_cnt <= 32'd0;
      stat_hh_candidate_head_cnt <= 32'd0;
      stat_hh_candidate_service_cnt <= 32'd0;
      stat_hh_insert_free_cnt <= 32'd0;
      stat_hh_replace_weak_cnt <= 32'd0;
      stat_hh_reject_weak_cnt <= 32'd0;
      for (j = 0; j < RECENT_BUDGET; j = j + 1) begin
        recent_valid[j] <= 1'b0;
        recent_block[j] <= '0;
        recent_epoch[j] <= '0;
      end
      for (j = 0; j < HH_BUDGET; j = j + 1) begin
        hh_valid[j] <= 1'b0;
        hh_block[j] <= '0;
        hh_accum[j] <= '0;
        hh_epoch[j] <= '0;
      end
    end else if (fire) begin
      if (!access_attn_valid) begin
        stat_h2o_fallback_cnt <= stat_h2o_fallback_cnt + 32'd1;
      end else begin
        if (hh_hit) begin
          stat_hh_hit_cnt <= stat_hh_hit_cnt + 32'd1;
        end
        if (hh_protect) begin
          stat_hh_protect_cnt <= stat_hh_protect_cnt + 32'd1;
        end
        if (recent_keep) begin
          stat_recent_keep_cnt <= stat_recent_keep_cnt + 32'd1;
        end
        if (hh_candidate) begin
          stat_hh_candidate_cnt <= stat_hh_candidate_cnt + 32'd1;
        end
        if (hh_candidate_attn) begin
          stat_hh_candidate_attn_cnt <= stat_hh_candidate_attn_cnt + 32'd1;
        end
        if (hh_candidate_query) begin
          stat_hh_candidate_query_cnt <= stat_hh_candidate_query_cnt + 32'd1;
        end
        if (hh_candidate_head) begin
          stat_hh_candidate_head_cnt <= stat_hh_candidate_head_cnt + 32'd1;
        end
        if (service_hh_candidate) begin
          stat_hh_candidate_service_cnt <= stat_hh_candidate_service_cnt + 32'd1;
        end
        unique case (h2o_class)
          KCMU_H2O_BOTH:        stat_h2o_both_cnt <= stat_h2o_both_cnt + 32'd1;
          KCMU_H2O_RECENT_ONLY: stat_h2o_recent_only_cnt <= stat_h2o_recent_only_cnt + 32'd1;
          KCMU_H2O_HEAVY_ONLY:  stat_h2o_hh_only_cnt <= stat_h2o_hh_only_cnt + 32'd1;
          default: begin end
        endcase

        if (RECENT_EN) begin
          for (j = RECENT_BUDGET-1; j > 0; j = j - 1) begin
            if (!recent_found || (j <= recent_hit_idx)) begin
              recent_valid[j] <= recent_valid[j-1];
              recent_block[j] <= recent_block[j-1];
              recent_epoch[j] <= recent_epoch[j-1];
            end
          end
          recent_valid[0] <= 1'b1;
          recent_block[0] <= access_token_block_id;
          recent_epoch[0] <= access_attn_epoch;
        end

        if (HEAVY_HITTER_EN) begin
          if (hh_found) begin
            hh_accum[hh_hit_idx] <= (HH_EPOCH_DECAY_EN ? hh_accum_eff[hh_hit_idx] : hh_accum[hh_hit_idx]) + HH_COUNT_W'(access_attn_score);
            hh_epoch[hh_hit_idx] <= access_attn_epoch;
          end else if (hh_candidate) begin
            if (hh_has_free) begin
              stat_hh_insert_free_cnt <= stat_hh_insert_free_cnt + 32'd1;
              hh_valid[hh_free_idx] <= 1'b1;
              hh_block[hh_free_idx] <= access_token_block_id;
              hh_accum[hh_free_idx] <= HH_COUNT_W'(access_attn_score);
              hh_epoch[hh_free_idx] <= access_attn_epoch;
            end else if (HH_COUNT_W'(access_attn_score) > hh_weak_score) begin
              stat_hh_replace_weak_cnt <= stat_hh_replace_weak_cnt + 32'd1;
              hh_valid[hh_weak_idx] <= 1'b1;
              hh_block[hh_weak_idx] <= access_token_block_id;
              hh_accum[hh_weak_idx] <= HH_COUNT_W'(access_attn_score);
              hh_epoch[hh_weak_idx] <= access_attn_epoch;
            end else begin
              stat_hh_reject_weak_cnt <= stat_hh_reject_weak_cnt + 32'd1;
            end
          end
        end
      end
    end
  end
endmodule
