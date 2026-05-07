(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE Vec3;

IMPORT Math;

PROCEDURE Add(READONLY a, b: T): T =
  BEGIN RETURN T{a.x + b.x, a.y + b.y, a.z + b.z}; END Add;

PROCEDURE Sub(READONLY a, b: T): T =
  BEGIN RETURN T{a.x - b.x, a.y - b.y, a.z - b.z}; END Sub;

PROCEDURE Scale(s: LONGREAL; READONLY a: T): T =
  BEGIN RETURN T{s * a.x, s * a.y, s * a.z}; END Scale;

PROCEDURE Negate(READONLY a: T): T =
  BEGIN RETURN T{-a.x, -a.y, -a.z}; END Negate;

PROCEDURE Dot(READONLY a, b: T): LONGREAL =
  BEGIN RETURN a.x * b.x + a.y * b.y + a.z * b.z; END Dot;

PROCEDURE Cross(READONLY a, b: T): T =
  BEGIN
    RETURN T{a.y * b.z - a.z * b.y,
             a.z * b.x - a.x * b.z,
             a.x * b.y - a.y * b.x};
  END Cross;

PROCEDURE LengthSq(READONLY a: T): LONGREAL =
  BEGIN RETURN Dot(a, a); END LengthSq;

PROCEDURE Length(READONLY a: T): LONGREAL =
  BEGIN RETURN Math.sqrt(Dot(a, a)); END Length;

PROCEDURE Normalize(READONLY a: T): T =
  VAR len := Length(a);
  BEGIN
    IF len = 0.0d0 THEN RETURN Zero; END;
    RETURN Scale(1.0d0 / len, a);
  END Normalize;

PROCEDURE FromReal(x, y, z: REAL): T =
  BEGIN
    RETURN T{FLOAT(x, LONGREAL), FLOAT(y, LONGREAL), FLOAT(z, LONGREAL)};
  END FromReal;

BEGIN
END Vec3.
