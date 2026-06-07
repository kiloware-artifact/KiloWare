`timescale 1ns/1ps
// ------------------------------------------------------------
// kcmu_kiloscore_native.sv
// H2O-independent FPGA-native hardware-value scorer.
//
// The module intentionally does not consume H2O HH/recent/oracle outputs.
// It maps runtime-visible descriptor, locality, pressure, and capacity
// signals into the legacy 2-bit policy bus:
//   0 = COLD, 1 = RECENCY_VALUE, 2 = REUSE_VALUE, 3 = BOTH_VALUE.
// ------------------------------------------------------------
module kcmu_kiloscore_native #(
  parameter integer ADDR_W   = 8,
  parameter integer SCORE_W  = 8,
  parameter integer LINES    = 16,
  parameter integer L2_LINES = 32,
  parameter integer L2_VB_LINES = 16,
  parameter integer L2_GROUP_BUF_LINES = 4
)(
  input  logic clk,
  input  logic rst_n,

  input  logic access_valid,
  input  logic access_ready,
  input  logic access_is_read,
  input  logic access_is_write,
  input  logic access_meta_valid,

  input  logic [ADDR_W-1:0] access_addr,
  input  logic [SCORE_W-1:0] access_desc_score,
  input  logic [SCORE_W-1:0] access_query_relevance,
  input  logic [SCORE_W-1:0] access_service_criticality,
  input  logic [kcmu_pkg::KCMU_HEAD_BUDGET_W-1:0] access_head_budget_class,
  input  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] access_temporal_persist_class,
  input  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] access_reuse_distance_class,
  input  logic [kcmu_pkg::KCMU_DESC_CLASS_W-1:0] access_query_structure_class,
  input  logic [kcmu_pkg::KCMU_COST_CLASS_W-1:0] access_compression_risk,
  input  logic [kcmu_pkg::KCMU_COST_CLASS_W-1:0] access_spill_cost,
  input  logic access_token_near,
  input  logic access_token_forward,
  input  logic access_block_last,
  input  logic backend_congested,
  input  logic backend_write_pressure,

  output logic native_hit,
  output logic native_protect,
  output logic native_l1_protect,
  output logic [SCORE_W-1:0] native_score,
  output logic native_recent_keep,
  output kcmu_pkg::kcmu_h2o_class_t native_class,
  output logic [SCORE_W-1:0] native_utility_score,
  output logic [kcmu_pkg::KCMU_HEAD_BUDGET_W-1:0] native_budget_class,
  output logic native_compression_guard,
  output logic [2:0] native_backend_priority_no_service,
  output logic [2:0] native_backend_priority
);
  import kcmu_pkg::*;

  localparam logic [7:0] L1_TINY_BONUS =
    (LINES <= 8) ? 8'd8 : ((LINES <= 16) ? 8'd4 : 8'd0);
  localparam logic [7:0] CVR_TINY_PENALTY =
    (L2_VB_LINES <= 4) ? 8'd8 : ((L2_VB_LINES <= 8) ? 8'd4 : 8'd0);
  localparam logic [7:0] GB_TINY_PENALTY =
    (L2_GROUP_BUF_LINES <= 2) ? 8'd6 : ((L2_GROUP_BUF_LINES <= 4) ? 8'd2 : 8'd0);
  localparam logic [7:0] CAPACITY_RECENCY_BONUS =
    (LINES >= 64) ? 8'd32 : ((LINES >= 32) ? 8'd20 : 8'd0);
  localparam bit TINY_L2_CONSERVATIVE_KEEP = (L2_LINES <= 16);
  localparam bit MID_CAPACITY_RECENCY_PROTECT = (LINES >= 32);
  localparam bit LARGE_CAPACITY_RECENCY_PROTECT = (LINES >= 64);
  localparam bit TINY_L1_LARGE_BACKING_RECENCY_FILTER =
    (LINES <= 8) && (L2_LINES >= 64) && (L2_GROUP_BUF_LINES >= 8);
  localparam integer ADDR_REUSE_ENTRIES = 128;
  localparam integer ADDR_REUSE_IDX_W = 7;
`ifdef KCMU_CFG_FPGA_KILOSCORE_NATIVE_NO_ADDR_REUSE
  localparam bit DISABLE_ADDR_REUSE = 1'b1;
