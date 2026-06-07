`timescale 1ns/1ps
// ------------------------------------------------------------
// kcmu_prefetcher.sv
// Stride-aware prefetcher with adaptive throttling:
// - learns short-range stride (+/-1, +/-2)
// - only issues after repeated stride confirmation
// - deduplicate repeated candidates
// - keep a small outstanding prefetch queue
// - adapt aggressiveness by usefulness feedback + HBM congestion
// ------------------------------------------------------------
module kcmu_prefetcher #(
  parameter integer ADDR_W = 8,
  parameter logic [2:0] PREFETCH_QOS_TH = 3'd2,
  parameter bit     PF_ADAPT_EN = 1'b1,
  parameter integer PREFETCH_QUEUE_DEPTH = 4,
  parameter integer STRIDE_LOOKAHEAD = 1,
  parameter integer USELESS_CREDIT_TH = 8,
  parameter integer MAX_USELESS_CREDIT = 31,
  parameter integer USEFUL_REWARD_STEP = 2,
  parameter integer MISS_CREDIT_TH = 6,
  parameter integer MAX_MISS_CREDIT = 31,
  parameter integer POLLUTION_CREDIT_TH = 8,
  parameter integer MAX_POLLUTION_CREDIT = 31
)(
  input  logic                 clk,
  input  logic                 rst_n,

  input  logic                 enable,

  input  logic                 access_fire,   // pulse when READ accepted
  input  logic [ADDR_W-1:0]    access_addr,
  input  logic [2:0]           access_qos,
  input  logic                 feedback_fill,
  input  logic                 feedback_useful,
  input  logic                 feedback_demand_miss,
  input  logic                 access_miss_penalty_phase,
  input  logic                 hbm_congested,

  output logic                 pf_valid,
  input  logic                 pf_ready,
  output logic [ADDR_W-1:0]    pf_addr
);

  localparam logic [ADDR_W-1:0] ADDR_MAX = {ADDR_W{1'b1}};
  localparam integer Q_DEPTH = (PREFETCH_QUEUE_DEPTH < 2) ? 2 : PREFETCH_QUEUE_DEPTH;
  localparam integer STRIDE_LOOKAHEAD_SAFE = (STRIDE_LOOKAHEAD < 1) ? 1 : STRIDE_LOOKAHEAD;
  localparam integer USEFUL_REWARD_SAFE = (USEFUL_REWARD_STEP < 1) ? 1 :
                                           ((USEFUL_REWARD_STEP > MAX_USELESS_CREDIT) ? MAX_USELESS_CREDIT : USEFUL_REWARD_STEP);

  logic [Q_DEPTH-1:0] q_valid, q_valid_n;
  logic [ADDR_W-1:0]  q_addr [0:Q_DEPTH-1];
  logic [ADDR_W-1:0]  q_addr_n [0:Q_DEPTH-1];
  logic               last_read_valid;
  logic [ADDR_W-1:0]  last_read_addr;
  logic               last_stride_valid;
  logic signed [ADDR_W:0] last_stride;
  logic [1:0]         stride_streak;
  logic signed [ADDR_W:0] stride_now;
  logic               stride_now_valid;
  logic               stride_match;
  logic signed [ADDR_W:0] push_addr_ext;
  logic               push_in_range;
  logic               warmup_budget_ok;

  logic               push_req;
  logic               stride_req;
  logic               warmup_req;
  logic               miss_penalty_req;
  logic               candidate_req;
  logic               pop_req;
  logic [ADDR_W-1:0]  push_addr;
  logic [ADDR_W-1:0]  push_addr_stride;
  logic               in_queue;
  logic [2:0]         qos_gate_th;
  logic [2:0]         qos_gate_th_stride;
  logic [2:0]         qos_gate_th_miss;
  logic               qos_ok;
  logic [5:0]         useless_credit;
  logic [5:0]         miss_credit;
  logic [5:0]         pollution_credit;
  logic               throttle_block;
  logic               drop_qos;
  logic               drop_throttle;
  integer             qi;
  integer             push_slot;
  integer             qos_th_tmp;
  integer             qos_th_stride_tmp;
  integer             qos_th_miss_tmp;

`ifndef SYNTHESIS
  logic [31:0] stat_pf_push_cnt;
  logic [31:0] stat_pf_pop_cnt;
  logic [31:0] stat_pf_drop_qos_cnt;
  logic [31:0] stat_pf_drop_throttle_cnt;
