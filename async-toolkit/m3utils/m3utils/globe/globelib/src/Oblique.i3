(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE Oblique;

IMPORT Projection, GeoCoord;

(* Oblique aspect wrapper.
   Wraps any projection by rotating coordinates so a user-specified
   great circle (defined by two points) becomes the equator.

   Example: to make a Mercator centered on the London-Tokyo great circle,
   create an Oblique projection wrapping a Mercator with those two points. *)

TYPE T <: Projection.T;

PROCEDURE FromTwoPoints(base : Projection.T;
                        READONLY a, b : GeoCoord.LatLon) : T;
  (* Create an oblique wrapper.  The great circle through a and b
     becomes the equator in the base projection's coordinate system. *)

PROCEDURE FromPoleAndEquator(base : Projection.T;
                             READONLY pole, eqPoint : GeoCoord.LatLon) : T;
  (* Create an oblique wrapper by specifying the projection's pole
     and one point on the equator. *)

CONST Brand = "Oblique";

END Oblique.
