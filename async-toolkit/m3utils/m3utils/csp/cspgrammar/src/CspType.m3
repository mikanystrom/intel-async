(* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE CspType;
IMPORT SchemeSymbol;
IMPORT SchemeObject;

FROM SchemeUtils IMPORT List2, List3, List5;

IMPORT SchemeBoolean;
IMPORT CspRange;
IMPORT CspDirection;
IMPORT SchemeInt;
IMPORT CspExpression;
IMPORT CspInterval;
IMPORT CspType;

CONST Sym = SchemeSymbol.FromText;

TYPE
  PubInteger = MayBeConst OBJECT
    isSigned          : BOOLEAN;
    dw                : CspExpression.T;
    hasInterval       : BOOLEAN;
    interval          : CspInterval.T;
  END; 

REVEAL
  T = Public BRANDED Brand OBJECT
  END;

  Integer = PubInteger BRANDED CspType.Brand & " Integer" OBJECT
  OVERRIDES
    lisp := IntegerLisp;
  END;

  Array = PubArray BRANDED Brand & " Array" OBJECT
  OVERRIDES
    lisp := ArrayLisp;
  END;
  
  Channel = PubChannel BRANDED Brand & " Channel" OBJECT
  OVERRIDES
    lisp := ChannelLisp;
  END;
  
  Node = PubNode BRANDED Brand & " Node" OBJECT
  OVERRIDES
    lisp := NodeLisp;
  END;
  
  Structure = PubStructure BRANDED Brand & " Structure" OBJECT
  OVERRIDES
    lisp := StructureLisp;
  END;
  
  Boolean = MayBeConst BRANDED Brand & " Boolean" OBJECT
  OVERRIDES
    lisp := BooleanLisp;
  END;

  String = MayBeConst BRANDED Brand & " String" OBJECT
  OVERRIDES
    lisp := StringLisp;
  END;

PROCEDURE ArrayLisp(self : Array) : SchemeObject.T =
  BEGIN
    RETURN List3(Sym("array"),
                 CspRange.Lisp(self.range),
                 self.elemntType.lisp())
  END ArrayLisp;
  
PROCEDURE ChannelLisp(self : Channel) : SchemeObject.T =
  BEGIN
    RETURN List3(Sym("channeltype"),
                 self.numValues,
                 CspDirection.Names[self.dir]);
  END ChannelLisp;
  
PROCEDURE IntegerLisp(self : Integer) : SchemeObject.T =
  VAR
    lispInterval, dw : SchemeObject.T;
  BEGIN
    IF self.hasInterval THEN
      lispInterval := List2(self.interval.left, self.interval.right)
    ELSE
      lispInterval := NIL
    END;
    
    IF self.dw = NIL THEN
      dw := NIL
    ELSE
      dw := self.dw.lisp()
    END;
    
    RETURN List5(Sym("integer"),
                 SchemeBoolean.Truth(self.isConst),
                 SchemeBoolean.Truth(self.isSigned),
                 dw,
                 lispInterval)
  END IntegerLisp;
  
PROCEDURE NodeLisp(self : Node) : SchemeObject.T =
  BEGIN
    IF self.arrayed THEN
      RETURN List3(Sym("node-array"),
                   Sym(CspDirection.Names[self.direction]),
                   SchemeInt.FromI(self.width))
    ELSE
      RETURN List2(Sym("node"),
                   Sym(CspDirection.Names[self.direction]))
    END
  END NodeLisp;
  
PROCEDURE StructureLisp(self : Structure) : SchemeObject.T =
  BEGIN
    RETURN List3(Sym("structure"),
                 SchemeBoolean.Truth(self.isConst),
                 Sym(self.name))
  END StructureLisp;
  
PROCEDURE BooleanLisp(self : Boolean) : SchemeObject.T =
  BEGIN
    RETURN List2(Sym("boolean"), SchemeBoolean.Truth(self.isConst))
  END BooleanLisp;
  
PROCEDURE StringLisp(self : String) : SchemeObject.T =
  BEGIN
    RETURN List2(Sym("string"), SchemeBoolean.Truth(self.isConst))
  END StringLisp;

BEGIN END CspType.
