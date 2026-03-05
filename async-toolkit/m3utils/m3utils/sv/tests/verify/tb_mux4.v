// tb_mux4.v - Exhaustive equivalence testbench for test_mux4
`timescale 1ns/1ps

module tb_mux4;
  reg  s0, s1, d0, d1, d2, d3;
  wire y_rtl, y_gate;
  integer errors = 0;
  integer vectors = 0;

  test_mux4       rtl  (.s0(s0), .s1(s1), .d0(d0), .d1(d1), .d2(d2), .d3(d3), .y(y_rtl));
  test_mux4_gates gate (.s0(s0), .s1(s1), .d0(d0), .d1(d1), .d2(d2), .d3(d3), .y(y_gate));

  initial begin
    $dumpfile("tb_mux4.vcd");
    $dumpvars(0, tb_mux4);
  end

  initial begin
    // Exhaustive: 6 inputs = 64 combinations
    for (integer i = 0; i < 64; i = i + 1) begin
      {s1, s0, d3, d2, d1, d0} = i[5:0];
      #10;
      vectors = vectors + 1;
      if (y_rtl !== y_gate) begin
        $display("MISMATCH at vector %0d: s1=%b s0=%b d3=%b d2=%b d1=%b d0=%b => rtl_y=%b gate_y=%b",
                 vectors, s1, s0, d3, d2, d1, d0, y_rtl, y_gate);
        errors = errors + 1;
      end
    end
    $display("test_mux4: %0d vectors, %0d errors - %s",
             vectors, errors, errors == 0 ? "PASS" : "FAIL");
    if (errors != 0) $finish(1);
    $finish;
  end
endmodule
