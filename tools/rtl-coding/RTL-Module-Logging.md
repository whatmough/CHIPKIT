# RTL Module Logging


Opening waveforms should be a last resort during RTL development
Simulation is slower
Opening and working with a GUI is slow and clumsy
Printing signals from a block-level test bench is quite clumsy
Logging directly from an RTL module is a better approach
Wrap non-synthesizable debug code in ‘ifndef SYNTHESIS
Use reset signal to mask junk during reset
Can generate a lot of clutter in the simulation transcript
Even better is to log to file with module name
You know where to look for module specific debug data
Easy to parse in python to check against a model (especially datapath)


```systemverilog
module my_module (
  // …signals…
);

// Module body


// Logging code

`LOGF_INIT        // This macro opens the log
`LOGF(clk, rstn, enable, format_expr)
`LOGF(clk, rstn,
  iss.valid,
  (”| %s | %s |”,iss.op,iss.data)
);


endmodule  // my_module
```


```systemverilog
// Macro prototype
`LOGF(clk, rstn, enable, format_expr)
```
