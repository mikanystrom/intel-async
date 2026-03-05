`timescale 1ns/1ps
module tb_compare;
  reg  a, b;
  wire eq_rtl, gt_rtl, lt_rtl, eq_gate, gt_gate, lt_gate;
  integer errors = 0, vectors = 0;

  test_compare       rtl  (.a(a), .b(b), .eq(eq_rtl), .gt(gt_rtl), .lt(lt_rtl));
  test_compare_gates gate (.a(a), .b(b), .eq(eq_gate), .gt(gt_gate), .lt(lt_gate));

  initial begin
    for (integer i = 0; i < 4; i = i + 1) begin
      {a, b} = i[1:0];
      #10;
      vectors = vectors + 1;
      if (eq_rtl !== eq_gate || gt_rtl !== gt_gate || lt_rtl !== lt_gate) begin
        $display("MISMATCH at vector %0d: a=%b b=%b", vectors, a, b);
        errors = errors + 1;
      end
    end
    $display("test_compare: %0d vectors, %0d errors - %s",
             vectors, errors, errors == 0 ? "PASS" : "FAIL");
    $finish;
  end
endmodule
