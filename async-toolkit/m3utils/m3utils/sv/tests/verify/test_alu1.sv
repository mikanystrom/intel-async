module test_alu1 (input a, input b, input op0, input op1, output y);
  // 1-bit ALU: op selects operation
  // 00=AND, 01=OR, 10=XOR, 11=NAND
  assign y = op1 ? (op0 ? ~(a & b) : (a ^ b))
                 : (op0 ? (a | b)  : (a & b));
endmodule
