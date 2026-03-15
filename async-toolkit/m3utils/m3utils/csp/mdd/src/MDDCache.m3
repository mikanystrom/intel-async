(* Copyright (c) 2026 Mika Nystrom. *)
(* SPDX-License-Identifier: Apache-2.0 *)

(* MDDCache -- direct-mapped operation cache.

   Each slot stores (a, b, result) keyed by hash of (a.tag, b.tag).
   Collisions simply evict the old entry (no chaining). *)

MODULE MDDCache;
IMPORT MDD, MDDPrivate, Word;

TYPE
  Slot = RECORD
    a, b, result : MDD.T;
    valid        : BOOLEAN;
  END;

REVEAL T = BRANDED "MDDCache" REF RECORD
    slots : REF ARRAY OF Slot;
    mask  : CARDINAL;
  END;

PROCEDURE New(size: CARDINAL := 65536) : T =
  VAR
    cache := NEW(T);
    sz    : CARDINAL := 1024;
  BEGIN
    WHILE sz < size DO sz := sz * 2 END;
    cache.slots := NEW(REF ARRAY OF Slot, sz);
    FOR i := 0 TO sz - 1 DO cache.slots[i].valid := FALSE END;
    cache.mask := sz - 1;
    RETURN cache;
  END New;

PROCEDURE SlotHash(a, b: MDD.T) : Word.T =
  BEGIN
    RETURN Word.Xor(NARROW(a, MDDPrivate.Node).tag,
                    Word.Rotate(NARROW(b, MDDPrivate.Node).tag, 16));
  END SlotHash;

PROCEDURE Get(cache: T; a, b: MDD.T; VAR result: MDD.T) : BOOLEAN =
  VAR
    idx := Word.And(SlotHash(a, b), cache.mask);
  BEGIN
    WITH s = cache.slots[idx] DO
      IF s.valid AND s.a = a AND s.b = b THEN
        result := s.result;
        RETURN TRUE;
      END;
    END;
    RETURN FALSE;
  END Get;

PROCEDURE Put(cache: T; a, b, result: MDD.T) =
  VAR
    idx := Word.And(SlotHash(a, b), cache.mask);
  BEGIN
    WITH s = cache.slots[idx] DO
      s.a      := a;
      s.b      := b;
      s.result := result;
      s.valid  := TRUE;
    END;
  END Put;

PROCEDURE Clear(cache: T) =
  BEGIN
    FOR i := 0 TO LAST(cache.slots^) DO
      cache.slots[i].valid := FALSE;
      cache.slots[i].a := NIL;
      cache.slots[i].b := NIL;
      cache.slots[i].result := NIL;
    END;
  END Clear;

BEGIN END MDDCache.
