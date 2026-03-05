module test_priority (input a, input b, input c, input d,
                     output y1, output y0);
  // Priority encoder: highest active input wins
  assign y1 = d | c;
  assign y0 = d | (~c & b);
endmodule
