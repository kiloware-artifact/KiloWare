`timescale 1ns/1ps
// ------------------------------------------------------------
// kcmu_policy.sv
// - Tag lookup (fully-associative small cache)
// - Use kcmu_h2o_repl to choose victim on miss
// ------------------------------------------------------------
module kcmu_policy #(
  parameter integer ADDR_W     = 8,
  parameter integer LINES      = 4,
  parameter integer SCORE_W    = 8,
  parameter integer TIME_W     = 16,
  parameter integer K_RECENT   = 1,
  parameter bit     LOOKAHEAD_KEEP_REPL_EN = 1'b0,
  parameter bit     AGE_DECAY_REPL_EN = 1'b0,
  parameter integer AGE_DECAY_TH = 8,
  parameter logic [SCORE_W-1:0] AGE_DECAY_PENALTY = SCORE_W'(4),
  parameter integer LINE_IDX_W = (LINES <= 1) ? 1 : $clog2(LINES)
)(
  input  logic [ADDR_W-1:0]           addr,
  input  logic [LINES-1:0]            valid,
  input  logic [LINES-1:0]            tier_hot,
  input  logic [LINES-1:0]            lookahead_keep,
  input  logic [LINES*ADDR_W-1:0]     tags_flat,
  input  logic [LINES*SCORE_W-1:0]    score_flat,
  input  logic [LINES*TIME_W-1:0]     last_flat,
  input  logic [TIME_W-1:0]           time_now,

  output logic                        hit,
  output logic [LINE_IDX_W-1:0]       hit_idx,

  output logic [LINE_IDX_W-1:0]       victim_idx,
  output logic                        victim_is_invalid
);

  function automatic logic [ADDR_W-1:0] tag_at(input integer idx);
    begin
      tag_at = tags_flat[idx*ADDR_W +: ADDR_W];
    end
  endfunction

  integer i;

  // hit detection
  always @(*) begin
    hit     = 1'b0;
    hit_idx = {LINE_IDX_W{1'b0}};
    for (i = 0; i < LINES; i = i + 1) begin
      if (!hit && valid[i] && (tag_at(i) == addr)) begin
        hit     = 1'b1;
        hit_idx = i[LINE_IDX_W-1:0];
      end
    end
  end

  // victim selection
  kcmu_h2o_repl #(
    .LINES(LINES),
    .SCORE_W(SCORE_W),
    .TIME_W(TIME_W),
    .K_RECENT(K_RECENT),
    .LOOKAHEAD_KEEP_REPL_EN(LOOKAHEAD_KEEP_REPL_EN),
    .AGE_DECAY_REPL_EN(AGE_DECAY_REPL_EN),
    .AGE_DECAY_TH(AGE_DECAY_TH),
    .AGE_DECAY_PENALTY(AGE_DECAY_PENALTY),
    .LINE_IDX_W(LINE_IDX_W)
  ) u_repl (
    .valid(valid),
    .tier_hot(tier_hot),
    .lookahead_keep(lookahead_keep),
    .score_flat(score_flat),
    .last_flat(last_flat),
    .time_now(time_now),
    .victim_idx(victim_idx),
    .victim_is_invalid(victim_is_invalid)
  );

endmodule
