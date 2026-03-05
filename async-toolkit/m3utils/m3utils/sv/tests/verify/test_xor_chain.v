// test_xor_chain.v - 4-input XOR chain
module test_xor_chain (
  input  a, b, c, d,
  output y
);
  assign y = a ^ b ^ c ^ d;
endmodule
