(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE GeoCoord;

IMPORT Math;

PROCEDURE LatLonDeg(latDeg, lonDeg : LONGREAL) : LatLon =
  BEGIN
    RETURN LatLon { lat := latDeg * DegToRad,
                    lon := lonDeg * DegToRad }
  END LatLonDeg;

PROCEDURE LatLonToXYZ(READONLY ll : LatLon) : XYZ =
  VAR cosLat := Math.cos(ll.lat);
  BEGIN
    RETURN XYZ { x := cosLat * Math.cos(ll.lon),
                 y := cosLat * Math.sin(ll.lon),
                 z := Math.sin(ll.lat) }
  END LatLonToXYZ;

PROCEDURE XYZToLatLon(READONLY p : XYZ) : LatLon =
  BEGIN
    RETURN LatLon { lat := Math.atan2(p.z, Math.sqrt(p.x * p.x + p.y * p.y)),
                    lon := Math.atan2(p.y, p.x) }
  END XYZToLatLon;

PROCEDURE NormalizeLon(lon : LONGREAL) : LONGREAL =
  CONST Pi = 3.141592653589793d0;
  BEGIN
    WHILE lon > Pi DO lon := lon - 2.0d0 * Pi END;
    WHILE lon < -Pi DO lon := lon + 2.0d0 * Pi END;
    RETURN lon
  END NormalizeLon;

BEGIN
END GeoCoord.
