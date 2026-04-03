(* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. *)
(* SPDX-License-Identifier: Apache-2.0 *)

GENERIC MODULE GenViews(Tgt, TgtNaming, TgtGenerators, TgtConstants);

IMPORT Debug; 
FROM Fmt IMPORT F;
IMPORT RTName;
IMPORT RdlComponentDef, RdlComponentDefClass;
IMPORT RdlComponentDefType, RdlComponentDefElem;
IMPORT RdlArray, BigInt;
IMPORT RdlComponentInstElemList;
IMPORT RegField, RegFieldSeq;
IMPORT RegAddrmap;
IMPORT RegReg;
IMPORT RdlComponentDefElemList;
IMPORT RegRegfile;
IMPORT Fmt;
IMPORT RegChild, RegChildSeq;
IMPORT RegComponent;
IMPORT OSError, Wr, AL;
IMPORT Thread;
IMPORT Pathname;
IMPORT FS;
IMPORT DecoratedComponentDef;
IMPORT RegFieldArraySort;
IMPORT ParseError;
IMPORT RegFieldAccess, IntelAccessType, IntelAccessTypeLookup;
IMPORT RdlPropertyRvalueKeyword;
FROM RegProperty IMPORT Unquote;

CONST Brand = "GenViews(" & Tgt.Brand & ")";
      
REVEAL
  T = Tgt.Gen BRANDED Brand OBJECT
  OVERRIDES
    decorate := Decorate;
    gen      := DoIt;
  END;

  <*FATAL Thread.Alerted*>

PROCEDURE ApplyFieldProperties(VAR f : RegField.T) : BOOLEAN
  RAISES { ParseError.E } =
  (* returns TRUE if field has access rules associated *)
  VAR
    gotRdlProps := FALSE;
    gotIntelProps := FALSE;
    str : TEXT;
  BEGIN
    f.reserved := FALSE;
    f.access := RegFieldAccess.Default;
    
    (* there are two ways of stating access rules:
       one way is using RDL standard hw, sw
       another way is using Intel AccessType annotation *)
    FOR i := FIRST(RegFieldAccess.Master) TO LAST(RegFieldAccess.Master) DO
      (* look for stated property — try keyword first (raw RDL), then text (preprocessed) *)
      VAR kw : RdlPropertyRvalueKeyword.T;
      BEGIN
        WITH p = RegFieldAccess.MasterProperty[i] DO
          IF f.getRdlPredefKwProperty(p, kw) THEN
            gotRdlProps := TRUE;
            f.access[i] := RegFieldAccess.Parse(RdlPropertyRvalueKeyword.Names[kw])
          ELSIF f.getRdlPredefTextProperty(p, str) THEN
            gotRdlProps := TRUE;
            f.access[i] := RegFieldAccess.Parse(str)
          END
        END
      END
    END;

    IF f.getRdlTextProperty(IntelAccessType.UDPName, str) THEN
      WITH at = IntelAccessTypeLookup.Parse(Unquote(str)) DO
        gotIntelProps := TRUE;
        IF gotRdlProps THEN
          IF at.rdlAccess # f.access THEN
            RAISE ParseError.E("RDL / IntelAccessType mismatch")
          END;
          f.access := at.rdlAccess
        END
      END
    END;

    RETURN gotRdlProps OR gotIntelProps
  END ApplyFieldProperties;
      
PROCEDURE AllocFields(c  : RdlComponentDef.T;
                      hn : TEXT) : RegFieldSeq.T
  RAISES { ParseError.E } =
  VAR
    seq := NEW(RegFieldSeq.T).init();
    p : RdlComponentInstElemList.T;
    last : TEXT := "(NIL)";
  BEGIN
    TRY
    <*ASSERT c.type = RdlComponentDefType.T.field*>
    <*ASSERT c.id # NIL*> (* now ANONYMOUS-smth...? *)
    <*ASSERT c.anonInstElems # NIL*>
    p := c.anonInstElems.list;
    WHILE p # NIL DO
      VAR i := p.head;
          f := NEW(RegField.T,
                   name  := TgtNaming.FieldName,
                   props := c.list.propTab
          );
      BEGIN
        f.nm := i.id;
        last := f.nm;
        f.defVal := i.eq;

        IF NOT ApplyFieldProperties(f) THEN
          Debug.Warning("field " & hn & "->" & f.nm & " doesnt have access rules associated with it")
        END;
        
        IF i.array = NIL THEN
          f.width := 1
        ELSE
          TRY
            TYPECASE i.array OF
              RdlArray.Single(sing) =>
              f.width := BigInt.ToInteger(sing.n.x)
            |
              RdlArray.Range(rang) =>
              WITH hi = BigInt.Max(rang.to.x,rang.frm.x),
                   lo = BigInt.Min(rang.to.x,rang.frm.x) DO
                f.width := BigInt.ToInteger(hi) - BigInt.ToInteger(lo) + 1;
                f.lsb := BigInt.ToInteger(lo)
              END
            ELSE
              <*ASSERT FALSE*>
            END
          EXCEPT
            BigInt.OutOfRange => Debug.Error("Array is too big!")
          END
        END;
        seq.addhi(f)
      END;
      p := p.tail
    END;
    RETURN seq
  EXCEPT
    ParseError.E(txt) =>
    RAISE ParseError.E("GenViews.AllocFields : processing field " & last & " : " & txt)
  END
  END AllocFields;
  
