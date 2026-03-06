// Test: latch inference from incomplete if/case
module test_latch (
  input  logic       sel,
  input  logic [1:0] mode,
  input  logic [3:0] a,
  input  logic [3:0] b,
  output logic [3:0] y,
  output logic [3:0] z
);
  // Incomplete if -- y is latched when sel=0
  always_comb begin
    if (sel)
      y = a;
    // no else
  end

  // Incomplete case -- z is latched for mode==2'b11
  always_comb begin
    case (mode)
      2'b00: z = a;
      2'b01: z = b;
      2'b10: z = a + b;
      // no default, no 2'b11 case
    endcase
  end
endmodule
