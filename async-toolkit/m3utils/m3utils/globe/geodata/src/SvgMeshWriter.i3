(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE SvgMeshWriter;

IMPORT Projection, GeoFeature, SvgWriter, Wr;

(* SVG writer using the 3D triangle mesh pipeline.
   Polygons are triangulated on the unit sphere, subdivided, and
   projected per-triangle — eliminating antimeridian artifacts.
   Points and linestrings use simple projection (no mesh). *)

PROCEDURE WriteFile(path : TEXT;
                    READONLY fc : GeoFeature.FeatureCollection;
                    proj : Projection.T;
                    READONLY cfg : SvgWriter.Config);

PROCEDURE WriteWr(wr : Wr.T;
                  READONLY fc : GeoFeature.FeatureCollection;
                  proj : Projection.T;
                  READONLY cfg : SvgWriter.Config);

END SvgMeshWriter.