PROCEDURE AllocAddrmap(c         : RdlComponentDef.T; hn : TEXT) : RegAddrmap.T
  RAISES { ParseError.E } =
  VAR
    props := c.list.propTab;
    defs  := c.list.defTab;
    am := NEW(RegAddrmap.T,
              props    := props,
              intfName := TgtNaming.MapIntfName,
              typeName := TgtNaming.MapTypename,
              generate := TgtGenerators.GenAddrmap,
              children := NEW(RegChildSeq.T).init());
    p : RdlComponentDefElemList.T := c.list.lst;
  BEGIN
    <*ASSERT c.id # NIL*>
    am.nm := c.id;
    <*ASSERT c.anonInstElems = NIL*> (* no immediate instances *)
    TRY
    WHILE p # NIL DO
      WITH cd = p.head DO
        TYPECASE cd OF
          RdlComponentDefElem.ComponentInst(ci) =>
          <*ASSERT ci.componentInst.alias = NIL*>
          <*ASSERT ci.componentInst.id # NIL*>
          VAR
            q := ci.componentInst.list;
            z : REFANY;
            def := defs.lookup(ci.componentInst.id);
          BEGIN
            IF def = NIL THEN
              Debug.Error("Couldnt find in defs : " & ci.componentInst.id)
            END;
            IF NOT ISTYPE(def, DecoratedComponentDef.T) THEN
              def := Decorate(NIL, def, defs.getPath(ci.componentInst.id,
                                                     TgtConstants.PathSep),
                              hn & "->" & c.id);
              defs.update(ci.componentInst.id, def)
            END;

            z := NARROW(def,DecoratedComponentDef.T).comp;
              
            WHILE q # NIL DO
              WITH elem = q.head,
                   ne = NEW(RegChild.T,
                            comp  := z,
                            nm    := elem.id,
                            array := elem.array,
                            at    := elem.at) DO
                IF elem.inc # NIL THEN
                  ne.stride := elem.inc
                ELSE
                  ne.stride := NIL
                END;
                
                am.children.addhi(ne)
              END;
              q := q.tail
            END
          END
        ELSE
          (*skip*)
        END
      END;
      p := p.tail
    END;
    RETURN am
    EXCEPT
      ParseError.E(txt) => RAISE ParseError.E("processing addrmap " & am.nm & " : " & txt)
    END
  END AllocAddrmap;

PROCEDURE Decorate(<*UNUSED*>t : T;
                   def         : RdlComponentDef.T;
                   path        : TEXT;
                   hn          : TEXT) : DecoratedComponentDef.T
  RAISES { ParseError.E } =
  VAR
    comp : RegComponent.T;
  BEGIN
    CASE def.type OF
      RdlComponentDefType.T.addrmap =>
      comp := AllocAddrmap(def, hn)
    |
      RdlComponentDefType.T.regfile =>
      comp := AllocRegfile(def, hn)
    |
      RdlComponentDefType.T.reg =>
      comp := AllocReg(def, hn)
    |
      RdlComponentDefType.T.field =>
      comp := NIL
    |
      RdlComponentDefType.T.signal =>
      comp := NIL
    END;
    IF comp # NIL THEN
      comp.path := path
    END;
    RETURN NEW(DecoratedComponentDef.T).init(def, comp)
  END Decorate;

