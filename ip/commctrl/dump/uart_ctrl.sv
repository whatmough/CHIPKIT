// uart_ctrl.sv - UART Controller
// HKL 01 2016 : Add package and interface

module uart_ctrl
import uart_defs_pkg::*;
(
  // CLOCK AND RESETS ------------------
  input  logic clk,
  input  logic rstn,
  // AHB-LITE MASTER PORT --------------
  output logic [31:0] haddr,    // AHB transaction Address            
  output logic [2:0]  hsize,    // AHB size: byte, half-word or word
  output logic [1:0]  htrans,   // AHB transfer: non-sequential only
  output logic [31:0] hwdata,   // AHB write-data
  output logic        hwrite,   // AHB write control
  input  logic [31:0] hrdata,   // AHB read-data       
  input  logic        hready,   // AHB stall signal
  input  logic        hresp,    // AHB error response
  // UART Controller PORT --------------
  input  logic [3:0]  baud_sel, // select Baud Rate
  input  logic        rxd,      // receive data
  input  logic        cts,      // clear to signal (connected to rts)
  output logic        rts,      // request to signal (connected to cts)
  output logic        txd,      // transmit data
  output logic [1:0]  hmsel     // select master module
);

//---------------------------------------------------------
// Set Baud Rates 
//---------------------------------------------------------
// For baud faster than 1Mbps, 50us line delay should be applied 
logic [11:0] baud_div;
always_comb begin
  case (baud_sel)
    4'd0 : baud_div = 12'd2604;
    4'd1 : baud_div = 12'd217; //  115200 bits/sec for 100Mhz
    4'd2 : baud_div = 12'd108; //  115200 bits/sec for 50Mhz
    4'd3 : baud_div = 12'd54;  //  230400 bits/sec for 50Mhz TESTED
    4'd4 : baud_div = 12'd27;  //  460800 bits/sec for 50Mhz TESTED
    4'd5 : baud_div = 12'd13;  // 1000000 bits/sec for 50Mhz TESTED
    4'd6 : baud_div = 12'd10;  // 1250000 bits/sec for 50Mhz TESTED
    4'd7 : baud_div = 12'd8;   // 1562500 bits/sec for 50Mhz TESTED
    4'd8 : baud_div = 12'd6;   // 2000000 bits/sec for 50Mhz *SOSO*
    4'd9 : baud_div = 12'd4;   // 3000000 bits/sec for 50Mhz *SOSO*
    4'd10: baud_div = 12'd130; //  115200 bits/sec for 60Mhz
    4'd11: baud_div = 12'd65;  //  230400 bits/sec for 60Mhz
    4'd12: baud_div = 12'd32;  //  460800 bits/sec for 60Mhz
    4'd13: baud_div = 12'd32;  //  460800 bits/sec for 60Mhz
    4'd14: baud_div = 12'd32;  //  460800 bits/sec for 60Mhz
    4'd15: baud_div = 12'd2;  //  460800 bits/sec for 60Mhz
    default: baud_div = 12'd2;
  endcase
end

//---------------------------------------------------------
// UART 
//---------------------------------------------------------
logic [7:0] rx_byte, tx_byte;
logic txen, tx_ing, rx_done, rx_ing, rx_error;

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
  .rx_error  // Indicates error in receiving packet.
);

