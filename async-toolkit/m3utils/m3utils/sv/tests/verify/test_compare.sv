module test_compare (input a, input b, output eq, output gt, output lt);
  // 1-bit comparator
  assign eq = ~(a ^ b);
  assign gt = a & ~b;
  assign lt = ~a & b;
endmodule
