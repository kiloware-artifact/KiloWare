`timescale 1ns/1ps
// ------------------------------------------------------------
// kcmu_hbm_axi_shell.sv
// Compatibility shell from the KCMU HBM-like memory edge to a
// single AXI4 master port suitable for a VCU128 HBM-controller
// integration path.
//
// This shell is intentionally conservative:
// - single-beat AXI transfers
// - one outstanding read and one outstanding write
// - small read/write request FIFOs to absorb the existing mem_re/mem_we
//   pulse-style backend interface
// ------------------------------------------------------------
module kcmu_hbm_axi_shell #(
  parameter integer ADDR_W = 8,
  parameter integer DATA_W = 32,
  parameter integer AXI_ADDR_W = 33,
  parameter integer AXI_DATA_W = 256,
  parameter integer REQ_FIFO_DEPTH = 8,
  parameter logic [AXI_ADDR_W-1:0] BASE_ADDR = '0
)(
  input  logic                       clk,
  input  logic                       rst_n,

  input  logic                       mem_re,
  input  logic [ADDR_W-1:0]          mem_raddr,
  output logic [DATA_W-1:0]          mem_rdata,
  output logic                       mem_rvalid,
  input  logic                       mem_we,
  input  logic [ADDR_W-1:0]          mem_waddr,
  input  logic [DATA_W-1:0]          mem_wdata,
  output logic                       mem_accept_ready,
  output logic                       mem_overflow,

  output logic [AXI_ADDR_W-1:0]      m_axi_awaddr,
  output logic [7:0]                 m_axi_awlen,
  output logic [2:0]                 m_axi_awsize,
  output logic [1:0]                 m_axi_awburst,
  output logic                       m_axi_awvalid,
  input  logic                       m_axi_awready,
  output logic [AXI_DATA_W-1:0]      m_axi_wdata,
  output logic [(AXI_DATA_W/8)-1:0]  m_axi_wstrb,
  output logic                       m_axi_wlast,
  output logic                       m_axi_wvalid,
  input  logic                       m_axi_wready,
  input  logic [1:0]                 m_axi_bresp,
  input  logic                       m_axi_bvalid,
  output logic                       m_axi_bready,

  output logic [AXI_ADDR_W-1:0]      m_axi_araddr,
  output logic [7:0]                 m_axi_arlen,
  output logic [2:0]                 m_axi_arsize,
  output logic [1:0]                 m_axi_arburst,
  output logic                       m_axi_arvalid,
  input  logic                       m_axi_arready,
  input  logic [AXI_DATA_W-1:0]      m_axi_rdata,
  input  logic [1:0]                 m_axi_rresp,
  input  logic                       m_axi_rlast,
  input  logic                       m_axi_rvalid,
  output logic                       m_axi_rready,

  output logic [31:0]                stat_axi_read_req_cnt_o,
  output logic [31:0]                stat_axi_write_req_cnt_o,
  output logic [31:0]                stat_axi_read_resp_cnt_o,
  output logic [31:0]                stat_axi_write_resp_cnt_o,
  output logic [31:0]                stat_axi_overflow_cnt_o,
  output logic [31:0]                stat_axi_error_resp_cnt_o
);
  localparam integer AXI_STRB_W = AXI_DATA_W / 8;
  localparam integer AXI_BYTES = AXI_DATA_W / 8;
  localparam integer AXI_ADDR_SHIFT = (AXI_BYTES <= 1) ? 0 : $clog2(AXI_BYTES);
  localparam integer AXI_SIZE_VALUE = (AXI_BYTES <= 1) ? 0 : $clog2(AXI_BYTES);
  localparam integer FIFO_DEPTH_SAFE = (REQ_FIFO_DEPTH < 2) ? 2 : REQ_FIFO_DEPTH;
  localparam integer FIFO_PTR_W = (FIFO_DEPTH_SAFE <= 2) ? 1 : $clog2(FIFO_DEPTH_SAFE);
  localparam integer FIFO_CNT_W = $clog2(FIFO_DEPTH_SAFE + 1);

  initial begin
    if (AXI_DATA_W < DATA_W) begin
      $error("AXI_DATA_W must be >= DATA_W");
    end
    if ((AXI_DATA_W % 8) != 0) begin
      $error("AXI_DATA_W must be byte aligned");
    end
    if ((DATA_W % 8) != 0) begin
      $error("DATA_W must be byte aligned");
    end
  end

  function automatic logic [FIFO_PTR_W-1:0] next_ptr(input logic [FIFO_PTR_W-1:0] ptr);
    begin
      if (ptr == FIFO_PTR_W'(FIFO_DEPTH_SAFE - 1)) begin
        next_ptr = '0;
      end else begin
        next_ptr = ptr + FIFO_PTR_W'(1);
      end
    end
  endfunction

  function automatic logic [AXI_ADDR_W-1:0] map_addr(input logic [ADDR_W-1:0] addr);
    begin
      map_addr = BASE_ADDR + (AXI_ADDR_W'(addr) << AXI_ADDR_SHIFT);
    end
  endfunction

  logic [ADDR_W-1:0] rd_fifo [0:FIFO_DEPTH_SAFE-1];
  logic [ADDR_W-1:0] wr_addr_fifo [0:FIFO_DEPTH_SAFE-1];
  logic [DATA_W-1:0] wr_data_fifo [0:FIFO_DEPTH_SAFE-1];
  logic [FIFO_PTR_W-1:0] rd_head;
  logic [FIFO_PTR_W-1:0] rd_tail;
  logic [FIFO_PTR_W-1:0] wr_head;
  logic [FIFO_PTR_W-1:0] wr_tail;
  logic [FIFO_CNT_W-1:0] rd_count;
  logic [FIFO_CNT_W-1:0] wr_count;

  logic rd_push;
  logic rd_pop;
  logic wr_push;
  logic wr_pop;
  logic rd_full;
  logic wr_full;
  logic rd_wait_resp;
  logic wr_active;
  logic wr_wait_resp;
  logic rd_load;
  logic wr_load;
  logic aw_hs;
  logic w_hs;

  logic [31:0] stat_axi_read_req_cnt;
  logic [31:0] stat_axi_write_req_cnt;
  logic [31:0] stat_axi_read_resp_cnt;
  logic [31:0] stat_axi_write_resp_cnt;
  logic [31:0] stat_axi_overflow_cnt;
  logic [31:0] stat_axi_error_resp_cnt;

  assign rd_full = (rd_count == FIFO_CNT_W'(FIFO_DEPTH_SAFE));
  assign wr_full = (wr_count == FIFO_CNT_W'(FIFO_DEPTH_SAFE));
  assign rd_push = mem_re && !rd_full;
  assign wr_push = mem_we && !wr_full;
  assign rd_load = !m_axi_arvalid && !rd_wait_resp && (rd_count != '0);
  assign wr_load = !wr_active && !wr_wait_resp && (wr_count != '0);
  assign rd_pop = rd_load;
  assign wr_pop = wr_load;
  assign aw_hs = m_axi_awvalid && m_axi_awready;
  assign w_hs = m_axi_wvalid && m_axi_wready;
  assign mem_accept_ready = !rd_full && !wr_full;
  assign mem_overflow = (mem_re && rd_full) || (mem_we && wr_full);

  assign m_axi_awlen = 8'd0;
  assign m_axi_awsize = 3'(AXI_SIZE_VALUE);
  assign m_axi_awburst = 2'b01;
  assign m_axi_wlast = 1'b1;
  assign m_axi_bready = wr_wait_resp;
  assign m_axi_arlen = 8'd0;
  assign m_axi_arsize = 3'(AXI_SIZE_VALUE);
  assign m_axi_arburst = 2'b01;
  assign m_axi_rready = rd_wait_resp;

  assign stat_axi_read_req_cnt_o = stat_axi_read_req_cnt;
  assign stat_axi_write_req_cnt_o = stat_axi_write_req_cnt;
  assign stat_axi_read_resp_cnt_o = stat_axi_read_resp_cnt;
  assign stat_axi_write_resp_cnt_o = stat_axi_write_resp_cnt;
  assign stat_axi_overflow_cnt_o = stat_axi_overflow_cnt;
  assign stat_axi_error_resp_cnt_o = stat_axi_error_resp_cnt;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rd_head <= '0;
      rd_tail <= '0;
      wr_head <= '0;
      wr_tail <= '0;
      rd_count <= '0;
      wr_count <= '0;
    end else begin
      if (rd_push) begin
        rd_fifo[rd_tail] <= mem_raddr;
        rd_tail <= next_ptr(rd_tail);
      end
      if (rd_pop) begin
        rd_head <= next_ptr(rd_head);
      end
      unique case ({rd_push, rd_pop})
        2'b10: rd_count <= rd_count + FIFO_CNT_W'(1);
        2'b01: rd_count <= rd_count - FIFO_CNT_W'(1);
        default: rd_count <= rd_count;
      endcase

      if (wr_push) begin
        wr_addr_fifo[wr_tail] <= mem_waddr;
        wr_data_fifo[wr_tail] <= mem_wdata;
        wr_tail <= next_ptr(wr_tail);
      end
      if (wr_pop) begin
        wr_head <= next_ptr(wr_head);
      end
      unique case ({wr_push, wr_pop})
        2'b10: wr_count <= wr_count + FIFO_CNT_W'(1);
        2'b01: wr_count <= wr_count - FIFO_CNT_W'(1);
        default: wr_count <= wr_count;
      endcase
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      m_axi_araddr <= '0;
      m_axi_arvalid <= 1'b0;
      rd_wait_resp <= 1'b0;
      mem_rdata <= '0;
      mem_rvalid <= 1'b0;
    end else begin
      mem_rvalid <= 1'b0;
      if (rd_load) begin
        m_axi_araddr <= map_addr(rd_fifo[rd_head]);
        m_axi_arvalid <= 1'b1;
      end else if (m_axi_arvalid && m_axi_arready) begin
        m_axi_arvalid <= 1'b0;
        rd_wait_resp <= 1'b1;
      end

      if (rd_wait_resp && m_axi_rvalid) begin
        mem_rdata <= m_axi_rdata[DATA_W-1:0];
        mem_rvalid <= 1'b1;
        if (m_axi_rlast) begin
          rd_wait_resp <= 1'b0;
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      m_axi_awaddr <= '0;
      m_axi_awvalid <= 1'b0;
      m_axi_wdata <= '0;
      m_axi_wstrb <= '0;
      m_axi_wvalid <= 1'b0;
      wr_active <= 1'b0;
      wr_wait_resp <= 1'b0;
    end else begin
      if (wr_load) begin
        m_axi_awaddr <= map_addr(wr_addr_fifo[wr_head]);
        m_axi_awvalid <= 1'b1;
        m_axi_wdata <= '0;
        m_axi_wdata[DATA_W-1:0] <= wr_data_fifo[wr_head];
        m_axi_wstrb <= '0;
        m_axi_wstrb[(DATA_W/8)-1:0] <= {(DATA_W/8){1'b1}};
        m_axi_wvalid <= 1'b1;
        wr_active <= 1'b1;
      end else begin
        if (aw_hs) begin
          m_axi_awvalid <= 1'b0;
        end
        if (w_hs) begin
          m_axi_wvalid <= 1'b0;
        end
        if (wr_active &&
            (!m_axi_awvalid || aw_hs) &&
            (!m_axi_wvalid || w_hs)) begin
          wr_active <= 1'b0;
          wr_wait_resp <= 1'b1;
        end
        if (wr_wait_resp && m_axi_bvalid) begin
          wr_wait_resp <= 1'b0;
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      stat_axi_read_req_cnt <= 32'd0;
      stat_axi_write_req_cnt <= 32'd0;
      stat_axi_read_resp_cnt <= 32'd0;
      stat_axi_write_resp_cnt <= 32'd0;
      stat_axi_overflow_cnt <= 32'd0;
      stat_axi_error_resp_cnt <= 32'd0;
    end else begin
      if (rd_load) stat_axi_read_req_cnt <= stat_axi_read_req_cnt + 32'd1;
      if (wr_load) stat_axi_write_req_cnt <= stat_axi_write_req_cnt + 32'd1;
      if (rd_wait_resp && m_axi_rvalid && m_axi_rlast) stat_axi_read_resp_cnt <= stat_axi_read_resp_cnt + 32'd1;
      if (wr_wait_resp && m_axi_bvalid) stat_axi_write_resp_cnt <= stat_axi_write_resp_cnt + 32'd1;
      if (mem_overflow) stat_axi_overflow_cnt <= stat_axi_overflow_cnt + 32'd1;
      if ((rd_wait_resp && m_axi_rvalid && (m_axi_rresp != 2'b00)) ||
          (wr_wait_resp && m_axi_bvalid && (m_axi_bresp != 2'b00))) begin
        stat_axi_error_resp_cnt <= stat_axi_error_resp_cnt + 32'd1;
      end
    end
  end
endmodule
