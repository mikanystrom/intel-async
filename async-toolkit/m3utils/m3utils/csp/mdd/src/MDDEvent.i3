(* Copyright (c) 2026 Mika Nystrom. *)
(* SPDX-License-Identifier: Apache-2.0 *)

(* MDDEvent -- Kronecker-encoded events for saturation.

   Each event is a transition relation encoded as sparse matrices
   at the levels it affects.  At identity levels, the event passes
   through unchanged.

   Tau event: affects a single level (one process's internal transition).
   Sync event: affects two levels (channel synchronisation between
   two processes). *)

INTERFACE MDDEvent;

TYPE
  T <: REFANY;

  (* Sparse transition matrix: list of (from, to) pairs *)
  Entry = RECORD from, to: CARDINAL END;
  Matrix = REF ARRAY OF Entry;

PROCEDURE NewTauEvent(level: CARDINAL; matrix: Matrix) : T;
PROCEDURE NewSyncEvent(topLevel, botLevel: CARDINAL;
                       topMatrix, botMatrix: Matrix) : T;

PROCEDURE TopLevel(e: T) : CARDINAL;
PROCEDURE BotLevel(e: T) : CARDINAL;
PROCEDURE GetMatrix(e: T; level: CARDINAL) : Matrix;
PROCEDURE IsIdentity(e: T; level: CARDINAL) : BOOLEAN;

END MDDEvent.
