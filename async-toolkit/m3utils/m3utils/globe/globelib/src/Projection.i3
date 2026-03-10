(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE Projection;

IMPORT GeoCoord;

(* Abstract map projection interface.
   Each concrete projection subtypes T and overrides forward/inverse. *)

TYPE
  T <: Public;
  Public = ROOT BRANDED Brand OBJECT
    name : TEXT;
  METHODS
    forward(READONLY ll : GeoCoord.LatLon; VAR xy : GeoCoord.XY) : BOOLEAN;
    (* Project geographic coordinates to map coordinates.
       Returns FALSE if the point is outside the projection domain. *)

    inverse(READONLY xy : GeoCoord.XY; VAR ll : GeoCoord.LatLon) : BOOLEAN;
    (* Convert map coordinates back to geographic coordinates.
       Returns FALSE if the point is outside the valid range. *)
  END;

CONST Brand = "Projection";

END Projection.
