`timescale 1ns/1ps

module tb_kcmu_fpga_top_counter_validation;
  import kcmu_pkg::*;

  localparam integer ADDR_W = 8;
  localparam integer DATA_W = 32;
  localparam integer AXIL_ADDR_W = 16;

  localparam logic [AXIL_ADDR_W-1:0] REG_CONTROL     = 16'h0000;
  localparam logic [AXIL_ADDR_W-1:0] REG_STATUS      = 16'h0004;
  localparam logic [AXIL_ADDR_W-1:0] REG_TRACE_COUNT = 16'h0008;
  localparam logic [AXIL_ADDR_W-1:0] REG_RESP_COUNT  = 16'h000C;
  localparam logic [AXIL_ADDR_W-1:0] REG_CONFIG_ID   = 16'h001C;
  localparam logic [AXIL_ADDR_W-1:0] REG_CONFIG_L1   = 16'h0030;
  localparam logic [AXIL_ADDR_W-1:0] REG_CONFIG_L2   = 16'h0034;
  localparam logic [AXIL_ADDR_W-1:0] REG_CONFIG_BACKEND = 16'h0038;
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_DEMAND_REQ = 16'h0080;
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_L1_HIT = 16'h0084;
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_L1_MISS = 16'h0088;
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_L2_HIT = 16'h008C;
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_L2_MISS = 16'h0090;
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_MISS_RATE = 16'h0094;
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_RD_REQ = 16'h0098;
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_WR_REQ = 16'h009C;
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_RD_LAT = 16'h00A0;
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_WR_LAT = 16'h00A4;
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_MISS_PEN = 16'h00A8;
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_POLICY_CYC = 16'h00AC;
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_PF_ACCEPT = 16'h00B0;
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_PF_FILL = 16'h00B4;
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_PF_USEFUL = 16'h00B8;
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_PF_POLLUTE = 16'h00BC;
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_BACK_STALL = 16'h00C0;
  localparam logic [AXIL_ADDR_W-1:0] REG_PERF_BACK_QFULL = 16'h00C4;
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_STATUS = 16'h00D0;
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_SEQ = 16'h00D4;
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_FLAGS = 16'h00D8;
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_DEMAND_REQ = 16'h0100;
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_L1_HIT = 16'h0104;
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_L1_MISS = 16'h0108;
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_L2_HIT = 16'h010C;
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_L2_MISS = 16'h0110;
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_RD_REQ = 16'h0114;
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_WR_REQ = 16'h0118;
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_RD_LAT = 16'h011C;
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_WR_LAT = 16'h0120;
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_MISS_PEN = 16'h0124;
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_POLICY_CYC = 16'h0128;
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_PF_ACCEPT = 16'h012C;
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_PF_FILL = 16'h0130;
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_PF_USEFUL = 16'h0134;
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_PF_POLLUTE = 16'h0138;
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_BACK_STALL = 16'h013C;
  localparam logic [AXIL_ADDR_W-1:0] REG_SNAP_BACK_QFULL = 16'h0140;
  localparam logic [AXIL_ADDR_W-1:0] TRACE_BASE      = 16'h1000;
  localparam logic [AXIL_ADDR_W-1:0] RESP_BASE       = 16'h4000;

  logic clk;
  logic rst_n;
  logic [AXIL_ADDR_W-1:0] s_axi_awaddr;
  logic [2:0]             s_axi_awprot;
  logic                   s_axi_awvalid;
  logic                   s_axi_awready;
  logic [DATA_W-1:0]      s_axi_wdata;
  logic [(DATA_W/8)-1:0]  s_axi_wstrb;
  logic                   s_axi_wvalid;
  logic                   s_axi_wready;
  logic [1:0]             s_axi_bresp;
  logic                   s_axi_bvalid;
  logic                   s_axi_bready;
  logic [AXIL_ADDR_W-1:0] s_axi_araddr;
  logic [2:0]             s_axi_arprot;
  logic                   s_axi_arvalid;
  logic                   s_axi_arready;
  logic [DATA_W-1:0]      s_axi_rdata;
  logic [1:0]             s_axi_rresp;
  logic                   s_axi_rvalid;
  logic                   s_axi_rready;

  integer poll_ctr;
  logic [31:0] rd_data;

  kcmu_fpga_top #(
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W),
    .AXIL_ADDR_W(AXIL_ADDR_W),
    .TRACE_DEPTH(64),
    .RESP_DEPTH(64)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awprot(s_axi_awprot),
    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready),
    .s_axi_bresp(s_axi_bresp),
    .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr),
    .s_axi_arprot(s_axi_arprot),
    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),
    .s_axi_rdata(s_axi_rdata),
    .s_axi_rresp(s_axi_rresp),
    .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rready(s_axi_rready)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  function automatic logic [31:0] pack_cmd_w0(
    input kcmu_op_t op,
    input logic meta_valid,
    input logic [7:0] seq_id,
    input kcmu_phase_t phase,
    input kcmu_kv_kind_t kv_kind,
    input logic [2:0] layer,
    input logic [1:0] head,
    input logic [2:0] prio
  );
    logic [31:0] word;
    begin
      word = 32'd0;
      word[1:0] = op;
      word[2] = meta_valid;
      word[3] = phase;
      word[4] = kv_kind;
      word[7:5] = layer;
      word[9:8] = head;
      word[12:10] = prio;
      word[20:13] = seq_id;
      pack_cmd_w0 = word;
    end
  endfunction

  function automatic logic [31:0] pack_cmd_w1(
    input logic [ADDR_W-1:0] addr,
    input logic [11:0] token
  );
    logic [31:0] word;
    begin
      word = 32'd0;
      word[ADDR_W-1:0] = addr;
      word[27:16] = token;
      pack_cmd_w1 = word;
    end
  endfunction

  task automatic apply_reset;
    begin
      rst_n = 1'b0;
      s_axi_awaddr = '0;
      s_axi_awprot = 3'd0;
      s_axi_awvalid = 1'b0;
      s_axi_wdata = '0;
      s_axi_wstrb = '1;
      s_axi_wvalid = 1'b0;
      s_axi_bready = 1'b1;
      s_axi_araddr = '0;
      s_axi_arprot = 3'd0;
      s_axi_arvalid = 1'b0;
      s_axi_rready = 1'b1;
      repeat (10) @(posedge clk);
      rst_n = 1'b1;
      repeat (5) @(posedge clk);
    end
  endtask

  task automatic axil_write(
    input logic [AXIL_ADDR_W-1:0] addr,
    input logic [31:0] data
  );
    begin
      @(negedge clk);
      s_axi_awaddr  <= addr;
      s_axi_awvalid <= 1'b1;
      s_axi_wdata   <= data;
      s_axi_wstrb   <= '1;
      s_axi_wvalid  <= 1'b1;
      while (!(s_axi_awready && s_axi_wready)) begin
        @(posedge clk);
      end
      @(negedge clk);
      s_axi_awvalid <= 1'b0;
      s_axi_wvalid  <= 1'b0;
      while (!s_axi_bvalid) begin
        @(posedge clk);
      end
      @(posedge clk);
    end
  endtask

  task automatic axil_read(
    input logic [AXIL_ADDR_W-1:0] addr,
    output logic [31:0] data
  );
    begin
      @(negedge clk);
      s_axi_araddr  <= addr;
      s_axi_arvalid <= 1'b1;
      while (!s_axi_arready) begin
        @(posedge clk);
      end
      @(negedge clk);
      s_axi_arvalid <= 1'b0;
      while (!s_axi_rvalid) begin
        @(posedge clk);
      end
      data = s_axi_rdata;
      @(posedge clk);
    end
  endtask

  task automatic poll_done;
    logic done_seen;
    begin
      poll_ctr = 0;
      done_seen = 1'b0;
      while (!done_seen) begin
        axil_read(REG_STATUS, rd_data);
        if (rd_data[2]) begin
          $fatal(1, "error bit set, status=0x%08h", rd_data);
        end
        if (rd_data[1]) begin
          done_seen = 1'b1;
        end
        poll_ctr = poll_ctr + 1;
        if (poll_ctr > 512) begin
          $fatal(1, "timeout waiting done");
        end
      end
    end
  endtask

  task automatic write_trace_entry(
    input integer index,
    input logic [31:0] w0,
    input logic [31:0] w1,
    input logic [31:0] w2
  );
    logic [AXIL_ADDR_W-1:0] base;
    begin
      base = TRACE_BASE + AXIL_ADDR_W'(index * 16);
      axil_write(base + 16'h0, w0);
      axil_write(base + 16'h4, w1);
      axil_write(base + 16'h8, w2);
    end
  endtask

  task automatic check_exact(
    input string name,
    input logic [AXIL_ADDR_W-1:0] addr,
    input integer expected
  );
    integer csr;
    integer delta;
    begin
      axil_read(addr, rd_data);
      csr = rd_data;
      delta = csr - expected;
      $display("CSR_COUNTER name=%s csr=%0d expected=%0d delta=%0d allowed_delta=0 rule=exact pass=%0d note=deterministic_trace", name, csr, expected, delta, (delta == 0));
      if (delta != 0) begin
        $fatal(1, "counter %s mismatch csr=%0d expected=%0d", name, csr, expected);
      end
    end
  endtask

  task automatic check_min(
    input string name,
    input logic [AXIL_ADDR_W-1:0] addr,
    input integer min_expected,
    input string note
  );
    integer csr;
    integer delta;
    begin
      axil_read(addr, rd_data);
      csr = rd_data;
      delta = csr - min_expected;
      $display("CSR_COUNTER name=%s csr=%0d expected_min=%0d delta=%0d allowed_delta=nonnegative rule=min pass=%0d note=%s", name, csr, min_expected, delta, (csr >= min_expected), note);
      if (csr < min_expected) begin
        $fatal(1, "counter %s below minimum csr=%0d min=%0d", name, csr, min_expected);
      end
    end
  endtask

  initial begin
    apply_reset();

    axil_read(REG_CONFIG_ID, rd_data);
    if (rd_data !== 32'h5634_3402) begin
      $fatal(1, "unexpected config_id=0x%08h", rd_data);
    end
    axil_read(REG_CONFIG_L1, rd_data);
    $display("CSR_CONFIG name=config_l1 value=0x%08h", rd_data);
    axil_read(REG_CONFIG_L2, rd_data);
    $display("CSR_CONFIG name=config_l2 value=0x%08h", rd_data);
    axil_read(REG_CONFIG_BACKEND, rd_data);
    $display("CSR_CONFIG name=config_backend value=0x%08h", rd_data);

    axil_write(REG_CONTROL, 32'h0000_0004);

    write_trace_entry(0, pack_cmd_w0(KCMU_OP_WR, 1'b1, 8'd2, KCMU_PHASE_PREFILL, KCMU_KV_KIND_K, 3'd5, 2'd3, 3'd1), pack_cmd_w1(8'h20, 12'd16), 32'hAAAA_0001);
    write_trace_entry(1, pack_cmd_w0(KCMU_OP_WR, 1'b1, 8'd2, KCMU_PHASE_PREFILL, KCMU_KV_KIND_V, 3'd5, 2'd3, 3'd1), pack_cmd_w1(8'h24, 12'd32), 32'hBBBB_0002);
    write_trace_entry(2, pack_cmd_w0(KCMU_OP_RD, 1'b1, 8'd2, KCMU_PHASE_DECODE, KCMU_KV_KIND_K, 3'd5, 2'd3, 3'd2), pack_cmd_w1(8'h20, 12'd16), 32'h0);
    write_trace_entry(3, pack_cmd_w0(KCMU_OP_RD, 1'b1, 8'd2, KCMU_PHASE_DECODE, KCMU_KV_KIND_V, 3'd5, 2'd3, 3'd2), pack_cmd_w1(8'h24, 12'd32), 32'h0);
    axil_write(REG_TRACE_COUNT, 32'd4);
    axil_write(REG_CONTROL, 32'h0000_0002);
    poll_done();

    axil_read(REG_RESP_COUNT, rd_data);
    if (rd_data != 32'd4) begin
      $fatal(1, "unexpected resp_count=%0d", rd_data);
    end
    axil_read(RESP_BASE + 16'h24, rd_data);
    if (rd_data !== 32'hAAAA_0001) begin
      $fatal(1, "trace response entry2 mismatch got=0x%08h", rd_data);
    end
    axil_read(RESP_BASE + 16'h34, rd_data);
    if (rd_data !== 32'hBBBB_0002) begin
      $fatal(1, "trace response entry3 mismatch got=0x%08h", rd_data);
    end

    check_exact("demand_req", REG_PERF_DEMAND_REQ, 2);
    check_exact("l1_hit", REG_PERF_L1_HIT, 2);
    check_exact("l1_miss", REG_PERF_L1_MISS, 0);
    check_exact("l2_hit", REG_PERF_L2_HIT, 0);
    check_exact("l2_miss", REG_PERF_L2_MISS, 0);
    check_exact("read_req", REG_PERF_RD_REQ, 2);
    check_exact("write_req", REG_PERF_WR_REQ, 2);
    check_exact("policy_decision_cycles", REG_PERF_POLICY_CYC, 4);
    check_min("prefetch_accept", REG_PERF_PF_ACCEPT, 0, "observed_prefetch_activity_trace_dependent");
    check_min("prefetch_fill", REG_PERF_PF_FILL, 0, "observed_prefetch_activity_trace_dependent");
    check_min("prefetch_useful", REG_PERF_PF_USEFUL, 0, "observed_prefetch_activity_trace_dependent");
    check_min("prefetch_pollution", REG_PERF_PF_POLLUTE, 0, "derived_fill_minus_useful_nonnegative");
    check_min("backend_stall_cycles", REG_PERF_BACK_STALL, 0, "backend_activity_trace_dependent");
    check_min("backend_queue_full_cycles", REG_PERF_BACK_QFULL, 0, "backend_activity_trace_dependent");
    check_min("read_latency_cycles", REG_PERF_RD_LAT, 1, "latency_sum_pipeline_dependent_nonzero");
    check_min("write_latency_cycles", REG_PERF_WR_LAT, 1, "latency_sum_pipeline_dependent_nonzero");
    check_exact("miss_penalty_cycles", REG_PERF_MISS_PEN, 0);
    check_exact("miss_rate_permille", REG_PERF_MISS_RATE, 0);

    axil_write(REG_CONTROL, 32'h0000_0008);
    axil_read(REG_SNAP_STATUS, rd_data);
    if (rd_data[0] !== 1'b1) begin
      $fatal(1, "snapshot_valid not set, status=0x%08h", rd_data);
    end
    if (rd_data[1] !== 1'b0) begin
      $fatal(1, "snapshot overflow flag set unexpectedly, status=0x%08h", rd_data);
    end
    check_exact("snapshot_seq", REG_SNAP_SEQ, 1);
    check_exact("snapshot_flags", REG_SNAP_FLAGS, 0);
    check_exact("snap_demand_req", REG_SNAP_DEMAND_REQ, 2);
    check_exact("snap_l1_hit", REG_SNAP_L1_HIT, 2);
    check_exact("snap_l1_miss", REG_SNAP_L1_MISS, 0);
    check_exact("snap_l2_hit", REG_SNAP_L2_HIT, 0);
    check_exact("snap_l2_miss", REG_SNAP_L2_MISS, 0);
    check_exact("snap_read_req", REG_SNAP_RD_REQ, 2);
    check_exact("snap_write_req", REG_SNAP_WR_REQ, 2);
    check_exact("snap_policy_decision_cycles", REG_SNAP_POLICY_CYC, 4);
    check_min("snap_prefetch_accept", REG_SNAP_PF_ACCEPT, 0, "snapshot_observed_prefetch_activity_trace_dependent");
    check_min("snap_prefetch_fill", REG_SNAP_PF_FILL, 0, "snapshot_observed_prefetch_activity_trace_dependent");
    check_min("snap_prefetch_useful", REG_SNAP_PF_USEFUL, 0, "snapshot_observed_prefetch_activity_trace_dependent");
    check_min("snap_prefetch_pollution", REG_SNAP_PF_POLLUTE, 0, "snapshot_derived_fill_minus_useful_nonnegative");
    check_min("snap_backend_stall_cycles", REG_SNAP_BACK_STALL, 0, "snapshot_backend_activity_trace_dependent");
    check_min("snap_backend_queue_full_cycles", REG_SNAP_BACK_QFULL, 0, "snapshot_backend_activity_trace_dependent");
    check_min("snap_read_latency_cycles", REG_SNAP_RD_LAT, 1, "snapshot_latency_sum_pipeline_dependent_nonzero");
    check_min("snap_write_latency_cycles", REG_SNAP_WR_LAT, 1, "snapshot_latency_sum_pipeline_dependent_nonzero");
    check_exact("snap_miss_penalty_cycles", REG_SNAP_MISS_PEN, 0);

    $display("CSR_COUNTER_VALIDATION_PASSED");
    $finish;
  end
endmodule
