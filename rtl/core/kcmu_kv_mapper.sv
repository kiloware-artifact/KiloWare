`timescale 1ns/1ps
// ------------------------------------------------------------
// kcmu_kv_mapper.sv
// KV block/page directory mapper.
// ------------------------------------------------------------
module kcmu_kv_mapper #(
  parameter integer ADDR_W = 8,
  parameter integer TOKEN_W = 12,
  parameter integer BLOCK_OFF_BITS = 2,
  parameter integer DIR_ENTRIES = 64,
  parameter integer PT_PAGES = (ADDR_W <= BLOCK_OFF_BITS) ? 1 : (1 << (ADDR_W - BLOCK_OFF_BITS)),
  parameter bit     REAL_KV_LAYOUT_EN = 1'b1,
  parameter integer TOKEN_BLOCK_BITS = 4,
  parameter integer KV_TYPE_ADDR_BIT = -1,
  parameter bit     SCORE_REPL_EN = 1'b1,
  parameter integer SCORE_REPL_HW_WIN = 2,
  parameter logic [3:0] SCORE_PROTECT_TH = 4'd12,
  parameter bit     SCORE_DECAY_EN = 1'b1,
  parameter integer SCORE_DECAY_LOG2 = 5
)(
  input  logic                    clk,
  input  logic                    rst_n,
  input  logic                    access_valid,
  input  logic                    access_ready,
  input  kcmu_pkg::kcmu_op_t      access_op,
  input  logic                    meta_valid,
  input  logic [kcmu_pkg::KCMU_SEQ_W-1:0] seq_id,
  input  kcmu_pkg::kcmu_phase_t   phase,
  input  kcmu_pkg::kcmu_kv_kind_t kv_kind,
  input  logic [2:0]              layer,
  input  logic [1:0]              head,
  input  logic [TOKEN_W-1:0]      token,
  input  logic [ADDR_W-1:0]       logical_addr,
  input  logic [2:0]              attn_hint_qos,
  input  logic                    access_victim_protect,
  input  logic                    access_compress_allow,
  output logic [ADDR_W-1:0]       physical_addr,
  output logic                    map_hit,
  output logic                    map_alloc,
  output logic                    map_overflow,
  output logic [31:0]             stat_map_overflow_cnt_o,
  output logic [31:0]             stat_map_repl_cnt_o,
  output logic [31:0]             stat_map_seq_reclaim_cnt_o
);
  localparam integer LOGICAL_BLK_W = (ADDR_W > BLOCK_OFF_BITS) ? (ADDR_W - BLOCK_OFF_BITS) : 1;
  localparam integer TOKEN_BLOCK_BITS_SAFE = (TOKEN_BLOCK_BITS < 1) ? 1 :
                                             ((TOKEN_BLOCK_BITS > TOKEN_W) ? TOKEN_W : TOKEN_BLOCK_BITS);
  localparam integer TOKEN_BLOCK_W = (TOKEN_W > BLOCK_OFF_BITS) ? (TOKEN_W - BLOCK_OFF_BITS) : 1;
  localparam integer DIR_IDX_W = (DIR_ENTRIES <= 1) ? 1 : $clog2(DIR_ENTRIES);
  localparam integer PAGE_W = (PT_PAGES <= 1) ? 1 : $clog2(PT_PAGES);
  localparam integer EPOCH_W = 8;
  localparam integer DECAY_LOG2_SAFE = (SCORE_DECAY_LOG2 < 1) ? 1 :
                                       ((SCORE_DECAY_LOG2 > EPOCH_W) ? EPOCH_W : SCORE_DECAY_LOG2);
  localparam integer REPL_HW_WIN = (SCORE_REPL_HW_WIN < 1) ? 1 :
                                   ((SCORE_REPL_HW_WIN > DIR_ENTRIES) ? DIR_ENTRIES : SCORE_REPL_HW_WIN);
`ifdef SYNTHESIS
  localparam bit SCORE_REPL_ACTIVE = SCORE_REPL_EN;
  localparam bit SCORE_DECAY_ACTIVE = 1'b0;
