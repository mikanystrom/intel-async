(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE Vec3;

(* 3D vector arithmetic in LONGREAL.

   All operations are pure (no side effects) and return new values.
   No procedure in this interface raises exceptions or modifies
   global state. *)

TYPE T = RECORD x, y, z: LONGREAL; END;

CONST Zero = T{0.0d0, 0.0d0, 0.0d0};

(* Arithmetic.  Ensures: result = the named operation on the inputs. *)
PROCEDURE Add(READONLY a, b: T): T;       (* a + b *)
PROCEDURE Sub(READONLY a, b: T): T;       (* a - b *)
PROCEDURE Scale(s: LONGREAL; READONLY a: T): T;  (* s * a *)
PROCEDURE Negate(READONLY a: T): T;        (* -a *)

(* Inner and cross products. *)
PROCEDURE Dot(READONLY a, b: T): LONGREAL;  (* a . b *)
PROCEDURE Cross(READONLY a, b: T): T;       (* a x b *)

(* Norms. *)
PROCEDURE Length(READONLY a: T): LONGREAL;    (* |a| *)
PROCEDURE LengthSq(READONLY a: T): LONGREAL;  (* |a|^2 = Dot(a,a) *)

PROCEDURE Normalize(READONLY a: T): T;
  (* Ensures: if |a| > 0, returns a / |a| (unit vector);
              if |a| = 0, returns Zero. *)

(* Conversion from single-precision REAL to LONGREAL. *)
PROCEDURE FromReal(x, y, z: REAL): T;
  (* Ensures: result = T{FLOAT(x,LONGREAL), FLOAT(y,LONGREAL),
                          FLOAT(z,LONGREAL)}. *)

END Vec3.
