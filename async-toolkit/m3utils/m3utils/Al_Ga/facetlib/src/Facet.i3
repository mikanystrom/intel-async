(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE Facet;

IMPORT TriMesh, Vec3;

(* Facet analysis: fit a plane, rotate to z-up, extract height field.

   A Facet.T represents a grain face after coordinate transformation:
   the best-fit plane is at z=0, the facet normal points in +z, and
   vertex positions are expressed in the rotated frame.  The "height"
   of each vertex is its z coordinate in this frame.

   The rotation is computed via Rodrigues' formula.  See:
     Rodrigues, O. (1840), "Des lois geometriques qui regissent les
     deplacements d'un systeme solide dans l'espace", Journal de
     Mathematiques Pures et Appliquees, 5, 380--440.

   Invariants:
     - NVertices(f) = TriMesh.NVertices(mesh) used to construct f
     - GetRotation(f) is orthogonal with determinant +1
     - GetRotation(f) * GetNormal(f) = (0, 0, 1)
     - For all i: GetTransformed(f,i) = R * (p_i - origin)
     - For all i: GetHeight(f,i) = GetTransformed(f,i).z *)

TYPE
  (* 3x3 rotation matrix, row-major: R[row][col]. *)
  Mat3 = ARRAY [0..2] OF ARRAY [0..2] OF LONGREAL;

  T <: REFANY;

PROCEDURE Analyze(mesh: TriMesh.T): T;
  (* Requires: mesh has at least one face with nonzero area.
     Ensures:  computes the area-weighted mean normal, the area-weighted
               centroid, the Rodrigues rotation matrix mapping the normal
               to (0,0,1), and transforms all vertex positions into the
               rotated frame centered at the centroid. *)

(* ---- Accessors ---- *)

PROCEDURE GetRotation(f: T): Mat3;
  (* Ensures: returns the rotation matrix R such that R * n = (0,0,1)
              where n is the best-fit plane normal. *)

PROCEDURE GetOrigin(f: T): Vec3.T;
  (* Ensures: returns the area-weighted centroid in original coordinates.
              This is subtracted from vertex positions before rotation. *)

PROCEDURE GetNormal(f: T): Vec3.T;
  (* Ensures: returns the best-fit plane normal in original coordinates
              (unit length). *)

PROCEDURE NVertices(f: T): CARDINAL;
  (* Ensures: returns the number of vertices. *)

PROCEDURE GetXY(f: T; i: CARDINAL; VAR x, y: LONGREAL);
  (* Requires: i < NVertices(f).
     Modifies: x, y.
     Ensures:  x, y are the first two components of the transformed
               position of vertex i. *)

PROCEDURE GetHeight(f: T; i: CARDINAL): LONGREAL;
  (* Requires: i < NVertices(f).
     Ensures:  returns the z component of the transformed position
               of vertex i (height above the best-fit plane). *)

PROCEDURE GetHeights(f: T): REF ARRAY OF LONGREAL;
  (* Ensures: returns the array of all vertex heights.
              NUMBER(result^) = NVertices(f). *)

PROCEDURE GetTransformed(f: T; i: CARDINAL): Vec3.T;
  (* Requires: i < NVertices(f).
     Ensures:  returns the full (x, y, z) position of vertex i in
               the rotated frame. *)

END Facet.
