(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE Stereographic;

IMPORT Projection, GeoCoord;

(* Stereographic projection — conformal azimuthal.
   Projects the sphere from a point antipodal to the center. *)

TYPE T <: Projection.T;

PROCEDURE New(READONLY center : GeoCoord.LatLon) : T;
  (* Create a stereographic projection centered on the given point *)

CONST Brand = "Stereographic";

END Stereographic.
