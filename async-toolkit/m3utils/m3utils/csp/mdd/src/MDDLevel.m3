(* Copyright (c) 2026 Mika Nystrom. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE MDDLevel;
IMPORT MDD, MDDUniqueTable;

PROCEDURE Init(VAR self: T; domain: CARDINAL) =
  BEGIN
    self.domain := domain;
    self.table  := MDDUniqueTable.New();
  END Init;

PROCEDURE FindOrInsert(VAR self: T; level: CARDINAL;
                       READONLY children: ARRAY OF MDD.T) : MDD.T =
  BEGIN
    RETURN MDDUniqueTable.FindOrInsert(self.table, level, children);
  END FindOrInsert;

PROCEDURE Count(VAR self: T) : CARDINAL =
  BEGIN
    RETURN MDDUniqueTable.Count(self.table);
  END Count;

BEGIN END MDDLevel.
