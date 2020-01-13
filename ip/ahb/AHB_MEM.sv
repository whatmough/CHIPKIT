// AHB_MEM.sv - A 64KB AHB memory
// PNW

`include "RTL.svh"

// TODO generate wait state only on RaW hazard


module AHB_MEM 
#(
  parameter AW = 16,          // Address width (16bits = 64KB)
  parameter filename = ""     // Initialization hex file
) (
  input logic HCLK, HRESETn,
  ahb_slave_intf.source S,
  
  input logic       SC_SRAM_STOV,
  input logic [2:0] SC_SRAM_EMA,
  input logic [1:0] SC_SRAM_EMAW,
  input logic       SC_SRAM_EMAS
);

logic clk, rstn;

always_comb clk = HCLK;
always_comb rstn = HRESETn;


// Detect valid transaction

// Transaction is split into two phases: APHASE and DPHASE
// Useful part of APHASE is 1 cycle.
// DPHASE is controlled by by slave.
// In this case, it is either 1 cycle for a READ,
// or 2 cycles for a WRITE.

logic aphase;
logic dphase;
always_comb aphase = S.HSEL & S.HREADY & S.HTRANS[1];
//`FF(aphase,dphase,clk,'1,rstn,'0);

// determine if it's a read or write transaction
logic write_en;
logic read_en;
logic write_en_reg;
always_comb write_en = aphase & S.HWRITE & (~write_en_reg);
always_comb read_en  = aphase & (~S.HWRITE);
`FF(write_en,write_en_reg,clk,'1,rstn,'0);

// Read enable for each byte (address phase)
logic [3:0] byte_lane_nxt;

always_comb begin
if (aphase)
  begin
  case (S.HSIZE)
    0 : // Byte
      begin
      case (S.HADDR[1:0])
        0: byte_lane_nxt = 4'b0001; // Byte 0
        1: byte_lane_nxt = 4'b0010; // Byte 1
        2: byte_lane_nxt = 4'b0100; // Byte 2
        3: byte_lane_nxt = 4'b1000; // Byte 3
        default:byte_lane_nxt = 4'b0000; // Address not valid
      endcase
      end
    1 : // Halfword
      begin
      if (S.HADDR[1])
        byte_lane_nxt = 4'b1100; // Upper halfword
      else
        byte_lane_nxt = 4'b0011; // Lower halfword
      end
    default : // Word
      byte_lane_nxt = 4'b1111; // Whole word
  endcase
  end
else
  byte_lane_nxt = 4'b0000; // Not reading
end

// Register address phase control signals
logic [3:0] byte_lane_reg; 
logic [AW-1:0] word_addr_reg;     
logic [AW-1:0] word_addr_nxt;
always_comb word_addr_nxt = {S.HADDR[AW-1:2], 2'b00};
`FF(byte_lane_nxt[3:0],byte_lane_reg[3:0],clk,'1,rstn,'0);
`FF(word_addr_nxt[AW-1:0],word_addr_reg[AW-1:0],clk,'1,rstn,'0);


// SRAM

logic sram_cen;
logic sram_gwen;
logic [AW-1:0] sram_a;
logic [31:0] sram_wen;
logic [31:0] sram_d;
logic [31:0] sram_q;
logic [7:0] sram_q0, sram_q1, sram_q2, sram_q3;
always_comb sram_cen = ~(read_en | write_en_reg);
always_comb sram_gwen = read_en;
always_comb sram_a = read_en ? word_addr_nxt : word_addr_reg;
always_comb sram_d[31:0] = S.HWDATA[31:0];
always_comb sram_wen = {{8{~byte_lane_reg[3]}},{8{~byte_lane_reg[2]}},{8{~byte_lane_reg[1]}},{8{~byte_lane_reg[0]}}};
always_comb sram_q0[7:0] = byte_lane_reg[0] ? sram_q[7:0]   : 8'h00;
always_comb sram_q1[7:0] = byte_lane_reg[1] ? sram_q[15:8]  : 8'h00;
always_comb sram_q2[7:0] = byte_lane_reg[2] ? sram_q[23:16] : 8'h00;
always_comb sram_q3[7:0] = byte_lane_reg[3] ? sram_q[31:24] : 8'h00;


LIB_SRAM_16384x32 
u_64kb_sram (
  .Q(sram_q[31:0]),
  .CLK(clk),
  .CEN(sram_cen),
  .GWEN(sram_gwen),
  .WEN(sram_wen),
  .A(sram_a[AW-1:2]),
  .D(sram_d[31:0]),
  .STOV(SC_SRAM_STOV),
  .EMA(SC_SRAM_EMA[2:0]),
  .EMAW(SC_SRAM_EMAW[1:0]),
  .EMAS(SC_SRAM_EMAS)
);


// Connect to top level
always_comb S.HREADYOUT     = ~write_en_reg;    // READ does not require wait state, WRITE requires 1 wait state
always_comb S.HRESP         = 1'b0;             // Always response with OKAY
always_comb S.HRDATA[31:0]  = {sram_q3[7:0],sram_q2[7:0],sram_q1[7:0],sram_q0[7:0]};


//----------------------------------
//logging
//--------------------------------

`LOGF_INIT


//add delay before logging read or write, but don't let address change for read
logic [AW-3:0] this_addr;
logic did_read;
`FF(read_en, did_read, clk, '1, rstn, '0);

always_ff @(posedge clk, negedge rstn)
begin
  if (!rstn) this_addr <= sram_a[AW-1:2];
  else if (read_en) this_addr <= sram_a[AW-1:2];
end

`LOGF(clk, rstn, read_en, ("READ: %8h : %8h", this_addr, sram_q));

logic did_write;
`FF(write_en, did_write, clk, '1, rstn, '0);

`LOGF(clk, rstn, did_write, ("WRITE: %8h : %8h", sram_a[AW-1:2], sram_d));

endmodule
