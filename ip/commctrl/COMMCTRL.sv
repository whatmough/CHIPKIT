// COMMCTRL.sv - Top-level Comm Controller
// HKL 01 2016

`include "rtl_macros.svh"

module COMMCTRL
import comm_defs_pkg::*;
(
//input logic HCLK, PORESETn,
input logic clk, rstn,
ahb_master_intf.source M,

input  logic       FESEL,           // Front End Select
input  logic       SCLK1,           // scan clock 1
input  logic       SCLK2,           // scan clock 2
input  logic       SHIFTIN,         // shift in
input  logic       SCEN,            // scan enable
output logic       SHIFTOUT,        // shift out
input  logic [3:0] UART_M_BAUD_SEL, // select Baud Rate
input  logic       UART_M_RXD,      // receive data
input  logic       UART_M_CTS,      // signal from RTS of PC
output logic       UART_M_RTS,      // RTS signal to CTS signal of PC
output logic       UART_M_TXD,      // transmit data
output logic       IRQ_COMMCTRL,    // interrupt to CM0
output logic [1:0] HMSEL            // select master module
);

//---------------------------------------------------------
// Interface
//---------------------------------------------------------
// clock and reset
//logic clk, rstn;
//always_comb begin
//clk = HCLK;
//rstn = PORESETn;
//end

// ahb-lite master
logic [31:0] haddr, hwdata, hrdata;
logic [2:0] hsize;
logic [1:0] htrans;
logic hwrite, hresp, hready;
always_comb begin
hrdata = M.HRDATA[31:0];
hready = M.HREADY;
hresp  = M.HRESP;
M.HWDATA = hwdata[31:0];
M.HADDR  = haddr[31:0];
M.HWRITE = hwrite;
M.HTRANS = htrans[1:0];
M.HSIZE  = hsize[2:0];
end

// COMM Controller
logic [3:0] baud_sel;
logic txd, rxd, rts, cts;
logic [1:0] hmsel;
always_comb begin
baud_sel = UART_M_BAUD_SEL[3:0];
HMSEL[1:0] = hmsel;
UART_M_TXD = txd;
UART_M_RTS = rts;
end

// synchronize RXD and CTS using syncff_set
// RXD, CTS are active low
syncff_set u_syncff0
  (.clock(clk),.reset_n(rstn),.data_i(UART_M_RXD),.data_o(rxd));
syncff_set u_syncff1
  (.clock(clk),.reset_n(rstn),.data_i(UART_M_CTS),.data_o(cts));

//---------------------------------------------------------
// UART Frontend
//---------------------------------------------------------
logic end_of_inst;
logic [IBUF_SZ-1:0][IBUF_DW-1:0] ibuf_dec;
logic [IBUF_AW-1:0]  ibuf_cnt_dec;
logic hmselbuf_xfer, decerrbuf_xfer;
logic hrdatabuf_xfer, ahberrbuf_xfer;
logic [7:0] hmselbuf_data, decerrbuf_data;
logic [7:0] hrdatabuf_data, ahberrbuf_data;
logic tx_work, echo_out;
logic sm_hmsel, sm_decerr, sm_ahbrd;
logic sm_readout, sm_ahberr, sm_done;

uartfront u_uartfront (
.clk, .rstn,

// uart
.baud_sel,              // select Baud Rate
.rxd,                   // receive data
.cts,                   // clear to signal (connected to rts)
.rts,                   // request to signal (connected to cts)
.txd,                   // transmit data

// interface to decoder
.end_of_inst,           // The end of instruction
.ibuf_dec,              // Instruction to be decoded
.ibuf_cnt_dec,          // Size of Instruction to be decoded

// interface to backend
.tx_work,               // 1-cycle pulse on tx transfer
.echo_out,              // indicator for echo buffer out
.hmselbuf_xfer,         // xfer for hmsel buffer
.decerrbuf_xfer,        // xfer for decode err buffer
.hrdatabuf_xfer,        // xfer for hrdata buffer
.ahberrbuf_xfer,        // xfer for ahb err buffer
.hmselbuf_data,         // data for hmsel buffer
.decerrbuf_data,        // data for decode err buffer
.hrdatabuf_data,        // data for hrdata buffer
.ahberrbuf_data,        // data for ahb err buffer

// state machine
.sm_hmsel,              // state=HMSEL_UPDATE
.sm_done,               // state=DONE
.sm_decerr,             // state=DECODE_ERR
.sm_ahbrd,              // state=AHB_READ
.sm_readout,            // state=READ_OUT
.sm_ahberr              // state=AHB_ERR
);

//---------------------------------------------------------
// Decoder
//---------------------------------------------------------
logic [31:0] addr_uart, wrdata_uart;
logic we_uart, sm_start_uart;
logic decode_err_uart;
logic [15:0] err_code_uart;

decoder u_decoder(
.clk, .rstn,

// interface to uartfront
.end_of_inst,       // Indicate the end of instruction
.ibuf_dec,          // Instruction to be decoded
.ibuf_cnt_dec,      // Count of Instruction to be decoded

// interface to frontmux
.addr_uart,         // Decoded Address
.wrdata_uart,       // Decoded Write Data
.we_uart,           // Decoded Write Enable
.decode_err_uart,   // Decode err
.sm_start_uart,     // Start signal for FSM in backend
.err_code_uart      // err code
);

//---------------------------------------------------------
// Scan Chain Frontend
//---------------------------------------------------------
logic sclk1, sclk2, shiftin, scen, shiftout;
logic [31:0] addr_scan, wrdata_scan, rddata_scan;
logic we_scan, sm_start_scan, scanxfer_scan, ahberr_scan;
logic [1:0] hmsel_scan;

scanfront u_scanfront (
.clk, .rstn,

// Scan Chain signals
.sclk1(SCLK1),       // scan clock 1
.sclk2(SCLK2),       // scan clock 2
.shiftin(SHIFTIN),   // shift in
.scen(SCEN),         // scan enable
.shiftout(SHIFTOUT), // shift out

// interface to frontmux
.addr_scan,          // Address from Scan Chain
.wrdata_scan,        // Write Data from Scan Chain
.we_scan,            // Write Enable from Scan Chain
.sm_start_scan,      // Start signal for FSM in backend
.scanxfer_scan,      // Flag bit to tell whether scan is xfering

// interface to backend
.hmsel_scan,         // hmsel to scan master
.ahberr_scan,        // ahberr to scan master
.rddata_scan         // rddata to scan master
);

//---------------------------------------------------------
// UART_SCAN_MUX
//---------------------------------------------------------
logic [31:0] addr, wrdata;
logic we, sm_start, scanxfer;
logic decode_err;
logic [15:0] err_code;

frontmux u_frontmux (
// From PORT
.fesel(FESEL),      // 1'b1 = Scan Chain 1'b0 = UART

// interface to decoder
.addr_uart,         // Decoded Address
.wrdata_uart,       // Decoded Write Data
.we_uart,           // Decoded Write Enable
.decode_err_uart,   // Decode err
.sm_start_uart,     // Start signal for FSM in backend
.err_code_uart,     // err code

// interface to scanfront
.addr_scan,         // Address from Scan Chain
.wrdata_scan,       // Write Data from Scan Chain
.we_scan,           // Write Enable from Scan Chain
.sm_start_scan,     // Start signal for FSM in backend
.scanxfer_scan,     // Flag bit to tell whether scan is xfering

// interface to backend
.sm_start,          // State Machine Start Signal
.addr,              // Decoded Address
.wrdata,            // Decoded Write Data
.we,                // Decoded Write Enable
.decode_err,        // Decode err
.err_code,          // err code
.scanxfer           // Flag bit to tell whether scan is xfering
);

//---------------------------------------------------------
// Backend
//---------------------------------------------------------
logic irq_o;
backend u_backend(
.clk, .rstn,

// From PORT
.fesel(FESEL),          // 1'b1 = Scan Chain 1'b0 = UART

// AHB interfaace
.haddr,                 // AHB transaction Address
.hsize,                 // AHB size: byte, half-word or word
.htrans,                // AHB transfer: non-sequential only
.hwdata,                // AHB write-data
.hwrite,                // AHB write control
.hrdata,                // AHB read-data
.hready,                // AHB stall signal
.hresp,                 // AHB err response
.hmsel,                 // select master module
.irq_o,                 // interrupt to CM0

// interface to frontmux
.sm_start,              // State Machine Start Signal
.addr,                  // Decoded Address
.wrdata,                // Decoded Write Data
.we,                    // Decoded Write Enable
.decode_err,            // Decode err
.err_code,              // err code
.scanxfer,              // Flag bit to tell whether scan is xfering

// interface to uartfront
.tx_work,               // 1-cycle pulse on tx transfer
.echo_out,              // indicator for echo buffer out
.hmselbuf_xfer,         // xfer for hmsel buffer
.decerrbuf_xfer,        // xfer for decode err buffer
.hrdatabuf_xfer,        // xfer for hrdata buffer
.ahberrbuf_xfer,        // xfer for ahb err buffer
.hmselbuf_data,         // data for hmsel buffer
.decerrbuf_data,        // data for decode err buffer
.hrdatabuf_data,        // data for hrdata buffer
.ahberrbuf_data,        // data for ahb err buffer

// state machine
.sm_hmsel,              // state=HMSEL_UPDATE
.sm_done,               // state=DONE
.sm_decerr,             // state=DECODE_ERR
.sm_ahbrd,              // state=AHB_READ
.sm_readout,            // state=READ_OUT
.sm_ahberr,             // state=AHB_ERR

// interface to scanfront
.hmsel_scan,            // hmsel to scan master
.ahberr_scan,           // ahberr to scan master
.rddata_scan            // rddata to scan master

);


// Interrupt
always_comb IRQ_COMMCTRL = irq_o;

endmodule
