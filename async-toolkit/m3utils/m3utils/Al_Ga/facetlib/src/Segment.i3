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
   (below minVertices) are also discarded. *)

TYPE
  Region = RECORD
    id         : CARDINAL;
    nVertices  : CARDINAL;
    meanNormal : Vec3.T;
    tiltAngle  : LONGREAL;  (* degrees from vertical *)
    area       : LONGREAL;
  END;

  T <: REFANY;

PROCEDURE Run(mesh: TriMesh.T;
              angleThreshold      : LONGREAL := 15.0d0;  (* degrees *)
              minVertices          : CARDINAL := 100;
              maxTiltFromVertical  : LONGREAL := 90.0d0   (* degrees *)
             ): T;
  (* Segment mesh into planar regions.
     angleThreshold: max angle between vertex normal and region mean
       normal for inclusion.
     minVertices: regions smaller than this are discarded.
     maxTiltFromVertical: regions whose mean normal is more than this
       many degrees from the z-axis are discarded.  Default 90 = keep all. *)

(* ---- Accessors ---- *)

PROCEDURE NRegions(s: T): CARDINAL;
PROCEDURE GetRegion(s: T; k: CARDINAL): Region;
PROCEDURE GetLabel(s: T; v: CARDINAL): INTEGER;
PROCEDURE GetRegionVertices(s: T; k: CARDINAL): REF ARRAY OF CARDINAL;
PROCEDURE GetRegionFaces(s: T; k: CARDINAL; mesh: TriMesh.T)
    : REF ARRAY OF CARDINAL;

END Segment.
