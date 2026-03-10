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
  (* The pole is computed as Cross(B, A) so that when the resulting
     rotation maps the great circle to the equator, point A appears
     at negative longitude (left) and B at positive longitude (right).
     This gives the natural map orientation: "from" on the left,
     "to" on the right. *)
  VAR
    va := GeoCoord.LatLonToXYZ(a);
    vb := GeoCoord.LatLonToXYZ(b);
    pole := Normalize(Cross(vb, va));
    poleLl := GeoCoord.XYZToLatLon(pole);
  BEGIN
    RETURN Rotation {
      pole := pole,
      sinPoleLat := Math.sin(poleLl.lat),
      cosPoleLat := Math.cos(poleLl.lat),
      poleLon := poleLl.lon,
      lonOffset := 0.0d0
    }
  END ComputeRotation;

(* Rotate coordinates so the great circle becomes the equator.
   This is equivalent to rotating the sphere so that the computed pole
   moves to the geographic north pole.

   The rotation is:
   1. Shift longitude so pole is at lon=0
   2. Rotate latitude so pole is at lat=90

   In spherical coordinates:
     lon' = lon - poleLon
     Then apply the latitude rotation matrix:
       lat_new = asin(sin(lat) * sin(poleLat) + cos(lat) * cos(poleLat) * cos(lon'))
       lon_new = atan2(cos(lat) * sin(lon'),
                       sin(lat) * cos(poleLat) - cos(lat) * sin(poleLat) * cos(lon'))
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
                             sinLat * rot.cosPoleLat -
                             cosLat * rot.sinPoleLat * cosDlon)
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
    result.lat := Math.asin(sinLat * rot.sinPoleLat +
                            cosLat * rot.cosPoleLat * cosLon);
    result.lon := GeoCoord.NormalizeLon(
                    rot.poleLon +
                    Math.atan2(cosLat * sinLon,
                               sinLat * rot.cosPoleLat -
                               cosLat * rot.sinPoleLat * cosLon));
    RETURN result
  END RotateInverse;

PROCEDURE FromPole(READONLY pole, eqPoint : GeoCoord.LatLon) : Rotation =
  (* Build rotation from an explicit pole.  The pole becomes the north
     pole of the rotated coordinate system.  lonOffset is set so that
     eqPoint maps to lon=0 on the rotated equator. *)
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
    (* Rotate eqPoint and see where it lands; use that as the offset *)
    eqRot := RotateForward(rot, eqPoint);
    rot.lonOffset := eqRot.lon;
    RETURN rot
  END FromPole;

BEGIN
END GreatCircle.
