module test_range4 (input [7:0] a,
                   output [3:0] lo, output [3:0] hi, output bit5);
  assign lo = a[3:0];
  assign hi = a[7:4];
  assign bit5 = a[5];
endmodule
