(* Copyright (c) 2026 Mika Nystrom. *)
(* SPDX-License-Identifier: Apache-2.0 *)

(* MDDImpl -- core MDD operations.

   Exports MDD and MDDPrivate.  Manages the global forest state:
   terminal singletons, level descriptors, and operation caches. *)

MODULE MDDImpl EXPORTS MDD, MDDPrivate;
IMPORT MDDLevel, MDDCache, Word, Fmt;

VAR
  zeroNode, oneNode : Terminal;
  nextTag           : CARDINAL := 0;
  levels            : REF ARRAY OF MDDLevel.T := NIL;
  nLevels           : CARDINAL := 0;
  unionCache        : MDDCache.T := NIL;
  interCache        : MDDCache.T := NIL;
  diffCache         : MDDCache.T := NIL;

(* ---- MDDPrivate exports ---- *)

PROCEDURE GetTag() : CARDINAL =
  VAR t : CARDINAL;
  BEGIN
    t := nextTag;
    INC(nextTag);
    RETURN t;
  END GetTag;

(* ---- Terminals ---- *)

PROCEDURE One() : T =
  BEGIN RETURN oneNode END One;

PROCEDURE Zero() : T =
  BEGIN RETURN zeroNode END Zero;

(* ---- Forest setup ---- *)

PROCEDURE SetLevels(n: CARDINAL; READONLY domains: ARRAY OF CARDINAL) =
  BEGIN
    <* ASSERT NUMBER(domains) = n *>
    nLevels := n;
    levels  := NEW(REF ARRAY OF MDDLevel.T, n);
    FOR i := 0 TO n - 1 DO
      MDDLevel.Init(levels[i], domains[i]);
    END;
    unionCache := MDDCache.New();
    interCache := MDDCache.New();
    diffCache  := MDDCache.New();
  END SetLevels;

PROCEDURE NumLevels() : CARDINAL =
  BEGIN RETURN nLevels END NumLevels;

PROCEDURE Domain(level: CARDINAL) : CARDINAL =
  BEGIN RETURN levels[level].domain END Domain;

(* ---- Node construction (quasi-reduced) ---- *)

PROCEDURE MakeNode(level: CARDINAL;
                   READONLY children: ARRAY OF T) : T =
  BEGIN
    <* ASSERT level < nLevels *>
    <* ASSERT NUMBER(children) = levels[level].domain *>
    (* Check if all children are Zero -> return Zero *)
    VAR allZero := TRUE;
    BEGIN
      FOR i := 0 TO LAST(children) DO
        IF children[i] # zeroNode THEN allZero := FALSE; EXIT END;
      END;
      IF allZero THEN RETURN zeroNode END;
    END;
    (* Quasi-reduced: keep node even if all children identical *)
    RETURN MDDLevel.FindOrInsert(levels[level], level, children);
  END MakeNode;

PROCEDURE Singleton(READONLY values: ARRAY OF CARDINAL) : T =
  VAR node : T;
  BEGIN
    <* ASSERT NUMBER(values) = nLevels *>
    node := oneNode;
    FOR k := 0 TO nLevels - 1 DO
      VAR
        dom := levels[k].domain;
        ch  := NEW(REF ARRAY OF T, dom);
      BEGIN
        FOR i := 0 TO dom - 1 DO ch[i] := zeroNode END;
        <* ASSERT values[k] < dom *>
        ch[values[k]] := node;
        node := MakeNode(k, ch^);
      END;
    END;
    RETURN node;
  END Singleton;

(* ---- Set operations ---- *)

PROCEDURE Union(a, b: T) : T =
  VAR cached : T;
  BEGIN
    IF a = zeroNode THEN RETURN b END;
    IF b = zeroNode THEN RETURN a END;
    IF a = b        THEN RETURN a END;
    IF unionCache # NIL AND MDDCache.Get(unionCache, a, b, cached) THEN
      RETURN cached;
    END;
    VAR
      na := NARROW(a, Node);
      nb := NARROW(b, Node);
    BEGIN
      <* ASSERT na.level = nb.level *>
      VAR
        dom := levels[na.level].domain;
        ch  := NEW(REF ARRAY OF T, dom);
      BEGIN
        FOR i := 0 TO dom - 1 DO
          ch[i] := Union(na.children[i], nb.children[i]);
        END;
        VAR result := MakeNode(na.level, ch^);
        BEGIN
          IF unionCache # NIL THEN
            MDDCache.Put(unionCache, a, b, result);
          END;
          RETURN result;
        END;
      END;
    END;
  END Union;

