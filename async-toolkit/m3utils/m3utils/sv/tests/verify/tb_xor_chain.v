// tb_xor_chain.v - Exhaustive equivalence testbench for test_xor_chain
`timescale 1ns/1ps

module tb_xor_chain;
  reg  a, b, c, d;
  wire y_rtl, y_gate;
  integer errors = 0;
  integer vectors = 0;

  test_xor_chain       rtl  (.a(a), .b(b), .c(c), .d(d), .y(y_rtl));
  test_xor_chain_gates gate (.a(a), .b(b), .c(c), .d(d), .y(y_gate));

  initial begin
    $dumpfile("tb_xor_chain.vcd");
    $dumpvars(0, tb_xor_chain);
  end

  initial begin
    // Exhaustive: 4 inputs = 16 combinations
    for (integer i = 0; i < 16; i = i + 1) begin
      {a, b, c, d} = i[3:0];
      #10;
      vectors = vectors + 1;
      if (y_rtl !== y_gate) begin
        $display("MISMATCH at vector %0d: a=%b b=%b c=%b d=%b => rtl_y=%b gate_y=%b",
                 vectors, a, b, c, d, y_rtl, y_gate);
        errors = errors + 1;
      end
    end
    $display("test_xor_chain: %0d vectors, %0d errors - %s",
             vectors, errors, errors == 0 ? "PASS" : "FAIL");
    if (errors != 0) $finish(1);
    $finish;
  end
endmodule
