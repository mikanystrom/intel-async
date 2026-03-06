// Test: large case statement (exceeds decomposition threshold)
// 16-arm case on a 4-bit selector, each arm assigns a different 8-bit value
module test_bigcase(
  input  [3:0] sel,
  output [7:0] y
);
  reg [7:0] y;
  always_comb begin
    case (sel)
      4'd0:  y = 8'hA0;
      4'd1:  y = 8'hB1;
      4'd2:  y = 8'hC2;
      4'd3:  y = 8'hD3;
      4'd4:  y = 8'hE4;
      4'd5:  y = 8'hF5;
      4'd6:  y = 8'h06;
      4'd7:  y = 8'h17;
      4'd8:  y = 8'h28;
      4'd9:  y = 8'h39;
      4'd10: y = 8'h4A;
      4'd11: y = 8'h5B;
      4'd12: y = 8'h6C;
      4'd13: y = 8'h7D;
      4'd14: y = 8'h8E;
      4'd15: y = 8'h9F;
    endcase
  end
endmodule
