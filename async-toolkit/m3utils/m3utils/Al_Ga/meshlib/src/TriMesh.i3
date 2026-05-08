(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE TriMesh;

IMPORT Ply, Vec3;

(* Triangle mesh with computed geometric properties.

   Built from a Ply.T.  Vertex positions are promoted to LONGREAL.
   Per-face normals and areas, per-vertex area-weighted normals, and
   vertex adjacency (1-ring neighbors) are computed eagerly on
   construction.  All accessors are O(1).

   Invariants:
     - NVertices(m) = ply.header.nVertices used to construct m
     - NFaces(m) = ply.header.nFaces used to construct m
     - For all i < NFaces(m): GetFaceInfo(m,i).normal is the
       outward unit normal of face i (or Zero if degenerate)
     - For all v < NVertices(m): GetVertexNormal(m,v) is unit length
       (or Zero if v has no incident faces)
     - Adjacency lists contain no duplicates and are sorted *)

TYPE
  T <: REFANY;

  FaceInfo = RECORD
    normal : Vec3.T;     (* unit outward normal, or Zero if degenerate *)
    area   : LONGREAL;   (* triangle area = |e1 x e2| / 2 *)
  END;

PROCEDURE FromPly(READONLY ply: Ply.T): T;
  (* Requires: ply contains valid vertex and face data.
     Ensures:  returns a TriMesh with all derived quantities computed:
               face normals and areas, vertex normals, 1-ring adjacency,
               centroid, mean normal, total area. *)

(* ---- Accessors ---- *)

PROCEDURE NVertices(m: T): CARDINAL;
  (* Ensures: returns the number of vertices. *)

PROCEDURE NFaces(m: T): CARDINAL;
  (* Ensures: returns the number of triangular faces. *)

PROCEDURE GetPosition(m: T; i: CARDINAL): Vec3.T;
  (* Requires: i < NVertices(m).
     Ensures:  returns the position of vertex i in LONGREAL. *)

PROCEDURE GetFace(m: T; i: CARDINAL; VAR v0, v1, v2: CARDINAL);
  (* Requires: i < NFaces(m).
     Modifies: v0, v1, v2.
     Ensures:  v0, v1, v2 are the three vertex indices of face i. *)

PROCEDURE GetFaceInfo(m: T; i: CARDINAL): FaceInfo;
  (* Requires: i < NFaces(m).
     Ensures:  returns the pre-computed normal and area of face i. *)

PROCEDURE GetVertexNormal(m: T; i: CARDINAL): Vec3.T;
  (* Requires: i < NVertices(m).
     Ensures:  returns the area-weighted average of incident face
               normals, normalized to unit length. *)

(* ---- Adjacency ---- *)

PROCEDURE NeighborCount(m: T; v: CARDINAL): CARDINAL;
  (* Requires: v < NVertices(m).
     Ensures:  returns the number of 1-ring neighbors of vertex v. *)

PROCEDURE GetNeighbor(m: T; v: CARDINAL; k: CARDINAL): CARDINAL;
  (* Requires: v < NVertices(m), k < NeighborCount(m, v).
     Ensures:  returns the vertex index of the k-th 1-ring neighbor
               of v (0-based). *)

(* ---- Global properties ---- *)

PROCEDURE Centroid(m: T): Vec3.T;
  (* Ensures: returns the area-weighted centroid of all faces,
              i.e. sum(A_f * c_f) / sum(A_f) where c_f is the
              centroid of face f. *)

PROCEDURE MeanNormal(m: T): Vec3.T;
  (* Ensures: returns the area-weighted mean of all face normals,
              normalized.  This is the best-fit plane normal for the
              mesh surface. *)

PROCEDURE TotalArea(m: T): LONGREAL;
  (* Ensures: returns the sum of all face areas. *)

END TriMesh.
