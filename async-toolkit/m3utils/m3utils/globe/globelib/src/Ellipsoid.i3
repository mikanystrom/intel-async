(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE Ellipsoid;

(* Ellipsoid and sphere definitions for map projections *)

TYPE
  T = RECORD
    a : LONGREAL;   (* semi-major axis (equatorial radius) in meters *)
    f : LONGREAL;   (* flattening *)
  END;

PROCEDURE B(READONLY e : T) : LONGREAL;
  (* Semi-minor axis *)

PROCEDURE E(READONLY e : T) : LONGREAL;
  (* First eccentricity *)

PROCEDURE ESq(READONLY e : T) : LONGREAL;
  (* First eccentricity squared *)

CONST
  (* WGS84 ellipsoid *)
  WGS84 = T { a := 6378137.0d0,
               f := 1.0d0 / 298.257223563d0 };

  (* Unit sphere (for spherical projections) *)
  Sphere = T { a := 1.0d0, f := 0.0d0 };

  (* Authalic sphere matching WGS84 surface area *)
  AuthalicSphere = T { a := 6371007.181d0, f := 0.0d0 };

CONST Brand = "Ellipsoid";

END Ellipsoid.
