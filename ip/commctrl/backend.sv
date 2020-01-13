// backend.sv - Backend of COMM Controller
// HKL 01 2016

module backend
import comm_defs_pkg::*;
(
  // CLOCK AND RESETS ------------------
  input  logic clk,
  input  logic rstn,
  // From Port ------------------
  input  logic        fesel,          // 1'b1 = Scan Chain 1'b0 = UART
  // AHB-LITE MASTER PORT --------------
  output logic [31:0] haddr,          // AHB transaction Address
  output logic [2:0]  hsize,          // AHB size: byte, half-word or word
  output logic [1:0]  htrans,         // AHB transfer: non-sequential only
  output logic [31:0] hwdata,         // AHB write-data
  output logic        hwrite,         // AHB write control
  input  logic [31:0] hrdata,         // AHB read-data
  input  logic        hready,         // AHB stall signal
  input  logic        hresp,          // AHB err response
  output logic [1:0]  hmsel,          // select master module
  output logic        irq_o,          // interrupt to CM0

  // interface to uart_scan_mux
  input  logic        sm_start,       // State Machine Start Signal
  input  logic [31:0] addr,           // Decoded Address
  input  logic [31:0] wrdata,         // Decoded Write Data
  input  logic        we,             // Decoded Write Enable
  input  logic        decode_err,     // Decode err
  input  logic [15:0] err_code,       // err code
  input  logic        scanxfer,       // Flag bit to tell whether scan is xfering

  // interface to fro ntend
  input  logic        tx_work,        // 1-cycle pulse on tx transfer
  input  logic        echo_out,       // indicator for echo buffer out
  output logic        hmselbuf_xfer,  // xfer for hmsel buffer
  output logic        decerrbuf_xfer, // xfer for decode err buffer
  output logic        hrdatabuf_xfer, // xfer for hrdata buffer
  output logic        ahberrbuf_xfer, // xfer for ahb err buffer
  output logic [7:0]  hmselbuf_data,  // data for hmsel buffer
  output logic [7:0]  decerrbuf_data, // data for decode err buffer
  output logic [7:0]  hrdatabuf_data, // data for hrdata buffer
  output logic [7:0]  ahberrbuf_data, // data for ahb err buffer

  // interface to scan_master
  output logic [31:0] rddata_scan,    // rddata to scan master
  output logic [1:0]  hmsel_scan,     // rddata to scan master
  output logic        ahberr_scan,    // ahberr to scan master

  // state machine
  output logic        sm_hmsel,       // state=HMSEL_UPDATE
  output logic        sm_done,        // state=DONE
  output logic        sm_decerr,      // state=DECODE_ERR
  output logic        sm_ahbrd,       // state=AHB_READ
  output logic        sm_readout,     // state=READ_OUT
  output logic        sm_ahberr       // state=AHB_ERR
);

//---------------------------------------------------------------------------------
// TRANSACTIONS
//---------------------------------------------------------------------------------
// Decode err           (IDLE=>DECODE_ERR=>DONE)
// HMSEL                (IDLE=>HMSEL_UPDATE=>DONE)
// IRQ                  (IDLE=>IRQ=>DONE)
// AHB Write Transaction(IDLE=>AHB_ADDR=>AHB_WRITE=>DONE)
// AHB Read Transaction (IDLE=>AHB_ADDR=>AHB_READ=>READ_OUT=>DONE)
// AHB Transaction err  (IDLE=>AHB_ADDR=>AHB_READ/AHB_WRITE=>AHB_ERR=>DONE)
//---------------------------------------------------------------------------------

/////////////////////////////////////
// State Machine and Control Signals
/////////////////////////////////////
// Control signals for state machine
logic rd_done, wr_done, readout_done, irq_done;
logic hmsel_done, decerr_done, ahberr_done, irq_o_done;
logic bus_err, c_decode_err;
logic c_hmsel_update, c_ahb_xfer, c_irq;

