`timescale 1ns/1ps
module tb_alu1;
  reg  a, b, op0, op1;
  wire y_rtl, y_gate;
  integer errors = 0, vectors = 0;

  test_alu1       rtl  (.a(a), .b(b), .op0(op0), .op1(op1), .y(y_rtl));
  test_alu1_gates gate (.a(a), .b(b), .op0(op0), .op1(op1), .y(y_gate));

  initial begin
    for (integer i = 0; i < 16; i = i + 1) begin
      {a, b, op0, op1} = i[3:0];
      #10;
      vectors = vectors + 1;
      if (y_rtl !== y_gate) begin
        $display("MISMATCH at vector %0d: a=%b b=%b op0=%b op1=%b => rtl=%b gate=%b",
                 vectors, a, b, op0, op1, y_rtl, y_gate);
        errors = errors + 1;
      end
    end
    $display("test_alu1: %0d vectors, %0d errors - %s",
             vectors, errors, errors == 0 ? "PASS" : "FAIL");
    $finish;
  end
endmodule
