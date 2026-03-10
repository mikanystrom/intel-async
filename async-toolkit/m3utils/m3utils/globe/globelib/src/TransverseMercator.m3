(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE TransverseMercator;

IMPORT Math, GeoCoord, Projection;
<*NOWARN*> IMPORT ProjectionRep;

REVEAL
  T = Projection.T BRANDED Brand OBJECT
    lon0 : LONGREAL;  (* central meridian in radians *)
  OVERRIDES
    forward := Forward;
    inverse := Inverse;
  END;

PROCEDURE Forward(self : T;
                  READONLY ll : GeoCoord.LatLon;
                  VAR xy : GeoCoord.XY) : BOOLEAN =
  VAR
    dlon := GeoCoord.NormalizeLon(ll.lon - self.lon0);
    b := Math.cos(ll.lat) * Math.sin(dlon);
  BEGIN
    IF ABS(b) > 0.9999d0 THEN RETURN FALSE END;
    xy.x := 0.5d0 * Math.log((1.0d0 + b) / (1.0d0 - b));
    xy.y := Math.atan2(Math.tan(ll.lat), Math.cos(dlon));
    RETURN TRUE
  END Forward;

PROCEDURE Inverse(self : T;
                  READONLY xy : GeoCoord.XY;
                  VAR ll : GeoCoord.LatLon) : BOOLEAN =
  VAR
    sinhX := (Math.exp(xy.x) - Math.exp(-xy.x)) / 2.0d0;
    cosD  := Math.cos(xy.y);
  BEGIN
    ll.lat := Math.asin(Math.sin(xy.y) /
                        Math.sqrt(1.0d0 + sinhX * sinhX));
    ll.lon := GeoCoord.NormalizeLon(self.lon0 +
                                     Math.atan2(sinhX, cosD));
    RETURN TRUE
  END Inverse;

PROCEDURE New(centralMeridian : LONGREAL := 0.0d0) : T =
  BEGIN
    RETURN NEW(T, name := "TransverseMercator", lon0 := centralMeridian)
  END New;

BEGIN
END TransverseMercator.
