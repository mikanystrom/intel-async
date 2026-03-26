(* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE CspAst;

IMPORT CspExpression;
IMPORT CspExpressionSeq;
IMPORT CspStatement;
IMPORT CspGuardedCommand;
IMPORT CspGuardedCommandSeq;
IMPORT CspInterval;
IMPORT CspRange;
IMPORT CspType;
IMPORT CspDirection;
IMPORT Pathname;
IMPORT CspStatementSeq;
IMPORT CspDeclaratorSeq;
IMPORT CspStructDeclaratorSeq;
IMPORT CspStructMemberSeq;
IMPORT Mpz;
IMPORT Atom;
IMPORT CspDeclaration;
IMPORT CspDeclarator;
IMPORT CspStructDeclarator;

TYPE
  Expr           = CspExpression.T;
  ExprSeq        = CspExpressionSeq.T;
  Stmt           = CspStatement.T;
  StmtSeq        = CspStatementSeq.T;
  Decl           = CspDeclaration.T;   (* XXX *)
  DeclSeq        = CspDeclaratorSeq.T; (* XXX *)
  Type           = CspType.T;
  Range          = CspRange.T;
  Interval       = CspInterval.T;
  Direction      = CspDirection.T;
  
PROCEDURE AssignmentStmt(lhs, rhs : Expr) : Stmt;

PROCEDURE AssignOperateStmt(lhs, rhs : Expr; op : CspExpression.BinaryOp) : Stmt;

PROCEDURE DetRepetitionStmt(gcs : CspGuardedCommandSeq.T) : Stmt;

PROCEDURE DetSelectionStmt(gcs : CspGuardedCommandSeq.T) : Stmt;

PROCEDURE NondetRepetitionStmt(gcs : CspGuardedCommandSeq.T) : Stmt;

PROCEDURE NondetSelectionStmt(gcs : CspGuardedCommandSeq.T) : Stmt;

PROCEDURE ErrorStmt(fn : Pathname.T; lno, cno : CARDINAL) : Stmt;

PROCEDURE ParallelStmt(stmts : StmtSeq) : Stmt;

PROCEDURE SequentialStmt(stmts : StmtSeq) : Stmt;

PROCEDURE SkipStmt() : Stmt;

PROCEDURE SendStmt(chan : Expr; val : Expr) : Stmt;

PROCEDURE RecvStmt(chan : Expr; val : Expr) : Stmt;

PROCEDURE VarStmt(decl : CspDeclarator.T) : Stmt;

PROCEDURE ExpressionStmt(expr : Expr) : Stmt;

PROCEDURE CommentStmt(string : TEXT) : Stmt;

PROCEDURE SequentialLoop(dummy : Atom.T;
                         range : CspRange.T;
                         stmt  : Stmt) : Stmt;

PROCEDURE ParallelLoop(dummy : Atom.T;
                       range : CspRange.T;
                       stmt  : Stmt) : Stmt;

(**********************************************************************)

PROCEDURE GuardedCommand(guard : Expr; command : Stmt) : CspGuardedCommand.T;
  
(**********************************************************************)

(* literal expressions *)

PROCEDURE BooleanExpr(val : BOOLEAN) : Expr;

PROCEDURE ElseExpr() : Expr;

PROCEDURE IntegerExpr(val : Mpz.T) : Expr;

PROCEDURE StringExpr(val : TEXT) : Expr;

(* identifiers *)

PROCEDURE IdentifierExpr(id : Atom.T) : Expr;
  
(* compound expressions *)  

PROCEDURE BinExpr(op : CspExpression.BinaryOp; l, r : Expr) : Expr;

PROCEDURE UnaExpr(op : CspExpression.UnaryOp; x : Expr) : Expr;

PROCEDURE ArrayAccessExpr(arr, idx : Expr) : Expr;

PROCEDURE MemberAccessExpr(struct : Expr; member : Atom.T) : Expr;

PROCEDURE StructureAccessExpr(struct : Expr; member : Atom.T) : Expr;

PROCEDURE BitRangeExpr(bits, minx, maxx : Expr) : Expr;

PROCEDURE RecvExpr(chan : Expr) : Expr;

PROCEDURE PeekExpr(chan : Expr) : Expr;

PROCEDURE ProbeExpr(chan : Expr) : Expr;

PROCEDURE FunctionCallExpr(f : Expr; args : ExprSeq) : Expr;

PROCEDURE LoopExpr(dummy : Atom.T;
                   range : CspRange.T;
                   op    : CspExpression.BinaryOp;
                   x     : Expr) : Expr;

(**********************************************************************)

PROCEDURE ArrayType(range : Range; elemntType : Type) : Type;

PROCEDURE BooleanType(isConst : BOOLEAN) : Type;

PROCEDURE ChannelStructureType(members : CspStructMemberSeq.T) : Type;

PROCEDURE ChannelType(numValues : Mpz.T; dir : Direction) : Type;

PROCEDURE IntegerType(isConst, isSigned : BOOLEAN;
                      dw                : Expr;
                      hasInterval       : BOOLEAN;
                      interval          : Interval) : Type;

PROCEDURE NodeType(arrayed   : BOOLEAN;
                   width     : [1..LAST(CARDINAL)];
                   direction : Direction) : Type;

PROCEDURE StringType(isConst : BOOLEAN) : Type;

PROCEDURE StructureType(isConst : BOOLEAN; name : TEXT) : Type;

(*
PROCEDURE TemporaryIntegerType() : Type; (* ?? *)
*)

(**********************************************************************)  

PROCEDURE FunctionDeclaration(funcName   : Atom.T;
                              formals    : CspDeclaratorSeq.T;
                              returnType : CspType.T;) : Decl;

PROCEDURE StructureDeclaration(name  : Atom.T;
                               decls : CspStructDeclaratorSeq.T;) : Stmt;
  
(**********************************************************************)  

PROCEDURE Declarator(ident        : Atom.T;
                     typeFragment : CspType.T;
                     direction    : CspDirection.T) : CspDeclarator.T;

PROCEDURE StructDeclarator(ident        : Atom.T;
                     typeFragment : CspType.T;
                     init         : CspExpression.T;
                     direction    : CspDirection.T) : CspStructDeclarator.T;

END CspAst.
