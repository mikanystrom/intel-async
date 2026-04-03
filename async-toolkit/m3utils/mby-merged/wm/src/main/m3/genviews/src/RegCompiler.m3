(* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE RegCompiler;
IMPORT RegAddrmap, BigInt;

REVEAL
  T = Public BRANDED Brand OBJECT
  OVERRIDES
    init := Init;
  END;
  
PROCEDURE Init(t : T; map : RegAddrmap.T) : T =
  BEGIN
    t.map := map;
    t.addr := BigInt.New(0); (* should be adjustable, no? *)
    RETURN t
  END Init;

BEGIN END RegCompiler.
