module test_mixed (input a, input b, input c, input d, output y, output z);
  assign y = (a & b) | (c ^ d);
  assign z = ~(a | b) & c;
endmodule
