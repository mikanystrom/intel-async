// test_mixed.v - Mixed logic with two outputs
// y = (a & b) | (c ^ d)
// z = ~(a | b) & c
module test_mixed (
  input  a, b, c, d,
  output y, z
);
  assign y = (a & b) | (c ^ d);
  assign z = ~(a | b) & c;
endmodule
