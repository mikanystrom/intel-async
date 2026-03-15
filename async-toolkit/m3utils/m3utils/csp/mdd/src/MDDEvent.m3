(* Copyright (c) 2026 Mika Nystrom. *)
(* SPDX-License-Identifier: Apache-2.0 *)

(* MDDEvent -- Kronecker-encoded events for saturation.

   A tau event affects one MDD level: its matrix says which local
   states can transition to which other local states.

   A sync event affects two MDD levels (the two processes that
   synchronise on a channel).  All levels between them are identity. *)

MODULE MDDEvent;

REVEAL T = BRANDED "MDDEvent" REF RECORD
    top, bot  : CARDINAL;
    topMatrix : Matrix;
    botMatrix : Matrix;       (* NIL for tau events *)
  END;

PROCEDURE NewTauEvent(level: CARDINAL; matrix: Matrix) : T =
  VAR e := NEW(T);
  BEGIN
    e.top       := level;
    e.bot       := level;
    e.topMatrix := matrix;
    e.botMatrix := NIL;
    RETURN e;
  END NewTauEvent;

PROCEDURE NewSyncEvent(topLevel, botLevel: CARDINAL;
                       topMatrix, botMatrix: Matrix) : T =
  VAR e := NEW(T);
  BEGIN
    <* ASSERT topLevel > botLevel *>
    e.top       := topLevel;
    e.bot       := botLevel;
    e.topMatrix := topMatrix;
    e.botMatrix := botMatrix;
    RETURN e;
  END NewSyncEvent;

PROCEDURE TopLevel(e: T) : CARDINAL =
  BEGIN RETURN e.top END TopLevel;

PROCEDURE BotLevel(e: T) : CARDINAL =
  BEGIN RETURN e.bot END BotLevel;

PROCEDURE GetMatrix(e: T; level: CARDINAL) : Matrix =
  BEGIN
    IF level = e.top THEN RETURN e.topMatrix END;
    IF level = e.bot AND e.botMatrix # NIL THEN RETURN e.botMatrix END;
    RETURN NIL;
  END GetMatrix;

PROCEDURE IsIdentity(e: T; level: CARDINAL) : BOOLEAN =
  BEGIN
    RETURN level # e.top AND (level # e.bot OR e.botMatrix = NIL);
  END IsIdentity;

BEGIN END MDDEvent.
