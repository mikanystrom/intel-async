`define ASSERT(name, prop, clk = clk_i, rst = !rst_ni)
`define REG(name, width = 1) reg [width-1:0] name
module test;
  `ASSERT(chk, a == b)
  `ASSERT(chk2, x, clk2, rst2)
  `REG(foo);
  `REG(bar, 8);
endmodule
