`define LONG_MACRO(a, b) \
  ((a) + \
   (b))
wire x = `LONG_MACRO(1, 2);
