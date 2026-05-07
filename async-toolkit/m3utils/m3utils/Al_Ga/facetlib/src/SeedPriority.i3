(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE SeedPriority;

(* Priority for seed selection in region growing.
   Lower value = higher priority.  We use negative unclaimed neighbor
   count so that vertices with the most unclaimed neighbors are
   selected first. *)

TYPE T = INTEGER;

CONST Brand = "SeedPriority";

PROCEDURE Compare(p1, p2: T): [-1..1];

END SeedPriority.
