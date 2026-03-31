(* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE Main;

(* 

   libertyscale : Simple scaling of Liberty timing files

   Uses the Liberty parser from the Barefoot LAMB project to
   understand the Liberty files.

   Author : mika.nystroem@intel.com

   December, 2023


   Example command line:

   libertyscale  \
     -i lib783_i0s_160h_50pp_seq_ulvt_tttt_0p300v_85c_tttt_cmax_ccslnt.lib\
     -o lib1.lib\
     -timing_type min_pulse_width\
     -values ocv_sigma_rise_constraint -values ocv_sigma_fall_constraint\
     -factor 1

*)

IMPORT LibertyParseMain;
IMPORT ParseParams;
IMPORT Stdio;
IMPORT Debug;
IMPORT OSError;
IMPORT Rd;
IMPORT FileRd;
IMPORT AL;
FROM Fmt IMPORT F, LongReal, Bool, Int;
IMPORT Text;
IMPORT LibertyComponent;
IMPORT LibertyComponentChildren;
IMPORT RTName;
IMPORT LibertySorI;
IMPORT FloatMode;
IMPORT TextReader;
IMPORT Scan;
IMPORT Lex;
IMPORT LibertyHead;
IMPORT LibertyGroup;
IMPORT TextWr;
IMPORT Process;
IMPORT Wr;
IMPORT SeekRd;
IMPORT Thread;
IMPORT LibertySimpleAttr;
IMPORT FileWr;
IMPORT Params;
IMPORT ProcUtils;
IMPORT TextList;
FROM TechLookup IMPORT Lookup;
IMPORT LibertyAttrVal;
IMPORT LibertyAttrValExpr;
IMPORT LibertyExpr;
IMPORT LibertyNumber;
IMPORT Wx;
<*FATAL Thread.Alerted*>

CONST TE = Text.Equal;
      LR = LongReal;

CONST HelpText = "Usage : libertyscale [-help|--help] -i <input lib> -o <output lib> [-factor <scale factor> -timing_type <timing_type> -values <edit values> [-values <edit values> ...] -factor <scale factor>] [-temp <temp in Celsius>] [-volt <vcc>] [-alltiming <scale factor>] [-proc fast|typical|slow] [-libname <lib name>]";
      
VAR
  pp              := NEW(ParseParams.T).init(Stdio.stderr);
  rd       : Rd.T;
  wr       : Wr.T := Stdio.stdout;
  lib      : LibertyComponent.T;
  Verbose         := Debug.DebugThis("libertyscale");

TYPE
  Visitor = OBJECT METHODS
    visit(x : LibertyComponent.T) : Visitor;
    (* return visitor to apply to children.

       In general, a Visitor will seek a match and then return a new
       Visitor to seek within the children of the last match point.

       A Visitor can return NIL to signify that its subtree is not to
       be searched further.
    *)
  END;

  Executor = OBJECT METHODS
    execute(x : LibertyComponent.T);
    (* do *something* to a component *)
  END;

  LibNameUpdater = Executor OBJECT
    libName : TEXT;
  OVERRIDES
    execute := LNUExecute;
  END;

  VoltageUpdater = Executor OBJECT
    (* not just used to update voltage but that's what it was invented for *)
    ignoreValue := 0.0d0;
    voltage : LONGREAL;
  OVERRIDES
    execute := VUExecute;
  END;

  VoltageMapUpdater = Executor OBJECT
    voltage : LONGREAL;
  OVERRIDES
    execute := VMUExecute;
  END;

  OpcUpdater = Executor OBJECT
    opc : TEXT;
  OVERRIDES
    execute := OUExecute;
  END;

PROCEDURE OUExecute(self : OpcUpdater; x : LibertyComponent.T) =
  BEGIN
    IF Verbose THEN
      Debug.Out(F("Got opc : \n" & x.debugDump()))
    END;
    WITH sa   = NARROW(x, LibertySimpleAttr.T),
         expr = sa.attrValExpr DO
      TYPECASE expr OF
        LibertyAttrValExpr.Expr(lax) =>
        TYPECASE lax.val OF
          LibertyExpr.Const(const) =>
          IF Verbose THEN
            Debug.Out(F("val : %s -> %s", const.val, self.opc))
          END;
          const.val := self.opc
        ELSE
          (* skip *)
        END
      ELSE
        (* skip *)
      END
    END
  END OUExecute;
  
PROCEDURE VUExecute(self : VoltageUpdater; x : LibertyComponent.T) =
  BEGIN
    IF Verbose THEN
      Debug.Out(F("Got volt : \n" & x.debugDump()))
    END;

    WITH sa   = NARROW(x, LibertySimpleAttr.T),
         expr = sa.attrValExpr DO
      TYPECASE expr OF
        LibertyAttrValExpr.Expr(lax) =>
        TYPECASE lax.val OF
          LibertyExpr.FloatLiteral(fl) =>
          IF fl.val # self.ignoreValue THEN
            IF Verbose THEN
              Debug.Out(F("val : %s -> %s", LR(fl.val), LR(self.voltage)))
            END;
            fl.val := self.voltage
          END
        |
          LibertyExpr.IntLiteral(il) =>
          IF FLOAT(il.val,LONGREAL) # self.ignoreValue THEN
            IF Verbose THEN
              Debug.Out(F("val : %s -> %s", Int(il.val), LR(self.voltage)))
            END;
            WITH intVal = ROUND(self.voltage) DO
              IF FLOAT(intVal, LONGREAL) = self.voltage THEN
                il.val := intVal
              ELSE
                lax.val := NEW(LibertyExpr.FloatLiteral, val := self.voltage)
              END
            END
          END
        ELSE
          (* skip *)
        END
      ELSE
        (* skip *)
      END
    END
  END VUExecute;

PROCEDURE VMUExecute(self : VoltageMapUpdater; x : LibertyComponent.T) =
  BEGIN
    IF Verbose THEN
      Debug.Out(F("Got voltage_map : \n" & x.debugDump()))
    END;

    WITH head = NARROW(x, LibertyHead.T) DO
      IF head.params.size() = 2 THEN
        WITH val = head.params.get(1) DO
          TYPECASE val OF
            LibertyAttrVal.Num(num) =>
            TYPECASE num.val OF
              LibertyNumber.Floating(fl) =>
              IF fl.val # 0.0d0 THEN
                IF Verbose THEN
                  Debug.Out(F("val : %s -> %s", LR(fl.val), LR(self.voltage)))
                END;
                fl.val := self.voltage
              END
            ELSE
              (* skip *)
            END
          ELSE
            (* skip *)
          END
        END
      END
    END
  END VMUExecute;

PROCEDURE LNUExecute(self : LibNameUpdater; x : LibertyComponent.T) =
  
  BEGIN
    IF Verbose THEN
      Debug.Out(F("Got lib : \n" & x.debugDump()))
    END;

    WITH head = NARROW(x, LibertyHead.T),
         sori = NARROW(head.params.get(0), LibertyAttrVal.SorI).val,
         ident = NARROW(sori, LibertySorI.Ident) DO
      IF Verbose THEN Debug.Out(F("Got ident : \n" & ident.debugDump())) END;
      ident.val := self.libName
    END
  END LNUExecute;
  
PROCEDURE VisitAll(x : LibertyComponent.T; v : Visitor) =
  BEGIN
    WITH newv = v.visit(x) DO
      
      IF newv # NIL AND x.canHaveChildren() THEN
        WITH children = x.children() DO
          FOR i := 0 TO children.size() - 1 DO
            WITH child = children.get(i) DO
              VisitAll(child, newv)
            END
          END
        END
      END
    END
  END VisitAll;

TYPE
  ChainedVisitor = Visitor OBJECT
    next     : Visitor  := NIL;
    executor : Executor := NIL;
  END;
  (* a ChainedVisitor is a type of Visitor that, when it has found its 
     target, returns the next visitor to seek the next target.

     If executor is non-NIL, then it will be called on the matched
     LibertyComponent at the time of match, which results in pre-order
     execution on the tree.  (executor.execute is called before children
     are visited.)
  *)
  
  TaggedVisitor = ChainedVisitor OBJECT
    tag         : TEXT;
    needAttr    : TEXT := NIL;
    needAttrVal : TEXT := NIL;
  OVERRIDES
    visit := TaggedVisit;
  END;
  (* a TaggedVisitor is a type of a ChainedVisitor that looks for a 
     specific tag.  If needAttr is specified, it also requires that
     the given attr matches the attrval in order to report a match.
     When matched, it returns the next Visitor in the chain. 

     An example attribute might be to seek 

     a timing() block with the attribute

     timing_type : min_pulse_width

     within.
  *)

  HeadVisitor = ChainedVisitor OBJECT
    tag         : TEXT;
  OVERRIDES
    visit := HeadVisit;
  END;
  (* seek a specific tagged Head (for example values() ) *)

  SimpleAttrVisitor = ChainedVisitor OBJECT
    tag         : REF ARRAY OF TEXT;
  OVERRIDES
    visit := SimpleAttrVisit;
  END;

  OrVisitor = Visitor OBJECT
    disjuncts : REF ARRAY OF Visitor;
  METHODS
    init2(a, b : Visitor) : OrVisitor := InitOV2;
  OVERRIDES
    visit := OrVisit;
  END;
  (* an OrVisitor passes over the Visitors in the disjuncts.
     If any Visitor in the disjuncts matches (i.e., returns a 
     different Visitor from itself), the result is to return the
     new Visitor.  If none match, return itself to continue.
     
     The implementation results in a short-circuit evaluation.
  *)

  StringVisitor = Visitor OBJECT
    editor : StringEditor;
  OVERRIDES
    visit := StringVisit;
  END;
  (* search for a String.  Once the String has been found, call the editor
     on the String. Returns itself---so it is applied to all Strings below
     a given point in the parse tree. 
  *)

  StringEditor = OBJECT METHODS
    edit(str : TEXT) : TEXT;
  END;
  (* simple abstract object to do a string edit *)
  
PROCEDURE StringVisit(sv : StringVisitor; c : LibertyComponent.T) : Visitor =
  BEGIN
    TYPECASE c OF
      LibertySorI.String(str) =>
      str.val := sv.editor.edit(str.val)
    ELSE
      (*skip*)
    END;
    RETURN sv
  END StringVisit;
    
PROCEDURE InitOV2(ov : OrVisitor; a, b : Visitor) : OrVisitor =
  VAR
    arr := NEW(REF ARRAY OF Visitor, 2);
  BEGIN
    arr[0] := a;
    arr[1] := b;
    ov.disjuncts := arr;
    RETURN ov
  END InitOV2;

PROCEDURE OrVisit(ov : OrVisitor; c : LibertyComponent.T) : Visitor =
  BEGIN
    FOR i := FIRST(ov.disjuncts^) TO LAST(ov.disjuncts^) DO
      WITH thisV = ov.disjuncts[i],
           newV  = thisV.visit(c) DO
        IF newV # thisV THEN RETURN newV END
      END
    END;
    RETURN ov
  END OrVisit;

PROCEDURE HeadVisit(hv : HeadVisitor; c : LibertyComponent.T) : Visitor =
  VAR
    success : BOOLEAN;
  BEGIN
    TYPECASE c OF
      LibertyHead.T(lh) =>
      success := TE(lh.ident, hv.tag);
      WITH sstr    = ARRAY BOOLEAN OF TEXT { "", " SUCCESS" }[success] DO
        IF Verbose THEN
          Debug.Out(F("Seeking tag %s in LibertyHead object with tag %s %s : %s",
                      hv.tag, lh.ident, sstr, lh.format()));
          IF success THEN
            Debug.Out("Success with head: obj:\n" & lh.debugDump())
          END
        END;
        
        IF success THEN
          IF hv.executor # NIL THEN
            hv.executor.execute(c)
          END;
          RETURN hv.next
        END
      END
    ELSE
      (* skip *)
    END;
    RETURN hv
  END HeadVisit;

PROCEDURE FmtArr(READONLY a : ARRAY OF TEXT) : TEXT =
  VAR
    wx := Wx.New();
  BEGIN
    Wx.PutChar(wx, '[');
    FOR i := FIRST(a) TO LAST(a) DO
      Wx.PutChar(wx, ' ');
      Wx.PutText(wx, a[i])
    END;
    Wx.PutText(wx, " }");
    RETURN Wx.ToText(wx)
  END FmtArr;

PROCEDURE MakeArrP(READONLY a : ARRAY OF TEXT) : REF ARRAY OF TEXT =
  VAR
    res := NEW(REF ARRAY OF TEXT, NUMBER(a));
  BEGIN
    res^ := a;
    RETURN res
  END MakeArrP;
  
PROCEDURE SimpleAttrVisit(hv : SimpleAttrVisitor; c : LibertyComponent.T) : Visitor =
  VAR
    success := FALSE;
  BEGIN
    TYPECASE c OF
      LibertySimpleAttr.T(x) =>
      FOR i := FIRST(hv.tag^) TO LAST(hv.tag^) DO
        success := success OR TE(x.ident, hv.tag[i])
      END;
      WITH sstr    = ARRAY BOOLEAN OF TEXT { "", " SUCCESS" }[success] DO
        IF Verbose THEN
          Debug.Out(F("Seeking tag %s in LibertySimpleAttr object with tag %s %s : %s",
                      FmtArr(hv.tag^), x.ident, sstr, x.format()));
          IF success THEN
            Debug.Out("Success with simpleattr: obj:\n" & x.debugDump())
          END
        END;
        
        IF success THEN
          IF hv.executor # NIL THEN
            hv.executor.execute(c)
          END;
          RETURN hv.next
        END
      END
    ELSE
      (* skip *)
    END;
    RETURN hv
  END SimpleAttrVisit;
  
PROCEDURE TaggedVisit(tv : TaggedVisitor; c : LibertyComponent.T) : Visitor =
  VAR
    success : BOOLEAN;
  BEGIN
    TYPECASE c OF
      LibertyGroup.T(lg) =>

      success :=  TE(lg.head.ident, tv.tag);
      WITH sstr    = ARRAY BOOLEAN OF TEXT { "", " SUCCESS" }[success] DO
        IF Verbose THEN
          Debug.Out(F("Seeking tag %s in object with head tag %s %s",
                      tv.tag, lg.head.ident, sstr))
        END;
          
          
        IF success AND tv.needAttr # NIL THEN
          success := FALSE;
          Debug.Out("Seeking attr " & tv.needAttr);
          FOR i := 0 TO lg.statements.size() - 1 DO
            WITH s = lg.statements.get(i) DO
              TYPECASE s OF
                LibertySimpleAttr.T(sa) =>
                IF TE(sa.ident, tv.needAttr) THEN
                  IF Verbose THEN
                    Debug.Out(F("matched attr %s type %s : %s", sa.ident, RTName.GetByTC(TYPECODE(sa.attrValExpr)), sa.attrValExpr.format()))
                  END;
                  IF tv.needAttrVal = NIL THEN
                    success := TRUE
                  ELSE
                    success := TE(sa.attrValExpr.format(), tv.needAttrVal);
                    IF Verbose THEN
                      Debug.Out(F("tv.needAttrVal %s, success %s",
                                  tv.needAttrVal, Bool(success)))
                    END;
                  END;
                  EXIT
                END
              ELSE
                (* skip *)
              END
            END
          END
        END;
        
        IF success THEN
          IF tv.executor # NIL THEN
            tv.executor.execute(c)
          END;
          RETURN tv.next
        ELSE
          RETURN tv
        END
      END
    ELSE
      RETURN tv
    END
  END TaggedVisit;

PROCEDURE DoTimingUpdate(timingType   : TEXT;
                         timingValues : TextList.T) =
  VAR
      valuesChanger    : HeadVisitor;
      valuesVisitors   := NEW(REF ARRAY OF Visitor, TextList.Length(timingValues));
    BEGIN
      valuesChanger := NEW(HeadVisitor,
                            tag  := "values",
                            next := NEW(StringVisitor,
                                        editor := NEW(StringScaler,
                                                      mult := scaleFac)));

      FOR i := FIRST(valuesVisitors^) TO LAST(valuesVisitors^) DO
        valuesVisitors[i] := NEW(TaggedVisitor,
                                 tag  := TextList.Nth(timingValues,i),
                                 next := valuesChanger)
      END;
    

      VAR
        ocvRiseOrFallVisitor := NEW(OrVisitor, disjuncts := valuesVisitors);

        timingTagVisitor := NEW(TaggedVisitor,
                                tag         := "timing",
                                needAttr    := "timing_type",
                                needAttrVal := timingType,
                                next        := ocvRiseOrFallVisitor);
        cellTagVisitor   := NEW(TaggedVisitor,
                                tag  := "cell"  ,
                                next := timingTagVisitor);
        
      BEGIN
        VisitAll(lib, cellTagVisitor)
      END
    END DoTimingUpdate;

PROCEDURE DoAllTimingUpdate(allTimingFac : LONGREAL) =
  VAR
    valuesChanger : HeadVisitor;
  BEGIN
    valuesChanger := NEW(HeadVisitor,
                         tag  := "values",
                         next := NEW(StringVisitor,
                                     editor := NEW(StringScaler,
                                                   mult := allTimingFac)));
    VAR
      timingTagVisitor := NEW(TaggedVisitor,
                              tag         := "timing",
                              next        := valuesChanger);
    BEGIN
      VisitAll(lib, timingTagVisitor)
    END

  END DoAllTimingUpdate;

PROCEDURE DoLibNameUpdate(libName : TEXT) =
  VAR
    valuesChanger : HeadVisitor;
  BEGIN
    valuesChanger := NEW(HeadVisitor,
                         tag := "library",
                         executor := NEW(LibNameUpdater,
                                         libName := libName));
    
    VisitAll(lib, valuesChanger)
  END DoLibNameUpdate;

PROCEDURE DoOpcHeadNameUpdate(opc : TEXT) =
  VAR
    valuesChanger : HeadVisitor;
  BEGIN
    valuesChanger := NEW(HeadVisitor,
                         tag := "operating_conditions",
                         executor := NEW(LibNameUpdater,
                                         libName := opc));
    
    VisitAll(lib, valuesChanger)
  END DoOpcHeadNameUpdate;
  
PROCEDURE DoVoltUpdate(volt : LONGREAL) =
  VAR
    valuesChanger : SimpleAttrVisitor;
    headChanger : HeadVisitor;
  BEGIN
    valuesChanger := NEW(SimpleAttrVisitor,
                         tag := MakeArrP(VoltNames),
                         executor := NEW(VoltageUpdater,
                                         voltage := volt));
    VisitAll(lib, valuesChanger);

    headChanger := NEW(HeadVisitor,
                       tag := "voltage_map",
                       executor := NEW(VoltageMapUpdater,
                                       voltage := volt));

    VisitAll(lib, headChanger)
  END DoVoltUpdate;
  
PROCEDURE DoTempUpdate(temp : LONGREAL) =
  VAR
    valuesChanger : SimpleAttrVisitor;
  BEGIN
    valuesChanger := NEW(SimpleAttrVisitor,
                         tag := MakeArrP(TempNames),
                         executor := NEW(VoltageUpdater (* not really! *),
                                         ignoreValue := FIRST(LONGREAL),
                                         voltage := temp));
    VisitAll(lib, valuesChanger)
  END DoTempUpdate;

PROCEDURE DoProcUpdate(proc : Proc) =
  VAR
    valuesChanger : SimpleAttrVisitor;
    opcName := ProcOpcLabels[proc];
  BEGIN

    valuesChanger := NEW(SimpleAttrVisitor,
                         tag := MakeArrP(OpcNames),
                         executor := NEW(OpcUpdater,
                                         opc := opcName));
    VisitAll(lib, valuesChanger);

    DoOpcHeadNameUpdate(opcName)
  END DoProcUpdate;

CONST
  VoltNames =
    ARRAY OF TEXT { "voltage", "vih", "voh", "vimax", "vomax", "nom_voltage" };
  OpcNames =
    ARRAY OF TEXT { "operating_conditions", "default_operating_conditions" };
  TempNames =
    ARRAY OF TEXT { "temperature", "nom_temperature" };

TYPE
  StringScaler = StringEditor OBJECT
    mult : LONGREAL;
  OVERRIDES
    edit := StringScalerEdit;
  END;

PROCEDURE CleanStr(str : TEXT) : TEXT =
  VAR
    s := 0;
    len := Text.Length(str);
  CONST
    Legal = SET OF CHAR { '0'..'9', 'e', 'E', '+', '-', '.' };
  BEGIN
    WHILE s < len AND NOT Text.GetChar(str, s) IN Legal DO
      INC(s)
    END;
    IF s = 0 THEN
      RETURN str
    ELSE
      RETURN Text.Sub(str, s)
    END
  END CleanStr;
  
PROCEDURE StringScalerEdit(ss : StringScaler; in : TEXT) : TEXT =
  <*FATAL Wr.Failure*>
  VAR
    reader := NEW(TextReader.T).init(in);
    lst    := reader.shatter(",", "");
    wr     := TextWr.New();
    p      := lst;
  BEGIN
    IF Verbose THEN
      Debug.Out(F("StringScalerEdit: in=\"%s\"", in))
    END;
    WHILE p # NIL DO
      TRY
        WITH val       = Scan.LongReal(CleanStr(p.head)),
             scaledVal = val * ss.mult DO
          Wr.PutText(wr, LR(scaledVal))
        END
      EXCEPT
        Lex.Error, FloatMode.Trap =>
        Debug.Error("Couldn't parse values number \"" & p.head & "\"")
      END;
      
      IF p.tail # NIL THEN
        Wr.PutText(wr, ", ")
      END;
      
      p := p.tail
    END;
    WITH out = TextWr.ToText(wr) DO
      IF Verbose THEN
        Debug.Out(F("StringScalerEdit: out=\"%s\"", out))
      END;
      RETURN out
    END
  END StringScalerEdit;

TYPE
  Proc = { Slow, Typical, Fast };
CONST
  ProcNames      = ARRAY Proc OF TEXT { "slow", "typical", "fast" };
  ProcOpcLabels  = ARRAY Proc OF TEXT { "slow_1.00", "typical_1.00", "fast_1.00" };
  
VAR (* variables to control the matching *)
  timingType    : TEXT       := NIL;
  timingValues  : TextList.T := NIL;
  scaleFac                   := 1.0d0;
  temp          : LONGREAL;
  forceTemp                  := FALSE;
  proc          : Proc;
  forceProc                  := FALSE;
  libName       : TEXT       := NIL;
  volt          : LONGREAL;
  forceVolt                  := FALSE;

  allTimingFac               := 1.0d0;
  
BEGIN
  TRY
    IF pp.keywordPresent("-help") OR pp.keywordPresent("--help") THEN
      TRY Wr.PutText(Stdio.stderr, HelpText) EXCEPT ELSE END;
      Process.Exit(0)
    END;

    IF pp.keywordPresent("-factor") THEN
      scaleFac := pp.getNextLongReal()
    END;

    IF pp.keywordPresent("-timing_type") THEN
      timingType := pp.getNext()
    END;

    IF pp.keywordPresent("-temp") THEN
      temp := pp.getNextLongReal();
      forceTemp := TRUE;
    END;

    IF pp.keywordPresent("-volt") THEN
      volt := pp.getNextLongReal();
      forceVolt := TRUE;
    END;

    IF pp.keywordPresent("-alltiming") THEN
      allTimingFac := pp.getNextLongReal()
    END;

    IF pp.keywordPresent("-proc") THEN
      WITH ptxt = pp.getNext() DO
        proc := VAL(Lookup(ptxt, ProcNames), Proc);
        forceProc := TRUE;
      END
    END;

    IF pp.keywordPresent("-libname") THEN
      libName := pp.getNext()
    END;

    WHILE pp.keywordPresent("-values") DO
      IF timingType = NIL THEN
        Debug.Error("?must specify -timing_type")
      END;
      timingValues := TextList.Cons(pp.getNext(), timingValues)
    END;
    
    IF pp.keywordPresent("-i") THEN
      WITH fn = pp.getNext() DO
        IF TE(fn, "-") THEN
          rd := SeekRd.Stdin()
        ELSE
          TRY
            rd := FileRd.Open(fn)
          EXCEPT
            OSError.E(e) =>
            Debug.Error(F("Couldn't open liberty file \"%s\" : OSError.E : %s\n%s",
                          fn, AL.Format(e), HelpText))
          END
        END
      END
    END;

    IF pp.keywordPresent("-o") THEN
      WITH fn = pp.getNext() DO
        IF TE(fn, "-") THEN
          wr := Stdio.stdout
        ELSE
          TRY
            wr := FileWr.Open(fn)
          EXCEPT
            OSError.E(e) =>
            Debug.Error(F("Couldn't open output file \"%s\" : OSError.E : %s\n%s",
                          fn, AL.Format(e), HelpText))
          END
        END
      END
    END;

    
    pp.skipParsed();
    pp.finish()

  EXCEPT
    ParseParams.Error => Debug.Error("Can't parse command line\n" & HelpText)
  END;

  TRY
    Debug.Out("Parsing lib...");
    lib := LibertyParseMain.Parse(rd);
    Debug.Out("Done parsing lib.");
    Rd.Close(rd)
  EXCEPT
    Rd.Failure(e) =>
    Debug.Error(F("I/O error while parsing liberty : Rd.Failure : %s\n%s",
                  AL.Format(e), HelpText))
  END;

  IF libName # NIL THEN
    DoLibNameUpdate(libName)
  END;
  
  IF timingType # NIL THEN
    DoTimingUpdate(timingType, timingValues)
  END;

  IF forceTemp THEN
    DoTempUpdate(temp)
  END;

  IF forceVolt THEN
    DoVoltUpdate(volt)
  END;

  IF forceProc THEN
    DoProcUpdate(proc)
  END;

  IF allTimingFac # 1.0d0 THEN
    DoAllTimingUpdate(allTimingFac)
  END;

  TRY
    Wr.PutText(wr, "/* DO NOT EDIT : generated by \n");
    Wr.PutChar(wr, '\n');
    Wr.PutText(wr, "  ");
    FOR i := 0 TO Params.Count - 1 DO
      Wr.PutText(wr, " ");
      Wr.PutText(wr, Params.Get(i))
    END;
    Wr.PutChar(wr, '\n');
    Wr.PutChar(wr, '\n');

    Wr.PutText(wr, "   Run at ");
    TRY
      ProcUtils.RunText("/usr/bin/date",
                        stdout := ProcUtils.WriteHere(wr)).wait();
    EXCEPT
      ProcUtils.ErrorExit(e) =>
      Debug.Error("Caught error exit running /usr/bin/date : " & e.error)
    END;
    Wr.PutChar(wr, '\n');
    
    Wr.PutText(wr, "   cwd : " & Process.GetWorkingDirectory() & "\n");
    Wr.PutChar(wr, '\n');

    Wr.PutText(wr, "*/\n\n");
    
    lib.write(wr);
    Wr.Close(wr)
  EXCEPT
    OSError.E(e) =>
    Debug.Error("Unable to write output lib file : OSError.E : " & AL.Format(e))
  |
    Wr.Failure(e) =>
    Debug.Error("Unable to write output lib file : Wr.Failure : " & AL.Format(e))
  END

END Main.
