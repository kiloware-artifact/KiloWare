create_clock -period 14.500 -name fpga_clk -waveform {0.000 7.250} [get_ports clk]
set_property IOSTANDARD LVCMOS18 [get_ports {clk rst_n}]
set_property IOSTANDARD LVCMOS18 [get_ports {s_axi_awaddr[*] s_axi_awprot[*] s_axi_awvalid s_axi_wdata[*] s_axi_wstrb[*] s_axi_wvalid s_axi_bready s_axi_araddr[*] s_axi_arprot[*] s_axi_arvalid s_axi_rready s_axi_awready s_axi_wready s_axi_bresp[*] s_axi_bvalid s_axi_arready s_axi_rdata[*] s_axi_rresp[*] s_axi_rvalid}]
set_property PULLUP true [get_ports rst_n]

