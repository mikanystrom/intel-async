(* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE GenViewsSvFulcrum;
IMPORT RegReg, RegField, RegContainer, RegChild, RegAddrmap;
IMPORT Pathname;
IMPORT Debug;
FROM Fmt IMPORT F, Int;
IMPORT Text;
IMPORT BigInt;
IMPORT FieldData, Rd, Pickle2;
IMPORT Wx;
IMPORT CitTextUtils AS TextUtils;
IMPORT RegComponent;
IMPORT Thread;
FROM RegProperty IMPORT Unquote;
IMPORT CardSeq;
IMPORT BigIntSeq;
IMPORT Word;
IMPORT RdlPredefProperty;
IMPORT TreeType, TreeTypeClass;
IMPORT TreeTypeArraySeq;
IMPORT TextSetDef;
IMPORT IndexBits;
IMPORT Wr, FileWr;
IMPORT OSError, FS, AL;
IMPORT ParseError;

<*FATAL Thread.Alerted*>
<*FATAL BigInt.OutOfRange*>

CONST TE = Text.Equal;

REVEAL
  T = Public BRANDED OBJECT
    wx : Wx.T;
    ac : AddressConverter;
    nfields : CARDINAL;
  METHODS
    put(txt : TEXT; lev : CARDINAL) := Put;
  OVERRIDES
    gen := Gen;
  END;

PROCEDURE Put(t : T; txt : TEXT; lev : CARDINAL) =
  BEGIN
    Wx.PutText(t.wx, Spaces(lev));
    Wx.PutText(t.wx, txt);
    Wx.PutText(t.wx, "\n");
  END Put;

PROCEDURE Spaces(lev : CARDINAL) : TEXT =
  VAR
    a := NEW(REF ARRAY OF CHAR, lev*2);
  BEGIN
    FOR i := FIRST(a^) TO LAST(a^) DO
      a[i] := ' '
    END;
    RETURN Text.FromChars(a^)
  END Spaces;

TYPE
  Arc = OBJECT
    up  : Arc;
  END;

  ArrayArc = Arc OBJECT
    sz : CARDINAL;
  END;

  NameArc = Arc OBJECT
    idx : CARDINAL;
    nm  : TEXT;
    field := FALSE;
  END;

PROCEDURE Gen(t : T; tgtmap : RegAddrmap.T; outDir : Pathname.T) =
  VAR
    a : REF ARRAY OF FieldData.T := NIL;
    b : REF ARRAY OF CARDINAL := NIL;
  BEGIN
    t.wx := Wx.New();
    TRY
      IF t.fieldAddrRd # NIL THEN
        Debug.Out("Reading field data...");
        a := Pickle2.Read(t.fieldAddrRd);
        Debug.Out("size of a : " & Int(NUMBER(a^)));
        b := Pickle2.Read(t.fieldAddrRd);
        Debug.Out("size of b : " & Int(NUMBER(b^)));
        Rd.Close(t.fieldAddrRd)
      END;
    EXCEPT
      Pickle2.Error => Debug.Error("Pickle.Error reading pickle from file")
    |
      Rd.EndOfFile => Debug.Error("short read reading pickle from file")
    |
      Rd.Failure(x) =>
        Debug.Error("I/O Error reading pickle from file : Rd.Failure : " & AL.Format(x))
    END;
    WITH tree = TreeType.To(tgtmap),
         ac   = NEW(AddressConverter, a := a) DO
      tree.offset := 0;
      tree.up := NIL;
      t.ac := ac;
      t.nfields := NUMBER(a^);
      TreeType.ComputeAddresses(tree, 0, ac);
      <*ASSERT t.packageName # NIL*>
      t.put("package " & t.packageName & ";", 0);
      DoContainer(t, tgtmap, 1, NIL, tree);
      t.put("endpackage", 0)
    END;
    <*ASSERT outDir # NIL*>
    <*ASSERT t.outFileName # NIL*>
    WITH pn = outDir & "/" & t.outFileName DO
      TRY
       TRY
          EVAL FS.Iterate(outDir)
        EXCEPT
          OSError.E(x) => Debug.Error(F("Problem opening directory \"%s\" : OSError.E : %s", outDir, AL.Format(x)))
        END;
       
       WITH wr = FileWr.Open(pn) DO
         Wr.PutText(wr, Wx.ToText(t.wx));
         Wr.Close(wr)
       END
      EXCEPT
         OSError.E(x) =>
        Debug.Error("Error in " &
          Brand & " code generation : OSError.E : " & AL.Format(x))
      |
       
        Wr.Failure(x) =>
        Debug.Error("Error in " &
          Brand & " code generation : Wr.Failure : " & AL.Format(x))
      END
    END
  END Gen;

TYPE
  AddressConverter = TreeType.AddressConverter OBJECT
    a : REF ARRAY OF FieldData.T;
  OVERRIDES
    field2bit := Field2Bit;
  END;
  
PROCEDURE Field2Bit(ac : AddressConverter; field : CARDINAL) : Word.T =
  BEGIN
    IF field > LAST(ac.a^) THEN
      Debug.Error(F("field %s > LAST(ac.a^) = %s",
                    Int(field), Int(LAST(ac.a^))))
    END;
    WITH fd = ac.a[field] DO
      RETURN Word.Plus(Word.Times(fd.byte,8),fd.lsb)
    END
  END Field2Bit;

PROCEDURE DoContainer(t    : T;
                      c    : RegContainer.T;
                      lev  : CARDINAL;
                      pfx  : Arc;
                      tree : TreeType.T  ) =
  VAR
    skipArc := c.skipArc();
    svName := FormatNameArcsOnly(pfx);
  BEGIN
    <*ASSERT c # NIL*>
    EmitComment(t, "Container", pfx, lev);

    IF pfx # NIL THEN
      WITH addrB = tree.addrBits DIV 8,
           next  = tree.address + tree.sz DO
        <*ASSERT tree.addrBits MOD 8 = 0 *>
        EmitLocalParam(t,
                       svName & "_BASE",
                       addrB,
                       t.addrBits,
                       lev);
        IF next # t.nfields THEN
          (* we cant do this FOR the last object *)
          WITH nextb = t.ac.field2bit(next),
               szb = nextb - tree.addrBits,
               szB = szb DIV 8 DO
            <*ASSERT szb MOD 8 = 0*>
            EmitLocalParam(t,
                           svName & "_SIZE",
                           szB,
                           t.addrBits,
                           lev)
          END
        END
      END
    END;
      

    FOR i := 0 TO c.children.size()-1 DO
      VAR chld := c.children.get(i);
          arc : Arc := pfx;
          ct  : TreeType.T;
      BEGIN        
        IF skipArc THEN
          ct := NARROW(tree, TreeType.Array).elem
        ELSE
          arc := NEW(NameArc,
                     idx := i,
                     nm := FulcrumName(chld.comp, chld.nm),
                     up := arc);
          ct := NARROW(tree, TreeType.Struct).fields.get(i)
        END;

        IF chld.array # NIL THEN
          arc := NEW(ArrayArc,
                     sz := BigInt.ToInteger(chld.array.n.x),
                     up := arc);
          IF NOT skipArc THEN (* confusing, cf. TreeType.Container *)
            ct := NARROW(ct, TreeType.Array).elem
          END;
        END;

        DoChild(t, chld, lev, arc, skipArc, ct)
      END
    END;
    EmitComment(t, "Container", pfx, lev, TRUE);
    Emit(t,"",lev);
  END DoContainer;

PROCEDURE HasNoFurtherArcs(c : RegComponent.T) : BOOLEAN =
  BEGIN
    TYPECASE c OF
      RegReg.T  =>
      RETURN TRUE (* it's a register, so we have done the last arc *)
    |
      RegContainer.T(container) =>
      (* recursively go down and ensure every level has only one child,
         and the recursion bottoms in a register *)
      RETURN
        container.children.size()=1 AND
        HasNoFurtherArcs(container.children.get(0).comp)
    ELSE
      <*ASSERT FALSE*>
    END    
  END HasNoFurtherArcs;
  
PROCEDURE DoChild(t       : T;
                  c       : RegChild.T;
                  lev     : CARDINAL;
                  pfx     : Arc;
                  <*UNUSED*>skipArc : BOOLEAN;(*why?*)
                  tree    : TreeType.T ) =
  BEGIN
    WITH ccomp = c.comp DO
      TYPECASE ccomp OF
        RegContainer.T => DoContainer(t, ccomp, lev, pfx, tree)
      |
        RegReg.T       => DoReg(t, ccomp, lev, pfx, tree)
      |
        RegField.T     => <*ASSERT FALSE*> (* right? *)
      ELSE
        <*ASSERT FALSE*>
      END
    END
  END DoChild;

PROCEDURE EmitComment(t    : T;
                      node : TEXT;
                      pfx  : Arc;
                      lev  : CARDINAL;
                      end  := FALSE) =
  VAR
    endS := "";
  BEGIN
    IF end THEN endS := "END " END;
    
    Emit(t, F("  // %s%s %-60s", endS, node, FormatNameArcsOnly(pfx)), lev);
    IF NOT end AND NOT TE(node, "Field") THEN
      Emit(t, F("  // arr %s", FormatArrayArcsOnly(pfx)), lev)
    END
  END EmitComment;
  
PROCEDURE DoField(t : T; f : RegField.T; lev : CARDINAL; pfx : Arc) =
  BEGIN
    EmitComment(t, "Field", pfx, lev);

    IF f.lsb = RegField.Unspecified THEN
      Debug.Warning("Unspecified LSB in field " & f.nm)
    END;
    IF f.width = RegField.Unspecified THEN
      Debug.Warning("Unspecified width in field " & f.nm)
    END;

    EmitLocalParam(t, FormatNameArcsOnly(pfx, "W_"), f.width, -1, lev); 
    IF f.width = 1 THEN
      EmitLocalParam(t, FormatNameArcsOnly(pfx, "B_"), f.lsb, -1, lev) 
    ELSE
      EmitLocalParam(t, FormatNameArcsOnly(pfx, "L_"), f.lsb, -1, lev); 
      EmitLocalParam(t, FormatNameArcsOnly(pfx, "H_"), f.lsb+f.width-1, -1, lev) 
    END;
  END DoField;

PROCEDURE Emit(t : T; str : TEXT; lev : CARDINAL) =
  BEGIN
    Debug.Out(str);
    t.put(str, lev);
  END Emit;

VAR localParams := NEW(TextSetDef.T).init();
    
PROCEDURE EmitLocalParam(t       : T;
                         nm      : TEXT;
                         val     : INTEGER;
                         hexBits : [-1..LAST(CARDINAL)];
                         lev     : CARDINAL) =
  VAR
    valStr : TEXT;
  BEGIN
    IF localParams.insert(nm) THEN
      Debug.Error("Multiple definitions for localparam \"" & nm & "\", please uniquify!")
    END;
    IF hexBits = -1 THEN
      valStr := Int(val)
    ELSE
      <*ASSERT val >= 0*>
      <*ASSERT val < Word.Shift(1,hexBits)*>
      valStr := F("%s'h%s", Int(hexBits), Int(val, base := 16))
    END;
    WITH str = F(LocalParamFmt, nm, valStr) DO
      Emit(t, str, lev)
    END
  END EmitLocalParam;

PROCEDURE EmitTextLocalParam(t       : T;
                             nm      : TEXT;
                             val     : TEXT;
                             lev     : CARDINAL) =
  BEGIN
    IF localParams.insert(nm) THEN
      Debug.Error("Multiple definitions for localparam \"" & nm & "\", please uniquify!")
    END;
    WITH str = F(LocalParamFmt, nm, val) DO
      Emit(t, str, lev)
    END
  END EmitTextLocalParam;

CONST LocalParamFmt = "  localparam %-55s = %s;";

PROCEDURE EmitBigLocalParam(t       : T;
                            nm      : TEXT;
                            val     : BigInt.T;
                            hexBits : [-1..LAST(CARDINAL)];
                            lev     : CARDINAL) =
  VAR
    valStr : TEXT;
  BEGIN
    IF localParams.insert(nm) THEN
      Debug.Error("Multiple definitions for localparam \"" & nm & "\", please uniquify!")
    END;
    IF hexBits = -1 THEN
      valStr := BigInt.Format(val)
    ELSE
      <*ASSERT BigInt.Compare(val,BigInt.New(0)) >= 0 *>
      <*ASSERT BigInt.Compare(val,BigPow2(hexBits)) < 1 *>
      valStr := F("%s'h%s", Int(hexBits), BigInt.Format(val, base := 16))
    END;
    WITH str = F(LocalParamFmt, nm, valStr) DO
      Emit(t, str, lev)
    END
  END EmitBigLocalParam;
  
PROCEDURE DoReg(t    : T;
                r    : RegReg.T;
                lev  : CARDINAL;
                pfx  : Arc;
                tree : TreeType.Struct) =
  VAR
    atomic : INTEGER;
    width  : INTEGER;
    svName := FormatNameArcsOnly(pfx);
    lim := 0;
    rst := BigInt.New(0);
  BEGIN
    EmitComment(t, "Reg", pfx, lev);
    Emit(t, "  // " & TreeType.Format(tree), lev);

    TRY
      WITH hadIt = r.getRdlPredefIntProperty(RdlPredefProperty.T.accesswidth,
                                             atomic) DO
        <*ASSERT hadIt*>
      END;
      WITH hadIt = r.getRdlPredefIntProperty(RdlPredefProperty.T.regwidth,
                                             width) DO
        <*ASSERT hadIt*>
      END
    EXCEPT
      ParseError.E(txt) =>
      Debug.Error("Unexpected syntax in reading RDL accesswidth/regwidth properties : " &
        txt)
    END;

    <*ASSERT atomic MOD 8 = 0*>
    <*ASSERT width  MOD 8 = 0*>
    EmitLocalParam(t, svName & "_ATOMIC_WIDTH", width DIV 8, -1, lev);

    FOR i := 0 TO r.fields.size()-1 DO
      WITH f = r.fields.get(i) DO
        lim := MAX(lim, f.lsb + f.width);
        IF f.defVal # NIL THEN
          rst := BigInt.Add(rst,
                             BigInt.Mul(f.defVal.x,BigPow2(f.lsb)))
        END
      END
    END;
    EmitLocalParam(t, svName & "_BITS", lim, -1, lev);
    EmitBigLocalParam(t, svName & "_DEFAULT", rst, lim, lev);
   
    VAR
      arraySizes := ArraySizes(pfx);
      arrays := NEW(TreeTypeArraySeq.T).init();
      addrB := tree.addrBits DIV 8;
    BEGIN
      <*ASSERT tree.addrBits MOD 8 = 0 *>
      TreeTypeClass.GetArrays(tree, arrays);
      
      CASE arraySizes.size() OF
        0 =>
        EmitLocalParam(t, svName & "_ADDR", addrB, t.addrBits, lev)
      |
        1 =>
        WITH arr          = arrays.get(0),
             strideBytes  = arr.strideBits DIV 8,
             strideBitSet = IndexBits.FromReg(lim) + IndexBits.FromArray(arr.n, strideBytes) DO
          Emit(t, "  // " & TreeType.Format(arr), lev);
          <*ASSERT arraySizes.get(0) = arr.n*>
          <*ASSERT arr.strideBits MOD 8 = 0*>
          EmitLocalParam(t,
                         svName & "_ENTRIES",
                         arraySizes.get(0),
                         -1,
                         lev);
          EmitLocalParam(t,
                         svName & "_STRIDE",
                         strideBytes,
                         -1,
                         lev);
          EmitTextLocalParam(t,
                             svName & "_MASK",
                             IndexBits.FormatMask(t.addrBits, strideBitSet),
                             lev);
          EmitTextLocalParam(t,
                             svName & "_BASEQ",
                             IndexBits.FormatBaseQ(t.addrBits,
                                                   strideBitSet,
                                                   addrB),
                             lev);
          EmitLocalParam(t,
                         svName & "_INDEX_H",
                         IndexBits.Hi(strideBitSet),
                         -1,
                         lev);
          EmitLocalParam(t,
                         svName & "_INDEX_L",
                         IndexBits.Lo(strideBitSet),
                         -1,
                         lev);
        END
      ELSE
        VAR
          allStridesBitSet := IndexBits.FromReg(lim);
        BEGIN
          FOR i := 0 TO arraySizes.size()-1 DO
            WITH arr         = arrays.get(i),
                 strideBytes = arr.strideBits DIV 8,
                 strideBitSet = IndexBits.FromArray(arr.n, strideBytes) DO
              Emit(t, "  // " & TreeType.Format(arr), lev);
              <*ASSERT arraySizes.get(i) = arrays.get(i).n*>
              <*ASSERT arr.strideBits MOD 8 = 0*>
              EmitLocalParam(t,
                             svName & "_ENTRIES_" & Int(i),
                             arraySizes.get(i),
                             -1,
                             lev);
              EmitLocalParam(t,
                             svName & "_STRIDE_" & Int(i),
                             strideBytes,
                             -1,
                             lev);
              EmitLocalParam(t,
                             svName & "_INDEX_H_" & Int(i),
                             IndexBits.Hi(strideBitSet),
                             -1,
                             lev);
              EmitLocalParam(t,
                             svName & "_INDEX_L_" & Int(i),
                             IndexBits.Lo(strideBitSet),
                             -1,
                             lev);
              allStridesBitSet := allStridesBitSet + strideBitSet;
            END(*WITH*);
          END(*FOR*);
          EmitTextLocalParam(t,
                             svName & "_MASK",
                             IndexBits.FormatMask(t.addrBits, allStridesBitSet),
                             lev);
          EmitTextLocalParam(t,
                             svName & "_BASEQ",
                             IndexBits.FormatBaseQ(t.addrBits,
                                                   allStridesBitSet,
                                                   addrB),
                             lev);
        END
      END
    END;
    
    FOR i := 0 TO r.fields.size()-1 DO
      WITH f = r.fields.get(i),
           arc = NEW(NameArc,
                     idx := i,
                     nm := FulcrumName(f, f.nm),
                     up := pfx,
                     field := TRUE) DO
        DoField(t, f, lev, arc)
      END
    END;
    EmitComment(t, "Reg", pfx, lev, TRUE);
    Emit(t,"",lev);
  END DoReg;

PROCEDURE FulcrumName(comp : RegComponent.T; iNm : TEXT) : TEXT =
  VAR
    hn : TEXT;
    gotIt : BOOLEAN;
  BEGIN
    TRY
      gotIt := comp.getRdlTextProperty("FulcrumName", hn);
      IF gotIt THEN
        hn := Unquote(hn);
        hn := TextUtils.Replace(hn, "$", iNm)
      END;
      IF hn = NIL OR TE(hn, "") THEN
        hn := iNm
      END;
      RETURN hn
    EXCEPT
      ParseError.E(txt) =>
      Debug.Error("Unexpected syntax in reading RDL UDP \"FulcrumName\" : " &
        txt);
      <*ASSERT FALSE*>
    END
  END FulcrumName;

PROCEDURE FormatNameArcsOnly(p : Arc; fieldPfx := "") : TEXT =
  VAR
    res := "";
  BEGIN
    WHILE p # NIL DO
      TYPECASE p OF
        NameArc(q) =>
        IF Text.Length(res) > 0 THEN res := "_" & res END;
        res := q.nm & res;
        IF q.field THEN
          res := "_" & fieldPfx & res
        END;
        (*Debug.Out("NameArc q.nm=" & q.nm & " res="& res );*)
        IF Text.Length(res) > 0 AND  Text.GetChar(res, 0) = '/' THEN
          res := Text.Sub(res,1);
          (*Debug.Out("NameArc return " & res);*)
          RETURN res
        END
      ELSE
        (* skip *)
      END;
      p := p.up;
    END;
    RETURN res
  END FormatNameArcsOnly;

PROCEDURE FormatArrayArcsOnly(p : Arc) : TEXT =
  VAR
    res := "";
  BEGIN
    WHILE p # NIL DO
      TYPECASE p OF
        ArrayArc(q) => res := F("[%s]",Int(q.sz)) & res;
      ELSE
        (* skip *)
      END;
      p := p.up
    END;
    RETURN res
  END FormatArrayArcsOnly;

PROCEDURE ArraySizes(p : Arc) : CardSeq.T =
  VAR
    res := NEW(CardSeq.T).init();
  BEGIN
    WHILE p # NIL DO
      TYPECASE p OF
        ArrayArc(q) => res.addhi(q.sz)
      ELSE
        (* skip *)
      END;
      p := p.up
    END;
    RETURN res
  END ArraySizes;

VAR bigPow2 := NEW(BigIntSeq.T).init();
  
PROCEDURE BigPow2(n : CARDINAL) : BigInt.T =
  BEGIN
    WHILE n >= bigPow2.size() DO
      bigPow2.addhi(BigInt.Mul(bigPow2.get(bigPow2.size()-1),BigInt.New(2)))
    END;
    RETURN bigPow2.get(n)
  END BigPow2;

BEGIN
  bigPow2.addhi(BigInt.New(1)) (* 2^0 = 1 *)
END GenViewsSvFulcrum.
