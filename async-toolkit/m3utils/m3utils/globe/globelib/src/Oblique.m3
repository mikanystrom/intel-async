(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE Oblique;

IMPORT GeoCoord, Projection, GreatCircle;
<*NOWARN*> IMPORT ProjectionRep;

REVEAL
  T = Projection.T BRANDED Brand OBJECT
    base : Projection.T;
    rot  : GreatCircle.Rotation;
  OVERRIDES
    forward := Forward;
    inverse := Inverse;
  END;

PROCEDURE Forward(self : T;
                  READONLY ll : GeoCoord.LatLon;
                  VAR xy : GeoCoord.XY) : BOOLEAN =
  VAR rotated := GreatCircle.RotateForward(self.rot, ll);
  BEGIN
    RETURN self.base.forward(rotated, xy)
  END Forward;

PROCEDURE Inverse(self : T;
                  READONLY xy : GeoCoord.XY;
                  VAR ll : GeoCoord.LatLon) : BOOLEAN =
  VAR rotated : GeoCoord.LatLon;
  BEGIN
    IF NOT self.base.inverse(xy, rotated) THEN RETURN FALSE END;
    ll := GreatCircle.RotateInverse(self.rot, rotated);
    RETURN TRUE
  END Inverse;

PROCEDURE FromTwoPoints(base : Projection.T;
                        READONLY a, b : GeoCoord.LatLon) : T =
  BEGIN
    RETURN NEW(T,
               name := "Oblique " & base.name,
               base := base,
               rot := GreatCircle.ComputeRotation(a, b))
  END FromTwoPoints;

PROCEDURE FromPoleAndEquator(base : Projection.T;
                             READONLY pole, eqPoint : GeoCoord.LatLon) : T =
  BEGIN
    RETURN NEW(T,
               name := "Oblique " & base.name,
               base := base,
               rot := GreatCircle.FromPole(pole, eqPoint))
  END FromPoleAndEquator;

BEGIN
END Oblique.
