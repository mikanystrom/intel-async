// Test: width mismatches
module test_width (
  input  logic [7:0] a,
  input  logic [3:0] b,
  output logic [7:0] y,
  output logic [3:0] z
);
  // 8-bit = 4-bit (width mismatch)
  assign y = b;
  // 4-bit = 8-bit (width mismatch, truncation)
  assign z = a;
endmodule
