# Verilog GENerator (VGEN)

## Introduction

SystemVerilog still has poor support for templating.
Generate statement and parameterization are both quite hard to use.
The perennial workaround for this is to write generators.

VGEN is a simple Python framework for writing generators quickly.
CSV database of objects, could be registers, pins, rams, pads, anything.
Implemented in Python as a list of dictionaries.

Tools to automatically populate and update this database from RTL, C, Python, or even documentation.
Easy to use signal or module name pre/post -fix to mark things for automation.
Tools to generate RTL modules/instances, Python code, C code, Markdown, …

## Examples

Two examples are included here: the first is a script to generate memory mapped registers automatically; the second script generates chip pad rings.

