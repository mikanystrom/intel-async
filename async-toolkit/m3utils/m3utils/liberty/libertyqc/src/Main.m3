(* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE Main;

(* 

   libertyqc : Simple quality control of Liberty timing files

   Current function is just to look for large (positive or negative) numbers in
   .lib files.  Other functions to be added later.

   Uses the Liberty parser from the Barefoot LAMB project to
   understand the Liberty files.

   Author : mika.nystroem@intel.com

   December, 2023

*)

IMPORT LibertyParseMain;
IMPORT ParseParams;
IMPORT Stdio;
IMPORT Debug;
IMPORT OSError;
IMPORT Rd;
IMPORT FileRd;
IMPORT AL;
FROM Fmt IMPORT F, Int, LongReal;
IMPORT Text;
IMPORT LibertyComponent;
IMPORT LibertyComponentChildren;
IMPORT RTName;
IMPORT LibertyAttrValExpr;
IMPORT LibertySorI;
IMPORT LibertyNumber;
IMPORT TextList;
IMPORT FloatMode;
IMPORT TextReader;
IMPORT Scan;
IMPORT Lex;
IMPORT LibertyHead;
IMPORT LibertyGroup;
IMPORT TextWr;
IMPORT RefSeq;
IMPORT RegEx, RegExList;
IMPORT Process;
IMPORT Wr;
IMPORT SeekRd;
IMPORT Thread;


<*FATAL Thread.Alerted*>


CONST TE = Text.Equal;
      LR = LongReal;

CONST HelpText =

"   perform basic QC on Liberty files \n" &
"\n" &
"   Currently we support only looking for maximum values.\n" &
"\n" &
"   -checkmaxval <value>\n" &
"\n" &
"     Look for values exceeding maximum.\n" &
"\n" &
"   -filtermax <value>\n" &
"\n" &
"     Skip values exceeding <value>.\n" &
"\n" &
"   -tag <tag regex>\n" &
"\n" &
"     Look only for values in contexts matching <tag regex>.  Repeated use of\n" &
"     this option means the logical conjunction of <tag regex>s.  For example\n" &
"\n" &
"     -tag cell tag timing -tag values\n" &
"\n" &
"     matches only values in a context that is inside a block tagged as a\n" &
"     cell, and as timing, and as values.\n" &
"\n" &
"   -maxprint <tag> <count>\n" &
"\n" &
"     Print only <count> matches for every instance of tag <tag> (globally)\n" &
"\n" &
"   <libfilename>\n" &
"   \n" &
"     Path to lib file.  Use - for standard input.\n" &
"\n" &
"   -worst\n" &
"\n" &
"      print data concerning the worst (largest) value matching\n" &
"\n" &
"   -help\n" &
"\n" &
"      print this help\n"&
"\n" &
"    EXAMPLE\n" &
"\n" &
"    zcat file.lib.gz | libertyqc -maxprint cell 2 -checkmaxval 1000 -tag cell -tag timing -tag values -worst -\n"
;
      
VAR Verbose := Debug.DebugThis("libertyqc");

TYPE Mode = { Maxval };

     ModeProc = PROCEDURE ();

CONST
  RunMode = ARRAY Mode OF ModeProc { RunMaxval };

TYPE
  LeafVisitor = OBJECT METHODS
    visitLeaf(leaf : LibertyComponent.T)
  END;
  
PROCEDURE VisitLeaves(root : LibertyComponent.T; v : LeafVisitor) =
  BEGIN
    IF root.canHaveChildren() THEN
      WITH children = root.children() DO
        FOR i := 0 TO children.size() - 1 DO
          WITH child = children.get(i) DO
            VisitLeaves(child, v)
          END
        END
      END
    ELSE
      v.visitLeaf(root)
    END
  END VisitLeaves;

TYPE
  MaxvalVisitor = LeafVisitor OBJECT
    maxval : LONGREAL;
  OVERRIDES
    visitLeaf := MaxvalVisitorVL;
  END;

PROCEDURE CheckString(str : TEXT; maxval : LONGREAL; p : LibertyComponent.T) =
  VAR
    ptr : TextList.T;
  BEGIN
    <*ASSERT str # NIL*>
    IF Verbose THEN Debug.Out("CheckString : " & str) END;
    WITH reader = NEW(TextReader.T).init(str),
         lst    = reader.shatter(",\n ;/\t\\\\", "") DO
      ptr := lst;
      
      WHILE ptr # NIL DO
        TRY
          <*ASSERT ptr.head # NIL*>
          IF Verbose THEN Debug.Out("Checking : " & ptr.head) END;
          CheckNumber(Scan.LongReal(ptr.head), maxval, p)
        EXCEPT
          Lex.Error, FloatMode.Trap => (* skip *)
        END;
        ptr := ptr.tail
      END
    END
  END CheckString;

PROCEDURE TagMatch(p : LibertyComponent.T; lst : RegExList.T) : BOOLEAN =
  VAR
    foundEx :BOOLEAN;
    rp := lst;
    ident : TEXT;
    q : LibertyComponent.T;
  BEGIN
    WHILE rp # NIL DO
      foundEx := FALSE;
      q := p;
      WHILE q # NIL DO
        TYPECASE q OF
          LibertyHead.T(h) => ident := h.ident
        |
          LibertyGroup.T(lg) => ident := lg.head.ident
        ELSE
          ident := NIL
        END;
        IF ident # NIL AND RegEx.Execute(rp.head, ident) # -1 THEN
          (* success -- found this regex among tags of this component *)
          foundEx := TRUE;
          EXIT
        END;
        q := q.parent
      END;
      (* at this point we looked for that regex among all the tags of p *)
      IF NOT foundEx THEN RETURN FALSE END;
      rp := rp.tail
    END;
    RETURN TRUE
  END TagMatch;
  
PROCEDURE CheckNumber(valarg : LONGREAL; maxval : LONGREAL; p : LibertyComponent.T) =
  VAR
    val : LONGREAL;
  BEGIN
    IF abs THEN val := ABS(valarg) ELSE val := valarg END;
    
    IF TagMatch(p, tagexlst) THEN
      IF val > maxval AND val <= filterMax THEN
        exitVal := 1;

        PROCEDURE Msg() : TEXT =
          BEGIN
            IF valarg > 0.0d0 THEN
              RETURN F("checkmaxval %s > %s at %s\n", LR(valarg), LR(maxval), FormatComp(p))
            ELSE
              RETURN F("checkmaxval ABS(%s) > %s at %s\n", LR(valarg), LR(maxval), FormatComp(p))
            END
          END Msg;
          
        BEGIN
          IF doWorst AND val > worstVal THEN
            worstTxt := Msg();
            worstVal := val
          END;
        
          IF CheckMaxprint(p, maxErrs) THEN
          
            Wr.PutText(Stdio.stdout, Msg());
            Wr.Flush(Stdio.stdout)
          END
        END
      END
    END
  END CheckNumber;

PROCEDURE CheckMaxprint(p : LibertyComponent.T; seq : RefSeq.T) : BOOLEAN =

  PROCEDURE CheckHead(h : LibertyHead.T) =
    BEGIN
      FOR i := 0 TO seq.size() - 1 DO
        WITH rec = NARROW(seq.get(i), MaxErrors) DO

          IF Verbose THEN
            Debug.Out(F("Checking %s against rec.tag %s", Debug.UnNil(h.ident),(rec.tag)));
          END;
          
          IF h.ident # NIL AND TE(rec.tag, h.ident) THEN
            IF Verbose THEN
              Debug.Out(F("CheckMaxprint tag match tag %s q %s",
                          (rec.tag), Int(q.getId())))
            END;
            IF rec.curObj = NIL OR rec.curObj # q THEN
              rec.curCnt := 0;
              rec.curObj := q
            END;

            INC(rec.curCnt);

            IF rec.curCnt > rec.maxCnt THEN doPrint := FALSE END
          END
        END
      END
    END CheckHead;
    
  VAR
    q       := p;
    doPrint := TRUE;
  BEGIN
    IF Verbose THEN
      Debug.Out("CheckMaxprint p.getId() = " & Int(p.getId()))
    END;
    
    WHILE q # NIL DO
      TYPECASE q OF
        LibertyHead.T(h) =>
        <*ASSERT h # NIL *>
        CheckHead(h)
      |
        LibertyGroup.T(lg) =>
        <*ASSERT lg # NIL*>
        <*ASSERT lg.head # NIL*>
        CheckHead(lg.head)
      ELSE
        (* skip *)
      END;
        
      q := q.parent;

    END;
    RETURN doPrint

  END CheckMaxprint;

PROCEDURE FormatComp(p : LibertyComponent.T) : TEXT =
  VAR
    <*NOWARN*>idStr := Int(p.getId());
    q := p;
    str := "";
    iStr := "";
    thisI : TEXT;
  BEGIN
    WHILE q # NIL DO
      str := RTName.GetByTC(TYPECODE(q)) & ":" & str;
      TYPECASE q OF
        LibertyHead.T(lh) => thisI := FormatHead(lh)
      |
        LibertyGroup.T(lg) => thisI := FormatHead(lg.head)
      ELSE
        thisI := NIL
      END;

      IF thisI # NIL THEN
        iStr := thisI & ":" & iStr;
      END;
      q := q.parent
    END;
    RETURN (* str & ":" & *) iStr (* & idStr  *)
  END FormatComp;

PROCEDURE FormatHead(h : LibertyHead.T) : TEXT =
  VAR
    wr := NEW(TextWr.T).init();
  BEGIN
    h.write(wr);
    RETURN TextWr.ToText(wr)
  END FormatHead;
  
PROCEDURE MaxvalVisitorVL(v : MaxvalVisitor; leaf : LibertyComponent.T) =
  BEGIN
    TYPECASE leaf OF
      LibertyAttrValExpr.String(ave) => CheckString(ave.val, v.maxval, leaf)
    |
      LibertyAttrValExpr.Boolean => (* skip *)
    |
      LibertyAttrValExpr.Expr => (* skip *)
    |
      LibertySorI.String(sori) =>  CheckString(sori.val, v.maxval, leaf)
    |
      LibertySorI.Ident =>  (* skip *)
    |
      LibertyNumber.Integer(int) =>
      IF FALSE THEN
        CheckNumber(FLOAT(int.val, LONGREAL), v.maxval, leaf)
      END
    |
      LibertyNumber.Floating(flt) => CheckNumber(flt.val,
                                                 v.maxval,
                                                 leaf)
    ELSE
      Debug.Warning("Unhandled leaf Component of type " & RTName.GetByTC(TYPECODE(leaf)))
    END
  END MaxvalVisitorVL;
  
PROCEDURE RunMaxval() =
  BEGIN
    VisitLeaves(lib, NEW(MaxvalVisitor, maxval := maxval))
  END RunMaxval;

TYPE
  MaxErrors = REF RECORD
    tag    : TEXT;
    maxCnt : CARDINAL;
    curObj : LibertyComponent.T;
    curCnt : CARDINAL;
  END;
  (* MaxErrors is used to limit output printing.

     For each output tag, print no more than maxCnt of a given message
     for each instance of that tag.
  *)

VAR
  modes    := SET OF Mode { };
  pp       := NEW(ParseParams.T).init(Stdio.stderr);
  rd       : Rd.T;
  lib      : LibertyComponent.T;
  maxval   := FIRST(LONGREAL);
  maxErrs  := NEW(RefSeq.T).init();
  tagexlst : RegExList.T := NIL;
  exitVal  := 0;

  doWorst : BOOLEAN;
  worstTxt : TEXT := NIL;
  worstVal := FIRST(LONGREAL);
  filterMax:= LAST(LONGREAL);

  abs      := TRUE;
  
BEGIN
  TRY
    abs     := NOT pp.keywordPresent("-noabs");
    
    doWorst := pp.keywordPresent("-worst");
    
    IF pp.keywordPresent("-help") OR pp.keywordPresent("--help") THEN
      Wr.PutText(Stdio.stderr, HelpText);
      Process.Exit(0)
    END;
    
    IF pp.keywordPresent("-checkmaxval") THEN
      modes := modes + SET OF Mode { Mode.Maxval };
      maxval := pp.getNextLongReal()
    END;
    
    IF pp.keywordPresent("-filtermax") THEN
      filterMax := pp.getNextLongReal()
    END;

    WHILE pp.keywordPresent("-maxprint") DO
      WITH tag = pp.getNext(),
           cnt = pp.getNextInt(),
           rec = NEW(MaxErrors, tag := tag, maxCnt := cnt) DO
        maxErrs.addhi(rec)
      END
    END;

    WHILE pp.keywordPresent("-tag")  DO
      WITH regstr = pp.getNext(),
           regex  = RegEx.Compile(regstr) DO
        tagexlst := RegExList.Cons(regex, tagexlst)
      END
    END;

    pp.skipParsed();
    
    WITH fn = pp.getNext() DO
      IF TE(fn, "-") THEN
        rd := SeekRd.Stdin()
        (* we can't just use Stdio.stdin here : 
           parser uses Rd.Seek() on its input stream *)
      ELSE
        TRY
          rd := FileRd.Open(fn)
        EXCEPT
          OSError.E(e) =>
          Debug.Error(F("Couldn't open liberty file \"%s\" : OSError.E : %s\n%s",
                        fn, AL.Format(e), HelpText))
        END
      END
    END;

    pp.finish()
  EXCEPT
    ParseParams.Error => Debug.Error("Can't parse command line\n" & HelpText)
  END;

  TRY
    lib := LibertyParseMain.Parse(rd);
    Rd.Close(rd)
  EXCEPT
    Rd.Failure(e) =>
    Debug.Error(F("I/O error while parsing liberty : Rd.Failure : %s\n%s",
                  AL.Format(e), HelpText))
  END;

  FOR mode := FIRST(Mode) TO LAST(Mode) DO
    IF mode IN modes THEN
      RunMode[mode]()
    END
  END;

  IF worstTxt # NIL THEN
    Wr.PutText(Stdio.stdout, "WORST : " & worstTxt);
    Wr.Flush(Stdio.stdout)
  END;

  Process.Exit(exitVal)
END Main.