`endif

  function automatic logic stride_allowed(input logic signed [ADDR_W:0] s);
    integer sval;
    begin
      sval = s;
      if (sval < 0) sval = -sval;
      stride_allowed = ((sval == 1) || (sval == 2));
    end
  endfunction

  always @(*) begin
    stride_now = $signed({1'b0, access_addr}) - $signed({1'b0, last_read_addr});
    stride_now_valid = last_read_valid && stride_allowed(stride_now);
    stride_match = stride_now_valid && last_stride_valid && (stride_now == last_stride);
    push_addr_ext = $signed({1'b0, access_addr}) + (stride_now * STRIDE_LOOKAHEAD_SAFE);
    push_in_range = (push_addr_ext >= $signed({(ADDR_W+1){1'b0}})) &&
                    (push_addr_ext <= $signed({1'b0, ADDR_MAX}));
    if (push_in_range) begin
      push_addr_stride = push_addr_ext[ADDR_W-1:0];
    end else begin
      push_addr_stride = {ADDR_W{1'b0}};
    end
  end

  assign stride_req = stride_match && (stride_streak >= 2'd1) && push_in_range;
  assign warmup_budget_ok = !PF_ADAPT_EN ||
                            (useless_credit < (USELESS_CREDIT_TH + 6));
  assign warmup_req = !stride_req &&
                      (access_addr != ADDR_MAX) &&
                      warmup_budget_ok &&
                      (!hbm_congested || (access_qos >= 3'd5)) &&
                      (
                        (!last_read_valid) ||
                        (stride_now_valid && (stride_streak == 2'd0)) ||
                        (access_qos >= 3'd6)
                      );
  assign miss_penalty_req = !stride_req &&
                            !warmup_req &&
                            PF_ADAPT_EN &&
                            access_miss_penalty_phase &&
                            (access_addr != ADDR_MAX) &&
                            !hbm_congested &&
                            (miss_credit >= 6'(MISS_CREDIT_TH)) &&
                            (pollution_credit < 6'(POLLUTION_CREDIT_TH));
  assign push_addr = stride_req ? push_addr_stride : (access_addr + {{(ADDR_W-1){1'b0}}, 1'b1});
  assign candidate_req = stride_req || warmup_req || miss_penalty_req;

  always @(*) begin
    qos_th_tmp = PREFETCH_QOS_TH;
    if (PF_ADAPT_EN && hbm_congested) begin
      qos_th_tmp = qos_th_tmp + 1;
    end
    if (PF_ADAPT_EN && (useless_credit >= USELESS_CREDIT_TH)) begin
      qos_th_tmp = qos_th_tmp + 1;
    end
    if (qos_th_tmp > 7) begin
      qos_gate_th = 3'd7;
    end else begin
      qos_gate_th = qos_th_tmp[2:0];
    end

    // Stride-like streams get one-step relaxed threshold.
    qos_th_stride_tmp = qos_gate_th;
    if (qos_th_stride_tmp > 0) begin
      qos_th_stride_tmp = qos_th_stride_tmp - 1;
    end
    qos_gate_th_stride = qos_th_stride_tmp[2:0];

    // Miss-penalty mode relaxes by one level only after the rolling miss credit
    // says there is real demand pressure. This keeps uniform/dense scans from
    // getting a free stream when useful feedback is absent.
    qos_th_miss_tmp = qos_gate_th;
    if (qos_th_miss_tmp > 0) begin
      qos_th_miss_tmp = qos_th_miss_tmp - 1;
    end
    qos_gate_th_miss = qos_th_miss_tmp[2:0];
  end

  // Keep confident stride streams alive under congestion while still protecting cold traffic.
  assign throttle_block = PF_ADAPT_EN &&
                          hbm_congested &&
                          (useless_credit >= USELESS_CREDIT_TH) &&
                          (access_qos < 3'd5) &&
                          !stride_req;
  assign qos_ok = (stride_req && (access_qos >= qos_gate_th_stride)) ||
                  (warmup_req && (access_qos >= qos_gate_th)) ||
                  (miss_penalty_req && (access_qos >= qos_gate_th_miss));
  assign drop_qos = enable && access_fire && candidate_req && !qos_ok;
  assign drop_throttle = enable && access_fire && candidate_req &&
                         qos_ok && throttle_block;

  // Adaptive issue gate: QoS threshold + usefulness/congestion throttling.
  assign push_req  = enable && access_fire && candidate_req &&
                     qos_ok && !throttle_block;
  assign pf_valid  = q_valid[0];
  assign pf_addr   = q_addr[0];
  assign pop_req   = pf_valid && pf_ready;

  always @(*) begin
    q_valid_n = q_valid;
    for (qi = 0; qi < Q_DEPTH; qi = qi + 1) begin
      q_addr_n[qi] = q_addr[qi];
    end

    // pop head when downstream accepts a prefetch
    if (pop_req) begin
      for (qi = 0; qi < (Q_DEPTH - 1); qi = qi + 1) begin
        q_valid_n[qi] = q_valid_n[qi + 1];
        q_addr_n[qi]  = q_addr_n[qi + 1];
      end
      q_valid_n[Q_DEPTH - 1] = 1'b0;
      q_addr_n[Q_DEPTH - 1]  = {ADDR_W{1'b0}};
    end

    // deduplicate on post-pop queue image
    in_queue = 1'b0;
    push_slot = -1;
    for (qi = 0; qi < Q_DEPTH; qi = qi + 1) begin
      if (q_valid_n[qi] && (q_addr_n[qi] == push_addr)) begin
        in_queue = 1'b1;
      end
      if ((push_slot < 0) && !q_valid_n[qi]) begin
        push_slot = qi;
      end
    end

    if (push_req && !in_queue && (push_slot >= 0)) begin
      q_valid_n[push_slot] = 1'b1;
      q_addr_n[push_slot]  = push_addr;
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      q_valid <= '0;
      last_read_valid <= 1'b0;
      last_read_addr  <= {ADDR_W{1'b0}};
      last_stride_valid <= 1'b0;
      last_stride <= '0;
      stride_streak <= 2'b00;
      useless_credit <= 6'd0;
      miss_credit <= 6'd0;
      pollution_credit <= 6'd0;
      for (qi = 0; qi < Q_DEPTH; qi = qi + 1) begin
        q_addr[qi] <= {ADDR_W{1'b0}};
      end
`ifndef SYNTHESIS
      stat_pf_push_cnt <= 32'd0;
      stat_pf_pop_cnt <= 32'd0;
      stat_pf_drop_qos_cnt <= 32'd0;
      stat_pf_drop_throttle_cnt <= 32'd0;
