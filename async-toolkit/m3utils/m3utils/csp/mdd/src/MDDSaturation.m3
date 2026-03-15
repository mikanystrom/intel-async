(* Copyright (c) 2026 Mika Nystrom. *)
(* SPDX-License-Identifier: Apache-2.0 *)

(* MDDSaturation -- saturation algorithm for MDD-based reachability.

   Implements the Ciardo-Marmorstein-Siminiceanu saturation algorithm.
   Events are partitioned by their top level and fired bottom-up.
   At each level, events whose top level matches are fired repeatedly
   until a fixed point is reached (the level is "saturated").

   A saturation cache records nodes that have already been fully
   saturated.  Since hash-consing gives canonical nodes, we can
   check by identity whether a node has already been processed. *)

MODULE MDDSaturation;
IMPORT MDD, MDDEvent, Word;

(* ---- Partition events by top level ---- *)

TYPE
  EventArray = REF ARRAY OF MDDEvent.T;
  LevelEvents = REF ARRAY OF EventArray;

PROCEDURE PartitionByTopLevel(events: EventList) : LevelEvents =
  VAR
    n := MDD.NumLevels();
    counts := NEW(REF ARRAY OF CARDINAL, n);
    result := NEW(LevelEvents, n);
  BEGIN
    FOR k := 0 TO n - 1 DO counts[k] := 0 END;
    FOR i := 0 TO LAST(events^) DO
      INC(counts[MDDEvent.TopLevel(events[i])]);
    END;
    FOR k := 0 TO n - 1 DO
      result[k] := NEW(EventArray, counts[k]);
      counts[k] := 0;
    END;
    FOR i := 0 TO LAST(events^) DO
      VAR top := MDDEvent.TopLevel(events[i]);
      BEGIN
        result[top][counts[top]] := events[i];
        INC(counts[top]);
      END;
    END;
    RETURN result;
  END PartitionByTopLevel;

(* ---- MakeNodeWithChild: create a node with only child[idx] = val ---- *)

PROCEDURE MakeNodeWithChild(level: CARDINAL;
                            idx: CARDINAL; val: MDD.T) : MDD.T =
  VAR
    dom := MDD.Domain(level);
    ch  := NEW(REF ARRAY OF MDD.T, dom);
  BEGIN
    FOR i := 0 TO dom - 1 DO ch[i] := MDD.Zero() END;
    ch[idx] := val;
    RETURN MDD.MakeNode(level, ch^);
  END MakeNodeWithChild;

(* ---- Saturation cache ---- *)

(* Direct-mapped cache: saturated[hash(node) MOD size] = node.
   If the cached value matches the node (reference equality),
   the node is already saturated. *)

TYPE
  SatCacheEntry = RECORD
    node : MDD.T;
  END;

VAR
  levEvents : LevelEvents := NIL;
  satCache  : REF ARRAY OF SatCacheEntry := NIL;
  satMask   : CARDINAL := 0;

PROCEDURE InitSatCache() =
  CONST Size = 65536;
  BEGIN
    satCache := NEW(REF ARRAY OF SatCacheEntry, Size);
    FOR i := 0 TO Size - 1 DO satCache[i].node := NIL END;
    satMask := Size - 1;
  END InitSatCache;

PROCEDURE IsSaturated(node: MDD.T) : BOOLEAN =
  VAR h := Word.And(MDD.Hash(node), satMask);
  BEGIN
    RETURN satCache[h].node = node;
  END IsSaturated;

PROCEDURE MarkSaturated(node: MDD.T) =
  VAR h := Word.And(MDD.Hash(node), satMask);
  BEGIN
    satCache[h].node := node;
  END MarkSaturated;

(* ---- Saturation core ---- *)

PROCEDURE Saturate(node: MDD.T; level: CARDINAL) : MDD.T =
  VAR dom : CARDINAL; result : MDD.T;
  BEGIN
    IF MDD.IsEmpty(node) THEN RETURN node END;
    IF IsSaturated(node) THEN RETURN node END;

    IF level = 0 THEN
      result := SaturateLocal(node, level);
      MarkSaturated(result);
      RETURN result;
    END;

    (* Recursively saturate all children *)
    dom := MDD.Domain(level);
    VAR
      ch      := NEW(REF ARRAY OF MDD.T, dom);
      changed := FALSE;
    BEGIN
      FOR i := 0 TO dom - 1 DO
        VAR
          old := MDD.NodeChild(node, i);
          sat := Saturate(old, level - 1);
        BEGIN
          ch[i] := sat;
          IF sat # old THEN changed := TRUE END;
        END;
      END;
      IF changed THEN
        node := MDD.MakeNode(level, ch^);
      END;
    END;

    (* Fire events at this level until fixed point *)
    result := SaturateLocal(node, level);
    MarkSaturated(result);
    RETURN result;
  END Saturate;

