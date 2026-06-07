`timescale 1ns/1ps
// ------------------------------------------------------------
// kcmu_hbm_axi_shell_ooc_wrapper.sv
// Small out-of-context timing wrapper for the HBM-facing AXI
// compatibility shell.  It creates internal pulse-style memory
// requests, AXI ready/valid handshakes, and response paths so the
// shell can be post-route checked on VCU128 without real HBM IP.
// ------------------------------------------------------------
module kcmu_hbm_axi_shell_ooc_wrapper #(
  parameter integer ADDR_W = 10,
  parameter integer DATA_W = 64,
  parameter integer AXI_ADDR_W = 33,
  parameter integer AXI_DATA_W = 256,
  parameter integer REQ_FIFO_DEPTH = 8
)(
  input  logic        clk,
  input  logic        rst_n,
  input  logic        enable,
  output logic [63:0] checksum_o,
  output logic [31:0] op_count_o
);
  localparam integer AXI_STRB_W = AXI_DATA_W / 8;

  logic mem_re;
  logic [ADDR_W-1:0] mem_raddr;
  logic [DATA_W-1:0] mem_rdata;
  logic mem_rvalid;
  logic mem_we;
  logic [ADDR_W-1:0] mem_waddr;
  logic [DATA_W-1:0] mem_wdata;
  logic mem_accept_ready;
  logic mem_overflow;

  logic [AXI_ADDR_W-1:0] m_axi_awaddr;
  logic [7:0] m_axi_awlen;
  logic [2:0] m_axi_awsize;
  logic [1:0] m_axi_awburst;
  logic m_axi_awvalid;
  logic m_axi_awready;
  logic [AXI_DATA_W-1:0] m_axi_wdata;
  logic [AXI_STRB_W-1:0] m_axi_wstrb;
  logic m_axi_wlast;
  logic m_axi_wvalid;
  logic m_axi_wready;
  logic [1:0] m_axi_bresp;
  logic m_axi_bvalid;
  logic m_axi_bready;
  logic [AXI_ADDR_W-1:0] m_axi_araddr;
  logic [7:0] m_axi_arlen;
  logic [2:0] m_axi_arsize;
  logic [1:0] m_axi_arburst;
  logic m_axi_arvalid;
  logic m_axi_arready;
  logic [AXI_DATA_W-1:0] m_axi_rdata;
  logic [1:0] m_axi_rresp;
  logic m_axi_rlast;
  logic m_axi_rvalid;
  logic m_axi_rready;
  logic [31:0] stat_axi_read_req_cnt;
  logic [31:0] stat_axi_write_req_cnt;
  logic [31:0] stat_axi_read_resp_cnt;
  logic [31:0] stat_axi_write_resp_cnt;
  logic [31:0] stat_axi_overflow_cnt;
  logic [31:0] stat_axi_error_resp_cnt;

  logic [ADDR_W-1:0] req_addr;
  logic [DATA_W-1:0] req_data;
  logic [31:0] op_count;
  logic [4:0] ready_lfsr;
  logic aw_seen;
  logic w_seen;
  logic [AXI_ADDR_W-1:0] araddr_hold;
  logic [2:0] r_delay;
  logic r_pending;
  logic [63:0] checksum;

  (* keep_hierarchy = "yes" *) kcmu_hbm_axi_shell #(
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W),
    .AXI_ADDR_W(AXI_ADDR_W),
    .AXI_DATA_W(AXI_DATA_W),
    .REQ_FIFO_DEPTH(REQ_FIFO_DEPTH)
  ) u_shell (
    .clk(clk),
    .rst_n(rst_n),
    .mem_re(mem_re),
    .mem_raddr(mem_raddr),
    .mem_rdata(mem_rdata),
    .mem_rvalid(mem_rvalid),
    .mem_we(mem_we),
    .mem_waddr(mem_waddr),
    .mem_wdata(mem_wdata),
    .mem_accept_ready(mem_accept_ready),
    .mem_overflow(mem_overflow),
    .m_axi_awaddr(m_axi_awaddr),
    .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize),
    .m_axi_awburst(m_axi_awburst),
    .m_axi_awvalid(m_axi_awvalid),
    .m_axi_awready(m_axi_awready),
    .m_axi_wdata(m_axi_wdata),
    .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wlast(m_axi_wlast),
    .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready),
    .m_axi_bresp(m_axi_bresp),
    .m_axi_bvalid(m_axi_bvalid),
    .m_axi_bready(m_axi_bready),
    .m_axi_araddr(m_axi_araddr),
    .m_axi_arlen(m_axi_arlen),
    .m_axi_arsize(m_axi_arsize),
    .m_axi_arburst(m_axi_arburst),
    .m_axi_arvalid(m_axi_arvalid),
    .m_axi_arready(m_axi_arready),
    .m_axi_rdata(m_axi_rdata),
    .m_axi_rresp(m_axi_rresp),
    .m_axi_rlast(m_axi_rlast),
    .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rready(m_axi_rready),
    .stat_axi_read_req_cnt_o(stat_axi_read_req_cnt),
    .stat_axi_write_req_cnt_o(stat_axi_write_req_cnt),
    .stat_axi_read_resp_cnt_o(stat_axi_read_resp_cnt),
    .stat_axi_write_resp_cnt_o(stat_axi_write_resp_cnt),
    .stat_axi_overflow_cnt_o(stat_axi_overflow_cnt),
    .stat_axi_error_resp_cnt_o(stat_axi_error_resp_cnt)
  );

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      req_addr <= '0;
      req_data <= DATA_W'(64'h1234_5678_9abc_def0);
      op_count <= 32'd0;
      mem_re <= 1'b0;
      mem_we <= 1'b0;
      mem_raddr <= '0;
      mem_waddr <= '0;
      mem_wdata <= '0;
    end else begin
      mem_re <= 1'b0;
      mem_we <= 1'b0;
      if (enable && mem_accept_ready) begin
        mem_re <= !op_count[0];
        mem_we <= op_count[0];
        mem_raddr <= req_addr;
        mem_waddr <= req_addr + ADDR_W'(3);
        mem_wdata <= req_data ^ DATA_W'(op_count);
        req_addr <= req_addr + ADDR_W'(1);
        req_data <= {req_data[DATA_W-2:0], req_data[DATA_W-1] ^ req_data[7] ^ req_data[3] ^ req_data[2]};
        op_count <= op_count + 32'd1;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      ready_lfsr <= 5'b1_0011;
      m_axi_awready <= 1'b0;
      m_axi_wready <= 1'b0;
      m_axi_arready <= 1'b0;
    end else begin
      ready_lfsr <= {ready_lfsr[3:0], ready_lfsr[4] ^ ready_lfsr[2]};
      m_axi_awready <= enable && ready_lfsr[0];
      m_axi_wready <= enable && ready_lfsr[1];
      m_axi_arready <= enable && ready_lfsr[2];
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      aw_seen <= 1'b0;
      w_seen <= 1'b0;
      m_axi_bvalid <= 1'b0;
      m_axi_bresp <= 2'b00;
    end else begin
      if (m_axi_awvalid && m_axi_awready) begin
        aw_seen <= 1'b1;
      end
      if (m_axi_wvalid && m_axi_wready) begin
        w_seen <= 1'b1;
      end
      if (!m_axi_bvalid && aw_seen && w_seen) begin
        m_axi_bvalid <= 1'b1;
        m_axi_bresp <= 2'b00;
        aw_seen <= 1'b0;
        w_seen <= 1'b0;
      end else if (m_axi_bvalid && m_axi_bready) begin
        m_axi_bvalid <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      araddr_hold <= '0;
      r_delay <= '0;
      r_pending <= 1'b0;
      m_axi_rvalid <= 1'b0;
      m_axi_rresp <= 2'b00;
      m_axi_rlast <= 1'b0;
      m_axi_rdata <= '0;
    end else begin
      if (m_axi_arvalid && m_axi_arready) begin
        araddr_hold <= m_axi_araddr;
        r_delay <= {1'b0, ready_lfsr[1:0]} + 3'd1;
        r_pending <= 1'b1;
      end

      if (m_axi_rvalid && m_axi_rready) begin
        m_axi_rvalid <= 1'b0;
        m_axi_rlast <= 1'b0;
      end else if (r_pending) begin
        if (r_delay == 3'd0) begin
          m_axi_rvalid <= 1'b1;
          m_axi_rlast <= 1'b1;
          m_axi_rresp <= 2'b00;
          m_axi_rdata <= {AXI_DATA_W{1'b0}};
          m_axi_rdata[DATA_W-1:0] <= DATA_W'(araddr_hold) ^ DATA_W'(op_count);
          r_pending <= 1'b0;
        end else begin
          r_delay <= r_delay - 3'd1;
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      checksum <= '0;
      checksum_o <= '0;
      op_count_o <= '0;
    end else begin
      if (mem_rvalid) begin
        checksum <= checksum ^ 64'(mem_rdata) ^ {32'd0, stat_axi_read_resp_cnt};
      end
      checksum_o <= checksum ^ {stat_axi_read_req_cnt, stat_axi_write_req_cnt};
      op_count_o <= op_count ^ stat_axi_write_resp_cnt ^ stat_axi_overflow_cnt ^ stat_axi_error_resp_cnt;
    end
  end
endmodule
