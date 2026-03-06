module test_mux4w (input sel, input [3:0] a, input [3:0] b,
                  output [3:0] y);
  assign y = sel ? a : b;
endmodule
