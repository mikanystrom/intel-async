module test_parity8 (input a, input b, input c, input d,
                    input e, input f, input g, input h,
                    output p);
  // 8-bit parity
  assign p = a ^ b ^ c ^ d ^ e ^ f ^ g ^ h;
endmodule
