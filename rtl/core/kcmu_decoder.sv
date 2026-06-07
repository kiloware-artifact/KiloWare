`timescale 1ns/1ps
// ------------------------------------------------------------
// kcmu_decoder.sv
// Pass-through decoder for trace stream.
// ------------------------------------------------------------
module kcmu_decoder #(
  parameter integer ADDR_W = 8,
  parameter integer DATA_W = 32,
  parameter integer SCORE_W = 8
)(
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

  output logic                 cmd_valid,
  input  logic                 cmd_ready,
  output kcmu_pkg::kcmu_op_t   cmd_op,
  output logic [ADDR_W-1:0]    cmd_addr,
  output logic [DATA_W-1:0]    cmd_wdata,
  output logic                 cmd_meta_valid,
  output logic [kcmu_pkg::KCMU_SEQ_W-1:0] cmd_seq_id,
  output kcmu_pkg::kcmu_phase_t cmd_phase,
  output kcmu_pkg::kcmu_kv_kind_t cmd_kv_kind,
  output logic [2:0]           cmd_layer,
  output logic [1:0]           cmd_head,
  output logic [11:0]          cmd_token,
  output logic [2:0]           cmd_prio,
  output logic [SCORE_W-1:0]   cmd_score,
  output logic                 cmd_attn_valid,
  output logic [SCORE_W-1:0]   cmd_attn_score,
  output logic [kcmu_pkg::KCMU_ATTN_RANK_W-1:0] cmd_recent_rank,
  output logic [kcmu_pkg::KCMU_TOKEN_BLOCK_W-1:0] cmd_token_block_id,
  output logic [kcmu_pkg::KCMU_ATTN_EPOCH_W-1:0] cmd_attn_epoch
);

  assign cmd_valid   = trace_valid;
  assign trace_ready = cmd_ready;

  assign cmd_op      = trace_op;
  assign cmd_addr    = trace_addr;
  assign cmd_wdata   = trace_wdata;
  assign cmd_meta_valid = trace_meta_valid;
  assign cmd_seq_id     = trace_seq_id;
  assign cmd_phase      = trace_phase;
  assign cmd_kv_kind    = trace_kv_kind;
  assign cmd_layer      = trace_layer;
  assign cmd_head       = trace_head;
  assign cmd_token      = trace_token;
  assign cmd_prio       = trace_prio;
  assign cmd_score      = {trace_prio, {(SCORE_W-3){1'b0}}};
  assign cmd_attn_valid = 1'b0;
  assign cmd_attn_score = {SCORE_W{1'b0}};
  assign cmd_recent_rank = {kcmu_pkg::KCMU_ATTN_RANK_W{1'b0}};
  assign cmd_token_block_id = {kcmu_pkg::KCMU_TOKEN_BLOCK_W{1'b0}};
  assign cmd_attn_epoch = {kcmu_pkg::KCMU_ATTN_EPOCH_W{1'b0}};

endmodule
