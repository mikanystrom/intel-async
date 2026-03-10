(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE SvgWriter;

IMPORT Projection, GeoFeature, Wr;

TYPE
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
