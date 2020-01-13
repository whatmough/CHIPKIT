// level_to_pulse.sv - Generic RTL model of level to pulse
// HKL 01 2016

module level_to_pulse (
input  logic clock,
input  logic reset_n,
input  logic level,
output logic pulse
);

logic level_delay1, level_delay2;

always@(posedge clock or negedge reset_n)
begin
  if(!reset_n)
  begin
    level_delay1 <= 1'b0;
    level_delay2 <= 1'b0;
  end
  else
  begin
    level_delay1 <= level;
    level_delay2 <= level_delay1;
  end
end

always_comb pulse = level_delay1 & (~level_delay2);

endmodule
