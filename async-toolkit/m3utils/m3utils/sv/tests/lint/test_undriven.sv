// Test: undriven output
module test_undriven (
  input  logic [3:0] a,
  input  logic [3:0] b,
  output logic [3:0] sum,
  output logic [3:0] diff  // never driven
);
  assign sum = a + b;
  // diff is intentionally undriven
endmodule
