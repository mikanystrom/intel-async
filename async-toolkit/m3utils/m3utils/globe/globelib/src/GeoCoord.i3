(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE GeoCoord;

(* Coordinate types for map projections *)

TYPE
  (* Latitude/longitude in radians *)
  LatLon = RECORD
    lat, lon : LONGREAL;  (* radians *)
  END;

  (* Projected 2D coordinates *)
  XY = RECORD
    x, y : LONGREAL;
  END;

  (* 3D unit-sphere Cartesian coordinates *)
  XYZ = RECORD
    x, y, z : LONGREAL;
  END;

CONST
  DegToRad = 0.017453292519943295d0;  (* Pi / 180 *)
  RadToDeg = 57.29577951308232d0;     (* 180 / Pi *)

PROCEDURE LatLonDeg(latDeg, lonDeg : LONGREAL) : LatLon;
  (* Construct LatLon from degrees *)

PROCEDURE LatLonToXYZ(READONLY ll : LatLon) : XYZ;
  (* Convert lat/lon to unit-sphere Cartesian *)

PROCEDURE XYZToLatLon(READONLY p : XYZ) : LatLon;
  (* Convert unit-sphere Cartesian to lat/lon *)

PROCEDURE NormalizeLon(lon : LONGREAL) : LONGREAL;
  (* Normalize longitude to [-Pi, Pi] *)

CONST Brand = "GeoCoord";

END GeoCoord.
