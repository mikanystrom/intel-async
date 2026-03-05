`timescale 1ns/1ps
module tb_parity8;
  reg  a, b, c, d, e, f, g, h;
  wire p_rtl, p_gate;
  integer errors = 0, vectors = 0;

  test_parity8       rtl  (.a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .g(g), .h(h), .p(p_rtl));
  test_parity8_gates gate (.a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .g(g), .h(h), .p(p_gate));

  initial begin
    for (integer i = 0; i < 256; i = i + 1) begin
      {a, b, c, d, e, f, g, h} = i[7:0];
      #10;
      vectors = vectors + 1;
      if (p_rtl !== p_gate) begin
        $display("MISMATCH at vector %0d", vectors);
        errors = errors + 1;
      end
    end
    $display("test_parity8: %0d vectors, %0d errors - %s",
             vectors, errors, errors == 0 ? "PASS" : "FAIL");
    $finish;
  end
endmodule
