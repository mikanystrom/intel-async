(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE GeoJSON;

IMPORT GeoFeature;

(* GeoJSON reader — parses GeoJSON files into GeoFeature structures.
   Uses the CM3 json library for parsing. *)

EXCEPTION Error(TEXT);

PROCEDURE ReadFile(path : TEXT) : GeoFeature.FeatureCollection RAISES {Error};
  (* Read a GeoJSON file and return a FeatureCollection *)

PROCEDURE ReadText(text : TEXT) : GeoFeature.FeatureCollection RAISES {Error};
  (* Parse a GeoJSON text string *)

CONST Brand = "GeoJSON";

END GeoJSON.
