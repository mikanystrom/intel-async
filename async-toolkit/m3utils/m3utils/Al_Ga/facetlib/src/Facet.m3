(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE Facet;

IMPORT TriMesh, Vec3, Math;

REVEAL T = BRANDED "Facet" REF RECORD
  origin      : Vec3.T;         (* centroid in original coords *)
  normal      : Vec3.T;         (* best-fit plane normal, original coords *)
  rotation    : Mat3;           (* rotation to z-up frame *)
  nVerts      : CARDINAL;
  transformed : REF ARRAY OF Vec3.T;  (* positions in rotated frame *)
  heights     : REF ARRAY OF LONGREAL;
END;

PROCEDURE Analyze(mesh: TriMesh.T): T =
  VAR
    f    := NEW(T);
    nV   := TriMesh.NVertices(mesh);
    orig : Vec3.T;
    centered : Vec3.T;
  BEGIN
    f.nVerts := nV;
    f.origin := TriMesh.Centroid(mesh);
    f.normal := TriMesh.MeanNormal(mesh);
    f.rotation := RotationToZUp(f.normal);
    f.transformed := NEW(REF ARRAY OF Vec3.T, nV);
    f.heights := NEW(REF ARRAY OF LONGREAL, nV);

    FOR i := 0 TO nV - 1 DO
      orig := TriMesh.GetPosition(mesh, i);
      centered := Vec3.Sub(orig, f.origin);
      f.transformed[i] := MatVecMul(f.rotation, centered);
      f.heights[i] := f.transformed[i].z;
    END;

    RETURN f;
  END Analyze;

PROCEDURE RotationToZUp(READONLY n: Vec3.T): Mat3 =
  (* Compute rotation matrix R such that R * n = (0, 0, 1).
     Uses Rodrigues' formula with the rotation axis = n x z_hat,
     and the rotation angle = acos(n . z_hat).
     Special case: if n is already (anti-)parallel to z. *)
  VAR
    zhat := Vec3.T{0.0d0, 0.0d0, 1.0d0};
    cosA := Vec3.Dot(n, zhat);
    axis : Vec3.T;
    sinA : LONGREAL;
    R    : Mat3;
  BEGIN
    IF cosA > 0.999999d0 THEN
      (* Already aligned with +z: identity *)
      RETURN Mat3{ARRAY [0..2] OF LONGREAL{1.0d0, 0.0d0, 0.0d0},
                  ARRAY [0..2] OF LONGREAL{0.0d0, 1.0d0, 0.0d0},
                  ARRAY [0..2] OF LONGREAL{0.0d0, 0.0d0, 1.0d0}};
    END;

    IF cosA < -0.999999d0 THEN
      (* Anti-aligned: rotate 180 degrees around x *)
      RETURN Mat3{ARRAY [0..2] OF LONGREAL{ 1.0d0, 0.0d0,  0.0d0},
                  ARRAY [0..2] OF LONGREAL{ 0.0d0, -1.0d0, 0.0d0},
                  ARRAY [0..2] OF LONGREAL{ 0.0d0, 0.0d0, -1.0d0}};
    END;

    axis := Vec3.Normalize(Vec3.Cross(n, zhat));
    sinA := Math.sqrt(1.0d0 - cosA * cosA);

    (* Rodrigues: R = I + sin(a) K + (1 - cos(a)) K^2
       where K is the skew-symmetric matrix of axis. *)
    VAR
      kx := axis.x;
      ky := axis.y;
      kz := axis.z;
      oneMinusCos := 1.0d0 - cosA;
    BEGIN
      R[0][0] := cosA + kx * kx * oneMinusCos;
      R[0][1] := kx * ky * oneMinusCos - kz * sinA;
      R[0][2] := kx * kz * oneMinusCos + ky * sinA;
      R[1][0] := ky * kx * oneMinusCos + kz * sinA;
      R[1][1] := cosA + ky * ky * oneMinusCos;
      R[1][2] := ky * kz * oneMinusCos - kx * sinA;
      R[2][0] := kz * kx * oneMinusCos - ky * sinA;
      R[2][1] := kz * ky * oneMinusCos + kx * sinA;
      R[2][2] := cosA + kz * kz * oneMinusCos;
    END;

    RETURN R;
  END RotationToZUp;

PROCEDURE MatVecMul(READONLY M: Mat3; READONLY v: Vec3.T): Vec3.T =
  BEGIN
    RETURN Vec3.T{
      M[0][0] * v.x + M[0][1] * v.y + M[0][2] * v.z,
      M[1][0] * v.x + M[1][1] * v.y + M[1][2] * v.z,
      M[2][0] * v.x + M[2][1] * v.y + M[2][2] * v.z};
  END MatVecMul;

(* ---- Accessors ---- *)

PROCEDURE GetRotation(f: T): Mat3 =
  BEGIN RETURN f.rotation; END GetRotation;

PROCEDURE GetOrigin(f: T): Vec3.T =
  BEGIN RETURN f.origin; END GetOrigin;

PROCEDURE GetNormal(f: T): Vec3.T =
  BEGIN RETURN f.normal; END GetNormal;

PROCEDURE NVertices(f: T): CARDINAL =
  BEGIN RETURN f.nVerts; END NVertices;

PROCEDURE GetXY(f: T; i: CARDINAL; VAR x, y: LONGREAL) =
  BEGIN
    x := f.transformed[i].x;
    y := f.transformed[i].y;
  END GetXY;

PROCEDURE GetHeight(f: T; i: CARDINAL): LONGREAL =
  BEGIN RETURN f.heights[i]; END GetHeight;

PROCEDURE GetHeights(f: T): REF ARRAY OF LONGREAL =
  BEGIN RETURN f.heights; END GetHeights;

PROCEDURE GetTransformed(f: T; i: CARDINAL): Vec3.T =
  BEGIN RETURN f.transformed[i]; END GetTransformed;

BEGIN
END Facet.
