`define MAX(a, b) ((a) > (b) ? (a) : (b))
`define MIN(a, b) ((a) < (b) ? (a) : (b))
module test;
  assign y = `MAX(x, 3);
  assign z = `MIN(x, `MAX(a, b));
endmodule