PROCEDURE SaturateLocal(node: MDD.T; level: CARDINAL) : MDD.T =
  VAR old : MDD.T;
  BEGIN
    REPEAT
      old := node;
      IF levEvents # NIL AND level < NUMBER(levEvents^) THEN
        VAR evts := levEvents[level];
        BEGIN
          FOR i := 0 TO LAST(evts^) DO
            node := SatFire(node, evts[i], level);
          END;
        END;
      END;
    UNTIL node = old;
    RETURN node;
  END SaturateLocal;

PROCEDURE SatFire(node: MDD.T; event: MDDEvent.T;
                  level: CARDINAL) : MDD.T =
  VAR matrix : MDDEvent.Matrix;
  BEGIN
    IF MDD.IsEmpty(node) THEN RETURN node END;

    matrix := MDDEvent.GetMatrix(event, level);

    IF level = MDDEvent.BotLevel(event) THEN
      (* Bottom of event: apply matrix locally *)
      RETURN ApplyMatrix(node, matrix, level);
    ELSIF MDDEvent.IsIdentity(event, level) THEN
      (* Identity level: recurse on each child, then re-saturate
         at this level only (children are already saturated). *)
      VAR
        dom     := MDD.Domain(level);
        ch      := NEW(REF ARRAY OF MDD.T, dom);
        changed := FALSE;
      BEGIN
        FOR i := 0 TO dom - 1 DO
          VAR
            old := MDD.NodeChild(node, i);
            fired := SatFire(old, event, level - 1);
          BEGIN
            ch[i] := fired;
            IF fired # old THEN changed := TRUE END;
          END;
        END;
        IF NOT changed THEN RETURN node END;
        VAR newNode := MDD.MakeNode(level, ch^);
            result  := SaturateLocal(newNode, level);
        BEGIN
          MarkSaturated(result);
          RETURN result;
        END;
      END;
    ELSE
      (* Top level of sync event: apply top matrix, recurse down *)
      VAR
        result := MDD.Zero();
      BEGIN
        FOR i := 0 TO LAST(matrix^) DO
          VAR
            from := matrix[i].from;
            to   := matrix[i].to;
            child := MDD.NodeChild(node, from);
          BEGIN
            IF NOT MDD.IsEmpty(child) THEN
              VAR fired := RecFire(child, event, level - 1);
              BEGIN
                IF NOT MDD.IsEmpty(fired) THEN
                  result := MDD.Union(result,
                              MakeNodeWithChild(level, to, fired));
                END;
              END;
            END;
          END;
        END;
        IF MDD.IsEmpty(result) THEN RETURN node END;
        VAR merged := MDD.Union(node, result);
        BEGIN
          IF merged = node THEN RETURN node END;  (* no new states *)
          VAR sat := SaturateLocal(merged, level);
          BEGIN
            MarkSaturated(sat);
            RETURN sat;
          END;
        END;
      END;
    END;
  END SatFire;

PROCEDURE RecFire(node: MDD.T; event: MDDEvent.T;
                  level: CARDINAL) : MDD.T =
  VAR matrix : MDDEvent.Matrix;
  BEGIN
    IF MDD.IsEmpty(node) THEN RETURN node END;

    IF level = MDDEvent.BotLevel(event) THEN
      (* Apply bottom matrix: produce only the fired states *)
      matrix := MDDEvent.GetMatrix(event, level);
      VAR applied := ApplyMatrixOnly(node, matrix, level);
      BEGIN
        RETURN Saturate(applied, level);
      END;
    ELSE
      (* Identity level: recurse on each child *)
      VAR
        dom     := MDD.Domain(level);
        ch      := NEW(REF ARRAY OF MDD.T, dom);
        changed := FALSE;
      BEGIN
        FOR i := 0 TO dom - 1 DO
          VAR
            old   := MDD.NodeChild(node, i);
            fired := RecFire(old, event, level - 1);
          BEGIN
            ch[i] := fired;
            IF fired # old THEN changed := TRUE END;
          END;
        END;
        IF NOT changed THEN RETURN node END;
        RETURN MDD.MakeNode(level, ch^);
      END;
    END;
  END RecFire;

PROCEDURE ApplyMatrix(node: MDD.T; matrix: MDDEvent.Matrix;
                      level: CARDINAL) : MDD.T =
  (* Apply a transition matrix at a single level.
     Keeps old states and adds new ones (old ∪ fired). *)
  VAR result := node;
  BEGIN
    IF matrix = NIL THEN RETURN node END;
    FOR i := 0 TO LAST(matrix^) DO
      VAR
        from  := matrix[i].from;
        to    := matrix[i].to;
        child := MDD.NodeChild(node, from);
      BEGIN
        IF NOT MDD.IsEmpty(child) THEN
          result := MDD.Union(result,
                      MakeNodeWithChild(level, to, child));
        END;
      END;
    END;
    RETURN result;
  END ApplyMatrix;

