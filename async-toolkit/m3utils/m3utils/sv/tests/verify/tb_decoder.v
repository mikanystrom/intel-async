`timescale 1ns/1ps
module tb_decoder;
  reg  a, b;
  wire y0_r, y1_r, y2_r, y3_r, y0_g, y1_g, y2_g, y3_g;
  integer errors = 0, vectors = 0;

  test_decoder       rtl  (.a(a), .b(b), .y0(y0_r), .y1(y1_r), .y2(y2_r), .y3(y3_r));
  test_decoder_gates gate (.a(a), .b(b), .y0(y0_g), .y1(y1_g), .y2(y2_g), .y3(y3_g));

  initial begin
    for (integer i = 0; i < 4; i = i + 1) begin
      {a, b} = i[1:0];
      #10;
      vectors = vectors + 1;
      if (y0_r !== y0_g || y1_r !== y1_g || y2_r !== y2_g || y3_r !== y3_g) begin
        $display("MISMATCH at vector %0d: a=%b b=%b", vectors, a, b);
        errors = errors + 1;
      end
    end
    $display("test_decoder: %0d vectors, %0d errors - %s",
             vectors, errors, errors == 0 ? "PASS" : "FAIL");
    $finish;
  end
endmodule
