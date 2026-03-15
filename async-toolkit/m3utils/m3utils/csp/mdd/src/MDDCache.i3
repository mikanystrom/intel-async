(* Copyright (c) 2026 Mika Nystrom. *)
(* SPDX-License-Identifier: Apache-2.0 *)

(* MDDCache -- operation cache for MDD set operations.

   Direct-mapped cache keyed on (MDD.T, MDD.T) -> MDD.T.
   Used by Union, Intersection, Difference. *)

INTERFACE MDDCache;
IMPORT MDD;

TYPE T <: REFANY;

PROCEDURE New(size: CARDINAL := 65536) : T;
PROCEDURE Get(cache: T; a, b: MDD.T; VAR result: MDD.T) : BOOLEAN;
PROCEDURE Put(cache: T; a, b, result: MDD.T);
PROCEDURE Clear(cache: T);

END MDDCache.
