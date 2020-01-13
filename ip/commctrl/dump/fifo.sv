// fifo.sv - generic parameterizable synchronous fifo
// HKL 10 2015  

`include "rtl_macros.svh"

module fifo
#(
parameter WIDTH=16, DEPTH=8 
)(
    input logic clk, rstn,
    strm_intf.sink wr,
    strm_intf.source rd,
    output logic full,
    output logic empty
);

// TODO better to be replace with SRAM logics later
logic [WIDTH-1:0] mem [DEPTH-1:0];
//logic full, empty;

//---------------------------------------------------------
// Write
//---------------------------------------------------------
// handshake
logic wr_xfer;
always_comb wr_xfer = (wr.valid && wr.ready);
always_comb wr.ready = ~full;

// pointer
logic [$clog2(DEPTH)-1:0] wr_ptr, wr_ptr_nxt;
`FF(wr_ptr_nxt,wr_ptr,clk,'1,rstn,'0);
always_comb wr_ptr_nxt = (wr_xfer) ? 
                         (wr_ptr == DEPTH-1) ? '0 : wr_ptr+1
                         : wr_ptr;

// write data into memory
logic [WIDTH-1:0] write_data;
`FF(wr.data,mem[wr_ptr],clk,wr_xfer,rstn,'0);

//---------------------------------------------------------
// Read
//---------------------------------------------------------
// handshake
logic rd_xfer;
`FF((~empty),rd.valid,clk,'1,rstn,'0);
always_comb rd_xfer = (rd.ready && rd.valid);

// pointer
logic [$clog2(DEPTH)-1:0] rd_ptr, rd_ptr_nxt;
`FF(rd_ptr_nxt,rd_ptr,clk,'1,rstn,'0);
always_comb rd_ptr_nxt = (rd_xfer)? 
                         (rd_ptr == DEPTH-1) ? '0 : rd_ptr+1
                         : rd_ptr;

// Read out data from memory
always_comb rd.data = mem[rd_ptr];

//---------------------------------------------------------
// Depth Counter
//---------------------------------------------------------
logic [$clog2(DEPTH):0] depth_cnt, depth_cnt_nxt;
`FF(depth_cnt_nxt,depth_cnt,clk,'1,rstn,'0);
always_comb begin
    if (wr_xfer && rd_xfer) begin
        depth_cnt_nxt = depth_cnt;
    end else if (wr_xfer && !rd_xfer) begin
        depth_cnt_nxt = depth_cnt+1;
    end else if (!wr_xfer && rd_xfer) begin
        depth_cnt_nxt = depth_cnt-1;
    end else begin
        depth_cnt_nxt = depth_cnt;
    end
end


//---------------------------------------------------------
// Check Status
//---------------------------------------------------------
always_comb empty = (depth_cnt == 0);
always_comb full = (depth_cnt == DEPTH);

endmodule
