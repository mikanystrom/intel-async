(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE SvgWriter;

IMPORT Projection, GeoCoord, GeoFeature, Wr;

TYPE
  Marker = RECORD
    loc   : GeoCoord.LatLon;  (* position in radians *)
    label : TEXT;              (* display label, e.g. "LHR" *)
  END;

  MarkerArray = REF ARRAY OF Marker;

  Config = RECORD
    width       : CARDINAL := 1024;
    height      : CARDINAL := 512;
    margin      : LONGREAL := 10.0d0;
    strokeWidth : LONGREAL := 0.5d0;
    stroke      : TEXT     := "#333333";
    fill        : TEXT     := "none";
    background  : TEXT     := "#ffffff";
    pointRadius : LONGREAL := 2.0d0;
    discRadius  : LONGREAL := 0.0d0;
    (* When discRadius > 0, the projection is bounded to a disc of that
       radius in projected coordinates.  A filled circle is drawn as the
       ocean/globe, features are clipped to it, and the area outside the
       disc is rendered as dark space. *)
    showMesh    : BOOLEAN  := FALSE;
    (* When TRUE, render individual triangles with visible edges and IDs
       for debugging.  When FALSE, hide mesh seams and show outlines. *)
    mercatorMinLat : LONGREAL := 0.0d0;
    mercatorMaxLat : LONGREAL := 0.0d0;
    (* Override bbox y-bounds using the Mercator formula at the given
       latitudes (degrees).  0.0 means "no limit".  Typical: -85/+85.
       Relative to the projection's equator, not Earth's equator. *)
    markers     : MarkerArray := NIL;
    (* Airport or point-of-interest markers to render as dots + labels *)
  END;

PROCEDURE WriteFile(path : TEXT;
                    READONLY fc : GeoFeature.FeatureCollection;
                    proj : Projection.T;
                    READONLY cfg : Config);

PROCEDURE WriteWr(wr : Wr.T;
                  READONLY fc : GeoFeature.FeatureCollection;
                  proj : Projection.T;
                  READONLY cfg : Config);

END SvgWriter.