`else
  localparam bit DISABLE_ADDR_REUSE = 1'b0;
`endif

  logic access_fire;
  logic [7:0] epoch_read_cnt;
  logic [7:0] epoch_write_cnt;
  logic [7:0] epoch_near_cnt;
  logic [7:0] epoch_value_cnt;
  logic [7:0] epoch_structured_cnt;
  logic [7:0] epoch_highq_struct_cnt;
  logic [7:0] write_pressure_score;
  logic read_dense_phase;
  logic near_dense_phase;
  logic value_dense_phase;
  logic access_structured_value;
  logic access_highq_struct_value;
  logic structured_reuse_phase;
  logic highq_struct_dense_phase;

  logic [9:0] value_acc;
  logic [7:0] value_score8;
  logic [7:0] utility_score8;
  logic recency_value;
  logic recency_value_eff;
  logic midprefix_recency_ok;
  logic midprefix_recent_fallback_ok;
  logic reuse_value;
  logic capacity_recency_value;
  logic capacity_recency_l1_value;
  logic pressure_safe;
  logic service_hot;
  logic query_hot;
  logic desc_hot;
  logic structural_hot;
  logic large_capacity_retention_safe;
  logic large_capacity_retention_value;
  logic structured_value_retention;
  logic structured_service_value;
  logic structured_query_value;
  logic tiny_l2_read_keep;
  logic tiny_l2_class_reuse_keep;
  logic tiny_l2_prefix_keep;
  logic tiny_l2_stream_reuse_keep;
  logic tiny_l2_dense_read_keep;
  logic mid_capacity_structured_value;
  logic mid_capacity_streaming_value;
  logic streaming_structural_reuse_value;
  logic warm_structure_reuse_only;
  logic structured_query_recency_brake;
  logic near_recency_evidence;
  logic [ADDR_REUSE_IDX_W-1:0] addr_reuse_idx;
  logic [ADDR_REUSE_ENTRIES-1:0] addr_reuse_valid_mem;
  logic [ADDR_W-1:0] addr_reuse_tag_mem [0:ADDR_REUSE_ENTRIES-1];
  logic [2:0] addr_reuse_ctr_mem [0:ADDR_REUSE_ENTRIES-1];
  logic [ADDR_REUSE_ENTRIES-1:0] addr_reuse_alt_valid_mem;
  logic [ADDR_W-1:0] addr_reuse_alt_tag_mem [0:ADDR_REUSE_ENTRIES-1];
  logic [2:0] addr_reuse_alt_ctr_mem [0:ADDR_REUSE_ENTRIES-1];
  logic [2:0] addr_reuse_ctr_sel;
  logic addr_reuse_hit;
  logic addr_reuse_primary_hit;
  logic addr_reuse_alt_hit;
  logic addr_reuse_warm;
  logic addr_reuse_hot;
  logic addr_reuse_fold_index;
  logic addr_reuse_two_way_en;
  integer addr_reuse_i;
  logic region_reuse_hit;
  logic region_reuse_warm;
  logic region_reuse_hot;
  logic region_reuse_value;

  function automatic [ADDR_REUSE_IDX_W-1:0] native_addr_reuse_index(
    input logic [ADDR_W-1:0] addr,
    input logic fold_en
  );
    integer bit_i;
    logic bit_v;
    begin
      native_addr_reuse_index = '0;
      for (bit_i = 0; bit_i < ADDR_REUSE_IDX_W; bit_i = bit_i + 1) begin
        if (fold_en) begin
          bit_v = addr[bit_i % ADDR_W];
          if ((bit_i + 6) < ADDR_W) begin
            bit_v = bit_v ^ addr[bit_i + 6];
          end
          if ((bit_i + 11) < ADDR_W) begin
            bit_v = bit_v ^ addr[bit_i + 11];
          end
        end else if ((bit_i + 2) < ADDR_W) begin
          bit_v = addr[bit_i + 2];
        end else begin
          bit_v = addr[bit_i % ADDR_W];
        end
        native_addr_reuse_index[bit_i] = bit_v;
      end
    end
  endfunction

