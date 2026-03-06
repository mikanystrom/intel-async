`define CHECK(name, prop, clk = clk_i, rst = !rst_ni)
module test;
  `CHECK(foo,
         a && b &&
         c)
  wire x;
endmodule
