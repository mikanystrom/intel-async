(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE Equirectangular;

IMPORT GeoCoord, Projection;
<*NOWARN*> IMPORT ProjectionRep;

REVEAL
  T = Projection.T BRANDED Brand OBJECT
    lon0 : LONGREAL := 0.0d0;
  OVERRIDES
    forward := Forward;
    inverse := Inverse;
  END;

PROCEDURE Forward(self : T;
                  READONLY ll : GeoCoord.LatLon;
                  VAR xy : GeoCoord.XY) : BOOLEAN =
  BEGIN
    xy.x := GeoCoord.NormalizeLon(ll.lon - self.lon0);
    xy.y := ll.lat;
    RETURN TRUE
  END Forward;

PROCEDURE Inverse(self : T;
                  READONLY xy : GeoCoord.XY;
                  VAR ll : GeoCoord.LatLon) : BOOLEAN =
  CONST HalfPi = 1.5707963267948966d0;
  BEGIN
    IF ABS(xy.y) > HalfPi THEN RETURN FALSE END;
    ll.lat := xy.y;
    ll.lon := GeoCoord.NormalizeLon(xy.x + self.lon0);
    RETURN TRUE
  END Inverse;

PROCEDURE New(lon0 : LONGREAL := 0.0d0) : T =
  BEGIN
    RETURN NEW(T, name := "Equirectangular", lon0 := lon0)
  END New;

BEGIN
END Equirectangular.
