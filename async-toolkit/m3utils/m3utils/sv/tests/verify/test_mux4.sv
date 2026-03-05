module test_mux4 (input s0, input s1, input d0, input d1, input d2, input d3, output y);
  assign y = s1 ? (s0 ? d3 : d2) : (s0 ? d1 : d0);
endmodule
