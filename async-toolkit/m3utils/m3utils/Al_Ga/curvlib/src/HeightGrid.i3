(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE HeightGrid;

IMPORT Facet;

(* Regular grid of the height field z(x,y) from a rotated facet.

   Scattered vertex data is binned onto an NxN grid by averaging.
   Gaussian smoothing at multiple scales provides a multiresolution
   decomposition.  Output is gnuplot-compatible grid data files. *)

TYPE
  T <: REFANY;

  Level = RECORD
    sigma : LONGREAL;     (* smoothing scale, 0 = raw *)
    grid  : REF ARRAY OF ARRAY OF LONGREAL;
    nx, ny : CARDINAL;
  END;

PROCEDURE FromFacet(facet: Facet.T; nCells: CARDINAL := 16384): T;
  (* Grid the height field from a rotated facet.  The grid dimensions
     are chosen to approximate nCells total cells with aspect ratio
     matching the data bounding box.  Empty cells outside the data
     boundary are masked. *)

PROCEDURE Smooth(g: T; sigma: LONGREAL): Level;
  (* Apply Gaussian smoothing with the given sigma (in grid cells). *)

PROCEDURE MultiRes(g: T; nLevels: CARDINAL := 4): REF ARRAY OF Level;
  (* Generate nLevels smoothing levels from coarse to fine.
     Level 0 is the coarsest (largest sigma), last level is raw data. *)

PROCEDURE RawLevel(g: T): Level;

PROCEDURE BandPass(READONLY coarse, fine: Level): Level;
  (* Compute the difference fine - coarse, representing the
     frequency band between the two smoothing scales. *)

PROCEDURE GetBounds(g: T; VAR xMin, xMax, yMin, yMax: LONGREAL);

PROCEDURE GetMask(g: T): REF ARRAY OF ARRAY OF BOOLEAN;
  (* TRUE for cells that have real vertex data. *)
  (* The unsmoothed grid. *)

PROCEDURE WriteGrid(READONLY lev: Level; path: TEXT;
                    xMin, xMax, yMin, yMax: LONGREAL;
                    xyScale: LONGREAL := 1.0d0;
                    zScale: LONGREAL := 1.0d0;
                    mask: REF ARRAY OF ARRAY OF BOOLEAN := NIL)
    RAISES {GridError};
  (* Write grid data to a file in gnuplot splot format
     (blank-line-separated rows).  Coordinates are multiplied
     by xyScale and values by zScale before writing.
     If mask is provided, cells where mask[i][j] = FALSE are
     written as NaN (gnuplot treats these as missing data). *)

PROCEDURE FromFacetWithValues(facet: Facet.T;
                              values: REF ARRAY OF LONGREAL;
                              nCells: CARDINAL := 16384): T;
  (* Like FromFacet, but grid arbitrary per-vertex values instead
     of height.  values must have NVertices(facet) elements. *)

PROCEDURE WriteGnuplotScript(path: TEXT;
                             levels: REF ARRAY OF Level;
                             baseName: TEXT;
                             xMin, xMax, yMin, yMax: LONGREAL)
    RAISES {GridError};
  (* Write a gnuplot script that plots contour maps of all levels. *)

EXCEPTION GridError(TEXT);

END HeightGrid.