// Generating a pulse to indicate whether the next byte is transmitted
logic tx_ing_n, tx_work;
`FF(~tx_ing,tx_ing_n,clk,1'b1,rstn,1'b0);
always_comb tx_work = tx_ing & tx_ing_n;

// registering received byte
logic [7:0] rx_byte_reg;
`FF(rx_byte,rx_byte_reg,clk,rx_done,rstn,8'h0);

// For ibuf update
logic ibuf_update;
`FF(rx_done,ibuf_update,clk,1'b1,rstn,1'b0);


//// Echo Buffer
//// TODO
//logic echobuf_full, echobuf_empty, echobuf_flush;
//logic echobuf_rdxfer;
//logic [7:0] echobuf_rddata;
//logic sm_idle;
//strm_intf #(.DW(8)) echobuf_wr();
//strm_intf #(.DW(8)) echobuf_rd();
//fifo #(
//.WIDTH(8),
//.DEPTH(32)
//) u_echobuf ( 
//.clk,
//.rstn,
//.wr(echobuf_wr),
//.rd(echobuf_rd),
//.full(echobuf_full),
//.empty(echobuf_empty)
//);
//always_comb echobuf_wr.valid = ibuf_update;
//always_comb echobuf_wr.data  = rx_byte_reg[7:0];
//
//always_comb echobuf_rd.ready = tx_work&&sm_idle;
//always_comb echobuf_rddata   = echobuf_rd.data;
//
//always_comb echobuf_rdxfer = echobuf_rd.ready & echobuf_rd.valid;

//---------------------------------------------------------
// Buffer for Echo back
//---------------------------------------------------------
logic echobuf_full, echobuf_empty, echobuf_flush;
logic echo_out, echo_xfer;
logic echobuf_wrxfer, echobuf_rdxfer;

logic [EBUF_SZ-1:0][EBUF_DW-1:0] echobuf;
logic [EBUF_AW-1:0] echobuf_wrcnt, echobuf_wrcnt_nxt;
logic [EBUF_AW-1:0] echobuf_rdcnt, echobuf_rdcnt_nxt;
logic [EBUF_AW-1:0] echobuf_depth, echobuf_depth_nxt;
always_comb echo_xfer = ((echobuf_depth!=0)&&(!tx_ing));
always_comb echobuf_wrxfer = ibuf_update;
always_comb echobuf_rdxfer = tx_work&&(!echobuf_empty);

always_comb echobuf_wrcnt_nxt = (echobuf_wrxfer) ? echobuf_wrcnt+EBUF_AW'(1) : echobuf_wrcnt;
always_comb echobuf_rdcnt_nxt = (echobuf_rdxfer) ? echobuf_rdcnt+EBUF_AW'(1) : echobuf_rdcnt;

always_comb echobuf_depth_nxt = (echobuf_wrxfer&&echobuf_rdxfer)

always_comb begin
if (echobuf_wrxfer&&echobuf_rdxfer) echobuf_depth_nxt = echobuf_depth;
else if (echobuf_wrxfer&&!echobuf_rdxfer) echobuf_depth_nxt = echobuf_depth+EBUF_AW'(1);
else if (!echobuf_wrxfer&&echobuf_rdxfer) echobuf_depth_nxt = echobuf_depth-EBUF_AW'(1);
else echobuf_depth_nxt = echobuf_depth;
end

// For echo back
always_ff @(posedge clk or negedge rstn) begin
  if (!rstn) echo_out <= 1'b0;
  else begin
    if (ibuf_update) echo_out <= 1'b1;
    else if (echobuf_empty) echo_out <= 1'b0;
  end
end
`FF(echobuf_wrcnt_nxt,echobuf_wrcnt,clk,1'b1,rstn,4'd0);
`FF(echobuf_rdcnt_nxt,echobuf_rdcnt,clk,1'b1,rstn,4'd0);
`FF(echobuf_depth_nxt,echobuf_depth,clk,1'b1,rstn,4'd0);
// Registering a byte to echo back
always_ff @(posedge clk or negedge rstn) begin
  if (!rstn) echobuf <= '0;
  else if (ibuf_update) echobuf[echobuf_wrcnt] <= rx_byte_reg;
end

// if echo buffer is full, halt transactions to flush all buffer data
always_comb echobuf_full  = (echobuf_depth==EBUF_AW'(EBUF_SZ-1));
always_comb echobuf_empty = (echobuf_depth==EBUF_AW'(0)); 
always_ff @(posedge clk or negedge rstn) begin
  if (!rstn) echobuf_flush <= 1'b0;
  else begin
    if (echobuf_full) echobuf_flush <= 1'b1;
    else if (echobuf_empty) echobuf_flush <= 1'b0;
  end
end

////////////////////

// Instruction Buffer (Shift Register)
logic [MAX_INST_SIZE-1:0][7:0] ibuf, ibuf_nxt;
always_comb ibuf_nxt = (ibuf_update) ? {rx_byte_reg[7:0],ibuf[MAX_INST_SIZE-1:1]} : ibuf;
`FF(ibuf_nxt,ibuf,clk,ibuf_update,rstn,'0);

// Instruction Counter
logic decode_done, sm_done;
logic [4:0] ibuf_cnt, ibuf_cnt_nxt;
always_comb ibuf_cnt_nxt = (ibuf_update) ? ibuf_cnt+1 : 
                           (sm_done) ? 5'h0 : ibuf_cnt; // TODO using other instead of sm_done?
`FF(ibuf_cnt_nxt,ibuf_cnt,clk,1'b1,rstn,5'h0);

// End of instruction when LF is received
// TODO This part is really sensitive on FPGA!!! Don't change this part
logic line_feed_n, line_feed, line_feed_nxt;
logic end_of_inst, end_of_inst_nxt;
always_comb line_feed_nxt = (rx_byte_reg==ASCII_LF) ? 1'b1 : 1'b0;
`FF(line_feed_nxt,line_feed,clk,1'b1,rstn,'0);
always_comb end_of_inst = line_feed;

//---------------------------------------------------------
// DECODE (combinational logic)
// 1. WRITE
// | 0 |1|2| 3 |4 - 11|12|13|14|15- 22|23|24|
// |W/w| |0|X/x|WRADDR|  | 0| x|WRDATA|CR|LF|
// 2. READ
// | 0 |1|2| 3 |4 - 11|12|13|
// |R/r| |0|X/x|RDADDR|CR|LF|
//---------------------------------------------------------
// Registering ibuf and ibuf_cnt for decode
logic [MAX_INST_SIZE-1:0][7:0] ibuf_dec;
logic [4:0] ibuf_cnt_dec;
`FF(ibuf>>(8*(MAX_INST_SIZE-ibuf_cnt)),ibuf_dec,clk,end_of_inst,rstn,'0);
`FF(ibuf_cnt,ibuf_cnt_dec,clk,end_of_inst,rstn,5'h2);

// decode takes 1 cycle
`FF(end_of_inst,decode_done,clk,1'b1,rstn,1'b0);

// Decode Address, Data, Write Enable, Error
logic [31:0] addr, addr_nxt;
logic [31:0] wrdata, wrdata_nxt;
logic we, we_nxt;
logic wr_dec_error, wr_dec_error_nxt;
logic rd_dec_error, rd_dec_error_nxt;
logic decode_error;

// Bytes of instruction
logic wr_num_bytes_error, rd_num_bytes_error;
always_comb wr_num_bytes_error = (ibuf_cnt_dec==MAX_INST_SIZE) ? 1'b0 : 1'b1;
always_comb rd_num_bytes_error = ((ibuf_cnt_dec>=14)&&(ibuf_cnt_dec<=MAX_INST_SIZE)) ? 1'b0 : 1'b1;

// Line Breaks (CRLF/LF) for [23,24] or [12,13]
logic linebreak_err;
always_comb linebreak_err = ((ibuf_dec[ibuf_cnt_dec-2]==ASCII_LF)||
                            ({ibuf_dec[ibuf_cnt_dec-2],ibuf_dec[ibuf_cnt_dec-1]}=={ASCII_CR,ASCII_LF})) ? 1'b0 : 1'b1;

// W/w or R/r
logic rw_err;
always_comb rw_err = ((ibuf_dec[0]==ASCII_W)||(ibuf_dec[0]==ASCII_w)||
                      (ibuf_dec[0]==ASCII_R)||(ibuf_dec[0]==ASCII_r)) ? 1'b0 : 1'b1;

// Separator ( 0x)
logic sep_err0, sep_err1;
always_comb sep_err0 = ((ibuf_dec[1] ==ASCII_SPACE)&&(ibuf_dec[2] ==ASCII_0)&&
                       ((ibuf_dec[3] ==ASCII_X)||(ibuf_dec[3] ==ASCII_x))) ? 1'b0 : 1'b1;
always_comb sep_err1 = ((ibuf_dec[12]==ASCII_SPACE)&&(ibuf_dec[13]==ASCII_0)&&
                       ((ibuf_dec[14]==ASCII_X)||(ibuf_dec[14]==ASCII_x))) ? 1'b0 : 1'b1;
                        
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
addr_err_7 = ascii_to_num_error(ibuf_dec[4]);
addr_err_6 = ascii_to_num_error(ibuf_dec[5]);
addr_err_5 = ascii_to_num_error(ibuf_dec[6]);
addr_err_4 = ascii_to_num_error(ibuf_dec[7]);
addr_err_3 = ascii_to_num_error(ibuf_dec[8]);
addr_err_2 = ascii_to_num_error(ibuf_dec[9]);
addr_err_1 = ascii_to_num_error(ibuf_dec[10]);
addr_err_0 = ascii_to_num_error(ibuf_dec[11]);
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
wrdata_err_7 = ascii_to_num_error(ibuf_dec[15]);
wrdata_err_6 = ascii_to_num_error(ibuf_dec[16]);
wrdata_err_5 = ascii_to_num_error(ibuf_dec[17]);
wrdata_err_4 = ascii_to_num_error(ibuf_dec[18]);
wrdata_err_3 = ascii_to_num_error(ibuf_dec[19]);
wrdata_err_2 = ascii_to_num_error(ibuf_dec[20]);
wrdata_err_1 = ascii_to_num_error(ibuf_dec[21]);
wrdata_err_0 = ascii_to_num_error(ibuf_dec[22]);
end


// Next values after decoded
always_comb we_nxt = ((ibuf_dec[0]==ASCII_W)||(ibuf_dec[0]==ASCII_w)) ? 1'b1 : 1'b0;
always_comb addr_nxt = {addr_7,addr_6,addr_5,addr_4,addr_3,addr_2,addr_1,addr_0}; 
always_comb wrdata_nxt = {wrdata_7,wrdata_6,wrdata_5,wrdata_4,wrdata_3,wrdata_2,wrdata_1,wrdata_0}; 
always_comb wr_dec_error_nxt = linebreak_err|   rw_err   |  sep_err0  |  sep_err1  |
                                addr_err_7  | addr_err_6 | addr_err_5 | addr_err_4 |
                                addr_err_3  | addr_err_2 | addr_err_1 | addr_err_0 |
                               wrdata_err_7 |wrdata_err_6|wrdata_err_5|wrdata_err_4|
                               wrdata_err_3 |wrdata_err_2|wrdata_err_1|wrdata_err_0;

always_comb rd_dec_error_nxt = linebreak_err|   rw_err   |  sep_err0  |
                                addr_err_7  | addr_err_6 | addr_err_5 | addr_err_4 |
                                addr_err_3  | addr_err_2 | addr_err_1 | addr_err_0 ;

always_comb decode_error = (we) ? linebreak_err|wr_num_bytes_error|wr_dec_error : 
                                  linebreak_err|rd_num_bytes_error|rd_dec_error;

// Registering Address, Data, Write Enable, Error when decode is done
`FF(addr_nxt,addr,clk,decode_done,rstn,32'h0);
`FF(wrdata_nxt,wrdata,clk,decode_done,rstn,32'h0);
`FF(we_nxt,we,clk,decode_done,rstn,1'b0);
`FF(wr_dec_error_nxt,wr_dec_error,clk,decode_done,rstn,1'b0);
`FF(rd_dec_error_nxt,rd_dec_error,clk,decode_done,rstn,1'b0);

//---------------------------------------------------------------------------------
// STATE MACHINE FOR 5-TYPE TRANSACTIONS
// TYPE 1 : Decode Error                (IDLE=>DECODE_ERROR=>DONE)
// Type 2 : HMSEL                       (IDLE=>HMSEL_UPDATE=>DONE)
// TYPE 3 : AHB Write Transaction       (IDLE=>AHB_ADDR=>AHB_WRITE=>DONE)
// TYPE 4 : AHB Read Transaction        (IDLE=>AHB_ADDR=>AHB_READ=>AHB_SEND=>DONE)
// TYPE 5 : AHB Transaction Error       (IDLE=>AHB_ADDR=>AHB_READ/AHB_WRITE=>AHB_ERROR=>DONE)
//---------------------------------------------------------------------------------

/////////////////////////////////////
// State Machine and Control Signals
/////////////////////////////////////
logic sm_start, sm_start_nxt;
logic decode_done_n;
always_comb sm_start_nxt = decode_done&&decode_done_n;
`FF(~decode_done,decode_done_n,clk,1'b1,rstn,1'b0);
`FF(sm_start_nxt,sm_start,clk,1'b1,rstn,1'b0);

// Control signals for state machine
logic rd_done, wr_done, send_done, hmsel_done, decerr_done, ahberr_done;
logic bus_error;
logic c_decode_error, c_hmsel_update, c_ahb_xfer;
always_comb c_decode_error = (sm_start&&decode_error);
always_comb c_hmsel_update = (sm_start&&(!decode_error)&&(addr==32'h10000000));
always_comb c_ahb_xfer     = (sm_start&&(!decode_error)&&(hmsel==2'b00));

// State Machine
enum logic [3:0] 
    {IDLE      = 4'b0000, DECODE_ERROR = 4'b0001, HMSEL_UPDATE = 4'b0010,
     AHB_ERROR = 4'b0011, AHB_ADDR     = 4'b0100, AHB_WRITE    = 4'b0101,
     AHB_READ  = 4'b0110, AHB_SEND     = 4'b0111, DONE         = 4'b1000}
    state, state_nxt;                
`FF(state_nxt,state,clk,1'b1,rstn,IDLE);

always_comb begin
  case(state)
    IDLE:
      state_nxt = (c_decode_error) ? DECODE_ERROR :
                  (c_hmsel_update) ? HMSEL_UPDATE : 
                  (c_ahb_xfer) ? AHB_ADDR : IDLE;
    DECODE_ERROR: 
      state_nxt = (decerr_done) ? DONE : DECODE_ERROR;
    HMSEL_UPDATE: 
      state_nxt = (hmsel_done) ? DONE : HMSEL_UPDATE;
    AHB_ADDR: 
      state_nxt = (we) ? AHB_WRITE : AHB_READ;
    AHB_READ: 
      state_nxt = (bus_error) ? AHB_ERROR :
                  (rd_done)   ? AHB_SEND : AHB_READ;
    AHB_WRITE: 
      state_nxt = (bus_error) ? AHB_ERROR :
                  (wr_done)   ? DONE : AHB_WRITE;
    AHB_SEND: 
      state_nxt = (send_done) ? DONE : AHB_SEND;
    AHB_ERROR: 
      state_nxt = (ahberr_done) ? DONE : AHB_ERROR;
    DONE: 
      state_nxt = IDLE;
    default: 
      state_nxt = IDLE;
  endcase 
end

// TODO
always_comb sm_done = (state==DONE);

//////////////////////////
// TYPE 1 : Decode Error 
////////////////////////// 
// Store Error Code into decerrbuf
// eg. "DECODE_ERROR: 23"
logic [15:0] error_code;
logic [17:0][7:0] decerrbuf, decerrbuf_nxt;
`FF(decerrbuf_nxt,decerrbuf,clk,(state==DECODE_ERROR),rstn,'0);
always_comb decerrbuf_nxt[11:0]  = DECERR_STR;  // ERROR
always_comb decerrbuf_nxt[12]    = ASCII_COLON; // :
always_comb decerrbuf_nxt[13]    = ASCII_SPACE; // (space)
always_comb decerrbuf_nxt[15:14] = error_code;  // error_code
always_comb decerrbuf_nxt[16]    = ASCII_CR;    // CR
always_comb decerrbuf_nxt[17]    = ASCII_LF;    // LF                   

// Error Code
always_comb begin
// Write Decode Error
if(we) begin 
error_code = (wr_num_bytes_error) ? {ASCII_0,ASCII_1} : // Write Inst Size
             (rw_err)             ? {ASCII_1,ASCII_1} : // W/w 
             (sep_err0)           ? {ASCII_0,ASCII_2} : // 1st _0X
             (sep_err1)           ? {ASCII_1,ASCII_2} : // 2nd _0X
             (linebreak_err)      ? {ASCII_2,ASCII_2} : // CRLF/LF
             (addr_err_0)         ? {ASCII_0,ASCII_3} : // ADDR_0 
             (addr_err_1)         ? {ASCII_1,ASCII_3} : // ADDR_1
             (addr_err_2)         ? {ASCII_2,ASCII_3} : // ADDR_2
             (addr_err_3)         ? {ASCII_3,ASCII_3} : // ADDR_3
             (addr_err_4)         ? {ASCII_4,ASCII_3} : // ADDR_4
             (addr_err_5)         ? {ASCII_5,ASCII_3} : // ADDR_5
             (addr_err_6)         ? {ASCII_6,ASCII_3} : // ADDR_6
             (addr_err_7)         ? {ASCII_7,ASCII_3} : // ADDR_7
             (wrdata_err_0)       ? {ASCII_0,ASCII_4} : // WRDATA_0
             (wrdata_err_1)       ? {ASCII_1,ASCII_4} : // WRDATA_1
             (wrdata_err_2)       ? {ASCII_2,ASCII_4} : // WRDATA_2
             (wrdata_err_3)       ? {ASCII_3,ASCII_4} : // WRDATA_3
             (wrdata_err_4)       ? {ASCII_4,ASCII_4} : // WRDATA_4
             (wrdata_err_5)       ? {ASCII_5,ASCII_4} : // WRDATA_5
             (wrdata_err_6)       ? {ASCII_6,ASCII_4} : // WRDATA_6
             (wrdata_err_7)       ? {ASCII_7,ASCII_4} : // WRDATA_7
             16'h0;
// Read Decode Error             
end else begin 
error_code = (rd_num_bytes_error) ? {ASCII_0,ASCII_1} : // Read Inst Size
             (rw_err)             ? {ASCII_1,ASCII_1} : // R/r
             (sep_err0)           ? {ASCII_0,ASCII_2} : // 1st _0X
             (linebreak_err)      ? {ASCII_2,ASCII_2} : // CRLF/LF
             (addr_err_0)         ? {ASCII_0,ASCII_3} : // ADDR_0 
             (addr_err_1)         ? {ASCII_1,ASCII_3} : // ADDR_1
             (addr_err_2)         ? {ASCII_2,ASCII_3} : // ADDR_2
             (addr_err_3)         ? {ASCII_3,ASCII_3} : // ADDR_3
             (addr_err_4)         ? {ASCII_4,ASCII_3} : // ADDR_4
             (addr_err_5)         ? {ASCII_5,ASCII_3} : // ADDR_5
             (addr_err_6)         ? {ASCII_6,ASCII_3} : // ADDR_6
             (addr_err_7)         ? {ASCII_7,ASCII_3} : // ADDR_7
             16'h0;
end
end

// decerrbuf transaction
logic decerrbuf_done, decerrbuf_done_nxt;
logic decerrbuf_out,  decerrbuf_out_nxt;
logic [4:0] decerrbuf_cnt, decerrbuf_cnt_nxt;
always_comb decerrbuf_out_nxt  = ((state==DECODE_ERROR)&&(!echo_out));
always_comb decerrbuf_done_nxt = (decerrbuf_cnt==5'd18) ? 1'b1 : 1'b0;
always_comb decerrbuf_cnt_nxt  = (!decerrbuf_out) ? 5'h0 :
                              (tx_work&&(!decerrbuf_done)) ? decerrbuf_cnt+1 :
                              (decerrbuf_done) ? 5'h0 : decerrbuf_cnt;
`FF(decerrbuf_out_nxt,decerrbuf_out,clk,1'b1,rstn,1'b0);
`FF(decerrbuf_done_nxt,decerrbuf_done,clk,1'b1,rstn,1'b0);
`FF(decerrbuf_cnt_nxt,decerrbuf_cnt,clk,1'b1,rstn,5'h0);

// done signal
always_comb decerr_done = (state==DECODE_ERROR) ? decerrbuf_done : 1'b0;

/////////////////////////////////////
// TYPE 2 : HMSEL
/////////////////////////////////////
// WRITE 
logic [1:0] hmsel_nxt;
always_comb hmsel_nxt = (we) ? wrdata[1:0] : hmsel;
`FF(hmsel_nxt,hmsel,clk,(state==HMSEL_UPDATE),rstn,2'b00);

// READ
// Store hmsel into hmselbuf
// eg. "HMSEL: 1"
logic [7:0] hmsel_value;
logic [9:0][7:0] hmselbuf, hmselbuf_nxt;
`FF(hmselbuf_nxt,hmselbuf,clk,(state==HMSEL_UPDATE),rstn,'0);
always_comb hmselbuf_nxt[4:0] = HMSEL_STR;   // HMSEL
always_comb hmselbuf_nxt[5]   = ASCII_COLON; // :
always_comb hmselbuf_nxt[6]   = ASCII_SPACE; // (space)
always_comb hmselbuf_nxt[7]   = hmsel_value; // HMSEL value
always_comb hmselbuf_nxt[8]   = ASCII_CR;    // CR
always_comb hmselbuf_nxt[9]   = ASCII_LF;    // LF                 

// current hmsel value
always_comb hmsel_value = (hmsel==2'b00) ? ASCII_0 :
                          (hmsel==2'b01) ? ASCII_1 :
                          (hmsel==2'b10) ? ASCII_2 : ASCII_3;;

// hmselbuf transaction
logic hmselbuf_done, hmselbuf_done_nxt;
logic hmselbuf_out,  hmselbuf_out_nxt;
logic [3:0] hmselbuf_cnt, hmselbuf_cnt_nxt;
always_comb hmselbuf_out_nxt = ((state==HMSEL_UPDATE)&&(!we)&&(!echo_out));
always_comb hmselbuf_done_nxt = (hmselbuf_cnt==4'd10) ? 1'b1 : 1'b0;
always_comb hmselbuf_cnt_nxt = (!hmselbuf_out) ? 4'h0 :
                               (tx_work&&(!hmselbuf_done)) ? hmselbuf_cnt+1 :
                               (hmselbuf_done) ? 4'h0 : hmselbuf_cnt;
`FF(hmselbuf_out_nxt,hmselbuf_out,clk,1'b1,rstn,1'b0);
`FF(hmselbuf_done_nxt,hmselbuf_done,clk,1'b1,rstn,1'b0);
`FF(hmselbuf_cnt_nxt,hmselbuf_cnt,clk,1'b1,rstn,4'h0);

// done signal
always_comb hmsel_done = (state!=HMSEL_UPDATE) ? 1'b0 :
                         (we) ? 1'b1 : hmselbuf_done;

////////////////////////////////////////////////////
// AHB TRANSACTIONS (WRITE, READ, ERROR, SEND)
////////////////////////////////////////////////////

/* STATE = AHB_ADDR (AHB Address Phase) */
always_comb haddr  = (state==AHB_ADDR)  ? addr   : 32'h0;
always_comb hsize  = (state==AHB_ADDR)  ? 2'b10  : 2'b0;
always_comb hwrite = (state==AHB_ADDR)  ? we     : 1'b0;
always_comb htrans = (state==AHB_ADDR)  ? 3'b010 : 3'b0;


/* STATE = AHB_WRITE (AHB Data Phase) */
logic wr_error;
always_comb hwdata   =  (state==AHB_WRITE) ? wrdata : 32'h0;
always_comb wr_done  = ((state==AHB_WRITE)&&hready&&(!hresp));
always_comb wr_error = ((state==AHB_WRITE)&&hresp);

/* STATE = AHB_READ (AHB Data Phase) */
logic rd_error;
logic [31:0] rddata;
always_comb rddata   = ((state==AHB_READ)&&hready) ? hrdata[31:0] : 32'h0; // Transaction when hready is 1
always_comb rd_done  = ((state==AHB_READ )&&hready&&(!hresp));
always_comb rd_error = ((state==AHB_READ)&&hresp);

/* STATE = AHB_SEND (After AHB transaction) */
// Store hrdata into hrdatabuf
// eg. "HRDATA: 0x12341234"
logic [19:0][7:0] hrdatabuf, hrdatabuf_nxt;
`FF(hrdatabuf_nxt,hrdatabuf,clk,rd_done,rstn,'0);
always_comb hrdatabuf_nxt[5:0] = HRDATA_STR;  // HRDATA
always_comb hrdatabuf_nxt[6]   = ASCII_COLON; // :
always_comb hrdatabuf_nxt[7]   = ASCII_SPACE; // (space)
always_comb hrdatabuf_nxt[8]   = ASCII_0;     // 0 
always_comb hrdatabuf_nxt[9]   = ASCII_x;     // x 
always_comb hrdatabuf_nxt[10]  = num_to_ascii(rddata[31:28]);
always_comb hrdatabuf_nxt[11]  = num_to_ascii(rddata[27:24]);
always_comb hrdatabuf_nxt[12]  = num_to_ascii(rddata[23:20]);
always_comb hrdatabuf_nxt[13]  = num_to_ascii(rddata[19:16]);
always_comb hrdatabuf_nxt[14]  = num_to_ascii(rddata[15:12]);
always_comb hrdatabuf_nxt[15]  = num_to_ascii(rddata[11: 8]);
always_comb hrdatabuf_nxt[16]  = num_to_ascii(rddata[7 : 4]);
always_comb hrdatabuf_nxt[17]  = num_to_ascii(rddata[3 : 0]);
always_comb hrdatabuf_nxt[18]  = ASCII_CR;    // CR
always_comb hrdatabuf_nxt[19]  = ASCII_LF;    // LF

// hrdatabuf transaction
logic hrdatabuf_done, hrdatabuf_done_nxt;
logic hrdatabuf_out,  hrdatabuf_out_nxt;
logic [4:0] hrdatabuf_cnt, hrdatabuf_cnt_nxt;
always_comb hrdatabuf_out_nxt   = ((state==AHB_SEND)&&(!echo_out));
always_comb hrdatabuf_done_nxt = (hrdatabuf_cnt==5'd20) ? 1'b1 : 1'b0;
always_comb hrdatabuf_cnt_nxt  = (!hrdatabuf_out) ? 5'h0 :
                             (tx_work&&(!hrdatabuf_done)) ? hrdatabuf_cnt+1 :
                             (hrdatabuf_done) ? 5'h0 : hrdatabuf_cnt;
`FF(hrdatabuf_out_nxt,hrdatabuf_out,clk,1'b1,rstn,1'b0);
`FF(hrdatabuf_done_nxt,hrdatabuf_done,clk,1'b1,rstn,1'b0);
`FF(hrdatabuf_cnt_nxt,hrdatabuf_cnt,clk,1'b1,rstn,5'h0);

// Done signal
always_comb send_done = (state==AHB_SEND) ? hrdatabuf_done : 1'b0;

/* STATE = AHB_ERROR (when hresp=1 in AHB Data Phase) */
// Detect Bus transaction error
always_comb bus_error = (wr_error||rd_error);

// Store AHB Error Message into ahberrbuf
// eg. "AHB_ERROR: HADDR=0x18000000"
logic [28:0][7:0] ahberrbuf, ahberrbuf_nxt;
`FF(ahberrbuf_nxt,ahberrbuf,clk,(state==AHB_ERROR),rstn,'0);
always_comb ahberrbuf_nxt[8:0]    = AHBERR_STR;     // AHB_ERROR
always_comb ahberrbuf_nxt[9]      = ASCII_COLON;    // :
always_comb ahberrbuf_nxt[10]     = ASCII_SPACE;    // (space)
always_comb ahberrbuf_nxt[15:11]  = HADDR_STR;      // HADDR
always_comb ahberrbuf_nxt[16]     = ASCII_EQUAL;    // = 
always_comb ahberrbuf_nxt[17]     = ASCII_0;        // 0 
always_comb ahberrbuf_nxt[18]     = ASCII_x;        // x 
always_comb ahberrbuf_nxt[26:19]  = ibuf_dec[11:4]; // Address
always_comb ahberrbuf_nxt[27]     = ASCII_CR;       // CR
always_comb ahberrbuf_nxt[28]     = ASCII_LF;       // LF                  


// ahberrbuf transaction
logic ahberrbuf_done, ahberrbuf_done_nxt;
logic ahberrbuf_out,  ahberrbuf_out_nxt;
logic [4:0] ahberrbuf_cnt, ahberrbuf_cnt_nxt;
always_comb ahberrbuf_out_nxt  = ((state==AHB_ERROR)&&(!echo_out));
always_comb ahberrbuf_done_nxt = (ahberrbuf_cnt==5'd29) ? 1'b1 : 1'b0;
always_comb ahberrbuf_cnt_nxt  = (!ahberrbuf_out) ? 5'h0 :
                                 (tx_work&&(!ahberrbuf_done)) ? ahberrbuf_cnt+1 :
                                 (ahberrbuf_done) ? 5'h0 : ahberrbuf_cnt;
`FF(ahberrbuf_out_nxt,ahberrbuf_out,clk,1'b1,rstn,1'b0);
`FF(ahberrbuf_done_nxt,ahberrbuf_done,clk,1'b1,rstn,1'b0);
`FF(ahberrbuf_cnt_nxt,ahberrbuf_cnt,clk,1'b1,rstn,5'h0);

// Done signal
always_comb ahberr_done = (state==AHB_ERROR) ? ahberrbuf_done : 1'b0;

//---------------------------------------------------------
// UART TX signals 
//---------------------------------------------------------
logic echobuf_xfer, hmselbuf_xfer, decerrbuf_xfer, hrdatabuf_xfer, ahberrbuf_xfer;
always_comb begin
echobuf_xfer   = echo_xfer;
hmselbuf_xfer  = hmselbuf_out &&(!hmselbuf_done);
decerrbuf_xfer = decerrbuf_out&&(!decerrbuf_done);
hrdatabuf_xfer = hrdatabuf_out&&(!hrdatabuf_done);
ahberrbuf_xfer = ahberrbuf_out&&(!ahberrbuf_done);
end
// TX enable
logic txen_nxt;
`FF(txen_nxt,txen,clk,1'b1,rstn,'0);
always_comb txen_nxt = (cts) ? 1'b0 :
                       (hmselbuf_xfer)  ? 1'b1 : // hmsel out
                       (decerrbuf_xfer) ? 1'b1 : // Decode Error out
                       (hrdatabuf_xfer) ? 1'b1 : // hrdata out
                       (ahberrbuf_xfer) ? 1'b1 : // AHB Error out
                       (echobuf_xfer)   ? 1'b1 : 1'b0; // Echo back

// TX Byte to send
logic [7:0] tx_byte_nxt;
`FF(tx_byte_nxt,tx_byte,clk,1'b1,rstn,'0);
always_comb tx_byte_nxt = (cts) ? 8'h0 :
                       (hmselbuf_xfer)  ? hmselbuf[hmselbuf_cnt]   : // hmsel out
                       (decerrbuf_xfer) ? decerrbuf[decerrbuf_cnt] : // Decode Error out
                       (hrdatabuf_xfer) ? hrdatabuf[hrdatabuf_cnt] : // hrdata out
                       (ahberrbuf_xfer) ? ahberrbuf[ahberrbuf_cnt] : // AHB Error out
                       (echobuf_xfer)   ? echobuf[echobuf_rdcnt] : 8'h0; // Echo back

//---------------------------------------------------------
// rts handshake 
//---------------------------------------------------------
always_comb rts = ((state==HMSEL_UPDATE)||
                   (state==DECODE_ERROR)||
                   (state==AHB_READ)    ||
                   (state==AHB_SEND)    ||
                   (state==AHB_ERROR)   ||
                   (echobuf_flush));

//// Send back to PC
//// Echo Buffer
//logic [63:0][7:0] ebuf, ebuf_nxt;
//logic [5:0] tx_cnt, tx_cnt_nxt;
//`FF(ebuf_nxt,ebuf,clk,rx_done,rstn,'0);
//`FF(tx_cnt_nxt,tx_cnt,clk,1'b1,rstn,6'h0);
//always_comb tx_cnt_nxt = (rx_done) ? tx_cnt+6'b1 :
//                         (!hrdatabuf_out&&tx_work&&(tx_cnt!=6'h0)) ? (tx_cnt-6'b1)
//                         : tx_cnt; 
//always_comb ebuf_nxt = {ebuf[MAX_INST_SIZE-2:0],rx_byte[7:0]};

endmodule