always_comb begin
c_decode_err   = (sm_start&&decode_err);
c_hmsel_update = (sm_start&&(!decode_err)&&(addr==32'h10000000));
c_irq          = (sm_start&&(!decode_err)&&(addr==32'h10000004));
c_ahb_xfer     = (sm_start&&(!decode_err)&&(hmsel==2'b00));
end

// State Machine
enum logic [3:0]
    {IDLE, DECODE_ERR, HMSEL_UPDATE, IRQ,
     AHB_ERR, AHB_ADDR, AHB_WRITE,
     AHB_READ, READ_OUT, DONE
    } state, state_nxt;
`FF(state_nxt,state,clk,1'b1,rstn,IDLE);

always_comb begin
case(state)
IDLE:
state_nxt = (c_decode_err) ? DECODE_ERR :
            (c_hmsel_update) ? HMSEL_UPDATE :
            (c_irq) ? IRQ :
            (c_ahb_xfer) ? AHB_ADDR : IDLE;
DECODE_ERR:
state_nxt = (decerr_done) ? DONE : DECODE_ERR;
HMSEL_UPDATE:
state_nxt = (hmsel_done) ? DONE : HMSEL_UPDATE;
IRQ:
state_nxt = (irq_done) ? DONE : IRQ;
AHB_ADDR:
state_nxt = (we) ? AHB_WRITE : AHB_READ;
AHB_READ:
state_nxt = (bus_err) ? AHB_ERR :
            (rd_done)   ? READ_OUT : AHB_READ;
AHB_WRITE:
state_nxt = (bus_err) ? AHB_ERR :
            (wr_done)   ? DONE : AHB_WRITE;
READ_OUT:
state_nxt = (readout_done) ? DONE : READ_OUT;
AHB_ERR:
state_nxt = (ahberr_done) ? DONE : AHB_ERR;
DONE:
state_nxt = IDLE;
default:
state_nxt = IDLE;
endcase
end

// state indicator
logic sm_ahbaddr, sm_ahbwr, sm_irq;

always_comb begin
sm_decerr  = (state==DECODE_ERR);
sm_hmsel   = (state==HMSEL_UPDATE);
sm_irq     = (state==IRQ);
sm_ahberr  = (state==AHB_ERR);
sm_ahbaddr = (state==AHB_ADDR);
sm_ahbwr   = (state==AHB_WRITE);
sm_ahbrd   = (state==AHB_READ);
sm_readout = (state==READ_OUT);
sm_done    = (state==DONE);
end

//////////////////////////
// TYPE 1 : Decode err
//////////////////////////
// Store err Code into decerrbuf
// eg. "DECODE_ERR: 23"
logic [17:0][7:0] decerrbuf, decerrbuf_nxt;
`FF(decerrbuf_nxt,decerrbuf,clk,sm_decerr,rstn,'0);

always_comb begin
decerrbuf_nxt[11:0]  = DECERR_STR;  // ERR
decerrbuf_nxt[12]    = ASCII_COLON; // :
decerrbuf_nxt[13]    = ASCII_SPACE; // (space)
decerrbuf_nxt[15:14] = err_code;    // err_code
decerrbuf_nxt[16]    = ASCII_CR;    // CR
decerrbuf_nxt[17]    = ASCII_LF;    // LF
end

// decerrbuf transaction
logic decerrbuf_done, decerrbuf_done_nxt;
logic decerrbuf_out,  decerrbuf_out_nxt;
logic [4:0] decerrbuf_cnt, decerrbuf_cnt_nxt;

always_comb begin
decerrbuf_out_nxt  = (sm_decerr&&(!echo_out));
decerrbuf_done_nxt = (decerrbuf_cnt==5'd18) ? 1'b1 : 1'b0;
decerrbuf_cnt_nxt  = (!decerrbuf_out) ? 5'h0 :
                     (tx_work&&(!decerrbuf_done)) ? decerrbuf_cnt+5'd1 :
                     (decerrbuf_done) ? 5'h0 : decerrbuf_cnt;
end

`FF(decerrbuf_out_nxt,decerrbuf_out,clk,1'b1,rstn,1'b0);
`FF(decerrbuf_done_nxt,decerrbuf_done,clk,1'b1,rstn,1'b0);
`FF(decerrbuf_cnt_nxt,decerrbuf_cnt,clk,1'b1,rstn,5'd0);

// done signal
always_comb decerr_done = (sm_decerr) ? decerrbuf_done : 1'b0;

/////////////////////////////////////
// TYPE 2 : HMSEL
/////////////////////////////////////
// WRITE
logic [1:0] hmsel_nxt;
always_comb hmsel_nxt = (we) ? wrdata[1:0] : hmsel;
`FF(hmsel_nxt,hmsel,clk,sm_hmsel,rstn,2'd0);

// READ

// Scan Chain Frontend
// when scan xfer is done, hmsel_scan is set to 2'd0
// for read xfer, hmsel_scan is set to hmsel
// otherwises, keep the current value
logic [1:0] hmsel_scan_nxt;
always_comb hmsel_scan_nxt = (scanxfer) ? 2'd0 :
                             (sm_hmsel&&(!we)) ? hmsel : hmsel_scan;
`FF(hmsel_scan_nxt[1:0],hmsel_scan[1:0],clk,1'b1,rstn,2'd0);

// UART Frontend
// Store hmsel into hmselbuf
// eg. "HMSEL: 1"
logic [9:0][7:0] hmselbuf, hmselbuf_nxt;
`FF(hmselbuf_nxt,hmselbuf,clk,sm_hmsel,rstn,'0);

always_comb begin
hmselbuf_nxt[4:0] = HMSEL_STR;                   // HMSEL
hmselbuf_nxt[5]   = ASCII_COLON;                 // :
hmselbuf_nxt[6]   = ASCII_SPACE;                 // (space)
hmselbuf_nxt[7]   = num_to_ascii({2'b00,hmsel}); // hmsel
hmselbuf_nxt[8]   = ASCII_CR;                    // CR
hmselbuf_nxt[9]   = ASCII_LF;                    // LF
end

// hmselbuf transaction
logic hmselbuf_done, hmselbuf_done_nxt;
logic hmselbuf_out,  hmselbuf_out_nxt;
logic [3:0] hmselbuf_cnt, hmselbuf_cnt_nxt;

always_comb begin
hmselbuf_out_nxt  = (sm_hmsel&&(!we)&&(!echo_out));
hmselbuf_done_nxt = (hmselbuf_cnt==4'd10) ? 1'b1 : 1'b0;
hmselbuf_cnt_nxt  = (!hmselbuf_out) ? 4'h0 :
                    (tx_work&&(!hmselbuf_done)) ? hmselbuf_cnt+4'd1 :
                    (hmselbuf_done) ? 4'h0 : hmselbuf_cnt;
end

`FF(hmselbuf_out_nxt,hmselbuf_out,clk,1'b1,rstn,1'b0);
`FF(hmselbuf_done_nxt,hmselbuf_done,clk,1'b1,rstn,1'b0);
`FF(hmselbuf_cnt_nxt,hmselbuf_cnt,clk,1'b1,rstn,4'h0);

// done signal
// UART : write takes 1 cycle / read takes multiple cycles
// SCAN : write takes 1 cycle / read takes 1 cycle
always_comb hmsel_done = (!sm_hmsel) ? 1'b0 :
                         (we) ? 1'b1 :
                         (fesel) ? 1'b1 : hmselbuf_done;

/////////////////////////////////////
// TYPE 3 : IRQ_CM0
/////////////////////////////////////
// when state is done, irq needs to be clear
// when we is 1'b1, update irq with wrdata[0] to generate interrupt
logic irq_nxt, irq, irq_1;
always_comb irq_nxt = (sm_done) ? 1'b0 :
                      (we) ? wrdata[0] : irq;
`FF(irq_nxt,irq,clk,(sm_irq|sm_done),rstn,1'b0);
`FF(irq,irq_1,clk,1'b1,rstn,1'b0);
// Generate a cycle pulse for interrupt to CM0
always_comb irq_o = (irq & (~irq_1));

// UART, SCAN : takes 1 cycle
always_comb irq_done = (!sm_irq) ? 1'b0 : 1'b1;


////////////////////////////////////////////////////
// AHB TRANSACTIONS (WRITE, READ, ERR, READ_OUT)
////////////////////////////////////////////////////

//---------------------------------------------------------
// STATE = AHB_ADDR (AHB Address Phase)
//---------------------------------------------------------
// haddr, hsize, hwrite, htrans is set in AHB_ADDR state
// Currently, 32-bit bus xfer is only supported. (hsize=2'b10)
always_comb begin
haddr  = (sm_ahbaddr)  ? addr   : 32'd0;
hsize  = (sm_ahbaddr)  ? 2'b10  : 2'b00;
hwrite = (sm_ahbaddr)  ? we     : 1'b0;
htrans = (sm_ahbaddr)  ? 3'b010 : 3'b000;
end

//---------------------------------------------------------
// STATE = AHB_WRITE (AHB Data Phase)
//---------------------------------------------------------
// hwdata is set to wrdata in AHB_WRITE state
// write xfer has no ereror when hready is gets back to high
// and hresp stays low.

logic wr_err;

always_comb begin
hwdata   = (sm_ahbwr) ? wrdata : 32'd0;
wr_done  = (sm_ahbwr&&hready&&(!hresp));
wr_err = (sm_ahbwr&&hresp);
end

//---------------------------------------------------------
// STATE = AHB_READ (AHB Data Phase)
//---------------------------------------------------------
// rddata is set to hrdata in AHB_READ state
// read xfer has no ereror when hready is gets back to high
// and hresp stays low.

logic rd_err;
logic [31:0] rddata;

always_comb begin
rddata   = (sm_ahbrd&&hready) ? hrdata[31:0] : 32'd0; // Transaction when hready is 1
rd_done  = (sm_ahbrd&&hready&&(!hresp));
rd_err = (sm_ahbrd&&hresp);
end

// rddata for scan master
logic [31:0] rddata_scan_nxt;
always_comb rddata_scan_nxt = (scanxfer) ? 32'd0 :
                              (sm_ahbrd&&hready) ? hrdata[31:0] : rddata_scan;
`FF(rddata_scan_nxt[31:0],rddata_scan[31:0],clk,1'b1,rstn,32'd0);

//---------------------------------------------------------
// STATE = READ_OUT (read out hrdata)
//---------------------------------------------------------
// Store hrdata into hrdatabuf
// eg. "HRDATA: 0x12341234"
logic [19:0][7:0] hrdatabuf, hrdatabuf_nxt;
`FF(hrdatabuf_nxt,hrdatabuf,clk,rd_done,rstn,'0);
always_comb begin
hrdatabuf_nxt[5:0] = HRDATA_STR;                  // HRDATA
hrdatabuf_nxt[6]   = ASCII_COLON;                 // :
hrdatabuf_nxt[7]   = ASCII_SPACE;                 // (space)
hrdatabuf_nxt[8]   = ASCII_0;                     // 0
hrdatabuf_nxt[9]   = ASCII_x;                     // x
hrdatabuf_nxt[10]  = num_to_ascii(rddata[31:28]); // rddata_7
hrdatabuf_nxt[11]  = num_to_ascii(rddata[27:24]); // rddata_6
hrdatabuf_nxt[12]  = num_to_ascii(rddata[23:20]); // rddata_5
hrdatabuf_nxt[13]  = num_to_ascii(rddata[19:16]); // rddata_4
hrdatabuf_nxt[14]  = num_to_ascii(rddata[15:12]); // rddata_3
hrdatabuf_nxt[15]  = num_to_ascii(rddata[11: 8]); // rddata_2
hrdatabuf_nxt[16]  = num_to_ascii(rddata[7 : 4]); // rddata_1
hrdatabuf_nxt[17]  = num_to_ascii(rddata[3 : 0]); // rddata_0
hrdatabuf_nxt[18]  = ASCII_CR;                    // CR
hrdatabuf_nxt[19]  = ASCII_LF;                    // LF
end

// hrdatabuf transaction
logic hrdatabuf_done, hrdatabuf_done_nxt;
logic hrdatabuf_out,  hrdatabuf_out_nxt;
logic [4:0] hrdatabuf_cnt, hrdatabuf_cnt_nxt;

always_comb begin
hrdatabuf_out_nxt  = (sm_readout&&(!echo_out));
hrdatabuf_done_nxt = (hrdatabuf_cnt==5'd20) ? 1'b1 : 1'b0;
hrdatabuf_cnt_nxt  = (!hrdatabuf_out) ? 5'd0 :
                     (tx_work&&(!hrdatabuf_done)) ? hrdatabuf_cnt+5'd1 :
                     (hrdatabuf_done) ? 5'd0 : hrdatabuf_cnt;
end

`FF(hrdatabuf_out_nxt,hrdatabuf_out,clk,1'b1,rstn,1'b0);
`FF(hrdatabuf_done_nxt,hrdatabuf_done,clk,1'b1,rstn,1'b0);
`FF(hrdatabuf_cnt_nxt,hrdatabuf_cnt,clk,1'b1,rstn,5'd0);

// Done signal
// UART : readout takes multiple cycles
// SCAN : readout takes a cycle
always_comb readout_done = (!sm_readout) ? 1'b0 :
                           (fesel) ? 1'b1 : hrdatabuf_done;

//---------------------------------------------------------
// STATE = AHB_ERR (when hresp=1 in AHB Data Phase)
//---------------------------------------------------------
// Detect Bus transaction err
always_comb bus_err = (wr_err||rd_err);

// For scan master
// When ahb bust err occurs, assert ahberr_scan
logic ahberr_scan_nxt;
always_comb ahberr_scan_nxt = (scanxfer) ? 1'b0 :
                              (sm_ahberr) ? 1'b1 : ahberr_scan;
`FF(ahberr_scan_nxt,ahberr_scan,clk,1'b1,rstn,1'b0);

// Store AHB err Message into ahberrbuf
// eg. "AHB_ERR: HADDR=0x18000000"
logic [28:0][7:0] ahberrbuf, ahberrbuf_nxt;
`FF(ahberrbuf_nxt,ahberrbuf,clk,sm_ahberr,rstn,'0);
always_comb begin
ahberrbuf_nxt[8:0]   = AHBERR_STR;                // AHB_ERR
ahberrbuf_nxt[9]     = ASCII_COLON;               // :
ahberrbuf_nxt[10]    = ASCII_SPACE;               // (space)
ahberrbuf_nxt[15:11] = HADDR_STR;                 // HADDR
ahberrbuf_nxt[16]    = ASCII_EQUAL;               // =
ahberrbuf_nxt[17]    = ASCII_0;                   // 0
ahberrbuf_nxt[18]    = ASCII_x;                   // x
ahberrbuf_nxt[19]    = num_to_ascii(addr[31:28]); // addr_7
ahberrbuf_nxt[20]    = num_to_ascii(addr[27:24]); // addr_6
ahberrbuf_nxt[21]    = num_to_ascii(addr[23:20]); // addr_5
ahberrbuf_nxt[22]    = num_to_ascii(addr[19:16]); // addr_4
ahberrbuf_nxt[23]    = num_to_ascii(addr[15:12]); // addr_3
ahberrbuf_nxt[24]    = num_to_ascii(addr[11: 8]); // addr_2
ahberrbuf_nxt[25]    = num_to_ascii(addr[7 : 4]); // addr_1
ahberrbuf_nxt[26]    = num_to_ascii(addr[3 : 0]); // addr_0
ahberrbuf_nxt[27]    = ASCII_CR;                  // CR
ahberrbuf_nxt[28]    = ASCII_LF;                  // LF
end

// ahberrbuf transaction
logic ahberrbuf_done, ahberrbuf_done_nxt;
logic ahberrbuf_out,  ahberrbuf_out_nxt;
logic [4:0] ahberrbuf_cnt, ahberrbuf_cnt_nxt;

always_comb begin
ahberrbuf_out_nxt  = (sm_ahberr&&(!echo_out));
ahberrbuf_done_nxt = (ahberrbuf_cnt==5'd29) ? 1'b1 : 1'b0;
ahberrbuf_cnt_nxt  = (!ahberrbuf_out) ? 5'd0 :
                     (tx_work&&(!ahberrbuf_done)) ? ahberrbuf_cnt+5'd1 :
                     (ahberrbuf_done) ? 5'd0 : ahberrbuf_cnt;
end

`FF(ahberrbuf_out_nxt,ahberrbuf_out,clk,1'b1,rstn,1'b0);
`FF(ahberrbuf_done_nxt,ahberrbuf_done,clk,1'b1,rstn,1'b0);
`FF(ahberrbuf_cnt_nxt,ahberrbuf_cnt,clk,1'b1,rstn,5'd0);

// Done signal
// UART : readout takes multiple cycles
// SCAN : readout takes a cycle
always_comb ahberr_done = (!sm_ahberr) ? 1'b0 :
                          (fesel) ? 1'b1 : ahberrbuf_done;

//---------------------------------------------------------
// transfer signals for uart tx mux
//---------------------------------------------------------
always_comb begin
hmselbuf_xfer  = hmselbuf_out &&(!hmselbuf_done);
decerrbuf_xfer = decerrbuf_out&&(!decerrbuf_done);
hrdatabuf_xfer = hrdatabuf_out&&(!hrdatabuf_done);
ahberrbuf_xfer = ahberrbuf_out&&(!ahberrbuf_done);
hmselbuf_data  = hmselbuf[hmselbuf_cnt];
decerrbuf_data = decerrbuf[decerrbuf_cnt];
hrdatabuf_data = hrdatabuf[hrdatabuf_cnt];
ahberrbuf_data = ahberrbuf[ahberrbuf_cnt];
end


endmodule
