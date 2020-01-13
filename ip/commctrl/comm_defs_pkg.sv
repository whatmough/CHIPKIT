// min_defs_pkg.svh -
// PNW 12 2015

package comm_defs_pkg;


// RTL_DEBUG turns on logging macros in the design
`ifdef SYNTHESIS
localparam RTL_DEBUG = 0;
`else
localparam RTL_DEBUG = 1;
`endif

//////////////////////////////////
// Design Parameters
//////////////////////////////////

// Baud Rate
localparam WIDTH_BAUD_DIV = 12;
localparam WIDTH_BAUD_SEL = 4;

// Instruction Buffer
localparam IBUF_SZ = 25; // in Bytes
localparam IBUF_DW = 8;
localparam IBUF_AW = 5;

// Echo back buffer
localparam EBUF_SZ = 16; // Size
localparam EBUF_DW = 8; // Data bits
localparam EBUF_AW = 4; // Address bits


//////////////////////////////////
// Parameters for ASCII code
//////////////////////////////////
localparam ASCII_W = 8'h57;
localparam ASCII_w = 8'h77;
localparam ASCII_R = 8'h52;
localparam ASCII_r = 8'h72;
localparam ASCII_SPACE = 8'h20;
localparam ASCII_EQUAL = 8'h3D;
localparam ASCII_COLON = 8'h3A;
localparam ASCII_LF = 8'h0A;
localparam ASCII_CR = 8'h0D;
localparam ASCII_0 = 8'h30;
localparam ASCII_1 = 8'h31;
localparam ASCII_2 = 8'h32;
localparam ASCII_3 = 8'h33;
localparam ASCII_4 = 8'h34;
localparam ASCII_5 = 8'h35;
localparam ASCII_6 = 8'h36;
localparam ASCII_7 = 8'h37;
localparam ASCII_8 = 8'h38;
localparam ASCII_9 = 8'h39;
localparam ASCII_A = 8'h41;
localparam ASCII_B = 8'h42;
localparam ASCII_C = 8'h43;
localparam ASCII_D = 8'h44;
localparam ASCII_E = 8'h45;
localparam ASCII_F = 8'h46;
localparam ASCII_x = 8'h78, ASCII_X = 8'h58;

// ASCII codes for different strings
// It should be in the opposite order
localparam HRDATA_STR = 48'h415441445248; // HRDATA (6 bytes)
localparam HMSEL_STR  = 40'h4C45534D48;   // HMSEL  (5 bytes)
localparam DECERR_STR = 96'h524F5252455F45444F434544; // DECODE_ERR (12 bytes)
localparam AHBERR_STR = 72'h524F5252455F424841; // AHB_ERR (9 bytes)
localparam HADDR_STR  = 40'h5244444148; // HADDR (5 bytes)

//////////////////////////////////
// Functions
//////////////////////////////////

// ASCII Code converted to Number
function automatic [3:0] ascii_to_num (input [7:0] ascii);
  return (((ascii>=8'h30)&&(ascii<=8'h39)) ? 4'(ascii-8'h30) : 4'(ascii-8'h41+10));
endfunction
// err when ASCII Code converted to Number
function automatic ascii_to_num_err (input [7:0] ascii);
  return ((ascii>=8'h30)&&(ascii<=8'h39)) ? 1'b0 :
         ((ascii>=8'h41)&&(ascii<=8'h46)) ? 1'b0 : 1'b1;
endfunction

// Number converted to ASCII Code
function automatic [7:0] num_to_ascii (input [3:0] num_in_hex);
  return (num_in_hex<=9) ? (8'(num_in_hex) + 8'h30) : (8'(num_in_hex) + 8'h41 - 8'd10);
endfunction

endpackage