`endif
    end else begin
      q_valid <= q_valid_n;
      for (qi = 0; qi < Q_DEPTH; qi = qi + 1) begin
        q_addr[qi] <= q_addr_n[qi];
      end

      if (PF_ADAPT_EN && feedback_useful) begin
        if (useless_credit <= USEFUL_REWARD_SAFE) begin
          useless_credit <= 6'd0;
        end else begin
          useless_credit <= useless_credit - USEFUL_REWARD_SAFE;
        end
      end else if (PF_ADAPT_EN && feedback_fill && !feedback_useful) begin
        if (useless_credit < 6'(MAX_USELESS_CREDIT)) begin
          useless_credit <= useless_credit + 6'd1;
        end
      end

      if (PF_ADAPT_EN && feedback_useful) begin
        if (miss_credit <= USEFUL_REWARD_SAFE) begin
          miss_credit <= 6'd0;
        end else begin
          miss_credit <= miss_credit - USEFUL_REWARD_SAFE;
        end
        if (pollution_credit <= USEFUL_REWARD_SAFE) begin
          pollution_credit <= 6'd0;
        end else begin
          pollution_credit <= pollution_credit - USEFUL_REWARD_SAFE;
        end
      end else begin
        if (PF_ADAPT_EN && feedback_demand_miss && (miss_credit < 6'(MAX_MISS_CREDIT))) begin
          miss_credit <= miss_credit + 6'd1;
        end
        if (PF_ADAPT_EN && feedback_fill && !feedback_useful &&
            (pollution_credit < 6'(MAX_POLLUTION_CREDIT))) begin
          pollution_credit <= pollution_credit + 6'd1;
        end
      end

`ifndef SYNTHESIS
      if (push_req) begin
        stat_pf_push_cnt <= stat_pf_push_cnt + 32'd1;
      end
      if (pop_req) begin
        stat_pf_pop_cnt <= stat_pf_pop_cnt + 32'd1;
      end
      if (drop_qos) begin
        stat_pf_drop_qos_cnt <= stat_pf_drop_qos_cnt + 32'd1;
      end
      if (drop_throttle) begin
        stat_pf_drop_throttle_cnt <= stat_pf_drop_throttle_cnt + 32'd1;
      end
`endif

      if (access_fire) begin
        if (stride_now_valid) begin
          if (last_stride_valid && (stride_now == last_stride)) begin
            if (stride_streak != 2'b11) begin
              stride_streak <= stride_streak + 2'b01;
            end
          end else begin
            stride_streak <= 2'b01;
          end
          last_stride_valid <= 1'b1;
          last_stride <= stride_now;
        end else begin
          last_stride_valid <= 1'b0;
          stride_streak <= 2'b00;
        end
        last_read_valid <= 1'b1;
        last_read_addr  <= access_addr;
      end
    end
  end

endmodule
