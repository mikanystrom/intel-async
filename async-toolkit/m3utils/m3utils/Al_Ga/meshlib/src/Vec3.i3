(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE Vec3;

(* 3D vector operations in LONGREAL. *)

TYPE T = RECORD x, y, z: LONGREAL; END;

CONST Zero = T{0.0d0, 0.0d0, 0.0d0};

PROCEDURE Add(READONLY a, b: T): T;
PROCEDURE Sub(READONLY a, b: T): T;
PROCEDURE Scale(s: LONGREAL; READONLY a: T): T;
PROCEDURE Negate(READONLY a: T): T;

PROCEDURE Dot(READONLY a, b: T): LONGREAL;
PROCEDURE Cross(READONLY a, b: T): T;

PROCEDURE Length(READONLY a: T): LONGREAL;
PROCEDURE LengthSq(READONLY a: T): LONGREAL;
PROCEDURE Normalize(READONLY a: T): T;
  (* Returns zero vector if length is zero. *)

PROCEDURE FromReal(x, y, z: REAL): T;

END Vec3.
