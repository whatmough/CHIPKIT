// uartfront.sv - Front End of COMM Controller
// HKL 01 2016

module uartfront
import comm_defs_pkg::*;
(
  // clock and reset
  input  logic clk,
  input  logic rstn,

  // uart interface (rts signal generated in top-level)
  input  logic [3:0] baud_sel, // select Baud Rate
  input  logic       rxd,      // receive data
  input  logic       cts,      // clear to signal (connected to rts)
  output logic       rts,      // request to signal (connected to cts)
  output logic       txd,      // transmit data

  // Interface to Decoder
  output logic                end_of_inst,          // The end of instruction
  output logic [IBUF_SZ-1:0][IBUF_DW-1:0] ibuf_dec, // Instruction to be decoded
  output logic [IBUF_AW-1:0]  ibuf_cnt_dec,         // Size of Instruction to be decoded

  // interface to backend
  output logic       tx_work,         // 1-cycle pulse on tx transfer
  output logic       echo_out,        // indicator for echo buffer out
  input  logic       hmselbuf_xfer,   // xfer for hmsel buffer
  input  logic       decerrbuf_xfer,  // xfer for decode err buffer
  input  logic       hrdatabuf_xfer,  // xfer for hrdata buffer
  input  logic       ahberrbuf_xfer,  // xfer for ahb err buffer
  input  logic [7:0] hmselbuf_data,   // data for hmsel buffer
  input  logic [7:0] decerrbuf_data,  // data for decode err buffer
  input  logic [7:0] hrdatabuf_data,  // data for hrdata buffer
  input  logic [7:0] ahberrbuf_data,  // data for ahb err buffer

  // state machine
  input  logic       sm_hmsel,        // state=HMSEL_UPDATE
  input  logic       sm_done,         // state=DONE
  input  logic       sm_decerr,       // state=DECODE_ERR
  input  logic       sm_ahbrd,        // state=AHB_READ
  input  logic       sm_readout,      // state=READ_OUT
  input  logic       sm_ahberr        // state=AHB_ERR
);

//---------------------------------------------------------
// Baud divider MUX
//---------------------------------------------------------
// This is a just 16-to-1 MUX with 4-bit select
// There are no flip flops
logic [11:0] baud_div;
baudmux u_baudmux(
.baud_sel, // select for baud dividers
.baud_div  // selected baud divider
);

//---------------------------------------------------------
// UART
//---------------------------------------------------------
logic [7:0] rx_byte, tx_byte;
logic txen, tx_ing, rx_done, rx_ing, rx_err;

// UART instatiation
uart u_uart(
  .clk,      // The master clock for this module
  .rstn,     // Asynchronous reset.
  .baud_div, // Baud Rate Divider
  .rxd,      // Incoming serial line
  .txd,      // Outgoing serial line
  .txen,     // TX enable
  .tx_byte,  // Byte to transmit
  .rx_done,  // Indicate that a byte has been received.
  .rx_byte,  // Byte received
  .rx_ing,   // Low when receive line is idle.
  .tx_ing,   // Low when transmit line is idle.
  .rx_err    // Indicates err in receiving packet.
);

