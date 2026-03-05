// test_mux4.v - 4:1 mux with 2 select bits
module test_mux4 (
  input  s0, s1,
  input  d0, d1, d2, d3,
  output y
);
  assign y = s1 ? (s0 ? d3 : d2) : (s0 ? d1 : d0);
endmodule
