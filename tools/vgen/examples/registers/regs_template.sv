// Paul Whatmough Nov 2015


// VGEN: HEADER


module 

// VGEN: MODULE NAME

(

// clocks and resets
input  logic     clk,           
input  logic     rstn,

// Synchronous register interface
reg_intf.sink regbus,


// VGEN: INPUTS TO REGS


// VGEN: OUTPUTS FROM REGS


);


//------------------------------------------------------------------------------
// Regsiter write
//------------------------------------------------------------------------------

// VGEN: REG WRITE


//------------------------------------------------------------------------------
// Regsiter read
//------------------------------------------------------------------------------


logic [31:0] rdata_o;

always @*
begin
  if (regbus.read_en)
  begin
    rdata_o[31:0] = 32'h00000000;

    // VGEN: REG READ

  end
  else 
  begin
    rdata_o[31:0] = {32'h00000000};
  end	
end

assign regbus.rdata[31:0] = rdata_o[31:0];


//------------------------------------------------------------------------------
// 
//------------------------------------------------------------------------------




endmodule
