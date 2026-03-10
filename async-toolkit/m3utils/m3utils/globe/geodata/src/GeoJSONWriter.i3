(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE GeoJSONWriter;

IMPORT Projection, GeoFeature, Wr;

(* GeoJSON writer — projects coordinates through a Projection.T
   and writes GeoJSON output suitable for rendering with D3.js
   using a null/identity projection. *)

PROCEDURE WriteFile(path : TEXT;
                    READONLY fc : GeoFeature.FeatureCollection;
                    proj : Projection.T);
  (* Project all coordinates and write GeoJSON to a file *)

PROCEDURE WriteWr(wr : Wr.T;
                  READONLY fc : GeoFeature.FeatureCollection;
                  proj : Projection.T);
  (* Project all coordinates and write GeoJSON to a writer *)

CONST Brand = "GeoJSONWriter";

END GeoJSONWriter.
