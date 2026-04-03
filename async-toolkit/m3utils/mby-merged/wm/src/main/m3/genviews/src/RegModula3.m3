(* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE RegModula3 EXPORTS RegModula3, RegModula3Generators, RegModula3Utils;
IMPORT Wr, Thread, RegAddrmap;
IMPORT BigInt;
FROM Fmt IMPORT F;
IMPORT Pathname, OSError;
IMPORT FileWr;
IMPORT RegReg, RegRegfile, RegField;
IMPORT Fmt, Word, Debug;
IMPORT Wx;
IMPORT RdlArray;
IMPORT TextSetDef;
IMPORT RegComponent;
FROM RegModula3Constants IMPORT IdiomName;
IMPORT RegGenState;
IMPORT RegChild;
IMPORT CompAddr, CompRange;
FROM CompRange IMPORT Prop, PropNames;
FROM Compiler IMPORT ThisLine, ThisFile;
IMPORT RegFieldArraySort, RegFieldSeq;
FROM RegModula3GenState IMPORT Section;
IMPORT RegModula3GenState;
IMPORT TextSet;
IMPORT RegContainer;
IMPORT CardSet, CardSetDef;
IMPORT RdlNum;
FROM RegModula3IntfNaming IMPORT MapIntfNameRW;
IMPORT GenViewsM3;
IMPORT TextSeq;

(* this stuff really shouldnt be in this module but in Main... *)
IMPORT RdlProperty, RdlExplicitPropertyAssign;
IMPORT RdlPropertyRvalueKeyword;
FROM RegProperty IMPORT GetKw, GetNumeric;

<*FATAL BigInt.OutOfRange*>

CONST LastISection = Section.ITrailer;
      FirstMSection = Section.MImport;

  (**********************************************************************)

  (* move Genstate into its own files...? *)
      
TYPE
  GenState = RegModula3GenState.T OBJECT
    map         : RegAddrmap.T;
    fieldWidths : CardSet.T;
  METHODS
    init(o : GenState) : GenState := InitGS;
    p(sec : Section; fmt : TEXT; t1, t2, t3, t4, t5 : TEXT := NIL) := GsP;
    mdecl(fmt : TEXT; t1, t2, t3, t4, t5 : TEXT := NIL) := GsMdecl;
    imain(fmt : TEXT; t1, t2, t3, t4, t5 : TEXT := NIL) := GsImain;

    defProc(c : RegComponent.T; ofType : ProcType; VAR pnm : TEXT; intf := TRUE) : BOOLEAN := DefProc;
    (* if returns FALSE, do not generate code! *)
    
  OVERRIDES
    put  := PutGS;
  END;

TYPE ProcType = { Csr, Range, Reset, Visit };

CONST DeclFmt = ARRAY ProcType OF TEXT {
  "PROCEDURE %s(VAR t : %s; READONLY a : %s; VAR op : CsrOp.T)",
  "PROCEDURE %s(READONLY a : %s) : CompRange.T",
  "PROCEDURE %s(READONLY t : %s; READONLY u : %s)",
  "PROCEDURE %s(READONLY a : %s; v : AddrVisitor.T; array : AddrVisitor.Array; parent : AddrVisitor.Internal)"
  };
(* we could extend this pattern to other procedure definitions ... *)
  
PROCEDURE DefProc(gs     : GenState;
                  c      : RegComponent.T;
                  ofType : ProcType;
                  VAR pnm: TEXT;
                  intf   : BOOLEAN) : BOOLEAN =
  VAR
    ttn := ComponentTypeNameInHier(c, gs, TypeHier.Read);
    atn := ComponentTypeNameInHier(c, gs, TypeHier.Addr);
    utn := ComponentTypeNameInHier(c, gs, TypeHier.Update);
  <*FATAL OSError.E, Thread.Alerted, Wr.Failure*>
  BEGIN
    pnm := ComponentName[ofType](c, gs);
    WITH hadIt = NOT gs.newSymbol(pnm) DO

      IF FALSE THEN
        Debug.Out(F("hadIt(%s) = %s", pnm, Fmt.Bool(hadIt)))
      END;
      IF hadIt THEN RETURN FALSE END
    END;

    CASE ofType OF
      ProcType.Csr =>
      gs.mdecl(DeclFmt[ofType] & " = \n", pnm, ttn, atn);
      IF intf THEN gs
        .imain(DeclFmt[ofType] & ";\n", pnm, ttn, atn);
      END
    |
      ProcType.Range, ProcType.Visit =>
      gs.mdecl(DeclFmt[ofType] & " = \n", pnm, atn);
      IF intf THEN gs
        .imain(DeclFmt[ofType] & ";\n", pnm, atn);
      END
    |
      ProcType.Reset =>
      gs.mdecl(DeclFmt[ofType] & " = \n", pnm, ttn, utn);
      IF intf THEN gs
        .imain(DeclFmt[ofType] & ";\n", pnm, ttn, utn);
      END
    END;
    RETURN TRUE
  END DefProc;

PROCEDURE GsP(gs  : GenState;
              sec : Section;
              fmt : TEXT;
              t1, t2, t3, t4, t5 : TEXT) =
  BEGIN gs.put(sec, F(fmt, t1, t2, t3, t4, t5)) END GsP;
  
PROCEDURE GsMdecl(gs : GenState; fmt : TEXT; t1, t2, t3, t4, t5 : TEXT := NIL)=
  BEGIN gs.p(Section.MDecl, fmt, t1, t2, t3, t4, t5) END GsMdecl;
  
PROCEDURE GsImain(gs : GenState; fmt : TEXT; t1, t2, t3, t4, t5 : TEXT := NIL)=
  BEGIN gs.p(Section.IMaintype, fmt, t1, t2, t3, t4, t5) END GsImain;
  

PROCEDURE InitGS(n, o : GenState) : GenState =
  BEGIN
    n := RegGenState.T.initF(n, o);
    n.map := o.map;
    n.wx := o.wx;
    n.rw := o.rw;
    n.th := o.th;
    RETURN n
  END InitGS;

PROCEDURE PutGS(gs : GenState; sec : Section; txt : TEXT) =
  BEGIN
    Wx.PutText(gs.wx[sec], txt)
  END PutGS;

  (**********************************************************************)

  (* basic idea:

     an addrmap can "contain" other addrmaps, regfiles, and regs.

     an addrmap corresponds to a Modula-3 interface (actually two), 
     with three types.

     T : a RECORD that matches the RDL, for read-only use (state -> WM)

     U : a RECORD that matches the RDL, for write-only use (WM -> state)

     A : a RECORD that matches the RDL, with addressing info (SB)

     X : a RECORD that matches the RDL, with addressing info (WM machine)

     Normal white-model use can be expected to rely on T (mainly) and
     U (for updates).

     regfiles and regs tend to be RECORDS, but there is an exception
     for regfiles that have only a single (syntactic) member: these
     are ARRAYs (see skipArc in the code).

     There are a few matching codes generated...

     Init : initialize the addresses in the A RECORD

     UpdateInit : initialize the updaters in the U RECORD

     CsrAccess : push a write down the tree to the leaves of the T
                 record.  This is how a write into U gets reflected in
                 T.  It also allows for "software writes" using
                 regular memory addressing with the addresses per the
                 RDL definitions used.

     Visit : visit the internals and fields of the A record

     The two interfaces appear in the code as "RW.R" (for the XXX_map.i3)
     and "RW.W" (for the XXX_map_addr.i3).

     XXX_map.T is in XXX_map.

     XXX_map_addr.U and XXX_map_addr.A are in XXX_map_addr.

     T, U, A, and X appear as TypeHier.Read, TypeHier.Update, 
     TypeHier.Addr, and TypeHier.Unsafe respectively 
  *)

VAR mapsDone := NEW(TextSetDef.T).init();
    (* global set of addrmaps that we have generated so far *)

VAR doDebug := Debug.DebugThis("RegModula3");
    
REVEAL
  T = GenViewsM3.Compiler BRANDED Brand OBJECT
  OVERRIDES
    write := Write;
  END;

PROCEDURE Write(t : T; dirPath : Pathname.T; rw : RW) 
  RAISES { Wr.Failure, Thread.Alerted, OSError.E } =
  VAR
    gs := NEW(GenState,
              rw          := rw,
              dirPath     := dirPath,
              map         := t.map,
              i3imports   := NEW(TextSetDef.T).init(),
              m3imports   := NEW(TextSetDef.T).init(),
              fieldWidths := NEW(CardSetDef.T).init()
              );
    intfNm := t.map.intfName(gs);
    iPath := dirPath & "/" & intfNm & ".i3";
    mPath := dirPath & "/" & intfNm & ".m3";
    us : TEXT;
  BEGIN
    IF mapsDone.insert(intfNm) THEN RETURN END;
    FOR i := FIRST(gs.wx) TO LAST(gs.wx) DO
      gs.wx[i] := Wx.New()
    END;
    IF rw = RW.W THEN us := "UNSAFE " ELSE us := "" END;
    gs.put(Section.IImport, F("INTERFACE %s;\n", intfNm));
    gs.put(Section.IComponents, F("CONST Brand = \"%s\";\n", intfNm));

    gs.put(Section.MImport, F("%sMODULE %s;\n", us, intfNm));

    CASE rw OF
      RW.W  =>
      EVAL gs.i3imports.insert(MapIntfNameRW(t.map, RW.R));
      EVAL gs.i3imports.insert("CompRange");
      EVAL gs.i3imports.insert("CompPath");
      EVAL gs.i3imports.insert("CsrOp");
      EVAL gs.i3imports.insert("CompAddr");
      
      EVAL gs.m3imports.insert("Word");
      EVAL gs.m3imports.insert("CsrOp");
      EVAL gs.m3imports.insert("CompAddr");
      EVAL gs.m3imports.insert(MapIntfNameRW(t.map, RW.R));
      EVAL gs.m3imports.insert("CompRange");
      EVAL gs.m3imports.insert("CompPath");
      EVAL gs.m3imports.insert("CompMemory");
      EVAL gs.m3imports.insert("Debug");
      EVAL gs.m3imports.insert("CompMemoryListener");
    |
      RW.R =>
    END;

    gs.put(Section.MImport, F("\n"));

    gs.put(Section.MCode, "BEGIN\n");
    
    FOR th := FIRST(TypeHier) TO LAST(TypeHier) DO
      IF TypePhase[th] = gs.rw THEN
        gs.th := th;
        (* set the hierarchy, this is how children know which type to dump *)
        
        t.map.generate(gs)
      END
    END;
    gs.put(Section.ITrailer,
           F("  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine())));

    gs.put(Section.MImport, F("\n"));
    gs.put(Section.ITrailer, F("END %s.\n", intfNm));
    gs.put(Section.MTrailer, F("END %s.\n", intfNm));


    DumpImports(gs.i3imports, gs, Section.IImport);
    DumpImports(gs.m3imports, gs, Section.MImport);

    gs.put(Section.IImport, F("\n"));
    gs.put(Section.MImport, F("\n"));

    CopyWx(SUBARRAY(gs.wx,
                    ORD(FIRST(gs.wx)),
                    ORD(LastISection)-ORD(FIRST(gs.wx))+1),
           iPath);
    CopyWx(SUBARRAY(gs.wx,
                    ORD(FirstMSection),
                    ORD(LAST(gs.wx))-ORD(FirstMSection)+1),
           mPath);

    WITH m3mWr = FileWr.OpenAppend(dirPath & "/m3makefile.maps") DO
      Wr.PutText(m3mWr, F("Module(\"%s\")\n",intfNm));
      Wr.Close(m3mWr)
    END
  END Write;

PROCEDURE DumpImports(set : TextSet.T; gs : GenState; sec : Section) =
  VAR
    iter := set.iterate();
    t : TEXT;
  BEGIN
    WHILE iter.next(t) DO
      gs.put(sec, F("IMPORT %s;\n", t))
    END
  END DumpImports;

PROCEDURE CopyWx(READONLY wx : ARRAY OF Wx.T; to : Pathname.T)
  (* copy an array of Wx.Ts in order to an output file *)
  RAISES { OSError.E, Wr.Failure, Thread.Alerted } =
  VAR
    wr := FileWr.Open(to);
  BEGIN
    FOR i := FIRST(wx) TO LAST(wx) DO
      Wr.PutText(wr, Wx.ToText(wx[i]))
    END;
    Wr.Close(wr)
  END CopyWx;

  (**********************************************************************)
  
PROCEDURE FmtArr(a : RdlArray.Single) : TEXT =
  BEGIN
    IF a = NIL THEN
      RETURN ""
    ELSE
      RETURN F("ARRAY [0..%s-1] OF ",BigInt.Format(a.n.x))
    END
  END FmtArr;

PROCEDURE FmtArrIdx(typeDecls : TextSeq.T; a : RdlArray.Single; nm : TEXT) =
  BEGIN
    IF a = NIL THEN
      RETURN
    ELSE
      typeDecls.addhi(F("%s = [0..%s-1]", nm, BigInt.Format(a.n.x)))
    END
  END FmtArrIdx;

PROCEDURE FmtArrFor(a : RdlArray.Single) : TEXT =
  BEGIN
    RETURN F("FOR i := 0 TO %s-1 DO", BigInt.Format(a.n.x))
  END FmtArrFor;
  
  (**********************************************************************)

VAR
  props : ARRAY Prop OF RdlProperty.T;
  propsInitted := FALSE;

PROCEDURE InitProps() =
  BEGIN
    IF propsInitted THEN RETURN END;
    FOR i := FIRST(Prop) TO LAST(Prop) DO
      props[i] := RdlProperty.Make(PropNames[i])
    END;
    propsInitted := TRUE
  END InitProps;

PROCEDURE GetPropText(prop : Prop; comp : RegComponent.T) : TEXT =
  VAR
    q : RdlExplicitPropertyAssign.T;
  BEGIN
    InitProps();
    q := comp.props.lookup(props[prop]);
    IF q = NIL THEN
      (* return default *)
      RETURN CompRange.DefProp[prop]
    ELSE
      (* parse result *)

      CASE prop OF 
        Prop.Addressing =>
        VAR
          a : CompAddr.Addressing;
        BEGIN
          CASE GetKw(q.rhs) OF
            RdlPropertyRvalueKeyword.T.compact =>
            a := CompAddr.Addressing.Compact
          |
            RdlPropertyRvalueKeyword.T.regalign =>
            a := CompAddr.Addressing.Regalign
          |
            RdlPropertyRvalueKeyword.T.fullalign =>
            a := CompAddr.Addressing.Fullalign
          ELSE
            <*ASSERT FALSE*>
          END;
          RETURN F("CompAddr.Addressing.%s", CompAddr.AddressingNames[a])
        END
      ELSE
        RETURN Fmt.Int(GetNumeric(q.rhs))
      END
    END
  END GetPropText;

  (* <--- ugly to have this twice ---> *)
  
PROCEDURE GetAddressingProp(comp : RegComponent.T) : CompAddr.Addressing =
  VAR
    q : RdlExplicitPropertyAssign.T;
  BEGIN
    InitProps();
    q := comp.props.lookup(props[CompRange.Prop.Addressing]);
    IF q = NIL THEN
      (* return default *)
      RETURN CompAddr.Addressing.Regalign
    ELSE
      (* parse result *)

      CASE GetKw(q.rhs) OF
        RdlPropertyRvalueKeyword.T.compact =>
        RETURN CompAddr.Addressing.Compact
      |
        RdlPropertyRvalueKeyword.T.regalign =>
        RETURN CompAddr.Addressing.Regalign
      |
        RdlPropertyRvalueKeyword.T.fullalign =>
        RETURN CompAddr.Addressing.Fullalign
      ELSE
        <*ASSERT FALSE*>
      END
    END
  END GetAddressingProp;
  
PROCEDURE GetPropTexts(c : RegComponent.T) : ARRAY Prop OF TEXT =
  VAR
    res : ARRAY Prop OF TEXT;
  BEGIN
    FOR i := FIRST(Prop) TO LAST(Prop) DO
      res[i] := GetPropText(i, c)
    END;
    RETURN res
  END GetPropTexts;

PROCEDURE FormatPropArgs(READONLY args : ARRAY Prop OF TEXT) : TEXT =
  VAR
    res := "";
  BEGIN
    FOR i := FIRST(args) TO LAST(args) DO
      res := res & F(", %s := %s", PropNames[i], args[i])
    END;
    RETURN res
  END FormatPropArgs;
  
PROCEDURE GenChildInit(e          : RegChild.T;
                       gs         : GenState;
                       addressing : CompAddr.Addressing;
                       skipArc := FALSE) =
  VAR
    childArc : TEXT;
    atS      : TEXT;
  BEGIN
    InitProps();
    (* special case for array with only one child is that it is NOT
       a record *)
    IF skipArc THEN
      childArc := "";
    ELSE
      childArc := "." & IdiomName(e.nm,debug := FALSE);
    END;

    IF doDebug THEN
      Debug.Out("GenChildInit " & e.nm & " -> \"" & childArc & "\"")
    END;
    
    FOR i := FIRST(props) TO LAST(props) DO
      VAR q   := e.comp.props.lookup(props[i]);
          dbg : TEXT := "**NIL**";
      BEGIN
        IF q # NIL THEN
          dbg := F("{ %s }", RdlExplicitPropertyAssign.Format(q))
        END;
        IF doDebug THEN
          Debug.Out(F("RdlProperty %s = %s",
                      RdlProperty.Format(props[i]),
                      dbg))
        END
      END
    END;
    
    IF e.at = RegChild.Unspecified AND e.mod = RegChild.Unspecified THEN
      atS := "at"
    ELSIF e.at # RegChild.Unspecified THEN
      atS := F("CompAddr.PlusBytes(base,16_%s)",
               Fmt.Int(BigInt.ToInteger(e.at.x), base := 16))
    ELSIF e.mod # RegChild.Unspecified THEN
      atS := F("CompAddr.ModAlign(at, 16_%s)",
               Fmt.Int(BigInt.ToInteger(e.mod.x), base := 16))
    END;
    
    IF e.array = NIL THEN
      gs.mdecl(
             "    at := mono.increase(at,%s(x%s, %s, CompPath.Cat(path,\"%s\")));\n",
               ComponentInitName(e.comp,gs),
               childArc,
               atS,
               childArc);
      IF NOT skipArc THEN
        gs.mdecl("    x.tab[c] := at; INC(c);\n");
      END
    ELSE
      (* e.array # NIL *)
      gs.mdecl("    VAR\n");
      gs.mdecl("      q := %s;\n", atS);
      gs.mdecl("    BEGIN\n");

      IF addressing = CompAddr.Addressing.Fullalign THEN
        (* cases : 
           (0) calc overriden by @ or %= 
           (1) stride given, then that is what we use to align
           (2) stride not given, then we need to calculate size of
               element
        *)
        IF e.at # RegChild.Unspecified OR e.mod # RegChild.Unspecified THEN
          (* skip , fall back to not using fullalign *)
        ELSIF e.stride # RegChild.Unspecified THEN
          WITH alignTo = BigInt.ToInteger(BigInt.Mul(e.array.n.x,
                                                     e.stride.x)) DO
            IF e.at = RegChild.Unspecified AND e.mod = RegChild.Unspecified THEN
              gs.mdecl("      q := CompAddr.Align(at,%s);\n",
                                     Fmt.Int(alignTo))
            END
          END
        ELSE
          (* fullalign given, stride not given, mod not given, at not given *)
          (* make a throwaway "first" and "second", 
             measure distance between,
             multiply by size,
             then align at to that and proceed *)
          gs.mdecl("      VAR first, second : CompRange.T; BEGIN\n");
          
          gs.mdecl("        first := %s(x%s[0], CompAddr.Zero, NIL);\n",
                                 ComponentInitName(e.comp,gs),
                                 childArc);
          gs.mdecl("        second := %s(x%s[1], CompRange.Lim(first), NIL);\n",
                                 ComponentInitName(e.comp,gs),
                                 childArc);
          gs.mdecl("        <*ASSERT first # second*>\n");
          gs.mdecl("        WITH len = %s*\n", BigInt.Format(e.array.n.x));
          gs.mdecl("                   CompAddr.DeltaBytes(CompRange.Lim(second),CompRange.Lim(first)) DO\n");
          gs.mdecl("          at := CompAddr.ModAlign(at, CompAddr.NextPower(len));\n");
          gs.mdecl("          q := at\n");
          gs.mdecl("        END\n");
          gs.mdecl("      END;\n")
        END
      END;
      
      gs.mdecl("      %s\n",FmtArrFor(e.array));
      gs.mdecl("        at := mono.increase(at,%s(x%s[i], q, CompPath.CatArray(path,\"%s\",i)));\n",
               ComponentInitName(e.comp,gs),
               childArc,
               childArc);
      IF NOT skipArc THEN
        gs.mdecl("        x.tab[c] := at; INC(c);\n");
      END;
      IF e.stride # RegChild.Unspecified THEN
        gs.mdecl("        q := CompAddr.PlusBytes(q,16_%s);\n",
                               Fmt.Int(BigInt.ToInteger(e.stride.x), base := 16))
      ELSE
        gs.mdecl("        q := at;\n")
      END;
      gs.mdecl("      END\n");
      gs.mdecl("    END;\n")
    END
  END GenChildInit;
  
  (**********************************************************************)

PROCEDURE PutFtypeDecls(gs : GenState; sec : Section; fTypeDecls : TextSeq.T) =
  BEGIN
    FOR i := 0 TO fTypeDecls.size()-1 DO
      WITH d = fTypeDecls.get(i) DO
        gs.put(sec, F("TYPE %s;\n", d))
      END
    END;
    gs.put(sec, "\n");
  END PutFtypeDecls;
  
PROCEDURE GenAddrmapRecord(map            : RegContainer.T;
                           gs             : GenState)
  RAISES { OSError.E, Thread.Alerted, Wr.Failure } =
  VAR
    ccnt : CARDINAL := 0;
    file := ThisFile(); line := Fmt.Int(ThisLine());
    mainTypeName := MainTypeName[gs.th];
    fTypeDecls := NEW(TextSeq.T).init();
  BEGIN
    IF NOT gs.newSymbol(map.typeName(gs)) THEN RETURN END;
    gs.put(Section.IMaintype, "\n");
    gs.put(Section.IMaintype, "TYPE\n");
    gs.put(Section.IMaintype,
           F("  %s = RECORD (* %s:%s *)\n",
             mainTypeName,
             file,
             line)
          );

    (* header for main type *)
    FOR i := 0 TO map.children.size()-1 DO
      WITH e = map.children.get(i) DO
        TYPECASE e.comp OF
          RegAddrmap.T(map) =>

          WITH iNm = map.intfName(gs)DO
            EVAL gs.i3imports.insert(iNm);
            CASE gs.rw OF RW.W =>  EVAL gs.m3imports.insert(iNm) ELSE END
          END;
         
          VAR sub : T := NEW(T).init(map);
          BEGIN
            sub.write(gs.dirPath, gs.rw)
          END
        ELSE
          e.comp.generate(gs)
        END;
        WITH typeStr   = FmtArr(e.array) & ComponentTypeName(e.comp,gs),
             fNm       = IdiomName(e.nm),
             typeNamePfx = F("%s_%s", mainTypeName, IdiomName(e.nm, FALSE)),
             fTypeDecl = F("%s_type = %s", typeNamePfx, typeStr) DO
          gs.put(Section.IMaintype, F("    %s : %s;\n", fNm, typeStr));
          INC(ccnt,ArrayCnt(e.array));
          fTypeDecls.addhi(fTypeDecl);
          FmtArrIdx(fTypeDecls, e.array, typeNamePfx & "_idx")
        END
      END
    END;

    CASE gs.th OF
      TypeHier.Addr =>
      gs.put(Section.IMaintype, F("    tab : ARRAY[0..%s+1-1] OF CompAddr.T;\n",
                                  Fmt.Int(ccnt)));
      gs.put(Section.IMaintype, F("    nonmono := FALSE;\n"));
      gs.put(Section.IMaintype, F("    monomap : REF ARRAY OF CARDINAL;\n"));
      gs.put(Section.IMaintype, F("    min, max: CompAddr.T;\n"));
    |
      TypeHier.Unsafe, TypeHier.Read => (* skip *)
    |
      TypeHier.Update =>          gs.put(Section.IMaintype, F("    updater : %s;\n",
                                      Updater(
                                          ComponentTypeNameInHier(map,
                                                                  gs,
                                                                  TypeHier.Read)
        )
        ))
     END;

    gs.put(Section.IMaintype, "  END;\n");
    gs.put(Section.IMaintype, "\n");
    PutFtypeDecls(gs, Section.IMaintype, fTypeDecls)
  END GenAddrmapRecord;
  
PROCEDURE GenAddrmap(map     : RegAddrmap.T; gsF : RegGenState.T) 
  RAISES { OSError.E, Thread.Alerted, Wr.Failure } =

  (* 
     generate a 

       TYPE HIERARCHY

     starting from an addrmap 
  *)

  VAR
    gs : GenState := gsF;
  BEGIN
    gs.put(Section.IMaintype, F("  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine())));
    
    gs := RegGenState.T.init(gs, gs.dirPath);
    (* clear symbols dumped, so we can re-generate the entire hier *)
    
    GenAddrmapRecord(map, gs);
    (* generate types and dependencies, starting from addrmap *)
    
    (* last, generate procedures to deal with the top-level type *)
    CASE gs.th OF
      TypeHier.Addr =>
      GenAddrmapInit(map, gs);
      GenAddrmapVisit(map, gs)
    |
      TypeHier.Unsafe =>
      GenAddrmapXInit(map, gs)
    |
      TypeHier.Read =>  
    |
      TypeHier.Update =>
      GenAddrmapGlobal    (map, gs);
      GenAddrmapUpdateInit(map, gs);
      GenAddrmapCsr       (map, gs);
      GenAddrmapRanger    (map, gs);
      GenAddrmapReset     (map, gs)
    END
  END GenAddrmap;

PROCEDURE ArrayCnt(a : RdlArray.Single) : CARDINAL =
  BEGIN
    IF a = NIL THEN RETURN 1 ELSE RETURN BigInt.ToInteger(a.n.x) END
  END ArrayCnt;

PROCEDURE GenAddrmapInit(map : RegAddrmap.T; gs : GenState) =
  (* generate interface for address map for struct *)
  VAR
    pname : TEXT;
  BEGIN
    CASE gs.th OF
      TypeHier.Addr => pname := "Init"
    ELSE
      <*ASSERT FALSE*>
    END;
    
    gs.put(Section.IMaintype,
           F("PROCEDURE %s(VAR x : %s; at : CompAddr.T; path : CompPath.T) : CompRange.T;\n", pname, MainTypeName[gs.th]));
    gs.put(Section.IMaintype, "\n");
    
    gs.mdecl(
           F("PROCEDURE %s(VAR x : %s; at : CompAddr.T; path : CompPath.T) : CompRange.T =\n", pname, MainTypeName[gs.th]));
    gs.mdecl("  (* %s:%s *)\n",ThisFile(),Fmt.Int(ThisLine()));

    gs.mdecl("  VAR\n");
    gs.mdecl("    base := at;\n");
    gs.mdecl("    c := 0;\n");
    gs.mdecl("    mono := NEW(CompRange.Monotonic).init();\n");
    gs.mdecl("  BEGIN\n");
    gs.mdecl("    x.tab[c] := at; INC(c);\n");

    FOR i := 0 TO map.children.size()-1 DO
      GenChildInit(map.children.get(i),
                   gs, 
                   GetAddressingProp(map)
                   )
    END;
    BuildTab(gs, map.intfName(gs));
    gs.mdecl("    RETURN CompRange.From2(base,at)\n");
    gs.mdecl("  END %s;\n", pname);
    gs.mdecl("\n");
  END GenAddrmapInit;

  (**********************************************************************)

PROCEDURE GenAddrmapVisit(map : RegAddrmap.T; gs : GenState) =
  BEGIN
    EVAL gs.i3imports.insert("AddrVisitor");
    EVAL gs.m3imports.insert("AddrVisitor");

    gs.imain("  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine()));
    gs.imain("PROCEDURE Visit(READONLY a : %s; v : AddrVisitor.T; array : AddrVisitor.Array := NIL; parent : AddrVisitor.Internal := NIL);\n",
             MainTypeName[gs.th]);
    
    gs.mdecl("  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine()));
    gs.mdecl("PROCEDURE Visit(READONLY a : %s; v : AddrVisitor.T; array : AddrVisitor.Array := NIL; parent : AddrVisitor.Internal := NIL) =",
             MainTypeName[gs.th]);
    gs.mdecl("  (* %s:%s *)\n",ThisFile(),Fmt.Int(ThisLine()));
    gs.mdecl("  VAR\n");
    gs.mdecl("     internal : AddrVisitor.Internal;\n");
    gs.mdecl("  BEGIN\n");
    gs.mdecl("    internal := v.internal(\"%s\", \"\", AddrVisitor.Type.Addrmap, array, parent);\n", map.nm);
    FOR i := 0 TO map.children.size()-1 DO
      GenChildVisit(map.children.get(i), gs, FALSE)
    END;
    gs.mdecl("  END Visit;\n");
    gs.mdecl("\n");

    FOR i := 0 TO map.children.size()-1 DO
      IF FALSE THEN
        Debug.Out("Trying " & ComponentResetName(map.children.get(i).comp, gs))
      END;
      GenCompProc(map.children.get(i).comp, gs, ProcType.Visit)
    END
  END GenAddrmapVisit;
  
PROCEDURE GenChildVisit(e          : RegChild.T;
                       gs         : GenState;
                       skipArc := FALSE) =
  VAR
    childArc : TEXT;
  BEGIN
    (* special case for array with only one child is that it is NOT
       a record *)
    IF skipArc THEN
      childArc := "";
    ELSE
      childArc := "." & IdiomName(e.nm,debug := FALSE);
    END;

    IF doDebug THEN
      Debug.Out("GenChildVisit " & e.nm & " -> \"" & childArc & "\"")
    END;
    
    WITH rnm = ComponentVisitName(e.comp,gs) DO
      IF e.array = NIL THEN
        gs.mdecl("    %s(a%s,v,NIL,internal);\n", rnm, childArc);
      ELSE
      
        gs.mdecl("    VAR array := NEW(AddrVisitor.Array, sz := %s); BEGIN\n",
                 BigInt.Format(e.array.n.x));
        gs.mdecl("      %s\n",FmtArrFor(e.array));
        gs.mdecl("        array.idx := i;\n");
        gs.mdecl("        %s(a%s[i],v,array,internal);\n", rnm, childArc);
        gs.mdecl("      END\n");
        gs.mdecl("    END;\n")
      END
    END
  END GenChildVisit;

PROCEDURE GenRegfileVisit(rf : RegRegfile.T; gs : GenState) =
  VAR
    pnm : TEXT;
  BEGIN
    IF NOT gs.defProc(rf, ProcType.Visit, pnm) THEN RETURN END;
    
    gs.mdecl("  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine()));
    gs.mdecl("  VAR\n");
    gs.mdecl("     internal : AddrVisitor.Internal;\n");
    gs.mdecl("  BEGIN\n");
    gs.mdecl("    internal := v.internal(\"%s\", \"\", AddrVisitor.Type.Regfile, array, parent);\n", rf.nm);

    (* chew through the children and reset each in turn *)
    
    FOR i := 0 TO rf.children.size()-1 DO
      GenChildVisit(rf.children.get(i), gs, rf.children.size()=1)
    END;
    gs.mdecl("  END %s;\n",pnm);
    gs.mdecl("\n");
    FOR i := 0 TO rf.children.size()-1 DO
      GenCompProc(rf.children.get(i).comp, gs, ProcType.Visit)
    END;
  END GenRegfileVisit;

PROCEDURE GenRegVisit(r : RegReg.T; gs : GenState) =
  VAR
    pnm : TEXT;
  BEGIN
    IF doDebug THEN
      Debug.Out("GenRegVisit: " & ComponentName[ProcType.Visit](r,gs));
    END;
    IF NOT gs.defProc(r, ProcType.Visit, pnm) THEN RETURN END;

    gs.mdecl("  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine()));
    gs.mdecl("  VAR\n");
    gs.mdecl("     internal : AddrVisitor.Internal;\n");
    gs.mdecl("  BEGIN\n");
    gs.mdecl("    internal := v.internal(\"%s\", \"\", AddrVisitor.Type.Reg, array, parent);\n", r.nm);
    FOR i := 0 TO r.fields.size()-1 DO
      WITH f  = r.fields.get(i),
           nm = f.name(debug := FALSE) DO
        gs.mdecl("    v.field(\"%s\",a.%s,%s,%s,internal);\n",
                 nm,
                 nm,
                 Fmt.Int(f.lsb),
                 Fmt.Int(f.width))
      END
    END;
    gs.mdecl("  END %s;\n",pnm);
    gs.mdecl("\n");
  END GenRegVisit;

  (**********************************************************************)
  
PROCEDURE GenAddrmapXInit(map : RegAddrmap.T; gs : GenState) =
  VAR
    qmtn := MapIntfNameRW(map, RW.R) & "." & MainTypeName[TypeHier.Read];
  BEGIN
    EVAL gs.i3imports.insert("UpdaterFactory");
    EVAL gs.m3imports.insert("UpdaterFactory");
    gs.put(Section.IMaintype,
           F("PROCEDURE InitX(READONLY t : %s; READONLY a : A; VAR x : X; root : REFANY; factory : UpdaterFactory.T);\n", qmtn));
    gs.put(Section.IMaintype, "\n");
    
    gs.mdecl(
           F("PROCEDURE InitX(READONLY t : %s; READONLY a : A; VAR x : X; root : REFANY; factory : UpdaterFactory.T) =\n", qmtn));
    gs.mdecl("  (* %s:%s *)\n",ThisFile(),Fmt.Int(ThisLine()));
    gs.mdecl("  BEGIN\n");

    FOR i := 0 TO map.children.size()-1 DO
      GenChildXInit(map.children.get(i),
                   gs
                   )
    END;
    gs.mdecl("  END InitX;\n");
    gs.mdecl("\n");
  END GenAddrmapXInit;
  
PROCEDURE GenChildXInit(e          : RegChild.T;
                       gs         : GenState;
                       skipArc := FALSE) =
  VAR
    childArc : TEXT;
  BEGIN
    (* special case for array with only one child is that it is NOT
       a record *)
    IF skipArc THEN
      childArc := "";
    ELSE
      childArc := "." & IdiomName(e.nm,debug := FALSE);
    END;

    IF doDebug THEN
      Debug.Out("GenChildXInit " & e.nm & " -> \"" & childArc & "\"")
    END;
    
    IF e.array = NIL THEN
      gs.mdecl(
          "    %s(t%s,a%s,x%s,root,factory);\n",
          ComponentInitName(e.comp,gs),
          childArc,
          childArc,
          childArc);
    ELSE
      
      gs.mdecl("    %s\n",FmtArrFor(e.array));
      gs.mdecl("      %s(t%s[i],a%s[i],x%s[i],root,factory);\n",
               ComponentInitName(e.comp,gs),
               childArc,
               childArc,
               childArc);
      gs.mdecl("    END;\n")
    END
  END GenChildXInit;

  (**********************************************************************)
PROCEDURE GenAddrmapUpdateInit(map : RegAddrmap.T; gs : GenState) =
  BEGIN
    gs.put(Section.IMaintype,
           F("PROCEDURE UpdateInit(VAR x : %s; READONLY a : %s; READONLY u : %s; m : CompMemory.T);\n",
             MainTypeName[TypeHier.Update],
             MainTypeName[TypeHier.Addr],
             MainTypeName[TypeHier.Unsafe]
             ));
    gs.mdecl(
           F("PROCEDURE UpdateInit(VAR x : %s; READONLY a : %s; READONLY u : %s; m : CompMemory.T) =\n",
             MainTypeName[TypeHier.Update],
             MainTypeName[TypeHier.Addr],
             MainTypeName[TypeHier.Unsafe]
             ));
    gs.mdecl("  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine()));
    gs.mdecl("  BEGIN\n");

    FOR i := 0 TO map.children.size()-1 DO
      GenChildUpdateInit(map.children.get(i), gs, FALSE)
    END;
    gs.mdecl("  END UpdateInit;\n");
    gs.mdecl("\n");

    (* generate field updaters *)
    GenFieldUpdaters(gs)
  END GenAddrmapUpdateInit;

PROCEDURE GenFieldUpdaters(gs : GenState) =
  VAR
    iter := gs.fieldWidths.iterate();
    c : CARDINAL;
  BEGIN
    (* generate declarations for interface file *)
    (* and code for implementation *)
    gs.mdecl("\n");
    WHILE iter.next(c) DO GenFieldUpdater(c,gs) END
  END GenFieldUpdaters;

PROCEDURE GenFieldUpdater(c : CARDINAL; gs : GenState) =
  VAR
    cs   := Fmt.Int(c);
    type := M3FieldWidthType(c,TypeHier.Read,gs);
  BEGIN
    gs.put(Section.IComponents, F("TYPE\n"));
    gs.put(Section.IComponents, F("  UObj%s = OBJECT METHODS\n", cs));
    gs.put(Section.IComponents, F("    u(READONLY x : %s);\n", type));
    gs.put(Section.IComponents, F("    updater() : UObj%s;\n", cs));
    gs.put(Section.IComponents, F("  END;\n"));
    gs.put(Section.IComponents, F("\n"));

    gs.mdecl("TYPE\n");
    gs.mdecl("  UObjConcrete%s= UObj%s OBJECT\n", cs, cs);
    gs.mdecl("    m      : CompMemory.T;\n");
    gs.mdecl("    addr   : CompAddr.T;\n");
    gs.mdecl("    h      : H;\n");
    gs.mdecl("    upObj  : Updater.T;\n");
    gs.mdecl("  OVERRIDES\n");
    gs.mdecl("    u := UpdateField%s;\n", cs);
    gs.mdecl("    updater := ReturnMe%s;\n", cs);
    gs.mdecl("  END;\n");
    gs.mdecl("\n");
    gs.mdecl("PROCEDURE ReturnMe%s(o : UObjConcrete%s) : UObj%s = \n", cs, cs, cs);
    gs.mdecl("  BEGIN RETURN o END ReturnMe%s;\n", cs);
    gs.mdecl("\n");
    gs.mdecl("PROCEDURE UpdateField%s(o : UObjConcrete%s; READONLY x : %s) =\n",
             cs, cs, type);
    gs.mdecl("  CONST Unsafe = DoUnsafeWrite AND %s <= BITSIZE(Word.T);\n",cs);
    gs.mdecl("  VAR\n");
    IF c > BITSIZE(Word.T) THEN
      gs.mdecl("    op := CsrOp.MakeWideWrite(o.addr, x, NOT Unsafe);\n")
    ELSE
      gs.mdecl("    op := CsrOp.MakeWrite(o.addr, %s, x, NOT Unsafe);\n",cs)
    END;
    gs.mdecl("  BEGIN\n");
    gs.mdecl("    EVAL o.m.csrOp(op);\n");
    IF c <= BITSIZE(Word.T) THEN
      gs.mdecl("    IF Unsafe THEN\n");
      gs.mdecl("      o.upObj.update(x)\n");
      gs.mdecl("    END\n");
    END;
    gs.mdecl("  END UpdateField%s;\n", cs);
    gs.mdecl("\n");
  END GenFieldUpdater;

PROCEDURE GenChildUpdateInit(e          : RegChild.T;
                             gs         : GenState;
                             skipArc := FALSE) =
  VAR
    childArc : TEXT;
  BEGIN
    (* special case for array with only one child is that it is NOT
       a record *)
    IF skipArc THEN
      childArc := "";
    ELSE
      childArc := "." & IdiomName(e.nm,debug := FALSE);
    END;

    IF e.array = NIL THEN
      gs.mdecl(
               "    %s(x%s,a%s,u%s,m);\n",
               ComponentInitName(e.comp,gs),
               childArc,
               childArc,
               childArc )
    ELSE
      gs.mdecl("    %s\n",FmtArrFor(e.array));
      gs.mdecl(
               "      %s(x%s[i],a%s[i],u%s[i],m);\n",
               ComponentInitName(e.comp,gs),
               childArc,
               childArc,
               childArc );
      gs.mdecl( "    END;\n");
   END
  END GenChildUpdateInit;

PROCEDURE GenRegfileUpdateInit(rf : RegRegfile.T; gs : GenState) =
  VAR
    iNm := ComponentInitName(rf, gs);
    utn := ComponentTypeNameInHier(rf, gs, TypeHier.Update);
    atn := ComponentTypeNameInHier(rf, gs, TypeHier.Addr);
    xtn := ComponentTypeNameInHier(rf, gs, TypeHier.Unsafe);
  BEGIN
    gs.mdecl(
             "PROCEDURE %s(VAR x : %s; READONLY a : %s; READONLY u : %s; m : CompMemory.T) =\n",
             iNm,
             utn,
             atn,
             xtn);

    gs.mdecl("  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine()));
    gs.mdecl("  BEGIN\n");

    FOR i := 0 TO rf.children.size()-1 DO
      GenChildUpdateInit(rf.children.get(i), gs, rf.skipArc())
    END;
    gs.mdecl("  END %s;\n",iNm);
    gs.mdecl("\n");
  END GenRegfileUpdateInit;
  
PROCEDURE GenRegUpdateInit(r : RegReg.T; gs : GenState) =
  VAR
    iNm := ComponentInitName(r, gs);
    utn := ComponentTypeNameInHier(r, gs, TypeHier.Update);
    atn := ComponentTypeNameInHier(r, gs, TypeHier.Addr);
    xtn := ComponentTypeNameInHier(r, gs, TypeHier.Unsafe);
  BEGIN
    gs.mdecl(
             "PROCEDURE %s(VAR x : %s; READONLY a : %s; READONLY u : %s; m : CompMemory.T) =\n", iNm, utn, atn, xtn);
    gs.mdecl("  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine()));
    gs.mdecl("  BEGIN\n");

    FOR i := 0 TO r.fields.size()-1 DO
      WITH f  = r.fields.get(i),
           ws = Fmt.Int(f.width),
           nm = f.name(debug := FALSE) DO

        IF f.width = BITSIZE(Word.T) THEN
          EVAL gs.i3imports.insert("Word")
        END;

        gs.mdecl(
                 "    x.%s := NEW(UObjConcrete%s, addr := a.%s.pos, upObj := u.%s, m := m);\n", nm, ws, nm, nm);
        EVAL gs.fieldWidths.insert(f.width)
      END
    END;
    gs.mdecl("  END %s;\n", iNm);
    gs.mdecl("\n");
    
  END GenRegUpdateInit;

  (**********************************************************************)
  
PROCEDURE GenAddrmapGlobal(map : RegAddrmap.T; gs : GenState) =
  VAR
    qmtn := MapIntfNameRW(map, RW.R) & "." & MainTypeName[TypeHier.Read];
  BEGIN
    EVAL gs.i3imports.insert("CompMemory");
    EVAL gs.i3imports.insert("MemoryMap");
    gs.put(Section.IMaintype,
           F("  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine())));
    gs.put(Section.IMaintype, "TYPE\n");
    gs.put(Section.IMaintype, "  U = Update;\n");
    gs.put(Section.IMaintype, "  H <: PublicH;\n");
    gs.put(Section.IMaintype, "\n");
    gs.put(Section.IMaintype, "  PublicH = MemoryMap.T OBJECT\n");
    gs.put(Section.IMaintype,
                            F("    read   : %s;\n",qmtn));
    gs.put(Section.IMaintype, "    update : U;\n");
    gs.put(Section.IMaintype, "    a      : A;\n");
    gs.put(Section.IMaintype, "  END;\n");
    gs.put(Section.IMaintype, "\n");
    gs.put(Section.IMaintype, "  CONST DoUnsafeWrite = TRUE;\n");
    
    gs.put(Section.IMaintype, "\n");

    (**********************************************************************)
    
   gs.mdecl(
                       "  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine()));
   gs.mdecl(
           "REVEAL\n" &
           "  H = PublicH BRANDED Brand & \"H\" OBJECT\n" &
           "    x : X;\n" & 
           "  OVERRIDES\n" &
           "    init := InitH;\n" &
           "    visit := VisitH;\n" &
           "  END;\n" &
           "\n"                 
    );
   gs.mdecl(
           "TYPE\n" &
           "  Callback = CompMemoryListener.T OBJECT\n" &
           "    h : H;\n" &
           "  OVERRIDES\n" &
           "    callback := CallbackCallback;\n" &
           "    hash     := CallbackHash;\n" &
           "    equal    := CallbackEqual;\n" &
           "  END;\n" &
           "\n"                 
    );
   gs.mdecl(
          "PROCEDURE CallbackCallback(cb : Callback; op : CsrOp.T) =\n" &
          "  (* can only do writes since no VAR *)\n" & 
          "  BEGIN\n" &
          "    CsrAccess(cb.h.read, cb.h.a, cb.h.x, op)\n" &
          "  END CallbackCallback;\n" &
          "\n" &

          "PROCEDURE CallbackHash(<*UNUSED*>cb : Callback) : Word.T =\n" &
          "  BEGIN\n" &
          "    RETURN 16_c0edbabe\n" &
          "  END CallbackHash;\n" &
          "\n" &

          "PROCEDURE CallbackEqual(cb : Callback; q : CompMemoryListener.T) : BOOLEAN =\n" &
          "  BEGIN\n" &
          "    RETURN cb = q\n" &
          "  END CallbackEqual;\n" &
          "\n" 
    );
    gs.mdecl(
           "  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine()));
    EVAL gs.m3imports.insert("UnsafeUpdaterFactory");
    EVAL gs.m3imports.insert("MemoryMap");
    gs.mdecl(
           "PROCEDURE InitH(h : H; base : CompAddr.T; factory : UpdaterFactory.T) : MemoryMap.T =\n" &
           "  VAR\n" &
           "    range : CompRange.T;\n"&
           "  BEGIN\n" &
           "    IF factory = NIL THEN factory := NEW(UnsafeUpdaterFactory.T) END;\n" &
         F("    range := Init(h.a, base, CompPath.One(\"ROOT\"));\n") &
           "    EVAL CompMemory.T.init(h, range);\n" &
           "    InitX(h.read, h.a, h.x, h, factory);\n" &
           "    UpdateInit(h.update, h.a, h.x, h);\n" &                         
           "    h.registerListener(range,NEW(Callback, h := h));\n"&
           "    RETURN h\n" &                             
           "  END InitH;\n" &
           "\n"
    );

    EVAL gs.m3imports.insert("AddrVisitor");

    gs.mdecl(
           "PROCEDURE VisitH(h : H; v : AddrVisitor.T) =\n" &
           "  BEGIN\n" &
           "    Visit(h.a, v, NIL, NIL)\n" &
           "  END VisitH;\n" &
           "\n"
    );

  END GenAddrmapGlobal;

PROCEDURE GenAddrmapCsr(map : RegAddrmap.T; gs : GenState) =
  (* generate interface for CSR write by address *)
  VAR
    qmtn := MapIntfNameRW(map, RW.R) & "." & MainTypeName[TypeHier.Read];
    ccnt : CARDINAL := 0;
  BEGIN
    gs.put(Section.IMaintype,
                       F("  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine())));
    gs.put(Section.IMaintype,
                       F("PROCEDURE CsrAccess(VAR t : %s; READONLY a : A; READONLY x : X; VAR op : CsrOp.T);\n", qmtn));

    gs.mdecl(
                       "PROCEDURE CsrAccess(VAR t : %s; READONLY a : A; READONLY x : X; VAR op : CsrOp.T) =\n", qmtn);
    gs.mdecl(
                       "  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine()));
    gs.mdecl("\n");
    gs.mdecl("  PROCEDURE DoChild(c : [0..NUMBER(a.tab)-2]) =\n");
    gs.mdecl("    BEGIN\n");
    gs.mdecl("      CASE c OF\n");
    FOR i := 0 TO map.children.size()-1 DO
      GenChildCsr(map.children.get(i), gs, ccnt, FALSE)
    END;
    gs.mdecl("      END\n");
    gs.mdecl("    END DoChild;\n");
    gs.mdecl("\n");

    MainBodyCsr(gs, "CsrAccess");
    
    gs.mdecl("\n");

    FOR i := 0 TO map.children.size()-1 DO
      GenCompProc(map.children.get(i).comp, gs, ProcType.Csr)
    END;
  END GenAddrmapCsr;

PROCEDURE GenAddrmapRanger(map : RegAddrmap.T; gs : GenState) =
  (* generate interface for CSR write by address *)
  BEGIN
    gs.imain("  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine()));
    gs.imain("PROCEDURE Range(READONLY a : A) : CompRange.T;\n");

    gs.mdecl("PROCEDURE Range(READONLY a : A) : CompRange.T =\n");
    gs.mdecl("  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine()));
    gs.mdecl("\n");
    
    MainBodyRange(gs, "Range");
    
    gs.mdecl("\n");

    FOR i := 0 TO map.children.size()-1 DO
      GenCompProc(map.children.get(i).comp, gs, ProcType.Range)
    END
  END GenAddrmapRanger;
  
PROCEDURE MainBodyRange(gs : GenState; pnm : TEXT) =
  BEGIN
    gs.mdecl("  BEGIN\n");
    gs.mdecl("    RETURN CompRange.From2(a.min, a.max)\n");
    gs.mdecl("  END %s;\n",pnm);
  END MainBodyRange;

  (**********************************************************************)

PROCEDURE DoSimpleBinarySearch(gs : GenState) =
  BEGIN
    gs.mdecl("      WITH start = CompAddr.Find(a.tab,lo) DO\n");
    gs.mdecl("        FOR i := MAX(start,0) TO NUMBER(a.tab)-2 DO\n");
    gs.mdecl("          IF CompAddr.Compare(a.tab[i],hi) > -1 THEN EXIT END;\n");
    gs.mdecl("          DoChild(i)\n");
    gs.mdecl("        END\n");
    gs.mdecl("      END\n");
  END DoSimpleBinarySearch;

PROCEDURE DoIndirectBinarySearch(gs : GenState) =
  BEGIN
    gs.mdecl("      WITH start = CompAddr.FindIndirect(SUBARRAY(a.tab,0,NUMBER(a.monomap^)),a.monomap^,lo) DO\n");
    gs.mdecl("        FOR i := MAX(start,0) TO NUMBER(a.tab)-2 DO\n");
    gs.mdecl("          IF CompAddr.Compare(a.tab[a.monomap[i]],hi) > -1 THEN EXIT END;\n");
    gs.mdecl("          DoChild(a.monomap[i])\n");
    gs.mdecl("        END\n");
    gs.mdecl("      END\n");
  END DoIndirectBinarySearch;

PROCEDURE GenCompProc(c     : RegComponent.T;
                      gs    : GenState;
                      whch  : ProcType) =
  BEGIN
    CASE
      whch OF
      ProcType.Csr =>
      TYPECASE c OF
        RegAddrmap.T => (* skip, generated in its own file *)
      |
        RegRegfile.T => GenRegfileCsr(c, gs)
      |
        RegReg.T     => GenRegCsr    (c, gs)
      ELSE
        <*ASSERT FALSE*>
      END
    |
      ProcType.Range =>
      TYPECASE c OF
        RegAddrmap.T => (* skip, generated in its own file *)
      |
        RegRegfile.T => GenRegfileRanger(c, gs)
      |
        RegReg.T     => GenRegRanger    (c, gs)
      ELSE
        <*ASSERT FALSE*>
      END
    |   ProcType.Reset =>
      TYPECASE c OF
        RegAddrmap.T => (* skip, generated in its own file *)
      |
        RegRegfile.T => GenRegfileReset(c, gs)
      |
        RegReg.T     => GenRegReset    (c, gs)
      ELSE
        <*ASSERT FALSE*>
      END
    |   ProcType.Visit =>
      TYPECASE c OF
        RegAddrmap.T => (* skip, generated in its own file *)
      |
        RegRegfile.T => GenRegfileVisit(c, gs)
      |
        RegReg.T     => GenRegVisit    (c, gs)
      ELSE
        <*ASSERT FALSE*>
      END
    END
  END GenCompProc;

  (**********************************************************************)

PROCEDURE GenAddrmapReset(map : RegAddrmap.T; gs : GenState) =
  VAR
    qmtn := MapIntfNameRW(map, RW.R) & "." & MainTypeName[TypeHier.Read];
  BEGIN
    gs.imain("  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine()));
    gs.imain("PROCEDURE Reset(READONLY t : %s; READONLY u : U);\n", qmtn);

    gs.mdecl("PROCEDURE Reset(READONLY t : %s; READONLY u : U) =\n", qmtn);
    gs.mdecl("  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine()));
    gs.mdecl("  BEGIN\n");
    FOR i := 0 TO map.children.size()-1 DO
      GenChildReset(map.children.get(i), gs, FALSE)
    END;
    gs.mdecl("  END Reset;\n");
    gs.mdecl("\n");

    FOR i := 0 TO map.children.size()-1 DO
      IF FALSE THEN
        Debug.Out("Trying " & ComponentResetName(map.children.get(i).comp, gs))
      END;
      GenCompProc(map.children.get(i).comp, gs, ProcType.Reset)
    END
  END GenAddrmapReset;

PROCEDURE GenRegfileReset(rf : RegRegfile.T; gs : GenState) =
  VAR
    pnm : TEXT;
  BEGIN
    IF NOT gs.defProc(rf, ProcType.Reset, pnm) THEN RETURN END;
    
    gs.mdecl("  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine()));
    gs.mdecl("  BEGIN\n");

    (* chew through the children and reset each in turn *)
    
    FOR i := 0 TO rf.children.size()-1 DO
      GenChildReset(rf.children.get(i), gs, rf.children.size()=1)
    END;
    gs.mdecl("  END %s;\n",pnm);
    gs.mdecl("\n");
    FOR i := 0 TO rf.children.size()-1 DO
      GenCompProc(rf.children.get(i).comp, gs, ProcType.Reset)
    END;
  END GenRegfileReset;

PROCEDURE GenChildReset(e          : RegChild.T;
                        gs         : GenState;
                        skipArc := FALSE) =
 VAR
    childArc : TEXT;
  BEGIN
    (* special case for array with only one child is that it is NOT
       a record *)
    IF skipArc THEN
      childArc := "";
    ELSE
      childArc := "." & IdiomName(e.nm,debug := FALSE);
    END;
    WITH rnm = ComponentResetName(e.comp,gs) DO
      IF e.array = NIL THEN
        gs.mdecl("    %s(t%s, u%s);\n", rnm, childArc, childArc)
      ELSE
        gs.mdecl("    %s\n",FmtArrFor(e.array));
        gs.mdecl("      %s(t%s[i],u%s[i])\n", rnm, childArc, childArc);
        gs.mdecl("    END;\n")
      END
    END
  END GenChildReset;
  
PROCEDURE FmtLittleEndian(x : BigInt.T; w : CARDINAL) : TEXT =
  VAR
    wx := Wx.New();
    r : BigInt.T;
  BEGIN
    Wx.PutText(wx, F("ARRAY [0..%s-1] OF [0..1] {", Fmt.Int(w)));
    IF BigInt.Equal(x,BigInt.New(0)) THEN
      FOR i := 0 TO w-1 DO
        Wx.PutText(wx, "0");
        IF i # w-1 THEN
          Wx.PutText(wx, ", ")
        END
      END
    ELSE
      FOR i := 0 TO w-1 DO
        BigInt.Divide(x, BigInt.New(2), x, r);
        Wx.PutText(wx, F("16_%s", BigInt.Format(r,base:=16)));
        IF i # w-1 THEN
          Wx.PutText(wx, ", ")
        END
      END
    END;
    Wx.PutText(wx," }");
    RETURN Wx.ToText(wx)
  END FmtLittleEndian;

PROCEDURE DefVal(canBeNil : RdlNum.T) : BigInt.T =
  BEGIN
    IF canBeNil # NIL THEN RETURN canBeNil.x ELSE RETURN BigInt.New(0) END
  END DefVal;
  
PROCEDURE GenRegReset(r : RegReg.T; gs : GenState) =
  VAR
    pnm : TEXT;
  BEGIN
    IF doDebug THEN
      Debug.Out("GenRegReset: " & ComponentName[ProcType.Reset](r,gs));
    END;
    IF NOT gs.defProc(r, ProcType.Reset, pnm) THEN RETURN END;

    gs.mdecl("  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine()));
    gs.mdecl("  BEGIN\n");
    FOR i := 0 TO r.fields.size()-1 DO
      WITH f  = r.fields.get(i),
           nm = f.name(debug := FALSE),
           dv = DefVal(f.defVal) DO
        IF f.width <= BITSIZE(Word.T) THEN
          WITH vs = "16_" & BigInt.Format(dv,base:=16) DO
            gs.mdecl("    IF t.%s # %s THEN\n",nm,vs);
            gs.mdecl("      u.%s.u(%s)\n",nm,vs);
            gs.mdecl("    END;\n")
          END
        ELSE
          gs.mdecl("    WITH rv = %s DO\n",
                   FmtLittleEndian(dv,f.width));
          gs.mdecl("      IF t.%s # rv THEN\n",nm);
          gs.mdecl("        u.%s.u(rv)\n",nm);
          gs.mdecl("      END\n");
          gs.mdecl("    END;\n")
        END
      END
    END;
    gs.mdecl("  END %s;\n",pnm);
    gs.mdecl("\n");
  END GenRegReset;

  (**********************************************************************)
  
PROCEDURE GenRegfileRanger(rf : RegRegfile.T; gs : GenState) =
  VAR
    pnm : TEXT;
  BEGIN
    IF NOT gs.defProc(rf, ProcType.Range, pnm) THEN RETURN END;

    gs.mdecl("  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine()));
    IF rf.children.size() = 1 THEN
      (* just one member *)
      WITH chld = rf.children.get(0),
           nm   = IdiomName(chld.nm,debug := FALSE),
           rnm  = ComponentRangeName(chld.comp,gs) DO
        gs.mdecl("  BEGIN\n");
        IF chld.array = NIL THEN
          gs.mdecl("    RETURN %s(a.%s)\n",
                   rnm, nm
                   )
        ELSE
          gs.mdecl("    RETURN CompRange.From2(%s(a[0]).pos, CompRange.Lim(%s(a[%s-1])))\n",
                   rnm, rnm, BigInt.Format(chld.array.n.x))
        END;
        gs.mdecl("  END %s;\n",pnm)
      END
   ELSE
      MainBodyRange(gs,pnm);
   END;
   gs.mdecl("\n");
   FOR i := 0 TO rf.children.size()-1 DO
     GenCompProc(rf.children.get(i).comp, gs, ProcType.Range)
   END;
 END GenRegfileRanger;

PROCEDURE GenRegRanger(r : RegReg.T; gs : GenState) =
  VAR
    pnm : TEXT;
  BEGIN
    IF NOT gs.defProc(r, ProcType.Range, pnm) THEN RETURN END;

    gs.mdecl("  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine()));
    MainBodyRange(gs,pnm);

   gs.mdecl("\n");
 END GenRegRanger;

  (**********************************************************************)

PROCEDURE GenRegfileCsr(rf : RegRegfile.T; gs : GenState) =
  VAR
    pnm := ComponentCsrName(rf, gs);
    ttn := ComponentTypeNameInHier(rf, gs, TypeHier.Read);
    atn := ComponentTypeNameInHier(rf, gs, TypeHier.Addr);
    xtn := ComponentTypeNameInHier(rf, gs, TypeHier.Unsafe);
    ccnt : CARDINAL := 0;
  <*FATAL OSError.E, Thread.Alerted, Wr.Failure*>
  BEGIN
    IF NOT gs.newSymbol(pnm) THEN RETURN END;
    gs.mdecl( "PROCEDURE %s(VAR t : %s; READONLY a : %s; READONLY x : %s; VAR op : CsrOp.T) =\n",
               pnm,
               ttn,
               atn,
               xtn);
    gs.mdecl("  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine()));
    IF rf.children.size() = 1 THEN
       gs.mdecl("  BEGIN\n");
       GenChildCsr(rf.children.get(0), gs, ccnt, skipArc := TRUE);
       gs.mdecl("  END %s;\n",pnm);
    ELSE

      gs.mdecl("  PROCEDURE DoChild(c : [0..NUMBER(a.tab)-2]) =\n");
      gs.mdecl("    BEGIN\n");
      gs.mdecl("      CASE c OF\n");
      FOR i := 0 TO rf.children.size()-1 DO
        GenChildCsr(rf.children.get(i), gs, ccnt, skipArc := FALSE)
      END;
      gs.mdecl("      END\n");
      gs.mdecl("    END DoChild;\n");
      gs.mdecl("\n");
      MainBodyCsr(gs,pnm);
   END;
   gs.mdecl("\n");
   FOR i := 0 TO rf.children.size()-1 DO
     GenCompProc(rf.children.get(i).comp, gs, ProcType.Csr)
   END;
 END GenRegfileCsr;

PROCEDURE GenRegCsr(r  : RegReg.T;
                    gs : GenState) =
  VAR
    pnm := ComponentCsrName(r, gs);
    ttn := ComponentTypeNameInHier(r, gs, TypeHier.Read);
    atn := ComponentTypeNameInHier(r, gs, TypeHier.Addr);
    xtn := ComponentTypeNameInHier(r, gs, TypeHier.Unsafe);
  <*FATAL OSError.E, Thread.Alerted, Wr.Failure*>
  BEGIN
    IF NOT gs.newSymbol(pnm) THEN RETURN END;
    gs.mdecl(
           "PROCEDURE %s(VAR t : %s; READONLY a : %s; READONLY x : %s; VAR op : CsrOp.T) =\n",
           pnm, ttn, atn, xtn);
    gs.mdecl("  (* %s:%s *)\n",ThisFile(),Fmt.Int(ThisLine()));
    gs.mdecl("  PROCEDURE DoChild(c : [0..NUMBER(a.tab)-2]) =\n");
    gs.mdecl("    BEGIN\n");
    gs.mdecl("      CASE c OF\n");

    FOR i := 0 TO r.fields.size()-1 DO
      WITH f  = r.fields.get(i),
           nm = f.name(debug := FALSE) DO
        IF f.width <= BITSIZE(Word.T) THEN
          gs.mdecl("    | %s => t.%s := CsrOp.DoField(op, t.%s, a.%s);\n",
                   Fmt.Int(i), nm, nm, nm)
        ELSE
          gs.mdecl("    | %s => CsrOp.DoWideField(op, t.%s, a.%s);\n",
                                  Fmt.Int(i), nm, nm)
        END;
        gs.mdecl("                    WITH u = x.%s DO\n", nm);
        gs.mdecl("                      IF u.doSync THEN u.sync() END\n");
        gs.mdecl("                    END\n");

      END
    END;
    gs.mdecl("      END\n");
    gs.mdecl("    END DoChild;\n");
    gs.mdecl("\n");
    MainBodyCsr(gs,pnm);
    gs.mdecl("\n");
  END GenRegCsr;

PROCEDURE MainBodyCsr(gs : GenState; pnm : TEXT) =
  BEGIN
    gs.mdecl("  VAR\n");
    gs.mdecl("    lo := CompAddr.T { op.at, op.fv };\n");
    gs.mdecl("    hi := op.hi;\n");
    gs.mdecl("  BEGIN\n");

    gs.mdecl("    IF NOT op.doStruct THEN RETURN END;\n");
    gs.mdecl("    IF a.min.word > hi.word THEN RETURN END;\n");
    gs.mdecl("    IF a.max.word < lo.word THEN RETURN END;\n");    
    gs.mdecl("    IF a.nonmono THEN\n");
    DoIndirectBinarySearch(gs);
    gs.mdecl("    ELSE\n");
    DoSimpleBinarySearch(gs);
    gs.mdecl("    END\n");
    gs.mdecl("  END %s;\n",pnm);
  END MainBodyCsr;

PROCEDURE GenChildCsr(e          : RegChild.T;
                      gs         : GenState;
                      VAR ccnt   : CARDINAL;
                      skipArc := FALSE) =
  CONST
    MaxFullIter = 4;
  VAR
    childArc : TEXT;
  BEGIN
    (* special case for array with only one child is that it is NOT
       a record *)
    IF skipArc THEN
      childArc := "";
    ELSE
      childArc := "." & IdiomName(e.nm,debug := FALSE);
    END;

    IF skipArc THEN

      (* this is "the array special case" --

         in this case, the current node of the type tree is not a RECORD,
         but an ARRAY.

         therefore, we CANNOT store auxiliary information in it.
         
         therefore, we have to do a bit more work at runtime: 
         
         we evaluate the base of elements 0 and 1 in the array

         use that to compute the stride (in bytes)

         use the byte offset of the location we want to read or write into
         the array, DIV to find the array element of the base of the write.

         then continue reading/writing by scanning array elements in
         turn until we are past the operated-on region
      *)

      IF BigInt.ToInteger(e.array.n.x) > MaxFullIter THEN
        gs.mdecl("  (* %s:%s *)\n",ThisFile(),Fmt.Int(ThisLine()));
        WITH rnm = ComponentRangeName(e.comp,gs) DO
          gs.mdecl("    VAR\n");
          gs.mdecl("      r0 := %s(a[0]).pos;\n",rnm);
          gs.mdecl("      r1 := %s(a[1]).pos;\n",rnm);
          gs.mdecl("      opLo := CsrOp.LowAddr(op);\n");
          gs.mdecl("      offB : CARDINAL;\n");
          gs.mdecl("      start : CARDINAL;\n");
          gs.mdecl("      stride := CompAddr.DeltaBytes(r1,r0);\n");
          gs.mdecl("    BEGIN\n");
          gs.mdecl("      IF CompAddr.Compare(opLo,r0)<1 THEN\n");
          gs.mdecl("        start := 0\n");
          gs.mdecl("      ELSE\n");
          gs.mdecl("        offB := CompAddr.DeltaBytes(opLo,r0,truncOK := TRUE);\n");
          gs.mdecl("        start := offB DIV stride\n");
          gs.mdecl("      END;\n");
          gs.mdecl("      FOR i := start TO %s-1 DO\n", BigInt.Format(e.array.n.x));
          gs.mdecl("        IF CompAddr.Compare(%s(a[i]).pos,op.hi) >= 0 THEN RETURN END;\n", rnm);

          IF FALSE THEN
            gs.mdecl("      Debug.Out(Fmt.Int(i));\n");
            EVAL gs.m3imports.insert("Fmt");
          END;
          
          gs.mdecl("        %s(t[i],a[i],x[i],op)\n", ComponentCsrName(e.comp,gs));
          gs.mdecl("      END\n");
          gs.mdecl("    END\n")
        END
      ELSE
        gs.mdecl("      (* %s:%s *)\n",ThisFile(),Fmt.Int(ThisLine()));
        gs.mdecl("    %s\n",FmtArrFor(e.array));
        gs.mdecl("      %s(t[i],a[i],x[i],op)\n", ComponentCsrName(e.comp,gs));
        gs.mdecl("    END\n")
      END;
    ELSE
     gs.mdecl("      (* %s:%s *)\n",ThisFile(),Fmt.Int(ThisLine()));
     IF e.array = NIL THEN
        gs.mdecl(
               "      | %s => %s(t%s,a%s,x%s,op);\n",
                 Fmt.Int(ccnt),
                 ComponentCsrName(e.comp,gs),
                 childArc,
                 childArc,
                 childArc )
      ELSE
        gs.mdecl(
               F("      | %s..%s =>  ",
                   Fmt.Int(ccnt),
                   Fmt.Int(ccnt+ArrayCnt(e.array)-1)) &
               F("%s(t%s[c-%s]",
                   ComponentCsrName(e.comp,gs),
                   childArc,
                   Fmt.Int(ccnt)) &

               F(",a%s[c-%s],x%s[c-%s],op);\n",
                   childArc,
                   Fmt.Int(ccnt),
                   childArc,
                   Fmt.Int(ccnt)));
      END;
      INC(ccnt,ArrayCnt(e.array))
    END
  END GenChildCsr;

  (**********************************************************************)

PROCEDURE GenRegfile(rf       : RegRegfile.T;
                     genState : RegGenState.T) 
  RAISES { Wr.Failure, Thread.Alerted, OSError.E } =
 (* dump a regfile type defn *)
  VAR
    ccnt : CARDINAL := 0;
    gs : GenState := genState;
    mainTypeName := rf.typeName(gs);
    fTypeDecls := NEW(TextSeq.T).init();
  BEGIN
    IF NOT gs.newSymbol(rf.typeName(gs)) THEN RETURN END;
    gs.put(Section.IComponents, F("  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine())));
    gs.put(Section.IComponents, "TYPE\n");
    gs.put(Section.IComponents, F("  %s = ", mainTypeName));

    IF rf.children.size() # 1 THEN
      gs.put(Section.IComponents, F("RECORD (* %s:%s *)\n",ThisFile(),Fmt.Int(ThisLine())));
      FOR i := 0 TO rf.children.size()-1 DO
        WITH r = rf.children.get(i),
             typeStr = FmtArr(r.array) & ComponentTypeName(r.comp, gs),
             fNm     = IdiomName(r.nm),
             typeNamePfx = F("%s_%s", mainTypeName, IdiomName(r.nm, FALSE)),
             fTypeDecl = F("%s_type = %s", typeNamePfx, typeStr) DO
          gs.put(Section.IComponents, F("    %s : %s;\n", fNm, typeStr));
          INC(ccnt,ArrayCnt(r.array));
          fTypeDecls.addhi(fTypeDecl);
          FmtArrIdx(fTypeDecls, r.array, typeNamePfx & "_idx")
        END
      END;
      CASE gs.th OF
        TypeHier.Addr =>
        gs.put(Section.IComponents, F("    tab : ARRAY[0..%s+1-1] OF CompAddr.T;\n",
                                      Fmt.Int(ccnt)));
      gs.put(Section.IComponents, F("    nonmono := FALSE;\n"));
      gs.put(Section.IComponents, F("    monomap : REF ARRAY OF CARDINAL;\n"));
      gs.put(Section.IComponents, F("    min, max: CompAddr.T;\n"));
      |
        TypeHier.Unsafe => (* skip *)
      |
        TypeHier.Update =>
        gs.put(Section.IComponents, F("    u : %s;\n",
                                      Updater(
                                          ComponentTypeNameInHier(rf,
                                                                  gs,
                                                                  TypeHier.Read)
        )
        ))
      |
        TypeHier.Read =>
      END;
      gs.put(Section.IComponents, "END;\n") 
    ELSE
      WITH r = rf.children.get(0) DO
        gs.put(Section.IComponents, F("%s%s;\n", FmtArr(r.array),
                                      ComponentTypeName(r.comp, gs)))
      END
    END;
    gs.put(Section.IComponents, "\n");
    PutFtypeDecls(gs, Section.IComponents, fTypeDecls);
    FOR i := 0 TO rf.children.size()-1 DO
      rf.children.get(i).comp.generate(gs)
    END;

    CASE gs.th OF
      TypeHier.Addr =>
      GenRegfileInit(rf, gs)
    |
      TypeHier.Unsafe =>
      GenRegfileXInit(rf, gs)
    |
      TypeHier.Read =>  (* skip *)
    |
      TypeHier.Update => GenRegfileUpdateInit(rf, gs)
    END
  END GenRegfile;

 PROCEDURE GenRegfileInit(rf : RegRegfile.T; gs : GenState) =
  VAR
    iNm := ComponentInitName(rf, gs);
  BEGIN
    gs.mdecl(
           
             "PROCEDURE %s(VAR x : %s; at : CompAddr.T; path : CompPath.T) : CompRange.T =\n",
             iNm,
             rf.typeName(gs));
    gs.mdecl("  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine()));
    
    gs.mdecl("  VAR\n");
    gs.mdecl("    base := at;\n");
    gs.mdecl("    mono := NEW(CompRange.Monotonic).init();\n");
    IF rf.skipArc() THEN
      gs.mdecl("  BEGIN\n");
    ELSE
      gs.mdecl("    c := 0;\n");
      gs.mdecl("  BEGIN\n");
      gs.mdecl("    x.tab[c] := at; INC(c);\n");
    END;

    FOR i := 0 TO rf.children.size()-1 DO
      (* special case:
         if RF has a single member, it is not a record, instead it
         is (a) an array of the child type (if an array)
         OR (b) a copy of the child type (if a scalar)
      *)
      GenChildInit(rf.children.get(i),
                   gs,
                   GetAddressingProp(rf),
                   skipArc := rf.skipArc());
    END;
    IF NOT rf.skipArc() THEN BuildTab(gs, iNm) END;

    gs.mdecl("    RETURN CompRange.From2(base,at)\n");
    gs.mdecl("  END %s;\n",iNm);
    gs.mdecl("\n");
  END GenRegfileInit;
   
 PROCEDURE GenRegfileXInit(rf : RegRegfile.T; gs : GenState) =
  VAR
    iNm := ComponentInitName(rf, gs);
    atn := ComponentTypeNameInHier(rf, gs, TypeHier.Addr);
    ttn := ComponentTypeNameInHier(rf, gs, TypeHier.Read);
  BEGIN
    gs.mdecl(
           
             "PROCEDURE %s(READONLY t : %s; READONLY a : %s; VAR x : %s; root : REFANY; factory : UpdaterFactory.T) =\n",
             iNm,
             ttn,
             atn,
             rf.typeName(gs));
    gs.mdecl("  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine()));
    
    gs.mdecl("  BEGIN\n");

    FOR i := 0 TO rf.children.size()-1 DO
      (* special case:
         if RF has a single member, it is not a record, instead it
         is (a) an array of the child type (if an array)
         OR (b) a copy of the child type (if a scalar)
      *)
      GenChildXInit(rf.children.get(i),
                   gs,
                   skipArc := rf.skipArc());
    END;

    gs.mdecl("  END %s;\n",iNm);
    gs.mdecl("\n");
  END GenRegfileXInit;

 PROCEDURE BuildTab(gs : GenState; iNm : TEXT) =
   BEGIN
     gs.mdecl("    <*ASSERT c = NUMBER(x.tab)*>\n");
     gs.mdecl("    x.nonmono := NOT mono.isok();\n");
     SetTabEnds(gs);
     gs.mdecl("    IF x.nonmono THEN\n");
     gs.mdecl("      x.monomap := mono.indexArr();\n");
     gs.mdecl("      Debug.Warning(\"Nonmono in %s\");\n",
                             iNm);
     gs.mdecl("    END;\n");
  END BuildTab;
   
 PROCEDURE SetTabEnds(gs : GenState) =
   (* update the tab so that min is least and max is most *)
   BEGIN
     gs.mdecl("    mono.setRange(x.min,x.max);\n")
  END SetTabEnds;
   
  (**********************************************************************)

PROCEDURE GenReg(r : RegReg.T; genState : RegGenState.T) =
  (* dump a reg type defn *)
  VAR
    gs : GenState := genState;
    ccnt := 0;
    mainTypeName := r.typeName(gs);
    fTypeDecls := NEW(TextSeq.T).init();
  <*FATAL OSError.E, Thread.Alerted, Wr.Failure*>
  BEGIN
    (* check if already dumped *)
    IF NOT gs.newSymbol(r.typeName(gs)) THEN RETURN END;
    
    gs.put(Section.IComponents, F("TYPE\n"));
    gs.put(Section.IComponents, F("  %s = RECORD (* %s:%s *)\n", mainTypeName,ThisFile(),Fmt.Int(ThisLine())));
    FOR i := 0 TO r.fields.size()-1 DO
      WITH f = r.fields.get(i),
           typeStr = M3FieldType(f, gs.th, gs),
           fNm = f.name(),
           fTypeDecl = F("%s_%s_type = %s",
                         mainTypeName, f.name(FALSE), typeStr) DO

        IF f.width = BITSIZE(Word.T) THEN
          EVAL gs.i3imports.insert("Word")
        END;
        
        gs.put(Section.IComponents, F("    %s : %s;\n", fNm, typeStr));
        INC(ccnt);
        fTypeDecls.addhi(fTypeDecl);
      END
    END;
    CASE gs.th OF
      TypeHier.Addr =>
      gs.put(Section.IComponents, F("    tab : ARRAY[0..%s+1-1] OF CompAddr.T;\n",
                                  Fmt.Int(ccnt)));
      gs.put(Section.IComponents, F("    nonmono := FALSE;\n"));
      gs.put(Section.IComponents, F("    monomap : REF ARRAY OF CARDINAL;\n"));
      gs.put(Section.IComponents, F("    min, max: CompAddr.T;\n"));
      gs.put(Section.IComponents, F("    nm : CompPath.T;\n"))
   |
      TypeHier.Update =>
      gs.put(Section.IComponents, F("    u : %s;\n",
                                    Updater(
                                        ComponentTypeNameInHier(r,
                                                                gs,
                                                                TypeHier.Read)
                                           )
      ))
    |
      TypeHier.Read, TypeHier.Unsafe =>
    END;
    gs.put(Section.IComponents, F("  END;\n"));
    gs.put(Section.IComponents, F("\n"));
    PutFtypeDecls(gs, Section.IComponents, fTypeDecls);
    CASE gs.th OF
      TypeHier.Addr =>  GenRegInit(r, gs)
    |
      TypeHier.Unsafe => GenRegXInit(r, gs)
    |
      TypeHier.Read =>  (* skip *)
    |
      TypeHier.Update => GenRegUpdateInit(r, gs)
    END
  END GenReg;

PROCEDURE GenRegInit(r : RegReg.T; gs : GenState) =
  VAR
    iNm := ComponentInitName(r, gs);
    props := GetPropTexts(r);
    haveUnspecLsb, haveSpecLsb := FALSE;
  BEGIN
    gs.mdecl(
           "PROCEDURE %s(VAR x : %s; at : CompAddr.T; path : CompPath.T) : CompRange.T =\n",
           iNm,
           r.typeName(gs));
    gs.mdecl("  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine()));
    
    gs.mdecl("  VAR\n");
    gs.mdecl("    base := at;\n");
    gs.mdecl("    range : CompRange.T;\n");
    gs.mdecl("    c := 0;\n");
    gs.mdecl("    mono := NEW(CompRange.Monotonic).init();\n");
    gs.mdecl("  BEGIN\n");
    gs.mdecl("    x.nm := path;\n");
    gs.mdecl("    range := CompRange.PlaceReg(at%s);\n",
                            FormatPropArgs(props));
    gs.mdecl("    at  := range.pos;\n");
    gs.mdecl("    x.tab[c] := at; INC(c);\n");

    FOR i := 0 TO r.fields.size()-1 DO
      WITH f = r.fields.get(i) DO
        <*ASSERT f.width # RegField.Unspecified*>
        IF f.lsb = RegField.Unspecified THEN
          haveUnspecLsb := TRUE;
          gs.mdecl(
                 "    x.%s := CompRange.MakeField(at,%s);\n",
                   f.name(debug := FALSE),
                   Fmt.Int(f.width));
        ELSE
          haveSpecLsb := TRUE;
          gs.mdecl(
                  "    x.%s := CompRange.MakeField(CompAddr.PlusBits(range.pos,%s),%s);\n",
                   f.name(debug := FALSE),
                   Fmt.Int(f.lsb),
                   Fmt.Int(f.width));
        END;
        gs.mdecl(
                 "    at := mono.increase(at,x.%s);\n",
                   f.name(debug := FALSE));
        gs.mdecl(
               "    INC(CompAddr.initCount);\n");
      END;
      gs.mdecl("    x.tab[c] := at; INC(c);\n");
    END;

    BuildTab(gs, iNm);
    
    IF haveSpecLsb AND haveUnspecLsb THEN
      Debug.Error("Can't handle both specified and unspecified bit fields in a single register: " & r.typeName(gs))
    END;
    gs.mdecl("    CompPath.Debug(path,range);\n");
    gs.mdecl("    WITH range = CompRange.From2(base,at) DO\n");
    gs.mdecl("      (*Debug.Out(CompRange.Format(range));*)\n");
    gs.mdecl("      RETURN range\n");
    gs.mdecl("    END\n");
    gs.mdecl("  END %s;\n",iNm);
    gs.mdecl("\n");
  END GenRegInit;

PROCEDURE GenRegXInit(r : RegReg.T; gs : GenState) =
  VAR
    iNm := ComponentInitName(r, gs);
    ttn := ComponentTypeNameInHier(r, gs, TypeHier.Read);
    atn := ComponentTypeNameInHier(r, gs, TypeHier.Addr);
  BEGIN
    gs.mdecl(
           "PROCEDURE %s(READONLY t : %s; READONLY a : %s; VAR x : %s; root : REFANY; factory : UpdaterFactory.T) =\n",
           iNm,
           ttn,
           atn,
           r.typeName(gs)
           );
    gs.mdecl("  (* %s:%s *)\n", ThisFile(), Fmt.Int(ThisLine()));
    
    gs.mdecl("  BEGIN\n");
    FOR i := 0 TO r.fields.size()-1 DO
      WITH f = r.fields.get(i) DO
        gs.mdecl(
            "    x.%s := NARROW(factory.buildT(),UnsafeUpdater.T).init(root,ADR(t.%s),%s,CompPath.Cat(a.nm,\".%s\"));\n",
            f.name(debug := FALSE),
            f.name(debug := FALSE),
            Fmt.Int(f.width),
            f.name(debug := FALSE))
      END;
    END;
    gs.mdecl("  END %s;\n",iNm);
    gs.mdecl("\n");
  END GenRegXInit;

  (**********************************************************************)

PROCEDURE ComponentTypeNameInHier(c : RegComponent.T;
                                  gs : GenState;
                                  th : TypeHier) : TEXT =
  VAR
    gsC := NEW(GenState, init := InitGS).init(gs);
    prefix : TEXT;
  BEGIN
    gsC.th := th;
    IF gs.rw # TypePhase[th] THEN
      (* requesting a type from another module, need to qualify it *)
      prefix := MapIntfNameRW(gs.map, TypePhase[th]) & "."
    ELSE
      prefix := ""
    END;
    IF ISTYPE(c, RegAddrmap.T) THEN
      RETURN prefix & MainTypeName[th] (* this is bad *)
    ELSE
      RETURN prefix & c.typeName(gsC)
    END
  END ComponentTypeNameInHier;

  (**********************************************************************)

PROCEDURE ComponentTypeName(c : RegComponent.T; gs : GenState) : TEXT =
  BEGIN
    TYPECASE c OF
      RegAddrmap.T(a) =>
      RETURN a.intfName(gs) & "." & MainTypeName[gs.th]
    ELSE
      RETURN c.typeName(gs)
    END
  END ComponentTypeName;

PROCEDURE ComponentInitName(c : RegComponent.T; gs : GenState) : TEXT =
  BEGIN
    TYPECASE c OF
      RegAddrmap.T(a) =>
      RETURN a.intfName(gs) & "." & InitProcName[gs.th]
    ELSE
      RETURN "Init_" & c.typeName(gs)
    END
  END ComponentInitName;

PROCEDURE ComponentVisitName(c : RegComponent.T; gs : GenState) : TEXT =
  BEGIN
    TYPECASE c OF
      RegAddrmap.T(a) =>
      RETURN a.intfName(gs) & ".Visit" 
    ELSE
      RETURN "Visit_" & c.typeName(gs)
    END
  END ComponentVisitName;

PROCEDURE ComponentCsrName(c : RegComponent.T; gs : GenState) : TEXT =
  VAR
    gsC := NEW(GenState, init := InitGS).init(gs);
  BEGIN
    gsC.th := TypeHier.Read;
    TYPECASE c OF
      RegAddrmap.T(a) =>
      RETURN a.intfName(gs) & ".CsrAccess" 
    ELSE
      RETURN "Csr__" & c.typeName(gsC)
    END
  END ComponentCsrName;
  
PROCEDURE ComponentRangeName(c : RegComponent.T; gs : GenState) : TEXT =
  VAR
    gsC := NEW(GenState, init := InitGS).init(gs);
  BEGIN
    gsC.th := TypeHier.Read;
    TYPECASE c OF
      RegAddrmap.T(a) =>
      RETURN a.intfName(gs) & ".Range" 
    ELSE
      RETURN "Range__" & c.typeName(gsC)
    END
  END ComponentRangeName;

PROCEDURE ComponentResetName(c : RegComponent.T; gs : GenState) : TEXT =
  VAR
    gsC := NEW(GenState, init := InitGS).init(gs);
  BEGIN
    gsC.th := TypeHier.Read;
    TYPECASE c OF
      RegAddrmap.T(a) =>
      RETURN a.intfName(gs) & ".Reset" 
    ELSE
      RETURN "Reset__" & c.typeName(gsC)
    END
  END ComponentResetName;

CONST
  ComponentName = ARRAY ProcType OF PROCEDURE(c : RegComponent.T;
                                              gs : GenState) : TEXT
  { ComponentCsrName,
    ComponentRangeName,
    ComponentResetName,
    ComponentVisitName };

  (**********************************************************************)
  
PROCEDURE M3FieldType(f : RegField.T; th : TypeHier; gs : GenState) : TEXT =
  BEGIN
    RETURN M3FieldWidthType(f.width, th, gs, f.nm)
  END M3FieldType;

PROCEDURE M3FieldWidthType(c : CARDINAL; th : TypeHier; gs : GenState; name := "") : TEXT =

  PROCEDURE M3Type() : TEXT =
    BEGIN
      CASE c OF 
        WordSize =>  RETURN "Word.T"
      |
        1..WordSize-1 => RETURN F("[0..16_%s]",
                                  Fmt.Int(Word.LeftShift(1, c)-1, base := 16))
      ELSE
        IF c > WordSize THEN
          Debug.Warning(F("%s : register widths of %s > %s not natively supported in Modula-3 on this machine", name, Fmt.Int(c), Fmt.Int(WordSize)));
          RETURN
            F("ARRAY [0..%s-1] OF [0..1]", Fmt.Int(c))
        ELSE
          (* only 0 in this category *)
          Debug.Error(F("Field width %s not supported : %s", Fmt.Int(c), name))
      END;
        <*ASSERT FALSE*>
      END
    END M3Type;

  CONST
    WordSize = BITSIZE(Word.T);
    (* normally BITSIZE(Word.T) = 64 *)
  BEGIN
    CASE th OF
      TypeHier.Addr =>
      EVAL gs.m3imports.insert("CompRange");
      RETURN "CompRange.T"
      (* all fields are addresses in the write mode *)
    |
      TypeHier.Unsafe =>
      EVAL gs.i3imports.insert("Updater");
      EVAL gs.m3imports.insert("Updater");
      EVAL gs.i3imports.insert("UpdaterFactory");
      EVAL gs.m3imports.insert("UpdaterFactory");
      EVAL gs.m3imports.insert("UnsafeUpdater");
      RETURN "Updater.T" (* actually an UnsafeUpdater.T *)
    |
      TypeHier.Read => RETURN M3Type()
    |
      TypeHier.Update =>
      EVAL gs.fieldWidths.insert(c);
      RETURN "UObj"&Fmt.Int(c)
    END      
  END M3FieldWidthType;
  
PROCEDURE Updater(ofType : TEXT) : TEXT =
  BEGIN
    RETURN F("OBJECT METHODS u(READONLY x : %s) END", ofType)
  END Updater;
  
BEGIN END RegModula3.
