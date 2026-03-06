module test_bitwise4 (input [3:0] a, input [3:0] b,
                     output [3:0] y_and, output [3:0] y_or,
                     output [3:0] y_xor, output [3:0] y_not);
  assign y_and = a & b;
  assign y_or  = a | b;
  assign y_xor = a ^ b;
  assign y_not = ~a;
endmodule
