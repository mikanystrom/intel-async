(* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE VaryBits;
IMPORT Mpz;
IMPORT FiniteInterval;
IMPORT Debug;
IMPORT CardSet;
IMPORT CardSetDef;
IMPORT CardArraySort;
FROM Fmt IMPORT F, Int;

TYPE Interval = FiniteInterval.T;

VAR MpzZero := Mpz.NewInt(0);

PROCEDURE MpzGetMsb(big : Mpz.T) : [-1 .. LAST(CARDINAL)] =
  (* Highest bit in the 2s complement representation that differs
     from the sign bit.  Returns -1 for 0 and -1. *)
  VAR sgn := Mpz.cmp(big, MpzZero);
  BEGIN
    IF sgn = 0 THEN
      RETURN -1
    ELSIF sgn > 0 THEN
      RETURN Mpz.sizeinbase(big, 2) - 1
    ELSE
      WITH k = Mpz.sizeinbase(big, 2) DO
        IF Mpz.tstbit(big, k - 1) = 0 THEN
          RETURN k - 1
        ELSE
          RETURN k - 2  (* e.g. -1: k=1, returns -1 *)
        END
      END
    END
  END MpzGetMsb;

PROCEDURE IntBits(big : Mpz.T) : T =
  VAR
    repBits := MAX(MpzGetMsb(big) + 1, 1);
    res     : T;
    sgn     := Mpz.cmp(big, MpzZero);
  BEGIN
    IF sgn < 0 THEN res.sign := Bit.One
    ELSE             res.sign := Bit.Zero
    END;

    FOR b := FIRST(res.x) TO LAST(res.x) DO
      res.x[b] := NEW(CardSetDef.T).init()
    END;

    FOR i := 0 TO repBits - 1 DO
      IF Mpz.tstbit(big, i) # 0 THEN
        EVAL res.x[Bit.One].insert(i)
      ELSE
        EVAL res.x[Bit.Zero].insert(i)
      END
    END;
    RETURN CleanMsbs(res)
  END IntBits;

PROCEDURE SetMax(c : CardSet.T) : [-1 .. LAST(CARDINAL) ] =
  (* really dumb way to do it *)
  VAR
    b : CARDINAL;
    max := -1;
  BEGIN
    WITH iter = c.iterate() DO
      WHILE iter.next(b) DO
        IF b > max THEN max := b END
      END
    END;
    RETURN max
  END SetMax;

PROCEDURE MaxDefinedBit(t : T) : [ -1 .. LAST(CARDINAL) ] =
  VAR
    max := -1;
  BEGIN
    FOR i := FIRST(Bit) TO LAST(Bit) DO
      max := MAX(max, SetMax(t.x[i]))
    END;
    RETURN max
  END MaxDefinedBit;

PROCEDURE FromInterval(fi : FiniteInterval.T) : T =
  BEGIN
    WITH loT   = IntBits(fi.lo),
         hiT   = IntBits(fi.hi),
         union = Union(loT, hiT) DO
      (* find the largest varying bit and set all the lower-order bits to
         vary *)
      WITH msb = SetMax(union.x[Bit.Vary]) DO
        FOR i := 0 TO msb - 1 DO
          EVAL union.x[Bit.Vary].insert(i);
          FOR b := Bit.Zero TO Bit.One DO
            EVAL union.x[b].delete(i)
          END
        END
      END;
      RETURN union
    END
  END FromInterval;

PROCEDURE ToInterval(t : T) : FiniteInterval.T =
  BEGIN
  END ToInterval;

PROCEDURE MaxVarying(t : T) : CARDINAL =
  BEGIN
  END MaxVarying;


PROCEDURE Union(a, b : T) : T =
  VAR
    c : T;
  BEGIN
    IF a.sign = b.sign THEN c.sign := a.sign ELSE c.sign := Bit.Vary END;

    (* bits already varying are still varying *)
    c.x[Bit.Vary] := a.x[Bit.Vary].union(b.x[Bit.Vary]);

    (* bits that are different are now varying *)
    WITH diffBits0 = a.x[Bit.Zero].intersection(b.x[Bit.One]),
         diffBits1 = a.x[Bit.One].intersection(b.x[Bit.Zero]),

         diffBits  = diffBits0.union(diffBits1) DO
      c.x[Bit.Vary] := c.x[Bit.Vary].union(diffBits)
    END;

    (* bits that exist in one but not in the other and are different 
       from the sign bit are varying *)

    VAR
      amax := MaxDefinedBit(a);
      bmax := MaxDefinedBit(b);
    PROCEDURE DoLeading(sml, big : T) =
      BEGIN
        FOR i := MaxDefinedBit(sml) + 1 TO MaxDefinedBit(big) DO
          IF big.x[Flip[a.sign]].member(i) THEN
            EVAL c.x[Bit.Vary].insert(i)
          END
        END
      END DoLeading;
    BEGIN
      IF amax > bmax THEN
        DoLeading(b, a);
      ELSIF bmax > amax THEN
        DoLeading(a, b)
      END
    END;
      
    FOR i := Bit.Zero TO Bit.One DO
      c.x[i] := a.x[i].union(b.x[i]).diff(c.x[Bit.Vary])
    END;

    RETURN CleanMsbs(c)
  END Union;

PROCEDURE AllDefinedBits(t : T) : CardSet.T =
  VAR
    res := NEW(CardSetDef.T).init();
  BEGIN
    FOR b := FIRST(Bit) TO LAST(Bit) DO
      res := res.unionD(t.x[b])
    END;
    RETURN res
  END AllDefinedBits;

PROCEDURE CleanMsbs(t : T) : T =
  (* delete leading bits that match the sign bit *)
  VAR
    diffSet := NEW(CardSetDef.T).init();
  BEGIN
    FOR b := FIRST(Bit) TO LAST(Bit) DO
      IF b # t.sign THEN
        diffSet := diffSet.union(t.x[b])
      END
    END;
    
    FOR i := SetMax(diffSet) + 1 TO SetMax(t.x[t.sign]) DO
      EVAL t.x[t.sign].delete(i)
    END;

    RETURN t

  END CleanMsbs;

PROCEDURE FormatSet(set : CardSet.T) : TEXT =
  VAR
    arr := NEW(REF ARRAY OF CARDINAL, set.size());
    c : CARDINAL;
    i := 0;
    res := "{ ";
    iter := set.iterate();
  BEGIN
    WHILE iter.next(c) DO
      arr[i] := c;
      INC(i)
    END;
    CardArraySort.Sort(arr^);
    FOR i := FIRST(arr^) TO LAST(arr^) DO
      res := res & Int(arr[i]) & " "
    END;
    RETURN res & "}"
  END FormatSet;
  
PROCEDURE Format(t : T) : TEXT =
  VAR
    res := F("[ VaryBits sign=%s ", BitName[t.sign]);
    
  BEGIN
    FOR i := FIRST(Bit) TO LAST(Bit) DO
      res := res & F("%s=%s ", BitName[i], FormatSet(t.x[i]));
    END;

    res := res & "]";
    RETURN res
  END Format;

PROCEDURE Min(t : T) : T =
  VAR
    res : T;
  BEGIN
    RETURN ForceX(t, Bit.Zero)
  END Min;

PROCEDURE Max(t : T) : T =
  VAR
    res : T;
  BEGIN
    RETURN ForceX(t, Bit.One)
  END Max;

PROCEDURE ForceX(t : T; to : Bit) : T =
  VAR
    res : T;
  BEGIN
    <*ASSERT to # Bit.Vary*>
    res.sign := t.sign;
    IF res.sign = Bit.Vary THEN res.sign := Flip[to] END;


    res.x[to] := t.x[to].union(t.x[Bit.Vary]);
    res.x[Bit.Vary] := NEW(CardSetDef.T).init(); (* empty *)
    res.x[Flip[to]] := t.x[Flip[to]];
    RETURN CleanMsbs(res)
  END ForceX;
  
BEGIN END VaryBits.
