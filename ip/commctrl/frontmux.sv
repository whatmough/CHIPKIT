// frontmux.sv - MUX to select UART data or Scan Chain for frontend
// HKL 02 2016

module frontmux
import comm_defs_pkg::*;
(
  // interface to PAD
  input logic         fesel,             // 1'b1 = Scan Chain 1'b0 = UART

  // interface to decoder
  input logic [31:0]  addr_uart,         // Decoded Address
  input logic [31:0]  wrdata_uart,       // Decoded Write Data
  input logic         we_uart,           // Decoded Write Enable
  input logic         decode_err_uart,   // Decode err
  input logic         sm_start_uart,     // Start signal for FSM in backend
  input logic [15:0]  err_code_uart,     // err code

  // interface to scanfront
  input logic [31:0]  addr_scan,         // Address from Scan Chain
  input logic [31:0]  wrdata_scan,       // Write Data from Scan Chain
  input logic         we_scan,           // Write Enable from Scan Chain
  input logic         sm_start_scan,     // Start signal for FSM in backend
  input logic         scanxfer_scan,     // Flag bit to tell whether scan is xfering

  // interface to backend
  output logic        sm_start,          // State Machine Start Signal
  output logic [31:0] addr,              // Decoded Address
  output logic [31:0] wrdata,            // Decoded Write Data
  output logic        we,                // Decoded Write Enable
  output logic        decode_err,        // Decode err
  output logic [15:0] err_code,          // err code
  output logic        scanxfer           // Flag bit to tell whether scan is xfering
);

// When FESEL=1'b1 : Scan Chain Master
// When FESEL=1'b0 : UART frontend
always_comb begin
sm_start     = (fesel) ? sm_start_scan     : sm_start_uart;
addr         = (fesel) ? addr_scan         : addr_uart;
wrdata       = (fesel) ? wrdata_scan       : wrdata_uart;
we           = (fesel) ? we_scan           : we_uart;
decode_err   = (fesel) ? 1'b0              : decode_err_uart;
err_code     = (fesel) ? {ASCII_0,ASCII_0} : err_code_uart;
scanxfer     = (fesel) ? scanxfer_scan     : 1'b0;
end

endmodule
