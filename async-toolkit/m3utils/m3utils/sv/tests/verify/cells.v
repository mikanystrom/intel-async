// cells.v - Standard cell behavioral models
module INV (input A, output Y);
  assign Y = ~A;
endmodule

module BUF (input A, output Y);
  assign Y = A;
endmodule

module NAND2 (input A, B, output Y);
  assign Y = ~(A & B);
endmodule

module NOR2 (input A, B, output Y);
  assign Y = ~(A | B);
endmodule

module AND2 (input A, B, output Y);
  assign Y = A & B;
endmodule

module OR2 (input A, B, output Y);
  assign Y = A | B;
endmodule

module XOR2 (input A, B, output Y);
  assign Y = A ^ B;
endmodule

module XNOR2 (input A, B, output Y);
  assign Y = ~(A ^ B);
endmodule

module MUX2 (input A, B, S, output Y);
  assign Y = S ? B : A;
endmodule

module TIEH (output Y);
  assign Y = 1'b1;
endmodule

module TIEL (output Y);
  assign Y = 1'b0;
endmodule