PROCEDURE Intersection(a, b: T) : T =
  VAR cached : T;
  BEGIN
    IF a = zeroNode THEN RETURN zeroNode END;
    IF b = zeroNode THEN RETURN zeroNode END;
    IF a = b        THEN RETURN a END;
    IF a = oneNode  THEN RETURN b END;
    IF b = oneNode  THEN RETURN a END;
    IF interCache # NIL AND MDDCache.Get(interCache, a, b, cached) THEN
      RETURN cached;
    END;
    VAR
      na := NARROW(a, Node);
      nb := NARROW(b, Node);
    BEGIN
      <* ASSERT na.level = nb.level *>
      VAR
        dom := levels[na.level].domain;
        ch  := NEW(REF ARRAY OF T, dom);
      BEGIN
        FOR i := 0 TO dom - 1 DO
          ch[i] := Intersection(na.children[i], nb.children[i]);
        END;
        VAR result := MakeNode(na.level, ch^);
        BEGIN
          IF interCache # NIL THEN
            MDDCache.Put(interCache, a, b, result);
          END;
          RETURN result;
        END;
      END;
    END;
  END Intersection;

PROCEDURE Difference(a, b: T) : T =
  VAR cached : T;
  BEGIN
    IF a = zeroNode THEN RETURN zeroNode END;
    IF b = zeroNode THEN RETURN a END;
    IF a = b        THEN RETURN zeroNode END;
    IF diffCache # NIL AND MDDCache.Get(diffCache, a, b, cached) THEN
      RETURN cached;
    END;
    VAR
      na := NARROW(a, Node);
      nb := NARROW(b, Node);
    BEGIN
      <* ASSERT na.level = nb.level *>
      VAR
        dom := levels[na.level].domain;
        ch  := NEW(REF ARRAY OF T, dom);
      BEGIN
        FOR i := 0 TO dom - 1 DO
          ch[i] := Difference(na.children[i], nb.children[i]);
        END;
        VAR result := MakeNode(na.level, ch^);
        BEGIN
          IF diffCache # NIL THEN
            MDDCache.Put(diffCache, a, b, result);
          END;
          RETURN result;
        END;
      END;
    END;
  END Difference;

PROCEDURE IsEmpty(a: T) : BOOLEAN =
  BEGIN RETURN a = zeroNode END IsEmpty;

PROCEDURE Equal(a, b: T) : BOOLEAN =
  BEGIN RETURN a = b END Equal;

(* ---- Node inspection ---- *)

PROCEDURE NodeLevel(a: T) : INTEGER =
  BEGIN RETURN NARROW(a, Node).level END NodeLevel;

PROCEDURE NodeChild(a: T; i: CARDINAL) : T =
  VAR n := NARROW(a, Node);
  BEGIN
    RETURN n.children[i];
  END NodeChild;

(* ---- Statistics ---- *)

PROCEDURE SizeWalk(a: T; visited: REF ARRAY OF BOOLEAN;
                   VAR count: CARDINAL) =
  BEGIN
    IF a = zeroNode OR a = oneNode THEN RETURN END;
    VAR n := NARROW(a, Node);
    BEGIN
      IF visited[n.tag] THEN RETURN END;
      visited[n.tag] := TRUE;
      INC(count);
      FOR i := 0 TO LAST(n.children^) DO
        SizeWalk(n.children[i], visited, count);
      END;
    END;
  END SizeWalk;

PROCEDURE Size(a: T) : CARDINAL =
  VAR
    count   : CARDINAL := 0;
    visited := NEW(REF ARRAY OF BOOLEAN, nextTag);
  BEGIN
    FOR i := 0 TO nextTag - 1 DO visited[i] := FALSE END;
    SizeWalk(a, visited, count);
    RETURN count;
  END Size;

PROCEDURE NodeCount() : CARDINAL =
  VAR total : CARDINAL := 0;
  BEGIN
    IF levels = NIL THEN RETURN 0 END;
    FOR k := 0 TO nLevels - 1 DO
      total := total + MDDLevel.Count(levels[k]);
    END;
    RETURN total;
  END NodeCount;

PROCEDURE Hash(a: T) : Word.T =
  BEGIN RETURN NARROW(a, Node).tag END Hash;

PROCEDURE ClearCaches() =
  BEGIN
    IF unionCache # NIL THEN MDDCache.Clear(unionCache) END;
    IF interCache # NIL THEN MDDCache.Clear(interCache) END;
    IF diffCache  # NIL THEN MDDCache.Clear(diffCache)  END;
  END ClearCaches;

PROCEDURE Format(a: T) : TEXT =
  VAR n := NARROW(a, Node);
  BEGIN
    IF a = zeroNode THEN RETURN "Zero" END;
    IF a = oneNode  THEN RETURN "One"  END;
    VAR
      s := "L" & Fmt.Int(n.level) & "[";
    BEGIN
      FOR i := 0 TO LAST(n.children^) DO
        IF i > 0 THEN s := s & "," END;
        s := s & Format(n.children[i]);
      END;
      RETURN s & "]";
    END;
  END Format;

(* ---- Module initialization ---- *)

BEGIN
  zeroNode := NEW(Terminal);
  zeroNode.level    := -1;
  zeroNode.children := NIL;
  zeroNode.tag      := GetTag();
  zeroNode.value    := FALSE;

  oneNode := NEW(Terminal);
  oneNode.level    := -1;
  oneNode.children := NIL;
  oneNode.tag      := GetTag();
  oneNode.value    := TRUE;
END MDDImpl.
