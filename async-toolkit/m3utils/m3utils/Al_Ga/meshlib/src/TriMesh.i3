(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE TriMesh;

IMPORT Ply, Vec3;

(* Triangle mesh with computed geometric properties.

   Built from a Ply.T.  Vertex positions are promoted to LONGREAL.
   Per-face normals and areas, per-vertex area-weighted normals, and
   vertex adjacency (1-ring neighbors) are computed on construction. *)

TYPE
  T <: REFANY;

  FaceInfo = RECORD
    normal : Vec3.T;
    area   : LONGREAL;
  END;

PROCEDURE FromPly(READONLY ply: Ply.T): T;
  (* Build a TriMesh from PLY data.  Computes all derived quantities. *)

(* ---- Accessors ---- *)

PROCEDURE NVertices(m: T): CARDINAL;
PROCEDURE NFaces(m: T): CARDINAL;

PROCEDURE GetPosition(m: T; i: CARDINAL): Vec3.T;
  (* Vertex position in LONGREAL. *)

PROCEDURE GetFace(m: T; i: CARDINAL; VAR v0, v1, v2: CARDINAL);
  (* Triangle vertex indices. *)

PROCEDURE GetFaceInfo(m: T; i: CARDINAL): FaceInfo;
  (* Pre-computed face normal and area. *)

PROCEDURE GetVertexNormal(m: T; i: CARDINAL): Vec3.T;
  (* Area-weighted average of incident face normals, normalized. *)

(* ---- Adjacency ---- *)

PROCEDURE NeighborCount(m: T; v: CARDINAL): CARDINAL;
  (* Number of 1-ring neighbors of vertex v. *)

PROCEDURE GetNeighbor(m: T; v: CARDINAL; k: CARDINAL): CARDINAL;
  (* k-th 1-ring neighbor of vertex v (0-based, k < NeighborCount). *)

(* ---- Global properties ---- *)

PROCEDURE Centroid(m: T): Vec3.T;
  (* Area-weighted centroid of all faces. *)

PROCEDURE MeanNormal(m: T): Vec3.T;
  (* Area-weighted mean normal (normalized).  This is the best-fit
     plane normal for the mesh. *)

PROCEDURE TotalArea(m: T): LONGREAL;

END TriMesh.
