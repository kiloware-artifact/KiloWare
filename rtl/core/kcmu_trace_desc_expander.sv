`timescale 1ns/1ps
// ------------------------------------------------------------
// kcmu_trace_desc_expander.sv
// Descriptor trace expander for base_addr + len style requests.
// ------------------------------------------------------------
module kcmu_trace_desc_expander #(
  parameter integer ADDR_W  = 8,
  parameter integer DATA_W  = 32,
  parameter integer SCORE_W = 8
)(
  input  logic                   clk,
  input  logic                   rst_n,

  input  logic                   desc_valid,
  output logic                   desc_ready,
  input  kcmu_pkg::kcmu_op_t     desc_op,
  input  logic [ADDR_W-1:0]      desc_base_addr,
  input  logic [7:0]             desc_len,
  input  logic [SCORE_W-1:0]     desc_score,
  input  logic [kcmu_pkg::KCMU_SEQ_W-1:0] desc_seq_id,
  input  kcmu_pkg::kcmu_phase_t  desc_phase,
  input  kcmu_pkg::kcmu_kv_kind_t desc_kv_kind,
  input  logic                   desc_attn_valid,
  input  logic [SCORE_W-1:0]     desc_attn_score,
  input  logic [kcmu_pkg::KCMU_ATTN_RANK_W-1:0] desc_recent_rank,
  input  logic [kcmu_pkg::KCMU_TOKEN_BLOCK_W-1:0] desc_token_block_id,
  input  logic [kcmu_pkg::KCMU_ATTN_EPOCH_W-1:0] desc_attn_epoch,
  input  logic [kcmu_pkg::KCMU_HEAD_BUDGET_W-1:0] desc_head_budget_class,
  input  logic [SCORE_W-1:0]     desc_query_relevance,
  input  logic [kcmu_pkg::KCMU_COST_CLASS_W-1:0] desc_compression_risk,
  input  logic [kcmu_pkg::KCMU_COST_CLASS_W-1:0] desc_spill_cost,
  input  logic [SCORE_W-1:0]     desc_service_criticality,
  input  logic                   desc_policy_select_s5,
  input  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] desc_temporal_persist_class,
  input  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] desc_reuse_distance_class,
  input  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] desc_query_structure_class,
  input  logic [kcmu_pkg::KCMU_SCHED_HINT_W-1:0] desc_sched_urgency_hint,
  input  logic                   desc_sig_valid,
  input  logic [5:0]             desc_query_sig,
  input  logic [5:0]             desc_key_sig,
  input  logic [1:0]             desc_prefix_class,
  input  logic [1:0]             desc_router_class,
  input  logic                   desc_wvalid,
  output logic                   desc_wready,
  input  logic [DATA_W-1:0]      desc_wdata,

  output logic                   cmd_valid,
  input  logic                   cmd_ready,
  output kcmu_pkg::kcmu_op_t     cmd_op,
  output logic [ADDR_W-1:0]      cmd_addr,
  output logic [DATA_W-1:0]      cmd_wdata,
  output logic                   cmd_meta_valid,
  output logic [kcmu_pkg::KCMU_SEQ_W-1:0] cmd_seq_id,
  output kcmu_pkg::kcmu_phase_t  cmd_phase,
  output kcmu_pkg::kcmu_kv_kind_t cmd_kv_kind,
  output logic [2:0]             cmd_layer,
  output logic [1:0]             cmd_head,
  output logic [11:0]            cmd_token,
  output logic [2:0]             cmd_prio,
  output logic [SCORE_W-1:0]     cmd_score,
  output logic                   cmd_attn_valid,
  output logic [SCORE_W-1:0]     cmd_attn_score,
  output logic [kcmu_pkg::KCMU_ATTN_RANK_W-1:0] cmd_recent_rank,
  output logic [kcmu_pkg::KCMU_TOKEN_BLOCK_W-1:0] cmd_token_block_id,
  output logic [kcmu_pkg::KCMU_ATTN_EPOCH_W-1:0] cmd_attn_epoch,
  output logic [kcmu_pkg::KCMU_HEAD_BUDGET_W-1:0] cmd_head_budget_class,
  output logic [SCORE_W-1:0]     cmd_query_relevance,
  output logic [kcmu_pkg::KCMU_COST_CLASS_W-1:0] cmd_compression_risk,
  output logic [kcmu_pkg::KCMU_COST_CLASS_W-1:0] cmd_spill_cost,
  output logic [SCORE_W-1:0]     cmd_service_criticality,
  output logic                   cmd_policy_select_s5,
  output logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] cmd_temporal_persist_class,
  output logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] cmd_reuse_distance_class,
  output logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] cmd_query_structure_class,
  output logic [kcmu_pkg::KCMU_SCHED_HINT_W-1:0] cmd_sched_urgency_hint,
  output logic                   cmd_sig_valid,
  output logic [5:0]             cmd_query_sig,
  output logic [5:0]             cmd_key_sig,
  output logic [1:0]             cmd_prefix_class,
  output logic [1:0]             cmd_router_class,
  output logic                   cmd_block_last
);
  import kcmu_pkg::*;

  logic                  active_q;
  kcmu_op_t              op_q;
  logic [ADDR_W-1:0]     base_addr_q;
  logic [7:0]            len_q;
  logic [SCORE_W-1:0]    score_q;
  logic [KCMU_SEQ_W-1:0] seq_id_q;
  kcmu_phase_t           phase_q;
  kcmu_kv_kind_t         kv_kind_q;
  logic                  attn_valid_q;
  logic [SCORE_W-1:0]    attn_score_q;
  logic [KCMU_ATTN_RANK_W-1:0] recent_rank_q;
  logic [KCMU_TOKEN_BLOCK_W-1:0] token_block_id_q;
  logic [KCMU_ATTN_EPOCH_W-1:0] attn_epoch_q;
  logic [KCMU_HEAD_BUDGET_W-1:0] head_budget_class_q;
  logic [SCORE_W-1:0]    query_relevance_q;
  logic [KCMU_COST_CLASS_W-1:0] compression_risk_q;
  logic [KCMU_COST_CLASS_W-1:0] spill_cost_q;
  logic [SCORE_W-1:0]    service_criticality_q;
  logic                  policy_select_s5_q;
  logic [KCMU_DESC_CLASS_W-1:0] temporal_persist_class_q;
  logic [KCMU_DESC_CLASS_W-1:0] reuse_distance_class_q;
  logic [KCMU_DESC_CLASS_W-1:0] query_structure_class_q;
  logic [KCMU_SCHED_HINT_W-1:0] sched_urgency_hint_q;
  logic                  sig_valid_q;
  logic [5:0]            query_sig_q;
  logic [5:0]            key_sig_q;
  logic [1:0]            prefix_class_q;
  logic [1:0]            router_class_q;
  logic [7:0]            beat_idx_q;
  logic                  payload_valid_q;
  logic [DATA_W-1:0]     payload_wdata_q;

  logic [ADDR_W-1:0]     cur_addr;
  logic [11:0]           cur_token;
  logic [7:0]            beat_count;
  logic                  fire_desc;
  logic                  fire_cmd;
  logic                  capture_payload;
  logic                  needs_payload;

  function automatic logic [11:0] addr_to_token(input logic [ADDR_W-1:0] addr_i);
    logic [11:0] tmp;
    begin
      tmp = '0;
      if (ADDR_W >= 12) begin
        tmp = addr_i[11:0];
      end else begin
        tmp[ADDR_W-1:0] = addr_i;
      end
      addr_to_token = tmp;
    end
  endfunction

  function automatic logic [2:0] score_to_prio(input logic [SCORE_W-1:0] score_i);
    logic [2:0] tmp;
    begin
      tmp = 3'd0;
      if (SCORE_W >= 3) begin
        tmp = score_i[SCORE_W-1 -: 3];
      end else begin
        tmp[2 -: SCORE_W] = score_i;
      end
      score_to_prio = tmp;
    end
  endfunction

  assign beat_count = (len_q == 8'd0) ? 8'd1 : len_q;
  assign cur_addr   = base_addr_q + ADDR_W'(beat_idx_q);
  assign cur_token  = addr_to_token(cur_addr);
  assign needs_payload = active_q && (op_q == KCMU_OP_WR) && !payload_valid_q;

  assign desc_ready  = !active_q;
  assign desc_wready = needs_payload;

  assign cmd_valid      = active_q && ((op_q != KCMU_OP_WR) || payload_valid_q);
  assign cmd_op         = active_q ? op_q : KCMU_OP_NOP;
  assign cmd_addr       = cur_addr;
  assign cmd_wdata      = payload_valid_q ? payload_wdata_q : '0;
  assign cmd_meta_valid = active_q;
  assign cmd_seq_id     = seq_id_q;
  assign cmd_phase      = phase_q;
  assign cmd_kv_kind    = kv_kind_q;
  assign cmd_layer      = cur_token[7:5];
  assign cmd_head       = cur_token[4:3];
  assign cmd_token      = cur_token;
  assign cmd_prio       = score_to_prio(score_q);
  assign cmd_score      = score_q;
  assign cmd_attn_valid = attn_valid_q;
  assign cmd_attn_score = attn_score_q;
  assign cmd_recent_rank = recent_rank_q;
  assign cmd_token_block_id = token_block_id_q;
  assign cmd_attn_epoch = attn_epoch_q;
  assign cmd_head_budget_class = head_budget_class_q;
  assign cmd_query_relevance = query_relevance_q;
  assign cmd_compression_risk = compression_risk_q;
  assign cmd_spill_cost = spill_cost_q;
  assign cmd_service_criticality = service_criticality_q;
  assign cmd_policy_select_s5 = policy_select_s5_q;
  assign cmd_temporal_persist_class = temporal_persist_class_q;
  assign cmd_reuse_distance_class = reuse_distance_class_q;
  assign cmd_query_structure_class = query_structure_class_q;
  assign cmd_sched_urgency_hint = sched_urgency_hint_q;
  assign cmd_sig_valid = sig_valid_q;
  assign cmd_query_sig = query_sig_q;
  assign cmd_key_sig = key_sig_q;
  assign cmd_prefix_class = prefix_class_q;
  assign cmd_router_class = router_class_q;
  assign cmd_block_last = active_q && ((beat_idx_q + 8'd1) >= beat_count);

  assign fire_desc = desc_valid && desc_ready;
  assign capture_payload = desc_wvalid && desc_wready;
  assign fire_cmd = cmd_valid && cmd_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active_q         <= 1'b0;
      op_q             <= KCMU_OP_NOP;
      base_addr_q      <= '0;
      len_q            <= 8'd0;
      score_q          <= '0;
      seq_id_q         <= '0;
      phase_q          <= KCMU_PHASE_PREFILL;
      kv_kind_q        <= KCMU_KV_KIND_K;
      attn_valid_q     <= 1'b0;
      attn_score_q     <= '0;
      recent_rank_q    <= '0;
      token_block_id_q <= '0;
      attn_epoch_q     <= '0;
      head_budget_class_q <= '0;
      query_relevance_q <= '0;
      compression_risk_q <= '0;
      spill_cost_q <= '0;
      service_criticality_q <= '0;
      policy_select_s5_q <= 1'b1;
      temporal_persist_class_q <= '0;
      reuse_distance_class_q <= '0;
      query_structure_class_q <= '0;
      sched_urgency_hint_q <= '0;
      sig_valid_q <= 1'b0;
      query_sig_q <= 6'd0;
      key_sig_q <= 6'd0;
      prefix_class_q <= 2'd0;
      router_class_q <= 2'd0;
      beat_idx_q       <= 8'd0;
      payload_valid_q  <= 1'b0;
      payload_wdata_q  <= '0;
    end else begin
      if (fire_desc) begin
        active_q         <= 1'b1;
        op_q             <= desc_op;
        base_addr_q      <= desc_base_addr;
        len_q            <= (desc_len == 8'd0) ? 8'd1 : desc_len;
        score_q          <= desc_score;
        seq_id_q         <= desc_seq_id;
        phase_q          <= desc_phase;
        kv_kind_q        <= desc_kv_kind;
        attn_valid_q     <= desc_attn_valid;
        attn_score_q     <= desc_attn_score;
        recent_rank_q    <= desc_recent_rank;
        token_block_id_q <= desc_token_block_id;
        attn_epoch_q     <= desc_attn_epoch;
        head_budget_class_q <= desc_head_budget_class;
        query_relevance_q <= desc_query_relevance;
        compression_risk_q <= desc_compression_risk;
        spill_cost_q <= desc_spill_cost;
        service_criticality_q <= desc_service_criticality;
        policy_select_s5_q <= desc_policy_select_s5;
        temporal_persist_class_q <= desc_temporal_persist_class;
        reuse_distance_class_q <= desc_reuse_distance_class;
        query_structure_class_q <= desc_query_structure_class;
        sched_urgency_hint_q <= desc_sched_urgency_hint;
        sig_valid_q <= desc_sig_valid;
        query_sig_q <= desc_query_sig;
        key_sig_q <= desc_key_sig;
        prefix_class_q <= desc_prefix_class;
        router_class_q <= desc_router_class;
        beat_idx_q       <= 8'd0;
        payload_valid_q  <= 1'b0;
        payload_wdata_q  <= '0;
      end

      if (capture_payload) begin
        payload_valid_q <= 1'b1;
        payload_wdata_q <= desc_wdata;
      end

      if (fire_cmd) begin
        if (op_q == KCMU_OP_WR) begin
          payload_valid_q <= 1'b0;
          payload_wdata_q <= '0;
        end

        if ((beat_idx_q + 8'd1) >= beat_count) begin
          active_q         <= 1'b0;
          op_q             <= KCMU_OP_NOP;
          beat_idx_q       <= 8'd0;
          attn_valid_q     <= 1'b0;
          attn_score_q     <= '0;
          recent_rank_q    <= '0;
          token_block_id_q <= '0;
          attn_epoch_q     <= '0;
          head_budget_class_q <= '0;
          query_relevance_q <= '0;
          compression_risk_q <= '0;
          spill_cost_q <= '0;
          service_criticality_q <= '0;
          policy_select_s5_q <= 1'b1;
          temporal_persist_class_q <= '0;
          reuse_distance_class_q <= '0;
          query_structure_class_q <= '0;
          sched_urgency_hint_q <= '0;
          sig_valid_q <= 1'b0;
          query_sig_q <= 6'd0;
          key_sig_q <= 6'd0;
          prefix_class_q <= 2'd0;
          router_class_q <= 2'd0;
        end else begin
          beat_idx_q <= beat_idx_q + 8'd1;
        end
      end
    end
  end
endmodule
