`timescale 1ns/1ps

module tb_kcmu_l2_group_fetch_contract;
  import kcmu_pkg::*;

  localparam int ADDR_W = 8;
  localparam int DATA_W = 32;
  localparam int SCORE_W = 8;
  localparam int L2_LINES = 2;
  localparam int L2_WAYS = 1;
  localparam int VB_LINES = 4;
  localparam int GROUP_STRIDE = 2;

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
  logic                 req_group_boundary;
  logic                 req_group_target_valid;
  logic [ADDR_W-1:0]    req_group_target_addr;
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
  logic                 mem_req_is_group;
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
    .GROUP_FETCH_TO_CVR_EN(1'b1),
    .GROUP_FETCH_ADDR_STRIDE(GROUP_STRIDE),
    .WRITE_ALLOCATE(1'b1),
    .WRITE_THROUGH_EN(1'b1),
    .BG_DIRTY_FLUSH_EN(1'b0),
    .READ_FILL_QOS_TH(3'd1),
    .LOSSY_COMPRESS_EN(1'b0),
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
    .req_group_boundary(req_group_boundary),
    .req_group_target_valid(req_group_target_valid),
    .req_group_target_addr(req_group_target_addr),
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
    .mem_req_is_group(mem_req_is_group),
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
        $display("GROUP_FETCH_CONTRACT_CHECK name=%s pass=1", name);
      end else begin
        fail_count++;
        $display("GROUP_FETCH_CONTRACT_CHECK name=%s pass=0", name);
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
      req_group_boundary = 1'b1;
      req_group_target_valid = 1'b0;
      req_group_target_addr = '0;
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
      #1;
    end
  endtask

  task automatic clear_l2_group_state;
    integer i;
    begin
      drive_idle();
      for (i = 0; i < L2_LINES; i = i + 1) begin
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
      end
      for (i = 0; i < VB_LINES; i = i + 1) begin
        dut.vb_valid_mem[i] = 1'b0;
        dut.vb_lossy_mem[i] = 1'b0;
        dut.vb_dirty_mem[i] = 1'b0;
        dut.vb_tag_mem[i] = '0;
        dut.vb_data_mem[i] = '0;
      end
      for (i = 0; i < 4; i = i + 1) begin
        dut.gb_valid_mem[i] = 1'b0;
        dut.gb_used_mem[i] = 1'b0;
        dut.gb_tag_mem[i] = '0;
        dut.gb_data_mem[i] = '0;
      end
      dut.vb_rr_ptr = '0;
      dut.gb_rr_ptr = '0;
      dut.group_pending = 1'b0;
      dut.group_issued = 1'b0;
      dut.group_cancel = 1'b0;
      dut.group_addr = '0;
      dut.group_idle_ctr = 2'd0;
      dut.group_pending_age = 4'd0;
      dut.group_write_quiet_cnt = 3'd7;
      dut.group_lane_valid = '0;
      for (i = 0; i < GROUP_STRIDE; i = i + 1) begin
        dut.group_lane_last_addr[i] = '0;
        dut.group_lane_conf[i] = 3'd0;
      end
      @(posedge clk);
      #1;
    end
  endtask

  task automatic demand_miss_fill(
    input logic [ADDR_W-1:0] miss_addr,
    input logic [DATA_W-1:0] fill_data
  );
    begin
      drive_idle();
      req_re = 1'b1;
      req_raddr = miss_addr;
      req_qos = 3'd7;
      req_fill_allow = 1'b1;
      req_query_structure_class = KCMU_DESC_CLASS_W'(1);
      req_group_boundary = 1'b1;
      mem_re_ready = 1'b1;
      @(posedge clk);
      #1;
      check("demand_miss_issued_as_non_group", dut.read_owner == 2'd1);
      check("demand_request_not_prefetch_or_group", !mem_req_is_prefetch && !mem_req_is_group);
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

  task automatic demand_miss_fill_with_target(
    input logic [ADDR_W-1:0] miss_addr,
    input logic [ADDR_W-1:0] target_addr,
    input logic [DATA_W-1:0] fill_data
  );
    begin
      drive_idle();
      req_re = 1'b1;
      req_raddr = miss_addr;
      req_qos = 3'd7;
      req_fill_allow = 1'b1;
      req_query_structure_class = '0;
      req_group_boundary = 1'b1;
      req_group_target_valid = 1'b1;
      req_group_target_addr = target_addr;
      mem_re_ready = 1'b1;
      @(posedge clk);
      #1;
      check("lookahead_demand_miss_issued_as_non_group", dut.read_owner == 2'd1);
      req_re = 1'b0;
      req_group_target_valid = 1'b0;
      mem_rdata = fill_data;
      mem_rvalid = 1'b1;
      @(posedge clk);
      #1;
      mem_rvalid = 1'b0;
      repeat (1) @(posedge clk);
      #1;
    end
  endtask

  task automatic wait_group_issue(input logic [ADDR_W-1:0] expected_addr);
    integer i;
    bit seen;
    begin
      seen = 1'b0;
      for (i = 0; i < 16; i = i + 1) begin
        #1;
        if (mem_re && mem_req_is_group) begin
          seen = 1'b1;
          check("group_read_issued", 1'b1);
          check("group_read_addr_expected", mem_raddr == expected_addr);
          check("group_read_not_prefetch_class", !mem_req_is_prefetch);
          @(posedge clk);
          #1;
          check("read_owner_is_group_after_issue", dut.read_owner == 2'd2);
          i = 16;
        end else begin
          @(posedge clk);
        end
      end
      check("group_read_seen_before_timeout", seen);
    end
  endtask

  task automatic group_response_fill(input logic [DATA_W-1:0] data);
    begin
      drive_idle();
      mem_rdata = data;
      mem_rvalid = 1'b1;
      @(posedge clk);
      #1;
      check("group_response_does_not_drive_demand_valid", !req_rvalid);
      mem_rvalid = 1'b0;
      repeat (1) @(posedge clk);
      #1;
      check("group_fill_buffer_valid", dut.gb_valid_mem[0]);
      check("group_fill_buffer_data", dut.gb_data_mem[0] == data);
      check("group_fill_counter_incremented", dut.stat_l2_group_fetch_fill_cnt >= 32'd1);
    end
  endtask

  task automatic group_hit_read(
    input logic [ADDR_W-1:0] addr,
    input logic [DATA_W-1:0] data
  );
    begin
      drive_idle();
      req_re = 1'b1;
      req_raddr = addr;
      req_qos = 3'd7;
      req_fill_allow = 1'b1;
      #1;
      check("group_hit_returns_valid", req_rvalid && req_rhit);
      check("group_hit_returns_data", req_rdata == data);
      @(posedge clk);
      #1;
      req_re = 1'b0;
      check("group_hit_marks_entry_useful", dut.gb_used_mem[0]);
      check("group_useful_counter_incremented", dut.stat_l2_group_fetch_useful_cnt >= 32'd1);
    end
  endtask

  task automatic test_serial_group_fill_contract;
    begin
      clear_l2_group_state();
      demand_miss_fill(8'h10, 32'hd00d_0010);
      demand_miss_fill(8'h12, 32'hd00d_0012);
      demand_miss_fill(8'h14, 32'hd00d_0014);
      check("group_pending_after_stride_miss", dut.group_pending);
      check("group_detect_counter_incremented", dut.stat_l2_group_fetch_detect_cnt >= 32'd1);
      wait_group_issue(8'h16);
      check("group_req_counter_incremented", dut.stat_l2_group_fetch_req_cnt >= 32'd1);
      group_response_fill(32'h9f00_0016);
      group_hit_read(8'h16, 32'h9f00_0016);
    end
  endtask

  task automatic test_lookahead_target_group_fill_contract;
    begin
      clear_l2_group_state();
      demand_miss_fill_with_target(8'h30, 8'h37, 32'hd00d_0030);
      check("lookahead_group_pending_after_miss", dut.group_pending);
      check("lookahead_group_addr_selected", dut.group_addr == 8'h37);
      wait_group_issue(8'h37);
      group_response_fill(32'h9f00_0037);
      group_hit_read(8'h37, 32'h9f00_0037);
    end
  endtask

  task automatic test_pending_cancel_on_write;
    begin
      clear_l2_group_state();
      dut.group_pending = 1'b1;
      dut.group_issued = 1'b0;
      dut.group_addr = 8'h60;
      req_we = 1'b1;
      req_waddr = 8'h60;
      req_wdata = 32'h5555_0060;
      @(posedge clk);
      #1;
      req_we = 1'b0;
      check("pending_group_cancelled_by_write", !dut.group_pending);
      check("group_buffer_cleared_by_write", dut.gb_valid_mem == 4'b0000);
    end
  endtask

  task automatic test_reset_clears_group_state;
    begin
      clear_l2_group_state();
      dut.gb_valid_mem = 4'b1111;
      dut.gb_used_mem = 4'b1010;
      dut.group_pending = 1'b1;
      dut.group_issued = 1'b1;
      rst_n = 1'b0;
      @(posedge clk);
      #1;
      check("reset_clears_group_valid", dut.gb_valid_mem == 4'b0000);
      check("reset_clears_group_used", dut.gb_used_mem == 4'b0000);
      check("reset_clears_group_pending", !dut.group_pending);
      check("reset_clears_group_issued", !dut.group_issued);
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

    test_serial_group_fill_contract();
    test_lookahead_target_group_fill_contract();
    test_pending_cancel_on_write();
    test_reset_clears_group_state();

    $display("GROUP_FETCH_CONTRACT_SUMMARY checks=%0d failures=%0d", check_count, fail_count);
    if (fail_count == 0) begin
      $display("GROUP_FETCH_CONTRACT_TB_PASSED");
      $finish;
    end
    $fatal(1, "GROUP_FETCH_CONTRACT_TB_FAILED failures=%0d", fail_count);
  end
endmodule