PROCEDURE AllocRegfile(c         : RdlComponentDef.T;
                       hn        : TEXT ) : RegRegfile.T
  RAISES { ParseError.E } =
  VAR
    props := c.list.propTab;
    defs  := c.list.defTab;
    regf := NEW(RegRegfile.T,
                nm       := c.id,
                props    := props,
                typeName := TgtNaming.RegfileTypename,
                generate := TgtGenerators.GenRegfile,
                children := NEW(RegChildSeq.T).init());
    p : RdlComponentDefElemList.T := c.list.lst;
  BEGIN
    <*ASSERT c.anonInstElems = NIL*> (* no immediate instances *)
    TRY
    WHILE p # NIL DO
      WITH cd = p.head DO
        TYPECASE cd OF
          RdlComponentDefElem.ComponentInst(ci) =>
          <*ASSERT ci.componentInst.alias = NIL*>
          <*ASSERT ci.componentInst.id # NIL*>
          VAR
            q := ci.componentInst.list;
            z : REFANY;
            def := defs.lookup(ci.componentInst.id);
          BEGIN
            IF def = NIL THEN
              Debug.Error(F("Couldnt find in defs : %s",ci.componentInst.id),FALSE);
              defs.dump();
              Debug.Error("QUIT")
            END;
            IF NOT ISTYPE(def, DecoratedComponentDef.T) THEN
              def := Decorate(NIL, def, defs.getPath(ci.componentInst.id,
                                                     TgtConstants.PathSep),
                              hn & "->" & c.id);
              defs.update(ci.componentInst.id, def)
            END;
            z := NARROW(def,DecoratedComponentDef.T).comp;
            WHILE q # NIL DO
              WITH elem = q.head,
                   regDef = NEW(RegChild.T,
                                comp   := z,
                                nm     := elem.id,
                                array  := elem.array,
                                at     := elem.at,
                                stride := elem.inc,
                                mod    := elem.mod) DO
                <*ASSERT elem.eq = NIL*>
                regf.children.addhi(regDef)
              END;
              q := q.tail
            END
          END
         ELSE
           (*skip*)
         END
      END;
      p := p.tail
    END;
    RETURN regf
    EXCEPT
      ParseError.E(txt) => RAISE ParseError.E("processing regfile " & c.id & " : " & txt)
    END
  END AllocRegfile;

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

PROCEDURE AllocReg(c     : RdlComponentDef.T;
                   hn    : TEXT) : RegReg.T
  RAISES { ParseError.E } =
  VAR
    props := c.list.propTab;
    reg := NEW(RegReg.T,
               props    := props,
               generate := TgtGenerators.GenReg,
               typeName := TgtNaming.RegTypename);
    fields := NEW(RegFieldSeq.T).init();
    p : RdlComponentDefElemList.T := c.list.lst;
  BEGIN
    <*ASSERT c.anonInstElems = NIL*> (* no immediate instances *)
    reg.nm := c.id;
    TRY
    WHILE p # NIL DO
      WITH cd = p.head DO
        TYPECASE cd OF
          RdlComponentDefElem.ComponentDef(cd) =>
          IF cd.componentDef.type # RdlComponentDefType.T.field THEN
            RAISE ParseError.E("Unexpected component in reg " & c.id & " : " &
              RdlComponentDefType.Names[cd.componentDef.type])
          END;
          fields := RegFieldSeq.Cat(fields, AllocFields(cd.componentDef,
                                                        hn & "->" & c.id))
        |
          RdlComponentDefElem.PropertyAssign =>
        |
          RdlComponentDefElem.EnumDef =>
        |
          RdlComponentDefElem.ComponentInst(ci) =>
          WITH comp = c.list.defTab.lookup(ci.componentInst.id) DO
            IF comp.type # RdlComponentDefType.T.field THEN
              RAISE ParseError.E("object of type RdlComponentDefElem.ComponentInst : "&
                ci.componentInst.id & " / " & RdlComponentDefType.Names[comp.type] )
            END
          END
        ELSE
          Debug.Error("object of type " & RTName.GetByTC(TYPECODE(cd)) &
            " unexpected in reg")
        END
      END;
      p := p.tail
    END;
    SortFieldsIfAllSpecified(fields);
    reg.fields := fields;
    RETURN reg
    EXCEPT
      ParseError.E(txt) => RAISE ParseError.E("processing reg " & reg.nm & " : " & txt)
    END
  END AllocReg;

PROCEDURE DoIt(t : T; tgtmap : RegAddrmap.T; outDir : Pathname.T) =
  VAR
    r : Compiler := NEW(Tgt.T).init(tgtmap);
  BEGIN
    r.gv := t;
    FOR i := FIRST(Tgt.Phase) TO LAST(Tgt.Phase) DO
      TRY
        TRY
          EVAL FS.Iterate(outDir)
        EXCEPT
          OSError.E(x) => Debug.Error(F("Problem opening directory \"%s\" : OSError.E : %s", outDir, AL.Format(x)))
        END;
        
        r.write(outDir, i)
      EXCEPT
        OSError.E(x) =>
        Debug.Error("Error in " &
          Tgt.PhaseNames[i] & " code generation : OSError.E : " & AL.Format(x))
      |
        Wr.Failure(x) =>
        Debug.Error("Error in " &
          Tgt.PhaseNames[i] & " code generation : Wr.Failure : " & AL.Format(x))
      END
    END
  END DoIt;
  
BEGIN END GenViews.
