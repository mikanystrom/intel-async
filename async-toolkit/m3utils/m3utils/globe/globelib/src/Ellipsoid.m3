(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE Ellipsoid;

IMPORT Math;

PROCEDURE B(READONLY e : T) : LONGREAL =
  BEGIN
    RETURN e.a * (1.0d0 - e.f)
  END B;

PROCEDURE E(READONLY e : T) : LONGREAL =
  BEGIN
    RETURN Math.sqrt(ESq(e))
  END E;

PROCEDURE ESq(READONLY e : T) : LONGREAL =
  BEGIN
    RETURN 2.0d0 * e.f - e.f * e.f
  END ESq;

BEGIN
END Ellipsoid.
