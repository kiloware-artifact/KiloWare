`timescale 1ns/1ps
// ------------------------------------------------------------
// kcmu_pkg
// Shared constants/types for KCMU.
// ------------------------------------------------------------
package kcmu_pkg;
  typedef logic [1:0] kcmu_op_t;
  typedef logic       kcmu_phase_t;
  typedef logic       kcmu_kv_kind_t;
  typedef logic [1:0] kcmu_h2o_class_t;
  localparam integer KCMU_SEQ_W = 8;
  localparam integer KCMU_ATTN_RANK_W = 4;
  localparam integer KCMU_TOKEN_BLOCK_W = 16;
  localparam integer KCMU_ATTN_EPOCH_W = 8;
  localparam integer KCMU_HEAD_BUDGET_W = 2;
  localparam integer KCMU_COST_CLASS_W = 4;
  localparam integer KCMU_DESC_CLASS_W = 2;
  localparam integer KCMU_SCHED_HINT_W = 2;
  localparam kcmu_op_t KCMU_OP_NOP = 2'b00;
  localparam kcmu_op_t KCMU_OP_RD  = 2'b01;
  localparam kcmu_op_t KCMU_OP_WR  = 2'b10;
  localparam kcmu_phase_t   KCMU_PHASE_PREFILL = 1'b0;
  localparam kcmu_phase_t   KCMU_PHASE_DECODE  = 1'b1;
  localparam kcmu_kv_kind_t KCMU_KV_KIND_K     = 1'b0;
  localparam kcmu_kv_kind_t KCMU_KV_KIND_V     = 1'b1;
  localparam kcmu_h2o_class_t KCMU_H2O_NEITHER          = 2'd0;
  localparam kcmu_h2o_class_t KCMU_H2O_RECENT_ONLY      = 2'd1;
  localparam kcmu_h2o_class_t KCMU_H2O_HEAVY_ONLY       = 2'd2;
  localparam kcmu_h2o_class_t KCMU_H2O_BOTH             = 2'd3;

  // KV-semantic QoS estimation from packed trace address:
  // [7:5] layer, [4:3] head, [2:0] token-window index.
  // Higher value means hotter / more latency-sensitive.
  function automatic logic [2:0] kv_qos_from_addr(
    input logic [31:0] addr32,
    input logic        is_prefetch,
    input logic        is_read
  );
    logic signed [4:0] qos_tmp;
    logic [2:0] token_idx;
    logic [1:0] head_idx;
    logic [2:0] layer_idx;
    begin
      token_idx = addr32[2:0];
      head_idx  = addr32[4:3];
      layer_idx = addr32[7:5];

      qos_tmp = 5'sd2;
      if (is_read)     qos_tmp = qos_tmp + 5'sd1;
      if (is_prefetch) qos_tmp = qos_tmp - 5'sd1;

      // Recent tokens are usually more likely to be reused soon.
      if (token_idx >= 3'd5) qos_tmp = qos_tmp + 5'sd2;

      // Earlier layers often feed many downstream operations.
      if (layer_idx <= 3'd1) qos_tmp = qos_tmp + 5'sd1;

      // Keep one head group slightly hotter to mimic attention skew.
      if (head_idx == 2'd0) qos_tmp = qos_tmp + 5'sd1;

      if (qos_tmp < 0)       kv_qos_from_addr = 3'd0;
      else if (qos_tmp > 7)  kv_qos_from_addr = 3'd7;
      else                   kv_qos_from_addr = qos_tmp[2:0];
    end
  endfunction

  function automatic logic kv_is_cold_qos(input logic [2:0] qos);
    begin
      kv_is_cold_qos = (qos <= 3'd2);
    end
  endfunction
endpackage

// ------------------------------------------------------------
// kcmu_decoder.sv
// Pass-through decoder for trace stream.
// ------------------------------------------------------------
