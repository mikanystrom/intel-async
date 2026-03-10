(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE GreatCircle;

IMPORT GeoCoord;

(* Great circle utilities and coordinate rotation.
   Used by Oblique to rotate coordinates so an arbitrary great circle
   becomes the equator. *)

PROCEDURE Distance(READONLY a, b : GeoCoord.LatLon) : LONGREAL;
  (* Central angle in radians between two points on the unit sphere *)

PROCEDURE Cross(READONLY a, b : GeoCoord.XYZ) : GeoCoord.XYZ;
  (* Cross product of two 3D vectors *)

PROCEDURE Normalize(READONLY p : GeoCoord.XYZ) : GeoCoord.XYZ;
  (* Normalize a 3D vector to unit length *)

PROCEDURE Dot(READONLY a, b : GeoCoord.XYZ) : LONGREAL;
  (* Dot product *)

(* Rotation matrix for oblique projections.
   RotationToEquator computes the pole of the great circle through a and b,
   then provides Forward/Inverse rotation procedures. *)

TYPE
  Rotation = RECORD
    (* New pole as unit vector (cross product of a and b, normalized) *)
    pole : GeoCoord.XYZ;
    (* Precomputed sin/cos of pole's latitude/longitude *)
    sinPoleLat, cosPoleLat : LONGREAL;
    poleLon : LONGREAL;
    (* Additional longitude offset applied after rotation (radians).
       Used by FromPole to place a specific equator point at lon=0. *)
    lonOffset : LONGREAL;
  END;

PROCEDURE ComputeRotation(READONLY a, b : GeoCoord.LatLon) : Rotation;
  (* Compute rotation parameters from two points defining a great circle *)

PROCEDURE FromPole(READONLY pole, eqPoint : GeoCoord.LatLon) : Rotation;
  (* Compute rotation from a pole and a point on the equator.
     The pole becomes the north pole of the rotated system, and
     eqPoint is placed at lon=0 on the rotated equator. *)

PROCEDURE RotateForward(READONLY rot : Rotation;
                        READONLY ll : GeoCoord.LatLon) : GeoCoord.LatLon;
  (* Rotate geographic coordinates: original → rotated frame
     where the great circle through a,b becomes the equator *)

PROCEDURE RotateInverse(READONLY rot : Rotation;
                        READONLY ll : GeoCoord.LatLon) : GeoCoord.LatLon;
  (* Rotate geographic coordinates: rotated frame → original *)

CONST Brand = "GreatCircle";

END GreatCircle.
