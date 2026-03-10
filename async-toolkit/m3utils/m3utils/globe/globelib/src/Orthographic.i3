(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE Orthographic;

IMPORT Projection, GeoCoord;

(* Orthographic projection — perspective azimuthal.
   "Earth from space" view; only the visible hemisphere is shown. *)

TYPE T <: Projection.T;

PROCEDURE New(READONLY center : GeoCoord.LatLon) : T;

CONST Brand = "Orthographic";

END Orthographic.
