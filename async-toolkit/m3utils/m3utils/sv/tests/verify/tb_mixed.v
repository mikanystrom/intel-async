// tb_mixed.v - Exhaustive equivalence testbench for test_mixed
`timescale 1ns/1ps

module tb_mixed;
  reg  a, b, c, d;
  wire y_rtl, z_rtl, y_gate, z_gate;
  integer errors = 0;
  integer vectors = 0;

  test_mixed       rtl  (.a(a), .b(b), .c(c), .d(d), .y(y_rtl),  .z(z_rtl));
  test_mixed_gates gate (.a(a), .b(b), .c(c), .d(d), .y(y_gate), .z(z_gate));

  initial begin
    $dumpfile("tb_mixed.vcd");
    $dumpvars(0, tb_mixed);
  end

  initial begin
    // Exhaustive: 4 inputs = 16 combinations
    for (integer i = 0; i < 16; i = i + 1) begin
      {a, b, c, d} = i[3:0];
      #10;
      vectors = vectors + 1;
      if (y_rtl !== y_gate || z_rtl !== z_gate) begin
        $display("MISMATCH at vector %0d: a=%b b=%b c=%b d=%b => rtl(y=%b,z=%b) gate(y=%b,z=%b)",
                 vectors, a, b, c, d, y_rtl, z_rtl, y_gate, z_gate);
        errors = errors + 1;
      end
    end
    $display("test_mixed: %0d vectors, %0d errors - %s",
             vectors, errors, errors == 0 ? "PASS" : "FAIL");
    if (errors != 0) $finish(1);
    $finish;
  end
endmodule
