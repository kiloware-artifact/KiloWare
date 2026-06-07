`timescale 1ns/1ps
// ------------------------------------------------------------
// kcmu_attn_scheduler.sv
// Attention-aware scheduler.
// ------------------------------------------------------------
module kcmu_attn_scheduler #(
  parameter integer TOKEN_W = 12,
  parameter integer HBM_Q_W = 3,
  parameter integer SCORE_W = 8,
  parameter bit     RELAX_REUSE_ONLY_PROTECT_UNDER_PRESSURE_EN = 1'b0,
  parameter logic [2:0] RELAX_REUSE_ONLY_PROTECT_QOS_TH = 3'd6,
  parameter bit     STEAL_REUSE_ONLY_OWNERSHIP_EN = 1'b0,
  parameter logic [2:0] STEAL_REUSE_ONLY_QOS_TH = 3'd4,
  parameter bit     OVERRIDE_FILL_BLOCK_WITH_UTILITY_EN = 1'b0,
  parameter logic [2:0] OVERRIDE_FILL_BLOCK_QOS_TH = 3'd5,
  parameter bit     BACKEND_ISSUE_OWNERSHIP_EN = 1'b0,
  parameter logic [2:0] BACKEND_ISSUE_OWNERSHIP_QOS_TH = 3'd5,
  parameter bit     BACKEND_ISSUE_RESCUE_EN = 1'b0,
  parameter logic [2:0] BACKEND_ISSUE_RESCUE_QOS_TH = 3'd5,
  parameter bit     BACKEND_ISSUE_STRONG_QUERY_GATE_EN = 1'b0,
  parameter bit     BACKEND_ISSUE_HIGH_SERVICE_ESCAPE_EN = 1'b0,
  parameter logic [SCORE_W-1:0] BACKEND_ISSUE_HIGH_SERVICE_TH = SCORE_W'(8'hD0),
  parameter bit     BACKEND_ISSUE_ROI_PRESSURE_GATE_EN = 1'b0,
  parameter bit     PROMOTE_QUERY_TEMPORAL_PRIMARY_UTILITY_EN = 1'b0,
  parameter logic [2:0] PROMOTE_QUERY_TEMPORAL_QOS_TH = 3'd4,
  parameter bit     FORCE_QUERY_TEMPORAL_DIRECT_TAKE_EN = 1'b0,
  parameter bit     OWNERSHIP_QOS_FLOOR_EN = 1'b0,
  parameter logic [2:0] OWNERSHIP_QOS_FLOOR = 3'd5,
  parameter logic [2:0] OWNERSHIP_QOS_BACKEND_FLOOR = 3'd6,
  parameter bit     MASTER_OWNERSHIP_FILL_STEAL_EN = 1'b0,
  parameter bit     MASTER_OWNERSHIP_FILL_ONLY_EN = 1'b0,
  parameter bit     MASTER_OWNERSHIP_BLOCK_RESCUE_EN = 1'b0,
  parameter bit     MASTER_OUTPUT_RESCUE_EN = 1'b0,
  parameter logic [2:0] MASTER_OWNERSHIP_FILL_STEAL_QOS_TH = 3'd6,
  parameter logic [2:0] MASTER_OUTPUT_RESCUE_QOS_TH = 3'd5
)(
  input  logic                clk,
  input  logic                rst_n,
  input  logic                req_valid,
  input  logic                req_ready,
  input  logic                is_read,
  input  logic                is_prefetch,
  input  logic                meta_valid,
  input  logic [kcmu_pkg::KCMU_SEQ_W-1:0] seq_id,
  input  kcmu_pkg::kcmu_phase_t phase,
  input  kcmu_pkg::kcmu_kv_kind_t kv_kind,
  input  logic [2:0]          layer,
  input  logic [1:0]          head,
  input  logic [TOKEN_W-1:0]  token,
  input  logic [2:0]          base_qos,
  input  logic                utility_hh_protect,
  input  logic                utility_recent_keep,
  input  logic                utility_query_hot,
  input  logic                utility_query_warm,
  input  logic                utility_temporal_hot,
  input  logic                utility_temporal_warm,
  input  logic                utility_long_distance_hot,
  input  logic                utility_structured_hot,
  input  logic                utility_policy_select_s5,
  input  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] utility_query_structure_class,
  input  logic [SCORE_W-1:0]  utility_service_criticality,
  input  logic [kcmu_pkg::KCMU_SCHED_HINT_W-1:0] utility_sched_urgency_hint,
  input  logic [HBM_Q_W-1:0]  hbm_q_level,
  input  logic                hbm_congested,
  input  logic                hbm_write_pressure,
  input  logic                hbm_prefetch_block,
  input  logic                backend_issue_dynamic_strong_query_gate,
  output logic [2:0]          sched_qos,
  output logic                prefetch_allow,
  output logic                fill_allow,
  output logic                victim_protect,
  output logic                hot_hint,
  output logic                repl_hot_hint,
  output logic                sched_fill_req,
  output logic                sched_fill_take,
  output logic                sched_fill_effect,
  output logic                sched_protect_req,
  output logic                sched_protect_take,
  output logic                sched_protect_effect,
  output logic                sched_victim_req,
  output logic                sched_victim_flip_take,
  output logic                sched_query_take,
  output logic                sched_temporal_take,
  output logic                sched_budget_steal,
  output logic                sched_backend_issue_req,
  output logic                sched_victim_flip_effect,
  output logic                sched_backend_issue_take,
  output logic                sched_fill_block_window_seen,
  output logic                sched_qos_raise_effect
);
  localparam integer ATTN_CTX = 32;
  localparam integer ATTN_IDX_W = 5;

  logic [TOKEN_W-1:0] last_token [0:ATTN_CTX-1];
  logic [kcmu_pkg::KCMU_SEQ_W-1:0] last_seq_id [0:ATTN_CTX-1];
  logic [2:0] last_layer [0:ATTN_CTX-1];
  logic [1:0] last_head [0:ATTN_CTX-1];
  kcmu_pkg::kcmu_phase_t last_phase [0:ATTN_CTX-1];
  kcmu_pkg::kcmu_kv_kind_t last_kv_kind [0:ATTN_CTX-1];
  logic [ATTN_CTX-1:0] last_token_valid;
  logic [ATTN_IDX_W-1:0] idx_cur;
  logic same_stream;
  logic [TOKEN_W-1:0] token_delta;
  logic token_vrecent;
  logic token_recent;
  logic reuse_hot;
  logic decode_hot;
  logic prefill_cold;
  logic sem_critical;
  logic utility_hot_base;
  logic utility_warm_base;
  logic utility_hot;
  logic utility_warm;
  logic temporal_hot;
  logic temporal_warm;
  logic query_struct_hot;
  logic sched_pressure;
  logic primary_query_promote;
  logic primary_temporal_promote;
  logic relax_reuse_candidate;
  logic relax_reuse_applied;
  logic relax_reuse_keep_state;
  logic relax_reuse_keep_utility;
  logic relax_reuse_keep_qos;
  logic reuse_ownership_steal;
  logic victim_protect_reuse_cause;
  logic victim_protect_reuse_cause_raw;
  logic prepromo_victim_protect_utility_cause;
  logic prepromo_victim_protect_decode_cause;
  logic prepromo_base_victim_protect;
  logic victim_protect_utility_cause;
  logic victim_protect_decode_cause;
  logic prepromo_fill_block_wr_prefetch_cause;
  logic prepromo_fill_block_wr_readcold_cause;
  logic prepromo_fill_block_cg_prefetch_cause;
  logic prepromo_fill_block_cg_readcold_cause;
  logic prepromo_base_fill_allow;
  logic fill_block_wr_prefetch_cause;
  logic fill_block_wr_readcold_cause;
  logic fill_block_cg_prefetch_cause;
  logic fill_block_cg_readcold_cause;
  logic readcold_backoff;
  logic base_fill_allow;
  logic base_victim_protect;
  logic ownership_query_intent;
  logic ownership_temporal_intent;
  logic direct_query_force_take;
  logic direct_temporal_force_take;
  logic ownership_query_take;
  logic ownership_temporal_take;
  logic ownership_fill_take;
  logic ownership_protect_take;
  logic ownership_query_protect_take;
  logic ownership_temporal_protect_take;
  logic ownership_budget_steal;
  logic ownership_backend_issue_take;
  logic backend_issue_force_take;
  logic backend_issue_seed_take;
  logic backend_issue_protect_steal;
  logic backend_issue_fill_rescue;
  logic backend_issue_gate_ok;
  logic backend_issue_roi_pressure_ok;
  logic backend_issue_high_service_escape;
  logic backend_issue_strong_query_gate_active;
  logic overlap_query_fill_block;
  logic overlap_hh_fill_block;
  logic overlap_backend_fill_block;
  logic overlap_query_baseprotect;
  logic overlap_hh_baseprotect;
  logic overlap_backend_baseprotect;
  logic fill_ownership_override;
  logic fill_ownership_query_drive;
  logic fill_ownership_temporal_drive;
  logic master_query_fill_steal;
  logic master_temporal_fill_steal;
  logic master_query_block_rescue;
  logic master_temporal_block_rescue;
  logic master_query_output_rescue;
  logic master_temporal_output_rescue;
  logic master_output_rescue;
  logic master_protect_mask;
  logic temporal_query_shadow_guard;
  logic [2:0] ownership_qos_floor;
  logic [2:0] sched_qos_pre_owner;
  logic [2:0] qos_tmp;
  logic [2:0] non_meta_cap;
  integer ai;

`ifndef SYNTHESIS
  logic [31:0] stat_sched_hot_hint_cnt;
  logic [31:0] stat_sched_pref_block_cnt;
  logic [31:0] stat_sched_fill_block_cnt;
  logic [31:0] stat_sched_victim_protect_cnt;
  logic [31:0] stat_sched_victim_reuse_cnt;
  logic [31:0] stat_sched_victim_utility_cnt;
  logic [31:0] stat_sched_victim_decode_cnt;
  logic [31:0] stat_sched_fillblk_wr_prefetch_cnt;
  logic [31:0] stat_sched_fillblk_wr_readcold_cnt;
  logic [31:0] stat_sched_fillblk_cg_prefetch_cnt;
  logic [31:0] stat_sched_fillblk_cg_readcold_cnt;
  logic [31:0] stat_sched_relax_reuse_candidate_cnt;
  logic [31:0] stat_sched_relax_reuse_applied_cnt;
  logic [31:0] stat_sched_relax_reuse_keep_state_cnt;
  logic [31:0] stat_sched_relax_reuse_keep_utility_cnt;
  logic [31:0] stat_sched_relax_reuse_keep_qos_cnt;
  logic [31:0] stat_sched_fill_effect_cnt;
  logic [31:0] stat_sched_protect_effect_cnt;
  logic [31:0] stat_sched_query_take_cnt;
  logic [31:0] stat_sched_temporal_take_cnt;
  logic [31:0] stat_sched_temporal_intent_cnt;
  logic [31:0] stat_sched_temporal_direct_take_cnt;
  logic [31:0] stat_sched_temporal_fill_steal_cnt;
  logic [31:0] stat_sched_temporal_block_rescue_cnt;
  logic [31:0] stat_sched_temporal_output_rescue_cnt;
  logic [31:0] stat_sched_budget_steal_cnt;
  logic [31:0] stat_sched_victim_flip_effect_cnt;
  logic [31:0] stat_sched_backend_issue_take_cnt;
  logic [31:0] stat_sched_backend_take_qstruct_ge3_cnt;
  logic [31:0] stat_sched_backend_take_query_hot_cnt;
  logic [31:0] stat_sched_backend_take_query_warm_cnt;
  logic [31:0] stat_sched_backend_take_service_ge_b8_cnt;
  logic [31:0] stat_sched_backend_take_service_ge_d0_cnt;
  logic [31:0] stat_sched_backend_take_urgency_msb_cnt;
  logic [31:0] stat_sched_backend_take_pressure_cnt;
  logic [31:0] stat_sched_backend_take_hh_recent_cnt;
  logic [31:0] stat_sched_qos_raise_effect_cnt;
  logic [31:0] stat_sched_query_fill_block_overlap_cnt;
  logic [31:0] stat_sched_hh_fill_block_overlap_cnt;
  logic [31:0] stat_sched_backend_fill_block_overlap_cnt;
  logic [31:0] stat_sched_query_baseprotect_overlap_cnt;
  logic [31:0] stat_sched_hh_baseprotect_overlap_cnt;
  logic [31:0] stat_sched_backend_baseprotect_overlap_cnt;
