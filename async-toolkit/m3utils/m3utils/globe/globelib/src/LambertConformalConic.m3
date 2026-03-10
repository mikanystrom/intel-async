(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE LambertConformalConic;

IMPORT Math, GeoCoord, Projection;
<*NOWARN*> IMPORT ProjectionRep;

CONST HalfPi = 1.5707963267948966d0;

REVEAL
  T = Projection.T BRANDED Brand OBJECT
    n       : LONGREAL;  (* cone constant *)
    f       : LONGREAL;  (* projection constant *)
    rho0    : LONGREAL;  (* radius at origin latitude *)
    lon0    : LONGREAL;
  OVERRIDES
    forward := Forward;
    inverse := Inverse;
  END;

PROCEDURE TanHalfPiMinusLat(lat : LONGREAL) : LONGREAL =
  BEGIN
    RETURN Math.tan((HalfPi - lat) / 2.0d0)
  END TanHalfPiMinusLat;

PROCEDURE Forward(self : T;
                  READONLY ll : GeoCoord.LatLon;
                  VAR xy : GeoCoord.XY) : BOOLEAN =
  VAR
    rho, theta : LONGREAL;
  BEGIN
    IF ABS(ll.lat) > HalfPi - 1.0d-10 THEN
      IF ll.lat * self.n <= 0.0d0 THEN RETURN FALSE END;
    END;
    rho := self.f * Math.pow(TanHalfPiMinusLat(ll.lat), self.n);
    theta := self.n * GeoCoord.NormalizeLon(ll.lon - self.lon0);
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
  BEGIN
    IF self.n < 0.0d0 THEN rho := -rho END;
    IF rho < 1.0d-15 THEN
      ll.lat := HalfPi;
      IF self.n < 0.0d0 THEN ll.lat := -HalfPi END;
      ll.lon := self.lon0;
      RETURN TRUE
    END;
    theta := Math.atan2(xy.x, dy);
    ll.lat := HalfPi - 2.0d0 * Math.atan(Math.pow(rho / self.f, 1.0d0 / self.n));
    ll.lon := GeoCoord.NormalizeLon(self.lon0 + theta / self.n);
    RETURN TRUE
  END Inverse;

PROCEDURE New(lat1, lat2 : LONGREAL;
              latOrigin : LONGREAL := 0.0d0;
              lonOrigin : LONGREAL := 0.0d0) : T =
  VAR
    n, ff, rho0 : LONGREAL;
    cosLat1 := Math.cos(lat1);
    tanHalf1 := TanHalfPiMinusLat(lat1);
    tanHalf2 := TanHalfPiMinusLat(lat2);
  BEGIN
    IF ABS(lat1 - lat2) < 1.0d-10 THEN
      n := Math.sin(lat1);
    ELSE
      n := Math.log(cosLat1 / Math.cos(lat2)) /
           Math.log(tanHalf2 / tanHalf1);
    END;
    ff := cosLat1 * Math.pow(tanHalf1, n) / n;
    rho0 := ff * Math.pow(TanHalfPiMinusLat(latOrigin), n);
    RETURN NEW(T, name := "LambertConformalConic",
               n := n, f := ff, rho0 := rho0, lon0 := lonOrigin)
  END New;

BEGIN
END LambertConformalConic.
