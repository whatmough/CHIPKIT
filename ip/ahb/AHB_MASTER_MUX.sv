// AHB_MASTER_MUX.sv - Simple mux for up to four AHB masters
// PNW 12 2015

// TODO:
// - Add assertions.
// - Add an option to have it self-arbitrating (or make this another module).


module AHB_MASTER_MUX
#(
  parameter M0_ENABLE = 1'b1,
  parameter M1_ENABLE = 1'b1,
  parameter M2_ENABLE = 1'b1,
  parameter M3_ENABLE = 1'b1
) (
  input logic HCLK, HRESETn,
  input logic [1:0] HMSEL,
  output logic [1:0] HMASTER,
  ahb_master_intf.sink M0,
  ahb_master_intf.sink M1,
  ahb_master_intf.sink M2,
  ahb_master_intf.sink M3,
  ahb_master_intf.source MOUT
);

// Use bus clock only in this module
logic clk, rstn;
always_comb clk = HCLK;
always_comb rstn = HRESETn;


// start out by stalling both masters with a low HREADY
// pipeline response switching back to correct master

//------------------------------------------------------------------------------
// Tie-off unused ports
//------------------------------------------------------------------------------

logic m0_hresp, m1_hresp, m2_hresp, m3_hresp;
logic m0_hready, m1_hready, m2_hready, m3_hready;
logic [31:0] m0_hrdata, m1_hrdata, m2_hrdata, m3_hrdata;

generate if(!M0_ENABLE)
always_comb {M0.HRESP, M0.HREADY, M0.HRDATA[31:0]} = '0;
else
always_comb {M0.HRESP, M0.HREADY, M0.HRDATA[31:0]} = {m0_hresp, m0_hready, m0_hrdata[31:0]};
endgenerate

generate if(!M1_ENABLE)
always_comb {M1.HRESP, M1.HREADY, M1.HRDATA[31:0]} = '0;
else
always_comb {M1.HRESP, M1.HREADY, M1.HRDATA[31:0]} = {m1_hresp, m1_hready, m1_hrdata[31:0]};
endgenerate

generate if(!M2_ENABLE)
always_comb {M2.HRESP, M2.HREADY, M2.HRDATA[31:0]} = '0;
else
always_comb {M2.HRESP, M2.HREADY, M2.HRDATA[31:0]} = {m2_hresp, m2_hready, m2_hrdata[31:0]};
endgenerate

generate if(!M3_ENABLE)
always_comb {M3.HRESP, M3.HREADY, M3.HRDATA[31:0]} = '0;
else
always_comb {M3.HRESP, M3.HREADY, M3.HRDATA[31:0]} = {m3_hresp, m3_hready, m3_hrdata[31:0]};
endgenerate


//------------------------------------------------------------------------------
// Control
//------------------------------------------------------------------------------

// The master should only be switched after any pending address phase completes.

// Transaction done when HREADY goes high
logic trans_done;
always_comb trans_done = MOUT.HREADY;

// Sample incoming mux value
logic [1:0] hmsel_aphase, hmsel_dphase;
`FF(HMSEL[1:0],hmsel_aphase[1:0],clk,trans_done,rstn,'0);
`FF(hmsel_aphase[1:0],hmsel_dphase[1:0],clk,trans_done,rstn,'0);

// TODO give warning if switch to unused port
// infact, probably shouldn't be able to switch to unused port - go to default instead

always_comb HMASTER[1:0] = hmsel_aphase[1:0];

//------------------------------------------------------------------------------
// Address Phase Signals
//------------------------------------------------------------------------------

// Slave -> Master signals

// If a master does is not granted, stall with HREADY
// otherwise, give the real HREADY from slave
always_comb begin
m0_hready = (hmsel_aphase[1:0] == 2'b00) ? MOUT.HREADY : 1'b0;
m1_hready = (hmsel_aphase[1:0] == 2'b01) ? MOUT.HREADY : 1'b0;
m2_hready = (hmsel_aphase[1:0] == 2'b10) ? MOUT.HREADY : 1'b0;
m3_hready = (hmsel_aphase[1:0] == 2'b11) ? MOUT.HREADY : 1'b0;
end

// Address phase signals (master -> slave)
always_comb 
case(hmsel_aphase[1:0])
  2'h0 : // M0
  {MOUT.HTRANS[1:0],MOUT.HWRITE,MOUT.HSIZE[2:0],MOUT.HADDR[31:0]} =
  {M0.HTRANS[1:0],M0.HWRITE,M0.HSIZE[2:0],M0.HADDR[31:0]};
  2'h1 : // M1
  {MOUT.HTRANS[1:0],MOUT.HWRITE,MOUT.HSIZE[2:0],MOUT.HADDR[31:0]} =
  {M1.HTRANS[1:0],M1.HWRITE,M1.HSIZE[2:0],M1.HADDR[31:0]};
  2'h2 : // M2
  {MOUT.HTRANS[1:0],MOUT.HWRITE,MOUT.HSIZE[2:0],MOUT.HADDR[31:0]} =
  {M2.HTRANS[1:0],M2.HWRITE,M2.HSIZE[2:0],M2.HADDR[31:0]};
  2'h3 : // M3
  {MOUT.HTRANS[1:0],MOUT.HWRITE,MOUT.HSIZE[2:0],MOUT.HADDR[31:0]} =
  {M3.HTRANS[1:0],M3.HWRITE,M3.HSIZE[2:0],M3.HADDR[31:0]};
  default : // M0
  {MOUT.HTRANS[1:0],MOUT.HWRITE,MOUT.HSIZE[2:0],MOUT.HADDR[31:0]} =
  {M0.HTRANS[1:0],M0.HWRITE,M0.HSIZE[2:0],M0.HADDR[31:0]};
endcase

//------------------------------------------------------------------------------
// Data Phase Signals
//------------------------------------------------------------------------------

// Data phase signals (slave -> master)
always_comb begin
  {m0_hresp, m0_hrdata[31:0]} = {MOUT.HRESP, MOUT.HRDATA[31:0]};
  {m1_hresp, m1_hrdata[31:0]} = {MOUT.HRESP, MOUT.HRDATA[31:0]};
  {m2_hresp, m2_hrdata[31:0]} = {MOUT.HRESP, MOUT.HRDATA[31:0]};
  {m3_hresp, m3_hrdata[31:0]} = {MOUT.HRESP, MOUT.HRDATA[31:0]};
end

// Data phase signals (master -> slave)
always_comb
case(hmsel_dphase[1:0])
  2'h0 : MOUT.HWDATA[31:0] = M0.HWDATA[31:0];
  2'h1 : MOUT.HWDATA[31:0] = M1.HWDATA[31:0];
  2'h2 : MOUT.HWDATA[31:0] = M2.HWDATA[31:0];
  2'h3 : MOUT.HWDATA[31:0] = M3.HWDATA[31:0];
  default : MOUT.HWDATA[31:0] = M0.HWDATA[31:0]; 
endcase


endmodule



