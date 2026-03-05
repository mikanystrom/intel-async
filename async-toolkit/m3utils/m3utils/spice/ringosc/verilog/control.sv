// Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information.
// SPDX-License-Identifier: Apache-2.0


// W-bit saturating counter, configurable count range
// range is [ 0 .. MAXVAL ]
// saturates at ends of range
module incdec
  #(parameter W=8,
    parameter MAXVAL=140)
   (
    input  logic [W-1:0]  cur,
    input  logic          decrement,
    output logic [W-1:0]  nxt
   );

   always_comb begin
     
      nxt = cur;

      if (decrement)
        nxt = (cur == 0)      ? 0      : (cur - 1);
      else
        nxt = (cur == MAXVAL) ? MAXVAL : (cur + 1);
   end
endmodule

module oscdecode
  #(parameter NSETTINGS=4,
    parameter NINTERP  =8,
    parameter NTAPS    =6,
    parameter NSETTINGS_PER_TAP = NINTERP * NSETTINGS,
    parameter NTOTAL_SPEEDS = NTAPS * NSETTINGS_PER_TAP + 1,
    parameter W        = $clog2(NTOTAL_SPEEDS)
    )
   (input logic [W-1:0] speed
    );

   generate
      for (genvar s=0; s < NTOTAL_SPEEDS; ++s) begin : gen_speed

         localparam tap_lo       = s / NSETTINGS_PER_TAP;
         localparam speed_in_tap = s % NSETTINGS_PER_TAP;
         localparam tap_hi       = tap_lo + 1;
         localparam code_in_tap  = (tap_lo % 2 == 0) ? speed_in_tap : (settings_per_tap - speed_in_tap);
         
         for (genvar i=0; i < NINTERP; ++i) begin : gen_interp
            localparam c_o_s = code_in_tap / NSETTINGS;
            
            localparam ic = (c_o_s > i) ? NSETTINGS :
                            ((c_o_s == i) ? code_in_tap % NSETTINGS :
                             0);
            
         end
         
        
         
      end
   endgenerate

  


endmodule
    
   
