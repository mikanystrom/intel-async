(* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE Main;

(* genpg 
   Policy-Group recognizer RTL generator.
   Author : Mika Nystrom <mika.nystroem@intel.com>
*)

IMPORT XMLParse;
IMPORT CSVParse;
IMPORT Rd, FileRd;
IMPORT Debug;
FROM Fmt IMPORT F;
IMPORT Fmt;
IMPORT Scan;
IMPORT Text;
IMPORT Pathname;
IMPORT Lex, FloatMode;
IMPORT SBAddress AS Address;
IMPORT Range;
IMPORT SortedRangeRefTbl AS SortedRangeTbl;
IMPORT TextRangeTblTbl;
IMPORT Word;
IMPORT ParseParams;
IMPORT Stdio;
IMPORT SortedRangeTextTbl;
IMPORT RefList;
IMPORT Wr, FileWr, OSError;
IMPORT Thread;
IMPORT CitTextUtils AS TextUtils;
IMPORT TextWr;
IMPORT AL;
IMPORT TextTextTbl, TextSeq;
IMPORT Wx;
IMPORT TextRd, PgToolSVTemplates, Bundle;
IMPORT CharSeq;
IMPORT Process;
IMPORT Params;
IMPORT PgField;
IMPORT PgCRIF;

<*FATAL Thread.Alerted*>

CONST MaxBitsAllowed = BITSIZE(Address.T)-1;

CONST TE = Text.Equal;

      Usage =
        "[-h|--help] [-allminterms] [(-D|--bind) <tag> <value>]* [-M|--module <module-name>] [-sv <sv-output-name>] [-T|--template HLP|MST|DEFAULT|<sv-template-name>] [--display-template] [-bits <address-bits>] [-[no]skipholes] [-elimoverlaps] [-defpgnm <PG_DEFAULT-name>] [-G|--policygroups <n> <pg(0)-name>...<pg(n-1)-name>] ([-crif <input-CRIF-name>] | [-csv] <input-CSV-name>)";


PROCEDURE DoUsage() : TEXT =
  BEGIN
    RETURN
      Params.Get(0) & ": usage: " & Usage
  END DoUsage;
  
VAR rd : Rd.T;

TYPE  Field = PgField.T;

VAR doDebug := Debug.GetLevel() >= 10;

PROCEDURE MapPGnameToNumber(str : TEXT) : CARDINAL =
  BEGIN
    IF TE(str, PgDefaultName) THEN
      RETURN DefaultIdx
    END;

    FOR i := FIRST(PolicyGroupArr^) TO LAST(PolicyGroupArr^) DO
      IF TE(str, PolicyGroupArr[i]) THEN RETURN i END
    END;

    Debug.Error("MapPGnameToNumber : Unknown policy group \"" & str & "\" : cannot map");
    <*ASSERT FALSE*>
  END MapPGnameToNumber;
  
PROCEDURE Int16(x : INTEGER) : TEXT =
  BEGIN RETURN Fmt.Int(x, base := 16) END Int16;

VAR
  pgs := NEW(TextRangeTblTbl.Default).init();
  allRanges : SortedRangeTbl.T := NewRL();
  reverse := NEW(SortedRangeTextTbl.Default).init();

PROCEDURE NewRL() : SortedRangeTbl.T =
  BEGIN RETURN NEW(SortedRangeTbl.Default).init() END NewRL;

PROCEDURE InsertOrdered(p : SortedRangeTbl.T; READONLY r : Range.T) : BOOLEAN =
  VAR
    ok := TRUE;
      iterU := p.iterateOrdered(up := TRUE);
      iterD := p.iterateOrdered(up := FALSE);
      nxt, prv : Range.T;
      nxtG, prvG : REFANY;
  BEGIN
    (* check for clean and dirty overlap cases here and behave
       accordingly
       
       note that range comparison is on range.lo *)
    
    iterU.seek(r); 
    IF iterU.next(nxt, nxtG) THEN
      <*ASSERT nxt.lo >= r.lo*>
      IF r.lo + r.len > nxt.lo THEN
        (* found an overlap *)
        Debug.Error(F("InsertOrdered : Register overlap %s %s <-> %s %s", r.userData, Range.Format(r), nxt.userData, Range.Format(nxt)), exit := FALSE);
        ok := FALSE
      END
    END;
    iterD.seek(r);
    IF iterD.next(prv, prvG) THEN
      <*ASSERT prv.lo <= r.lo*>
      IF prv.lo + prv.len > r.lo THEN
        (* found an overlap *)
        Debug.Error(F("InsertOrdered : Register overlap %s %s <-> %s %s", prv.userData, Range.Format(prv), r.userData, Range.Format(r)), exit := FALSE);
        ok := FALSE
      END
    END;
    
    EVAL p.put(r, r.group);
    
    RETURN ok
  END InsertOrdered;
  
VAR totLen := 0;

    widest := ARRAY Field OF CARDINAL { 0 , .. };

VAR
  procBufOK := TRUE;
  
PROCEDURE ProcessBuf(b : ARRAY Field OF TEXT; lenPerByte : CARDINAL) =

  (* lenPerByte 8 if size in bits, 1 if size in bytes *)
  VAR
    rl : SortedRangeTbl.T;
    len : CARDINAL;
  BEGIN
    IF doDebug AND Debug.GetLevel() >= 100 THEN
      FOR f := FIRST(Field) TO LAST(Field) DO
        IF doDebug THEN Debug.Out(F("ProcessBuf : %s : %s", PgField.Names[f], b[f])) END
      END
    END;

    FOR f := FIRST(Field) TO LAST(Field) DO
      WITH l = Text.Length(b[f]) DO
        IF l > widest[f] THEN
          IF doDebug THEN Debug.Out(F("widest %s <- %s", PgField.Names[f], b[f])) END;
          widest[f] := l
        END
      END
    END;

    WITH base = ParseLiteral(b[Field.Base]),
         lenU = ParseLiteral(b[Field.Length]),
         grp  =              b[Field.Group]    DO

      IF lenU MOD lenPerByte # 0 THEN
        Debug.Error(F("ProcessBuf : specified len 0x%s , not divisible by 0x%s", Int16(lenU), Int16(lenPerByte)))
      END;

      len := lenU DIV lenPerByte;
      
      IF doDebug AND Debug.GetLevel() >= 100 THEN
        Debug.Out(F("range start %s len %s pg %s",
                    Int16(base),
                    Int16(len),
                    grp))
      END;

      IF base >= addrLim THEN
        Debug.Error(F("ProcessBuf : Base address for register %s %s is out of range: limit is %s", Debug.UnNil(b[Field.Name]), Int16(base), Int16(addrLim)))
      END;
      IF base+len > addrLim THEN
        Debug.Error(F("ProcessBuf : Base+len address for register %s %s is out of range: limit is %s", Debug.UnNil(b[Field.Name]), Int16(base+len), Int16(addrLim)))
      END;

      EVAL MapPGnameToNumber(grp); (* ensure we can map group *)
      INC(totLen, len);
      IF NOT pgs.get(grp, rl) THEN
        rl := NewRL();
        EVAL pgs.put(grp, rl)
      END;
      WITH range = NEW(Range.T) DO
        range^ := Range.B { base, len, grp, b[Field.Name] };
        IF NOT InsertOrdered(rl, range) THEN procBufOK := FALSE END;
        IF NOT InsertOrdered(allRanges, range) THEN procBufOK := FALSE END;
        EVAL reverse.put(range, b[Field.Name]);
      END
    END
  END ProcessBuf;

PROCEDURE ParseLiteral(t : TEXT) : Address.T =
  BEGIN
    TRY
      RETURN Scan.Int(t)
    EXCEPT
      Lex.Error, FloatMode.Trap =>

      RETURN ParseHexLiteral(t)
    END
  END ParseLiteral;

PROCEDURE ParseHexLiteral(t : TEXT) : Address.T =

  PROCEDURE GetHexDigit(VAR d : [0..15]) : BOOLEAN =
    VAR c : CHAR;
    BEGIN
      IF Get(c) THEN
        CASE c OF
          '0' .. '9' => d := ORD(c) - ORD('0')     ; RETURN TRUE
        |
          'a' .. 'f' => d := ORD(c) - ORD('a') + 10; RETURN TRUE
        |
          'A' .. 'F' => d := ORD(c) - ORD('A') + 10; RETURN TRUE
        ELSE
          Push();
          RETURN FALSE
        END
      END;
      RETURN FALSE
    END GetHexDigit;

  PROCEDURE GetDecDigit(VAR d : [0..9]) : BOOLEAN =
    VAR
      x : [0..15];
    BEGIN
      IF NOT GetHexDigit(x) THEN RETURN FALSE END;
      IF x<=9 THEN
        d := x;
        RETURN TRUE;
      ELSE
        Push();
        RETURN FALSE
      END
    END GetDecDigit;

  PROCEDURE Get(VAR c : CHAR) : BOOLEAN =
    BEGIN
      IF p >= Text.Length(t) THEN RETURN FALSE END;
      c := Text.GetChar(t, p);
      INC(p);
      RETURN TRUE
    END Get;

  PROCEDURE Push() =
    BEGIN DEC(p) END Push;

  PROCEDURE Error() =
    BEGIN
      Debug.Error("ParseHexLiteral : cant parse hex \"" & t & "\"")
    END Error;
    
  VAR
    w : CARDINAL := 0;
    p : CARDINAL := 0;
    d : [0..9];
    h : [0..15];
    a : Address.T := 0;
    c : CHAR;
  BEGIN
    WHILE GetDecDigit(d) DO w := w * 10 + d END;
    IF NOT Get(c) OR c # '\'' THEN Error() END;
    IF NOT Get(c) OR c # 'h'  THEN Error() END;
    WHILE  GetHexDigit(h) DO a := a * 16 + h END;

    RETURN a
  END ParseHexLiteral;

  (**********************************************************************)

PROCEDURE MergeRanges(s : SortedRangeTbl.T) =
  (* modifies merged ranges in allRanges, not in per-PG tables *)
  PROCEDURE Push(ran : Range.T) =
    BEGIN
      IF doDebug THEN Debug.Out(F("MergeRanges pushing %s", Range.Format(ran))) END;
      EVAL allRanges.put(ran, ran.group)
    END Push;
  
  VAR
    iter := s.iterateOrdered();
    r, q : Range.T;
    qv := FALSE; (* q holds valid data *)
    dummy : REFANY;
  BEGIN
    WHILE iter.next(r,dummy) DO
      IF qv AND q.lo + q.len = r.lo THEN
        IF Debug.GetLevel() >= 100 THEN
          IF doDebug THEN Debug.Out(F("merging ranges : %s <-> %s",
                                      Range.Format(q), Range.Format(r))) END
        END;
          
        q.len := q.len + r.len
      ELSIF qv THEN Push(q); q := r
      ELSE
        (* first iteration *)
        q := r;
        qv := TRUE
      END
    END;
    IF qv THEN Push(q) END;
  END MergeRanges;

PROCEDURE ScatterRanges() =
  VAR rIter := pgs.iterate();
      iter := allRanges.iterate();
      nm : TEXT;
      tbl : SortedRangeTbl.T;
      r : Range.T;
      ref : REFANY;
  BEGIN
    (* clear all ranges *)
    WHILE rIter.next(nm, tbl) DO
      tbl := NEW(SortedRangeTbl.Default).init();
      WITH hadIt = pgs.put(nm, tbl) DO <*ASSERT hadIt*> END
    END;
    
    WHILE iter.next(r, ref) DO
      VAR z : SortedRangeTbl.T;
          hadIt := pgs.get(ref, z);
      BEGIN
        <*ASSERT hadIt*>

        WITH hadIt2 = z.put(r, ref) DO
          <*ASSERT NOT hadIt2*>
        END
        
      END
    END
  END ScatterRanges;
  
PROCEDURE MergeGroups() =
  VAR
    iter := pgs.iterate();
    nm : TEXT;
    s : SortedRangeTbl.T;
  BEGIN
    IF doDebug THEN
      Debug.Out(">>>>>>>>>>>>>>>>>>>>  MERGE GROUPS  >>>>>>>>>>>>>>>>>>>>")
    END;

    allRanges := NEW(SortedRangeTbl.Default).init();
    
    WHILE iter.next(nm, s) DO
      IF doDebug THEN
        Debug.Out("Merging ranges in group " & nm)
      END;
      MergeRanges(s)
    END;

    ScatterRanges();

    IF doDebug THEN
      Debug.Out("<<<<<<<<<<<<<<<<<<<<  MERGE GROUPS  <<<<<<<<<<<<<<<<<<<<")
    END;

  END MergeGroups;

PROCEDURE CheckForOverlaps(checkMerges : BOOLEAN) : BOOLEAN =

  PROCEDURE CheckForOverlap(r : Range.T) =
    VAR
      jter := allRanges.iterateOrdered();
      q, rdum : Range.T;
      nn : REFANY;
    BEGIN
      (* this code is inefficient but maybe adaptable .. *)
      jter.seek(r);
      (* at next entry *)

      (* skip r itself *)
      WITH hadIt = jter.next(q,nn) DO <*ASSERT hadIt AND Range.Equal(r, q)*> END;
      
      IF jter.next(q, nn) THEN
        IF checkMerges AND TE(q.group, r.group) AND Range.CanMerge(q, r, rdum) THEN
          Debug.Error(F("CheckForOverlaps : Uncaught merge opportunity : %s <-> %s",
                        Range.Format(r), Range.Format(q)))
        END;

        IF Range.Overlap(q, r) THEN
          VAR pr := FALSE;
              qn, rn := "--UNKNOWN--";
              w := "";
          BEGIN
            IF reverse.get(q, qn) THEN pr := TRUE END;
            IF reverse.get(r, rn) THEN pr := TRUE END;

            IF pr THEN
              w := F("\nOVERLAP REGISTER(S) POSSIBLY INVOLVED: %s <-> %s", qn, rn)
            END;
            Debug.Warning(F("FOUND PG RANGE OVERLAP DURING MERGE: %s <-> %s%s", Range.Format(q), Range.Format(r),w));
            
          END;
          success := FALSE
        END
      END
    END CheckForOverlap;
    
  VAR
    iter := allRanges.iterateOrdered();
    r : Range.T;
    n : REFANY;
    success := TRUE;
  BEGIN
    IF doDebug THEN
      Debug.Out(">>>>>>>>>>>>>>>>>>>>  CHECKING FOR OVERLAPS  >>>>>>>>>>>>>>>>>>>>")
    END;
    WHILE iter.next(r, n) DO CheckForOverlap(r) END;

    IF doDebug THEN
      Debug.Out("<<<<<<<<<<<<<<<<<<<<  CHECKING FOR OVERLAPS  <<<<<<<<<<<<<<<<<<<<")
    END;
    RETURN success

  END CheckForOverlaps;

PROCEDURE AttemptElimOverlaps() =
  VAR
    iter := allRanges.iterateOrdered();
    q, r : Range.T;
    first := TRUE;
    overlaps := NEW(SortedRangeTbl.Default).init();
    n : REFANY;
  BEGIN
    IF doDebug THEN
      Debug.Out(">>>>>>>>>>>>>>>>>>>>  ELIMINATING OVERLAPS  >>>>>>>>>>>>>>>>>>>>")
    END;
    (* invariant : q is beginning of current overlap *)
    WHILE iter.next(r, n) DO
      IF first THEN
        first := FALSE;
        q := r
      ELSIF TE(q.group, r.group) AND Range.Overlap(q, r) THEN
        VAR lst : REFANY := NIL;
        BEGIN
          EVAL overlaps.get(q, lst);
          lst := RefList.Cons(r, lst);
          EVAL overlaps.put(q, lst)
        END
      ELSE (* no overlap case *)
        q := r
      END
    END;

    iter := overlaps.iterateOrdered();
    
    VAR
      nm : TEXT;
      lst : REFANY;
      p : RefList.T;
      max : CARDINAL;
      dum : REFANY;
    BEGIN
      WHILE iter.next(q, lst) DO
        nm := "--UNKNOWN--";
        EVAL reverse.get(q, nm);
        p := lst;
        max := q.lo + q.len;
        WHILE p # NIL DO
          WITH r = NARROW(p.head, Range.T) DO
            max := MAX(max, r.lo + r.len);
            WITH hadIt = allRanges.delete(r,dum) DO <*ASSERT hadIt*> END;
          END;
          p := p.tail
        END;
        IF doDebug THEN
          Debug.Out(F("Eliminating overlaps for %s @ %s, %s overlaps %s -> %s",
                      nm, Int16(q.lo), Fmt.Int(RefList.Length(lst)), Int16(q.len), Int16(max-q.lo)))
        END;
        WITH hadIt = allRanges.delete(q,dum) DO <*ASSERT hadIt*> END;
        q.len := max - q.lo
      END
    END;

    ScatterRanges();

    IF doDebug THEN
      Debug.Out("<<<<<<<<<<<<<<<<<<<<  ELIMINATING OVERLAPS  <<<<<<<<<<<<<<<<<<<<")
    END;

  END AttemptElimOverlaps;

PROCEDURE BestSplit(a, b : Address.T) : Address.T =
  VAR
    di : [-1..LAST(CARDINAL)] := -1;
    r := b;
  BEGIN
    <*ASSERT b>a*>
    (* the Address.T that is in between a (exclusive) and b (inclusive) and has the most zeros trailing *)
    FOR i := Word.Size-1 TO 0 BY -1 DO
      IF Word.Extract(a,i,1) # Word.Extract(b,i,1) THEN
        di := i;
        EXIT
      END
    END;
    <* ASSERT di > -1 OR a = b *>
    IF di # -1 THEN
      r := Word.Insert(r, 0, 0, di);
    END;
    <*ASSERT r>a*>
    <*ASSERT b>=r*>
    RETURN r
  END BestSplit;
  
PROCEDURE ExtendIntoGaps() : BOOLEAN =

  PROCEDURE ExtendRange(r : Range.T) =

    PROCEDURE Next(x : Range.T; dir : [-1..1]; VAR nxt : Range.T) : BOOLEAN =
      VAR
        jter := allRanges.iterateOrdered(up := dir=1);
        q : Range.T;
        nn : REFANY;
      BEGIN
        <*ASSERT dir # 0*>
        jter.seek(x);
        (* skip x itself *)
        WITH hadIt = jter.next(q,nn) DO
          <*ASSERT hadIt AND Range.Equal(x, q)*>
        END;

        RETURN jter.next(nxt, nn)
      END Next;

    VAR
      n, p : Range.T;
      haveN, haveP : BOOLEAN;
      lo, lim : Address.T;
      z := new.size();
    BEGIN
      IF doDebug THEN
        Debug.Out(F("ExtendRange(%s)", Range.Format(r)))
      END;
      
      haveP := Next(r, -1, p);
      haveN := Next(r, +1, n);

      IF doDebug THEN
        Debug.Out(F("ExtendRange haveN=%s haveP=%s", Fmt.Bool(haveN), Fmt.Bool(haveP)))
      END;
      IF doDebug AND haveN AND haveP THEN
        Debug.Out(F("ExtendRange(%s) : p = %s n = %s", Range.Format(r), Range.Format(p), Range.Format(n)))
      END;
      
      IF haveP THEN
        lo := BestSplit(p.lo + p.len-1, r.lo)
      ELSE
        lo := 0
      END;

      IF haveN THEN
        lim := BestSplit(r.lo + r.len - 1, n.lo)
      ELSE
        lim := Word.LeftShift(1, bits);
      END;

      IF doDebug THEN
        Debug.Out(F("ExtendRange: r.lo=%s lo=%s  r.lo+r.len=%s lim=%s",
                    Int16(r.lo), Int16(lo), Int16(r.lo+r.len), Int16(lim)))
      END;
      <*ASSERT lo  <= r.lo *>
      <*ASSERT lim >= r.lo + r.len*>
      extended := extended OR r.lo # lo OR r.len # lim-lo;
      r.lo  := lo;
      r.len := lim - lo;

      IF doDebug THEN
        Debug.Out(F("Extending range into gap: %s", Range.Format(r)))
      END;

      EVAL new.put(r, r.group);
      <*ASSERT new.size() = z+1*>
    END ExtendRange;
    
  VAR
    iter := allRanges.iterateOrdered();
    new := NEW(SortedRangeTbl.Default).init();
    r : Range.T;
    n : REFANY;
    extended : BOOLEAN;
  BEGIN
    IF doDebug THEN
      Debug.Out(">>>>>>>>>>>>>>>>>>>>  EXTENDING RANGES  >>>>>>>>>>>>>>>>>>>>")
    END;

    WHILE iter.next(r, n) DO ExtendRange(r) END;

    IF doDebug THEN
      Debug.Out(F("allRanges %s new %s", Fmt.Int(allRanges.size()), Fmt.Int(new.size())))
    END;
    
    <*ASSERT allRanges.size() = new.size()*>
    
    allRanges := new;
    reverse := Rehash(reverse); (* hashes might be screwed up *)
    
    ScatterRanges(); (* maintain invariant that allRanges is union of pgs *)

    IF doDebug THEN
      Debug.Out("<<<<<<<<<<<<<<<<<<<<  EXTENDING RANGES  <<<<<<<<<<<<<<<<<<<<")
    END;

    RETURN extended

  END ExtendIntoGaps;

PROCEDURE Rehash(tbl : SortedRangeTextTbl.T) : SortedRangeTextTbl.T =
  VAR
    new := NEW(SortedRangeTextTbl.Default).init();
    iter := tbl.iterate();
    r : Range.T;
    n : TEXT;
  BEGIN
    WHILE iter.next(r, n) DO EVAL new.put(r, n) END;
    RETURN new
  END Rehash;

PROCEDURE PrintStats() =
  VAR
    iter := pgs.iterate();
    nm : TEXT;
    rl : SortedRangeTbl.T;
  BEGIN
    Debug.Out(">>>>>>>>>>>>>>>  STATS  >>>>>>>>>>>>>>>");
    WHILE iter.next(nm, rl) DO
      Debug.Out(F("%s : %s", nm, Fmt.Int(rl.size())));
      
    END;

    Debug.Out(F("totLen = %s", Fmt.Int(totLen)));
    Debug.Out("<<<<<<<<<<<<<<<  STATS  <<<<<<<<<<<<<<<");

  END PrintStats;

PROCEDURE DebugDump() =
  VAR iter := allRanges.iterateOrdered();
      r : Range.T;
      ref : REFANY;
  BEGIN
    Debug.Out(">>>>>>>>>>>>>>>>>>>>  DEBUG DUMP  >>>>>>>>>>>>>>>>>>>>");
    WHILE iter.next(r, ref) DO
      Debug.Out(Range.Format(r))
    END;
    Debug.Out("<<<<<<<<<<<<<<<<<<<<  DEBUG DUMP  <<<<<<<<<<<<<<<<<<<<")
  END DebugDump;

PROCEDURE AssertNoGaps() =
  VAR iter := allRanges.iterateOrdered();
      q, r : Range.T;
      ref : REFANY;
      qv := FALSE;
  BEGIN
    IF doDebug THEN
      Debug.Out(">>>>>>>>>>>>>>>>>>>>  CHECKING  >>>>>>>>>>>>>>>>>>>>")
    END;
    WHILE iter.next(r, ref) DO
      IF qv THEN
        IF q.lo + q.len # r.lo THEN
          Debug.Error(F("AssertNoGaps : gap between consecutive ranges : %s <-> %s", Range.Format(q), Range.Format(r)))
        END;
        
        IF TE(r.group, q.group) THEN
          Debug.Error(F("AssertNoGaps : consecutive groups match: %s <-> %s", Range.Format(q), Range.Format(r)))
        END
      END;
      q := r; qv := TRUE
    END;
    IF doDebug THEN
      Debug.Out("<<<<<<<<<<<<<<<<<<<<  CHECKING  <<<<<<<<<<<<<<<<<<<<")
    END
  END AssertNoGaps;

(**********************************************************************)
(*TYPE ExtPolicyGroupIdx = [FIRST(PolicyGroupArr)  .. DefaultIdx];*)
TYPE ExtPolicyGroupIdx = CARDINAL;

TYPE
  Sections = { Prolog, Early, BaseStrap, Decls, Code, Epilog };
  Streams = ARRAY Sections OF Wr.T ;

CONST
  SectionNames = ARRAY Sections OF TEXT { "PROLOG", "EARLY", "BASESTRAP", "DECLS", "CODE", "EPILOG" };
  
PROCEDURE FmtSVCard(a : Address.T) : TEXT =
  BEGIN
    RETURN "'h" & Fmt.Int(a, base := 16)
  END FmtSVCard;

PROCEDURE NewCardArr() : REF ARRAY OF CARDINAL =
  VAR
    res := NEW(REF ARRAY OF CARDINAL, DefaultIdx + 1);
  BEGIN
    FOR i := FIRST(res^) TO LAST(res^) DO
      res[i] := 0
    END;
    RETURN res
  END NewCardArr;

PROCEDURE DumpSV(pn : Pathname.T) RAISES { Wr.Failure, OSError.E, Rd.Failure } =
  VAR
    p := NewCardArr();

  PROCEDURE O(str : TEXT; ptgt : Wr.T := NIL) RAISES { Wr.Failure } =
    BEGIN
      IF ptgt = NIL THEN ptgt := cur END;
      Wr.PutText(ptgt, str);
      Wr.PutChar(ptgt, '\n')
    END O;

  PROCEDURE Iterate(idx : ExtPolicyGroupIdx; VAR pp : CARDINAL)
    RAISES { Wr.Failure } =
    VAR
      iter := allRanges.iterateOrdered();
      r : Range.T;
      n : REFANY;
      nm : TEXT;
    BEGIN
      WHILE iter.next(r, n) DO
        VAR
          pgi : ExtPolicyGroupIdx;
          fmt, str : TEXT;
        BEGIN
          pgi := MapPGnameToNumber(r.group);
          IF pgi = idx THEN
            WITH hadIt = reverse.get(r, nm) DO <*ASSERT hadIt*> END;
            
            fmt := "  // %-" & Fmt.Int(widest[Field.Name]) & "s " &
                       "%-" & Fmt.Int(widest[Field.Group]) & "s " &
                       "%9s <= addr < (+%9s) %9s";
            
            str := F(fmt, 
                     nm,
                     r.group,
                     FmtSVCard(r.lo),
                     FmtSVCard(r.len),
                     FmtSVCard(r.lo+r.len));
            O("");
            O(str);

            Debug.Out(F("Iterate emitting m%s[%s]:\n%s",
                        Fmt.Int(idx), Fmt.Int(pp), str));

            O(F("  assign m%s[%s] = %s;",
                Fmt.Int(idx),
                Fmt.Int(pp),
                RangeExpr("addr", r.lo, r.lo+r.len)));
            INC(pp)
          END
        END
      END;
    END Iterate;

  PROCEDURE DumpPgListDebug() RAISES { Wr.Failure } =
    BEGIN
      O(F(" // policy group PG_DEFAULT"));
      FOR i := FIRST(PolicyGroupArr^) TO LAST(PolicyGroupArr^) DO
        O(F(" // policy group %5s \"%s\"", Fmt.Int(i), PolicyGroupArr[i]));
      END
    END DumpPgListDebug;

  PROCEDURE DeclareMinterms() RAISES { Wr.Failure } =
    BEGIN
      FOR i := 0 TO DefaultIdx DO
        IF p[i] # 0 AND i # pgToSkip THEN
          O(F("  logic[%s-1:0]  m%s;", Fmt.Int(p[i]), Fmt.Int(i)))
        END
      END
    END DeclareMinterms;

  PROCEDURE EmitBaseStrapArg() RAISES { Wr.Failure } =
    BEGIN
      O(F("input logic [(%s)-1:0] i_basestrap,", baseStrapBits))
    END EmitBaseStrapArg;

  PROCEDURE DeclareAddr() RAISES { Wr.Failure } =
    BEGIN
      O("  logic[$bits(i_addr)-1:0] addr;")
    END DeclareAddr;
    
  PROCEDURE EmitAddrCalc() RAISES { Wr.Failure } =
    BEGIN
      IF baseStrapBits = NIL THEN
        O("  assign addr = i_addr;")
      ELSE
        O("  assign addr = i_addr - i_basestrap;")
      END
    END EmitAddrCalc;
    
  PROCEDURE DeclareOneHot() RAISES { Wr.Failure } =
    BEGIN
      O(F("  logic[%s-1:0] pg1;", Fmt.Int(DefaultIdx + 1)));
    END DeclareOneHot;

  PROCEDURE EmitMinterms() RAISES { Wr.Failure } =
    BEGIN
      FOR i := 0 TO DefaultIdx DO
        IF i = pgToSkip THEN
          Debug.Out(F("EmitMinterms : skipping PG %s", Fmt.Int(i)))
        ELSE
          Iterate(i, p[i]);
          Debug.Out(F("EmitMinterms: p[%s] = %s", Fmt.Int(i), Fmt.Int(p[i])))
        END
      END
    END EmitMinterms;

  PROCEDURE CountMinterms() : REF ARRAY OF CARDINAL =
    VAR
      iter := allRanges.iterateOrdered();
      n  : REFANY;
      r  : Range.T;
      res := NewCardArr();
    BEGIN
      WHILE iter.next(r, n) DO
        WITH pgi = MapPGnameToNumber(r.group) DO
          INC(res[pgi])
        END
      END;
      RETURN res
    END CountMinterms;
    
  PROCEDURE EmitOneHotCombBlock(idx : CARDINAL) RAISES { Wr.Failure } =
    VAR
      l := 0;
      h := p[idx]-1; 
    BEGIN
      O(F(""));
      IF h >= l THEN
        (* nonempty range *)
        O(F("  assign pg1[%s] = |(m%s);",
            Fmt.Int(idx), Fmt.Int(idx)))
      ELSE
        O(F("  assign pg1[%s] = '0;", Fmt.Int(idx)))
      END
    END EmitOneHotCombBlock;
    
  PROCEDURE EmitOneHotCombBlocks() RAISES { Wr.Failure } =
    BEGIN
      FOR i := 0 TO DefaultIdx DO
        EmitOneHotCombBlock(i)
      END
    END EmitOneHotCombBlocks;

  PROCEDURE EmitEncodePGBlock() RAISES { Wr.Failure } =
    BEGIN
      O(F(  ""));
      O(F(  "  always_comb begin : generate_pg"));
      O(F(  ""));
      IF allTerms THEN
        O(F(  "    pg = DEFAULT_PG;"))
      ELSE
        O(F(  "    pg = %s;", Fmt.Int(pgToSkip)))
      END;
      
      O(F(  ""));
      O(F(  "    if      (0)  /* skip */ ; // lintra s-60131 \"stand-alone semicolon\""));
      FOR i := FIRST(PolicyGroupArr^) TO LAST(PolicyGroupArr^) DO
        IF i # pgToSkip THEN
          O(F("    else if (pg1[%-3s]) pg = %s;", Fmt.Int(i), Fmt.Int(i)))
        END
      END;
      O(F(  "    else if (pg1[%-3s]) pg = %s;", Fmt.Int(DefaultIdx), "DEFAULT_PG"));
      O(F(  "  end : generate_pg"));
    END EmitEncodePGBlock;

  PROCEDURE CopyInFromPath(path : Pathname.T)
    RAISES { Rd.Failure, OSError.E, Wr.Failure } =
    VAR
      rd := FileRd.Open(path);
    BEGIN
      CopyInFromReader(rd);
      Rd.Close(rd)
    END CopyInFromPath;

  PROCEDURE CopyInFromReader(rd : Rd.T)
    RAISES { Rd.Failure, Wr.Failure } =
    BEGIN
      TRY
        LOOP
          WITH ln = Rd.GetLine(rd) DO
            O(ln)
          END
        END
      EXCEPT
        Rd.EndOfFile => (* skip *)
      END
    END CopyInFromReader;

  VAR 
    cur : Wr.T;

  PROCEDURE DoEmitAll() RAISES { Wr.Failure, OSError.E, Rd.Failure } =
  VAR
    tgt : Streams;
  BEGIN
    FOR i := FIRST(tgt) TO LAST(tgt) DO tgt[i] := TextWr.New() END;
    
    cur := tgt[Sections.Prolog];
    TRY
      IF copyRightPath # NIL THEN
        CopyInFromPath(copyRightPath)
      END
    EXCEPT
      Rd.Failure(x) =>
      Debug.Error(F("DoEmitAll : I/O error while reading copyright file %s: Rd.Failure : ", copyRightPath,    AL.Format(x)))
    |
      OSError.E(x) =>
      Debug.Error(F("DoEmitAll : Error while opening copyright file %s : OSError.E : %s", copyRightPath, AL.Format(x)))
    END;
    
    cur := tgt[Sections.Early];
    DumpPgListDebug();

    IF baseStrapBits # NIL THEN
      cur := tgt[Sections.BaseStrap];
      EmitBaseStrapArg()
    END;

    cur := tgt[Sections.Code];
    EmitAddrCalc();
    WITH cnt = CountMinterms() DO
      Debug.Out("CountMinterms");
      FOR i := FIRST(cnt^) TO LAST(cnt^) DO
        Debug.Out(F("pgi %s cnt %s", Fmt.Int(i), Fmt.Int(cnt[i])));
      END;
      IF NOT allTerms THEN
        (* determine which PG to skip generating *)
        VAR
          maxCnt := cnt[0];
        BEGIN
          pgToSkip := 0;
          FOR i := FIRST(cnt^) TO LAST(cnt^) DO
            IF cnt[i] > maxCnt THEN
              maxCnt := cnt[i]; pgToSkip := i
            END
          END
        END
      END;
      Debug.Out(F("CountMinterms : pgToSkip = %s", Fmt.Int(pgToSkip)))
    END;
    EmitMinterms();
    EmitOneHotCombBlocks();
    EmitEncodePGBlock();

    EmitSharedExpressions(tgt);
    
    cur := tgt[Sections.Decls];
    DeclareAddr();
    DeclareMinterms();
    DeclareOneHot();

    cur := tgt[Sections.Epilog];
    VAR wr := TextWr.New(); BEGIN
      FOR i := FIRST(tgt) TO LAST(tgt) DO
        CopyTill(templateRd, wr, "**" & SectionNames[i] & "**");
        Wr.PutText(wr, TextWr.ToText(tgt[i]))
      END;
      CopyTill(templateRd, wr, NIL);
      wr := MakeSubstitutions(wr);
      WITH nwr = FileWr.Open(pn) DO
        Wr.PutText(nwr, TextWr.ToText(wr));
        Wr.Close(nwr)
      END
    END
  END DoEmitAll;
  
  BEGIN
    DoEmitAll()
  END DumpSV;

PROCEDURE MakeSubstitutions(wr : TextWr.T) : TextWr.T =
  VAR
    nm, val : TEXT;
    ot : TEXT;
  BEGIN
    ot := TextWr.ToText(wr);
    WITH new  = TextWr.New(),
         iter = bindings.iterate() DO
      WHILE iter.next(nm,val) DO
        WITH tag = "**" & nm & "**" DO
          Debug.Out(F("MakeSubstitutions replacing \"%s\" -> \"%s\"", tag, val));
          ot := TextUtils.Replace(ot, tag, val)
        END
      END;
      Wr.PutText(new, ot);
      RETURN new
    END
  END MakeSubstitutions;

PROCEDURE CopyTill(rd : Rd.T; wr : Wr.T; tag : TEXT) RAISES { Rd.Failure, Wr.Failure } =

  PROCEDURE TagFound() : BOOLEAN =
    VAR 
      len : CARDINAL;
    BEGIN
      IF tag = NIL THEN RETURN FALSE END;
      len := Text.Length(tag);
      FOR i := 0 TO Text.Length(tag)-1 DO
        WITH j = s.size()-len+i DO
          IF j<0 THEN RETURN FALSE END;
          IF Text.GetChar(tag,i) # s.get(j) THEN RETURN FALSE END
        END
      END;
      RETURN TRUE
    END TagFound;

  PROCEDURE RewindOutputTag() =
    BEGIN
      FOR i := Text.Length(tag)-1 TO 0 BY -1 DO
        WITH c = s.remhi() DO
          <*ASSERT c = Text.GetChar(tag,i)*>
        END
      END
    END RewindOutputTag;

  VAR
    s := NEW(CharSeq.T).init();
  BEGIN
    TRY
      LOOP
        s.addhi(Rd.GetChar(rd)); 
        IF TagFound() THEN RewindOutputTag(); EXIT END; (* found tag, quit *)
      END
    EXCEPT 
      Rd.EndOfFile => (* skip *)
    END;
    (* convert buffer *)
    FOR i := 0 TO s.size()-1 DO
      Wr.PutChar(wr, s.get(i))
    END
  END CopyTill;

VAR exprTbl := NEW(TextTextTbl.Default).init();
    exprSeq := NEW(TextSeq.T).init();

PROCEDURE EmitSharedExpressions(tgt : Streams) RAISES { Wr.Failure } =
  VAR
    v : TEXT;
  BEGIN
    FOR i := 0 TO exprSeq.size()-1 DO
      WITH x     = exprSeq.get(i),
           hadIt = exprTbl.get(x, v) DO
        <*ASSERT hadIt*>
      Wr.PutText(tgt[Sections.Decls],
                 F("  logic %s;\n", v));
      Wr.PutText(tgt[Sections.Code],
                 F("  assign %s = %s;\n", v, exprSeq.get(i)))
      END
    END
  END EmitSharedExpressions;

PROCEDURE Ruler(w : CARDINAL; digit : [0..1]) : TEXT =
  VAR
    wx := Wx.New();
  BEGIN
    FOR i := w-1 TO 0 BY -1 DO
      CASE digit OF
        0 =>
        Wx.PutChar(wx, VAL(i MOD 10 + ORD('0'), CHAR))
      |
        1 =>
        IF i MOD 10 = 0 THEN
          Wx.PutChar(wx, VAL((i DIV 10) MOD 10 + ORD('0'), CHAR))
        ELSE
          Wx.PutChar(wx, ' ')
        END
      END
    END;
    RETURN Wx.ToText(wx)
  END Ruler;
  
PROCEDURE RangeExpr(var : TEXT; lo, lm : CARDINAL) : TEXT =

  PROCEDURE AndIn(str : TEXT) : TEXT =
    BEGIN
      WITH res = MemoizeExpr(str) DO
        Debug.Out(F("AndIn %s -> %s", str, res));
        RETURN res
      END
    END AndIn;

  VAR
    loW  : Word.T := lo;
    hiW  : Word.T := lm-1;
    di := -1;
  BEGIN
    (* (addr >= %s) & (addr < %s) *)
    Debug.Out(F("RangeExpr(%s, %s, %s)", var, FmtSVCard(lo), FmtSVCard(lm)));
    
    FOR i := Word.Size-1 TO 0 BY -1 DO
      IF Word.Extract(loW, i, 1) # Word.Extract(hiW, i, 1) THEN
        di := i; EXIT
      END
    END;

    Debug.Out(F("    %64s", Ruler(64,1)));
    Debug.Out(F("    %64s", Ruler(64,0)));
    Debug.Out(F("loW %64s", Fmt.Int(loW, base:=2)));
    Debug.Out(F("hiW %64s", Fmt.Int(hiW, base:=2)));

    Debug.Out(F("RangeExpr di=%s", Fmt.Int(di)));

    IF di = -1 THEN
      (* lo, hi words differ in every bit *)
      RETURN
        MemoizeExpr(F("(%s >= %s) & (%s < %s)", var, FmtSVCard(lo), FmtSVCard(lm)))
    ELSE
      (* words are equal from Word.Size downto di+1 
         words differ    from di        downto    0 *)

      <*ASSERT Word.Extract(loW, di+1, Word.Size-(di+1)) =
               Word.Extract(hiW, di+1, Word.Size-(di+1)) *>
      
      <*ASSERT Word.Extract(loW, di, 1) #
               Word.Extract(hiW, di, 1) *>
      
      WITH loD = Word.Extract(loW, 0   , di+1),
           hiD = Word.Extract(hiW, 0   , di+1) DO
        VAR
          res := "";
        BEGIN
          res := EqualsExpr(var, di+1, loW);

          IF loD # 0 THEN
            res := res & F(" & ") &
                       AndIn(F("(%s[%s:0] >= %s)", var, Fmt.Int(di), FmtSVCard(loD)))
          END;

          IF hiD # Word.LeftShift(1, di+1)-1 THEN
            res := res & 
                F(" & ") &
                AndIn(F("(%s[%s:0] <  %s)", var, Fmt.Int(di), FmtSVCard(hiD+1)))
          END;
          RETURN res
        END
      END
    END
  END RangeExpr;

PROCEDURE EqualsExpr(var  : TEXT;
                     lsb  : CARDINAL;
                     val  : Word.T) : TEXT =
  (* format infix expression denoting var = val starting at bit lb,
     with the various terms being easily shareable *)
  
  VAR
    first := TRUE;
    
  PROCEDURE Push(str : TEXT) =
    BEGIN
      IF first THEN res := str; first := FALSE ELSE res := res & " & " & str END
    END Push;

  PROCEDURE AndIn(str : TEXT) =
    BEGIN
      WITH var = MemoizeExpr(str) DO
        Debug.Out(F("AndIn %s -> %s", str, var));
        Push(var)
      END
    END AndIn;
    
  CONST
    Step = 4;
  VAR
    msb := MAX(lsb,MaxSetBit(val));
    res : TEXT;
    maxChecked := -1;
  BEGIN
    IF lsb >= bits THEN RETURN "1" END;
      
    <*ASSERT msb>=lsb*>
    Debug.Out(F("FmtEquals(%s,%s,16_%s)", var, Fmt.Int(lsb), Fmt.Int(val, base := 16)));
    
    (* F("(%s[$bits(%s)-1:%s] == %s)",var,var,Fmt.Int(di+1),FmtSVCard(eqP)); *)
    FOR k := 0 TO Word.Size-Step BY Step DO
      WITH
        valChunk = Word.Extract(val, k, Step),
        chunkMsb = MIN(bits-1, k + Step-1), (* top of this chunk *)
        chunkLsb = MAX(k, lsb),             (* bottom of this chunk *)

        (* note that if lsb > k + Step - 1  then there is nothing to
           emit on this chunk since we havent reached the bits involved 
           in the equality test yet *)
        
        valCmp   = Word.RightShift(valChunk, chunkLsb - k),
        valCmpStr= FmtSVCard(valCmp),
        last     = chunkMsb >= msb               DO

        Debug.Out(F("  FmtEquals k=%s valChunk=16_%s chunkMsb=%s chunkLsb=%s valCmp=16_%s",
                    Fmt.Int(k),
                    Fmt.Int(valChunk, base := 16),
                    Fmt.Int(chunkMsb),
                    Fmt.Int(chunkLsb),
                    Fmt.Int(valCmp, base := 16)) &
                  F(" last=%s",                                                
                    Fmt.Bool(last)));
        IF chunkMsb >= chunkLsb THEN
          <*ASSERT chunkLsb >= lsb*>
          AndIn(F("(%s[%s:%s] == %s)",
                  var,
                  Fmt.Int(chunkMsb),
                  Fmt.Int(chunkLsb),
                  valCmpStr))
        END;
        IF last THEN maxChecked := chunkMsb; EXIT END
      END
    END;
    <*ASSERT maxChecked # -1*>
    IF maxChecked # bits-1 THEN
      <*ASSERT maxChecked+1 >= lsb*>
      (* there are more leading zero bits as yet not considered *)
      AndIn(F("(%s[%s:%s] == %s)", var,
              Fmt.Int(bits-1),
              Fmt.Int(maxChecked+1),
              "'0"))
    END;
    RETURN res
  END EqualsExpr;

PROCEDURE FormatVar(expr : TEXT) : TEXT =
  (* make a useful variable name *)
  VAR
    wx := Wx.New();
  BEGIN
    Wx.PutText(wx, "comb_");
    FOR i := 0 TO Text.Length(expr)-1 DO
      WITH c = Text.GetChar(expr, i) DO
        CASE c OF
          '0'..'9', 'a'..'z', 'A'..'Z' => Wx.PutChar(wx, c)
        |
          ' ' => (* skip *)
        ELSE
          Wx.PutText(wx, "_A");
          Wx.PutText(wx, Fmt.Int(ORD(c)));
          Wx.PutText(wx, "A_");
        END
      END
    END;
    RETURN Wx.ToText(wx)
  END FormatVar;
  
PROCEDURE MemoizeExpr(expr : TEXT) : TEXT =
  VAR
    v : TEXT;
  BEGIN
    IF NOT exprTbl.get(expr, v) THEN
      v := FormatVar(expr);
      EVAL exprTbl.put(expr, v);
      exprSeq.addhi(expr);
    END;
    RETURN v
  END MemoizeExpr;

PROCEDURE MaxSetBit(w : Word.T) : [-1..Word.Size-1] =
  BEGIN
    FOR i := 0 TO Word.Size DO
      IF Word.RightShift(w, i) = 0 THEN RETURN i-1 END
    END;
    <*ASSERT FALSE*>
  END MaxSetBit;
  
(**********************************************************************)
  
CONST
  DefPolicyGroupArr = ARRAY OF TEXT
  { "PG0",
    "PG1",
    "PG2",
    "PG3",
    "PG4",
    "PG5",
    "PG6",
    "PG7" };

PROCEDURE DoCSV(fn : Pathname.T) =
  VAR
    buf : ARRAY Field OF TEXT;
    csv : CSVParse.T;
  BEGIN
    
    TRY
      rd := FileRd.Open(fn);
      csv := NEW(CSVParse.T).init(rd);
      
      csv.startLine();
      csv.startLine();
      LOOP
        TRY
          csv.startLine();
          FOR i := FIRST(Field) TO LAST(Field) DO
            buf[i] := csv.cell()
          END;
          IF NOT TextUtils.HavePrefix(buf[FIRST(buf)], "//") THEN
            ProcessBuf(buf, 1)
          END
        EXCEPT
          CSVParse.EndOfLine => (* wrong syntax *)
        END
      END
    EXCEPT
      Rd.Failure(x) =>
      Debug.Error(F("DoCSV : I/O error while reading input %s : Rd.Failure : %s", fn, AL.Format(x)))
    |
      OSError.E(x) =>
      Debug.Error(F("DoCSV : Error while opening input %s : OSError.E : %s", fn,  AL.Format(x)))
    |
      Rd.EndOfFile =>
      (* done *)
      TRY Rd.Close(rd) EXCEPT ELSE <*ASSERT FALSE*> END
    END;

  END DoCSV;

PROCEDURE DebugDumpParser(p : XMLParse.T; level : CARDINAL := 0) =
  VAR
    aIter := p.iterateAttrs();
    cIter := p.iterateChildren();
    leader : TEXT;
    attr : XMLParse.Attr;
    child : XMLParse.T;
  BEGIN
    WITH ca = NEW(REF ARRAY OF CHAR, level)^ DO
      FOR i := FIRST(ca) TO LAST(ca) DO ca[i] := '.' END;
      leader := Text.FromChars(ca)
    END;

    WHILE aIter.next(attr) DO
      Debug.Out(leader & " attr " & attr.tag & " = " & attr.attr)
    END;

    WHILE cIter.next(child) DO
      Debug.Out(leader &
                " child " & child.getEl() & " : " & DeWhiteSpace(child.getCharData()));
      DebugDumpParser(child, level+1)
    END
    
  END DebugDumpParser;

  (**********************************************************************)

PROCEDURE GenerateOutput() =
  BEGIN
    IF doDebug THEN
      Debug.Out("allRanges : " & Fmt.Int(allRanges.size()));

      PrintStats()
    END;

    IF attemptElimOverlaps THEN
      AttemptElimOverlaps()
    END;
    
    IF NOT CheckForOverlaps(FALSE) THEN
      Debug.Error("GenerateOutput : There were overlaps.  Cant continue")
    END;
    
    MergeGroups();

    IF doDebug THEN
      PrintStats()
    END;

    IF NOT CheckForOverlaps(TRUE) THEN
      Debug.Error("GenerateOutput : Internal program error---overlaps created, please save your input and report this as a bug")
    END;

    IF skipHoles THEN
      IF ExtendIntoGaps() THEN
        MergeGroups()
      END
    END;

    IF doDebug THEN
      PrintStats()
    END;

    IF NOT CheckForOverlaps(TRUE) THEN
      Debug.Error("GenerateOutput : Internal program error---overlaps created, please save your input and report this as a bug")
    END;

    IF doDebug THEN
      DebugDump()
    END;
    
    IF skipHoles THEN AssertNoGaps() END;

    IF svOutput # NIL THEN
      TRY
        DumpSV(svOutput)
      EXCEPT
        Wr.Failure(x) =>
        Debug.Error(F("GenerateOutput : I/O error while writing SV output %s : Wr.Failure : %s", svOutput, AL.Format(x)))
      |
        Rd.Failure(x) =>
        Debug.Error(F("GenerateOutput : I/O error while reading SV template %s: Rd.Failure : ", "unknown",    AL.Format(x)))
      |
        OSError.E(x) =>
        Debug.Error(F("GenerateOutput : Error while opening SV output %s : OSError.E : %s", svOutput, AL.Format(x)))
      END
    END
  END GenerateOutput;

PROCEDURE DeWhiteSpace(txt : TEXT) : TEXT =
  CONST
    White = SET OF CHAR { '\t', ' ', '\n', '\r' };
  BEGIN
    FOR i := 0 TO Text.Length(txt)-1 DO
      IF NOT Text.GetChar(txt, i) IN White THEN RETURN txt END
    END;
    RETURN ""
  END DeWhiteSpace;

<*UNUSED*>
PROCEDURE OldDoCRIF(fn : Pathname.T) =
  (* dead code *)
  VAR
    parser : XMLParse.T;
  BEGIN
    parser := XMLParse.DoIt(fn);

    (*IF Debug.GetLevel() >= 10 THEN DebugDumpParser(parser) END*)
    TraverseXML(NEW(CRIFVisitor), parser)
  END OldDoCRIF;

TYPE
  (* dead code *)
  XMLVisitor = OBJECT METHODS
    visit(node, parent : XMLParse.T)
  END;

PROCEDURE TraverseXML(visitor : XMLVisitor;
                      root    : XMLParse.T;
                      parent  : XMLParse.T := NIL) =
  (* dead code *)
  VAR
    cIter := root.iterateChildren();
    child : XMLParse.T;
  BEGIN
    visitor.visit(root, parent);
    WHILE cIter.next(child) DO TraverseXML(visitor, child, root) END
  END TraverseXML;

PROCEDURE CRIFVisit(<*UNUSED*>visitor : CRIFVisitor;
                    node    : XMLParse.T;
                    <*UNUSED*>parent  : XMLParse.T) =
  (* dead code *)
  BEGIN
    IF TE(node.getEl(), "register") THEN
      (* this is a register *)
      WITH name           = node.getChild("name").getCharData(),
           addressOffsetT = node.getChild("addressOffset").getCharData(),
           sizeT          = node.getChild("size").getCharData(),
           pg             = node.getChild("Security_PolicyGroup").getCharData() DO
        IF doDebug THEN
          Debug.Out(F("reg %s off %s sz %s pg %s",
                      name, addressOffsetT, sizeT, pg))
        END;

        WITH buf = ARRAY Field OF TEXT { name, addressOffsetT, sizeT, pg } DO
          ProcessBuf(buf, 8)
        END
      END
    END
  END CRIFVisit;

(* dead code *)
TYPE
  CRIFVisitor = XMLVisitor OBJECT OVERRIDES visit := CRIFVisit END;

  (**********************************************************************)

PROCEDURE LoadTemplate(nm : TEXT) =
  BEGIN
    TRY
      templateRd := FileRd.Open(nm)
    EXCEPT
      OSError.E =>
      VAR
        bundleTxt := Bundle.Get(PgToolSVTemplates.Get(),nm);
      BEGIN
        IF bundleTxt = NIL THEN
          Debug.Error(F("Cant find template \"%s\"", nm))
        END;
        templateRd := TextRd.New(bundleTxt);
      END
    END
  END LoadTemplate;

  (**********************************************************************)

     
     
VAR
  PgDefaultName := "PG_DEFAULT";
  PolicyGroupArr : REF ARRAY OF TEXT;
  DefaultIdx : CARDINAL;
  bits := -1;
  addrLim : Address.T;
  pgToSkip : [-1..LAST(CARDINAL)] := -1;
  copyRightPath : Pathname.T := NIL;
  allTerms : BOOLEAN;

VAR
  skipHoles := TRUE;
  attemptElimOverlaps : BOOLEAN;
  svOutput : Pathname.T := NIL;
  ifn : Pathname.T;

TYPE
  InputMode = { Default, CSV, CRIF };

VAR
  mode := InputMode.Default;
  templateRd : Rd.T := NIL;
  baseStrapBits : TEXT := NIL;
  bindings := NEW(TextTextTbl.Default).init();

BEGIN
  (* setup default PGs per HLP HAS *)
  PolicyGroupArr := NEW(REF ARRAY OF TEXT, NUMBER(DefPolicyGroupArr));
  DefaultIdx := LAST(PolicyGroupArr^)+1;
  FOR i := FIRST(DefPolicyGroupArr) TO LAST(DefPolicyGroupArr) DO
    PolicyGroupArr[i] := DefPolicyGroupArr[i];
  END;
  
  TRY
    WITH pp = NEW(ParseParams.T).init(Stdio.stderr) DO
      allTerms := pp.keywordPresent("-allminterms");

      IF pp.keywordPresent("-M") OR pp.keywordPresent("--module") THEN
        WITH modName = pp.getNext() DO
          EVAL bindings.put("MODULE_NAME", modName);
          svOutput := modName & ".sv"
        END
      END;
      IF pp.keywordPresent("-sv") THEN svOutput := pp.getNext() END;

      IF pp.keywordPresent("-bits") THEN
        bits := pp.getNextInt();
        addrLim := Word.LeftShift(1, bits);
        (* predefine ADDR_BITS *)
        EVAL bindings.put("ADDR_BITS", Fmt.Int(bits))
      END;
      
      IF pp.keywordPresent("-skipholes") THEN
        (* skip *)
      ELSIF pp.keywordPresent("-noskipholes") THEN
        skipHoles := FALSE
      END;
      attemptElimOverlaps := pp.keywordPresent("-elimoverlaps");

      IF pp.keywordPresent("-h") OR pp.keywordPresent("--help") THEN
        Wr.PutText(Stdio.stderr, DoUsage() & "\n");
        Process.Exit(0)
      END;
      
      IF pp.keywordPresent("-defpgnm") THEN
        PgDefaultName := pp.getNext()
      END;

      IF pp.keywordPresent("-G") OR pp.keywordPresent("--policygroups") THEN
        WITH n = pp.getNextInt() DO
          PolicyGroupArr := NEW(REF ARRAY OF TEXT, n);
          DefaultIdx := n;
          FOR i := 0 TO n-1 DO
            PolicyGroupArr[i] := pp.getNext()
          END;
          EVAL bindings.put("NUM_PG", Fmt.Int(n))
        END
      END;

      IF pp.keywordPresent("-basestrapbits") THEN
        baseStrapBits := pp.getNext() 
      END;

      IF pp.keywordPresent("--template") OR pp.keywordPresent("-T") THEN
        WITH tfn = pp.getNext() DO
          IF TE(tfn, "HLP") THEN
            LoadTemplate("hlp_pg_template.sv.tmpl.tmpl")
          ELSIF TE (tfn, "DEFAULT") OR TE(tfn, "MST") THEN
            LoadTemplate("pg_template.sv.tmpl")
          ELSE
            LoadTemplate(tfn)
          END
        END
      ELSE
        LoadTemplate("pg_template.sv.tmpl")
      END;

      IF pp.keywordPresent("--display-template") THEN
        VAR
          buff : ARRAY [0..8191] OF CHAR;
          c : CARDINAL;
        BEGIN
          REPEAT
            c := Rd.GetSub(templateRd, buff);
            Wr.PutString(Stdio.stdout, SUBARRAY(buff, 0, c))
          UNTIL c = 0
        END;
        Process.Exit(0)
      END;

      IF pp.keywordPresent("-copyrightpath") THEN
        copyRightPath := pp.getNext()
      END;

      IF pp.keywordPresent("-csv") THEN
        ifn := pp.getNext();
        mode := InputMode.CSV
      ELSIF pp.keywordPresent("-crif") THEN
        ifn := pp.getNext();
        mode := InputMode.CRIF
      END;

      (* defines should be last so we can override implicit defines *)
      WHILE pp.keywordPresent("-D") OR pp.keywordPresent("--bind") DO
        VAR
          nm := pp.getNext();
          vl := pp.getNext();
        BEGIN
          EVAL bindings.put(nm,vl)
        END
      END;
      
      pp.skipParsed();

      IF mode = InputMode.Default THEN
        ifn := pp.getNext();
        mode := InputMode.CSV
      END;
      
      pp.finish();
    END;
    IF bits = -1 THEN Debug.Error("Must specify -bits") END;
    IF bits > MaxBitsAllowed THEN Debug.Error("Max # of bits currently supported is " & Fmt.Int(MaxBitsAllowed)) END
  EXCEPT
    ParseParams.Error => Debug.Error("Command-line params wrong:\n" & DoUsage())
  END;

  CASE mode OF
    InputMode.CSV => DoCSV(ifn)
  |
    InputMode.CRIF => PgCRIF.Parse(ifn, ProcessBuf)
  ELSE
    <*ASSERT FALSE*>
  END;

  IF NOT procBufOK THEN
    Debug.Error("register overlaps detected---cant continue")
  END;
  
  GenerateOutput()
END Main.
