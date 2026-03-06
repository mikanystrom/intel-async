`define MAKE_WIRE(prefix, suffix) wire prefix``suffix
`MAKE_WIRE(data, _out);
`MAKE_WIRE(clk, _buf);
