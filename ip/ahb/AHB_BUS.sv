// AHB_BUS.sv - Self-contained AHB bus module
// PNW 12 2015
// PNW 11 2016 Major rev


// NOTES:
// This is essentially AHB-Lite, well suited to micro-controller style CPUs
// that do not issue bursts and do not require atmoic transaction sequencences.


// TODO:
//
// - Add an interface AHB protocol checker assertion deck incase of no 3rd party checker.
// - Add some internal checking on address map etc
// - It seems it's not possible to concatenate SV interfaces into an array of interfaces.
// - Bus timeout watchdog option.
// - Is it possible to discover the bus data width using $bits()?  If so, would remove a parameter.
// - Quite a few SystemVerilog coding styles that would help here aren't currently supported in DC.


// Output properties:
// - When HREADYOUT is low, reg_hsel must be non-zero (Property of design)
// Input Properties:
// - HSEL should be one-hot
// - When HREADYOUT is low, HREADY should be low
// - Check if a disabled port is selected



`include "RTL.svh"

module AHB_BUS 
#(
  parameter NSLAVES       = 1,              // Number of slaves on the bus
  parameter DEFAULT_SLAVE = 1,           // Enables default slave for unmapped addresses
  parameter DW            = 32,             // Data bus width: 8, 16, 32, 64, 128, 256
  parameter AW            = 32,             // Address bus width
  //parameter logic [AW-1:0] S_ADDR_START [NSLAVES],    // This style doesn't seem to work in DC 
  //parameter logic [AW-1:0] S_ADDR_END [NSLAVES]       // This style doesn't seem to work in DC 
  parameter logic [(NSLAVES*AW)-1:0] S_ADDR_START,    
  parameter logic [(NSLAVES*AW)-1:0] S_ADDR_END       
)
(
  input logic HCLK, HRESETn,
  ahb_master_intf.sink M,
  ahb_slave_intf.sink S[NSLAVES]
);


// Unmapped addresses
ahb_slave_intf SX(.HCLK, .HRESETn);


//---------------------------------------------------------
// Master -> Slave
//---------------------------------------------------------


// connect up all the common signals
// clock and reset are connected at the top level

genvar i;
generate 
for (i=0; i<NSLAVES; i=i+1) begin
  assign S[i].HADDR = M.HADDR;
  assign S[i].HWRITE = M.HWRITE;
  assign S[i].HSIZE = M.HSIZE;
  assign S[i].HREADY = M.HREADY;
  //assign S[i].HBURST = M.HBURST;
  //assign S[i].HPROT = M.HPROT;
  assign S[i].HTRANS = M.HTRANS;
  assign S[i].HWDATA = M.HWDATA;
end
endgenerate

// Unmapped address regions
always_comb begin
  SX.HADDR = M.HADDR;
  SX.HWRITE = M.HWRITE;
  SX.HSIZE = M.HSIZE;
  SX.HREADY = M.HREADY;
  SX.HTRANS = M.HTRANS;
  SX.HWDATA = M.HWDATA;
end


//---------------------------------------------------------
// Address Decoder
//---------------------------------------------------------

generate for (i=0; i<NSLAVES; i=i+1) begin
  assign S[i].HSEL =    // ignore if start and end are zero
                        ~((S_ADDR_START[(i*AW)+AW-1:(i*AW)]==32'h0000_0000) & (S_ADDR_END[(i*AW)+AW-1:(i*AW)]==32'h0000_0000)) &
                        // assert HSEL if address is within this range
                        (M.HADDR[31:0] >= S_ADDR_START[(i*AW)+AW-1:(i*AW)]) & (M.HADDR[31:0] <= S_ADDR_END[(i*AW)+AW-1:(i*AW)]);
//  assign S[i].HSEL =    // ignore if start and end are zero
//                        ~((S_ADDR_START[i]==32'h0000_0000) & (S_ADDR_END[i]==32'h0000_0000)) &
//                        // assert HSEL if address is within this range
//                        (M.HADDR[31:0] >= S_ADDR_START[i]) & (M.HADDR[31:0] <= S_ADDR_END[i]);
end
endgenerate
//assign SX.HSEL = ~(S[0].HSEL | S[1].HSEL | S[2].HSEL | S[3].HSEL | S[4].HSEL | S[5].HSEL | S[6].HSEL);


// TODO switch this around and assign to the HSEL outputs from hsel[:]
// Useful to have everything in a single place here
logic [NSLAVES:0] hsel;         // next state for nxt_hsel_reg

generate for (i=0; i<NSLAVES; i=i+1) begin
  assign  hsel[i] = S[i].HSEL ;
end
endgenerate

// If no valid address regions are decoded, assert the default slave
assign hsel[NSLAVES] = ~(|{hsel[NSLAVES-1:0]});
assign SX.HSEL = hsel[NSLAVES];


// Useful to have a binary version too for the muxes
logic [$clog2(NSLAVES+1)-1:0] hsel_bin;
always_comb begin
  for (int j = 0; j < NSLAVES+1; j++)
    if(hsel[j]) hsel_bin = j;
end

//---------------------------------------------------------
// Delayed Decode for data phase
//---------------------------------------------------------

// Register hsel address decode
logic [NSLAVES:0] hsel_reg;     // Register selection control
always @(posedge HCLK or negedge HRESETn)
begin
 if (~HRESETn)
   hsel_reg <= '0;
 else if (M.HREADY) // advance pipeline if HREADY is 1
   hsel_reg <= hsel;
end

// Useful to have a binary version for the muxes
logic [$clog2(NSLAVES+1)-1:0] hsel_reg_bin;
always_comb begin
  hsel_reg_bin = 0;               // if hsel is all zeros
  for (int j = 0; j < NSLAVES+1; j++)
    if(hsel_reg[j]) hsel_reg_bin = j;
end


//---------------------------------------------------------
// Slave -> Master Muxes
//---------------------------------------------------------

// HREADY mux
logic [NSLAVES:0] hready_mux;   // multiplexed HREADY signal

generate
for(i = 0; i < NSLAVES; i++)
  assign hready_mux[i] = S[i].HREADYOUT;
endgenerate
assign hready_mux[NSLAVES] = SX.HREADYOUT;
assign M.HREADY = hready_mux[hsel_reg_bin];


/*
  assign hready_mux =
           ((~reg_hsel[0]) | HREADYOUT0 | (0)) &
           ((~reg_hsel[1]) | HREADYOUT1 | (0)) &
           ((~reg_hsel[2]) | HREADYOUT2 | (0)) &
           ((~reg_hsel[3]) | HREADYOUT3 | (0)) &
           ((~reg_hsel[4]) | HREADYOUT4 | (0)) &
           ((~reg_hsel[5]) | HREADYOUT5 | (0)) &
           ((~reg_hsel[6]) | HREADYOUT6 | (0)) &
           ((~reg_hsel[7]) | HREADYOUT7 | (1)) &
           ((~reg_hsel[8]) | HREADYOUT8 | (1)) &
           ((~reg_hsel[9]) | HREADYOUT9 | (0)) ;
*/


// HRDATA mux
logic [DW-1:0] hrdata_mux [NSLAVES:0];
generate
for(i = 0; i < NSLAVES; i++)
  assign hrdata_mux[i] = S[i].HRDATA;
endgenerate
assign hrdata_mux[NSLAVES] = SX.HRDATA;
assign M.HRDATA = hrdata_mux[hsel_reg_bin];
 
// HRESP mux
logic [NSLAVES:0] hresp_mux;
generate
for(i = 0; i < NSLAVES; i++)
  assign hresp_mux[i] = S[i].HRESP;
endgenerate
assign hresp_mux[NSLAVES] = SX.HRESP;
assign M.HRESP = hresp_mux[hsel_reg_bin];


//---------------------------------------------------------
// Automatic response to unmapped addresses
//---------------------------------------------------------
// The default slave gets any unmapped address regions
// and returns error response.

AHB_DEFAULT uDEFAULT (
.HCLK,
.HRESETn,
.S(SX.source)
);


//---------------------------------------------------------
// Assertions
//---------------------------------------------------------


// Check the memmap configuration file is legit.
/*  
`ASSERT_INIT(S0_ADDR_START <= S0_ADDR_END) 
`ASSERT_INIT(S1_ADDR_START <= S1_ADDR_END) 
`ASSERT_INIT(S2_ADDR_START <= S2_ADDR_END) 
`ASSERT_INIT(S3_ADDR_START <= S3_ADDR_END) 
`ASSERT_INIT(S4_ADDR_START <= S4_ADDR_END) 
`ASSERT_INIT(S5_ADDR_START <= S5_ADDR_END) 
`ASSERT_INIT(S6_ADDR_START <= S6_ADDR_END) 
`ASSERT_INIT(S7_ADDR_START <= S7_ADDR_END) 
*/

// TODO report the mapped regions in an initial statement
// TODO check DW of connected master and slaves.
// TODO check NSLAVES >= 1

//---------------------------------------------------------
// Logging
//---------------------------------------------------------



endmodule



