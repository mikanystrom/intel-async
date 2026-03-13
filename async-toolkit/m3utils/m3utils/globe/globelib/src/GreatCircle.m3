(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE GreatCircle;

IMPORT Math, GeoCoord;

PROCEDURE Distance(READONLY a, b : GeoCoord.LatLon) : LONGREAL =
  VAR
    dlon := b.lon - a.lon;
    sinDlat := Math.sin((b.lat - a.lat) / 2.0d0);
    sinDlon := Math.sin(dlon / 2.0d0);
    h := sinDlat * sinDlat +
         Math.cos(a.lat) * Math.cos(b.lat) * sinDlon * sinDlon;
  BEGIN
    RETURN 2.0d0 * Math.asin(Math.sqrt(MIN(1.0d0, h)))
  END Distance;

PROCEDURE Cross(READONLY a, b : GeoCoord.XYZ) : GeoCoord.XYZ =
  BEGIN
    RETURN GeoCoord.XYZ {
      x := a.y * b.z - a.z * b.y,
      y := a.z * b.x - a.x * b.z,
      z := a.x * b.y - a.y * b.x
    }
  END Cross;

PROCEDURE Normalize(READONLY p : GeoCoord.XYZ) : GeoCoord.XYZ =
  VAR len := Math.sqrt(p.x * p.x + p.y * p.y + p.z * p.z);
  BEGIN
    IF len < 1.0d-15 THEN
      RETURN GeoCoord.XYZ { x := 0.0d0, y := 0.0d0, z := 1.0d0 }
    END;
    RETURN GeoCoord.XYZ { x := p.x / len, y := p.y / len, z := p.z / len }
  END Normalize;

PROCEDURE Dot(READONLY a, b : GeoCoord.XYZ) : LONGREAL =
  BEGIN
    RETURN a.x * b.x + a.y * b.y + a.z * b.z
  END Dot;

PROCEDURE ComputeRotation(READONLY a, b : GeoCoord.LatLon) : Rotation =
  (* The pole is Cross(A, B) so that "north" in the rotated system
     corresponds to the left side of the A→B path (geographic north
     of the route).  lonOffset centers the A–B arc. *)
  VAR
    va := GeoCoord.LatLonToXYZ(a);
    vb := GeoCoord.LatLonToXYZ(b);
    pole := Normalize(Cross(va, vb));
    poleLl := GeoCoord.XYZToLatLon(pole);
    rot : Rotation;
    rotA, rotB : GeoCoord.LatLon;
  BEGIN
    rot.pole := pole;
    rot.sinPoleLat := Math.sin(poleLl.lat);
    rot.cosPoleLat := Math.cos(poleLl.lat);
    rot.poleLon := poleLl.lon;
    rot.lonOffset := 0.0d0;
    (* Center the route: lonOffset = midpoint so A is left, B is right.
       Use atan2 to compute the circular mean, which handles wraparound
       at ±π correctly (e.g. when the two rotated longitudes straddle
       the antimeridian). *)
    rotA := RotateForward(rot, a);
    rotB := RotateForward(rot, b);
    rot.lonOffset := Math.atan2(Math.sin(rotA.lon) + Math.sin(rotB.lon),
                                Math.cos(rotA.lon) + Math.cos(rotB.lon));
    RETURN rot
  END ComputeRotation;

(* Rotate coordinates so the great circle becomes the equator.
   This is equivalent to rotating the sphere so that the computed pole
   moves to the geographic north pole.

   Derived from the 3D rotation matrix: first R_z(-poleLon) to bring
   the pole to the prime meridian, then R_y(alpha) to tilt it to the
   north pole (sin alpha = -cosPoleLat, cos alpha = sinPoleLat).

   The resulting spherical coordinates are:
     lat' = asin(sin(lat) sin(poleLat) + cos(lat) cos(poleLat) cos(dlon))
     lon' = atan2(cos(lat) sin(dlon),
                  cos(lat) sin(poleLat) cos(dlon) - sin(lat) cos(poleLat))
*)

PROCEDURE RotateForward(READONLY rot : Rotation;
                        READONLY ll : GeoCoord.LatLon) : GeoCoord.LatLon =
  VAR
    dlon := ll.lon - rot.poleLon;
    sinLat := Math.sin(ll.lat);
    cosLat := Math.cos(ll.lat);
    cosDlon := Math.cos(dlon);
    sinDlon := Math.sin(dlon);
    result : GeoCoord.LatLon;
  BEGIN
    result.lat := Math.asin(sinLat * rot.sinPoleLat +
                            cosLat * rot.cosPoleLat * cosDlon);
    result.lon := Math.atan2(cosLat * sinDlon,
                             cosLat * rot.sinPoleLat * cosDlon -
                             sinLat * rot.cosPoleLat)
                  - rot.lonOffset;
    RETURN result
  END RotateForward;

PROCEDURE RotateInverse(READONLY rot : Rotation;
                        READONLY ll : GeoCoord.LatLon) : GeoCoord.LatLon =
  VAR
    adjLon := ll.lon + rot.lonOffset;
    sinLat := Math.sin(ll.lat);
    cosLat := Math.cos(ll.lat);
    cosLon := Math.cos(adjLon);
    sinLon := Math.sin(adjLon);
    result : GeoCoord.LatLon;
  BEGIN
    result.lat := Math.asin(sinLat * rot.sinPoleLat -
                            cosLat * rot.cosPoleLat * cosLon);
    result.lon := GeoCoord.NormalizeLon(
                    rot.poleLon +
                    Math.atan2(cosLat * sinLon,
                               sinLat * rot.cosPoleLat +
                               cosLat * rot.sinPoleLat * cosLon));
    RETURN result
  END RotateInverse;

PROCEDURE FromPole(READONLY pole, eqPoint : GeoCoord.LatLon) : Rotation =
  (* Build rotation from an explicit pole.  The pole becomes the north
     pole of the rotated coordinate system exactly as given.  lonOffset
     is set so that eqPoint maps to lon=0 on the rotated equator.
     The equator point need not be exactly 90 deg from the pole —
     it is used only to orient the rotated longitude. *)
  VAR
    poleXYZ := GeoCoord.LatLonToXYZ(pole);
    rot : Rotation;
    eqRot : GeoCoord.LatLon;
  BEGIN
    rot.pole := poleXYZ;
    rot.sinPoleLat := Math.sin(pole.lat);
    rot.cosPoleLat := Math.cos(pole.lat);
    rot.poleLon := pole.lon;
    rot.lonOffset := 0.0d0;
    (* Rotate eqPoint and use its longitude as the offset *)
    eqRot := RotateForward(rot, eqPoint);
    rot.lonOffset := eqRot.lon;
    RETURN rot
  END FromPole;

BEGIN
END GreatCircle.
