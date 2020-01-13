// scanfront.sv - Scan Chain Master
// HKL 02 2016

module scanfront
(
  // CLOCK AND RESETS
  input  logic clk,
  input  logic rstn,

  // Scan Chain signals
  input  logic        sclk1,         // scan clock 1
  input  logic        sclk2,         // scan clock 2
  input  logic        shiftin,       // shift in
  input  logic        scen,          // scan enable
  output logic        shiftout,      // shift out

  // Interface to Dec_MUX
  output logic [31:0] addr_scan,     // Address from Scan Chain
  output logic [31:0] wrdata_scan,   // Write Data from Scan Chain
  output logic        we_scan,       // Write Enable from Scan Chain
  output logic        sm_start_scan, // Start signal for FSM in backend
  output logic        scanxfer_scan, // Flag bit to tell whether scan is xfering

  // Interface to backend
  input  logic [31:0] rddata_scan,   // rddata to scan master
  input  logic [1:0]  hmsel_scan,    // hmsel to scan master
  input  logic        ahberr_scan    // ahberr to scan master

);

// Signals  |ahberr| hmsel |rddata |wrdata | addr |we |ahbxfer|
// num_bits |  1   |   2   |  32   |  32   |  32  | 1 |   1   |
// Region   |[100] |[99:98]|[97:66]|[65:34]|[33:2]|[1]|  [0]  |
// Instantiate a scan chain
logic [99:0] scancell_q;
logic [100:0] internal_nodes;
logic [31:0] wrdata, addr;
logic we, ahbxfer;

scancell u_scancell[100:0] (
    .sclk1,
    .sclk2,
    .shiftin({scancell_q[99:0],shiftin}),
    .scen,
    .internal_data(internal_nodes),
    .shiftout({shiftout, scancell_q[99:0]})
);

// Connect to internal blocks
always_comb internal_nodes =
    {
    ahberr_scan,
    hmsel_scan[1:0],
    rddata_scan[31:0],
    wrdata[31:0],
    addr[31:0],
    we,
    ahbxfer
    };

// q pins are connected to internal blocks
// to load them
always_comb ahbxfer      = scancell_q[0];
always_comb we           = scancell_q[1];
always_comb addr[31:0]   = scancell_q[33:2];
always_comb wrdata[31:0] = scancell_q[65:34];


// Generate control and data signals based on scan chain values
// Synchronize to FFs in HCLK domain

// Synchronize scen
logic scen_sync;
syncff u_syncff
  (.clock(clk),.reset_n(rstn),.data_i(scen),.data_o(scen_sync));

// sm_start is a 1-cycle pulse
// sense falling-edge to generate a 1-cycle pulse
logic sm_start, sm_start_reg;
logic scen_sync_1;
`FF(scen_sync,scen_sync_1,clk,1'b1,rstn,1'b0);
always_comb sm_start = (~scen_sync) & scen_sync_1;

// Add a cycle delay
logic sm_start_nxt, sm_start_reg_1;
always_comb sm_start_nxt = sm_start & ahbxfer;
`FF(sm_start_nxt,sm_start_reg,clk,1'b1,rstn,1'b0);
`FF(sm_start_reg,sm_start_reg_1,clk,1'b1,rstn,1'b0);

// FF with enable for data from scan chain
logic we_reg;
logic [31:0] addr_reg;
logic [31:0] wrdata_reg;
`FF(we,we_reg,clk,sm_start_reg,rstn,1'b0);
`FF(addr[31:0],addr_reg[31:0],clk,sm_start_reg,rstn,32'd0);
`FF(wrdata[31:0],wrdata_reg[31:0],clk,sm_start_reg,rstn,32'd0);


// Output assignments
always_comb begin
addr_scan     = addr_reg;
wrdata_scan   = wrdata_reg;
we_scan       = we_reg;
sm_start_scan = sm_start_reg_1;
scanxfer_scan = scen_sync;
end


endmodule
