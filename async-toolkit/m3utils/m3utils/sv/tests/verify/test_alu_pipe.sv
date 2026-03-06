// Registered ALU: flop-to-flop combinational cone
//
// Inputs a_q, b_q, op_q are outputs of input register stage.
// result is the D-input to the output register.
//
// Flop path: a_q/b_q/op_q (Q) --> combinational ALU --> result (D)
//
// op=00: add    op=01: sub    op=10: bitwise AND    op=11: bitwise XOR
//
module alu_pipe (
  input        clk,
  input  [3:0] a_q,
  input  [3:0] b_q,
  input  [1:0] op_q,
  output [3:0] result
);
  reg [3:0] result;

  always_ff @(posedge clk) begin
    case (op_q)
      2'b00: result <= a_q + b_q;
      2'b01: result <= a_q - b_q;
      2'b10: result <= a_q & b_q;
      2'b11: result <= a_q ^ b_q;
    endcase
  end
endmodule
