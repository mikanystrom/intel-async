`define FOO
module test;
`ifdef FOO
  wire a;
`else
  wire b;
`endif
`ifdef BAR
  wire c;
`elsif FOO
  wire d;
`else
  wire e;
`endif
`ifndef FOO
  wire f;
`else
  wire g;
`endif
endmodule