`else
  localparam bit SCORE_REPL_ACTIVE = SCORE_REPL_EN;
  localparam bit SCORE_DECAY_ACTIVE = SCORE_DECAY_EN;
`endif

  logic [DIR_ENTRIES-1:0] dir_valid;
  logic [kcmu_pkg::KCMU_SEQ_W-1:0] dir_seq_id [0:DIR_ENTRIES-1];
  logic [2:0]             dir_layer [0:DIR_ENTRIES-1];
  logic [1:0]             dir_head [0:DIR_ENTRIES-1];
  logic                   dir_kv_kind [0:DIR_ENTRIES-1];
  logic [TOKEN_BLOCK_W-1:0] dir_token_block [0:DIR_ENTRIES-1];
  logic [PAGE_W-1:0]      dir_page [0:DIR_ENTRIES-1];
  logic [3:0]             dir_score [0:DIR_ENTRIES-1];
  logic [EPOCH_W-1:0]     dir_touch_epoch [0:DIR_ENTRIES-1];
  logic [DIR_ENTRIES-1:0] dir_hot;
  logic [DIR_ENTRIES-1:0] dir_protect;
  logic [DIR_ENTRIES-1:0] dir_resident_clean;
  logic [DIR_ENTRIES-1:0] dir_resident_dirty;
  logic [DIR_ENTRIES-1:0] dir_evict_pending;
  logic [DIR_ENTRIES-1:0] dir_spilled_to_hbm;
  logic [DIR_ENTRIES-1:0] dir_compressed;

  logic [DIR_IDX_W-1:0] dir_alloc_ptr;
  logic [PAGE_W-1:0]    page_alloc_ptr;
  logic [DIR_IDX_W:0]   dir_used_cnt;
  logic [PAGE_W:0]      page_used_cnt;
  logic                 map_booted = 1'b0;
  logic [EPOCH_W-1:0]   map_epoch;

  logic [LOGICAL_BLK_W-1:0] logical_blk;
  logic [TOKEN_BLOCK_W-1:0] logical_token_block;
  logic [TOKEN_BLOCK_BITS_SAFE-1:0] logical_page_color;
  logic                logical_kv_type;
  logic [DIR_IDX_W-1:0] lookup_base_idx;
  logic [DIR_IDX_W-1:0] lookup_cand_idx;
  logic lookup_hit;
  logic [DIR_IDX_W-1:0] lookup_idx;
  logic [DIR_IDX_W-1:0] repl_idx;
  logic [DIR_IDX_W-1:0] repl_best_idx;
  logic [PAGE_W-1:0] mapped_page;
  logic has_free;
  logic has_repl_cold;
  logic repl_found;
  logic [DIR_IDX_W-1:0] repl_cand_idx;
  logic [3:0] repl_best_score;
  logic [3:0] repl_cand_score;
  logic [EPOCH_W-1:0] repl_best_age;
  logic [EPOCH_W-1:0] repl_cand_age;
  logic [EPOCH_W-1:0] repl_age_i;
  logic                repl_dirty;
  logic                repl_hot;
  logic                repl_protect;
  logic                map_access_active;
  logic                seq_reclaim_req;
  logic [DIR_IDX_W:0]  seq_reclaim_count;
  logic                seq_compress_seed;
  integer di;
  integer wi;

  logic [31:0] stat_map_overflow_cnt;
  logic [31:0] stat_map_repl_cnt;
  logic [31:0] stat_map_seq_reclaim_cnt;
  assign stat_map_overflow_cnt_o = stat_map_overflow_cnt;
  assign stat_map_repl_cnt_o = stat_map_repl_cnt;
  assign stat_map_seq_reclaim_cnt_o = stat_map_seq_reclaim_cnt;