`ifndef SYNTHESIS
  logic [31:0] stat_native_read_cnt;
  logic [31:0] stat_native_protect_cnt;
  logic [31:0] stat_native_l1_protect_cnt;
  logic [31:0] stat_native_recent_keep_cnt;
  logic [31:0] stat_native_class_cold_cnt;
  logic [31:0] stat_native_class_recency_cnt;
  logic [31:0] stat_native_class_reuse_cnt;
  logic [31:0] stat_native_class_both_cnt;
  logic [31:0] stat_native_score_ge40_cnt;
  logic [31:0] stat_native_score_ge60_cnt;
  logic [31:0] stat_native_score_ge80_cnt;
  logic [31:0] stat_native_structured_service_cnt;
  logic [31:0] stat_native_structured_query_cnt;
  logic [31:0] stat_native_structured_retention_cnt;
  logic [31:0] stat_native_largecap_retention_cnt;
  logic [31:0] stat_native_warm_structure_reuse_only_cnt;
  logic [31:0] stat_native_addr_reuse_hit_cnt;
  logic [31:0] stat_native_addr_reuse_hot_cnt;
  logic [31:0] stat_native_region_reuse_hit_cnt;
  logic [31:0] stat_native_region_reuse_hot_cnt;
  logic [31:0] stat_native_region_reuse_value_cnt;
  logic [31:0] stat_native_highq_struct_phase_cnt;
`endif

  assign access_fire = access_valid && access_ready;
  assign access_structured_value =
    access_meta_valid &&
    access_is_read &&
    ((access_query_structure_class >= KCMU_DESC_CLASS_W'(2)) ||
     (access_service_criticality >= SCORE_W'(8'hB8)) ||
     (access_query_relevance >= SCORE_W'(8'hA0)));
  assign access_highq_struct_value =
    access_meta_valid &&
    access_is_read &&
    (access_query_structure_class >= KCMU_DESC_CLASS_W'(3)) &&
    (access_query_relevance >= SCORE_W'(8'hC0));
  assign structured_reuse_phase = (epoch_structured_cnt >= 8'd1);
  assign addr_reuse_fold_index =
    structured_reuse_phase ||
    access_structured_value;
  assign addr_reuse_two_way_en = addr_reuse_fold_index;
  assign addr_reuse_idx = native_addr_reuse_index(access_addr, addr_reuse_fold_index);
  assign addr_reuse_primary_hit =
    !DISABLE_ADDR_REUSE &&
    addr_reuse_valid_mem[addr_reuse_idx] &&
    (addr_reuse_tag_mem[addr_reuse_idx] == access_addr);
  assign addr_reuse_alt_hit =
    !DISABLE_ADDR_REUSE &&
    addr_reuse_two_way_en &&
    addr_reuse_alt_valid_mem[addr_reuse_idx] &&
    (addr_reuse_alt_tag_mem[addr_reuse_idx] == access_addr);
  assign addr_reuse_hit = addr_reuse_primary_hit || addr_reuse_alt_hit;
  assign addr_reuse_ctr_sel =
    addr_reuse_primary_hit ? addr_reuse_ctr_mem[addr_reuse_idx] :
    addr_reuse_alt_hit ? addr_reuse_alt_ctr_mem[addr_reuse_idx] : 3'd0;
  assign addr_reuse_warm = addr_reuse_hit && (addr_reuse_ctr_sel >= 3'd1);
  assign addr_reuse_hot = addr_reuse_hit && (addr_reuse_ctr_sel >= 3'd2);
  // P2-NATIVE-004: strict ablation showed the region observer can be removed
  // without increasing negative rows or lowering average benefit.
  assign region_reuse_hit = 1'b0;
  assign region_reuse_warm = 1'b0;
  assign region_reuse_hot = 1'b0;
  assign region_reuse_value = 1'b0;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      epoch_read_cnt <= 8'd0;
      epoch_write_cnt <= 8'd0;
      epoch_near_cnt <= 8'd0;
      epoch_value_cnt <= 8'd0;
      epoch_structured_cnt <= 8'd0;
      epoch_highq_struct_cnt <= 8'd0;
    end else if (access_fire) begin
      if (epoch_read_cnt == 8'hff) begin
        epoch_read_cnt <= access_is_read ? 8'd1 : 8'd0;
        epoch_write_cnt <= access_is_write ? 8'd1 : 8'd0;
        epoch_near_cnt <= (access_is_read && access_token_near) ? 8'd1 : 8'd0;
        epoch_structured_cnt <= access_structured_value ? 8'd1 : 8'd0;
        epoch_highq_struct_cnt <= access_highq_struct_value ? 8'd1 : 8'd0;
        epoch_value_cnt <=
          (access_is_read &&
           ((access_query_relevance >= SCORE_W'(8'h80)) ||
            (access_service_criticality >= SCORE_W'(8'h80)) ||
            (access_reuse_distance_class >= KCMU_DESC_CLASS_W'(2)))) ? 8'd1 : 8'd0;
      end else begin
        if (access_is_read) begin
          epoch_read_cnt <= epoch_read_cnt + 8'd1;
          if (access_token_near && (epoch_near_cnt != 8'hff)) begin
            epoch_near_cnt <= epoch_near_cnt + 8'd1;
          end
          if (((access_query_relevance >= SCORE_W'(8'h80)) ||
               (access_service_criticality >= SCORE_W'(8'h80)) ||
               (access_reuse_distance_class >= KCMU_DESC_CLASS_W'(2))) &&
              (epoch_value_cnt != 8'hff)) begin
            epoch_value_cnt <= epoch_value_cnt + 8'd1;
          end
          if (access_structured_value && (epoch_structured_cnt != 8'hff)) begin
            epoch_structured_cnt <= epoch_structured_cnt + 8'd1;
          end
          if (access_highq_struct_value && (epoch_highq_struct_cnt != 8'hff)) begin
            epoch_highq_struct_cnt <= epoch_highq_struct_cnt + 8'd1;
          end
        end
        if (access_is_write && (epoch_write_cnt != 8'hff)) begin
          epoch_write_cnt <= epoch_write_cnt + 8'd1;
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      addr_reuse_valid_mem <= '0;
      addr_reuse_alt_valid_mem <= '0;
      for (addr_reuse_i = 0; addr_reuse_i < ADDR_REUSE_ENTRIES; addr_reuse_i = addr_reuse_i + 1) begin
        addr_reuse_tag_mem[addr_reuse_i] <= '0;
        addr_reuse_ctr_mem[addr_reuse_i] <= 3'd0;
        addr_reuse_alt_tag_mem[addr_reuse_i] <= '0;
        addr_reuse_alt_ctr_mem[addr_reuse_i] <= 3'd0;
      end
    end else if (access_fire && access_meta_valid) begin
      if (access_is_read) begin
        if (addr_reuse_primary_hit) begin
          if (addr_reuse_ctr_mem[addr_reuse_idx] != 3'd7) begin
            addr_reuse_ctr_mem[addr_reuse_idx] <= addr_reuse_ctr_mem[addr_reuse_idx] + 3'd1;
          end
        end else if (addr_reuse_alt_hit) begin
          if (addr_reuse_alt_ctr_mem[addr_reuse_idx] != 3'd7) begin
            addr_reuse_alt_ctr_mem[addr_reuse_idx] <= addr_reuse_alt_ctr_mem[addr_reuse_idx] + 3'd1;
          end
        end else begin
          if (addr_reuse_two_way_en &&
              addr_reuse_valid_mem[addr_reuse_idx] &&
              (!addr_reuse_alt_valid_mem[addr_reuse_idx] ||
               (addr_reuse_alt_ctr_mem[addr_reuse_idx] < addr_reuse_ctr_mem[addr_reuse_idx]))) begin
            addr_reuse_alt_valid_mem[addr_reuse_idx] <= 1'b1;
            addr_reuse_alt_tag_mem[addr_reuse_idx] <= access_addr;
            addr_reuse_alt_ctr_mem[addr_reuse_idx] <= 3'd1;
          end else begin
            addr_reuse_valid_mem[addr_reuse_idx] <= 1'b1;
            addr_reuse_tag_mem[addr_reuse_idx] <= access_addr;
            addr_reuse_ctr_mem[addr_reuse_idx] <= 3'd1;
          end
        end
      end else if (access_is_write && addr_reuse_hit) begin
        if (addr_reuse_primary_hit && (addr_reuse_ctr_mem[addr_reuse_idx] <= 3'd1)) begin
          addr_reuse_valid_mem[addr_reuse_idx] <= 1'b0;
          addr_reuse_ctr_mem[addr_reuse_idx] <= 3'd0;
        end else if (addr_reuse_primary_hit) begin
          addr_reuse_ctr_mem[addr_reuse_idx] <= addr_reuse_ctr_mem[addr_reuse_idx] - 3'd1;
        end else if (addr_reuse_alt_hit && (addr_reuse_alt_ctr_mem[addr_reuse_idx] <= 3'd1)) begin
          addr_reuse_alt_valid_mem[addr_reuse_idx] <= 1'b0;
          addr_reuse_alt_ctr_mem[addr_reuse_idx] <= 3'd0;
        end else if (addr_reuse_alt_hit) begin
          addr_reuse_alt_ctr_mem[addr_reuse_idx] <= addr_reuse_alt_ctr_mem[addr_reuse_idx] - 3'd1;
        end
      end
    end
  end

  assign read_dense_phase = (epoch_read_cnt >= (epoch_write_cnt + 8'd8));
  assign near_dense_phase = (epoch_near_cnt >= 8'd16) && (epoch_near_cnt >= (epoch_read_cnt >> 2));
  assign value_dense_phase = (epoch_value_cnt >= 8'd8) && (epoch_value_cnt >= (epoch_read_cnt >> 4));
  assign highq_struct_dense_phase =
    TINY_L2_CONSERVATIVE_KEEP &&
    (epoch_structured_cnt >= 8'd4) &&
    (epoch_highq_struct_cnt >= 8'd4) &&
    (epoch_highq_struct_cnt >= (epoch_structured_cnt >> 1));
  assign write_pressure_score =
    backend_write_pressure ? 8'd24 :
    ((epoch_write_cnt >= (epoch_read_cnt >> 1)) ? 8'd12 : 8'd0);

  always_comb begin
    value_acc = 10'd0;

    value_acc = value_acc + {6'd0, access_desc_score[SCORE_W-1:SCORE_W-4]};
    value_acc = value_acc + {6'd0, access_query_relevance[SCORE_W-1:SCORE_W-4]};
    value_acc = value_acc + {7'd0, access_service_criticality[SCORE_W-1:SCORE_W-3]};
    value_acc = value_acc + ({8'd0, access_temporal_persist_class} << 3);
    value_acc = value_acc + ({8'd0, access_reuse_distance_class} << 3);
    value_acc = value_acc + ({8'd0, access_query_structure_class} << 2);
    value_acc = value_acc + ({8'd0, access_head_budget_class} << 2);
    value_acc = value_acc + ({6'd0, access_spill_cost} << 1);

    if (access_token_near) begin
      value_acc = value_acc + 10'd10;
    end
    if (access_token_forward) begin
      value_acc = value_acc + 10'd4;
    end
    if (access_block_last) begin
      value_acc = value_acc + 10'd3;
    end
    if (read_dense_phase) begin
      value_acc = value_acc + 10'd8;
    end
    if (near_dense_phase) begin
      value_acc = value_acc + 10'd8;
    end
    if (value_dense_phase) begin
      value_acc = value_acc + 10'd6;
    end
    if (value_dense_phase &&
        (access_service_criticality >= SCORE_W'(8'hB8) ||
         (access_query_structure_class >= KCMU_DESC_CLASS_W'(2)))) begin
      value_acc = value_acc + 10'd14;
    end
    if (structured_service_value) begin
      value_acc = value_acc + 10'd20;
    end
    if (structured_query_value) begin
      value_acc = value_acc + 10'd12;
    end
    if (tiny_l2_prefix_keep) begin
      value_acc = value_acc + 10'd8;
    end
    if (tiny_l2_stream_reuse_keep) begin
      value_acc = value_acc + 10'd18;
    end
    if (mid_capacity_structured_value) begin
      value_acc = value_acc + 10'd18;
    end
    if (mid_capacity_streaming_value) begin
      value_acc = value_acc + 10'd12;
    end
    if ((L2_LINES >= 32) &&
        (L2_GROUP_BUF_LINES <= 8) &&
        !((LINES >= 32) && (L2_LINES <= 32) && (L2_GROUP_BUF_LINES <= 2)) &&
        (access_query_structure_class == KCMU_DESC_CLASS_W'(1)) &&
        (access_query_relevance >= SCORE_W'(8'h70)) &&
        (access_query_relevance <= SCORE_W'(8'h80)) &&
        (access_temporal_persist_class >= KCMU_DESC_CLASS_W'(2)) &&
        (access_reuse_distance_class <= KCMU_DESC_CLASS_W'(1))) begin
      value_acc = value_acc + 10'd16;
    end
    if ((L2_LINES >= 128) &&
        (L2_GROUP_BUF_LINES >= 8) &&
        (access_query_structure_class == KCMU_DESC_CLASS_W'(1)) &&
        (access_query_relevance >= SCORE_W'(8'h60)) &&
        (access_query_relevance < SCORE_W'(8'h70)) &&
        (access_service_criticality >= SCORE_W'(8'h70)) &&
        (access_temporal_persist_class >= KCMU_DESC_CLASS_W'(2)) &&
        (access_reuse_distance_class <= KCMU_DESC_CLASS_W'(1))) begin
      value_acc = value_acc + 10'd14;
    end
    if (addr_reuse_hot) begin
      value_acc = value_acc + 10'd32;
    end else if (addr_reuse_warm) begin
      value_acc = value_acc + 10'd16;
    end
    if (region_reuse_value) begin
      value_acc = value_acc + (region_reuse_hot ? 10'd16 : 10'd8);
    end
    if (capacity_recency_value) begin
      value_acc = value_acc + {2'd0, CAPACITY_RECENCY_BONUS};
    end

    value_acc = value_acc + {2'd0, L1_TINY_BONUS};
    if (value_acc > {2'd0, CVR_TINY_PENALTY}) begin
      value_acc = value_acc - {2'd0, CVR_TINY_PENALTY};
    end else begin
      value_acc = 10'd0;
    end
    if (value_acc > {2'd0, GB_TINY_PENALTY}) begin
      value_acc = value_acc - {2'd0, GB_TINY_PENALTY};
    end else begin
      value_acc = 10'd0;
    end
    if (value_acc > {2'd0, write_pressure_score}) begin
      value_acc = value_acc - {2'd0, write_pressure_score};
    end else begin
      value_acc = 10'd0;
    end
    if (backend_congested) begin
      value_acc = value_acc + 10'd8;
    end
  end

  assign value_score8 = (value_acc >= 10'd255) ? 8'hff : value_acc[7:0];
  assign utility_score8 =
    (highq_struct_dense_phase &&
     (access_query_structure_class >= KCMU_DESC_CLASS_W'(3)) &&
     (access_query_relevance <= SCORE_W'(8'hC8)) &&
     (value_score8 >= 8'h40)) ? 8'h3f : value_score8;
  assign service_hot = access_service_criticality >= SCORE_W'(8'hB8);
  assign query_hot = access_query_relevance >= SCORE_W'(8'hA0);
  assign desc_hot = access_desc_score >= SCORE_W'(8'hA0);
  assign structural_hot =
    (access_temporal_persist_class >= KCMU_DESC_CLASS_W'(2)) ||
    (access_reuse_distance_class >= KCMU_DESC_CLASS_W'(2)) ||
    (access_query_structure_class >= KCMU_DESC_CLASS_W'(2));
  assign pressure_safe = !backend_write_pressure || service_hot || query_hot;
  assign capacity_recency_value =
    (CAPACITY_RECENCY_BONUS != 8'd0) &&
    access_meta_valid &&
     access_is_read &&
     read_dense_phase &&
    !backend_write_pressure &&
    (LARGE_CAPACITY_RECENCY_PROTECT ?
      (addr_reuse_warm ||
       region_reuse_value ||
       backend_write_pressure ||
       ((access_reuse_distance_class <= KCMU_DESC_CLASS_W'(1)) &&
        (access_query_relevance <= SCORE_W'(8'h60)))) :
      addr_reuse_warm);
  assign capacity_recency_l1_value =
    (CAPACITY_RECENCY_BONUS != 8'd0) &&
    access_meta_valid &&
     access_is_read &&
     (LARGE_CAPACITY_RECENCY_PROTECT || read_dense_phase) &&
     (LARGE_CAPACITY_RECENCY_PROTECT || !backend_write_pressure) &&
    (LARGE_CAPACITY_RECENCY_PROTECT ?
      (addr_reuse_warm ||
       region_reuse_value ||
       backend_write_pressure ||
       ((access_reuse_distance_class <= KCMU_DESC_CLASS_W'(1)) &&
        (access_query_relevance <= SCORE_W'(8'h60)))) :
      addr_reuse_warm);
  assign warm_structure_reuse_only =
    LARGE_CAPACITY_RECENCY_PROTECT &&
    access_meta_valid &&
    access_is_read &&
    value_dense_phase &&
    (epoch_read_cnt >= 8'd32) &&
    (access_query_structure_class >= KCMU_DESC_CLASS_W'(3)) &&
    !query_hot &&
    (access_service_criticality >= SCORE_W'(8'h80));
  assign large_capacity_retention_safe =
    !warm_structure_reuse_only &&
    ((access_query_structure_class < KCMU_DESC_CLASS_W'(3)) ||
     service_hot ||
     query_hot ||
     desc_hot ||
     access_token_near ||
     access_block_last);
  assign large_capacity_retention_value =
    LARGE_CAPACITY_RECENCY_PROTECT &&
    access_meta_valid &&
    access_is_read &&
    large_capacity_retention_safe;
  assign structured_value_retention =
    LARGE_CAPACITY_RECENCY_PROTECT &&
    access_meta_valid &&
    access_is_read &&
    value_dense_phase &&
    (epoch_read_cnt >= 8'd32);
  assign structured_service_value =
    LARGE_CAPACITY_RECENCY_PROTECT &&
    access_meta_valid &&
    access_is_read &&
    (epoch_read_cnt >= 8'd32) &&
    service_hot &&
    (access_query_structure_class >= KCMU_DESC_CLASS_W'(2)) &&
    !query_hot;
  assign structured_query_value =
    LARGE_CAPACITY_RECENCY_PROTECT &&
    access_meta_valid &&
    access_is_read &&
    value_dense_phase &&
    (epoch_read_cnt >= 8'd32) &&
    (access_query_structure_class >= KCMU_DESC_CLASS_W'(3)) &&
    ((access_query_relevance >= SCORE_W'(8'h80)) ||
     (access_service_criticality >= SCORE_W'(8'h80)));
  assign tiny_l2_read_keep =
    tiny_l2_prefix_keep ||
    tiny_l2_stream_reuse_keep ||
    (tiny_l2_dense_read_keep &&
     (addr_reuse_hot ||
      region_reuse_value ||
      access_token_near ||
      (highq_struct_dense_phase &&
       (access_query_relevance >= SCORE_W'(8'hD0)))));
  assign tiny_l2_class_reuse_keep =
    tiny_l2_prefix_keep ||
    tiny_l2_stream_reuse_keep ||
    (tiny_l2_dense_read_keep && highq_struct_dense_phase);
  assign tiny_l2_prefix_keep =
    TINY_L2_CONSERVATIVE_KEEP &&
    access_meta_valid &&
    access_is_read &&
    (access_query_structure_class >= KCMU_DESC_CLASS_W'(3)) &&
    (access_query_relevance >= SCORE_W'(8'hE0)) &&
    (access_temporal_persist_class >= KCMU_DESC_CLASS_W'(3)) &&
    (access_reuse_distance_class >= KCMU_DESC_CLASS_W'(2));
  assign tiny_l2_stream_reuse_keep =
    TINY_L2_CONSERVATIVE_KEEP &&
    access_meta_valid &&
    access_is_read &&
    (access_query_structure_class == KCMU_DESC_CLASS_W'(0)) &&
    (access_temporal_persist_class >= KCMU_DESC_CLASS_W'(1)) &&
    (access_reuse_distance_class >= KCMU_DESC_CLASS_W'(1));
  assign tiny_l2_dense_read_keep =
    TINY_L2_CONSERVATIVE_KEEP &&
    (LINES > 8) &&
    access_meta_valid &&
    access_is_read;
  assign mid_capacity_structured_value =
    MID_CAPACITY_RECENCY_PROTECT &&
    !LARGE_CAPACITY_RECENCY_PROTECT &&
    access_meta_valid &&
    access_is_read &&
    value_dense_phase &&
    (epoch_read_cnt >= 8'd24) &&
    !backend_write_pressure &&
    (access_query_structure_class >= KCMU_DESC_CLASS_W'(3)) &&
    ((access_query_relevance >= SCORE_W'(8'hA0)) ||
     (access_service_criticality >= SCORE_W'(8'hB0)) ||
     ((access_temporal_persist_class >= KCMU_DESC_CLASS_W'(3)) &&
      (access_reuse_distance_class <= KCMU_DESC_CLASS_W'(2))));
  assign mid_capacity_streaming_value =
    MID_CAPACITY_RECENCY_PROTECT &&
    !LARGE_CAPACITY_RECENCY_PROTECT &&
    access_meta_valid &&
    access_is_read &&
    read_dense_phase &&
    !backend_write_pressure &&
    !access_structured_value &&
    !addr_reuse_hit &&
    !structured_value_retention &&
    (access_query_relevance <= SCORE_W'(8'h70)) &&
    (access_service_criticality <= SCORE_W'(8'h70)) &&
    (access_temporal_persist_class >= KCMU_DESC_CLASS_W'(2)) &&
    (access_reuse_distance_class <= KCMU_DESC_CLASS_W'(1)) &&
    (access_query_structure_class <= KCMU_DESC_CLASS_W'(1));
  assign streaming_structural_reuse_value =
    LARGE_CAPACITY_RECENCY_PROTECT &&
    access_meta_valid &&
    access_is_read &&
    !access_structured_value &&
    !addr_reuse_hit &&
    !structured_value_retention &&
    (access_query_relevance <= SCORE_W'(8'h70)) &&
    (access_service_criticality <= SCORE_W'(8'h70)) &&
    (access_temporal_persist_class >= KCMU_DESC_CLASS_W'(2)) &&
    (access_reuse_distance_class <= KCMU_DESC_CLASS_W'(1)) &&
    (access_query_structure_class <= KCMU_DESC_CLASS_W'(1));
  assign structured_query_recency_brake =
    warm_structure_reuse_only;
  assign near_recency_evidence =
    access_token_near &&
    (!MID_CAPACITY_RECENCY_PROTECT ||
     backend_write_pressure ||
     addr_reuse_hot ||
     service_hot);
  assign recency_value =
    !structured_query_recency_brake &&
    (near_recency_evidence ||
     (near_dense_phase &&
      (!MID_CAPACITY_RECENCY_PROTECT ||
       backend_write_pressure ||
       addr_reuse_hot ||
       service_hot)) ||
     large_capacity_retention_value ||
     capacity_recency_value ||
     ((access_temporal_persist_class >= KCMU_DESC_CLASS_W'(2)) &&
      (backend_write_pressure || addr_reuse_hot || service_hot || access_token_near)) ||
     ((access_query_relevance >= SCORE_W'(8'h80)) && read_dense_phase &&
      (backend_write_pressure || addr_reuse_hot || service_hot || access_token_near)));
  assign recency_value_eff =
    recency_value &&
     midprefix_recency_ok &&
     (!TINY_L1_LARGE_BACKING_RECENCY_FILTER ||
      (backend_write_pressure && (service_hot || query_hot)) ||
      addr_reuse_hot ||
      (value_score8 >= 8'h60));
  assign midprefix_recency_ok =
    !(highq_struct_dense_phase &&
      (access_query_structure_class >= KCMU_DESC_CLASS_W'(3)) &&
      (access_query_relevance <= SCORE_W'(8'hC8))) ||
    addr_reuse_hot ||
    region_reuse_value;
  assign midprefix_recent_fallback_ok =
    !(highq_struct_dense_phase &&
      (access_query_structure_class >= KCMU_DESC_CLASS_W'(3)) &&
      (access_query_relevance <= SCORE_W'(8'hC8))) ||
    addr_reuse_hot ||
    region_reuse_value;
  assign reuse_value =
    addr_reuse_warm ||
    region_reuse_value ||
    structured_value_retention ||
    structured_service_value ||
    structured_query_value ||
    tiny_l2_class_reuse_keep ||
    mid_capacity_structured_value ||
    mid_capacity_streaming_value ||
    streaming_structural_reuse_value ||
    service_hot ||
    query_hot ||
    desc_hot ||
    ((value_score8 >= 8'h40) &&
     (!TINY_L2_CONSERVATIVE_KEEP ||
      (access_query_relevance >= SCORE_W'(8'h40)) ||
      (access_query_structure_class >= KCMU_DESC_CLASS_W'(2))));

  assign native_hit =
    access_meta_valid && access_is_read &&
    ((value_score8 >= 8'h60) ||
     addr_reuse_hot ||
     (region_reuse_value && region_reuse_hot) ||
     (LARGE_CAPACITY_RECENCY_PROTECT && capacity_recency_value));
  assign native_protect =
    tiny_l2_read_keep ||
    addr_reuse_warm ||
    (region_reuse_value && region_reuse_hot) ||
    structured_query_value ||
    (structured_value_retention &&
     (service_hot ||
      (access_query_relevance >= SCORE_W'(8'h40)) ||
      (access_query_structure_class >= KCMU_DESC_CLASS_W'(2)))) ||
    structured_service_value ||
    mid_capacity_structured_value ||
    mid_capacity_streaming_value ||
    (access_meta_valid && access_is_read && pressure_safe &&
     (service_hot || query_hot || (value_score8 >= 8'h40) ||
      (LARGE_CAPACITY_RECENCY_PROTECT && (value_score8 >= 8'h40)) ||
      (LARGE_CAPACITY_RECENCY_PROTECT && capacity_recency_value)));
  assign native_l1_protect =
    native_protect ||
    (LARGE_CAPACITY_RECENCY_PROTECT &&
     access_meta_valid &&
     access_is_read &&
     (addr_reuse_hot ||
      (region_reuse_value && region_reuse_hot) ||
      structured_query_value ||
      structured_service_value ||
      service_hot ||
      query_hot ||
      desc_hot ||
      access_token_near ||
      access_block_last));
  assign native_recent_keep =
    (!structured_query_recency_brake && large_capacity_retention_value) ||
    (access_meta_valid && access_is_read && pressure_safe &&
      (recency_value_eff ||
       ((value_score8 >= 8'h50) && midprefix_recent_fallback_ok &&
        !backend_congested && !structured_query_recency_brake &&
        (backend_write_pressure || addr_reuse_hot || service_hot || access_token_near))));
  assign native_class =
    (reuse_value && recency_value_eff) ? KCMU_H2O_BOTH :
    reuse_value ? KCMU_H2O_HEAVY_ONLY :
    recency_value_eff ? KCMU_H2O_RECENT_ONLY :
    KCMU_H2O_NEITHER;
  assign native_score = value_score8;
  assign native_utility_score =
    access_meta_valid ? utility_score8 : {SCORE_W{1'b0}};
  assign native_budget_class =
    (access_head_budget_class != KCMU_HEAD_BUDGET_W'(0)) ? access_head_budget_class :
    (service_hot || query_hot) ? KCMU_HEAD_BUDGET_W'(2) :
    (structural_hot || recency_value) ? KCMU_HEAD_BUDGET_W'(1) :
    KCMU_HEAD_BUDGET_W'(0);
  // P2 ablation showed this guard is row-identical scaffolding for Native.
  assign native_compression_guard = 1'b0;
  assign native_backend_priority_no_service =
    (value_score8 >= 8'hc0) ? 3'd7 :
    (value_score8 >= 8'ha0) ? 3'd6 :
    (value_score8 >= 8'h80) ? 3'd5 :
    (value_score8 >= 8'h60) ? 3'd4 :
    (value_score8 >= 8'h40) ? 3'd3 :
    (value_score8 >= 8'h20) ? 3'd2 : 3'd1;
  assign native_backend_priority =
    service_hot ? 3'd7 :
    (access_service_criticality >= SCORE_W'(8'h90)) ? 3'd6 :
    native_backend_priority_no_service;

`ifndef SYNTHESIS
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      stat_native_read_cnt <= 32'd0;
      stat_native_protect_cnt <= 32'd0;
      stat_native_l1_protect_cnt <= 32'd0;
      stat_native_recent_keep_cnt <= 32'd0;
      stat_native_class_cold_cnt <= 32'd0;
      stat_native_class_recency_cnt <= 32'd0;
      stat_native_class_reuse_cnt <= 32'd0;
      stat_native_class_both_cnt <= 32'd0;
      stat_native_score_ge40_cnt <= 32'd0;
      stat_native_score_ge60_cnt <= 32'd0;
      stat_native_score_ge80_cnt <= 32'd0;
      stat_native_structured_service_cnt <= 32'd0;
      stat_native_structured_query_cnt <= 32'd0;
      stat_native_structured_retention_cnt <= 32'd0;
      stat_native_largecap_retention_cnt <= 32'd0;
      stat_native_warm_structure_reuse_only_cnt <= 32'd0;
      stat_native_addr_reuse_hit_cnt <= 32'd0;
      stat_native_addr_reuse_hot_cnt <= 32'd0;
      stat_native_region_reuse_hit_cnt <= 32'd0;
      stat_native_region_reuse_hot_cnt <= 32'd0;
      stat_native_region_reuse_value_cnt <= 32'd0;
      stat_native_highq_struct_phase_cnt <= 32'd0;
    end else if (access_fire && access_is_read && access_meta_valid) begin
      stat_native_read_cnt <= stat_native_read_cnt + 32'd1;
      if (native_protect) begin
        stat_native_protect_cnt <= stat_native_protect_cnt + 32'd1;
      end
      if (native_l1_protect) begin
        stat_native_l1_protect_cnt <= stat_native_l1_protect_cnt + 32'd1;
      end
      if (native_recent_keep) begin
        stat_native_recent_keep_cnt <= stat_native_recent_keep_cnt + 32'd1;
      end
      unique case (native_class)
        KCMU_H2O_BOTH:        stat_native_class_both_cnt <= stat_native_class_both_cnt + 32'd1;
        KCMU_H2O_HEAVY_ONLY:  stat_native_class_reuse_cnt <= stat_native_class_reuse_cnt + 32'd1;
        KCMU_H2O_RECENT_ONLY: stat_native_class_recency_cnt <= stat_native_class_recency_cnt + 32'd1;
        default:              stat_native_class_cold_cnt <= stat_native_class_cold_cnt + 32'd1;
      endcase
      if (native_utility_score >= SCORE_W'(8'h40)) begin
        stat_native_score_ge40_cnt <= stat_native_score_ge40_cnt + 32'd1;
      end
      if (native_utility_score >= SCORE_W'(8'h60)) begin
        stat_native_score_ge60_cnt <= stat_native_score_ge60_cnt + 32'd1;
      end
      if (native_utility_score >= SCORE_W'(8'h80)) begin
        stat_native_score_ge80_cnt <= stat_native_score_ge80_cnt + 32'd1;
      end
      if (structured_service_value) begin
        stat_native_structured_service_cnt <= stat_native_structured_service_cnt + 32'd1;
      end
      if (structured_query_value) begin
        stat_native_structured_query_cnt <= stat_native_structured_query_cnt + 32'd1;
      end
      if (structured_value_retention) begin
        stat_native_structured_retention_cnt <= stat_native_structured_retention_cnt + 32'd1;
      end
      if (large_capacity_retention_value) begin
        stat_native_largecap_retention_cnt <= stat_native_largecap_retention_cnt + 32'd1;
      end
      if (warm_structure_reuse_only) begin
        stat_native_warm_structure_reuse_only_cnt <= stat_native_warm_structure_reuse_only_cnt + 32'd1;
      end
      if (addr_reuse_hit) begin
        stat_native_addr_reuse_hit_cnt <= stat_native_addr_reuse_hit_cnt + 32'd1;
      end
      if (addr_reuse_hot) begin
        stat_native_addr_reuse_hot_cnt <= stat_native_addr_reuse_hot_cnt + 32'd1;
      end
      if (highq_struct_dense_phase) begin
        stat_native_highq_struct_phase_cnt <= stat_native_highq_struct_phase_cnt + 32'd1;
      end
    end
  end
`endif
endmodule
