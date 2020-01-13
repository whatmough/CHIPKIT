// decoder.sv - Decoder of UART Controller
// HKL 01 2016

module decoder
import comm_defs_pkg::*;
(
  // clock and reset
  input  logic clk,
  input  logic rstn,

  // Interface to frontend
  input logic                end_of_inst,          // Indicate the end of instruction
  input logic [IBUF_SZ-1:0][IBUF_DW-1:0] ibuf_dec, // Instruction to be decoded
  input logic [IBUF_AW-1:0]  ibuf_cnt_dec,         // Count of Instruction to be decoded

  // Interface to backend
  output logic [31:0]  addr_uart,       // Decoded Address
  output logic [31:0]  wrdata_uart,     // Decoded Write Data
  output logic         we_uart,         // Decoded Write Enable
  output logic         decode_err_uart, // Decode err
  output logic         sm_start_uart,   // Start signal for FSM in backend
  output logic [15:0]  err_code_uart    // err code
);

//---------------------------------------------------------
// DECODE (combinational logic)
// 1. WRITE
// | 0 |1|2| 3 |4 - 11|12|13|14|15- 22|23|24|
// |W/w| |0|X/x|WRADDR|  | 0| x|WRDATA|CR|LF|
// 2. READ
// | 0 |1|2| 3 |4 - 11|12|13|
// |R/r| |0|X/x|RDADDR|CR|LF|
//---------------------------------------------------------
// Decode Address, Data, Write Enable, err
logic [31:0] addr, addr_nxt;
logic [31:0] wrdata, wrdata_nxt;
logic        we, we_nxt;
logic        decode_done;
logic        decode_err, decode_err_nxt;
logic [15:0] err_code, err_code_nxt;

