(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE Orthographic;

IMPORT Math, GeoCoord, Projection;
<*NOWARN*> IMPORT ProjectionRep;

REVEAL
  T = Projection.T BRANDED Brand OBJECT
    lat0, lon0 : LONGREAL;
    sinLat0, cosLat0 : LONGREAL;
  OVERRIDES
    forward := Forward;
    inverse := Inverse;
  END;

PROCEDURE Forward(self : T;
                  READONLY ll : GeoCoord.LatLon;
                  VAR xy : GeoCoord.XY) : BOOLEAN =
  VAR
    dlon := GeoCoord.NormalizeLon(ll.lon - self.lon0);
    sinLat := Math.sin(ll.lat);
    cosLat := Math.cos(ll.lat);
    cosDlon := Math.cos(dlon);
    cosC := self.sinLat0 * sinLat + self.cosLat0 * cosLat * cosDlon;
  BEGIN
    (* Always set xy so callers can use coordinates for winding
       computation even when the point is on the back hemisphere. *)
    xy.x := cosLat * Math.sin(dlon);
    xy.y := self.cosLat0 * sinLat - self.sinLat0 * cosLat * cosDlon;
    RETURN cosC >= 0.0d0
  END Forward;

PROCEDURE Inverse(self : T;
                  READONLY xy : GeoCoord.XY;
                  VAR ll : GeoCoord.LatLon) : BOOLEAN =
  VAR
    rho := Math.sqrt(xy.x * xy.x + xy.y * xy.y);
    sinC, cosC : LONGREAL;
  BEGIN
    IF rho > 1.0d0 THEN RETURN FALSE END;
    IF rho < 1.0d-15 THEN
      ll.lat := self.lat0;
      ll.lon := self.lon0;
      RETURN TRUE
    END;
    cosC := Math.sqrt(1.0d0 - rho * rho);
    sinC := rho;
    ll.lat := Math.asin(cosC * self.sinLat0 + xy.y * sinC * self.cosLat0 / rho);
    ll.lon := GeoCoord.NormalizeLon(
                self.lon0 + Math.atan2(xy.x * sinC,
                                       rho * self.cosLat0 * cosC - xy.y * self.sinLat0 * sinC));
    RETURN TRUE
  END Inverse;

PROCEDURE New(READONLY center : GeoCoord.LatLon) : T =
  BEGIN
    RETURN NEW(T, name := "Orthographic",
               lat0 := center.lat, lon0 := center.lon,
               sinLat0 := Math.sin(center.lat),
               cosLat0 := Math.cos(center.lat))
  END New;

BEGIN
END Orthographic.
