(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE Equirectangular;

IMPORT Projection;

(* Equirectangular (Plate Carree) projection.
   Simplest cylindrical projection: x = lon, y = lat. *)

TYPE T <: Projection.T;

PROCEDURE New(lon0 : LONGREAL := 0.0d0) : T;
  (* lon0 = central meridian in radians *)

CONST Brand = "Equirectangular";

END Equirectangular.
