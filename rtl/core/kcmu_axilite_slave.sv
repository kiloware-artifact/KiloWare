`timescale 1ns/1ps

module kcmu_axilite_slave #(
  parameter integer ADDR_W = 16,
  parameter integer DATA_W = 32
)(
  input  logic                    clk,
  input  logic                    rst_n,

  input  logic [ADDR_W-1:0]       s_axi_awaddr,
  input  logic [2:0]              s_axi_awprot,
  input  logic                    s_axi_awvalid,
  output logic                    s_axi_awready,
  input  logic [DATA_W-1:0]       s_axi_wdata,
  input  logic [(DATA_W/8)-1:0]   s_axi_wstrb,
  input  logic                    s_axi_wvalid,
  output logic                    s_axi_wready,
  output logic [1:0]              s_axi_bresp,
  output logic                    s_axi_bvalid,
  input  logic                    s_axi_bready,

  input  logic [ADDR_W-1:0]       s_axi_araddr,
  input  logic [2:0]              s_axi_arprot,
  input  logic                    s_axi_arvalid,
  output logic                    s_axi_arready,
  output logic [DATA_W-1:0]       s_axi_rdata,
  output logic [1:0]              s_axi_rresp,
  output logic                    s_axi_rvalid,
  input  logic                    s_axi_rready,

  output logic                    reg_wr_en,
  output logic [ADDR_W-1:0]       reg_wr_addr,
  output logic [DATA_W-1:0]       reg_wr_data,
  output logic [(DATA_W/8)-1:0]   reg_wr_strb,
  output logic                    reg_rd_en,
  output logic [ADDR_W-1:0]       reg_rd_addr,
  input  logic [DATA_W-1:0]       reg_rd_data
);

  logic                  aw_hold_valid;
  logic [ADDR_W-1:0]     aw_hold_addr;
  logic                  w_hold_valid;
  logic [DATA_W-1:0]     w_hold_data;
  logic [(DATA_W/8)-1:0] w_hold_strb;
  logic                  rd_hold_valid;
  logic [ADDR_W-1:0]     rd_hold_addr;

  assign s_axi_awready = !aw_hold_valid && !s_axi_bvalid;
  assign s_axi_wready  = !w_hold_valid  && !s_axi_bvalid;
  assign s_axi_arready = !rd_hold_valid && !s_axi_rvalid;
  assign s_axi_bresp   = 2'b00;
  assign s_axi_rresp   = 2'b00;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      aw_hold_valid <= 1'b0;
      aw_hold_addr  <= {ADDR_W{1'b0}};
      w_hold_valid  <= 1'b0;
      w_hold_data   <= {DATA_W{1'b0}};
      w_hold_strb   <= {(DATA_W/8){1'b0}};
      rd_hold_valid <= 1'b0;
      rd_hold_addr  <= {ADDR_W{1'b0}};
      s_axi_bvalid  <= 1'b0;
      s_axi_rvalid  <= 1'b0;
      s_axi_rdata   <= {DATA_W{1'b0}};
      reg_wr_en     <= 1'b0;
      reg_wr_addr   <= {ADDR_W{1'b0}};
      reg_wr_data   <= {DATA_W{1'b0}};
      reg_wr_strb   <= {(DATA_W/8){1'b0}};
      reg_rd_en     <= 1'b0;
      reg_rd_addr   <= {ADDR_W{1'b0}};
    end else begin
      reg_wr_en <= 1'b0;
      reg_rd_en <= 1'b0;

      if (s_axi_awready && s_axi_awvalid) begin
        aw_hold_valid <= 1'b1;
        aw_hold_addr  <= s_axi_awaddr;
      end

      if (s_axi_wready && s_axi_wvalid) begin
        w_hold_valid <= 1'b1;
        w_hold_data  <= s_axi_wdata;
        w_hold_strb  <= s_axi_wstrb;
      end

      if (!s_axi_bvalid && aw_hold_valid && w_hold_valid) begin
        reg_wr_en   <= 1'b1;
        reg_wr_addr <= aw_hold_addr;
        reg_wr_data <= w_hold_data;
        reg_wr_strb <= w_hold_strb;
        aw_hold_valid <= 1'b0;
        w_hold_valid  <= 1'b0;
        s_axi_bvalid  <= 1'b1;
      end else if (s_axi_bvalid && s_axi_bready) begin
        s_axi_bvalid <= 1'b0;
      end

      if (s_axi_arready && s_axi_arvalid) begin
        rd_hold_valid <= 1'b1;
        rd_hold_addr  <= s_axi_araddr;
        reg_rd_addr   <= s_axi_araddr;
      end else if (rd_hold_valid && !s_axi_rvalid) begin
        reg_rd_en    <= 1'b1;
        s_axi_rdata  <= reg_rd_data;
        s_axi_rvalid <= 1'b1;
        rd_hold_valid <= 1'b0;
      end else if (s_axi_rvalid && s_axi_rready) begin
        s_axi_rvalid <= 1'b0;
      end
    end
  end

endmodule

