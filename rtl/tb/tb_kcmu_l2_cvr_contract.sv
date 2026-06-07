`timescale 1ns/1ps

module tb_kcmu_l2_cvr_contract;
  import kcmu_pkg::*;

  localparam int ADDR_W = 8;
  localparam int DATA_W = 32;
  localparam int SCORE_W = 8;
  localparam int L2_LINES = 2;
  localparam int L2_WAYS = 1;
  localparam int VB_LINES = 4;

  logic clk;
  logic rst_n;

  logic                 req_re;
  logic [ADDR_W-1:0]    req_raddr;
  logic                 req_is_prefetch;
  logic [2:0]           req_qos;
  logic                 req_sem_hot;
  logic                 req_fill_allow;
  logic                 req_victim_protect;
  logic                 req_compress_allow;
  logic                 req_hh_protect;
  logic                 req_recent_keep;
  logic [1:0]           req_h2o_class;
  logic [SCORE_W-1:0]   req_utility_score;
  logic [SCORE_W-1:0]   req_query_relevance;
  logic [KCMU_DESC_CLASS_W-1:0] req_query_structure_class;
  logic                 req_marginal_active;
  logic                 req_service_issue_boost;
  logic                 req_sched_query_take;
  logic                 req_sched_temporal_take;
  logic                 req_sched_query_bias_take;
  logic [DATA_W-1:0]    req_rdata;
  logic                 req_rvalid;
  logic                 req_rhit;
  logic                 req_rlossy;

  logic                 req_we;
  logic [ADDR_W-1:0]    req_waddr;
  logic [DATA_W-1:0]    req_wdata;

  logic                 mem_re;
  logic [ADDR_W-1:0]    mem_raddr;
  logic                 mem_req_is_prefetch;
  logic                 mem_req_service_issue_boost;
  logic                 mem_re_ready;
  logic                 mem_req_accepted;
  logic [DATA_W-1:0]    mem_rdata;
  logic                 mem_rvalid;

  logic                 mem_we;
  logic [ADDR_W-1:0]    mem_waddr;
  logic [DATA_W-1:0]    mem_wdata;
  logic                 mem_req_is_writeback;
  logic                 mem_we_ready;
  logic                 fill_req_query_admit_event;
  logic [31:0]          stat_l2_comp_fill_cnt_o;
  logic [31:0]          stat_l2_comp_readback_cnt_o;
  logic [31:0]          stat_l2_comp_spill_cnt_o;
  logic [31:0]          stat_l2_dirty_wb_req_cnt_o;

  int fail_count;
  int check_count;

  kcmu_l2_ctrl #(
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W),
    .SCORE_W(SCORE_W),
    .L2_LINES(L2_LINES),
    .L2_WAYS(L2_WAYS),
    .VB_LINES(VB_LINES),
    .VB_ENABLE(1'b1),
    .VB_CLEAN_READONLY_EN(1'b1),
    .WRITE_ALLOCATE(1'b1),
    .WRITE_THROUGH_EN(1'b1),
    .BG_DIRTY_FLUSH_EN(1'b0),
    .READ_FILL_QOS_TH(3'd1),
    .LOSSY_COMPRESS_EN(1'b1),
    .H2O_V2_EN(1'b1)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .req_re(req_re),
    .req_raddr(req_raddr),
    .req_is_prefetch(req_is_prefetch),
    .req_qos(req_qos),
    .req_sem_hot(req_sem_hot),
    .req_fill_allow(req_fill_allow),
    .req_victim_protect(req_victim_protect),
    .req_compress_allow(req_compress_allow),
    .req_hh_protect(req_hh_protect),
    .req_recent_keep(req_recent_keep),
    .req_h2o_class(req_h2o_class),
    .req_utility_score(req_utility_score),
    .req_query_relevance(req_query_relevance),
    .req_head_budget_class('0),
    .req_temporal_persist_class('0),
    .req_reuse_distance_class('0),
    .req_query_structure_class(req_query_structure_class),
    .req_marginal_active(req_marginal_active),
    .req_service_issue_boost(req_service_issue_boost),
    .req_sched_query_take(req_sched_query_take),
    .req_sched_temporal_take(req_sched_temporal_take),
    .req_sched_query_bias_take(req_sched_query_bias_take),
    .req_group_boundary(1'b1),
    .req_group_target_valid(1'b0),
    .req_group_target_addr('0),
    .req_group_v251gf_force(1'b0),
    .req_kiloscore_extra_cvr_hint(1'b0),
    .req_kiloscore_qsig_bucket(3'd0),
    .req_backend_write_pressure(1'b0),
    .req_rdata(req_rdata),
    .req_rvalid(req_rvalid),
    .req_rhit(req_rhit),
    .req_rlossy(req_rlossy),
    .req_we(req_we),
    .req_waddr(req_waddr),
    .req_wdata(req_wdata),
    .mem_re(mem_re),
    .mem_raddr(mem_raddr),
    .mem_req_is_prefetch(mem_req_is_prefetch),
    .mem_req_service_issue_boost(mem_req_service_issue_boost),
    .mem_re_ready(mem_re_ready),
    .mem_req_accepted(mem_req_accepted),
    .mem_rdata(mem_rdata),
    .mem_rvalid(mem_rvalid),
    .mem_we(mem_we),
    .mem_waddr(mem_waddr),
    .mem_wdata(mem_wdata),
    .mem_req_is_writeback(mem_req_is_writeback),
    .mem_we_ready(mem_we_ready),
    .fill_req_query_admit_event(fill_req_query_admit_event),
    .stat_l2_comp_fill_cnt_o(stat_l2_comp_fill_cnt_o),
    .stat_l2_comp_readback_cnt_o(stat_l2_comp_readback_cnt_o),
    .stat_l2_comp_spill_cnt_o(stat_l2_comp_spill_cnt_o),
    .stat_l2_dirty_wb_req_cnt_o(stat_l2_dirty_wb_req_cnt_o)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task automatic check(input string name, input bit cond);
    begin
      check_count++;
      if (cond) begin
        $display("CVR_CONTRACT_CHECK name=%s pass=1", name);
      end else begin
        fail_count++;
        $display("CVR_CONTRACT_CHECK name=%s pass=0", name);
      end
    end
  endtask

  task automatic drive_idle;
    begin
      req_re = 1'b0;
      req_raddr = '0;
      req_is_prefetch = 1'b0;
      req_qos = 3'd0;
      req_sem_hot = 1'b0;
      req_fill_allow = 1'b0;
      req_victim_protect = 1'b0;
      req_compress_allow = 1'b0;
      req_hh_protect = 1'b0;
      req_recent_keep = 1'b0;
      req_h2o_class = KCMU_H2O_NEITHER;
      req_utility_score = '0;
      req_query_relevance = '0;
      req_query_structure_class = '0;
      req_marginal_active = 1'b0;
      req_service_issue_boost = 1'b0;
      req_sched_query_take = 1'b0;
      req_sched_temporal_take = 1'b0;
      req_sched_query_bias_take = 1'b0;
      req_we = 1'b0;
      req_waddr = '0;
      req_wdata = '0;
      mem_re_ready = 1'b1;
      mem_rdata = '0;
      mem_rvalid = 1'b0;
      mem_we_ready = 1'b1;
    end
  endtask

  task automatic apply_reset;
    begin
      drive_idle();
      rst_n = 1'b0;
      repeat (4) @(posedge clk);
      rst_n = 1'b1;
      repeat (2) @(posedge clk);
    end
  endtask

  task automatic clear_l2_vb_state;
    integer i;
    begin
      drive_idle();
      for (i = 0; i < L2_LINES; i++) begin
        dut.valid_mem[i] = 1'b0;
        dut.lossy_mem[i] = 1'b0;
        dut.dirty_mem[i] = 1'b0;
        dut.tag_mem[i] = '0;
        dut.data_mem[i] = '0;
        dut.comp_mem[i] = '0;
        dut.comp_bits_mem[i] = 3'd4;
        dut.line_sem_hot[i] = 1'b0;
        dut.line_hh_protect_mem[i] = 1'b0;
        dut.line_recent_keep_mem[i] = 1'b0;
        dut.line_h2o_class_mem[i] = KCMU_H2O_NEITHER;
        dut.line_utility_score_mem[i] = '0;
        dut.line_marginal_keep_mem[i] = 1'b0;
        dut.line_pollution_risk_mem[i] = 1'b0;
        dut.line_pressure_bonus_mem[i] = 3'd0;
        dut.line_freq[i] = 4'd0;
        dut.line_touch_epoch[i] = 8'd0;
`ifndef SYNTHESIS
        dut.line_fill_cycle[i] = 32'd0;
