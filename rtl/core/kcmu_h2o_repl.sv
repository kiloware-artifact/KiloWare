`timescale 1ns/1ps
// ------------------------------------------------------------
// kcmu_h2o_repl.sv
// Basic H2O victim selection:
// 1) If invalid line exists: pick first invalid.
// 2) Else prefer warm-tier victims; within tier evict min(score), tie -> oldest(last_used).
// 3) Optional hot escape (timing-safe): low-score hot line can re-enter
//    candidate set, preventing permanent hot lock-in.
// 4) K_RECENT>0 enables lightweight MRU protection: keep the most-recent
//    line out of victim candidates when other candidates exist.
// 5) Optional lookahead keep: if at least one non-lookahead candidate exists,
//    avoid evicting lines with a near-future reuse hint.
// ------------------------------------------------------------
module kcmu_h2o_repl #(
  parameter integer LINES      = 4,
  parameter integer SCORE_W    = 8,
  parameter integer TIME_W     = 16,
  parameter integer K_RECENT   = 1,
  parameter bit     HOT_ESCAPE_EN = 1'b1,
  parameter bit     LOOKAHEAD_KEEP_REPL_EN = 1'b0,
  parameter bit     AGE_DECAY_REPL_EN = 1'b0,
  parameter integer AGE_DECAY_TH = 8,
  parameter logic [SCORE_W-1:0] AGE_DECAY_PENALTY = SCORE_W'(4),
  parameter logic [SCORE_W-1:0] HOT_ESCAPE_SCORE_TH = SCORE_W'(2),
  parameter integer LINE_IDX_W = (LINES <= 1) ? 1 : $clog2(LINES)
)(
  input  logic [LINES-1:0]              valid,
  input  logic [LINES-1:0]              tier_hot,
  input  logic [LINES-1:0]              lookahead_keep,
  input  logic [LINES*SCORE_W-1:0]      score_flat,
  input  logic [LINES*TIME_W-1:0]       last_flat,
  input  logic [TIME_W-1:0]             time_now,
  output logic [LINE_IDX_W-1:0]         victim_idx,
  output logic                          victim_is_invalid
);

  logic [SCORE_W-1:0] score_arr [0:LINES-1];
  logic [SCORE_W-1:0] score_eff_arr [0:LINES-1];
  logic [TIME_W-1:0]  last_arr  [0:LINES-1];
  localparam integer CAND_PACK_W = 1 + LINE_IDX_W + SCORE_W + TIME_W;
  localparam integer CAND_LAST_LSB = 0;
  localparam integer CAND_SCORE_LSB = TIME_W;
  localparam integer CAND_IDX_LSB = TIME_W + SCORE_W;
  localparam integer CAND_VALID_LSB = TIME_W + SCORE_W + LINE_IDX_W;

  function automatic logic [SCORE_W-1:0] age_damped_score(
    input integer idx
  );
    logic [TIME_W-1:0] age;
    begin
      age = time_now - last_arr[idx];
      if (AGE_DECAY_REPL_EN && (age >= TIME_W'(AGE_DECAY_TH))) begin
        if (score_arr[idx] > AGE_DECAY_PENALTY) begin
          age_damped_score = score_arr[idx] - AGE_DECAY_PENALTY;
        end else begin
          age_damped_score = {SCORE_W{1'b0}};
        end
      end else begin
        age_damped_score = score_arr[idx];
      end
    end
  endfunction

  genvar gi;
  generate
    for (gi = 0; gi < LINES; gi = gi + 1) begin : GEN_FLAT
      assign score_arr[gi] = score_flat[gi*SCORE_W +: SCORE_W];
      assign last_arr[gi]  = last_flat [gi*TIME_W  +: TIME_W];
      assign score_eff_arr[gi] = age_damped_score(gi);
    end
  endgenerate

  function automatic logic a_is_weaker(
    input logic               a_valid,
    input logic [SCORE_W-1:0] a_score,
    input logic [TIME_W-1:0]  a_last,
    input logic               b_valid,
    input logic [SCORE_W-1:0] b_score,
    input logic [TIME_W-1:0]  b_last
  );
    begin
      if (a_valid && !b_valid) begin
        a_is_weaker = 1'b1;
      end else if (!a_valid && b_valid) begin
        a_is_weaker = 1'b0;
      end else if (!a_valid && !b_valid) begin
        a_is_weaker = 1'b1;
      end else if (a_score < b_score) begin
        a_is_weaker = 1'b1;
      end else if (a_score > b_score) begin
        a_is_weaker = 1'b0;
      end else if (a_last < b_last) begin
        a_is_weaker = 1'b1;
      end else begin
        a_is_weaker = 1'b0;
      end
    end
  endfunction

  function automatic logic [CAND_PACK_W-1:0] pack_candidate(
    input logic                    cand_valid,
    input logic [LINE_IDX_W-1:0]   cand_idx,
    input logic [SCORE_W-1:0]      cand_score,
    input logic [TIME_W-1:0]       cand_last
  );
    begin
      pack_candidate = {cand_valid, cand_idx, cand_score, cand_last};
    end
  endfunction

  function automatic logic [CAND_PACK_W-1:0] weaker_candidate(
    input logic [CAND_PACK_W-1:0] a,
    input logic [CAND_PACK_W-1:0] b
  );
    logic                    av;
    logic                    bv;
    logic [LINE_IDX_W-1:0]   ai;
    logic [LINE_IDX_W-1:0]   bi;
    logic [SCORE_W-1:0]      ascore;
    logic [SCORE_W-1:0]      bscore;
    logic [TIME_W-1:0]       alast;
    logic [TIME_W-1:0]       blast;
    begin
      av = a[CAND_VALID_LSB];
      bv = b[CAND_VALID_LSB];
      ai = a[CAND_IDX_LSB +: LINE_IDX_W];
      bi = b[CAND_IDX_LSB +: LINE_IDX_W];
      ascore = a[CAND_SCORE_LSB +: SCORE_W];
      bscore = b[CAND_SCORE_LSB +: SCORE_W];
      alast = a[CAND_LAST_LSB +: TIME_W];
      blast = b[CAND_LAST_LSB +: TIME_W];
      if (av && !bv) begin
        weaker_candidate = a;
      end else if (!av && bv) begin
        weaker_candidate = b;
      end else if (!av && !bv) begin
        weaker_candidate = a;
      end else if (ascore < bscore) begin
        weaker_candidate = a;
      end else if (ascore > bscore) begin
        weaker_candidate = b;
      end else if (alast < blast) begin
        weaker_candidate = a;
      end else if (alast > blast) begin
        weaker_candidate = b;
      end else if (ai <= bi) begin
        weaker_candidate = a;
      end else begin
        weaker_candidate = b;
      end
    end
  endfunction

  function automatic logic [CAND_PACK_W-1:0] newer_candidate(
    input logic [CAND_PACK_W-1:0] a,
    input logic [CAND_PACK_W-1:0] b
  );
    logic                    av;
    logic                    bv;
    logic [LINE_IDX_W-1:0]   ai;
    logic [LINE_IDX_W-1:0]   bi;
    logic [TIME_W-1:0]       alast;
    logic [TIME_W-1:0]       blast;
    begin
      av = a[CAND_VALID_LSB];
      bv = b[CAND_VALID_LSB];
      ai = a[CAND_IDX_LSB +: LINE_IDX_W];
      bi = b[CAND_IDX_LSB +: LINE_IDX_W];
      alast = a[CAND_LAST_LSB +: TIME_W];
      blast = b[CAND_LAST_LSB +: TIME_W];
      if (av && !bv) begin
        newer_candidate = a;
      end else if (!av && bv) begin
        newer_candidate = b;
      end else if (!av && !bv) begin
        newer_candidate = a;
      end else if (alast > blast) begin
        newer_candidate = a;
      end else if (alast < blast) begin
        newer_candidate = b;
      end else if (ai <= bi) begin
        newer_candidate = a;
      end else begin
        newer_candidate = b;
      end
    end
  endfunction

  function automatic logic same_candidate_idx(
    input logic [CAND_PACK_W-1:0] a,
    input logic [CAND_PACK_W-1:0] b
  );
    begin
      same_candidate_idx = a[CAND_VALID_LSB] &&
                           b[CAND_VALID_LSB] &&
                           (a[CAND_IDX_LSB +: LINE_IDX_W] == b[CAND_IDX_LSB +: LINE_IDX_W]);
    end
  endfunction

  function automatic logic [CAND_PACK_W-1:0] second_candidate_pair(
    input logic [CAND_PACK_W-1:0] a_best,
    input logic [CAND_PACK_W-1:0] a_second,
    input logic [CAND_PACK_W-1:0] b_best,
    input logic [CAND_PACK_W-1:0] b_second
  );
    logic [CAND_PACK_W-1:0] best_ab;
    begin
      best_ab = weaker_candidate(a_best, b_best);
      if (same_candidate_idx(best_ab, a_best)) begin
        second_candidate_pair = weaker_candidate(a_second, b_best);
      end else begin
        second_candidate_pair = weaker_candidate(a_best, b_second);
      end
    end
  endfunction

  generate
    // Fast path for default configuration (LINES=4): use a two-level compare tree.
    if (LINES == 4) begin : GEN_L4_FAST
      logic               sel01;
      logic               sel23;
      logic               selfinal;
      logic               has_warm;
      logic               has_alt_cand;
      logic               has_nonkeep_cand;
      logic [3:0]         cand_valid;
      logic [LINE_IDX_W-1:0] mru_idx;
      logic               weak01_valid;
      logic               weak23_valid;
      logic [SCORE_W-1:0] weak01_score;
      logic [SCORE_W-1:0] weak23_score;
      logic [TIME_W-1:0]  weak01_last;
      logic [TIME_W-1:0]  weak23_last;
      logic [LINE_IDX_W-1:0] weak01_idx;
      logic [LINE_IDX_W-1:0] weak23_idx;

      always @(*) begin
        victim_is_invalid = 1'b1;
        victim_idx        = {LINE_IDX_W{1'b0}};

        // Prefer first invalid line.
        if (!valid[0]) begin
          victim_idx = LINE_IDX_W'(0);
        end else if (!valid[1]) begin
          victim_idx = LINE_IDX_W'(1);
        end else if (!valid[2]) begin
          victim_idx = LINE_IDX_W'(2);
        end else if (!valid[3]) begin
          victim_idx = LINE_IDX_W'(3);
        end else begin
          victim_is_invalid = 1'b0;
          has_warm = (valid[0] && !tier_hot[0]) ||
                     (valid[1] && !tier_hot[1]) ||
                     (valid[2] && !tier_hot[2]) ||
                     (valid[3] && !tier_hot[3]);
          cand_valid[0] = valid[0] && (!tier_hot[0] || !has_warm || (HOT_ESCAPE_EN && (score_eff_arr[0] <= HOT_ESCAPE_SCORE_TH)));
          cand_valid[1] = valid[1] && (!tier_hot[1] || !has_warm || (HOT_ESCAPE_EN && (score_eff_arr[1] <= HOT_ESCAPE_SCORE_TH)));
          cand_valid[2] = valid[2] && (!tier_hot[2] || !has_warm || (HOT_ESCAPE_EN && (score_eff_arr[2] <= HOT_ESCAPE_SCORE_TH)));
          cand_valid[3] = valid[3] && (!tier_hot[3] || !has_warm || (HOT_ESCAPE_EN && (score_eff_arr[3] <= HOT_ESCAPE_SCORE_TH)));

          if (LOOKAHEAD_KEEP_REPL_EN) begin
            has_nonkeep_cand = (cand_valid[0] && !lookahead_keep[0]) ||
                               (cand_valid[1] && !lookahead_keep[1]) ||
                               (cand_valid[2] && !lookahead_keep[2]) ||
                               (cand_valid[3] && !lookahead_keep[3]);
            if (has_nonkeep_cand) begin
              cand_valid[0] = cand_valid[0] && !lookahead_keep[0];
              cand_valid[1] = cand_valid[1] && !lookahead_keep[1];
              cand_valid[2] = cand_valid[2] && !lookahead_keep[2];
              cand_valid[3] = cand_valid[3] && !lookahead_keep[3];
            end
          end else begin
            has_nonkeep_cand = 1'b0;
          end

          // MRU protection for K_RECENT>=1: avoid evicting most-recent line if alternatives exist.
          if ((last_arr[0] >= last_arr[1]) && (last_arr[0] >= last_arr[2]) && (last_arr[0] >= last_arr[3])) begin
            mru_idx = LINE_IDX_W'(0);
          end else if ((last_arr[1] >= last_arr[0]) && (last_arr[1] >= last_arr[2]) && (last_arr[1] >= last_arr[3])) begin
            mru_idx = LINE_IDX_W'(1);
          end else if ((last_arr[2] >= last_arr[0]) && (last_arr[2] >= last_arr[1]) && (last_arr[2] >= last_arr[3])) begin
            mru_idx = LINE_IDX_W'(2);
          end else begin
            mru_idx = LINE_IDX_W'(3);
          end

          if (K_RECENT > 0) begin
            has_alt_cand = (cand_valid[0] && (mru_idx != LINE_IDX_W'(0))) ||
                           (cand_valid[1] && (mru_idx != LINE_IDX_W'(1))) ||
                           (cand_valid[2] && (mru_idx != LINE_IDX_W'(2))) ||
                           (cand_valid[3] && (mru_idx != LINE_IDX_W'(3)));
            if (has_alt_cand) begin
              cand_valid[mru_idx] = 1'b0;
            end
          end

          sel01 = a_is_weaker(cand_valid[0], score_eff_arr[0], last_arr[0],
                              cand_valid[1], score_eff_arr[1], last_arr[1]);
          if (sel01) begin
            weak01_idx   = LINE_IDX_W'(0);
            weak01_valid = cand_valid[0];
            weak01_score = score_eff_arr[0];
            weak01_last  = last_arr[0];
          end else begin
            weak01_idx   = LINE_IDX_W'(1);
            weak01_valid = cand_valid[1];
            weak01_score = score_eff_arr[1];
            weak01_last  = last_arr[1];
          end

          sel23 = a_is_weaker(cand_valid[2], score_eff_arr[2], last_arr[2],
                              cand_valid[3], score_eff_arr[3], last_arr[3]);
          if (sel23) begin
            weak23_idx   = LINE_IDX_W'(2);
            weak23_valid = cand_valid[2];
            weak23_score = score_eff_arr[2];
            weak23_last  = last_arr[2];
          end else begin
            weak23_idx   = LINE_IDX_W'(3);
            weak23_valid = cand_valid[3];
            weak23_score = score_eff_arr[3];
            weak23_last  = last_arr[3];
          end

          selfinal = a_is_weaker(weak01_valid, weak01_score, weak01_last,
                                 weak23_valid, weak23_score, weak23_last);
          victim_idx = selfinal ? weak01_idx : weak23_idx;
        end
      end
    end else begin : GEN_GENERIC_TREE
      integer i;
      logic found_invalid;
      logic found_warm;
      logic found_nonkeep_cand;
      logic [LINE_IDX_W-1:0] invalid_idx;
      logic [LINE_IDX_W-1:0] mru_idx;
      logic [LINES-1:0]   cand_base_vec;
      logic [LINES-1:0]   cand_pre_vec;
      logic [CAND_PACK_W-1:0] victim_best;
      logic [CAND_PACK_W-1:0] victim_second;
      localparam integer TREE_LEVELS = (LINES <= 1) ? 1 : $clog2(LINES);
      logic [CAND_PACK_W-1:0] mru_tree  [0:TREE_LEVELS][0:LINES-1];
      logic [CAND_PACK_W-1:0] best_tree [0:TREE_LEVELS][0:LINES-1];
      logic [CAND_PACK_W-1:0] second_tree [0:TREE_LEVELS][0:LINES-1];

      assign found_warm = |(valid & ~tier_hot);
      assign found_nonkeep_cand = |(cand_base_vec & ~lookahead_keep);
      assign mru_idx = mru_tree[TREE_LEVELS][0][CAND_IDX_LSB +: LINE_IDX_W];
      assign victim_best = best_tree[TREE_LEVELS][0];
      assign victim_second = second_tree[TREE_LEVELS][0];

      genvar tj;
      for (tj = 0; tj < LINES; tj = tj + 1) begin : GEN_TREE_LEAF
        assign mru_tree[0][tj] = pack_candidate(
          valid[tj],
          LINE_IDX_W'(tj),
          {SCORE_W{1'b0}},
          last_arr[tj]
        );
        assign cand_base_vec[tj] = valid[tj] &&
                                   (!tier_hot[tj] ||
                                    !found_warm ||
                                    (HOT_ESCAPE_EN && tier_hot[tj] && (score_eff_arr[tj] <= HOT_ESCAPE_SCORE_TH)));
        assign cand_pre_vec[tj] = cand_base_vec[tj] &&
                                  (!LOOKAHEAD_KEEP_REPL_EN ||
                                   !found_nonkeep_cand ||
                                   !lookahead_keep[tj]);
        assign best_tree[0][tj] = pack_candidate(
          cand_pre_vec[tj],
          LINE_IDX_W'(tj),
          score_eff_arr[tj],
          last_arr[tj]
        );
        assign second_tree[0][tj] = pack_candidate(
          1'b0,
          LINE_IDX_W'(tj),
          {SCORE_W{1'b0}},
          {TIME_W{1'b0}}
        );
      end

      genvar tl;
      genvar tn;
      for (tl = 0; tl < TREE_LEVELS; tl = tl + 1) begin : GEN_TREE_LEVEL
        localparam integer CUR_N = (LINES + (1 << tl) - 1) >> tl;
        localparam integer NEXT_N = (CUR_N + 1) >> 1;
        for (tn = 0; tn < NEXT_N; tn = tn + 1) begin : GEN_TREE_NODE
          if ((2 * tn + 1) < CUR_N) begin : GEN_TREE_PAIR
            assign mru_tree[tl+1][tn] = newer_candidate(mru_tree[tl][2*tn], mru_tree[tl][2*tn+1]);
            assign best_tree[tl+1][tn] = weaker_candidate(best_tree[tl][2*tn], best_tree[tl][2*tn+1]);
            assign second_tree[tl+1][tn] = second_candidate_pair(
              best_tree[tl][2*tn],
              second_tree[tl][2*tn],
              best_tree[tl][2*tn+1],
              second_tree[tl][2*tn+1]
            );
          end else begin : GEN_TREE_SINGLE
            assign mru_tree[tl+1][tn] = mru_tree[tl][2*tn];
            assign best_tree[tl+1][tn] = best_tree[tl][2*tn];
            assign second_tree[tl+1][tn] = second_tree[tl][2*tn];
          end
        end
      end

      always @(*) begin
        victim_idx        = {LINE_IDX_W{1'b0}};
        victim_is_invalid = 1'b0;

        found_invalid = 1'b0;
        invalid_idx   = {LINE_IDX_W{1'b0}};
        for (i = 0; i < LINES; i = i + 1) begin
          if (!found_invalid && !valid[i]) begin
            found_invalid = 1'b1;
            invalid_idx   = i[LINE_IDX_W-1:0];
          end
        end

        if (found_invalid) begin
          victim_is_invalid = 1'b1;
          victim_idx        = invalid_idx;
        end else begin
          if ((K_RECENT > 0) &&
              victim_second[CAND_VALID_LSB] &&
              (victim_best[CAND_IDX_LSB +: LINE_IDX_W] == mru_idx)) begin
            victim_idx = victim_second[CAND_IDX_LSB +: LINE_IDX_W];
          end else begin
            victim_idx = victim_best[CAND_IDX_LSB +: LINE_IDX_W];
          end
        end
      end
    end
  endgenerate

endmodule
