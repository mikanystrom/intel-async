(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE LambertConformalConic;

IMPORT Projection;

(* Lambert Conformal Conic projection.
   Conformal conic with one or two standard parallels.
   Widely used for aviation charts and regional maps. *)

TYPE T <: Projection.T;

PROCEDURE New(lat1, lat2 : LONGREAL;
              latOrigin : LONGREAL := 0.0d0;
              lonOrigin : LONGREAL := 0.0d0) : T;
  (* lat1, lat2 = standard parallels in radians
     latOrigin, lonOrigin = origin of the projection in radians *)

CONST Brand = "LambertConformalConic";

END LambertConformalConic.
