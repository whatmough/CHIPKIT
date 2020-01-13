// uart.sv : duplex uart module
// HKL 01 2016

`include "rtl_macros.svh"

module uart
import comm_defs_pkg::*;
(
    input  logic        clk,      // The master clock for this module
    input  logic        rstn,     // Asynchronous reset.
    input  logic [11:0] baud_div, // Baud Rate Divider
    input  logic        rxd,      // Incoming serial line
    output logic        txd,      // Outgoing serial line
    input  logic        txen,     // Signal to transmit
    input  logic [7:0]  tx_byte,  // Byte to transmit
    output logic        rx_done,  // Indicated that a byte has been received.
    output logic [7:0]  rx_byte,  // Byte received
    output logic        rx_ing,   // Low when receive line is idle.
    output logic        tx_ing,   // Low when transmit line is idle.
    output logic        rx_err    // Indicates err in receiving packet.
    );

// Baud Rate
logic [11:0] clk_div;
always_comb clk_div = baud_div - 1;

//---------------------------------------------------------
// TX
//---------------------------------------------------------
// tx_cntdown_nxt is basically the same as tx_cntdown_cycle
// tx_refclk_nxt is basically the same as tx_refclk_cycle
// Just seperate them to avoid multi driven err
logic tx_out, tx_out_nxt;
logic [5:0] tx_cntdown, tx_cntdown_nxt, tx_cntdown_cycle;
logic [11:0] tx_refclk, tx_refclk_nxt, tx_refclk_cycle;
logic [3:0] tx_bits, tx_bits_nxt;
logic [7:0] tx_data, tx_data_nxt;
logic tx_refclk_tick, tx_cntdown_tick, tx_bits_tick;

// Reference clock using a counter for txd operation
always_comb tx_refclk_cycle = (!tx_refclk_tick) ? (tx_refclk-12'd1) : clk_div;
// Down counter to generate baud rate for txd (4 counts = 1 baud pulse)
always_comb tx_cntdown_cycle = (!tx_refclk_tick) ? tx_cntdown : (tx_cntdown-6'd1);

// Ticks
always_comb tx_refclk_tick  = (tx_refclk==12'd0);
always_comb tx_cntdown_tick = (tx_cntdown_cycle==6'd0);
always_comb tx_bits_tick    = (tx_bits==4'd0);


// TX FSM Encoding
enum logic [1:0]
    {TX_IDLE,
     TX_SENDING,
     TX_DELAY_RESTART
    } tx_state, tx_state_nxt;
`FF(tx_state_nxt,tx_state,clk,1'b1,rstn,TX_IDLE);
always_comb begin : TX_FSM_STATE_MACHINE
    // Default assignments to avoid infered latch
    tx_state_nxt = tx_state;
    case(tx_state)
        TX_IDLE: begin
	        if (txen) begin
	            tx_state_nxt = TX_SENDING;
            end
        end
        TX_SENDING: begin
	        if (tx_cntdown_tick) begin
	            if (!tx_bits_tick) begin
	                tx_state_nxt = TX_SENDING;
	            end else begin
	                tx_state_nxt = TX_DELAY_RESTART;
		        end
            end
	    end
	    TX_DELAY_RESTART: begin
            if (!tx_cntdown_tick) begin
                tx_state_nxt = TX_DELAY_RESTART;
            end else begin
                tx_state_nxt = TX_IDLE;
            end
        end
        default: tx_state_nxt = TX_IDLE;
    endcase
end

// Update next state values
`FF(tx_refclk_nxt,tx_refclk,clk,'1,rstn,'0);
`FF(tx_cntdown_nxt,tx_cntdown,clk,'1,rstn,'0);
`FF(tx_out_nxt,tx_out,clk,'1,rstn,'1);
`FF(tx_bits_nxt,tx_bits,clk,'1,rstn,'0);
`FF(tx_data_nxt,tx_data,clk,'1,rstn,'0);

// Combinational logics for next state values
always_comb begin : TX_FSM_DECODE
    // Default assignments to avoid infered latch
    tx_out_nxt = tx_out;
    tx_bits_nxt = tx_bits;
    tx_data_nxt = tx_data;
    // Baud_Rate Generate
    tx_refclk_nxt = tx_refclk_cycle;
    tx_cntdown_nxt = tx_cntdown_cycle;

    case (tx_state)
        TX_IDLE: begin
            if (txen) begin
                // If the txen flag is raised in the idle
                // state, start transmitting the current content
                // of the tx_byte input.
                tx_data_nxt = tx_byte;
                // Send the initial, low pulse of 1 bit period
                // to signal the start, followed by the data
                tx_refclk_nxt = clk_div;
                tx_cntdown_nxt = 4;
                tx_out_nxt= 0;
                tx_bits_nxt = 8;
            end
        end
        TX_SENDING: begin
            if (tx_cntdown_tick) begin
                if (!tx_bits_tick) begin
                    tx_bits_nxt = tx_bits - 1;
                    tx_out_nxt = tx_data[0];
                    tx_data_nxt = {1'b0, tx_data[7:1]};
                    tx_cntdown_nxt = 4;
                end else begin
                // Set delay to send out 2 stop bits.
                    tx_out_nxt = 1;
                    //tx_cntdown_nxt = 4;
                    tx_cntdown_nxt = 8;
                end
            end
        end
    	TX_DELAY_RESTART: begin
            // Empty
    	end
        default: begin
            // Default assignments to avoid infered latch
            tx_out_nxt = '0;
            tx_bits_nxt = '0;
            tx_data_nxt = '0;
            // Baud_Rate Generate
            tx_refclk_nxt = '0;
            tx_cntdown_nxt = '0;
        end
    endcase
end

// Output Combinational Logic
always_comb txd = tx_out;
always_comb tx_ing = (tx_state != TX_IDLE);

//---------------------------------------------------------
// RX
//---------------------------------------------------------
// rx_cntdown_nxt is basically the same as rx_cntdown_cycle
// rx_refclk_nxt is basically the same as rx_refclk_cycle
// Just seperate them to avoid multi driven err
logic [5:0] rx_cntdown, rx_cntdown_nxt, rx_cntdown_cycle;
logic [11:0] rx_refclk, rx_refclk_nxt, rx_refclk_cycle;
logic [3:0] rx_bits, rx_bits_nxt;
logic [7:0] rx_data, rx_data_nxt;
logic rx_refclk_tick, rx_cntdown_tick, rx_bits_tick;


// Reference clock using a counter for rxd operation
always_comb rx_refclk_cycle = (rx_refclk_tick) ? clk_div : (rx_refclk-12'd1);
// Down counter to generate baud rate for rxd (4 counts = 1 baud pulse)
always_comb rx_cntdown_cycle = (rx_refclk_tick) ? (rx_cntdown-6'd1) : rx_cntdown;

// Ticks
always_comb rx_refclk_tick  = (rx_refclk==12'd0);
always_comb rx_cntdown_tick = (rx_cntdown_cycle==6'd0);
always_comb rx_bits_tick    = (rx_bits==4'd0);


// RX FSM Encoding
enum logic [2:0]
    {RX_IDLE,
     RX_CHECK_START,
     RX_READ_BITS,
     RX_CHECK_STOP,
     RX_DELAY_RESTART,
     RX_ERR,
     RX_DONE
    } rx_state, rx_state_nxt;
`FF(rx_state_nxt,rx_state,clk,1'b1,rstn,RX_IDLE);
always_comb begin : RX_FSM_STATE_MACHINE
    // Default assignments to avoid infered latch
    rx_state_nxt = rx_state;
    case (rx_state)
	    RX_IDLE: begin
	        if (!rxd) begin
		        rx_state_nxt = RX_CHECK_START;
            end
	    end
	    RX_CHECK_START: begin
            if (rx_cntdown_tick) begin
	            if (!rxd) begin
		            rx_state_nxt = RX_READ_BITS;
		        end else begin
		            rx_state_nxt = RX_ERR;
		        end
            end
	    end
	    RX_READ_BITS: begin
	        if (rx_cntdown_tick) begin
                if (rx_bits!=4'd1) begin
                    rx_state_nxt = RX_READ_BITS;
                end else begin
                    rx_state_nxt = RX_CHECK_STOP;
                end
            end
	    end
	    RX_CHECK_STOP: begin
	        if (rx_cntdown_tick) begin
                if (rxd) begin
		            rx_state_nxt = RX_DONE;
                end else begin
		            rx_state_nxt = RX_ERR;
                end
            end
	    end
        RX_DELAY_RESTART: begin
            if (!rx_cntdown_tick) begin
	            rx_state_nxt = RX_DELAY_RESTART;
            end
	    end
	    RX_ERR: begin
            rx_state_nxt = RX_DELAY_RESTART;
	    end
	    RX_DONE: begin
	        rx_state_nxt = RX_IDLE;
	    end
        default: rx_state_nxt = RX_IDLE;
    endcase
end

// Update next state values
`FF(rx_refclk_nxt,rx_refclk,clk,'1,rstn,'0);
`FF(rx_cntdown_nxt,rx_cntdown,clk,'1,rstn,'0);
`FF(rx_bits_nxt,rx_bits,clk,'1,rstn,'0);
`FF(rx_data_nxt,rx_data,clk,'1,rstn,'0);

// Combinational logics for next state values
always_comb begin : RX_FSM_DECODE
    // Default assignments to avoid infered latch
    rx_bits_nxt = rx_bits;
    rx_data_nxt = rx_data;
    // Baud_Rate Generate
    rx_refclk_nxt = rx_refclk_cycle;
    rx_cntdown_nxt = rx_cntdown_cycle;

    // Update Registers
    case (rx_state)
	    RX_IDLE: begin
	        // A low pulse on the receive line indicates the
	        // start of data.
	        if (!rxd) begin
	            // Wait half the period - should resume in the
	            // middle of this first pulse.
	            rx_refclk_nxt = clk_div;
	            rx_cntdown_nxt = 2;
	        end
	    end
	    RX_CHECK_START: begin
	        if (rx_cntdown_tick) begin
	        // Check the pulse is still there
	            if (!rxd) begin
	                // Pulse still there - good
	                // Wait the bit period to resume half-way
	                // through the first bit.
	                rx_cntdown_nxt = 4;
	                rx_bits_nxt = 8;
	            end
	        end
	    end
	    RX_READ_BITS: begin
	        if (rx_cntdown_tick) begin
	            // Should be half-way through a bit pulse here.
	            // Read this bit in, wait for the next if we
	            // have more to get.
	            rx_data_nxt = {rxd, rx_data[7:1]};
	            rx_cntdown_nxt = 4;
                // 8 for 2 stop bits
	            //rx_cntdown_nxt = (rx_bits==4'd1) ? 6'd8 : 6'd4;
	            rx_bits_nxt = rx_bits - 1;
	        end
	    end
	    RX_CHECK_STOP: begin
        end
        RX_DELAY_RESTART: begin
        end
        RX_ERR: begin
	        // There was an err receiving.
	        // Raises the RX_ERR flag for one clock
	        // cycle while in this state and then waits
	        // 2 bit periods before accepting another
	        // transmission.
	        rx_cntdown_nxt = 8;
	    end
        default: begin
            rx_refclk_nxt = '0;
            rx_cntdown_nxt = '0;
            rx_bits_nxt = '0;
            rx_data_nxt = '0;
        end
    endcase
end

// Output Combinational Logic
always_comb rx_done = (rx_state == RX_DONE);
always_comb rx_err  = (rx_state == RX_ERR);
always_comb rx_ing  = (rx_state != RX_IDLE);
always_comb rx_byte = (rx_data);

endmodule
