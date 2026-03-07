(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

(* BDDPrims.m3 -- BDD primitives for mscheme *)

MODULE BDDPrims;
IMPORT SchemePrimitive, SchemeProcedure, Scheme;
IMPORT SchemeString, SchemeBoolean, SchemeLongReal;
IMPORT SchemeUtils, Atom;
IMPORT BDD, BDDImpl;
IMPORT SopBDD, SopBDDRep;
FROM SchemeUtils IMPORT First, Second, Third;
FROM SchemeBoolean IMPORT True, False;
FROM Scheme IMPORT Object, E;

(* All BDD.T values are opaque REFANY, which Scheme can hold as objects *)

PROCEDURE CheckBDD(x : Object) : BDD.T RAISES { E } =
  BEGIN
    IF x = NIL OR NOT ISTYPE(x, BDD.T) THEN
      RAISE E("expected a BDD, got: " & SchemeUtils.Stringify(x))
    END;
    RETURN NARROW(x, BDD.T)
  END CheckBDD;

(* (bdd-true) => BDD constant true *)
PROCEDURE BDDTrueApply(<*UNUSED*>p : SchemeProcedure.T;
                       <*UNUSED*>interp : Scheme.T;
                       <*UNUSED*>args : Object) : Object =
  BEGIN RETURN BDD.True() END BDDTrueApply;

(* (bdd-false) => BDD constant false *)
PROCEDURE BDDFalseApply(<*UNUSED*>p : SchemeProcedure.T;
                        <*UNUSED*>interp : Scheme.T;
                        <*UNUSED*>args : Object) : Object =
  BEGIN RETURN BDD.False() END BDDFalseApply;

(* (bdd-var name) => new BDD variable with given name *)
PROCEDURE BDDVarApply(<*UNUSED*>p : SchemeProcedure.T;
                      <*UNUSED*>interp : Scheme.T;
                                args : Object) : Object RAISES { E } =
  VAR name : TEXT;
  BEGIN
    WITH x = First(args) DO
      IF ISTYPE(x, SchemeString.T) THEN
        name := SchemeString.ToText(x)
      ELSIF ISTYPE(x, Atom.T) THEN
        name := Atom.ToText(NARROW(x, Atom.T))
      ELSE
        RAISE E("bdd-var: expected string or symbol name")
      END
    END;
    RETURN BDD.New(name)
  END BDDVarApply;

(* (bdd-not a) => NOT a *)
PROCEDURE BDDNotApply(<*UNUSED*>p : SchemeProcedure.T;
                      <*UNUSED*>interp : Scheme.T;
                                args : Object) : Object RAISES { E } =
  BEGIN
    RETURN BDD.Not(CheckBDD(First(args)))
  END BDDNotApply;

(* (bdd-and a b) => a AND b *)
PROCEDURE BDDAndApply(<*UNUSED*>p : SchemeProcedure.T;
                      <*UNUSED*>interp : Scheme.T;
                                args : Object) : Object RAISES { E } =
  BEGIN
    RETURN BDD.And(CheckBDD(First(args)), CheckBDD(Second(args)))
  END BDDAndApply;

(* (bdd-or a b) => a OR b *)
PROCEDURE BDDOrApply(<*UNUSED*>p : SchemeProcedure.T;
                     <*UNUSED*>interp : Scheme.T;
                               args : Object) : Object RAISES { E } =
  BEGIN
    RETURN BDD.Or(CheckBDD(First(args)), CheckBDD(Second(args)))
  END BDDOrApply;

(* (bdd-xor a b) => a XOR b *)
PROCEDURE BDDXorApply(<*UNUSED*>p : SchemeProcedure.T;
                      <*UNUSED*>interp : Scheme.T;
                                args : Object) : Object RAISES { E } =
  BEGIN
    RETURN BDD.Xor(CheckBDD(First(args)), CheckBDD(Second(args)))
  END BDDXorApply;

(* (bdd-implies a b) => a => b *)
PROCEDURE BDDImpliesApply(<*UNUSED*>p : SchemeProcedure.T;
                          <*UNUSED*>interp : Scheme.T;
                                    args : Object) : Object RAISES { E } =
  BEGIN
    RETURN BDD.Implies(CheckBDD(First(args)), CheckBDD(Second(args)))
  END BDDImpliesApply;

(* (bdd-equiv a b) => a <=> b *)
PROCEDURE BDDEquivApply(<*UNUSED*>p : SchemeProcedure.T;
                        <*UNUSED*>interp : Scheme.T;
                                  args : Object) : Object RAISES { E } =
  BEGIN
    RETURN BDD.Equivalent(CheckBDD(First(args)), CheckBDD(Second(args)))
  END BDDEquivApply;

(* (bdd-ite c t e) => if c then t else e *)
PROCEDURE BDDIteApply(<*UNUSED*>p : SchemeProcedure.T;
                      <*UNUSED*>interp : Scheme.T;
                                args : Object) : Object RAISES { E } =
  VAR c, t, e : BDD.T;
  BEGIN
    c := CheckBDD(First(args));
    t := CheckBDD(Second(args));
    e := CheckBDD(Third(args));
    (* ITE(c,t,e) = (c AND t) OR (NOT c AND e) *)
    RETURN BDD.Or(BDD.And(c, t), BDD.And(BDD.Not(c), e))
  END BDDIteApply;

(* (bdd-restrict b v val) => cofactor: set v to val (0 or 1) in b *)
PROCEDURE BDDRestrictApply(<*UNUSED*>p : SchemeProcedure.T;
                           <*UNUSED*>interp : Scheme.T;
                                     args : Object) : Object RAISES { E } =
  VAR b, v : BDD.T;
  BEGIN
    b := CheckBDD(First(args));
    v := CheckBDD(Second(args));
    WITH valObj = Third(args) DO
      IF SchemeBoolean.TruthO(valObj) THEN
        RETURN BDD.MakeTrue(b, v)
      ELSE
        RETURN BDD.MakeFalse(b, v)
      END
    END
  END BDDRestrictApply;

(* (bdd-format b) => string representation *)
PROCEDURE BDDFormatApply(<*UNUSED*>p : SchemeProcedure.T;
                         <*UNUSED*>interp : Scheme.T;
                                   args : Object) : Object RAISES { E } =
  BEGIN
    RETURN SchemeString.FromText(BDD.Format(CheckBDD(First(args))))
  END BDDFormatApply;

(* (bdd-size b) => node count *)
PROCEDURE BDDSizeApply(<*UNUSED*>p : SchemeProcedure.T;
                       <*UNUSED*>interp : Scheme.T;
                                 args : Object) : Object RAISES { E } =
  BEGIN
    RETURN SchemeLongReal.FromLR(FLOAT(BDD.Size(CheckBDD(First(args))), LONGREAL))
  END BDDSizeApply;

(* (bdd-equal? a b) => boolean equality *)
PROCEDURE BDDEqualApply(<*UNUSED*>p : SchemeProcedure.T;
                        <*UNUSED*>interp : Scheme.T;
                                  args : Object) : Object RAISES { E } =
  BEGIN
    IF BDD.Equal(CheckBDD(First(args)), CheckBDD(Second(args))) THEN
      RETURN True()
    ELSE
      RETURN False()
    END
  END BDDEqualApply;

(* (bdd-true? b) => is b the constant TRUE? *)
PROCEDURE BDDIsTrueApply(<*UNUSED*>p : SchemeProcedure.T;
                         <*UNUSED*>interp : Scheme.T;
                                   args : Object) : Object RAISES { E } =
  BEGIN
    IF BDD.Equal(CheckBDD(First(args)), BDD.True()) THEN
      RETURN True()
    ELSE
      RETURN False()
    END
  END BDDIsTrueApply;

(* (bdd-false? b) => is b the constant FALSE? *)
PROCEDURE BDDIsFalseApply(<*UNUSED*>p : SchemeProcedure.T;
                          <*UNUSED*>interp : Scheme.T;
                                    args : Object) : Object RAISES { E } =
  BEGIN
    IF BDD.Equal(CheckBDD(First(args)), BDD.False()) THEN
      RETURN True()
    ELSE
      RETURN False()
    END
  END BDDIsFalseApply;

(* (bdd-const? b) => is b TRUE or FALSE? *)
PROCEDURE BDDIsConstApply(<*UNUSED*>p : SchemeProcedure.T;
                          <*UNUSED*>interp : Scheme.T;
                                    args : Object) : Object RAISES { E } =
  VAR b : BDD.T;
  BEGIN
    b := CheckBDD(First(args));
    IF BDD.Equal(b, BDD.True()) OR BDD.Equal(b, BDD.False()) THEN
      RETURN True()
    ELSE
      RETURN False()
    END
  END BDDIsConstApply;

(* (bdd-high b) => the high (then) child *)
PROCEDURE BDDHighApply(<*UNUSED*>p : SchemeProcedure.T;
                       <*UNUSED*>interp : Scheme.T;
                                 args : Object) : Object RAISES { E } =
  BEGIN
    RETURN BDDImpl.Left(CheckBDD(First(args)))
  END BDDHighApply;

(* (bdd-low b) => the low (else) child *)
PROCEDURE BDDLowApply(<*UNUSED*>p : SchemeProcedure.T;
                      <*UNUSED*>interp : Scheme.T;
                                args : Object) : Object RAISES { E } =
  BEGIN
    RETURN BDDImpl.Right(CheckBDD(First(args)))
  END BDDLowApply;

(* (bdd-node-var b) => the decision variable of this node *)
PROCEDURE BDDNodeVarApply(<*UNUSED*>p : SchemeProcedure.T;
                          <*UNUSED*>interp : Scheme.T;
                                    args : Object) : Object RAISES { E } =
  BEGIN
    RETURN BDDImpl.NodeVar(CheckBDD(First(args)))
  END BDDNodeVarApply;

(* (bdd-name b) => the name string of a variable, or #f *)
PROCEDURE BDDNameApply(<*UNUSED*>p : SchemeProcedure.T;
                       <*UNUSED*>interp : Scheme.T;
                                 args : Object) : Object RAISES { E } =
  VAR name : TEXT;
  BEGIN
    name := BDD.Format(CheckBDD(First(args)));
    IF name = NIL THEN RETURN False() END;
    RETURN SchemeString.FromText(name)
  END BDDNameApply;

(* (bdd-id b) => integer id of the node (variable index, NOT unique) *)
PROCEDURE BDDIdApply(<*UNUSED*>p : SchemeProcedure.T;
                     <*UNUSED*>interp : Scheme.T;
                               args : Object) : Object RAISES { E } =
  BEGIN
    RETURN SchemeLongReal.FromLR(FLOAT(BDD.GetId(CheckBDD(First(args))), LONGREAL))
  END BDDIdApply;

(* (bdd-hash b) => unique hash tag of the BDD node (monotonic counter) *)
PROCEDURE BDDHashApply(<*UNUSED*>p : SchemeProcedure.T;
                       <*UNUSED*>interp : Scheme.T;
                                 args : Object) : Object RAISES { E } =
  BEGIN
    RETURN SchemeLongReal.FromI(BDD.Hash(CheckBDD(First(args))))
  END BDDHashApply;

(* (bdd->sop b) => minimized SOP string *)
PROCEDURE BDDToSopApply(<*UNUSED*>p : SchemeProcedure.T;
                        <*UNUSED*>interp : Scheme.T;
                                  args : Object) : Object RAISES { E } =
  VAR
    b   : BDD.T;
    sop : SopBDD.T;
    tr  : BDD.T;
  BEGIN
    b := CheckBDD(First(args));
    tr := BDD.True();
    sop := SopBDD.ConvertBool(b).invariantSimplify(tr, tr, tr);
    RETURN SchemeString.FromText(sop.format(NIL))
  END BDDToSopApply;

(* (bdd->sop-raw b) => unminimized SOP string *)
PROCEDURE BDDToSopRawApply(<*UNUSED*>p : SchemeProcedure.T;
                           <*UNUSED*>interp : Scheme.T;
                                     args : Object) : Object RAISES { E } =
  VAR
    b   : BDD.T;
    sop : SopBDD.T;
  BEGIN
    b := CheckBDD(First(args));
    sop := SopBDD.ConvertBool(b);
    RETURN SchemeString.FromText(sop.format(NIL))
  END BDDToSopRawApply;

(* (bdd->sop-terms b) => number of product terms after minimization *)
PROCEDURE BDDToSopTermsApply(<*UNUSED*>p : SchemeProcedure.T;
                             <*UNUSED*>interp : Scheme.T;
                                       args : Object) : Object RAISES { E } =
  VAR
    b   : BDD.T;
    sop : SopBDD.T;
    tr  : BDD.T;
  BEGIN
    b := CheckBDD(First(args));
    tr := BDD.True();
    sop := SopBDD.ConvertBool(b).invariantSimplify(tr, tr, tr);
    RETURN SchemeLongReal.FromLR(
             FLOAT(NUMBER(NARROW(sop, SopBDDRep.Private).rep^), LONGREAL))
  END BDDToSopTermsApply;

(**********************************************************************)

PROCEDURE Install(prims : SchemePrimitive.ExtDefiner) : SchemePrimitive.ExtDefiner =
  BEGIN
    prims.addPrim("bdd-true", NEW(SchemeProcedure.T,
                                   apply := BDDTrueApply),
                  0, 0);
    prims.addPrim("bdd-false", NEW(SchemeProcedure.T,
                                    apply := BDDFalseApply),
                  0, 0);
    prims.addPrim("bdd-var", NEW(SchemeProcedure.T,
                                  apply := BDDVarApply),
                  1, 1);
    prims.addPrim("bdd-not", NEW(SchemeProcedure.T,
                                  apply := BDDNotApply),
                  1, 1);
    prims.addPrim("bdd-and", NEW(SchemeProcedure.T,
                                  apply := BDDAndApply),
                  2, 2);
    prims.addPrim("bdd-or", NEW(SchemeProcedure.T,
                                 apply := BDDOrApply),
                  2, 2);
    prims.addPrim("bdd-xor", NEW(SchemeProcedure.T,
                                  apply := BDDXorApply),
                  2, 2);
    prims.addPrim("bdd-implies", NEW(SchemeProcedure.T,
                                      apply := BDDImpliesApply),
                  2, 2);
    prims.addPrim("bdd-equiv", NEW(SchemeProcedure.T,
                                    apply := BDDEquivApply),
                  2, 2);
    prims.addPrim("bdd-ite", NEW(SchemeProcedure.T,
                                  apply := BDDIteApply),
                  3, 3);
    prims.addPrim("bdd-restrict", NEW(SchemeProcedure.T,
                                       apply := BDDRestrictApply),
                  3, 3);
    prims.addPrim("bdd-format", NEW(SchemeProcedure.T,
                                     apply := BDDFormatApply),
                  1, 1);
    prims.addPrim("bdd-size", NEW(SchemeProcedure.T,
                                   apply := BDDSizeApply),
                  1, 1);
    prims.addPrim("bdd-equal?", NEW(SchemeProcedure.T,
                                     apply := BDDEqualApply),
                  2, 2);
    prims.addPrim("bdd-true?", NEW(SchemeProcedure.T,
                                    apply := BDDIsTrueApply),
                  1, 1);
    prims.addPrim("bdd-false?", NEW(SchemeProcedure.T,
                                     apply := BDDIsFalseApply),
                  1, 1);
    prims.addPrim("bdd-const?", NEW(SchemeProcedure.T,
                                     apply := BDDIsConstApply),
                  1, 1);
    prims.addPrim("bdd-high", NEW(SchemeProcedure.T,
                                   apply := BDDHighApply),
                  1, 1);
    prims.addPrim("bdd-low", NEW(SchemeProcedure.T,
                                  apply := BDDLowApply),
                  1, 1);
    prims.addPrim("bdd-node-var", NEW(SchemeProcedure.T,
                                       apply := BDDNodeVarApply),
                  1, 1);
    prims.addPrim("bdd-name", NEW(SchemeProcedure.T,
                                   apply := BDDNameApply),
                  1, 1);
    prims.addPrim("bdd-id", NEW(SchemeProcedure.T,
                                 apply := BDDIdApply),
                  1, 1);
    prims.addPrim("bdd-hash", NEW(SchemeProcedure.T,
                                   apply := BDDHashApply),
                  1, 1);
    prims.addPrim("bdd->sop", NEW(SchemeProcedure.T,
                                   apply := BDDToSopApply),
                  1, 1);
    prims.addPrim("bdd->sop-raw", NEW(SchemeProcedure.T,
                                       apply := BDDToSopRawApply),
                  1, 1);
    prims.addPrim("bdd->sop-terms", NEW(SchemeProcedure.T,
                                         apply := BDDToSopTermsApply),
                  1, 1);
    RETURN prims
  END Install;

BEGIN
END BDDPrims.
