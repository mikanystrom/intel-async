(* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE FiniteInterval;
IMPORT Mpz;

PROCEDURE Construct(lo, hi : Mpz.T) : T =
  BEGIN
    RETURN T { lo, hi }
  END Construct;

BEGIN END FiniteInterval.