`ifndef SYNTHESIS
  logic [31:0] stat_map_hit_cnt;
  logic [31:0] stat_map_alloc_cnt;
  logic [31:0] stat_map_reclaim_cnt;
  logic [31:0] stat_map_decay_cnt;
  logic [31:0] stat_map_score_repl_cnt;
  logic [31:0] stat_map_protect_skip_cnt;
  logic [31:0] stat_map_dirty_spill_cnt;
  logic [31:0] stat_map_cold_spill_cnt;
`endif

  function automatic logic [DIR_IDX_W-1:0] hash_dir_idx(
    input logic [kcmu_pkg::KCMU_SEQ_W-1:0] in_seq_id,
    input logic [2:0] in_layer,
    input logic [1:0] in_head,
    input logic [TOKEN_BLOCK_W-1:0] in_token_block,
    input logic in_kv_kind,
    input logic [LOGICAL_BLK_W-1:0] in_logical_blk,
    input logic in_meta_valid
  );
    logic [DIR_IDX_W-1:0] hash_v;
    begin
      hash_v = DIR_IDX_W'(in_logical_blk);
      if (in_meta_valid) begin
        hash_v = DIR_IDX_W'(in_seq_id) ^
                 DIR_IDX_W'(in_layer) ^
                 DIR_IDX_W'(in_head) ^
                 DIR_IDX_W'(in_token_block) ^
                 DIR_IDX_W'(in_kv_kind);
      end
      hash_dir_idx = hash_v;
    end
  endfunction

  function automatic logic [3:0] sat_add_score(
    input logic [3:0] in_score,
    input logic [1:0] add_step
  );
    logic [4:0] sum;
    begin
      sum = {1'b0, in_score} + {3'b000, add_step};
      if (sum[4]) begin
        sat_add_score = 4'hf;
      end else begin
        sat_add_score = sum[3:0];
      end
    end
  endfunction

  function automatic logic [1:0] score_step_from_qos(
    input logic [2:0] qos
  );
    begin
      if (qos >= 3'd5) begin
        score_step_from_qos = 2'd2;
      end else begin
        score_step_from_qos = 2'd1;
      end
    end
  endfunction

  function automatic logic [3:0] seed_score_from_qos(
    input logic [2:0] qos
  );
    begin
      seed_score_from_qos = {1'b0, qos};
      if (qos >= 3'd6) begin
        seed_score_from_qos = 4'd9;
      end
    end
  endfunction

  always @(*) begin
    if (ADDR_W > BLOCK_OFF_BITS) begin
      logical_blk = logical_addr[ADDR_W-1:BLOCK_OFF_BITS];
    end else begin
      logical_blk = {LOGICAL_BLK_W{1'b0}};
    end

    if (TOKEN_W > BLOCK_OFF_BITS) begin
      logical_token_block = token[TOKEN_W-1:BLOCK_OFF_BITS];
    end else begin
      logical_token_block = {TOKEN_BLOCK_W{1'b0}};
    end
    logical_page_color = token[TOKEN_W-1 -: TOKEN_BLOCK_BITS_SAFE];
    if ((KV_TYPE_ADDR_BIT >= 0) && (KV_TYPE_ADDR_BIT < ADDR_W)) begin
      logical_kv_type = logical_addr[KV_TYPE_ADDR_BIT];
    end else begin
      logical_kv_type = kv_kind;
    end
    lookup_base_idx = hash_dir_idx(seq_id, layer, head, logical_token_block, logical_kv_type, logical_blk, meta_valid);

    lookup_hit = 1'b0;
    lookup_idx = {DIR_IDX_W{1'b0}};
`ifdef SYNTHESIS
    // Synthesis mode: bounded lookup window to keep combinational depth predictable.
    for (wi = 0; wi < REPL_HW_WIN; wi = wi + 1) begin
      lookup_cand_idx = lookup_base_idx + DIR_IDX_W'(wi);
      if (!lookup_hit &&
          meta_valid &&
          dir_valid[lookup_cand_idx] &&
          (dir_seq_id[lookup_cand_idx] == seq_id) &&
          (dir_layer[lookup_cand_idx] == layer) &&
          (dir_head[lookup_cand_idx] == head) &&
          (dir_kv_kind[lookup_cand_idx] == logical_kv_type) &&
          (dir_token_block[lookup_cand_idx] == logical_token_block)) begin
        lookup_hit = 1'b1;
        lookup_idx = lookup_cand_idx;
      end
    end
`else
    for (di = 0; di < DIR_ENTRIES; di = di + 1) begin
      if (!lookup_hit &&
          meta_valid &&
          dir_valid[di] &&
          (dir_seq_id[di] == seq_id) &&
          (dir_layer[di] == layer) &&
          (dir_head[di] == head) &&
          (dir_kv_kind[di] == logical_kv_type) &&
          (dir_token_block[di] == logical_token_block)) begin
        lookup_hit = 1'b1;
        lookup_idx = di[DIR_IDX_W-1:0];
      end
    end
`endif

    // H2O-style directory replacement with synthesis-safe candidate window.
    // The full scan is kept for simulation. Synthesis uses a bounded window.
    repl_idx = dir_alloc_ptr;
    repl_best_idx = dir_alloc_ptr;
    has_repl_cold = 1'b0;
    repl_found = 1'b0;
    repl_best_score = 4'hf;
    repl_best_age = {EPOCH_W{1'b0}};
    repl_cand_idx = dir_alloc_ptr;
    repl_cand_score = 4'hf;
    repl_cand_age = {EPOCH_W{1'b0}};
    if (SCORE_REPL_ACTIVE) begin
`ifdef SYNTHESIS
      // Fast hardware mode: evaluate only REPL_HW_WIN entries from current RR head.
      for (wi = 0; wi < REPL_HW_WIN; wi = wi + 1) begin
        repl_cand_idx = dir_alloc_ptr + DIR_IDX_W'(wi);
        if (dir_valid[repl_cand_idx] &&
            !dir_protect[repl_cand_idx] &&
            (!dir_hot[repl_cand_idx] || (dir_score[repl_cand_idx] <= SCORE_PROTECT_TH))) begin
          has_repl_cold = 1'b1;
        end
      end
      for (wi = 0; wi < REPL_HW_WIN; wi = wi + 1) begin
        repl_cand_idx = dir_alloc_ptr + DIR_IDX_W'(wi);
        repl_cand_age = map_epoch - dir_touch_epoch[repl_cand_idx];
        repl_cand_score = dir_score[repl_cand_idx];
        if (dir_valid[repl_cand_idx] &&
            (!has_repl_cold || (!dir_protect[repl_cand_idx] &&
                                (!dir_hot[repl_cand_idx] || (repl_cand_score <= SCORE_PROTECT_TH))))) begin
          if (!repl_found ||
              (repl_cand_age > repl_best_age) ||
              ((repl_cand_age == repl_best_age) && (repl_cand_score < repl_best_score))) begin
            repl_found = 1'b1;
            repl_best_score = repl_cand_score;
            repl_best_age = repl_cand_age;
            repl_best_idx = repl_cand_idx;
          end
        end
      end
`else
      for (di = 0; di < DIR_ENTRIES; di = di + 1) begin
        if (dir_valid[di] &&
            !dir_protect[di] &&
            (!dir_hot[di] || (dir_score[di] <= SCORE_PROTECT_TH))) begin
          has_repl_cold = 1'b1;
        end
      end
      for (di = 0; di < DIR_ENTRIES; di = di + 1) begin
        repl_age_i = map_epoch - dir_touch_epoch[di];
        if (dir_valid[di] &&
            (!has_repl_cold || (!dir_protect[di] &&
                                (!dir_hot[di] || (dir_score[di] <= SCORE_PROTECT_TH))))) begin
          if (!repl_found ||
              (repl_age_i > repl_best_age) ||
              ((repl_age_i == repl_best_age) && (dir_score[di] < repl_best_score))) begin
            repl_found = 1'b1;
            repl_best_score = dir_score[di];
            repl_best_age = repl_age_i;
            repl_best_idx = di[DIR_IDX_W-1:0];
          end
        end
      end
`endif
      if (repl_found) begin
        repl_idx = repl_best_idx;
      end
    end

    seq_reclaim_req = meta_valid && (access_op == kcmu_pkg::KCMU_OP_NOP);
    map_access_active = meta_valid && !seq_reclaim_req;
    has_free = (dir_used_cnt < DIR_ENTRIES) && (page_used_cnt < PT_PAGES);
    map_hit = map_access_active && lookup_hit;
    map_alloc = map_access_active && !lookup_hit && has_free;
    map_overflow = map_access_active && !lookup_hit && !has_free;
    repl_dirty = dir_resident_dirty[repl_idx];
    repl_hot = dir_hot[repl_idx];
    repl_protect = dir_protect[repl_idx];
    seq_compress_seed =
      access_compress_allow &&
      (access_op != kcmu_pkg::KCMU_OP_WR) &&
      (phase == kcmu_pkg::KCMU_PHASE_PREFILL) &&
      (attn_hint_qos <= 3'd2) &&
      !access_victim_protect;

    if (lookup_hit) begin
      mapped_page = dir_page[lookup_idx];
    end else if (map_alloc || map_overflow) begin
      // Until page migration/data copy exists, new semantic bindings must
      // preserve logical-page visibility for correctness.
      mapped_page = logical_blk[PAGE_W-1:0];
    end else begin
      mapped_page = logical_blk[PAGE_W-1:0];
    end

    if (ADDR_W > BLOCK_OFF_BITS) begin
      physical_addr = {mapped_page, logical_addr[BLOCK_OFF_BITS-1:0]};
    end else begin
      physical_addr = logical_addr;
    end
  end

  always @(*) begin
    seq_reclaim_count = {(DIR_IDX_W+1){1'b0}};
    if (seq_reclaim_req) begin
      for (di = 0; di < DIR_ENTRIES; di = di + 1) begin
        if (dir_valid[di] && (dir_seq_id[di] == seq_id)) begin
          seq_reclaim_count = seq_reclaim_count + (DIR_IDX_W+1)'(1);
        end
      end
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      // Soft reset only clears transient control state.
      map_epoch <= {EPOCH_W{1'b0}};
    end else if (!map_booted) begin
      map_booted <= 1'b1;
      dir_valid <= {DIR_ENTRIES{1'b0}};
      dir_hot <= {DIR_ENTRIES{1'b0}};
      dir_protect <= {DIR_ENTRIES{1'b0}};
      dir_resident_clean <= {DIR_ENTRIES{1'b0}};
      dir_resident_dirty <= {DIR_ENTRIES{1'b0}};
      dir_evict_pending <= {DIR_ENTRIES{1'b0}};
      dir_spilled_to_hbm <= {DIR_ENTRIES{1'b0}};
      dir_compressed <= {DIR_ENTRIES{1'b0}};
      dir_alloc_ptr <= {DIR_IDX_W{1'b0}};
      page_alloc_ptr <= {PAGE_W{1'b0}};
      dir_used_cnt <= {(DIR_IDX_W+1){1'b0}};
      page_used_cnt <= {(PAGE_W+1){1'b0}};
      map_epoch <= {EPOCH_W{1'b0}};
      for (di = 0; di < DIR_ENTRIES; di = di + 1) begin
        dir_seq_id[di] <= {kcmu_pkg::KCMU_SEQ_W{1'b0}};
        dir_layer[di] <= 3'd0;
        dir_head[di] <= 2'd0;
        dir_kv_kind[di] <= kcmu_pkg::KCMU_KV_KIND_K;
        dir_token_block[di] <= {TOKEN_BLOCK_W{1'b0}};
        dir_page[di] <= {PAGE_W{1'b0}};
        dir_score[di] <= 4'd0;
        dir_touch_epoch[di] <= {EPOCH_W{1'b0}};
      end
`ifndef SYNTHESIS
      stat_map_hit_cnt <= 32'd0;
      stat_map_alloc_cnt <= 32'd0;
      stat_map_overflow_cnt <= 32'd0;
      stat_map_repl_cnt <= 32'd0;
      stat_map_reclaim_cnt <= 32'd0;
      stat_map_decay_cnt <= 32'd0;
      stat_map_score_repl_cnt <= 32'd0;
      stat_map_protect_skip_cnt <= 32'd0;
      stat_map_seq_reclaim_cnt <= 32'd0;
      stat_map_dirty_spill_cnt <= 32'd0;
      stat_map_cold_spill_cnt <= 32'd0;
`else
      stat_map_overflow_cnt <= 32'd0;
      stat_map_repl_cnt <= 32'd0;
      stat_map_seq_reclaim_cnt <= 32'd0;
`endif
    end else if (access_valid && access_ready) begin
      map_epoch <= map_epoch + EPOCH_W'(1);

      if (SCORE_DECAY_ACTIVE && (map_epoch[DECAY_LOG2_SAFE-1:0] == {DECAY_LOG2_SAFE{1'b1}})) begin
        for (di = 0; di < DIR_ENTRIES; di = di + 1) begin
          if (dir_valid[di] && (dir_score[di] != 4'd0)) begin
            dir_score[di] <= dir_score[di] - 4'd1;
          end
          if (dir_valid[di] &&
              dir_hot[di] &&
              ((map_epoch - dir_touch_epoch[di]) >= EPOCH_W'(32)) &&
              (dir_score[di] <= 4'd2)) begin
            dir_hot[di] <= 1'b0;
            dir_protect[di] <= 1'b0;
          end
        end
`ifndef SYNTHESIS
        stat_map_decay_cnt <= stat_map_decay_cnt + 32'd1;
`endif
      end

      if (seq_reclaim_req) begin
        for (di = 0; di < DIR_ENTRIES; di = di + 1) begin
          if (dir_valid[di] && (dir_seq_id[di] == seq_id)) begin
            dir_valid[di] <= 1'b0;
            dir_hot[di] <= 1'b0;
            dir_protect[di] <= 1'b0;
            dir_resident_clean[di] <= 1'b0;
            dir_resident_dirty[di] <= 1'b0;
            dir_evict_pending[di] <= 1'b0;
            dir_spilled_to_hbm[di] <= 1'b0;
            dir_compressed[di] <= 1'b0;
          end
        end
        if (dir_used_cnt > seq_reclaim_count) begin
          dir_used_cnt <= dir_used_cnt - seq_reclaim_count;
        end else begin
          dir_used_cnt <= {(DIR_IDX_W+1){1'b0}};
        end
        if (page_used_cnt > seq_reclaim_count) begin
          page_used_cnt <= page_used_cnt - (PAGE_W+1)'(seq_reclaim_count);
        end else begin
          page_used_cnt <= {(PAGE_W+1){1'b0}};
        end
        if (seq_reclaim_count != {(DIR_IDX_W+1){1'b0}}) begin
          stat_map_seq_reclaim_cnt <= stat_map_seq_reclaim_cnt + 32'(seq_reclaim_count);
`ifndef SYNTHESIS
          stat_map_reclaim_cnt <= stat_map_reclaim_cnt + 32'(seq_reclaim_count);
`endif
        end
      end else if (map_hit) begin
        dir_score[lookup_idx] <= sat_add_score(dir_score[lookup_idx], score_step_from_qos(attn_hint_qos));
        dir_touch_epoch[lookup_idx] <= map_epoch;
        if (attn_hint_qos >= 3'd5) begin
          dir_hot[lookup_idx] <= 1'b1;
        end
        if (attn_hint_qos >= 3'd6) begin
          dir_protect[lookup_idx] <= 1'b1;
        end else if (attn_hint_qos <= 3'd2) begin
          dir_protect[lookup_idx] <= 1'b0;
        end
        dir_evict_pending[lookup_idx] <= 1'b0;
        dir_spilled_to_hbm[lookup_idx] <= 1'b0;
        if (access_op == kcmu_pkg::KCMU_OP_WR) begin
          dir_resident_dirty[lookup_idx] <= 1'b1;
          dir_resident_clean[lookup_idx] <= 1'b0;
          dir_compressed[lookup_idx] <= 1'b0;
        end else begin
          dir_resident_clean[lookup_idx] <= 1'b1;
          if (access_victim_protect || dir_hot[lookup_idx] || dir_protect[lookup_idx]) begin
            dir_compressed[lookup_idx] <= 1'b0;
          end else if (seq_compress_seed && !dir_resident_dirty[lookup_idx]) begin
            dir_compressed[lookup_idx] <= 1'b1;
          end
        end
`ifndef SYNTHESIS
        stat_map_hit_cnt <= stat_map_hit_cnt + 32'd1;
`endif
      end else if (map_alloc) begin
        dir_valid[dir_alloc_ptr] <= 1'b1;
        dir_seq_id[dir_alloc_ptr] <= seq_id;
        dir_layer[dir_alloc_ptr] <= layer;
        dir_head[dir_alloc_ptr] <= head;
        dir_kv_kind[dir_alloc_ptr] <= logical_kv_type;
        dir_token_block[dir_alloc_ptr] <= logical_token_block;
        dir_page[dir_alloc_ptr] <= logical_blk[PAGE_W-1:0];
        dir_score[dir_alloc_ptr] <= seed_score_from_qos(attn_hint_qos);
        dir_touch_epoch[dir_alloc_ptr] <= map_epoch;
        dir_hot[dir_alloc_ptr] <= (attn_hint_qos >= 3'd5);
        dir_protect[dir_alloc_ptr] <= (attn_hint_qos >= 3'd6);
        dir_resident_clean[dir_alloc_ptr] <= (access_op != kcmu_pkg::KCMU_OP_WR);
        dir_resident_dirty[dir_alloc_ptr] <= (access_op == kcmu_pkg::KCMU_OP_WR);
        dir_evict_pending[dir_alloc_ptr] <= 1'b0;
        dir_spilled_to_hbm[dir_alloc_ptr] <= 1'b0;
        dir_compressed[dir_alloc_ptr] <= seq_compress_seed;

        if (dir_alloc_ptr == DIR_IDX_W'(DIR_ENTRIES-1)) begin
          dir_alloc_ptr <= {DIR_IDX_W{1'b0}};
        end else begin
          dir_alloc_ptr <= dir_alloc_ptr + DIR_IDX_W'(1);
        end

        if (page_alloc_ptr == PAGE_W'(PT_PAGES-1)) begin
          page_alloc_ptr <= {PAGE_W{1'b0}};
        end else begin
          page_alloc_ptr <= page_alloc_ptr + PAGE_W'(1);
        end

        if (dir_used_cnt < DIR_ENTRIES) begin
          dir_used_cnt <= dir_used_cnt + (DIR_IDX_W+1)'(1);
        end
        if (page_used_cnt < PT_PAGES) begin
          page_used_cnt <= page_used_cnt + (PAGE_W+1)'(1);
        end
`ifndef SYNTHESIS
        stat_map_alloc_cnt <= stat_map_alloc_cnt + 32'd1;
`endif
      end else if (map_overflow) begin
        dir_valid[repl_idx] <= 1'b1;
        dir_seq_id[repl_idx] <= seq_id;
        dir_layer[repl_idx] <= layer;
        dir_head[repl_idx] <= head;
        dir_kv_kind[repl_idx] <= logical_kv_type;
        dir_token_block[repl_idx] <= logical_token_block;
        // Reclaim directory ownership while preserving logical-page visibility.
        dir_page[repl_idx] <= logical_blk[PAGE_W-1:0];
        dir_score[repl_idx] <= seed_score_from_qos(attn_hint_qos);
        dir_touch_epoch[repl_idx] <= map_epoch;
        dir_hot[repl_idx] <= (attn_hint_qos >= 3'd5);
        dir_protect[repl_idx] <= (attn_hint_qos >= 3'd6);
        dir_resident_clean[repl_idx] <= (access_op != kcmu_pkg::KCMU_OP_WR);
        dir_resident_dirty[repl_idx] <= (access_op == kcmu_pkg::KCMU_OP_WR);
        dir_evict_pending[repl_idx] <= 1'b0;
        dir_spilled_to_hbm[repl_idx] <= 1'b0;
        dir_compressed[repl_idx] <= seq_compress_seed;
        if (dir_alloc_ptr == DIR_IDX_W'(DIR_ENTRIES-1)) begin
          dir_alloc_ptr <= {DIR_IDX_W{1'b0}};
        end else begin
          dir_alloc_ptr <= dir_alloc_ptr + DIR_IDX_W'(1);
        end
        stat_map_overflow_cnt <= stat_map_overflow_cnt + 32'd1;
        stat_map_repl_cnt <= stat_map_repl_cnt + 32'd1;
`ifndef SYNTHESIS
        stat_map_reclaim_cnt <= stat_map_reclaim_cnt + 32'd1;
        if (repl_dirty) begin
          stat_map_dirty_spill_cnt <= stat_map_dirty_spill_cnt + 32'd1;
        end else begin
          stat_map_cold_spill_cnt <= stat_map_cold_spill_cnt + 32'd1;
        end
        if (SCORE_REPL_ACTIVE) begin
          stat_map_score_repl_cnt <= stat_map_score_repl_cnt + 32'd1;
        end
        if (has_repl_cold || repl_hot || repl_protect || access_victim_protect) begin
          stat_map_protect_skip_cnt <= stat_map_protect_skip_cnt + 32'd1;
        end
`endif
      end
    end
  end
endmodule

