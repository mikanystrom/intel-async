module test_reduce8 (input [7:0] a,
                    output r_and, output r_or, output r_xor);
  assign r_and = &a;
  assign r_or  = |a;
  assign r_xor = ^a;
endmodule
