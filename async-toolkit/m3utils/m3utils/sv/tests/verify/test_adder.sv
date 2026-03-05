module test_adder (input a, input b, input cin,
                  output sum, output cout);
  // Full adder
  assign sum = a ^ b ^ cin;
  assign cout = (a & b) | (a & cin) | (b & cin);
endmodule