`endif

  assign idx_cur = seq_id[ATTN_IDX_W-1:0] ^ {layer, head};

  always @(*) begin
    same_stream = 1'b0;
    token_delta = {TOKEN_W{1'b0}};
    token_vrecent = 1'b0;
    token_recent = 1'b0;
    reuse_hot = 1'b0;
    decode_hot = 1'b0;
    prefill_cold = 1'b0;
    utility_hot_base = 1'b0;
    utility_warm_base = 1'b0;
    utility_hot = 1'b0;
    utility_warm = 1'b0;
    primary_query_promote = 1'b0;
    primary_temporal_promote = 1'b0;
    relax_reuse_candidate = 1'b0;
    relax_reuse_applied = 1'b0;
    relax_reuse_keep_state = 1'b0;
    relax_reuse_keep_utility = 1'b0;
    relax_reuse_keep_qos = 1'b0;
    reuse_ownership_steal = 1'b0;
    victim_protect_reuse_cause_raw = 1'b0;
    prepromo_victim_protect_utility_cause = 1'b0;
    prepromo_victim_protect_decode_cause = 1'b0;
    prepromo_base_victim_protect = 1'b0;
    victim_protect_reuse_cause = 1'b0;
    victim_protect_utility_cause = 1'b0;
    victim_protect_decode_cause = 1'b0;
    prepromo_fill_block_wr_prefetch_cause = 1'b0;
    prepromo_fill_block_wr_readcold_cause = 1'b0;
    prepromo_fill_block_cg_prefetch_cause = 1'b0;
    prepromo_fill_block_cg_readcold_cause = 1'b0;
    prepromo_base_fill_allow = 1'b1;
    fill_block_wr_prefetch_cause = 1'b0;
    fill_block_wr_readcold_cause = 1'b0;
    fill_block_cg_prefetch_cause = 1'b0;
    fill_block_cg_readcold_cause = 1'b0;
    readcold_backoff = 1'b0;
    ownership_query_intent = 1'b0;
    ownership_temporal_intent = 1'b0;
    direct_query_force_take = 1'b0;
    direct_temporal_force_take = 1'b0;
    backend_issue_seed_take = 1'b0;
    backend_issue_protect_steal = 1'b0;
    backend_issue_fill_rescue = 1'b0;
    backend_issue_gate_ok = 1'b1;
    backend_issue_roi_pressure_ok = 1'b1;
    backend_issue_high_service_escape = 1'b0;
    overlap_query_fill_block = 1'b0;
    overlap_hh_fill_block = 1'b0;
    overlap_backend_fill_block = 1'b0;
    overlap_query_baseprotect = 1'b0;
    overlap_hh_baseprotect = 1'b0;
    overlap_backend_baseprotect = 1'b0;
    fill_ownership_override = 1'b0;
    fill_ownership_query_drive = 1'b0;
    fill_ownership_temporal_drive = 1'b0;
    master_query_fill_steal = 1'b0;
    master_temporal_fill_steal = 1'b0;
    master_query_block_rescue = 1'b0;
    master_temporal_block_rescue = 1'b0;
      master_query_output_rescue = 1'b0;
      master_temporal_output_rescue = 1'b0;
    master_output_rescue = 1'b0;
    master_protect_mask = 1'b0;
    temporal_query_shadow_guard = 1'b0;
    ownership_qos_floor = 3'd0;
    sched_qos_pre_owner = 3'd0;
    if (meta_valid && last_token_valid[idx_cur]) begin
      same_stream = (last_seq_id[idx_cur] == seq_id) &&
                    (last_layer[idx_cur] == layer) &&
                    (last_head[idx_cur] == head) &&
                    (last_kv_kind[idx_cur] == kv_kind);
      if (token >= last_token[idx_cur]) begin
        token_delta = token - last_token[idx_cur];
      end else begin
        token_delta = last_token[idx_cur] - token;
      end
      token_vrecent = same_stream && (token_delta <= TOKEN_W'(3));
      token_recent = same_stream && (token_delta <= TOKEN_W'(15));
    end
    utility_hot_base = meta_valid && (utility_hh_protect || utility_query_hot);
    utility_warm_base = meta_valid &&
                        (utility_hot_base || utility_recent_keep || utility_query_warm);
    temporal_hot = meta_valid && (utility_temporal_hot || utility_long_distance_hot);
    temporal_warm = meta_valid && (temporal_hot || utility_temporal_warm);
    query_struct_hot = meta_valid && utility_structured_hot;
    // In structured/query-heavy traffic, prefer the query-owned path unless
    // temporal evidence is backed by recent or HH protection. Keep this guard
    // intentionally aggressive for structured-hot lines so strong-model
    // MDQA/CMQA does not collapse into temporal-direct bypass behavior.
    temporal_query_shadow_guard = meta_valid &&
                                  query_struct_hot &&
                                  temporal_warm &&
                                  !utility_recent_keep &&
                                  !utility_hh_protect;
    sched_pressure = hbm_write_pressure || hbm_congested || (hbm_q_level >= HBM_Q_W'(4));
    backend_issue_roi_pressure_ok =
      !BACKEND_ISSUE_ROI_PRESSURE_GATE_EN ||
      ((hbm_write_pressure || hbm_congested || (hbm_q_level >= HBM_Q_W'(3))) &&
       (utility_service_criticality >= BACKEND_ISSUE_HIGH_SERVICE_TH));
    reuse_hot = meta_valid && same_stream && token_vrecent;
    primary_query_promote = PROMOTE_QUERY_TEMPORAL_PRIMARY_UTILITY_EN &&
                            meta_valid &&
                            !is_prefetch &&
                            query_struct_hot &&
                            (utility_query_warm ||
                             utility_recent_keep ||
                             utility_hh_protect ||
                             (utility_sched_urgency_hint >= kcmu_pkg::KCMU_SCHED_HINT_W'(1))) &&
                            (sched_pressure ||
                             (phase == kcmu_pkg::KCMU_PHASE_DECODE) ||
                             !reuse_hot ||
                             (base_qos >= PROMOTE_QUERY_TEMPORAL_QOS_TH));
    primary_temporal_promote = PROMOTE_QUERY_TEMPORAL_PRIMARY_UTILITY_EN &&
                               meta_valid &&
                               !is_prefetch &&
                               (temporal_hot ||
                                (temporal_warm &&
                                 utility_sched_urgency_hint[kcmu_pkg::KCMU_SCHED_HINT_W-1])) &&
                               !temporal_query_shadow_guard &&
                               (sched_pressure ||
                                (phase == kcmu_pkg::KCMU_PHASE_DECODE) ||
                                !reuse_hot ||
                                (base_qos >= PROMOTE_QUERY_TEMPORAL_QOS_TH));
    utility_hot = meta_valid &&
                  (utility_hot_base ||
                   primary_query_promote ||
                   (primary_temporal_promote && temporal_hot));
    utility_warm = meta_valid &&
                   (utility_warm_base ||
                    primary_query_promote ||
                    primary_temporal_promote);
    decode_hot = meta_valid &&
                 (phase == kcmu_pkg::KCMU_PHASE_DECODE) &&
                 (reuse_hot || utility_hot || ((layer <= 3'd1) && (head == 2'd0)) || (base_qos >= 3'd5));
    prefill_cold = meta_valid &&
                   (phase == kcmu_pkg::KCMU_PHASE_PREFILL) &&
                   !reuse_hot &&
                   !utility_warm &&
                   !token_recent;
    sem_critical = meta_valid &&
                   (decode_hot ||
                    reuse_hot ||
                    utility_hot ||
                    ((phase == kcmu_pkg::KCMU_PHASE_DECODE) && (base_qos >= 3'd5)) ||
                    ((layer <= 3'd1) && (head == 2'd0)));

    qos_tmp = base_qos;
    if (is_read && (qos_tmp < 3'd7)) begin
      qos_tmp = qos_tmp + 3'd1;
    end
    if (meta_valid && decode_hot && (qos_tmp < 3'd7)) begin
      qos_tmp = qos_tmp + 3'd1;
    end
    if (meta_valid && ((layer <= 3'd1) && (head == 2'd0)) && (qos_tmp < 3'd7)) begin
      qos_tmp = qos_tmp + 3'd1;
    end
    if (meta_valid && reuse_hot && (qos_tmp < 3'd7)) begin
      qos_tmp = qos_tmp + 3'd1;
    end
    if (meta_valid && utility_hot && (qos_tmp < 3'd7)) begin
      qos_tmp = qos_tmp + 3'd1;
    end
    if (meta_valid && !utility_hot && utility_warm && (phase == kcmu_pkg::KCMU_PHASE_DECODE) && (qos_tmp < 3'd7)) begin
      qos_tmp = qos_tmp + 3'd1;
    end
    if (meta_valid && (kv_kind == kcmu_pkg::KCMU_KV_KIND_K) &&
        (reuse_hot || decode_hot || (base_qos >= 3'd5)) &&
        (qos_tmp < 3'd7)) begin
      qos_tmp = qos_tmp + 3'd1;
    end
    if (prefill_cold && (qos_tmp > 3'd0)) begin
      qos_tmp = qos_tmp - 3'd1;
    end
    if (is_prefetch && (qos_tmp > 3'd0)) begin
      qos_tmp = qos_tmp - 3'd1;
    end
    if (hbm_q_level >= HBM_Q_W'(4) &&
        (qos_tmp > 3'd0) &&
        (is_prefetch || !sem_critical)) begin
      qos_tmp = qos_tmp - 3'd1;
    end
    if (hbm_congested &&
        (qos_tmp > 3'd0) &&
        (is_prefetch || !sem_critical)) begin
      qos_tmp = qos_tmp - 3'd1;
    end
    if (hbm_write_pressure &&
        !sem_critical &&
        (qos_tmp > 3'd0)) begin
      qos_tmp = qos_tmp - 3'd1;
    end

    if (base_qos == 3'd7) begin
      non_meta_cap = 3'd7;
    end else begin
      non_meta_cap = base_qos + 3'd1;
    end

    sched_qos_pre_owner = qos_tmp;
    if (!meta_valid) begin
      // Non-semantic commands should not be overly boosted.
      if (sched_qos_pre_owner > non_meta_cap) begin
        sched_qos_pre_owner = non_meta_cap;
      end
    end
    sched_qos = sched_qos_pre_owner;
    relax_reuse_candidate = RELAX_REUSE_ONLY_PROTECT_UNDER_PRESSURE_EN &&
                            meta_valid &&
                            reuse_hot &&
                            (hbm_write_pressure || hbm_congested);
    relax_reuse_keep_state = relax_reuse_candidate &&
                             (utility_hh_protect || utility_recent_keep);
    relax_reuse_keep_utility = relax_reuse_candidate &&
                               !relax_reuse_keep_state &&
                               utility_warm;
    relax_reuse_keep_qos = relax_reuse_candidate &&
                           !relax_reuse_keep_state &&
                           !relax_reuse_keep_utility &&
                           (sched_qos >= RELAX_REUSE_ONLY_PROTECT_QOS_TH);
    relax_reuse_applied = relax_reuse_candidate &&
                          !relax_reuse_keep_state &&
                          !relax_reuse_keep_utility &&
                          !relax_reuse_keep_qos;
    victim_protect_reuse_cause_raw = meta_valid && reuse_hot && !relax_reuse_applied;
    ownership_query_intent = meta_valid &&
                             query_struct_hot &&
                             (utility_query_hot ||
                              (utility_sched_urgency_hint >= kcmu_pkg::KCMU_SCHED_HINT_W'(1))) &&
                             (sched_pressure ||
                              (phase == kcmu_pkg::KCMU_PHASE_DECODE) ||
                              (hbm_q_level >= HBM_Q_W'(3)));
    ownership_temporal_intent = meta_valid &&
                                (temporal_hot || (temporal_warm && utility_sched_urgency_hint[kcmu_pkg::KCMU_SCHED_HINT_W-1])) &&
                                !temporal_query_shadow_guard &&
                                (sched_pressure ||
                                 (phase == kcmu_pkg::KCMU_PHASE_DECODE) ||
                                 !reuse_hot);
    direct_query_force_take = FORCE_QUERY_TEMPORAL_DIRECT_TAKE_EN &&
                              meta_valid &&
                              is_read &&
                              !is_prefetch &&
                              (query_struct_hot || utility_query_hot || utility_query_warm) &&
                              (utility_query_warm ||
                               utility_hh_protect ||
                               utility_recent_keep ||
                               (utility_sched_urgency_hint != kcmu_pkg::KCMU_SCHED_HINT_W'(0)) ||
                               temporal_query_shadow_guard ||
                               (phase == kcmu_pkg::KCMU_PHASE_DECODE));
    direct_temporal_force_take = FORCE_QUERY_TEMPORAL_DIRECT_TAKE_EN &&
                                 meta_valid &&
                                 is_read &&
                                 !is_prefetch &&
                                 (temporal_hot || temporal_warm) &&
                                 (temporal_hot ||
                                  utility_sched_urgency_hint[kcmu_pkg::KCMU_SCHED_HINT_W-1] ||
                                  (utility_hh_protect && !utility_recent_keep) ||
                                  (phase == kcmu_pkg::KCMU_PHASE_DECODE)) &&
                                 !temporal_query_shadow_guard;
    reuse_ownership_steal = STEAL_REUSE_ONLY_OWNERSHIP_EN &&
                            victim_protect_reuse_cause_raw &&
                            !utility_hh_protect &&
                            !utility_recent_keep &&
                            !is_prefetch &&
                            (sched_qos <= STEAL_REUSE_ONLY_QOS_TH) &&
                            (ownership_query_intent || ownership_temporal_intent);
    ownership_qos_floor = sched_qos_pre_owner;
    if (OWNERSHIP_QOS_FLOOR_EN &&
        meta_valid &&
        !is_prefetch &&
        (sched_pressure || (phase == kcmu_pkg::KCMU_PHASE_DECODE))) begin
      if ((ownership_query_intent ||
           direct_query_force_take ||
           query_struct_hot ||
           utility_query_hot ||
           utility_query_warm ||
           utility_hh_protect) &&
          (ownership_qos_floor < OWNERSHIP_QOS_FLOOR)) begin
        ownership_qos_floor = OWNERSHIP_QOS_FLOOR;
      end
      if ((ownership_temporal_intent ||
           direct_temporal_force_take ||
           temporal_hot) &&
          (ownership_qos_floor < OWNERSHIP_QOS_FLOOR)) begin
        ownership_qos_floor = OWNERSHIP_QOS_FLOOR;
      end
      if (backend_issue_seed_take &&
          (ownership_qos_floor < OWNERSHIP_QOS_BACKEND_FLOOR)) begin
        ownership_qos_floor = OWNERSHIP_QOS_BACKEND_FLOOR;
      end
    end
    sched_qos = ownership_qos_floor;
    sched_qos_raise_effect = meta_valid && (ownership_qos_floor > sched_qos_pre_owner);
    hot_hint = meta_valid &&
               (reuse_hot ||
                utility_hot ||
                (decode_hot && (sched_qos >= 3'd5)) ||
                (sched_qos >= 3'd6));
    victim_protect_reuse_cause = victim_protect_reuse_cause_raw &&
                                 !reuse_ownership_steal;
    prepromo_victim_protect_utility_cause = meta_valid &&
                                            !victim_protect_reuse_cause &&
                                            utility_hot_base;
    prepromo_victim_protect_decode_cause = meta_valid &&
                                           !victim_protect_reuse_cause &&
                                           !prepromo_victim_protect_utility_cause &&
                                           decode_hot && (sched_qos >= 3'd6);
    prepromo_base_victim_protect = victim_protect_reuse_cause ||
                                   prepromo_victim_protect_utility_cause ||
                                   prepromo_victim_protect_decode_cause;
    master_query_fill_steal = MASTER_OWNERSHIP_FILL_STEAL_EN &&
                              meta_valid &&
                              is_read &&
                              !is_prefetch &&
                              prepromo_base_victim_protect &&
                              (sched_pressure || (phase == kcmu_pkg::KCMU_PHASE_DECODE)) &&
                              (sched_qos <= MASTER_OWNERSHIP_FILL_STEAL_QOS_TH) &&
                              (query_struct_hot ||
                               utility_query_hot ||
                               utility_query_warm ||
                               utility_hh_protect ||
                               utility_recent_keep) &&
                              ((utility_sched_urgency_hint != kcmu_pkg::KCMU_SCHED_HINT_W'(0)) ||
                               query_struct_hot ||
                               utility_query_hot);
    master_temporal_fill_steal = MASTER_OWNERSHIP_FILL_STEAL_EN &&
                                 meta_valid &&
                                 is_read &&
                                 !is_prefetch &&
                                 prepromo_base_victim_protect &&
                                 (sched_pressure || (phase == kcmu_pkg::KCMU_PHASE_DECODE)) &&
                                 (sched_qos <= MASTER_OWNERSHIP_FILL_STEAL_QOS_TH) &&
                                 (temporal_hot || temporal_warm) &&
                                 ((utility_sched_urgency_hint != kcmu_pkg::KCMU_SCHED_HINT_W'(0)) ||
                                  temporal_hot) &&
                                 !temporal_query_shadow_guard;
    master_protect_mask = master_query_fill_steal || master_temporal_fill_steal;
    victim_protect_utility_cause = meta_valid && !victim_protect_reuse_cause && utility_hot;
    victim_protect_decode_cause = meta_valid &&
                                  !victim_protect_reuse_cause &&
                                  !victim_protect_utility_cause &&
                                  decode_hot && (sched_qos >= 3'd6);
    if (master_protect_mask) begin
      victim_protect_reuse_cause = 1'b0;
      victim_protect_utility_cause = 1'b0;
      victim_protect_decode_cause = 1'b0;
    end
    base_victim_protect = victim_protect_reuse_cause ||
                          victim_protect_utility_cause ||
                          victim_protect_decode_cause;

    prefetch_allow = 1'b1;
    if (meta_valid && (phase == kcmu_pkg::KCMU_PHASE_PREFILL) && !reuse_hot && is_prefetch) begin
      prefetch_allow = 1'b0;
    end
    if (hbm_prefetch_block &&
        !victim_protect &&
        (sched_qos < 3'd5) &&
        (is_prefetch || prefill_cold)) begin
      prefetch_allow = 1'b0;
    end
    if (hbm_congested &&
        !victim_protect &&
        (sched_qos < 3'd4) &&
        (is_prefetch || prefill_cold)) begin
      prefetch_allow = 1'b0;
    end

    prepromo_base_fill_allow = 1'b1;
`ifdef KCMU_CFG_FPGA_KILOSCORE_POLICY_SIGSAFE_READCOLD_BACKOFF_V780
    readcold_backoff = meta_valid &&
                       is_read &&
                       !is_prefetch &&
                       (phase == kcmu_pkg::KCMU_PHASE_DECODE) &&
                       utility_policy_select_s5 &&
                       ((utility_query_structure_class >= kcmu_pkg::KCMU_DESC_CLASS_W'(2)) ||
                        query_struct_hot ||
                        (utility_service_criticality >= SCORE_W'(8'hB8)));
