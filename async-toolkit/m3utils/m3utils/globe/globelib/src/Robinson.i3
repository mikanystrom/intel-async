(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE Robinson;

IMPORT Projection;

(* Robinson projection — compromise pseudocylindrical.
   Neither conformal nor equal-area; minimizes distortion for world maps.
   Uses tabulated values with interpolation. *)

TYPE T <: Projection.T;

PROCEDURE New(lon0 : LONGREAL := 0.0d0) : T;
  (* lon0 = central meridian in radians *)

CONST Brand = "Robinson";

END Robinson.
