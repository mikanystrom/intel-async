(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE Segment;

IMPORT TriMesh, Vec3;

(* Region-growing segmentation of a triangle mesh into planar facets.

   Each facet is a connected region of vertices whose surface normal
   is within an angular threshold of the region's mean normal.  Seeds
   are selected by priority queue (most unclaimed neighbors first).

   Regions whose mean normal deviates more than maxTiltFromVertical
   degrees from the vertical (z-axis) are discarded.  Small regions
   (below minVertices) are also discarded.

   The algorithm is a standard region-growing approach; see e.g.
   Rabbani, T., van den Heuvel, F., Vosselman, G. (2006),
   "Segmentation of point clouds using smoothness constraint",
   ISPRS, for a survey of related methods. *)

TYPE
  Region = RECORD
    id         : CARDINAL;     (* 0-based, ordered by decreasing nVertices *)
    nVertices  : CARDINAL;     (* number of vertices in this region *)
    meanNormal : Vec3.T;       (* area-weighted mean normal, unit length *)
    tiltAngle  : LONGREAL;     (* angle from vertical in degrees *)
    area       : LONGREAL;     (* total area of faces in this region *)
  END;

  T <: REFANY;

PROCEDURE Run(mesh: TriMesh.T;
              angleThreshold      : LONGREAL := 15.0d0;  (* degrees *)
              minVertices          : CARDINAL := 100;
              maxTiltFromVertical  : LONGREAL := 90.0d0   (* degrees *)
             ): T;
  (* Requires: mesh has valid vertex normals and adjacency.
     Ensures:  segments mesh into planar regions by BFS growth
               from priority-queue-selected seeds.  Returned regions
               satisfy:
                 - each region has >= minVertices vertices
                 - each region's mean normal is within maxTiltFromVertical
                   degrees of (0, 0, 1)
                 - regions are sorted by decreasing vertex count
                 - vertex labels partition the claimed vertices;
                   unclaimed vertices have label -1
     Modifies: nothing (mesh is read-only). *)

(* ---- Accessors ---- *)

PROCEDURE NRegions(s: T): CARDINAL;
  (* Ensures: returns the number of regions found. *)

PROCEDURE GetRegion(s: T; k: CARDINAL): Region;
  (* Requires: k < NRegions(s).
     Ensures:  returns the k-th region record (0 = largest). *)

PROCEDURE GetLabel(s: T; v: CARDINAL): INTEGER;
  (* Requires: v < number of vertices in the original mesh.
     Ensures:  returns the region id (0-based) for vertex v,
               or -1 if v was not assigned to any region. *)

PROCEDURE GetRegionVertices(s: T; k: CARDINAL): REF ARRAY OF CARDINAL;
  (* Requires: k < NRegions(s).
     Ensures:  returns an array of all vertex indices belonging
               to region k.  NUMBER(result^) = GetRegion(s,k).nVertices. *)

PROCEDURE GetRegionFaces(s: T; k: CARDINAL; mesh: TriMesh.T)
    : REF ARRAY OF CARDINAL;
  (* Requires: k < NRegions(s); mesh is the same mesh used in Run.
     Ensures:  returns an array of face indices where all three
               vertices belong to region k. *)

END Segment.
