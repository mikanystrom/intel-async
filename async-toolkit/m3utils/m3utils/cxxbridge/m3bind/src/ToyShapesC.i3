(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

(* Raw C bindings — thin layer matching shapes_c.h exactly.
   Not intended for direct use; see ToyShapes.i3 for the M3 API. *)

UNSAFE INTERFACE ToyShapesC;

IMPORT Ctypes;

TYPE
  Handle = ADDRESS;  (* opaque C++ object pointer *)

  VisitorProc  = PROCEDURE(s: Handle; index: Ctypes.unsigned_long;
                            ctx: ADDRESS);
  PredicateProc = PROCEDURE(s: Handle; ctx: ADDRESS): Ctypes.int;

(* Error handling *)
<*EXTERNAL toy_last_error*>
PROCEDURE LastError(): Ctypes.char_star;

(* Shape constructors *)
<*EXTERNAL toy_circle_new*>
PROCEDURE CircleNew(cx, cy, r: LONGREAL): Handle;

<*EXTERNAL toy_rectangle_new*>
PROCEDURE RectangleNew(cx, cy, w, h: LONGREAL): Handle;

(* Shape methods *)
<*EXTERNAL toy_shape_free*>
PROCEDURE ShapeFree(s: Handle);

<*EXTERNAL toy_shape_cx*>
PROCEDURE ShapeCx(s: Handle): LONGREAL;

<*EXTERNAL toy_shape_cy*>
PROCEDURE ShapeCy(s: Handle): LONGREAL;

<*EXTERNAL toy_shape_move*>
PROCEDURE ShapeMove(s: Handle; dx, dy: LONGREAL);

<*EXTERNAL toy_shape_area*>
PROCEDURE ShapeArea(s: Handle): LONGREAL;

<*EXTERNAL toy_shape_perimeter*>
PROCEDURE ShapePerimeter(s: Handle): LONGREAL;

<*EXTERNAL toy_shape_contains*>
PROCEDURE ShapeContains(s: Handle; px, py: LONGREAL): Ctypes.int;

(* Returns malloc'd string; caller must free() *)
<*EXTERNAL toy_shape_name*>
PROCEDURE ShapeName(s: Handle): Ctypes.char_star;

(* ShapeList *)
<*EXTERNAL toy_shapelist_new*>
PROCEDURE ShapeListNew(): Handle;

<*EXTERNAL toy_shapelist_free*>
PROCEDURE ShapeListFree(sl: Handle);

<*EXTERNAL toy_shapelist_add*>
PROCEDURE ShapeListAdd(sl: Handle; s: Handle);

<*EXTERNAL toy_shapelist_size*>
PROCEDURE ShapeListSize(sl: Handle): Ctypes.unsigned_long;

<*EXTERNAL toy_shapelist_get*>
PROCEDURE ShapeListGet(sl: Handle; i: Ctypes.unsigned_long): Handle;

<*EXTERNAL toy_shapelist_total_area*>
PROCEDURE ShapeListTotalArea(sl: Handle): LONGREAL;

(* Callbacks *)
<*EXTERNAL toy_shapelist_foreach*>
PROCEDURE ShapeListForEach(sl: Handle; fn: VisitorProc; ctx: ADDRESS);

<*EXTERNAL toy_shapelist_filter*>
PROCEDURE ShapeListFilter(sl: Handle; fn: PredicateProc; ctx: ADDRESS;
                          VAR out_n: Ctypes.unsigned_long): ADDRESS;

END ToyShapesC.
