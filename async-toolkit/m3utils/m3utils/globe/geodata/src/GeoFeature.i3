(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE GeoFeature;

IMPORT GeoCoord;

(* GIS feature/geometry types for map data *)

TYPE
  (* A ring of coordinates (for linestrings and polygon boundaries) *)
  CoordArray = REF ARRAY OF GeoCoord.LatLon;

  GeometryKind = { Point, LineString, Polygon, MultiPoint,
                   MultiLineString, MultiPolygon };

  (* A single geometry *)
  Geometry = RECORD
    kind   : GeometryKind;
    coords : CoordArray;         (* for Point: 1 element; LineString: N elements *)
    rings  : REF ARRAY OF CoordArray;  (* for Polygon: outer ring + holes;
                                          for Multi* types: array of sub-geometries *)
  END;

  (* A feature = geometry + properties *)
  Feature = RECORD
    geometry   : Geometry;
    name       : TEXT;       (* from properties.NAME or properties.name, if available *)
    cssClass   : TEXT;       (* extra CSS class for SVG styling, e.g. "secondary" *)
    properties : TEXT;       (* raw JSON properties text for pass-through *)
  END;

  FeatureArray = REF ARRAY OF Feature;

  (* A collection of features *)
  FeatureCollection = RECORD
    features : FeatureArray;
  END;

CONST Brand = "GeoFeature";

END GeoFeature.
