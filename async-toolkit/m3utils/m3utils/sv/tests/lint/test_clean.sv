// Test: clean module -- should produce zero warnings
module test_clean (
  input  logic       clk,
  input  logic       rst_n,
  input  logic [3:0] a,
  input  logic [3:0] b,
  output logic [3:0] sum,
  output logic [3:0] q
);
  assign sum = a + b;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      q <= 4'b0000;
    else
      q <= a;
  end
endmodule
