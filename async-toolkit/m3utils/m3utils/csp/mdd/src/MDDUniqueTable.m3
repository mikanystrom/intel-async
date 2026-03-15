(* Copyright (c) 2026 Mika Nystrom. *)
(* SPDX-License-Identifier: Apache-2.0 *)

(* MDDUniqueTable -- chained hash table for MDD node canonicalization.

   Hash is computed from children tags using XOR with rotation.
   Lookup compares children arrays element-by-element (reference
   equality suffices because children are themselves canonical). *)

MODULE MDDUniqueTable;
IMPORT MDD, MDDPrivate, Word;

TYPE
  Bucket = REF RECORD
    node : MDDPrivate.Node;
    next : Bucket;
  END;

REVEAL T = BRANDED "MDDUniqueTable" REF RECORD
    buckets : REF ARRAY OF Bucket;
    count   : CARDINAL;
    mask    : CARDINAL;
  END;

PROCEDURE New(initialSize: CARDINAL := 256) : T =
  VAR
    tbl := NEW(T);
    sz  : CARDINAL := 256;
  BEGIN
    WHILE sz < initialSize DO sz := sz * 2 END;
    tbl.buckets := NEW(REF ARRAY OF Bucket, sz);
    FOR i := 0 TO sz - 1 DO tbl.buckets[i] := NIL END;
    tbl.count := 0;
    tbl.mask  := sz - 1;
    RETURN tbl;
  END New;

PROCEDURE HashChildren(READONLY children: ARRAY OF MDD.T) : Word.T =
  VAR h : Word.T := 0;
  BEGIN
    FOR i := 0 TO LAST(children) DO
      VAR tag := NARROW(children[i], MDDPrivate.Node).tag;
      BEGIN
        h := Word.Xor(h, Word.Rotate(tag, i * 7));
      END;
    END;
    RETURN h;
  END HashChildren;

PROCEDURE ChildrenEqual(READONLY a, b: ARRAY OF MDD.T) : BOOLEAN =
  BEGIN
    IF NUMBER(a) # NUMBER(b) THEN RETURN FALSE END;
    FOR i := 0 TO LAST(a) DO
      IF a[i] # b[i] THEN RETURN FALSE END;
    END;
    RETURN TRUE;
  END ChildrenEqual;

PROCEDURE Rehash(tbl: T) =
  VAR
    oldBuckets := tbl.buckets;
    newSize    := NUMBER(oldBuckets^) * 2;
    newBuckets := NEW(REF ARRAY OF Bucket, newSize);
    newMask    := newSize - 1;
  BEGIN
    FOR i := 0 TO newSize - 1 DO newBuckets[i] := NIL END;
    FOR i := 0 TO LAST(oldBuckets^) DO
      VAR b := oldBuckets[i];
      BEGIN
        WHILE b # NIL DO
          VAR
            next := b.next;
            h    := Word.And(HashChildren(b.node.children^), newMask);
          BEGIN
            b.next := newBuckets[h];
            newBuckets[h] := b;
            b := next;
          END;
        END;
      END;
    END;
    tbl.buckets := newBuckets;
    tbl.mask    := newMask;
  END Rehash;

PROCEDURE FindOrInsert(tbl: T; level: CARDINAL;
                       READONLY children: ARRAY OF MDD.T) : MDD.T =
  VAR
    h := Word.And(HashChildren(children), tbl.mask);
    b := tbl.buckets[h];
  BEGIN
    (* Search existing entries *)
    WHILE b # NIL DO
      IF b.node.level = level AND
         ChildrenEqual(b.node.children^, children) THEN
        RETURN b.node;
      END;
      b := b.next;
    END;

    (* Not found: create new node *)
    VAR
      ch  := NEW(REF ARRAY OF MDD.T, NUMBER(children));
      node := NEW(MDDPrivate.Node);
    BEGIN
      ch^ := children;
      node.level    := level;
      node.children := ch;
      node.tag      := MDDPrivate.GetTag();

      VAR entry := NEW(Bucket);
      BEGIN
        entry.node := node;
        entry.next := tbl.buckets[h];
        tbl.buckets[h] := entry;
      END;

      INC(tbl.count);
      IF tbl.count > NUMBER(tbl.buckets^) * 2 THEN
        Rehash(tbl);
      END;

      RETURN node;
    END;
  END FindOrInsert;

PROCEDURE Count(tbl: T) : CARDINAL =
  BEGIN
    RETURN tbl.count;
  END Count;

BEGIN END MDDUniqueTable.
