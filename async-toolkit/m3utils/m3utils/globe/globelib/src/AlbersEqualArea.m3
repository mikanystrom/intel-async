(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE AlbersEqualArea;

IMPORT Math, GeoCoord, Projection;
<*NOWARN*> IMPORT ProjectionRep;

REVEAL
  T = Projection.T BRANDED Brand OBJECT
    n    : LONGREAL;  (* cone constant *)
    c    : LONGREAL;
    rho0 : LONGREAL;
    lon0 : LONGREAL;
  OVERRIDES
    forward := Forward;
    inverse := Inverse;
  END;

PROCEDURE Forward(self : T;
                  READONLY ll : GeoCoord.LatLon;
                  VAR xy : GeoCoord.XY) : BOOLEAN =
  VAR
    theta := self.n * GeoCoord.NormalizeLon(ll.lon - self.lon0);
    rhoSq := self.c - 2.0d0 * self.n * Math.sin(ll.lat);
    rho : LONGREAL;
  BEGIN
    IF rhoSq < 0.0d0 THEN RETURN FALSE END;
    rho := Math.sqrt(rhoSq) / self.n;
    xy.x := rho * Math.sin(theta);
    xy.y := self.rho0 - rho * Math.cos(theta);
    RETURN TRUE
  END Forward;

PROCEDURE Inverse(self : T;
                  READONLY xy : GeoCoord.XY;
                  VAR ll : GeoCoord.LatLon) : BOOLEAN =
  VAR
    dy := self.rho0 - xy.y;
    rho := Math.sqrt(xy.x * xy.x + dy * dy);
    theta : LONGREAL;
    sinLat : LONGREAL;
  BEGIN
    IF self.n < 0.0d0 THEN rho := -rho END;
    theta := Math.atan2(xy.x, dy);
    sinLat := (self.c - rho * rho * self.n * self.n) / (2.0d0 * self.n);
    IF ABS(sinLat) > 1.0d0 THEN RETURN FALSE END;
    ll.lat := Math.asin(sinLat);
    ll.lon := GeoCoord.NormalizeLon(self.lon0 + theta / self.n);
    RETURN TRUE
  END Inverse;

PROCEDURE New(lat1, lat2 : LONGREAL;
              latOrigin : LONGREAL := 0.0d0;
              lonOrigin : LONGREAL := 0.0d0) : T =
  VAR
    sinLat1 := Math.sin(lat1);
    sinLat2 := Math.sin(lat2);
    cosLat1 := Math.cos(lat1);
    n := (sinLat1 + sinLat2) / 2.0d0;
    c := cosLat1 * cosLat1 + 2.0d0 * n * sinLat1;
    rho0 := Math.sqrt(c - 2.0d0 * n * Math.sin(latOrigin)) / n;
  BEGIN
    RETURN NEW(T, name := "AlbersEqualArea",
               n := n, c := c, rho0 := rho0, lon0 := lonOrigin)
  END New;

BEGIN
END AlbersEqualArea.
