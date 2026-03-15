(* Copyright (c) 2026 Mika Nystrom. *)
(* SPDX-License-Identifier: Apache-2.0 *)

(* MDDLevel -- descriptor for one level of the MDD forest. *)

INTERFACE MDDLevel;
IMPORT MDD, MDDUniqueTable;

TYPE
  T = RECORD
    domain : CARDINAL;
    table  : MDDUniqueTable.T;
  END;

PROCEDURE Init(VAR self: T; domain: CARDINAL);
PROCEDURE FindOrInsert(VAR self: T; level: CARDINAL;
                       READONLY children: ARRAY OF MDD.T) : MDD.T;
PROCEDURE Count(VAR self: T) : CARDINAL;

END MDDLevel.
