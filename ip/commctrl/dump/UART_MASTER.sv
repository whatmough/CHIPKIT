// UART_MASTER.sv - wrapper for UART Controller
// HKL 01 2016

`include "rtl_macros.svh"

module UART_MASTER (
input logic HCLK, PORESETn,
ahb_master_intf.source M,

input  logic [3:0] UART_M_BAUD_SEL, // select Baud Rate
input  logic UART_M_RXD,      // receive data
input  logic UART_M_CTS,      // signal from RTS of PC
output logic UART_M_RTS,      // RTS signal to CTS signal of PC
output logic UART_M_TXD,      // transmit data
output logic [1:0] HMSEL      // select master module
);

uart_ctrl u_uart_ctrl (
  // CLOCK AND RESETS ------------------
    .clk            (HCLK),
    .rstn           (PORESETn),
  // AHB-LITE MASTER PORT --------------
    .haddr          (M.HADDR[31:0]),    // AHB transaction address            
    .hsize          (M.HSIZE[2:0]),     // AHB size: byte, half-word or word
    .htrans         (M.HTRANS[1:0]),    // AHB transfer: non-sequential only
    .hwdata         (M.HWDATA[31:0]),   // AHB write-data
    .hwrite         (M.HWRITE),         // AHB write control
    .hrdata         (M.HRDATA[31:0]),   // AHB read-data       
    .hready         (M.HREADY),         // AHB stall signal
    .hresp          (M.HRESP),          // AHB error response
  // UART Controller PORT --------------
    .baud_sel       (UART_M_BAUD_SEL),  // select Baud Rate
    .rxd            (UART_M_RXD),       // receive data
    .cts            (UART_M_CTS),       // signal from RTS of PC
    .rts            (UART_M_RTS),       // RTS signal to CTS signal of PC
    .txd            (UART_M_TXD),       // transmit data
    .hmsel          (HMSEL)             // select master module
);
endmodule
