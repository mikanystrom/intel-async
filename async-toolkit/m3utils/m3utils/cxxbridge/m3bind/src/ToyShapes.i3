(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE ToyShapes;

(* Idiomatic M3 interface to the toy C++ Shape library.

   DESIGN DECISIONS:

   1. Object lifetime: Each Shape is a traced M3 object holding a C++
      handle.  When the M3 object is garbage-collected, a weak-ref
      cleaner calls the C++ destructor.  This means the caller never
      calls Free() explicitly.

   2. Type fidelity: The C++ class hierarchy (Shape, Circle, Rectangle)
      is represented as a single M3 opaque type Shape.T.  Virtual
      dispatch happens on the C++ side.  Type-specific constructors
      (NewCircle, NewRectangle) are provided.

   3. Strings: C++ returns malloc'd char*.  The M3 wrapper converts
      to TEXT and frees the C buffer immediately.

   4. Callbacks: ForEach takes an M3 closure (PROCEDURE with captured
      environment).  The bridge passes a trampoline function pointer
      to C, with the M3 closure's address as the context.

   5. Errors: C++ exceptions are caught by the C bridge and converted
      to NIL returns.  The M3 wrapper raises an exception. *)

EXCEPTION Error(TEXT);

TYPE
  Shape <: REFANY;
  ShapeList <: REFANY;

  VisitorClosure = OBJECT METHODS
    visit(s: Shape; index: CARDINAL);
  END;

  PredicateClosure = OBJECT METHODS
    test(s: Shape): BOOLEAN;
  END;

(* --- Shape constructors --- *)

PROCEDURE NewCircle(cx, cy, r: LONGREAL): Shape RAISES {Error};
PROCEDURE NewRectangle(cx, cy, w, h: LONGREAL): Shape RAISES {Error};

(* --- Shape methods --- *)

PROCEDURE Cx(s: Shape): LONGREAL;
PROCEDURE Cy(s: Shape): LONGREAL;
PROCEDURE Move(s: Shape; dx, dy: LONGREAL);
PROCEDURE Area(s: Shape): LONGREAL;
PROCEDURE Perimeter(s: Shape): LONGREAL;
PROCEDURE Contains(s: Shape; px, py: LONGREAL): BOOLEAN;
PROCEDURE Name(s: Shape): TEXT;

(* --- ShapeList --- *)

PROCEDURE NewShapeList(): ShapeList RAISES {Error};

(* Add transfers ownership to the list.  The Shape remains usable
   from M3, but the C++ object is now owned by the list.  Do NOT
   let the M3 GC destroy the shape separately.  *)
PROCEDURE Add(sl: ShapeList; s: Shape);

PROCEDURE Size(sl: ShapeList): CARDINAL;
PROCEDURE Get(sl: ShapeList; i: CARDINAL): Shape;
PROCEDURE TotalArea(sl: ShapeList): LONGREAL;

(* --- Callbacks --- *)

PROCEDURE ForEach(sl: ShapeList; v: VisitorClosure);

PROCEDURE Filter(sl: ShapeList; p: PredicateClosure):
    REF ARRAY OF Shape;

END ToyShapes.
