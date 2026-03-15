(* Copyright (c) 2026 Mika Nystrom. *)
(* SPDX-License-Identifier: Apache-2.0 *)

(* MDDUniqueTable -- per-level hash-consing table for MDD nodes.

   Keyed on variable-length child arrays.  Two nodes at the same level
   with identical children arrays map to the same canonical node. *)

INTERFACE MDDUniqueTable;
IMPORT MDD;

TYPE T <: REFANY;

PROCEDURE New(initialSize: CARDINAL := 256) : T;
PROCEDURE FindOrInsert(tbl: T; level: CARDINAL;
                       READONLY children: ARRAY OF MDD.T) : MDD.T;
PROCEDURE Count(tbl: T) : CARDINAL;

END MDDUniqueTable.
