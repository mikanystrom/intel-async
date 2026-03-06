// Test: unused signals
module test_unused (
  input  logic       clk,
  input  logic       unused_in,  // never read
  input  logic [3:0] a,
  output logic [3:0] y
);
  logic [3:0] temp;     // used
  logic [3:0] dead_sig; // never used

  assign temp = a + 4'd1;
  assign y = temp;
endmodule
