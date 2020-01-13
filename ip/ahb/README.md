# AHB Components

## AHB Interfaces
`ahb_intf.sv`

Provides SystemVerilog interfaces for the AHB-Lite interconnect standard.  This allows rapid, agile SoC development in RTL without all of the typing and debugging.

## AHB Bus
`AHB_BUS.sv`

An agile AHB bus implementation in a single RTL file!  A single include file defines the memory map for the decoder.  This design has been extensively used for numerous successful chip tape outs.

## AHB Master Mux
`AHB_MASTER_MUX.sv`

A simple module to mux up to four masters together.

## AHB Memory Example
`AHB_MEM.sv`

A simple example of a 64KB SRAM attached to an AHB slave port.
