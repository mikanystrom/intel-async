(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE Triangulate;

IMPORT GeoFeature, TriMesh;

(* Triangulate GeoJSON polygon rings into a triangle mesh on the unit sphere.
   Each ring is ear-clipped independently; large triangles are subdivided
   so no edge exceeds maxArcLen radians.  Hole rings (CW winding) produce
   CW triangles that cancel outer-ring area under fill-rule="nonzero". *)

PROCEDURE PolygonToMesh(rings : REF ARRAY OF GeoFeature.CoordArray;
                        maxArcLen : LONGREAL) : TriMesh.Mesh;
  (* Triangulate all rings and subdivide.  Returns mesh with shared vertices. *)

PROCEDURE RingToVertices(coords : GeoFeature.CoordArray)
    : REF ARRAY OF TriMesh.Vertex;
  (* Convert LatLon coordinates to Vertex REFs on the unit sphere.
     Strips the GeoJSON closing duplicate if present. *)

END Triangulate.