`endif
    prepromo_fill_block_wr_prefetch_cause = hbm_write_pressure &&
                                            !prepromo_base_victim_protect &&
                                            (sched_qos < 3'd4) &&
                                            (is_prefetch || prefill_cold);
    prepromo_fill_block_wr_readcold_cause = hbm_write_pressure &&
                                            !prepromo_base_victim_protect &&
                                            (sched_qos < 3'd4) &&
                                            is_read && !utility_warm_base &&
                                            !decode_hot && !reuse_hot &&
                                            !readcold_backoff;
    prepromo_fill_block_cg_prefetch_cause = hbm_congested &&
                                            !prepromo_base_victim_protect &&
                                            (sched_qos < 3'd3) &&
                                            (is_prefetch || prefill_cold);
    prepromo_fill_block_cg_readcold_cause = hbm_congested &&
                                            !prepromo_base_victim_protect &&
                                            (sched_qos < 3'd3) &&
                                            is_read && !utility_warm_base &&
                                            !decode_hot && !reuse_hot &&
                                            !readcold_backoff;
    if (prepromo_fill_block_wr_prefetch_cause ||
        prepromo_fill_block_wr_readcold_cause ||
        prepromo_fill_block_cg_prefetch_cause ||
        prepromo_fill_block_cg_readcold_cause) begin
      prepromo_base_fill_allow = 1'b0;
    end

    master_query_block_rescue = MASTER_OWNERSHIP_BLOCK_RESCUE_EN &&
                                meta_valid &&
                                is_read &&
                                !is_prefetch &&
                                !prepromo_base_fill_allow &&
                                !prepromo_base_victim_protect &&
                                (sched_pressure || (phase == kcmu_pkg::KCMU_PHASE_DECODE)) &&
                                (query_struct_hot ||
                                 utility_query_hot ||
                                 utility_query_warm) &&
                                ((utility_sched_urgency_hint != kcmu_pkg::KCMU_SCHED_HINT_W'(0)) ||
                                 query_struct_hot ||
                                 utility_query_hot ||
                                 utility_hh_protect ||
                                 utility_recent_keep);
    master_temporal_block_rescue = MASTER_OWNERSHIP_BLOCK_RESCUE_EN &&
                                   meta_valid &&
                                   is_read &&
                                   !is_prefetch &&
                                   !prepromo_base_fill_allow &&
                                   !prepromo_base_victim_protect &&
                                   (sched_pressure || (phase == kcmu_pkg::KCMU_PHASE_DECODE)) &&
                                   (temporal_hot || temporal_warm) &&
                                   ((utility_sched_urgency_hint != kcmu_pkg::KCMU_SCHED_HINT_W'(0)) ||
                                    temporal_hot ||
                                    utility_hh_protect ||
                                    utility_recent_keep) &&
                                   !temporal_query_shadow_guard;

    base_fill_allow = 1'b1;
    fill_block_wr_prefetch_cause = hbm_write_pressure &&
                                   !base_victim_protect &&
                                   (sched_qos < 3'd4) &&
                                   (is_prefetch || prefill_cold);
    fill_block_wr_readcold_cause = hbm_write_pressure &&
                                   !base_victim_protect &&
                                   (sched_qos < 3'd4) &&
                                   is_read && !utility_warm &&
                                   !decode_hot && !reuse_hot &&
                                   !readcold_backoff;
    fill_block_cg_prefetch_cause = hbm_congested &&
                                   !base_victim_protect &&
                                   (sched_qos < 3'd3) &&
                                   (is_prefetch || prefill_cold);
    fill_block_cg_readcold_cause = hbm_congested &&
                                   !base_victim_protect &&
                                   (sched_qos < 3'd3) &&
                                   is_read && !utility_warm &&
                                   !decode_hot && !reuse_hot &&
                                   !readcold_backoff;
    if (fill_block_wr_prefetch_cause ||
        fill_block_wr_readcold_cause ||
        fill_block_cg_prefetch_cause ||
        fill_block_cg_readcold_cause) begin
      base_fill_allow = 1'b0;
    end

    fill_ownership_query_drive = OVERRIDE_FILL_BLOCK_WITH_UTILITY_EN &&
                                 meta_valid &&
                                 is_read &&
                                 !is_prefetch &&
                                 !base_fill_allow &&
                                 query_struct_hot &&
                                 utility_query_warm &&
                                 (sched_qos <= OVERRIDE_FILL_BLOCK_QOS_TH) &&
                                 (utility_sched_urgency_hint[kcmu_pkg::KCMU_SCHED_HINT_W-1] ||
                                  sched_pressure);
    fill_ownership_temporal_drive = OVERRIDE_FILL_BLOCK_WITH_UTILITY_EN &&
                                    meta_valid &&
                                    is_read &&
                                    !is_prefetch &&
                                    !base_fill_allow &&
                                    temporal_warm &&
                                    (sched_qos <= OVERRIDE_FILL_BLOCK_QOS_TH) &&
                                    (utility_sched_urgency_hint[kcmu_pkg::KCMU_SCHED_HINT_W-1] ||
                                     sched_pressure) &&
                                    !temporal_query_shadow_guard;
    fill_ownership_override = fill_ownership_query_drive ||
                              fill_ownership_temporal_drive ||
                              (OVERRIDE_FILL_BLOCK_WITH_UTILITY_EN &&
                               meta_valid &&
                               is_read &&
                               !is_prefetch &&
                               !base_fill_allow &&
                               utility_hh_protect &&
                               (sched_qos <= OVERRIDE_FILL_BLOCK_QOS_TH) &&
                               (utility_sched_urgency_hint[kcmu_pkg::KCMU_SCHED_HINT_W-1] ||
                                sched_pressure));

    backend_issue_high_service_escape =
      BACKEND_ISSUE_HIGH_SERVICE_ESCAPE_EN &&
      (utility_service_criticality >= BACKEND_ISSUE_HIGH_SERVICE_TH);
    backend_issue_strong_query_gate_active =
      BACKEND_ISSUE_STRONG_QUERY_GATE_EN ||
      backend_issue_dynamic_strong_query_gate;
    backend_issue_gate_ok =
      !backend_issue_strong_query_gate_active ||
      !utility_policy_select_s5 ||
      (utility_query_structure_class >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) ||
      backend_issue_high_service_escape;
    backend_issue_seed_take = BACKEND_ISSUE_RESCUE_EN &&
                              backend_issue_gate_ok &&
                              backend_issue_roi_pressure_ok &&
                              meta_valid &&
                              is_read &&
                              !is_prefetch &&
                              (sched_qos <= BACKEND_ISSUE_RESCUE_QOS_TH) &&
                              (utility_sched_urgency_hint != kcmu_pkg::KCMU_SCHED_HINT_W'(0)) &&
                              (query_struct_hot ||
                               temporal_warm ||
                               utility_hh_protect ||
                               utility_recent_keep ||
                               fill_ownership_override);
    backend_issue_protect_steal = backend_issue_seed_take &&
                                  (victim_protect_reuse_cause_raw ||
                                   (prepromo_base_victim_protect &&
                                    !utility_hh_protect &&
                                    !utility_hot_base &&
                                    !decode_hot));
    backend_issue_fill_rescue = backend_issue_seed_take &&
                                !base_fill_allow &&
                                (fill_block_wr_prefetch_cause ||
                                 fill_block_wr_readcold_cause ||
                                 fill_block_cg_prefetch_cause ||
                                 fill_block_cg_readcold_cause);
    overlap_query_fill_block = meta_valid &&
                               is_read &&
                               !is_prefetch &&
                               !base_fill_allow &&
                               (query_struct_hot || utility_query_hot || utility_query_warm);
    overlap_hh_fill_block = meta_valid &&
                            is_read &&
                            !is_prefetch &&
                            !base_fill_allow &&
                            (utility_hh_protect || utility_recent_keep);
    overlap_backend_fill_block = backend_issue_seed_take && !base_fill_allow;
    overlap_query_baseprotect = meta_valid &&
                                is_read &&
                                !is_prefetch &&
                                prepromo_base_victim_protect &&
                                (query_struct_hot || utility_query_hot || utility_query_warm);
    overlap_hh_baseprotect = meta_valid &&
                             is_read &&
                             !is_prefetch &&
                             prepromo_base_victim_protect &&
                             (utility_hh_protect || utility_recent_keep);
    overlap_backend_baseprotect = backend_issue_seed_take && prepromo_base_victim_protect;
    master_query_output_rescue = MASTER_OUTPUT_RESCUE_EN &&
                                 meta_valid &&
                                 is_read &&
                                 !is_prefetch &&
                                 (prepromo_base_victim_protect || !base_fill_allow) &&
                                 (sched_pressure || (phase == kcmu_pkg::KCMU_PHASE_DECODE)) &&
                                 (sched_qos <= MASTER_OUTPUT_RESCUE_QOS_TH) &&
                                 (query_struct_hot || utility_query_hot || utility_query_warm) &&
                                 (utility_hh_protect ||
                                  utility_recent_keep ||
                                  (utility_sched_urgency_hint != kcmu_pkg::KCMU_SCHED_HINT_W'(0)) ||
                                  query_struct_hot ||
                                  utility_query_hot);
    master_temporal_output_rescue = MASTER_OUTPUT_RESCUE_EN &&
                                    meta_valid &&
                                    is_read &&
                                    !is_prefetch &&
                                    (prepromo_base_victim_protect || !base_fill_allow) &&
                                    (sched_pressure || (phase == kcmu_pkg::KCMU_PHASE_DECODE)) &&
                                    (sched_qos <= MASTER_OUTPUT_RESCUE_QOS_TH) &&
                                    (temporal_hot || temporal_warm) &&
                                    (utility_hh_protect ||
                                     utility_recent_keep ||
                                     (utility_sched_urgency_hint != kcmu_pkg::KCMU_SCHED_HINT_W'(0)) ||
                                     temporal_hot) &&
                                    !temporal_query_shadow_guard;
    master_output_rescue = master_query_output_rescue || master_temporal_output_rescue;
    ownership_query_take = direct_query_force_take ||
                           master_query_fill_steal ||
                           master_query_block_rescue ||
                           master_query_output_rescue ||
                           (ownership_query_intent &&
                            (!base_victim_protect || reuse_ownership_steal));
    ownership_temporal_take = direct_temporal_force_take ||
                              master_temporal_fill_steal ||
                              master_temporal_block_rescue ||
                              master_temporal_output_rescue ||
                              (ownership_temporal_intent &&
                               (!base_victim_protect || reuse_ownership_steal));
    ownership_query_protect_take = ownership_query_take &&
                                   !(MASTER_OWNERSHIP_FILL_ONLY_EN &&
                                     master_query_fill_steal) &&
                                   !master_query_block_rescue &&
                                   !master_query_output_rescue;
    ownership_temporal_protect_take = ownership_temporal_take &&
                                      !(MASTER_OWNERSHIP_FILL_ONLY_EN &&
                                        master_temporal_fill_steal) &&
                                      !master_temporal_block_rescue &&
                                      !master_temporal_output_rescue;
    ownership_budget_steal = reuse_ownership_steal ||
                             (master_query_fill_steal &&
                              !MASTER_OWNERSHIP_FILL_ONLY_EN) ||
                             (master_temporal_fill_steal &&
                              !MASTER_OWNERSHIP_FILL_ONLY_EN) ||
                             (relax_reuse_applied &&
                              (ownership_query_take || ownership_temporal_take)) ||
                             backend_issue_protect_steal;
    backend_issue_force_take = BACKEND_ISSUE_OWNERSHIP_EN &&
                               backend_issue_gate_ok &&
                               backend_issue_roi_pressure_ok &&
                               ownership_backend_issue_take &&
                               !is_prefetch &&
                               (sched_qos <= BACKEND_ISSUE_OWNERSHIP_QOS_TH);
    ownership_protect_take = ownership_query_protect_take ||
                             ownership_temporal_protect_take ||
                             (backend_issue_force_take && !prepromo_base_victim_protect) ||
                             backend_issue_protect_steal;
    ownership_fill_take = (meta_valid &&
                           is_read &&
                           !is_prefetch &&
                           (master_query_fill_steal ||
                            master_temporal_fill_steal ||
                            master_query_block_rescue ||
                            master_temporal_block_rescue ||
                            master_query_output_rescue ||
                            master_temporal_output_rescue)) ||
                          (meta_valid &&
                           !base_fill_allow &&
                           (ownership_query_take ||
                            ownership_temporal_take ||
                            backend_issue_force_take ||
                            backend_issue_fill_rescue ||
                            (query_struct_hot && utility_query_warm && utility_sched_urgency_hint[kcmu_pkg::KCMU_SCHED_HINT_W-1]) ||
                            fill_ownership_override));
    ownership_backend_issue_take = backend_issue_gate_ok &&
                                   backend_issue_roi_pressure_ok &&
                                   meta_valid &&
                                   (ownership_query_take ||
                                    ownership_temporal_take ||
                                    utility_hh_protect ||
                                    fill_ownership_override ||
                                    backend_issue_protect_steal ||
                                    backend_issue_fill_rescue) &&
                                   (utility_sched_urgency_hint[kcmu_pkg::KCMU_SCHED_HINT_W-1] ||
                                    sched_pressure) &&
                                   is_read;

    sched_fill_req = meta_valid &&
                     is_read &&
                     !is_prefetch &&
                     (ownership_query_intent ||
                      ownership_temporal_intent ||
                      master_query_fill_steal ||
                      master_temporal_fill_steal ||
                      master_query_block_rescue ||
                      master_temporal_block_rescue ||
                      master_query_output_rescue ||
                      master_temporal_output_rescue ||
                      backend_issue_fill_rescue ||
                      fill_ownership_override ||
                      direct_query_force_take ||
                      direct_temporal_force_take ||
                      backend_issue_seed_take);
    sched_fill_take = ownership_fill_take || master_output_rescue;
    sched_protect_req = meta_valid &&
                        is_read &&
                        (ownership_query_intent ||
                         ownership_temporal_intent ||
                         master_query_output_rescue ||
                         master_temporal_output_rescue ||
                         backend_issue_protect_steal ||
                         backend_issue_force_take ||
                         utility_hh_protect);
    sched_protect_take = ownership_protect_take ||
                         master_protect_mask ||
                         (master_output_rescue && prepromo_base_victim_protect);
    sched_victim_req = sched_protect_req;
    sched_victim_flip_take = sched_protect_take;
    sched_backend_issue_req = meta_valid &&
                              is_read &&
                              !is_prefetch &&
                              (ownership_backend_issue_take ||
                               backend_issue_seed_take);
    sched_fill_block_window_seen = meta_valid &&
                                   is_read &&
                                   !is_prefetch &&
                                   !base_fill_allow &&
                                   (ownership_query_intent ||
                                    ownership_temporal_intent ||
                                    utility_hh_protect ||
                                    backend_issue_fill_rescue ||
                                    fill_ownership_override ||
                                    (utility_sched_urgency_hint != kcmu_pkg::KCMU_SCHED_HINT_W'(0)));
    sched_query_take = ownership_query_take ||
                       fill_ownership_query_drive ||
                       primary_query_promote;
    sched_temporal_take = ownership_temporal_take ||
                          fill_ownership_temporal_drive ||
                          primary_temporal_promote;
      sched_budget_steal = ownership_budget_steal;
    sched_fill_effect = (ownership_fill_take && !base_fill_allow) ||
                        master_query_fill_steal ||
                        master_temporal_fill_steal ||
                        master_output_rescue ||
                          ((primary_query_promote || primary_temporal_promote) &&
                           !prepromo_base_fill_allow &&
                         base_fill_allow);
    sched_protect_effect = (ownership_protect_take &&
                            (!prepromo_base_victim_protect || reuse_ownership_steal || backend_issue_protect_steal)) ||
                           master_protect_mask ||
                           (master_output_rescue && prepromo_base_victim_protect) ||
                           ((primary_query_promote || primary_temporal_promote) &&
                            !prepromo_base_victim_protect &&
                            base_victim_protect);
    sched_victim_flip_effect = sched_protect_effect;
    sched_backend_issue_take = ownership_backend_issue_take;

    victim_protect = (base_victim_protect && !master_output_rescue) || ownership_protect_take;
    fill_allow = base_fill_allow || ownership_fill_take || master_output_rescue;
    repl_hot_hint = victim_protect ||
                    ownership_fill_take ||
                    master_output_rescue ||
                    (hot_hint && (!meta_valid || token_vrecent || reuse_hot || (sched_qos >= 3'd6)));
    hot_hint = hot_hint || ownership_query_take || ownership_temporal_take;
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      last_token_valid <= {ATTN_CTX{1'b0}};
      for (ai = 0; ai < ATTN_CTX; ai = ai + 1) begin
        last_token[ai] <= {TOKEN_W{1'b0}};
        last_seq_id[ai] <= {kcmu_pkg::KCMU_SEQ_W{1'b0}};
        last_layer[ai] <= 3'd0;
        last_head[ai] <= 2'd0;
        last_phase[ai] <= kcmu_pkg::KCMU_PHASE_PREFILL;
        last_kv_kind[ai] <= kcmu_pkg::KCMU_KV_KIND_K;
      end
`ifndef SYNTHESIS
      stat_sched_hot_hint_cnt <= 32'd0;
      stat_sched_pref_block_cnt <= 32'd0;
      stat_sched_fill_block_cnt <= 32'd0;
      stat_sched_victim_protect_cnt <= 32'd0;
      stat_sched_victim_reuse_cnt <= 32'd0;
      stat_sched_victim_utility_cnt <= 32'd0;
      stat_sched_victim_decode_cnt <= 32'd0;
      stat_sched_fillblk_wr_prefetch_cnt <= 32'd0;
      stat_sched_fillblk_wr_readcold_cnt <= 32'd0;
      stat_sched_fillblk_cg_prefetch_cnt <= 32'd0;
      stat_sched_fillblk_cg_readcold_cnt <= 32'd0;
      stat_sched_relax_reuse_candidate_cnt <= 32'd0;
      stat_sched_relax_reuse_applied_cnt <= 32'd0;
      stat_sched_relax_reuse_keep_state_cnt <= 32'd0;
      stat_sched_relax_reuse_keep_utility_cnt <= 32'd0;
      stat_sched_relax_reuse_keep_qos_cnt <= 32'd0;
      stat_sched_fill_effect_cnt <= 32'd0;
      stat_sched_protect_effect_cnt <= 32'd0;
      stat_sched_query_take_cnt <= 32'd0;
      stat_sched_temporal_take_cnt <= 32'd0;
      stat_sched_temporal_intent_cnt <= 32'd0;
      stat_sched_temporal_direct_take_cnt <= 32'd0;
      stat_sched_temporal_fill_steal_cnt <= 32'd0;
      stat_sched_temporal_block_rescue_cnt <= 32'd0;
      stat_sched_temporal_output_rescue_cnt <= 32'd0;
        stat_sched_budget_steal_cnt <= 32'd0;
        stat_sched_victim_flip_effect_cnt <= 32'd0;
        stat_sched_backend_issue_take_cnt <= 32'd0;
        stat_sched_backend_take_qstruct_ge3_cnt <= 32'd0;
        stat_sched_backend_take_query_hot_cnt <= 32'd0;
        stat_sched_backend_take_query_warm_cnt <= 32'd0;
        stat_sched_backend_take_service_ge_b8_cnt <= 32'd0;
        stat_sched_backend_take_service_ge_d0_cnt <= 32'd0;
        stat_sched_backend_take_urgency_msb_cnt <= 32'd0;
        stat_sched_backend_take_pressure_cnt <= 32'd0;
        stat_sched_backend_take_hh_recent_cnt <= 32'd0;
        stat_sched_qos_raise_effect_cnt <= 32'd0;
        stat_sched_query_fill_block_overlap_cnt <= 32'd0;
        stat_sched_hh_fill_block_overlap_cnt <= 32'd0;
        stat_sched_backend_fill_block_overlap_cnt <= 32'd0;
        stat_sched_query_baseprotect_overlap_cnt <= 32'd0;
        stat_sched_hh_baseprotect_overlap_cnt <= 32'd0;
        stat_sched_backend_baseprotect_overlap_cnt <= 32'd0;
