(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE AzimuthalEquidistant;

IMPORT Projection, GeoCoord;

(* Azimuthal Equidistant projection.
   Preserves distances from the center point.
   Often used for UN emblem / polar maps. *)

TYPE T <: Projection.T;

PROCEDURE New(READONLY center : GeoCoord.LatLon) : T;

CONST Brand = "AzimuthalEquidistant";

END AzimuthalEquidistant.
