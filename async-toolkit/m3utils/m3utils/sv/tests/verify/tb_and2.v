// tb_and2.v - Exhaustive equivalence testbench for test_and2
`timescale 1ns/1ps

module tb_and2;
  reg  a, b;
  wire y_rtl, y_gate;
  integer errors = 0;
  integer vectors = 0;

  test_and2       rtl  (.a(a), .b(b), .y(y_rtl));
  test_and2_gates gate (.a(a), .b(b), .y(y_gate));

  initial begin
    $dumpfile("tb_and2.vcd");
    $dumpvars(0, tb_and2);
  end

  initial begin
    // Exhaustive: 2 inputs = 4 combinations
    for (integer i = 0; i < 4; i = i + 1) begin
      {a, b} = i[1:0];
      #10;
      vectors = vectors + 1;
      if (y_rtl !== y_gate) begin
        $display("MISMATCH at vector %0d: a=%b b=%b => rtl_y=%b gate_y=%b",
                 vectors, a, b, y_rtl, y_gate);
        errors = errors + 1;
      end
    end
    $display("test_and2: %0d vectors, %0d errors - %s",
             vectors, errors, errors == 0 ? "PASS" : "FAIL");
    if (errors != 0) $finish(1);
    $finish;
  end
endmodule
