// Test: blocking assign in always_ff
module test_blocking_ff (
  input  logic       clk,
  input  logic       rst_n,
  input  logic [3:0] d,
  output logic [3:0] q
);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      q = 4'b0000;   // should be <=
    else
      q = d;          // should be <=
  end
endmodule
