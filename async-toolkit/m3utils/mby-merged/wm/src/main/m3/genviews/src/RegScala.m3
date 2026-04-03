(* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE RegScala EXPORTS RegScala, RegScalaGenerators;
IMPORT GenViewsScala;
IMPORT RegReg, RegGenState, RegRegfile, RegAddrmap, RegField;
IMPORT OSError, Thread, Wr;
IMPORT Pathname, RegScalaGenState;
FROM RegScalaGenState IMPORT Section;
IMPORT Wx;
IMPORT RdlArray, BigInt;
FROM Compiler IMPORT ThisFile, ThisLine;
IMPORT Fmt;
FROM Fmt IMPORT Int, F;
IMPORT RegComponent;
IMPORT RegChildSeq;
IMPORT RegChild;
IMPORT CompAddr, CompRange;
FROM CompRange IMPORT Prop, PropNames;
FROM RegScalaConstants IMPORT IdiomName;
IMPORT RegFieldArraySort, RegFieldSeq;
IMPORT Debug;
IMPORT AtomList, Atom;
IMPORT RdlNum;
IMPORT Text;

(* this stuff really shouldnt be in this module but in Main... *)
IMPORT RdlProperty, RdlExplicitPropertyAssign;
IMPORT RdlPropertyRvalueKeyword;
FROM RegProperty IMPORT GetKw, GetNumeric;

(* stuff inherited from m3 *)
FROM RegModula3Utils IMPORT CopyWx, DefVal;


VAR doDebug := Debug.DebugThis("Scala");

REVEAL
  T = GenViewsScala.Compiler BRANDED Brand OBJECT
  OVERRIDES
    write := Write;
  END;

PROCEDURE Write(t : T; dirPath : Pathname.T; phase : Phase)
  RAISES { Wr.Failure, Thread.Alerted, OSError.E } =
  VAR
    gs : GenState := RegGenState.T.init(NEW(GenState, map := t.map), dirPath);
    intfNm := t.map.intfName(gs);
    fn := intfNm & ".scala";
    path := dirPath & "/" & fn;
  BEGIN
    FOR i := FIRST(gs.wx) TO LAST(gs.wx) DO
      gs.wx[i] := Wx.New()
    END;

    t.map.generate(gs);

    (* do the actual output *)
    IF IndividualTypeFiles THEN
      (* this is the last pending symbol .. *)
      PushPendingOutput(gs)
    ELSE
      Debug.Out("Copying output to " & path);
      CopyWx(gs.wx, path)
    END
  END Write;

PROCEDURE PushPendingOutput(gs : GenState)
  RAISES { OSError.E, Thread.Alerted, Wr.Failure } =
  (* this routine is used to push out the pending output in case of
     "IndividualTypeFiles" *)
  VAR
    path : Pathname.T;
  BEGIN
    (* is it the first symbol, in that case there is no output yet *)
    IF gs.curSym = NIL THEN RETURN END;
      
    path := gs.dirPath & "/" & gs.curSym & ".scala";
    TRY
      Debug.Out("Copying output to " & path);
      CopyWx(gs.wx, path)
    EXCEPT
      OSError.E(x) => x := AtomList.Append(x,
                                           AtomList.List1(
                                               Atom.FromText(": " & path)));
      RAISE OSError.E(x)
    END
  END PushPendingOutput;

PROCEDURE ComponentInitName(c : RegComponent.T; gs : GenState) : TEXT =
  BEGIN
    RETURN "init__" & c.typeName(gs)
  END ComponentInitName;

  
  (**********************************************************************)
  
TYPE
  GenState = RegScalaGenState.T OBJECT
    map : RegAddrmap.T; (* do we really need this? could refer to T instead *)
    curSym : TEXT := NIL;
  METHODS
    p(sec : Section; fmt : TEXT; t1, t2, t3, t4, t5 : TEXT := NIL) := GsP;
    main(fmt : TEXT; t1, t2, t3, t4, t5 : TEXT := NIL) := GsMain;
  OVERRIDES
    put := PutGS;
    newSymbol := NewSymbol;
  END;

CONST IndividualTypeFiles = TRUE;
      
PROCEDURE NewSymbol(gs : GenState; nm : TEXT) : BOOLEAN
  RAISES { OSError.E, Thread.Alerted, Wr.Failure } =
  VAR
    res : BOOLEAN;
  BEGIN
    (* is it OK to generate this symbol?  
       if we had it before -> NOT OK
       if we did not have it before -> OK
     *)
    res := RegGenState.T.newSymbol(gs, nm);

    (* if we are using "IndividualTypeFiles" we push out the output
       from the previous work before starting the next type, and do so
       into its own file. 

       if we are NOT using "IndividualTypeFiles" we instead accumulate
       all the output of ALL the types in a single big output stream
       and dump it at the end in Write().

       This slightly screwy design allows us to share more code with
       the Modula-3 generator, which generates each addrmap into its
       own file, but not every single individual type.
    *)
    
    IF IndividualTypeFiles AND res THEN

      PushPendingOutput(gs);

      gs.curSym := nm
    END;
    RETURN res
  END NewSymbol;
  
PROCEDURE PutGS(gs : GenState; sec : Section; txt : TEXT) =
  BEGIN
    Wx.PutText(gs.wx[sec], txt)
  END PutGS;

PROCEDURE GsP(gs  : GenState;
              sec : Section;
              fmt : TEXT;
              t1, t2, t3, t4, t5 : TEXT) =
  BEGIN gs.put(sec, F(fmt, t1, t2, t3, t4, t5)) END GsP;

PROCEDURE GsMain(gs : GenState; fmt : TEXT; t1, t2, t3, t4, t5 : TEXT := NIL)= 
  BEGIN gs.p(Section.Maintype, fmt, t1, t2, t3, t4, t5) END GsMain;
  
  (**********************************************************************)

(* Scala types' names *)
CONST AddressType = "Address";
(* class *)
  (* + Int *)
(* object *)
CONST AddressingType = "Addressing";
(* class *)
(* object *)
(* variants (enum or case class) *)
  (* Regalign *)
  (* Compact *)
  (* Fullalign *)
CONST PathType = "CompPath";
CONST RangeType = "AddressRange";
(* class *)
(* object *)
  (* placeReg  -- or a constructor *)
  (* makeField -- or a constructor *)
CONST RangeMonotonicType = "AddressRangeMonotonic";

(* addr map generation-related routines: *)

PROCEDURE FmtArr(a : RdlArray.Single) : TEXT =
  BEGIN
    IF a = NIL THEN
      RETURN ""
    ELSE
      RETURN F("ARRAY [0..%s-1] OF ",BigInt.Format(a.n.x))
     END
  END FmtArr;

PROCEDURE FmtArrFor(a : RdlArray.Single) : TEXT =
  BEGIN
    RETURN F("for( i <- 0 until %s ) {", BigInt.Format(a.n.x))
  END FmtArrFor;

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

CONST
   DefProp = ARRAY Prop OF TEXT {
    "32",
    "None",
    "32",
    AddressingType & ".Regalign"
  };

(* our Scala lib has meaningful memory units, so we can check them at generation-time *)
PROCEDURE FormatMemory(bits : CARDINAL) : TEXT =
  BEGIN
    IF bits MOD 8 = 0 THEN
      RETURN Fmt.Int(bits DIV 8) & ".bytes"
    ELSE
      RETURN Fmt.Int(bits) & ".bits"
    END
  END FormatMemory;

PROCEDURE GetPropText(prop : Prop; comp : RegComponent.T) : TEXT =
  VAR
    q : RdlExplicitPropertyAssign.T;
  BEGIN
    InitProps();
    q := comp.props.lookup(props[prop]);
    IF q = NIL THEN
      (* return default *)
      RETURN DefProp[prop]
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
          RETURN F("%s.%s", AddressingType, CompAddr.AddressingNames[a])
        END
      ELSE
        RETURN FormatMemory(GetNumeric(q.rhs))
      END
    END
  END GetPropText;
  
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
      IF NOT Text.Equal(args[i], "None") THEN
        res := res & F(", %s = %s", PropNames[i], args[i])
      END
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
    childArc := IdiomName(e.nm,debug := FALSE);

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
      atS := F("base + 0x%s",
               Fmt.Int(BigInt.ToInteger(e.at.x), base := 16))
    ELSIF e.mod # RegChild.Unspecified THEN
      atS := F("at.modAlign(0x%s)",
               Fmt.Int(BigInt.ToInteger(e.mod.x), base := 16))
    END;
    
    IF e.array = NIL THEN
      gs.main(
             "    at = mono.increase(at, %s(x.%s, %s, CompPath.Cat(path, \".%s\")))\n",
               ComponentInitName(e.comp,gs),
               childArc,
               atS,
               childArc);
      gs.main("    buff = buff :+ (at, x.%s)\n", childArc);
    ELSE
      (* e.array # NIL *)
      gs.main("    var q = %s\n", atS);

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
              gs.main("    q = CompAddr.Align(at, %s);\n",  (* TOCHECK: modAlign? *)
                                     Fmt.Int(alignTo))
            END
          END
        ELSE
          (* fullalign given, stride not given, mod not given, at not given *)
          (* make a throwaway "first" and "second", measure distance between,
             then align at to that and proceed *)
          gs.main("    var first  = %s(x.%s(0), CompAddr.Zero, None)\n",
                                 ComponentInitName(e.comp,gs),
                                 childArc);
          gs.main("    var second = %s(x.%s(1), first.lim, None)\n",
                                 ComponentInitName(e.comp,gs),
                                 childArc);
          gs.main("    require( first != second )\n");
          gs.main("    val len = second.lim.deltaBytes(first.lim)\n");
          gs.main("    at = at.modAlign(len.nextPower)\n");
          gs.main("    q = at\n");
        END
      END;
      
      gs.main("    %s\n",FmtArrFor(e.array));
      gs.main("      at = mono.increase(at, %s(x.%s(i), q, CompPath.CatArray(path, \".%s\", i)))\n",
               ComponentInitName(e.comp,gs),
               childArc,
               childArc);
      (* IF NOT skipArc THEN *)
      gs.main("      buff = buff :+ (at, x.%s(i))\n", childArc);
      (* END; *)
      IF e.stride # RegChild.Unspecified THEN
        gs.main("      q = q + 0x%s.bytes\n",
                               Fmt.Int(BigInt.ToInteger(e.stride.x), base := 16))
      ELSE
        gs.main("      q = at\n")
      END;
      gs.main("    }\n")
    END
  END GenChildInit;

(* generating routines *)

PROCEDURE GenRegInit(r : RegReg.T; gs : GenState) =
  VAR 
    iNm := ComponentInitName(r, gs);  (* builder's name *)
    props := GetPropTexts(r);         (* alignment type *)
    haveUnspecLsb := FALSE;
    haveSpecLsb := FALSE;
  BEGIN
    gs.main("  override def addressRegisterMap(x: %s, addr: %s, path: %s): SortedMap[%s, _ <: IndexedSeq[RdlElement]] = {\n",
      (* iNm,           builder's name  *)
      r.typeName(gs),  (* parser's type *)
      AddressType,
      PathType,
      AddressType);
    gs.main("    // %s:%s\n", ThisFile(), Fmt.Int(ThisLine()));
    gs.main("    var at = addr\n");
    gs.main("    val range = %s.placeReg(at%s)\n", RangeType, FormatPropArgs(props));
    gs.main("    var mono = %s()\n", RangeMonotonicType);
    gs.main("    var buff = IndexedSeq[(%s, _ <: IndexedSeq[RdlElement])]()\n", AddressType);
    (* if x.tab was an immutable Vector (default IndexedSeq)... *)
    (* no diff if it's IndexedSeq, Array or ArrayBuffer --- conversion to map will require iteration *)

    gs.main("\n");
    gs.main("    at = range.pos\n");
    (* we don't want `this` in the map *)
    (* gs.main("    buff = buff :+ (at, DegenerateHierarchy[IndexedSeq[%s]](this))\n", ...); *)

    (* TODO *)
    (* consider using Vector or a SortedMap *)
    (* if a Vector, one needs two: one for indexing the other and the other ones with refs *)
    
    SortFieldsIfAllSpecified(r.fields);
    FOR i := 0 TO r.fields.size()-1 DO
      WITH f = r.fields.get(i) DO
        <*ASSERT f.width # RegField.Unspecified*>
        IF f.lsb = RegField.Unspecified THEN
          haveUnspecLsb := TRUE;
          gs.main("    x.%s = %s.makeField(at, %s)\n",
                   f.name(debug := FALSE),
                   RangeType,
                   Fmt.Int(f.width));
        ELSE
          haveSpecLsb := TRUE;
          gs.main("    x.%s = %s.makeField(range.pos + %s, %s)\n",
                   f.name(debug := FALSE),
                   RangeType,
                   FormatMemory(f.lsb),
                   FormatMemory(f.width));
        END;
        gs.main("    at = mono.increase(at, x.%s)\n",
                 f.name(debug := FALSE));
        (* TOASK: is it not counting registers? we have sth like that *)
        (* gs.main(
               "    INC(CompAddr.initCount)\n"); *)
        gs.main("    buff = buff :+ (at, x.%s)\n", f.name(debug := FALSE));
      END;
      (* gs.main("    x.tab(c) = at; c += 1\n"); *)
    END;

    BuildTab(gs, iNm);
    
    IF haveSpecLsb AND haveUnspecLsb THEN
      Debug.Error("Can't handle both specified and unspecified bit fields in a single register: " & r.typeName(gs))
    END;
    gs.main("    CompPath.Debug(path,range)\n");
    (* gs.main("    return %s.From2(base,at)\n", RangeType); *)
    gs.main("\n");
    gs.main("    SortedMap(buff: _*)\n");
    gs.main("  }");
    gs.main("\n\n");
  END GenRegInit;

 PROCEDURE GenRegfileInit(rf : RegRegfile.T; gs : GenState) =
  VAR
    iNm := ComponentInitName(rf, gs);
    skipArc := rf.children.size() = 1;
  BEGIN
    gs.main("  override def addressRegisterMap(x: %s, addr: %s, path: %s): SortedMap[%s, _ <: IndexedSeq[RdlElement]] = {\n",
      (* iNm,           builder's name  *)
      rf.typeName(gs),  (* parser's type *)
      AddressType,
      PathType,
      AddressType);
    gs.main("    // %s:%s\n", ThisFile(), Fmt.Int(ThisLine()));
    gs.main("    var at = addr\n");
    gs.main("    var mono = %s()\n", RangeMonotonicType);
    gs.main("    var buff = IndexedSeq[(Int, _ <: IndexedSeq[RdlElement])]()\n");

    FOR i := 0 TO rf.children.size()-1 DO
      (* special case:
         if RF has a single member, it is not a record, instead it
         is (a) an array of the child type (if an array)
         OR (b) a copy of the child type (if a scalar)
      *)
      GenChildInit(rf.children.get(i),
                   gs,
                   GetAddressingProp(rf),
                   skipArc := skipArc);
    END;
    IF NOT skipArc THEN BuildTab(gs, iNm) END;

    (* gs.main("    RETURN CompRange.From2(base,at)\n"); *)
    gs.main("    SortedMap(buff: _*)\n");
    gs.main("  }");
    gs.main("\n\n");
  END GenRegfileInit;

PROCEDURE SortFieldsIfAllSpecified(seq : RegFieldSeq.T) =
  VAR
    arr : REF ARRAY OF RegField.T;
  BEGIN
    FOR i := 0 TO seq.size()-1 DO
      IF seq.get(i).lsb = RegField.Unspecified THEN
        RETURN (* can't sort *)
      END
    END;
    arr := NEW(REF ARRAY OF RegField.T, seq.size());
    FOR i := 0 TO seq.size()-1 DO
      arr[i] := seq.get(i)
    END;
    RegFieldArraySort.Sort(arr^);
    FOR i := 0 TO seq.size()-1 DO
      seq.put(i,arr[i])
    END
  END SortFieldsIfAllSpecified;

 PROCEDURE BuildTab(gs : GenState; iNm : TEXT) =
   BEGIN
     gs.main("    require( c == x.tab.length)\n");
     gs.main("    x.nonmono = !mono.isok()\n");
     SetTabEnds(gs);
     gs.main("    if( x.nonmono ) {\n");
     gs.main("      x.monomap = mono.indexArr()\n");
     gs.main("      Debug.Warning(\"Nonmono in %s\")\n",
                             iNm);
     gs.main("    }\n");
  END BuildTab;
   
 PROCEDURE SetTabEnds(gs : GenState) =
   (* update the tab so that min is least and max is most *)
   BEGIN
     gs.main("    mono.setRange(x.min,x.max)\n")
  END SetTabEnds;

  (**********************************************************************)

CONST StdFieldAttrs = "RdlField with HardwareReadable with HardwareWritable";

PROCEDURE GenReg(r : RegReg.T; genState : RegGenState.T)
  RAISES { OSError.E, Thread.Alerted, Wr.Failure } =
  VAR
    gs : GenState := genState;
    myTn := r.typeName(gs);

  PROCEDURE PutFields( (* could restrict here *) ) =
    BEGIN
      FOR i := 0 TO r.fields.size()-1 DO
        WITH nm = r.fields.get(i).name(debug := FALSE) DO
          gs.main(nm);
          IF i # r.fields.size()-1 THEN gs.main(", ") END
        END
      END
    END PutFields;
    
  BEGIN
    IF NOT gs.newSymbol(myTn) THEN RETURN END;
    gs.main("package madisonbay.csr\n");
    gs.main("import madisonbay.memory._\n");
    gs.main("import com.intel.cg.hpfd.csr.macros.annotations.reg\n");
    gs.main("import monocle.macros.Lenses\n");
    gs.main("\n// %s:%s\n", ThisFile(), Fmt.Int(ThisLine()));
    gs.main("trait %s_instance {\n", myTn);
    gs.main("@reg class %s {\n", myTn);
    (*
    gs.main("case class %s(addr: Address, state: Long) extends RdlRegister[%s] {\n", myTn, myTn);
    gs.main("  val name: String = \"%s\"\n", myTn);
    gs.main("\n");
    gs.main("  def copy(addr: Address = this.addr, state: Long = this.state): %s = new %s(addr, state)\n", myTn, myTn);
    gs.main("  def copy(newState: Long): %s = new %s(addr, newState)\n", myTn, myTn);
    gs.main("\n");
    gs.main("  def reset(): %s = copy(0xDEADBEEFl)\n", myTn);
    gs.main("\n");
    *)
    FOR i := 0 TO r.fields.size()-1 DO
      WITH f  = r.fields.get(i),
           nm = f.name(debug := FALSE),
           (* nm = f.name(debug := TRUE), *)
           dv = DefVal(f.defVal),
           myEn = "Long" (* for now *) DO
        (*
        gs.main("  def %s = new RdlField[%s, %s](this) ", nm, myTn, myEn);
        gs.main("with HardwareReadable[%s] with HardwareWritable[%s, %s] {\n", myEn, myTn, myEn);

        gs.main("    val name = \"%s\"\n", f.name(debug := FALSE));
        gs.main("    val range = %s until %s\n", Int(f.lsb), Int(f.lsb+f.width));
        gs.main("    override val resetValue = 0x%sl\n", BigInt.Format(dv,base:=16));
        gs.main("  }\n");
        *)
        gs.main("  field %s(%s until %s, hard = \"R+W\", soft = \"\") {\n", nm, Int(f.lsb), Int(f.lsb+f.width));
        gs.main("    resetValue = 0x%sl\n", BigInt.Format(dv, base := 16));
        gs.main("  }\n");
      END
    END;
    (* gs.main("\n"); *)

    (* GenRegInit(r, gs); *)
    gs.main("}\n");
    gs.main("}\n\n");

    (* sth like put reg object *)
    (*
    gs.main("  object %s {\n", myTn);
    gs.main("    def apply(address: Address): %s = {\n", myTn);
    gs.main("      %s(AddressRange.placeReg(address, Alignment(8 bytes)).pos, 0xDEADBEEF)\n", myTn);
    gs.main("    }\n");
    gs.main("  }\n");
    gs.main("}\n");
    *)

    (*PutRegObject(myTn, gs);*)
  END GenReg;

PROCEDURE PutChildrenDef(children : RegChildSeq.T;
                         genState : RegGenState.T) 
  RAISES {} =
  VAR
    gs : GenState := genState;
  BEGIN
    gs.main("\n");
    gs.main("  def children =\n");
    FOR i := 0 TO children.size()-1 DO
      WITH c = children.get(i) DO
        gs.main("    %s ::\n", IdiomName(c.nm))
      END
    END;
    gs.main("    Nil\n");
  END PutChildrenDef;

PROCEDURE PutAddrMapDef(children : RegChildSeq.T;
                        genState : RegGenState.T) 
  RAISES {} =
  VAR
    gs : GenState := genState;
  BEGIN
    gs.main("\n");
    gs.main("  override def addressRegisterMap(baseAddress: Int) = SortedMap[Int, RdlElement](");
    FOR i := 0 TO children.size()-1 DO
      WITH c = children.get(i) DO
        gs.main("\n");
        IF c.at = RegChild.Unspecified THEN
          gs.main("    (-1, %s(0))", IdiomName(c.nm));
        ELSE
          gs.main("    (baseAddress + %s, %s(0))", Fmt.Int(BigInt.ToInteger(c.at.x)), IdiomName(c.nm));
        END;
        IF i # children.size()-1 THEN gs.main(",") END;
      END
    END;
    gs.main(")\n");
  END PutAddrMapDef;


  (* the way this is coded, GenRegfile and GenAddrmap could be merged into
     one routine, viz., GenContainer *)
  
PROCEDURE GenRegfile(rf       : RegRegfile.T;
                     genState : RegGenState.T) 
  RAISES { Wr.Failure, Thread.Alerted, OSError.E } =
  VAR
    gs : GenState := genState;
    myTn := rf.typeName(gs);
  BEGIN
    IF NOT gs.newSymbol(myTn) THEN RETURN END;
    gs.main("package madisonbay.csr\n");
    gs.main("import madisonbay.memory._\n");
    gs.main("import madisonbay.memory.ImplicitConversions._\n");
    gs.main("import madisonbay.PrimitiveTypes._\n");
    gs.main("import monocle.macros.Lenses\n");
    gs.main("import com.intel.cg.hpfd.csr.macros.annotations._\n");
    gs.main("\n// %s:%s\n", ThisFile(), Fmt.Int(ThisLine()));

    gs.main("trait %s_instance {\n", myTn);

    gs.main("  @Initialize\n");
    gs.main("  @Lenses(\"_\")\n");
    gs.main("  @GenOpticsLookup\n");
    gs.main("  case class %s(\n", myTn);
    gs.main("    range: AddressRange");
    FOR i := 0 TO rf.children.size()-1 DO
      WITH c  = rf.children.get(i),
           tn = ComponentTypeName(c.comp,gs) DO
        gs.main(",\n    @OfSize(%s) %s: List[all.%s]", Int(ArrSz(c.array)), IdiomName(c.nm), tn);
      END
    END;
    gs.main("\n  )\n");

    gs.main("}");

    (*PutChildrenDef(rf.children, gs);*)
    (* PutAddrMapDef(rf.children, gs); *)
    (* GenRegfileInit(rf, gs); *)
    (*PutObject(myTn, gs);*)
    FOR i := 0 TO rf.children.size()-1 DO
      WITH c = rf.children.get(i) DO
        <*ASSERT c.comp # NIL*>
        c.comp.generate(gs)
      END
    END
   END GenRegfile;

PROCEDURE GenAddrmap(map     : RegAddrmap.T; gsF : RegGenState.T) 
  RAISES { OSError.E, Thread.Alerted, Wr.Failure } =
  VAR
    gs : GenState := gsF;
    myTn := map.typeName(gs);  
  BEGIN
    IF NOT gs.newSymbol(myTn) THEN RETURN END;
    gs.main("package madisonbay.csr\n");
    gs.main("import madisonbay.memory._\n");
    gs.main("import monocle.macros.Lenses\n");
    gs.main("import com.intel.cg.hpfd.csr.macros.annotations._\n");
    gs.main("\n// %s:%s\n", ThisFile(), Fmt.Int(ThisLine()));
    gs.main("trait %s_instance {\n", myTn);
    gs.main("  @Lenses(\"_\")\n");
    gs.main("  @GenOpticsLookup\n");
    gs.main("  @Initialize\n");
    gs.main("  case class %s(\n", myTn);
    gs.main("    range: AddressRange");
    FOR i := 0 TO map.children.size()-1 DO
      WITH c  = map.children.get(i),
           tn = ComponentTypeName(c.comp,gs) DO
        IF (c.array = NIL) THEN
          gs.main(",\n    %s: all.%s", IdiomName(c.nm), tn)
        ELSE
          gs.main(",\n    @OfSize(%s) %s: List[all.%s]", Int(ArrSz(c.array)), IdiomName(c.nm), tn)
        END
      END
    END;
    gs.main("\n  )\n");
    gs.main("}\n");

    (*PutChildrenDef(map.children, gs);*)
    (*PutAddrMapDef(map.children, gs);*)
    (*PutObject(myTn, gs);*)
    FOR i := 0 TO map.children.size()-1 DO
      WITH c = map.children.get(i) DO
        <*ASSERT c.comp # NIL*>
        c.comp.generate(gs)
      END
    END
 END GenAddrmap;

  (**********************************************************************)

PROCEDURE PutObject(tn : TEXT; gs : GenState) =
  BEGIN
    gs.main("object %s {\n", tn);
    gs.main("  def apply(parent : RdlHierarchy) : %s = apply(Some(parent))\n", tn);
    gs.main("  def apply(parent : Option[RdlHierarchy] = None) : %s = {\n", tn);
    gs.main("    new %s(parent)\n", tn);
    gs.main("  }\n");
    (* what's that implicit def stuff in Michael's email? *)
    gs.main("}\n");
  END PutObject;

  PROCEDURE PutRegObject(tn : TEXT; gs : GenState) =
    BEGIN
      gs.main("object %s {\n", tn);
      gs.main("  def apply(address : Address) : %s = {\n", tn);
      gs.main("    new %s(???, 0xDEADBEEFl)\n", tn);
      gs.main("  }\n");
      gs.main("  type Underlying = U64\n");

      (* what's that implicit def stuff in Michael's email? *)
      gs.main("}\n");
    END PutRegObject;

  (**********************************************************************)
  
PROCEDURE ArrSz(a : RdlArray.Single) : CARDINAL =
  BEGIN
    IF a = NIL THEN
      RETURN 1
    ELSE
      RETURN BigInt.ToInteger(a.n.x)
    END
  END ArrSz;
  
PROCEDURE ComponentTypeName(c : RegComponent.T; gs : GenState) : TEXT =
  BEGIN
    TYPECASE c OF
      RegAddrmap.T(a) =>
      RETURN a.intfName(gs) 
    ELSE
      RETURN c.typeName(gs)
    END
  END ComponentTypeName;

BEGIN END RegScala.
