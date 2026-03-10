(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE Mercator;

IMPORT Projection;

(* Mercator projection — conformal cylindrical.
   Preserves angles; used in navigation and web maps. *)

TYPE T <: Projection.T;

PROCEDURE New(lon0 : LONGREAL := 0.0d0) : T;
  (* lon0 = central meridian in radians *)

CONST Brand = "Mercator";

END Mercator.
