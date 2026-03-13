(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE MeshProject;

IMPORT TriMesh, Projection;

TYPE
  BBox = RECORD
    minX, minY, maxX, maxY : LONGREAL;
    empty : BOOLEAN := TRUE;
  END;

PROCEDURE ProjectMesh(VAR mesh : TriMesh.Mesh;
                      proj : Projection.T;
                      discRadius : LONGREAL) : BBox;
  (* Project all mesh vertices via proj.forward(), invert y.
     For disc projections (discRadius > 0): marks vertices on the
     back hemisphere as invalid.
     Returns the bounding box of valid projected vertices. *)

PROCEDURE ExtendBBox(VAR bb : BBox; x, y : LONGREAL);

END MeshProject.
