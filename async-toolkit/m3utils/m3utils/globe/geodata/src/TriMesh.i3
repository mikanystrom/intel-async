(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE TriMesh;

IMPORT GeoCoord;

(* Triangle mesh types for the 3D rendering pipeline.
   Vertices are shared (REF) so each is projected exactly once. *)

TYPE
  Vertex = REF VertexRec;
  VertexRec = RECORD
    ll    : GeoCoord.LatLon;
    xyz   : GeoCoord.XYZ;       (* unit sphere *)
    xy    : GeoCoord.XY;        (* filled by projection pass *)
    valid : BOOLEAN := FALSE;   (* projection succeeded? *)
    idx   : INTEGER := -1;      (* index in mesh vertex array *)
  END;

  Triangle = RECORD
    v : ARRAY [0..2] OF Vertex;  (* shared refs *)
  END;

  Mesh = RECORD
    tris  : REF ARRAY OF Triangle;
    verts : REF ARRAY OF Vertex;  (* all unique vertices *)
  END;

CONST Brand = "TriMesh";

END TriMesh.
