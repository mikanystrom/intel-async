(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE Facet;

IMPORT TriMesh, Vec3;

(* Facet analysis: fit a plane, rotate to z-up, extract height field.

   A Facet.T represents a grain face after coordinate transformation:
   the best-fit plane is at z=0, the facet normal points in +z, and
   vertex positions are expressed in the rotated frame.  The "height"
   of each vertex is its z coordinate in this frame. *)

TYPE
  (* 3x3 rotation matrix, row-major: R[row][col]. *)
  Mat3 = ARRAY [0..2] OF ARRAY [0..2] OF LONGREAL;

  T <: REFANY;

PROCEDURE Analyze(mesh: TriMesh.T): T;
  (* Fit plane, compute rotation, transform all vertices. *)

(* ---- Accessors ---- *)

PROCEDURE GetRotation(f: T): Mat3;
  (* Rotation matrix that maps original coordinates to z-up frame. *)

PROCEDURE GetOrigin(f: T): Vec3.T;
  (* The centroid in original coordinates (subtracted before rotation). *)

PROCEDURE GetNormal(f: T): Vec3.T;
  (* The best-fit plane normal in original coordinates. *)

PROCEDURE NVertices(f: T): CARDINAL;

PROCEDURE GetXY(f: T; i: CARDINAL; VAR x, y: LONGREAL);
  (* Rotated x, y of vertex i. *)

PROCEDURE GetHeight(f: T; i: CARDINAL): LONGREAL;
  (* z coordinate of vertex i in the rotated frame. *)

PROCEDURE GetHeights(f: T): REF ARRAY OF LONGREAL;
  (* All vertex heights. *)

PROCEDURE GetTransformed(f: T; i: CARDINAL): Vec3.T;
  (* Full (x, y, z) in the rotated frame. *)

END Facet.
