(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE SeedPriority;

PROCEDURE Compare(p1, p2: T): [-1..1] =
  BEGIN
    IF    p1 < p2 THEN RETURN -1;
    ELSIF p1 > p2 THEN RETURN  1;
    ELSE                RETURN  0;
    END;
  END Compare;

BEGIN
END SeedPriority.
