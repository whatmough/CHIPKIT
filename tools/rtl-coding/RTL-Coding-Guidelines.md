# CHIPKIT RTL Coding Guidelines

Research test chip projects are typically severely time constrained.
Therefore, it is important to use an RTL development approach that is 1) efficient, 2) minimizes bugs, and 3) is supported by front-to-back EDA tool flows.
While less verbose than VHDL, the earlier Verilog RTL standards such as Verilog'95 and Verilog-2001 offer very limited compile-time checking, which can lead to a large number of trivial bugs.
Although this can be overcome by the use of lining tools and strict coding guidlines, it is generally slow.

In recent years, there has been a significant research effort exploring new hardware design languages, such as Chisel, PyMTL, MyHDL etc, as well as high-level synthesis (HLS) from C++/SystemC languages.
However, in either case, there is a translation step of varying complexity required to generate Verilog for the EDA tools to consume.
We use SystemVerilog (SV) for most of our RTL design, which is mature, natively supported by EDA tools, and relatively well supported in open source projects.
SV includes a number of more advanced language features that prevent a whole class of common issues with older Verilog standards.

This document outlines some coding guidelines for writing bug-free RTL in SV.
More generally, we offer advice for arranging RTL projects.

## SystemVerilog RTL Coding Style Overview

SV is a very large language with many verification-oriented features that are not relevant to writing synthesizable RTL.
Therefore, we use a strict RTL coding style, which can be summarized in the following directives:

* **Separate logic and registers.**
Makes RTL easier to parse and pipelining easier to modify.
Forces designers to think about where registers exist in the design.
Also typically also  it easier to modify pipelines.

* **Use rising-edge registers with active-low async reset.**
Simplifies functional debug, validation and timing constraint development.

* **Only one clock and reset signal in a module.**
This guideline drastically reduces bugs related to clocking and reset.
The vast majority of RTL modules do not require more than one clock and reset.
Any logic that *requires* multiple clocks should be careful contained in a special module.

* **Use the `logic` type exclusively.**
Replaces both the older \texttt{wire} and (very confusing) \texttt{reg} types.
Provides compile-time checking for multiple drivers.

* **Use the `always_comb` keyword for logic.**
Provides compile-time checking for unintended latches or registers.

* **Use the ``always_ff`` keyword to infer registers.**
Provides compile-time checking for unintentional latches.

* **Use automatic module instantiation connections (`.*`).**
These significantly reduce the verbosity of connecting modules and provide additional compile-time checking.

* **Lower-case signal names with underscores (`_`).**

* **Use all-caps for top-level module port signals.**


The following tiny RTL example module `my_counter` demonstrates some of these guidelines in a compact example.

```systemverilog
`include RTL.svh

module my_counter (
  input  logic       clock,
  input  logic       reset_n,
  
  input  logic       enable,
  output logic[31:0] count
);

// "logic" type replaces "wire" and "reg"
logic[31:0] count_next;

// Use "always_comb" keyword for logic
always_comb count_next = count + 32'd1;

// Use a macro to infer registers
`FF(count_next, count, clock, enable, reset_n, '0); 

endmodule  // my_counter
```

In addition to these guidelines, we also recommend the strict use of a pre-processor macro for register inference.
This is a fairly common practice in industry and has a number of advantages, including: 1) significant reduction in lines of code, 2) removes the risk of poor inference style, e.g. embedded logic, 3) enforces use of a rising-edge, async active-low reset, 4) allows the register inference template to be changed to suit ASIC or FPGA.
A macro is used instead of a module to reduce simulation overhead.
The CHIPKIT RTL header file (`RTL.svh`) includes a macro definition `` `FF()`` for this purpose, which replaces the traditional inference template, as shown in the snippet below.  
When using FPGAs with an RTL codebase, this macro can be easily redefined to infer a synchronous reset, which is more common.

```systemverilog
// Include file contains flip-flop inference macro
// Add this at the top of every RTL source file
`include RTL.svh

// Traditional flip-flop inference template
always_ff @(posedge clock, negedge reset_n) begin
  if(!reset_n) q_out <= ‘0;
  else
    if(enable) q_out <= d_in;
end

// Example of flip-flop macro
// (Final term ('0) is the reset state)
`FF(count_next, count, clock, enable, reset_n, '0); 
```

### Instantiated Library Components

Physical IP such as SRAMs, IO cells, clock oscillators, and synchronizers need to be instantiated in the RTL.
It's worth remembering that various versions of these cells may be required over the lifetime of the IP or full-chip, including RTL functional models as well as various ASIC and FPGA libraries.
Therefore, it is helpful to wrap instantiated components inside a module, which can then be easily switched as needed.
Each set of wrapped component instantiation modules is stored in a different directory for each library, with the correct directory included at compile time or physical implementation time.

TODO - example

### Project Directory Organization

TODO

```
project
│   README.md
│   file001.txt    
│
└───folder1 
│   │   file011.txt
│   │   file012.txt
│   │
│   └───subfolder1
│       │   file111.txt
│       │   file112.txt
│       │   ...
│   
└───folder2
    │   file021.txt
    │   file022.txt
```




