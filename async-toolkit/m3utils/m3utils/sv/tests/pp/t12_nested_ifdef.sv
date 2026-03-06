`define A
`define B
`ifdef A
  `ifdef B
    wire ab = 1;
  `else
    wire a_only = 1;
  `endif
`else
  `ifdef B
    wire b_only = 1;
  `else
    wire neither = 1;
  `endif
`endif
