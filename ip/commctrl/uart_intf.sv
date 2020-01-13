// uart_intf.sv
// HKL 01 2016


//---------------------------------------------------------
// UART without handshake
//---------------------------------------------------------
interface uart;
logic txd;
logic rxd;

modport source(input rxd, output txd);
modport sink(input txd, output rxd);
endinterface

//---------------------------------------------------------
// UART with hardware handshake
//---------------------------------------------------------
interface uart_hw;
logic txd;
logic rxd;
logic cts;
logic rts;

modport source(input rxd, cts, output txd, rts);
modport sink(input txd, rts, output rxd, cts);
endinterface
