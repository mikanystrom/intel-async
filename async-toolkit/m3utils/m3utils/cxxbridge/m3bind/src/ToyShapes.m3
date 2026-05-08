(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

UNSAFE MODULE ToyShapes;

IMPORT ToyShapesC, WeakRef, M3toC, Ctypes, Cstdlib;

(* ================================================================
   OBJECT LIFETIME
   ================================================================

   Each Shape wraps a C++ handle.  When the M3 Shape is GC'd, we
   need to call toy_shape_free() on the handle.  We use WeakRef for
   this: register a weak-ref cleaner at construction time.

   COMPLICATION: When a Shape is added to a ShapeList, the C++ side
   takes ownership.  We must NOT free the C++ handle when the M3
   Shape is GC'd in that case.  We set owned := FALSE to suppress
   the destructor.

   ================================================================ *)

REVEAL Shape = BRANDED "ToyShape" REF RECORD
  handle : ToyShapesC.Handle;
  owned  : BOOLEAN;  (* TRUE = we should free handle on GC *)
END;

REVEAL ShapeList = BRANDED "ToyShapeList" REF RECORD
  handle : ToyShapesC.Handle;
  (* Keep references to added shapes so they aren't GC'd
     while the list exists *)
  members : REF ARRAY OF Shape;
  nMembers : CARDINAL;
END;

(* --- Weak-ref cleaners --- *)

PROCEDURE ShapeCleaner(<*UNUSED*> READONLY w: WeakRef.T;
                       r: REFANY) =
  VAR s := NARROW(r, Shape);
  BEGIN
    IF s.owned AND s.handle # NIL THEN
      ToyShapesC.ShapeFree(s.handle);
      s.handle := NIL;
    END;
  END ShapeCleaner;

PROCEDURE ShapeListCleaner(<*UNUSED*> READONLY w: WeakRef.T;
                           r: REFANY) =
  VAR sl := NARROW(r, ShapeList);
  BEGIN
    IF sl.handle # NIL THEN
      ToyShapesC.ShapeListFree(sl.handle);
      sl.handle := NIL;
    END;
  END ShapeListCleaner;

(* --- Shape constructors --- *)

PROCEDURE WrapHandle(h: ToyShapesC.Handle): Shape RAISES {Error} =
  VAR s: Shape;
  BEGIN
    IF h = NIL THEN
      RAISE Error(GetLastError());
    END;
    s := NEW(Shape, handle := h, owned := TRUE);
    EVAL WeakRef.FromRef(s, ShapeCleaner);
    RETURN s;
  END WrapHandle;

PROCEDURE NewCircle(cx, cy, r: LONGREAL): Shape RAISES {Error} =
  BEGIN
    RETURN WrapHandle(ToyShapesC.CircleNew(cx, cy, r));
  END NewCircle;

PROCEDURE NewRectangle(cx, cy, w, h: LONGREAL): Shape RAISES {Error} =
  BEGIN
    RETURN WrapHandle(ToyShapesC.RectangleNew(cx, cy, w, h));
  END NewRectangle;

(* --- Shape methods --- *)

PROCEDURE Cx(s: Shape): LONGREAL =
  BEGIN RETURN ToyShapesC.ShapeCx(s.handle); END Cx;

PROCEDURE Cy(s: Shape): LONGREAL =
  BEGIN RETURN ToyShapesC.ShapeCy(s.handle); END Cy;

PROCEDURE Move(s: Shape; dx, dy: LONGREAL) =
  BEGIN ToyShapesC.ShapeMove(s.handle, dx, dy); END Move;

PROCEDURE Area(s: Shape): LONGREAL =
  BEGIN RETURN ToyShapesC.ShapeArea(s.handle); END Area;

PROCEDURE Perimeter(s: Shape): LONGREAL =
  BEGIN RETURN ToyShapesC.ShapePerimeter(s.handle); END Perimeter;

PROCEDURE Contains(s: Shape; px, py: LONGREAL): BOOLEAN =
  BEGIN
    RETURN ToyShapesC.ShapeContains(s.handle, px, py) # 0;
  END Contains;

PROCEDURE Name(s: Shape): TEXT =
  VAR
    cstr := ToyShapesC.ShapeName(s.handle);
    t : TEXT;
  BEGIN
    IF cstr = NIL THEN RETURN ""; END;
    t := M3toC.CopyStoT(cstr);
    Cstdlib.free(cstr);
    RETURN t;
  END Name;

(* --- ShapeList --- *)

PROCEDURE NewShapeList(): ShapeList RAISES {Error} =
  VAR
    h  := ToyShapesC.ShapeListNew();
    sl : ShapeList;
  BEGIN
    IF h = NIL THEN RAISE Error(GetLastError()); END;
    sl := NEW(ShapeList,
              handle := h,
              members := NEW(REF ARRAY OF Shape, 64),
              nMembers := 0);
    EVAL WeakRef.FromRef(sl, ShapeListCleaner);
    RETURN sl;
  END NewShapeList;

PROCEDURE Add(sl: ShapeList; s: Shape) =
  BEGIN
    ToyShapesC.ShapeListAdd(sl.handle, s.handle);
    (* C++ now owns the handle — suppress M3 GC destructor *)
    s.owned := FALSE;
    (* Keep a reference so GC doesn't collect the M3 object *)
    IF sl.nMembers >= NUMBER(sl.members^) THEN
      GrowMembers(sl);
    END;
    sl.members[sl.nMembers] := s;
    INC(sl.nMembers);
  END Add;

PROCEDURE GrowMembers(sl: ShapeList) =
  VAR
    old := sl.members;
    n   := NUMBER(old^) * 2;
    new := NEW(REF ARRAY OF Shape, n);
  BEGIN
    SUBARRAY(new^, 0, sl.nMembers) := SUBARRAY(old^, 0, sl.nMembers);
    sl.members := new;
  END GrowMembers;

PROCEDURE Size(sl: ShapeList): CARDINAL =
  BEGIN
    RETURN ToyShapesC.ShapeListSize(sl.handle);
  END Size;

PROCEDURE Get(sl: ShapeList; i: CARDINAL): Shape =
  BEGIN
    (* Return the M3 shape we kept a reference to *)
    RETURN sl.members[i];
  END Get;

PROCEDURE TotalArea(sl: ShapeList): LONGREAL =
  BEGIN
    RETURN ToyShapesC.ShapeListTotalArea(sl.handle);
  END TotalArea;

(* ================================================================
   CALLBACKS — the most interesting part
   ================================================================

   The C bridge takes a function pointer + void* context.
   We pass a trampoline procedure as the function pointer and
   the M3 closure object's address as the context.

   CRITICAL: During the callback, the GC must not move the closure
   object.  Since we pass its address as a void*, the GC doesn't
   know about it.  We must ensure the closure is pinned.  In CM3,
   traced references passed to EXTERNAL procedures are automatically
   pinned for the duration of the call, but the context pointer is
   just an ADDRESS.  We keep a local reference to the closure on the
   M3 stack to prevent collection.

   ================================================================ *)

PROCEDURE ForEach(sl: ShapeList; v: VisitorClosure) =
  BEGIN
    (* v is on the M3 stack, so it won't be collected during the call *)
    ToyShapesC.ShapeListForEach(
      sl.handle, VisitorTrampoline, LOOPHOLE(v, ADDRESS));
  END ForEach;

PROCEDURE VisitorTrampoline(h: ToyShapesC.Handle;
                            index: Ctypes.unsigned_long;
                            ctx: ADDRESS) =
  (* Called from C for each shape.  ctx is the M3 VisitorClosure. *)
  VAR
    v := LOOPHOLE(ctx, VisitorClosure);
    (* We need a Shape wrapper for this handle.  Since this is a
       borrowed handle (owned by the list), we create a temporary
       wrapper with owned := FALSE. *)
    s := NEW(Shape, handle := h, owned := FALSE);
  BEGIN
    v.visit(s, index);
  END VisitorTrampoline;

PROCEDURE Filter(sl: ShapeList; p: PredicateClosure):
    REF ARRAY OF Shape =
  VAR
    n   : Ctypes.unsigned_long;
    arr : ADDRESS;
  BEGIN
    arr := ToyShapesC.ShapeListFilter(
      sl.handle, PredicateTrampoline, LOOPHOLE(p, ADDRESS), n);

    IF arr = NIL OR n = 0 THEN
      RETURN NEW(REF ARRAY OF Shape, 0);
    END;

    (* Convert the C array of handles to M3 Shape wrappers.
       The C array is a malloc'd block of n consecutive ADDRESS-sized
       pointers.  We index it by pointer arithmetic. *)
    VAR
      result := NEW(REF ARRAY OF Shape, n);
      ptr : UNTRACED REF ADDRESS := arr;
    BEGIN
      FOR i := 0 TO n - 1 DO
        result[i] := FindMember(sl, ptr^);
        INC(ptr, ADRSIZE(ADDRESS));
      END;
      Cstdlib.free(arr);
      RETURN result;
    END;
  END Filter;

PROCEDURE PredicateTrampoline(h: ToyShapesC.Handle;
                              ctx: ADDRESS): Ctypes.int =
  VAR
    p := LOOPHOLE(ctx, PredicateClosure);
    s := NEW(Shape, handle := h, owned := FALSE);
  BEGIN
    IF p.test(s) THEN RETURN 1; ELSE RETURN 0; END;
  END PredicateTrampoline;

PROCEDURE FindMember(sl: ShapeList; h: ADDRESS): Shape =
  BEGIN
    FOR i := 0 TO sl.nMembers - 1 DO
      IF sl.members[i].handle = h THEN RETURN sl.members[i]; END;
    END;
    (* Handle not found — create a temporary borrowed wrapper *)
    RETURN NEW(Shape, handle := h, owned := FALSE);
  END FindMember;

(* --- Helpers --- *)

PROCEDURE GetLastError(): TEXT =
  VAR cstr := ToyShapesC.LastError();
  BEGIN
    IF cstr = NIL THEN RETURN "unknown error"; END;
    RETURN M3toC.CopyStoT(cstr);
  END GetLastError;

BEGIN
END ToyShapes.
