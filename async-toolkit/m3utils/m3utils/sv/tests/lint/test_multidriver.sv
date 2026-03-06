// Test: multiple drivers on same signal
module test_multidriver (
  input  logic       sel,
  input  logic [3:0] a,
  input  logic [3:0] b,
  output logic [3:0] y
);
  // Two assign statements driving y -- multiple driver error
  assign y = sel ? a : b;
  assign y = a & b;
endmodule
