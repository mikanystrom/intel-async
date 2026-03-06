// MOS 6502 ALU -- pure combinational
//
// Based on the 6502 instruction set as documented in fake6502.c
// (public domain, Mike Chambers).
//
// Operations:
//   0: ADC  (A + operand + C)
//   1: SBC  (A + ~operand + C)
//   2: AND  (A & operand)
//   3: ORA  (A | operand)
//   4: EOR  (A ^ operand)
//   5: ASL  (operand << 1)
//   6: LSR  (operand >> 1)
//   7: ROL  ((operand << 1) | C)
//   8: ROR  ((operand >> 1) | (C << 7))
//   9: INC  (operand + 1)
//  10: DEC  (operand - 1)
//  11: CMP  (A - operand, flags only)
//  12: BIT  (A & operand, special flags)
//  13: PASS_A (pass A through)
//  14: PASS_OP (pass operand through)
//
module alu_6502 (
  input  logic [3:0] op,
  input  logic [7:0] a_in,
  input  logic [7:0] operand,
  input  logic       carry_in,
  output logic [7:0] result,
  output logic       carry_out,
  output logic       zero_out,
  output logic       sign_out,
  output logic       overflow_out
);

  localparam OP_ADC    = 4'd0;
  localparam OP_SBC    = 4'd1;
  localparam OP_AND    = 4'd2;
  localparam OP_ORA    = 4'd3;
  localparam OP_EOR    = 4'd4;
  localparam OP_ASL    = 4'd5;
  localparam OP_LSR    = 4'd6;
  localparam OP_ROL    = 4'd7;
  localparam OP_ROR    = 4'd8;
  localparam OP_INC    = 4'd9;
  localparam OP_DEC    = 4'd10;
  localparam OP_CMP    = 4'd11;
  localparam OP_BIT    = 4'd12;
  localparam OP_PASS_A = 4'd13;
  localparam OP_PASS   = 4'd14;

  logic [8:0] sum;  // 9-bit for carry detection

  always_comb begin
    result       = 8'd0;
    carry_out    = 1'b0;
    overflow_out = 1'b0;

    case (op)
      OP_ADC: begin
        sum          = {1'b0, a_in} + {1'b0, operand} + {8'd0, carry_in};
        result       = sum[7:0];
        carry_out    = sum[8];
        overflow_out = (a_in[7] == operand[7]) && (result[7] != a_in[7]);
      end

      OP_SBC: begin
        sum          = {1'b0, a_in} + {1'b0, ~operand} + {8'd0, carry_in};
        result       = sum[7:0];
        carry_out    = sum[8];
        overflow_out = (a_in[7] != operand[7]) && (result[7] != a_in[7]);
      end

      OP_AND: begin
        result = a_in & operand;
      end

      OP_ORA: begin
        result = a_in | operand;
      end

      OP_EOR: begin
        result = a_in ^ operand;
      end

      OP_ASL: begin
        {carry_out, result} = {operand, 1'b0};
      end

      OP_LSR: begin
        carry_out = operand[0];
        result    = {1'b0, operand[7:1]};
      end

      OP_ROL: begin
        {carry_out, result} = {operand, carry_in};
      end

      OP_ROR: begin
        carry_out = operand[0];
        result    = {carry_in, operand[7:1]};
      end

      OP_INC: begin
        result = operand + 8'd1;
      end

      OP_DEC: begin
        result = operand - 8'd1;
      end

      OP_CMP: begin
        sum       = {1'b0, a_in} + {1'b0, ~operand} + 9'd1;
        result    = sum[7:0];
        carry_out = sum[8]; // C set if A >= operand
      end

      OP_BIT: begin
        result       = a_in & operand;
        overflow_out = operand[6];
      end

      OP_PASS_A: begin
        result = a_in;
      end

      OP_PASS: begin
        result = operand;
      end

      default: begin
        result = 8'd0;
      end
    endcase

    zero_out = (result == 8'd0);
    sign_out = result[7];
  end

endmodule