PROCEDURE ApplyMatrixOnly(node: MDD.T; matrix: MDDEvent.Matrix;
                          level: CARDINAL) : MDD.T =
  (* Apply a transition matrix, returning only the fired states.
     Does NOT include the original node in the result. *)
  VAR result := MDD.Zero();
  BEGIN
    IF matrix = NIL THEN RETURN MDD.Zero() END;
    FOR i := 0 TO LAST(matrix^) DO
      VAR
        from  := matrix[i].from;
        to    := matrix[i].to;
        child := MDD.NodeChild(node, from);
      BEGIN
        IF NOT MDD.IsEmpty(child) THEN
          result := MDD.Union(result,
                      MakeNodeWithChild(level, to, child));
        END;
      END;
    END;
    RETURN result;
  END ApplyMatrixOnly;

(* ---- Public interface ---- *)

PROCEDURE ComputeReachable(initial: MDD.T; events: EventList) : MDD.T =
  BEGIN
    levEvents := PartitionByTopLevel(events);
    InitSatCache();
    VAR result := Saturate(initial, MDD.NumLevels() - 1);
    BEGIN
      levEvents := NIL;
      satCache := NIL;
      RETURN result;
    END;
  END ComputeReachable;

PROCEDURE HasSuccessor(reached: MDD.T; events: EventList) : MDD.T =
  VAR
    result := MDD.Zero();
    n      := MDD.NumLevels();
  BEGIN
    FOR i := 0 TO LAST(events^) DO
      VAR
        e    := events[i];
        top  := MDDEvent.TopLevel(e);
        bot  := MDDEvent.BotLevel(e);
        succ := HasSuccForEvent(reached, e, n - 1, top, bot);
      BEGIN
        result := MDD.Union(result, succ);
      END;
    END;
    RETURN result;
  END HasSuccessor;

PROCEDURE HasSuccForEvent(node: MDD.T; event: MDDEvent.T;
                          level: CARDINAL;
                          top, bot: CARDINAL) : MDD.T =
  BEGIN
    IF MDD.IsEmpty(node) THEN RETURN MDD.Zero() END;
    IF level = LAST(CARDINAL) THEN RETURN node END;

    IF level > top THEN
      VAR
        dom     := MDD.Domain(level);
        ch      := NEW(REF ARRAY OF MDD.T, dom);
        changed := FALSE;
      BEGIN
        FOR i := 0 TO dom - 1 DO
          VAR
            old := MDD.NodeChild(node, i);
            sub := HasSuccForEvent(old, event, level - 1, top, bot);
          BEGIN
            ch[i] := sub;
            IF sub # old THEN changed := TRUE END;
          END;
        END;
        IF NOT changed THEN RETURN node END;
        RETURN MDD.MakeNode(level, ch^);
      END;
    ELSIF level = top OR level = bot THEN
      VAR
        matrix := MDDEvent.GetMatrix(event, level);
        dom    := MDD.Domain(level);
        ch     := NEW(REF ARRAY OF MDD.T, dom);
      BEGIN
        FOR i := 0 TO dom - 1 DO ch[i] := MDD.Zero() END;
        IF matrix # NIL THEN
          FOR i := 0 TO LAST(matrix^) DO
            VAR
              from := matrix[i].from;
              child := MDD.NodeChild(node, from);
            BEGIN
              IF NOT MDD.IsEmpty(child) THEN
                IF level = bot THEN
                  ch[from] := MDD.Union(ch[from], child);
                ELSE
                  VAR sub := HasSuccForEvent(child, event,
                                             level - 1, top, bot);
                  BEGIN
                    ch[from] := MDD.Union(ch[from], sub);
                  END;
                END;
              END;
            END;
          END;
        END;
        RETURN MDD.MakeNode(level, ch^);
      END;
    ELSE
      VAR
        dom     := MDD.Domain(level);
        ch      := NEW(REF ARRAY OF MDD.T, dom);
        changed := FALSE;
      BEGIN
        FOR i := 0 TO dom - 1 DO
          VAR
            old := MDD.NodeChild(node, i);
            sub := HasSuccForEvent(old, event, level - 1, top, bot);
          BEGIN
            ch[i] := sub;
            IF sub # old THEN changed := TRUE END;
          END;
        END;
        IF NOT changed THEN RETURN node END;
        RETURN MDD.MakeNode(level, ch^);
      END;
    END;
  END HasSuccForEvent;

BEGIN END MDDSaturation.