// decode takes 1 cycle
`FF(end_of_inst,decode_done,clk,1'b1,rstn,1'b0);

// Bytes of instruction
logic wr_size_err, rd_size_err;
always_comb wr_size_err = (ibuf_cnt_dec!=IBUF_SZ);
always_comb rd_size_err = !((ibuf_cnt_dec>=14)&&(ibuf_cnt_dec<=IBUF_SZ));

// Line Breaks (CRLF/LF) for [23,24] or [12,13]
logic crlf_err;
always_comb crlf_err =
    !((ibuf_dec[ibuf_cnt_dec-2]==ASCII_LF)||
     ({ibuf_dec[ibuf_cnt_dec-2],ibuf_dec[ibuf_cnt_dec-1]}=={ASCII_CR,ASCII_LF}));

// W/w or R/r
logic rw_err;
always_comb rw_err =
    !((ibuf_dec[0]==ASCII_W)||(ibuf_dec[0]==ASCII_w)||
     (ibuf_dec[0]==ASCII_R)||(ibuf_dec[0]==ASCII_r));

// Separator ( 0x)
logic sep_err0;
always_comb sep_err0 =
    !((ibuf_dec[1] ==ASCII_SPACE)&&(ibuf_dec[2] ==ASCII_0)&&
     ((ibuf_dec[3] ==ASCII_X)||(ibuf_dec[3] ==ASCII_x)));

logic sep_err1;
always_comb sep_err1 =
    !((ibuf_dec[12]==ASCII_SPACE)&&(ibuf_dec[13]==ASCII_0)&&
     ((ibuf_dec[14]==ASCII_X)||(ibuf_dec[14]==ASCII_x)));

// Read or Write Address [11:4]
logic [3:0] addr_7, addr_6, addr_5, addr_4, addr_3, addr_2, addr_1, addr_0;
logic addr_err_7, addr_err_6, addr_err_5, addr_err_4;
logic addr_err_3, addr_err_2, addr_err_1, addr_err_0;
always_comb begin
addr_7     = ascii_to_num(ibuf_dec[4]);
addr_6     = ascii_to_num(ibuf_dec[5]);
addr_5     = ascii_to_num(ibuf_dec[6]);
addr_4     = ascii_to_num(ibuf_dec[7]);
addr_3     = ascii_to_num(ibuf_dec[8]);
addr_2     = ascii_to_num(ibuf_dec[9]);
addr_1     = ascii_to_num(ibuf_dec[10]);
addr_0     = ascii_to_num(ibuf_dec[11]);
addr_err_7 = ascii_to_num_err(ibuf_dec[4]);
addr_err_6 = ascii_to_num_err(ibuf_dec[5]);
addr_err_5 = ascii_to_num_err(ibuf_dec[6]);
addr_err_4 = ascii_to_num_err(ibuf_dec[7]);
addr_err_3 = ascii_to_num_err(ibuf_dec[8]);
addr_err_2 = ascii_to_num_err(ibuf_dec[9]);
addr_err_1 = ascii_to_num_err(ibuf_dec[10]);
addr_err_0 = ascii_to_num_err(ibuf_dec[11]);
end

// Write Data [22:15]
logic [3:0] wrdata_7, wrdata_6, wrdata_5, wrdata_4, wrdata_3, wrdata_2, wrdata_1, wrdata_0;
logic wrdata_err_7, wrdata_err_6, wrdata_err_5, wrdata_err_4;
logic wrdata_err_3, wrdata_err_2, wrdata_err_1, wrdata_err_0;
always_comb begin
wrdata_7     = ascii_to_num(ibuf_dec[15]);
wrdata_6     = ascii_to_num(ibuf_dec[16]);
wrdata_5     = ascii_to_num(ibuf_dec[17]);
wrdata_4     = ascii_to_num(ibuf_dec[18]);
wrdata_3     = ascii_to_num(ibuf_dec[19]);
wrdata_2     = ascii_to_num(ibuf_dec[20]);
wrdata_1     = ascii_to_num(ibuf_dec[21]);
wrdata_0     = ascii_to_num(ibuf_dec[22]);
wrdata_err_7 = ascii_to_num_err(ibuf_dec[15]);
wrdata_err_6 = ascii_to_num_err(ibuf_dec[16]);
wrdata_err_5 = ascii_to_num_err(ibuf_dec[17]);
wrdata_err_4 = ascii_to_num_err(ibuf_dec[18]);
wrdata_err_3 = ascii_to_num_err(ibuf_dec[19]);
wrdata_err_2 = ascii_to_num_err(ibuf_dec[20]);
wrdata_err_1 = ascii_to_num_err(ibuf_dec[21]);
wrdata_err_0 = ascii_to_num_err(ibuf_dec[22]);
end

// Next values after decoded
// Write Enable
always_comb we_nxt = ((ibuf_dec[0]==ASCII_W)||(ibuf_dec[0]==ASCII_w));

// Address
always_comb addr_nxt = {addr_7,addr_6,addr_5,addr_4,addr_3,addr_2,addr_1,addr_0};

// Wrdata
always_comb wrdata_nxt = {wrdata_7,wrdata_6,wrdata_5,wrdata_4,wrdata_3,wrdata_2,wrdata_1,wrdata_0};

// Decode err
always_comb begin
if (we_nxt) begin // Write Decode err
decode_err_nxt =
    crlf_err    |rw_err      |sep_err0    |sep_err1    |
    addr_err_7  |addr_err_6  |addr_err_5  |addr_err_4  |
    addr_err_3  |addr_err_2  |addr_err_1  |addr_err_0  |
    wrdata_err_7|wrdata_err_6|wrdata_err_5|wrdata_err_4|
    wrdata_err_3|wrdata_err_2|wrdata_err_1|wrdata_err_0;
end
else begin // Read Decode err
decode_err_nxt =
    crlf_err  |rw_err    |sep_err0  |
    addr_err_7|addr_err_6|addr_err_5|addr_err_4|
    addr_err_3|addr_err_2|addr_err_1|addr_err_0;
end
end

// err Code
always_comb begin
if(we_nxt) begin // Write Decode err Code
err_code_nxt =
    (wr_size_err)  ? {ASCII_0,ASCII_1} : // CODE 10 : Write Instruction Size err
    (rw_err)       ? {ASCII_1,ASCII_1} : // CODE 12 : W/w err
    (sep_err0)     ? {ASCII_0,ASCII_2} : // CODE 20 : First (Space)0x err
    (sep_err1)     ? {ASCII_1,ASCII_2} : // CODE 21 : Second (Space)0x err
    (crlf_err)     ? {ASCII_2,ASCII_2} : // CODE 22 : Line Break err
    (addr_err_0)   ? {ASCII_0,ASCII_3} : // CODE 30 : Address_0 NaN err
    (addr_err_1)   ? {ASCII_1,ASCII_3} : // CODE 31 : Address_1 NaN err
    (addr_err_2)   ? {ASCII_2,ASCII_3} : // CODE 32 : Address_2 NaN err
    (addr_err_3)   ? {ASCII_3,ASCII_3} : // CODE 33 : Address_3 NaN err
    (addr_err_4)   ? {ASCII_4,ASCII_3} : // CODE 34 : Address_4 NaN err
    (addr_err_5)   ? {ASCII_5,ASCII_3} : // CODE 35 : Address_5 NaN err
    (addr_err_6)   ? {ASCII_6,ASCII_3} : // CODE 36 : Address_6 NaN err
    (addr_err_7)   ? {ASCII_7,ASCII_3} : // CODE 37 : Address_7 NaN err
    (wrdata_err_0) ? {ASCII_0,ASCII_4} : // CODE 40 : Wrdata_0 NaN err
    (wrdata_err_1) ? {ASCII_1,ASCII_4} : // CODE 41 : Wrdata_1 NaN err
    (wrdata_err_2) ? {ASCII_2,ASCII_4} : // CODE 42 : Wrdata_2 NaN err
    (wrdata_err_3) ? {ASCII_3,ASCII_4} : // CODE 43 : Wrdata_3 NaN err
    (wrdata_err_4) ? {ASCII_4,ASCII_4} : // CODE 44 : Wrdata_4 NaN err
    (wrdata_err_5) ? {ASCII_5,ASCII_4} : // CODE 45 : Wrdata_5 NaN err
    (wrdata_err_6) ? {ASCII_6,ASCII_4} : // CODE 46 : Wrdata_6 NaN err
    (wrdata_err_7) ? {ASCII_7,ASCII_4} : // CODE 47 : Wrdata_7 NaN err
                     {ASCII_0,ASCII_0};  // No err
end
else begin  // Read Decode err Code
err_code_nxt =
    (rd_size_err)  ? {ASCII_0,ASCII_1} : // CODE 10 : Write Instruction Size err
    (rw_err)       ? {ASCII_1,ASCII_1} : // CODE 11 : R/r err
    (sep_err0)     ? {ASCII_0,ASCII_2} : // CODE 20 : First (Space)0x err
    (crlf_err)     ? {ASCII_2,ASCII_2} : // CODE 22 : Line Break err
    (addr_err_0)   ? {ASCII_0,ASCII_3} : // CODE 30 : Address_0 NaN err
    (addr_err_1)   ? {ASCII_1,ASCII_3} : // CODE 31 : Address_1 NaN err
    (addr_err_2)   ? {ASCII_2,ASCII_3} : // CODE 32 : Address_2 NaN err
    (addr_err_3)   ? {ASCII_3,ASCII_3} : // CODE 33 : Address_3 NaN err
    (addr_err_4)   ? {ASCII_4,ASCII_3} : // CODE 34 : Address_4 NaN err
    (addr_err_5)   ? {ASCII_5,ASCII_3} : // CODE 35 : Address_5 NaN err
    (addr_err_6)   ? {ASCII_6,ASCII_3} : // CODE 36 : Address_6 NaN err
    (addr_err_7)   ? {ASCII_7,ASCII_3} : // CODE 37 : Address_7 NaN err
                     {ASCII_0,ASCII_0};  // No err
end
end

// Address, Write_Data, Write_Enable
// Write Decode err, Read Decode err, err Code
`FF(addr_nxt,addr,clk,decode_done,rstn,32'd0);
`FF(wrdata_nxt,wrdata,clk,decode_done,rstn,32'd0);
`FF(we_nxt,we,clk,decode_done,rstn,1'b0);
`FF(decode_err_nxt,decode_err,clk,decode_done,rstn,1'b0);
`FF(err_code_nxt,err_code,clk,decode_done,rstn,22'd0);

// Generate a sm_start signal
// sm_start is a 1-cycle pulse
// this signal should be delayed with an extra cycle
// to sync up with other data
logic sm_start;
logic decode_done_reg, decode_done_reg_1;
`FF(decode_done,decode_done_reg,clk,1'b1,rstn,1'b0);
`FF(decode_done_reg,decode_done_reg_1,clk,1'b1,rstn,1'b0);
always_comb sm_start = decode_done_reg & (~decode_done_reg_1);


// Output Assignments
always_comb begin
addr_uart       = addr;
wrdata_uart     = wrdata;
we_uart         = we;
sm_start_uart   = sm_start;
decode_err_uart = decode_err;
err_code_uart   = err_code;
end

endmodule
