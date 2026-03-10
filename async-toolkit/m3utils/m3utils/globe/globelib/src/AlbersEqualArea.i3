(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE AlbersEqualArea;

IMPORT Projection;

(* Albers Equal-Area Conic projection.
   Preserves area; commonly used for thematic maps. *)

TYPE T <: Projection.T;

PROCEDURE New(lat1, lat2 : LONGREAL;
              latOrigin : LONGREAL := 0.0d0;
              lonOrigin : LONGREAL := 0.0d0) : T;
  (* lat1, lat2 = standard parallels in radians *)

CONST Brand = "AlbersEqualArea";

END AlbersEqualArea.