`endif
    end else if (req_valid && req_ready) begin
      if (meta_valid) begin
        last_token[idx_cur] <= token;
        last_seq_id[idx_cur] <= seq_id;
        last_layer[idx_cur] <= layer;
        last_head[idx_cur] <= head;
        last_phase[idx_cur] <= phase;
        last_kv_kind[idx_cur] <= kv_kind;
        last_token_valid[idx_cur] <= 1'b1;
      end
`ifndef SYNTHESIS
      if (repl_hot_hint) stat_sched_hot_hint_cnt <= stat_sched_hot_hint_cnt + 32'd1;
      if (is_prefetch && !prefetch_allow) stat_sched_pref_block_cnt <= stat_sched_pref_block_cnt + 32'd1;
      if (!fill_allow) stat_sched_fill_block_cnt <= stat_sched_fill_block_cnt + 32'd1;
      if (victim_protect) stat_sched_victim_protect_cnt <= stat_sched_victim_protect_cnt + 32'd1;
      if (victim_protect_reuse_cause) stat_sched_victim_reuse_cnt <= stat_sched_victim_reuse_cnt + 32'd1;
      if (victim_protect_utility_cause) stat_sched_victim_utility_cnt <= stat_sched_victim_utility_cnt + 32'd1;
      if (victim_protect_decode_cause) stat_sched_victim_decode_cnt <= stat_sched_victim_decode_cnt + 32'd1;
      if (fill_block_wr_prefetch_cause) stat_sched_fillblk_wr_prefetch_cnt <= stat_sched_fillblk_wr_prefetch_cnt + 32'd1;
      if (fill_block_wr_readcold_cause) stat_sched_fillblk_wr_readcold_cnt <= stat_sched_fillblk_wr_readcold_cnt + 32'd1;
      if (fill_block_cg_prefetch_cause) stat_sched_fillblk_cg_prefetch_cnt <= stat_sched_fillblk_cg_prefetch_cnt + 32'd1;
      if (fill_block_cg_readcold_cause) stat_sched_fillblk_cg_readcold_cnt <= stat_sched_fillblk_cg_readcold_cnt + 32'd1;
      if (relax_reuse_candidate) stat_sched_relax_reuse_candidate_cnt <= stat_sched_relax_reuse_candidate_cnt + 32'd1;
      if (relax_reuse_applied) stat_sched_relax_reuse_applied_cnt <= stat_sched_relax_reuse_applied_cnt + 32'd1;
      if (relax_reuse_keep_state) stat_sched_relax_reuse_keep_state_cnt <= stat_sched_relax_reuse_keep_state_cnt + 32'd1;
      if (relax_reuse_keep_utility) stat_sched_relax_reuse_keep_utility_cnt <= stat_sched_relax_reuse_keep_utility_cnt + 32'd1;
      if (relax_reuse_keep_qos) stat_sched_relax_reuse_keep_qos_cnt <= stat_sched_relax_reuse_keep_qos_cnt + 32'd1;
      if (sched_fill_effect) stat_sched_fill_effect_cnt <= stat_sched_fill_effect_cnt + 32'd1;
      if (sched_protect_effect) stat_sched_protect_effect_cnt <= stat_sched_protect_effect_cnt + 32'd1;
      if (sched_query_take) stat_sched_query_take_cnt <= stat_sched_query_take_cnt + 32'd1;
      if (sched_temporal_take) stat_sched_temporal_take_cnt <= stat_sched_temporal_take_cnt + 32'd1;
      if (ownership_temporal_intent) stat_sched_temporal_intent_cnt <= stat_sched_temporal_intent_cnt + 32'd1;
      if (direct_temporal_force_take) stat_sched_temporal_direct_take_cnt <= stat_sched_temporal_direct_take_cnt + 32'd1;
      if (master_temporal_fill_steal) stat_sched_temporal_fill_steal_cnt <= stat_sched_temporal_fill_steal_cnt + 32'd1;
      if (master_temporal_block_rescue) stat_sched_temporal_block_rescue_cnt <= stat_sched_temporal_block_rescue_cnt + 32'd1;
      if (master_temporal_output_rescue) stat_sched_temporal_output_rescue_cnt <= stat_sched_temporal_output_rescue_cnt + 32'd1;
        if (sched_budget_steal) stat_sched_budget_steal_cnt <= stat_sched_budget_steal_cnt + 32'd1;
        if (sched_victim_flip_effect) stat_sched_victim_flip_effect_cnt <= stat_sched_victim_flip_effect_cnt + 32'd1;
        if (sched_backend_issue_take) begin
          stat_sched_backend_issue_take_cnt <= stat_sched_backend_issue_take_cnt + 32'd1;
          if (utility_query_structure_class >= kcmu_pkg::KCMU_DESC_CLASS_W'(3)) begin
            stat_sched_backend_take_qstruct_ge3_cnt <= stat_sched_backend_take_qstruct_ge3_cnt + 32'd1;
          end
          if (utility_query_hot) stat_sched_backend_take_query_hot_cnt <= stat_sched_backend_take_query_hot_cnt + 32'd1;
          if (utility_query_warm) stat_sched_backend_take_query_warm_cnt <= stat_sched_backend_take_query_warm_cnt + 32'd1;
          if (utility_service_criticality >= SCORE_W'(8'hB8)) begin
            stat_sched_backend_take_service_ge_b8_cnt <= stat_sched_backend_take_service_ge_b8_cnt + 32'd1;
          end
          if (utility_service_criticality >= SCORE_W'(8'hD0)) begin
            stat_sched_backend_take_service_ge_d0_cnt <= stat_sched_backend_take_service_ge_d0_cnt + 32'd1;
          end
          if (utility_sched_urgency_hint[kcmu_pkg::KCMU_SCHED_HINT_W-1]) begin
            stat_sched_backend_take_urgency_msb_cnt <= stat_sched_backend_take_urgency_msb_cnt + 32'd1;
          end
          if (sched_pressure) stat_sched_backend_take_pressure_cnt <= stat_sched_backend_take_pressure_cnt + 32'd1;
          if (utility_hh_protect || utility_recent_keep) begin
            stat_sched_backend_take_hh_recent_cnt <= stat_sched_backend_take_hh_recent_cnt + 32'd1;
          end
        end
        if (sched_qos_raise_effect) stat_sched_qos_raise_effect_cnt <= stat_sched_qos_raise_effect_cnt + 32'd1;
        if (overlap_query_fill_block) stat_sched_query_fill_block_overlap_cnt <= stat_sched_query_fill_block_overlap_cnt + 32'd1;
        if (overlap_hh_fill_block) stat_sched_hh_fill_block_overlap_cnt <= stat_sched_hh_fill_block_overlap_cnt + 32'd1;
        if (overlap_backend_fill_block) stat_sched_backend_fill_block_overlap_cnt <= stat_sched_backend_fill_block_overlap_cnt + 32'd1;
      if (overlap_query_baseprotect) stat_sched_query_baseprotect_overlap_cnt <= stat_sched_query_baseprotect_overlap_cnt + 32'd1;
      if (overlap_hh_baseprotect) stat_sched_hh_baseprotect_overlap_cnt <= stat_sched_hh_baseprotect_overlap_cnt + 32'd1;
      if (overlap_backend_baseprotect) stat_sched_backend_baseprotect_overlap_cnt <= stat_sched_backend_baseprotect_overlap_cnt + 32'd1;
`endif
    end
  end
endmodule

