(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE HeightGrid;

IMPORT Facet;

(* Regular grid of the height field z(x,y) from a rotated facet.

   Scattered vertex data is binned onto an aspect-ratio-matched grid
   by averaging.  Gaussian smoothing at multiple scales provides a
   multiresolution decomposition (a discrete approximation to the
   Laplacian pyramid of Burt and Adelson, 1983).  Output is
   gnuplot-compatible grid data files.

   References:
     Burt, P.J., Adelson, E.H. (1983), "The Laplacian Pyramid as
     a Compact Image Code", IEEE Trans. Communications, 31(4),
     pp. 532-540.  (Multiresolution pyramid decomposition.)

   Invariants:
     - nx * ny approximately equals nCells
     - nx / ny approximately equals (xMax - xMin) / (yMax - yMin)
     - mask[i][j] = TRUE iff at least one vertex mapped to cell (i,j)
     - grid values in masked cells are nearest-neighbor interpolated
       (for smoothing), but WriteGrid emits NaN for masked cells *)

TYPE
  T <: REFANY;

  Level = RECORD
    sigma : LONGREAL;  (* Gaussian smoothing scale in grid cells; 0 = raw *)
    grid  : REF ARRAY OF ARRAY OF LONGREAL;  (* nx x ny values *)
    nx, ny : CARDINAL;
  END;

PROCEDURE FromFacet(facet: Facet.T; nCells: CARDINAL := 16384): T;
  (* Requires: Facet.NVertices(facet) > 0.
     Ensures:  grids the height field z(x,y) from the rotated facet
               onto a regular grid with approximately nCells total cells,
               aspect ratio matching the bounding box.  Multiple vertices
               falling in the same cell are averaged.  Empty cells are
               filled by iterative nearest-neighbor interpolation and
               marked FALSE in the mask. *)

PROCEDURE FromFacetWithValues(facet: Facet.T;
                              values: REF ARRAY OF LONGREAL;
                              nCells: CARDINAL := 16384): T;
  (* Requires: NUMBER(values^) = Facet.NVertices(facet).
     Ensures:  like FromFacet, but grids the given per-vertex values
               instead of height. *)

PROCEDURE Smooth(g: T; sigma: LONGREAL): Level;
  (* Requires: sigma >= 0.
     Ensures:  returns a Level with the grid convolved by a separable
               Gaussian kernel of standard deviation sigma (in grid cells).
               Kernel is truncated at 3*sigma; boundary uses clamping.
               If sigma < 0.5, returns the raw grid (no smoothing). *)

PROCEDURE MultiRes(g: T; nLevels: CARDINAL := 4): REF ARRAY OF Level;
  (* Requires: nLevels >= 2.
     Ensures:  returns nLevels smoothing levels with geometrically
               spaced sigmas.  Level 0 has the largest sigma (coarsest);
               level nLevels-1 is the raw (unsmoothed) data. *)

PROCEDURE RawLevel(g: T): Level;
  (* Ensures: returns the unsmoothed grid as a Level with sigma = 0. *)

PROCEDURE BandPass(READONLY coarse, fine: Level): Level;
  (* Requires: coarse.nx = fine.nx, coarse.ny = fine.ny.
     Ensures:  returns fine - coarse, representing the spatial
               frequency band between the two smoothing scales. *)

PROCEDURE GetBounds(g: T; VAR xMin, xMax, yMin, yMax: LONGREAL);
  (* Modifies: xMin, xMax, yMin, yMax.
     Ensures:  returns the bounding box of the grid in the facet's
               rotated coordinate system (includes 1% margin). *)

PROCEDURE GetMask(g: T): REF ARRAY OF ARRAY OF BOOLEAN;
  (* Ensures: returns the mask array.  mask[i][j] = TRUE iff cell (i,j)
              received at least one vertex during gridding. *)

PROCEDURE WriteGrid(READONLY lev: Level; path: TEXT;
                    xMin, xMax, yMin, yMax: LONGREAL;
                    xyScale: LONGREAL := 1.0d0;
                    zScale: LONGREAL := 1.0d0;
                    mask: REF ARRAY OF ARRAY OF BOOLEAN := NIL)
    RAISES {GridError};
  (* Requires: path is writable.
     Ensures:  writes grid data in gnuplot splot format (x y z, with
               blank lines between rows of constant x).  Coordinates
               are multiplied by xyScale, values by zScale.  If mask
               is non-NIL, cells where mask[i][j] = FALSE are written
               as NaN (gnuplot treats these as missing data).
     Raises:   GridError if the file cannot be opened or written. *)

PROCEDURE WriteGnuplotScript(path: TEXT;
                             levels: REF ARRAY OF Level;
                             baseName: TEXT;
                             xMin, xMax, yMin, yMax: LONGREAL)
    RAISES {GridError};
  (* Requires: path is writable; levels has at least one element.
     Ensures:  writes a gnuplot script that produces a multiplot of
               contour maps for all levels, rendered to a PDF file.
     Raises:   GridError if the file cannot be opened or written. *)

EXCEPTION GridError(TEXT);

END HeightGrid.
