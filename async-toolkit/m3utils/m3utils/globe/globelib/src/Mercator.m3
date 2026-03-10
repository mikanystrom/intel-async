(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE Mercator;

IMPORT Math, GeoCoord, Projection;
<*NOWARN*> IMPORT ProjectionRep;

CONST
  MaxLat = 1.5707d0;  (* ~89.96 degrees — just short of the pole singularity *)

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
  VAR lat := ll.lat;
  BEGIN
    (* Always compute xy (clamped for extreme latitudes) so that
       polygon ring recovery in SvgWriter has meaningful coordinates.
       Return FALSE for extreme latitudes so they don't affect the
       bounding box — clamped points extend off-screen. *)
    IF lat > MaxLat THEN lat := MaxLat
    ELSIF lat < -MaxLat THEN lat := -MaxLat
    END;
    xy.x := GeoCoord.NormalizeLon(ll.lon - self.lon0);
    xy.y := Math.log(Math.tan(lat) + 1.0d0 / Math.cos(lat));
    RETURN ABS(ll.lat) <= MaxLat
  END Forward;

PROCEDURE Inverse(self : T;
                  READONLY xy : GeoCoord.XY;
                  VAR ll : GeoCoord.LatLon) : BOOLEAN =
  BEGIN
    ll.lat := 2.0d0 * Math.atan(Math.exp(xy.y)) - Math.Pi / 2.0d0;
    ll.lon := GeoCoord.NormalizeLon(xy.x + self.lon0);
    RETURN TRUE
  END Inverse;

PROCEDURE New(lon0 : LONGREAL := 0.0d0) : T =
  BEGIN
    RETURN NEW(T, name := "Mercator", lon0 := lon0)
  END New;

BEGIN
END Mercator.
