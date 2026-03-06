module test_shift4 (input [3:0] a,
                   output [3:0] shl1, output [3:0] shr1);
  assign shl1 = a << 1;
  assign shr1 = a >> 1;
endmodule
