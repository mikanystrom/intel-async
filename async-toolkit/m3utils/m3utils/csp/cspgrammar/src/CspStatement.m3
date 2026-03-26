(* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE CspStatement;
IMPORT CspStatementPublic;

IMPORT SchemeObject;
FROM SchemeUtils IMPORT List2, List3, List4, Cons;
IMPORT SchemeSymbol;
IMPORT CspStatementSeq;
IMPORT SchemePair;
IMPORT CspGuardedCommandSeq;
IMPORT CspSyntax;
FROM CspSyntax IMPORT Lisp;
IMPORT Pathname;
IMPORT SchemeString;
IMPORT SchemeInt;
IMPORT CspDeclarator;
IMPORT CspRange;
IMPORT CspExpression;
IMPORT Atom;
IMPORT CspStructDeclarator;
IMPORT CspStructDeclaratorSeq;

CONST Sym = SchemeSymbol.FromText;

REVEAL
  T = Public BRANDED Brand OBJECT END;

  DetRepetition = Repetition BRANDED Brand & " DetRepetition" OBJECT
  OVERRIDES
    lisp := DetRepetitionLisp;
  END;

  DetSelection = Selection BRANDED Brand & " DetSelection" OBJECT
  OVERRIDES
    lisp := DetSelectionLisp;
  END;

  NondetRepetition = Repetition BRANDED Brand & " NondetRepetition" OBJECT
  OVERRIDES
    lisp := NondetRepetitionLisp;
  END;

  NondetSelection = Selection BRANDED Brand & " NondetSelection" OBJECT
  OVERRIDES
    lisp := NondetSelectionLisp;
  END;

  Parallel = Compound BRANDED Brand & " Parallel" OBJECT
  OVERRIDES
    lisp := ParallelLisp;
  END;

  Sequential = Compound BRANDED Brand & " Sequential" OBJECT
  OVERRIDES
    lisp := SequentialLisp;
  END;

  Skip = T BRANDED Brand & " Skip" OBJECT
  OVERRIDES
    lisp := SkipLisp;
  END;

TYPE
  PubAssignment = T OBJECT
    lhs, rhs : Expr;
  END;

REVEAL
  Assignment = PubAssignment BRANDED Brand & " Assignment" OBJECT
  OVERRIDES
    lisp := AssignmentLisp;
  END;

TYPE
  PubAssignOperate = T OBJECT
    lhs, rhs : Expr;
    op       : CspExpression.BinaryOp;
  END;

REVEAL
  AssignOperate = PubAssignOperate BRANDED Brand & " AssignOperate" OBJECT
  OVERRIDES
    lisp := AssignOperateLisp;
  END;

TYPE  
  PubSend = T OBJECT
    chan, val : Expr;
  END;

REVEAL
  Send = PubSend  BRANDED Brand & " Send" OBJECT
  OVERRIDES
    lisp := SendLisp;
  END;

TYPE  
  PubRecv = T OBJECT
    chan, val : Expr;
  END;

REVEAL
  Recv = PubRecv  BRANDED Brand & " Recv" OBJECT
  OVERRIDES
    lisp := RecvLisp;
  END;

TYPE  
  PubVar = T OBJECT
    decl : CspDeclarator.T;
  END;

REVEAL
  Var = PubVar  BRANDED Brand & " Var" OBJECT
  OVERRIDES
    lisp := VarLisp;
  END;

TYPE
  PubStructure = T OBJECT 
    name  : Atom.T;
    decls : CspStructDeclaratorSeq.T;
  END;

REVEAL
  Structure = PubStructure BRANDED Brand & " Structure" OBJECT
  OVERRIDES
    lisp := StructureLisp;
  END;

TYPE  
  PubExpression = T OBJECT
    expr : Expr;
  END;

REVEAL
  Expression = PubExpression  BRANDED Brand & " Expression" OBJECT
  OVERRIDES
    lisp := ExpressionLisp;
  END;

TYPE
  PubError = T OBJECT
    fn : Pathname.T;
    lno, cno : CARDINAL;
  END;

REVEAL
  Error = PubError BRANDED Brand & " Error" OBJECT
  OVERRIDES
    lisp := ErrorLisp;
  END;

PROCEDURE ErrorLisp(self : Error) : SchemeObject.T =
  BEGIN
    RETURN List4(Sym("error"),
                 SchemeString.FromText(self.fn),
                 SchemeInt.FromI(self.lno),
                 SchemeInt.FromI(self.cno))
  END ErrorLisp;
  
PROCEDURE AssignmentLisp(self : Assignment) : SchemeObject.T =
  BEGIN
    RETURN List3(Sym("assign"), Lisp(self.lhs), Lisp(self.rhs))
  END AssignmentLisp;
  
PROCEDURE AssignOperateLisp(self : AssignOperate) : SchemeObject.T =
  BEGIN
    RETURN List4(Sym("assign-operate"),
                 Sym(CspExpression.BinMap[self.op]),
                 Lisp(self.lhs),
                 Lisp(self.rhs))
  END AssignOperateLisp;
  
PROCEDURE ExpressionLisp(self : Expression) : SchemeObject.T =
  BEGIN
    RETURN List2(Sym("eval"), Lisp(self.expr))
  END ExpressionLisp;
  
PROCEDURE VarLisp(self : Var) : SchemeObject.T =
  BEGIN
    RETURN List2(Sym("var1"),
                 CspDeclarator.Lisp(self.decl))
  END VarLisp;

PROCEDURE StructureLisp(t : Structure) : SchemeObject.T =
  VAR
    p : SchemePair.T := NIL;
  BEGIN
    FOR i := t.decls.size() - 1 TO 0 BY -1 DO
      p := Cons(CspStructDeclarator.Lisp(t.decls.get(i)), p)
    END;
    p := Cons(t.name, p);
    p := Cons(Sym("structdecl"), p);
    RETURN p
  END StructureLisp;

PROCEDURE RecvLisp(self : Recv) : SchemeObject.T =
  BEGIN
    RETURN List3(Sym("recv"), Lisp(self.chan), Lisp(self.val))
  END RecvLisp;
  
PROCEDURE SendLisp(self : Send) : SchemeObject.T =
  BEGIN
    RETURN List3(Sym("send"), Lisp(self.chan), Lisp(self.val))
  END SendLisp;
  
PROCEDURE SkipLisp(<*UNUSED*>self : Skip) : SchemeObject.T =
  BEGIN
    RETURN Sym("skip")
  END SkipLisp;

PROCEDURE StmtSeqLisp(seq : CspStatementSeq.T) : SchemePair.T =
  VAR
    p : SchemePair.T := NIL;
  BEGIN
    FOR i := seq.size() - 1 TO 0 BY -1 DO
      p := Cons(Lisp(seq.get(i)), p)
    END;
    RETURN p
  END StmtSeqLisp;
  
PROCEDURE SequentialLisp(self : Sequential) : SchemeObject.T =
  BEGIN
    RETURN Cons(Sym("sequence"), StmtSeqLisp(self.stmts))
  END SequentialLisp;
  
PROCEDURE ParallelLisp(self : Parallel) : SchemeObject.T =
  BEGIN
    RETURN Cons(Sym("parallel"), StmtSeqLisp(self.stmts))
  END ParallelLisp;

PROCEDURE GuardedCommandSeqLisp(gcs : CspGuardedCommandSeq.T) : SchemePair.T =
  VAR
    p : SchemePair.T := NIL;
  BEGIN
    FOR i := gcs.size() - 1 TO 0 BY -1 DO
      WITH gc = gcs.get(i) DO
        p := Cons(List2(Lisp(gc.guard), Lisp(gc.command)), p)
      END
    END;
    RETURN p
  END GuardedCommandSeqLisp;
   
PROCEDURE NondetSelectionLisp(self : NondetSelection) : SchemeObject.T =
  BEGIN
    RETURN Cons(Sym("nondet-if"), GuardedCommandSeqLisp(self.gcs))
  END NondetSelectionLisp;
  
PROCEDURE NondetRepetitionLisp(self : NondetRepetition) : SchemeObject.T =
  BEGIN
    RETURN Cons(Sym("nondet-do"), GuardedCommandSeqLisp(self.gcs))
  END NondetRepetitionLisp;
  
PROCEDURE DetSelectionLisp(self : DetSelection) : SchemeObject.T =
  BEGIN
    RETURN Cons(Sym("if"), GuardedCommandSeqLisp(self.gcs))
  END DetSelectionLisp;
  
PROCEDURE DetRepetitionLisp(self : DetRepetition) : SchemeObject.T =
  BEGIN
    RETURN Cons(Sym("do"), GuardedCommandSeqLisp(self.gcs))
  END DetRepetitionLisp;

TYPE
  PubComment = T OBJECT
    string : TEXT;
  END;

REVEAL
  Comment = PubComment BRANDED Brand & " Comment" OBJECT
  OVERRIDES
    lisp := CommentLisp;
  END;
  
PROCEDURE CommentLisp(self : Comment) : SchemeObject.T =
  BEGIN
    RETURN List2(Sym("comment"),  SchemeString.FromText(self.string))
  END CommentLisp;

REVEAL
  SequentialLoop = Loop BRANDED Brand & " SequentialLoop" OBJECT
  OVERRIDES
    lisp := SequentialLoopLisp;
  END;

  ParallelLoop = Loop BRANDED Brand & " ParallelLoop" OBJECT
  OVERRIDES
    lisp := ParallelLoopLisp;
  END;

PROCEDURE SequentialLoopLisp(loop : SequentialLoop) : SchemeObject.T =
  BEGIN
    RETURN List4(Sym("sequential-loop"),
                 loop.dummy,
                 CspRange.Lisp(loop.range),
                 loop.stmt.lisp())
  END SequentialLoopLisp;
  
PROCEDURE ParallelLoopLisp(loop : ParallelLoop) : SchemeObject.T =
  BEGIN
    RETURN List4(Sym("parallel-loop"),
                 loop.dummy,
                 CspRange.Lisp(loop.range),
                 loop.stmt.lisp())
  END ParallelLoopLisp;
  
BEGIN END CspStatement.