`endif
      end
      for (i = 0; i < VB_LINES; i++) begin
        dut.vb_valid_mem[i] = 1'b0;
        dut.vb_lossy_mem[i] = 1'b0;
        dut.vb_dirty_mem[i] = 1'b0;
        dut.vb_tag_mem[i] = '0;
        dut.vb_data_mem[i] = '0;
        dut.vb_comp_mem[i] = '0;
        dut.vb_comp_bits_mem[i] = 3'd4;
        dut.vb_sem_hot_mem[i] = 1'b0;
        dut.vb_hh_protect_mem[i] = 1'b0;
        dut.vb_recent_keep_mem[i] = 1'b0;
        dut.vb_h2o_class_mem[i] = KCMU_H2O_NEITHER;
        dut.vb_utility_score_mem[i] = '0;
        dut.vb_marginal_keep_mem[i] = 1'b0;
        dut.vb_pollution_risk_mem[i] = 1'b0;
        dut.vb_pressure_bonus_mem[i] = 3'd0;
        dut.vb_freq_mem[i] = 4'd0;
        dut.vb_touch_epoch_mem[i] = 8'd0;
      end
      dut.vb_rr_ptr = '0;
      @(posedge clk);
      #1;
    end
  endtask

  task automatic install_l2_line0(
    input logic [ADDR_W-1:0] addr,
    input logic [DATA_W-1:0] data,
    input bit dirty,
    input bit lossy
  );
    begin
      dut.valid_mem[0] = 1'b1;
      dut.tag_mem[0] = addr[ADDR_W-1:1];
      dut.data_mem[0] = data;
      dut.comp_mem[0] = data[15:0];
      dut.comp_bits_mem[0] = 3'd2;
      dut.dirty_mem[0] = dirty;
      dut.lossy_mem[0] = lossy;
      dut.line_freq[0] = 4'd0;
      dut.line_touch_epoch[0] = 8'd0;
    end
  endtask

  task automatic miss_and_fill_same_set(
    input logic [ADDR_W-1:0] miss_addr,
    input logic [DATA_W-1:0] fill_data
  );
    begin
      req_re = 1'b1;
      req_raddr = miss_addr;
      req_qos = 3'd7;
      req_fill_allow = 1'b1;
      req_compress_allow = 1'b0;
      mem_re_ready = 1'b1;
      @(posedge clk);
      #1;
      check("miss_request_accepted", mem_req_accepted || dut.miss_pending);
      req_re = 1'b0;
      mem_rdata = fill_data;
      mem_rvalid = 1'b1;
      @(posedge clk);
      #1;
      mem_rvalid = 1'b0;
      repeat (1) @(posedge clk);
      #1;
    end
  endtask

  task automatic test_clean_insert;
    begin
      clear_l2_vb_state();
      install_l2_line0(8'h20, 32'hc1ea_5001, 1'b0, 1'b0);
      miss_and_fill_same_set(8'h40, 32'hfeed_4000);
      check("clean_nonlossy_victim_inserted", dut.vb_valid_mem[0] && (dut.vb_tag_mem[0] == 8'h20));
      check("clean_nonlossy_victim_data_preserved", dut.vb_data_mem[0] == 32'hc1ea_5001);
      check("clean_nonlossy_victim_is_not_dirty_or_lossy", !dut.vb_dirty_mem[0] && !dut.vb_lossy_mem[0]);
`ifndef SYNTHESIS
      check("clean_insert_counter_incremented", dut.stat_l2_vb_insert_cnt >= 32'd1);
`endif
    end
  endtask

  task automatic test_dirty_excluded;
    begin
      clear_l2_vb_state();
      install_l2_line0(8'h20, 32'hd17a_0001, 1'b1, 1'b0);
      miss_and_fill_same_set(8'h40, 32'hfeed_4001);
      check("dirty_victim_not_inserted", dut.vb_valid_mem == {VB_LINES{1'b0}});
      check("dirty_victim_never_marked_in_cvr", dut.vb_dirty_mem == {VB_LINES{1'b0}});
    end
  endtask

  task automatic test_lossy_excluded;
    begin
      clear_l2_vb_state();
      install_l2_line0(8'h20, 32'h1055_0001, 1'b0, 1'b1);
      miss_and_fill_same_set(8'h40, 32'hfeed_4002);
      check("lossy_victim_not_inserted", dut.vb_valid_mem == {VB_LINES{1'b0}});
      check("lossy_victim_never_marked_in_cvr", dut.vb_lossy_mem == {VB_LINES{1'b0}});
    end
  endtask

  task automatic test_read_hit_promote;
    begin
      clear_l2_vb_state();
      dut.vb_valid_mem[1] = 1'b1;
      dut.vb_tag_mem[1] = 8'h22;
      dut.vb_data_mem[1] = 32'hca5e_2222;
      req_re = 1'b1;
      req_raddr = 8'h22;
      req_qos = 3'd7;
      req_fill_allow = 1'b1;
      #1;
      check("cvr_read_hit_visible", req_rvalid && req_rhit && !req_rlossy && (req_rdata == 32'hca5e_2222));
      @(posedge clk);
      #1;
      req_re = 1'b0;
      check("cvr_read_hit_promotes_to_l2", dut.valid_mem[0] && (dut.tag_mem[0] == 7'h11) && (dut.data_mem[0] == 32'hca5e_2222));
      check("cvr_read_hit_entry_consumed", !dut.vb_valid_mem[1]);
`ifndef SYNTHESIS
      check("cvr_read_hit_counter_incremented", dut.stat_l2_vb_read_hit_cnt >= 32'd1);
`endif
    end
  endtask

  task automatic test_write_invalidate_under_backpressure;
    begin
      clear_l2_vb_state();
      dut.vb_valid_mem = 4'b1011;
      dut.vb_tag_mem[0] = 8'h10;
      dut.vb_tag_mem[1] = 8'h12;
      dut.vb_tag_mem[3] = 8'h16;
      mem_we_ready = 1'b0;
      req_we = 1'b1;
      req_waddr = 8'h12;
      req_wdata = 32'h7777_1212;
      @(posedge clk);
      #1;
      req_we = 1'b0;
      mem_we_ready = 1'b1;
      check("write_invalidates_all_clean_cvr_entries", dut.vb_valid_mem == {VB_LINES{1'b0}});
    end
  endtask

  task automatic test_reset_clears_cvr;
    begin
      clear_l2_vb_state();
      dut.vb_valid_mem = 4'b1111;
      dut.vb_dirty_mem = 4'b1010;
      dut.vb_lossy_mem = 4'b0101;
      rst_n = 1'b0;
      @(posedge clk);
      #1;
      check("reset_clears_cvr_valid", dut.vb_valid_mem == {VB_LINES{1'b0}});
      check("reset_clears_cvr_dirty", dut.vb_dirty_mem == {VB_LINES{1'b0}});
      check("reset_clears_cvr_lossy", dut.vb_lossy_mem == {VB_LINES{1'b0}});
      rst_n = 1'b1;
      repeat (2) @(posedge clk);
      #1;
    end
  endtask

  initial begin
    fail_count = 0;
    check_count = 0;
    rst_n = 1'b0;
    drive_idle();

    apply_reset();
    check("post_reset_valid_clear", dut.vb_valid_mem == {VB_LINES{1'b0}});
    check("post_reset_dirty_clear", dut.vb_dirty_mem == {VB_LINES{1'b0}});
    check("post_reset_lossy_clear", dut.vb_lossy_mem == {VB_LINES{1'b0}});

    test_clean_insert();
    test_dirty_excluded();
    test_lossy_excluded();
    test_read_hit_promote();
    test_write_invalidate_under_backpressure();
    test_reset_clears_cvr();

    $display("CVR_CONTRACT_SUMMARY checks=%0d failures=%0d", check_count, fail_count);
    if (fail_count == 0) begin
      $display("CVR_CONTRACT_TB_PASSED");
      $finish;
    end
    $fatal(1, "CVR_CONTRACT_TB_FAILED failures=%0d", fail_count);
  end
endmodule
