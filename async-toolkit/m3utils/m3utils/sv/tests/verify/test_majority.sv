module test_majority (input a, input b, input c, output y);
  assign y = (a & b) | (b & c) | (a & c);
endmodule
