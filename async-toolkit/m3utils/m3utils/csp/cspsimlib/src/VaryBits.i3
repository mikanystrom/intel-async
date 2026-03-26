(* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE VaryBits;
IMPORT CardSet;
IMPORT FiniteInterval;
IMPORT Mpz;

TYPE
  Bit = { Zero, One, Vary };

  T = RECORD
    sign : Bit;
    x    : ARRAY Bit OF CardSet.T;
  END;

CONST
  BitName = ARRAY Bit OF TEXT { "0", "1", "X" };

  Flip    = ARRAY Bit OF Bit  { Bit.One, Bit.Zero, Bit.Vary };

PROCEDURE IntBits(big : Mpz.T) : T;

PROCEDURE Union(a, b : T) : T;
  
PROCEDURE FromInterval(fi : FiniteInterval.T) : T;

PROCEDURE ToInterval(t : T) : FiniteInterval.T;

PROCEDURE MaxVarying(t : T) : CARDINAL;

PROCEDURE MaxDefinedBit(t : T) : [ -1 .. LAST(CARDINAL) ];

PROCEDURE Format(t : T) : TEXT;

PROCEDURE Min(t : T) : T;
PROCEDURE Max(t : T) : T;
  
CONST Brand = "VaryBits";

END VaryBits.