// Generating a 1-cycle pulse on TX transfer
logic tx_ing_n;
`FF(~tx_ing,tx_ing_n,clk,1'b1,rstn,1'b0);
always_comb tx_work = tx_ing & tx_ing_n;

// registering received byte
logic [7:0] rx_byte_reg;
`FF(rx_byte,rx_byte_reg,clk,rx_done,rstn,8'h00);

// For ibuf update
logic ibuf_update;
`FF(rx_done,ibuf_update,clk,1'b1,rstn,1'b0);

//---------------------------------------------------------
// Buffer for Echo back
//---------------------------------------------------------
logic [EBUF_SZ-1:0][EBUF_DW-1:0] echobuf;
logic echobuf_full, echobuf_empty, echobuf_flush;
logic echo_xfer, echobuf_wrxfer, echobuf_rdxfer;
logic [EBUF_AW-1:0] echobuf_wrcnt, echobuf_wrcnt_nxt;
logic [EBUF_AW-1:0] echobuf_rdcnt, echobuf_rdcnt_nxt;
logic [EBUF_AW-1:0] echobuf_depth, echobuf_depth_nxt;

// Registering a byte to echo back
always_ff @(posedge clk or negedge rstn) begin
  if (!rstn) echobuf <= '0;
  else if (ibuf_update) echobuf[echobuf_wrcnt] <= rx_byte_reg;
end

// Xfer signals for read and write
always_comb begin
echo_xfer = ((echobuf_depth!=0)&&(!tx_ing));
echobuf_wrxfer = ibuf_update;
echobuf_rdxfer = (tx_work&&(!echobuf_empty));
end

// Write/Read counter, Depth pointer
`FF(echobuf_wrcnt_nxt,echobuf_wrcnt,clk,1'b1,rstn,'0);
`FF(echobuf_rdcnt_nxt,echobuf_rdcnt,clk,1'b1,rstn,'0);
`FF(echobuf_depth_nxt,echobuf_depth,clk,1'b1,rstn,'0);

always_comb begin
echobuf_wrcnt_nxt = (echobuf_wrxfer) ? echobuf_wrcnt+1 : echobuf_wrcnt;
echobuf_rdcnt_nxt = (echobuf_rdxfer) ? echobuf_rdcnt+1 : echobuf_rdcnt;
echobuf_depth_nxt =
    (echobuf_wrxfer&&echobuf_rdxfer) ? echobuf_depth :    // write/read at the same time
    (echobuf_wrxfer&&!echobuf_rdxfer) ? echobuf_depth+1 : // write
    (!echobuf_wrxfer&&echobuf_rdxfer) ? echobuf_depth-1 : // read
    echobuf_depth; // neight of them
end

// whether echobuf is full or empty
always_comb echobuf_full  = (echobuf_depth==(EBUF_SZ-1));
always_comb echobuf_empty = (echobuf_depth==0);

// echo_out should be 1 until all received instruction is echo back
always_ff @(posedge clk or negedge rstn) begin
  if (!rstn) echo_out <= 1'b0;
  else begin
    if (ibuf_update) echo_out <= 1'b1;
    else if (echobuf_empty) echo_out <= 1'b0;
  end
end

// if echo buffer is full, halt transactions to flush all buffer data
always_ff @(posedge clk or negedge rstn) begin
  if (!rstn) echobuf_flush <= 1'b0;
  else begin
    if (echobuf_full) echobuf_flush <= 1'b1;
    else if (echobuf_empty) echobuf_flush <= 1'b0;
  end
end

// Instruction Buffer (Shift Register)
logic [IBUF_SZ-1:0][IBUF_DW-1:0] ibuf, ibuf_nxt;
always_comb ibuf_nxt =
    (ibuf_update) ? {rx_byte_reg[7:0],ibuf[IBUF_SZ-1:1]} : ibuf;
`FF(ibuf_nxt,ibuf,clk,ibuf_update,rstn,'0);

// Instruction Counter
// when a byte is received (ibuf_update), increase ibuf_cnt by 1
// when a transaction is done (sm_done), reset it to zero
logic [IBUF_AW-1:0] ibuf_cnt, ibuf_cnt_nxt;
always_comb ibuf_cnt_nxt =
    (ibuf_update) ? ibuf_cnt+1 :
    (sm_done) ? 0 : ibuf_cnt;
`FF(ibuf_cnt_nxt,ibuf_cnt,clk,1'b1,rstn,'0);

// End of instruction when LF is received
logic end_of_inst_nxt;
always_comb end_of_inst_nxt = (rx_byte_reg==ASCII_LF) ? 1'b1 : 1'b0;
`FF(end_of_inst_nxt,end_of_inst,clk,1'b1,rstn,1'b0);

// Registering ibuf and ibuf_cnt for decode
`FF((ibuf>>(8*(IBUF_SZ-ibuf_cnt))),ibuf_dec,clk,end_of_inst,rstn,'0);
`FF(ibuf_cnt,ibuf_cnt_dec,clk,end_of_inst,rstn,IBUF_AW'(2));

//---------------------------------------------------------
// UART TX signals
//---------------------------------------------------------
logic [7:0] echobuf_data;
always_comb echobuf_data = echobuf[echobuf_rdcnt];
// TX enable
logic txen_nxt;
`FF(txen_nxt,txen,clk,1'b1,rstn,1'b0);
always_comb txen_nxt =
    (cts) ? 1'b0 :
    (hmselbuf_xfer)  ? 1'b1 : // hmsel out
    (decerrbuf_xfer) ? 1'b1 : // Decode err out
    (hrdatabuf_xfer) ? 1'b1 : // hrdata out
    (ahberrbuf_xfer) ? 1'b1 : // AHB err out
    (echo_xfer)      ? 1'b1 : // Echo back
    1'b0;

// TX Byte to send
logic [7:0] tx_byte_nxt;
`FF(tx_byte_nxt,tx_byte,clk,1'b1,rstn,8'h00);
always_comb tx_byte_nxt =
    (cts) ? 8'h00 :
    (hmselbuf_xfer)  ? hmselbuf_data  : // hmsel out
    (decerrbuf_xfer) ? decerrbuf_data : // Decode err out
    (hrdatabuf_xfer) ? hrdatabuf_data : // hrdata out
    (ahberrbuf_xfer) ? ahberrbuf_data : // AHB err out
    (echo_xfer)      ? echobuf_data   : // Echo back
    8'h00;

//---------------------------------------------------------
// Handshake (rts)
//---------------------------------------------------------
always_comb rts = (sm_hmsel||sm_decerr||sm_ahbrd||
                   sm_readout||sm_ahberr||echobuf_flush);

endmodule
