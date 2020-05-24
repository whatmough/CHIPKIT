// RTL.svh - Useful macros for RTL coding 
// PNW 05 2015


`ifndef RTL_MACROS_SVH
`define RTL_MACROS_SVH


// NOTES: 
//
// - Please do check out the CHIPKIT documentation for more info.
//
// - All of these macros should be synthesis safe, no need to wrap them.
//
// - For bigger designs, a framework such as UVM may be preferred for validation purposes.
//



// TODO: 
//
// There are a lot of potential optional features that would be useful here.
// Unfortunately, synthesis tools don't currently support default arguments in macros. 
// Although VCS does.  I suspect this will be resolved in the passing of time.
//
// I still can't figure out a way to implement `LOGF() without also requiring `LOGF_INIT in a single macro:
// - Defines are global, so it's not possible to detect if it's been called already in the current scope.
// - Can't check an integer/string etc without throwing error if it doesn't exist
// - Can't make a define specific to the module by including the name due to "." not allowed in define
// For now, to use `LOGF(), you first need to define LOGF_INIT().
//



// -----------------------------------------------------------------------------
// `FF()
// -----------------------------------------------------------------------------
// Macro to enforce the use of asynchronous reset positive-edge flip-flops.
//
// TODO 
// Possible to add some (optional) debug checks here:
// - Stop on X/Z
// - Check d and q have the same number of $bits

`define FF(__d_nxt, __q_reg, __clk, __en, __rstn, __rst_val)  \
    /* FF with async reset */                                 \
      always_ff @(posedge __clk, negedge __rstn) begin        \
        if (!__rstn) __q_reg <= (__rst_val);                  \
        else if(__en) __q_reg <= (__d_nxt);                   \
      end                                                     \


// -----------------------------------------------------------------------------
// `ASSERT_CLK()
// -----------------------------------------------------------------------------
// A simple, easy to use concurrent (clocked) assertion.

`define ASSERT_CLK(__clk,__rst_n,__arg) \
	assert property (@(posedge __clk) disable iff (!__rst_n) (__arg)) \
    else $error("%t: %m",$time);


//---------------------------------------------------------
// `ASSERT_INIT()
//---------------------------------------------------------
// A simple, easy to use immediate (un-clocked) assertion.

`define ASSERT_INIT(__arg) \
	initial assert (__arg) \
    else $error("%t: %m",$time);


// -----------------------------------------------------------------------------
// `LOG()
// -----------------------------------------------------------------------------
// Helps debugging by conditionally printing data to the simulator transcript.
//
// Prints __format_expr to the transcript at the __clk edge when __en is true and __rstn is not asserted (i.e. high).
// Optionally prints a hello message at time 0.  Active this feature by editing the "initial if(0)" line below.
// The __format_expr must be wrapped in parens - ().

`define LOG(__clk, __rstn, __en, __format_expr) \
  `ifndef SYNTHESIS \
    /* Optionally generate a hello message for each log statement with some details */ \
    initial if(0) $display("[%0t] LOG:STARTING:%m:%s:%0d", $stime, `__FILE__, `__LINE__);*/ \
    /* Signal logging statement */ \
    always @(posedge __clk, negedge __rstn) if((__rstn) & (__en)) \
    $display("[%0t] %m: %0s", $stime, $sformatf __format_expr); \
  `endif 


// -----------------------------------------------------------------------------
// `LOGF_INIT
// -----------------------------------------------------------------------------
// Opens a logging file for a module.
//
// Opens a log file for the module.  Use this in all modules that use LOGF.

`define LOGF_INIT \
  `ifndef SYNTHESIS \
    /* Open a log file named after the current module hierarchical path */ \
    integer __logf_file; \
    initial begin \
      __logf_file = $fopen($sformatf("%m.log"),"w"); \
      if(1) $fdisplay(__logf_file,"[%0t] LOG:STARTING:%m:%s:%0d", $stime, `__FILE__, `__LINE__); \
    end \
    final begin \
      if(1) $fdisplay(__logf_file,"[%0t] LOG:CLOSING:%m:%s:%0d", $stime, `__FILE__, `__LINE__); \
      $fclose(__logf_file); \
    end \
  `endif


// -----------------------------------------------------------------------------
// `LOGF()
// -----------------------------------------------------------------------------
// Logs a message to the module log file.
//
// Must also define `LOGF_INIT in the same module.

`define LOGF(__clk, __rstn, __en, __format_expr) \
  `ifndef SYNTHESIS \
    /* Generate a hello message for each log statement with some details */ \
    /* initial $display("[%0t] LOG:STARTING:%m:%s:%d", $stime, `__FILE__, `__LINE__); */ \
    /* Generate the signal logging statement */ \
    always @(posedge __clk, negedge __rstn) if((__rstn) & (__en)) \
      $fdisplay(__logf_file,"[%0t] %0s", $stime, $sformatf __format_expr); \
  `endif 


`endif
