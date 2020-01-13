# CHIPKIT RTL Coding Guidelines

TODO 
add intro on importance of coding guidelines and explain not much currently around
add examples of common gotchas, especially with Verilog (and how SV helps)
add all the references on this stuff


We’ve had very fast results with HLS, potentially great for exploration
For higher-performance designs, sometimes it’s nice to have more control over pipelining
We’ve used SystemVerilog extensively
Native support in commercial EDA tools
Much more compile time checking
No translation step
We’ve used a strict subset of SV for synthesizable code with good results
Easy to learn
Removes a large number of common bug classes
Great PPA results
Great correlation through front-end and back-end
One drawback is less support for some features in open source simulators


## Combinational Logic

Separate combinational logic and sequential logic (flops)
Extra compile time checking, easier pipeline adjustments, code readability
Use logic type exclusively
No need for the confusing wire/reg types
Except for netlists – use wire and use `default_nettype none to catch undeclared nets that are usually typos
Use lower-case signal names with underscores (_)
Except for top-level module port signals – all caps by convention
Use always_comb keyword for all combinational logic
Compile-time checking that latches or flops are not inferred (enforces above)
Be careful with multiplexers
Be careful with signed numbers in SV

```systemverilog
module my_module (
  // …signals…
);

// Always split out logic and flops!

logic a, b, c;            // Use logic type only
logic d, e, f;            // Lower-case signals

always_comb a = b & c;    // Single-line logic

always_comb begin         // multi-line logic
  d = e & f;
  // more code
end

endmodule  // my_module
```

```systemverilog
`default_nettype none

module my_netlist (
  // …signals…
);

// No logic in netlists!

wire sig_a, sig_b;    // Use wire type only

My_module0 u0 (
  .clk,
  .rstn,
  .sig_a,
  .sig_b
);

// more code

endmodule  // my_netlist

`default_nettype wire
```


## Sequential Logic

Separate combinational logic and sequential logic (flops)
Extra compile time checking, easier pipeline adjustments, code readability
Use the always_ff keyword
Compile-time checking that no flops are inferred in block (enforces above)
Stick to positive-edge clocked, active-low asynchronous reset flops
Use macro definition for inferring flops
Enforces separation of logic and flops
More compact, but still readable
Easily swap out for different flops, e.g. synchronous reset for FPGA
Use flop/RAM enable terms -> clock/RAM gating

```systemverilog
module my_module (
  // …signals…
);

// Always split out logic and flops!

logic d_in, q_out;        // Use logic type only

always_ff @(posedge clk, negedge rstn) begin
  if(!rstn)
    q_out <= ‘0;
  else
    if(en)
      q_out <= d_in;
end


endmodule  // my_module
```

```systemverilog

`include RTL.svh

module my_module (
  // …signals…
);

// Always split out logic and flops!

logic d_in, q_out;        // Use logic type only

`FF(d_in, q_out, clk, en, rstn, ‘0); 


endmodule  // my_module
```

## Module Declarations and Instantiations

Use the SV syntax for module declarations
Saves typing
For module instantiation, use the automatic SV connections
Use SV packages to group common functions and definitions

```systemverilog
module my_module (
  input logic  clk,
  input logic  rstn,
// …more signals…
);

// Module body

my_module2 u0 (
  .clk,                     // automatic connect
  .rstn,

// …more signals…

  .signal99(),v             // unused output
  .signal100(other_sig)     // override automatic
);

endmodule  // my_module
```


