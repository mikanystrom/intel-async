(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE TransverseMercator;

IMPORT Projection;

(* Transverse Mercator projection — conformal cylindrical.
   Cylinder tangent along a meridian.  Basis for UTM zones. *)

TYPE T <: Projection.T;

PROCEDURE New(centralMeridian : LONGREAL := 0.0d0) : T;
  (* centralMeridian in radians *)

CONST Brand = "TransverseMercator";

END TransverseMercator.
