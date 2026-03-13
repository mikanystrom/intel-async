(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE MeshProject;

IMPORT TriMesh, Projection, GeoCoord;

PROCEDURE ExtendBBox(VAR bb : BBox; x, y : LONGREAL) =
  BEGIN
    IF bb.empty THEN
      bb.minX := x; bb.maxX := x;
      bb.minY := y; bb.maxY := y;
      bb.empty := FALSE;
    ELSE
      IF x < bb.minX THEN bb.minX := x END;
      IF x > bb.maxX THEN bb.maxX := x END;
      IF y < bb.minY THEN bb.minY := y END;
      IF y > bb.maxY THEN bb.maxY := y END;
    END;
  END ExtendBBox;

PROCEDURE ProjectMesh(VAR mesh : TriMesh.Mesh;
                      proj : Projection.T;
                      discRadius : LONGREAL) : BBox =
  VAR
    bb : BBox;
    v : TriMesh.Vertex;
    xy : GeoCoord.XY;
  BEGIN
    bb.empty := TRUE;

    IF mesh.verts = NIL THEN RETURN bb END;

    (* Project every vertex exactly once *)
    FOR i := 0 TO LAST(mesh.verts^) DO
      v := mesh.verts[i];
      v.valid := proj.forward(v.ll, xy);
      v.xy.x := xy.x;
      v.xy.y := -xy.y;  (* SVG y-axis is inverted *)
      IF v.valid THEN
        ExtendBBox(bb, v.xy.x, v.xy.y);
      ELSIF discRadius <= 0.0d0 THEN
        (* Non-disc projections: recover clamped points (e.g. Mercator
           polar clamp) if their projected coords are reasonable. *)
        IF ABS(v.xy.x) < 50.0d0 AND ABS(v.xy.y) < 50.0d0 THEN
          v.valid := TRUE;
          (* Don't include recovered points in bbox *)
        END;
      END;
    END;

    RETURN bb;
  END ProjectMesh;

BEGIN
END MeshProject.
