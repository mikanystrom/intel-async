`timescale 1ns/1ps
module tb_adder;
  reg  a, b, cin;
  wire sum_rtl, cout_rtl, sum_gate, cout_gate;
  integer errors = 0, vectors = 0;

  test_adder       rtl  (.a(a), .b(b), .cin(cin), .sum(sum_rtl), .cout(cout_rtl));
  test_adder_gates gate (.a(a), .b(b), .cin(cin), .sum(sum_gate), .cout(cout_gate));

  initial begin
    for (integer i = 0; i < 8; i = i + 1) begin
      {a, b, cin} = i[2:0];
      #10;
      vectors = vectors + 1;
      if (sum_rtl !== sum_gate || cout_rtl !== cout_gate) begin
        $display("MISMATCH at vector %0d: a=%b b=%b cin=%b => rtl=%b%b gate=%b%b",
                 vectors, a, b, cin, cout_rtl, sum_rtl, cout_gate, sum_gate);
        errors = errors + 1;
      end
    end
    $display("test_adder: %0d vectors, %0d errors - %s",
             vectors, errors, errors == 0 ? "PASS" : "FAIL");
    $finish;
  end
endmodule
