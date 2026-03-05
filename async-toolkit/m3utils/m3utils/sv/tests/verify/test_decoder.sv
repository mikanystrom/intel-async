module test_decoder (input a, input b,
                    output y0, output y1, output y2, output y3);
  // 2-to-4 decoder
  assign y0 = ~a & ~b;
  assign y1 = ~a &  b;
  assign y2 =  a & ~b;
  assign y3 =  a &  b;
endmodule
