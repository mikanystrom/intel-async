(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE HeightGrid;

IMPORT Facet, Math, Wr, FileWr, OSError, Fmt, Thread;

<*FATAL Thread.Alerted*>

REVEAL T = BRANDED "HeightGrid" REF RECORD
  nx, ny   : CARDINAL;
  xMin, xMax, yMin, yMax : LONGREAL;
  dx, dy   : LONGREAL;    (* cell size *)
  grid     : REF ARRAY OF ARRAY OF LONGREAL;
  count    : REF ARRAY OF ARRAY OF CARDINAL;  (* hits per cell *)
  mask     : REF ARRAY OF ARRAY OF BOOLEAN;   (* TRUE = has real data *)
END;

PROCEDURE SetupGrid(g: T; facet: Facet.T; nCells: CARDINAL) =
  (* Compute bounding box, choose nx/ny to match aspect ratio,
     allocate arrays. *)
  VAR
    nV := Facet.NVertices(facet);
    x, y : LONGREAL;
    xRange, yRange, aspect, cellSize : LONGREAL;
  BEGIN
    Facet.GetXY(facet, 0, x, y);
    g.xMin := x; g.xMax := x;
    g.yMin := y; g.yMax := y;
    FOR i := 1 TO nV - 1 DO
      Facet.GetXY(facet, i, x, y);
      IF x < g.xMin THEN g.xMin := x; END;
      IF x > g.xMax THEN g.xMax := x; END;
      IF y < g.yMin THEN g.yMin := y; END;
      IF y > g.yMax THEN g.yMax := y; END;
    END;

    VAR
      mx := (g.xMax - g.xMin) * 0.01d0;
      my := (g.yMax - g.yMin) * 0.01d0;
    BEGIN
      g.xMin := g.xMin - mx;  g.xMax := g.xMax + mx;
      g.yMin := g.yMin - my;  g.yMax := g.yMax + my;
    END;

    xRange := g.xMax - g.xMin;
    yRange := g.yMax - g.yMin;
    aspect := xRange / MAX(yRange, 1.0d0);

    (* Choose nx, ny so nx * ny ~ nCells and nx/ny ~ aspect *)
    cellSize := Math.sqrt(xRange * yRange / FLOAT(nCells, LONGREAL));
    g.nx := MAX(4, ROUND(xRange / cellSize));
    g.ny := MAX(4, ROUND(yRange / cellSize));

    g.dx := xRange / FLOAT(g.nx, LONGREAL);
    g.dy := yRange / FLOAT(g.ny, LONGREAL);

    g.grid := NEW(REF ARRAY OF ARRAY OF LONGREAL, g.nx, g.ny);
    g.count := NEW(REF ARRAY OF ARRAY OF CARDINAL, g.nx, g.ny);
    g.mask := NEW(REF ARRAY OF ARRAY OF BOOLEAN, g.nx, g.ny);
    FOR i := 0 TO g.nx - 1 DO
      FOR j := 0 TO g.ny - 1 DO
        g.grid[i][j] := 0.0d0;
        g.count[i][j] := 0;
        g.mask[i][j] := FALSE;
      END;
    END;
  END SetupGrid;

PROCEDURE BinVertex(g: T; x, y, val: LONGREAL) =
  VAR
    ix := TRUNC((x - g.xMin) / g.dx);
    iy := TRUNC((y - g.yMin) / g.dy);
  BEGIN
    IF ix >= g.nx THEN ix := g.nx - 1; END;
    IF iy >= g.ny THEN iy := g.ny - 1; END;
    IF ix < 0 THEN ix := 0; END;
    IF iy < 0 THEN iy := 0; END;
    g.grid[ix][iy] := g.grid[ix][iy] + val;
    INC(g.count[ix][iy]);
  END BinVertex;

PROCEDURE FinalizeGrid(g: T) =
  BEGIN
    FOR i := 0 TO g.nx - 1 DO
      FOR j := 0 TO g.ny - 1 DO
        g.mask[i][j] := g.count[i][j] > 0;
        IF g.count[i][j] > 0 THEN
          g.grid[i][j] := g.grid[i][j] / FLOAT(g.count[i][j], LONGREAL);
        END;
      END;
    END;
    FillEmpty(g);
  END FinalizeGrid;

PROCEDURE FromFacet(facet: Facet.T; nCells: CARDINAL := 16384): T =
  VAR
    g  := NEW(T);
    nV := Facet.NVertices(facet);
    x, y : LONGREAL;
  BEGIN
    SetupGrid(g, facet, nCells);
    FOR v := 0 TO nV - 1 DO
      Facet.GetXY(facet, v, x, y);
      BinVertex(g, x, y, Facet.GetHeight(facet, v));
    END;
    FinalizeGrid(g);
    RETURN g;
  END FromFacet;

PROCEDURE FromFacetWithValues(facet: Facet.T;
                              values: REF ARRAY OF LONGREAL;
                              nCells: CARDINAL := 16384): T =
  VAR
    g  := NEW(T);
    nV := Facet.NVertices(facet);
    x, y : LONGREAL;
  BEGIN
    SetupGrid(g, facet, nCells);
    FOR v := 0 TO nV - 1 DO
      Facet.GetXY(facet, v, x, y);
      BinVertex(g, x, y, values[v]);
    END;
    FinalizeGrid(g);
    RETURN g;
  END FromFacetWithValues;

PROCEDURE FillEmpty(g: T) =
  VAR
    changed := TRUE;
    nx := g.nx;
    ny := g.ny;
    sum : LONGREAL;
    cnt : CARDINAL;
  BEGIN
    WHILE changed DO
      changed := FALSE;
      FOR i := 0 TO nx - 1 DO
        FOR j := 0 TO ny - 1 DO
          IF g.count[i][j] = 0 THEN
            sum := 0.0d0; cnt := 0;
            IF i > 0 AND g.count[i-1][j] > 0 THEN
              sum := sum + g.grid[i-1][j]; INC(cnt);
            END;
            IF i < nx-1 AND g.count[i+1][j] > 0 THEN
              sum := sum + g.grid[i+1][j]; INC(cnt);
            END;
            IF j > 0 AND g.count[i][j-1] > 0 THEN
              sum := sum + g.grid[i][j-1]; INC(cnt);
            END;
            IF j < ny-1 AND g.count[i][j+1] > 0 THEN
              sum := sum + g.grid[i][j+1]; INC(cnt);
            END;
            IF cnt > 0 THEN
              g.grid[i][j] := sum / FLOAT(cnt, LONGREAL);
              g.count[i][j] := 1;
              changed := TRUE;
            END;
          END;
        END;
      END;
    END;
  END FillEmpty;

PROCEDURE Smooth(g: T; sigma: LONGREAL): Level =
  VAR
    lev : Level;
    nx  := g.nx;
    ny  := g.ny;
    radius : CARDINAL;
    tmp := NEW(REF ARRAY OF ARRAY OF LONGREAL, nx, ny);
    kernel : REF ARRAY OF LONGREAL;
    ksum, val : LONGREAL;
  BEGIN
    lev.sigma := sigma;
    lev.nx := nx;
    lev.ny := ny;
    lev.grid := NEW(REF ARRAY OF ARRAY OF LONGREAL, nx, ny);

    IF sigma < 0.5d0 THEN
      FOR i := 0 TO nx - 1 DO
        FOR j := 0 TO ny - 1 DO
          lev.grid[i][j] := g.grid[i][j];
        END;
      END;
      RETURN lev;
    END;

    radius := ROUND(3.0d0 * sigma);
    IF radius < 1 THEN radius := 1; END;
    kernel := NEW(REF ARRAY OF LONGREAL, 2 * radius + 1);
    ksum := 0.0d0;
    FOR k := 0 TO 2 * radius DO
      VAR d := FLOAT(k, LONGREAL) - FLOAT(radius, LONGREAL); BEGIN
        kernel[k] := Math.exp(-d * d / (2.0d0 * sigma * sigma));
        ksum := ksum + kernel[k];
      END;
    END;
    FOR k := 0 TO 2 * radius DO
      kernel[k] := kernel[k] / ksum;
    END;

    (* Separable convolution: horizontal pass (along j / y) *)
    FOR i := 0 TO nx - 1 DO
      FOR j := 0 TO ny - 1 DO
        val := 0.0d0;
        FOR k := 0 TO 2 * radius DO
          VAR jj := j + k - radius; BEGIN
            IF jj < 0 THEN jj := 0; END;
            IF jj >= ny THEN jj := ny - 1; END;
            val := val + kernel[k] * g.grid[i][jj];
          END;
        END;
        tmp[i][j] := val;
      END;
    END;

    (* Vertical pass (along i / x) *)
    FOR i := 0 TO nx - 1 DO
      FOR j := 0 TO ny - 1 DO
        val := 0.0d0;
        FOR k := 0 TO 2 * radius DO
          VAR ii := i + k - radius; BEGIN
            IF ii < 0 THEN ii := 0; END;
            IF ii >= nx THEN ii := nx - 1; END;
            val := val + kernel[k] * tmp[ii][j];
          END;
        END;
        lev.grid[i][j] := val;
      END;
    END;

    RETURN lev;
  END Smooth;

PROCEDURE MultiRes(g: T; nLevels: CARDINAL := 4): REF ARRAY OF Level =
  VAR
    levels := NEW(REF ARRAY OF Level, nLevels);
    maxSigma := FLOAT(MIN(g.nx, g.ny), LONGREAL) / 4.0d0;
  BEGIN
    FOR k := 0 TO nLevels - 1 DO
      IF k = nLevels - 1 THEN
        (* Finest level: raw data *)
        levels[k] := RawLevel(g);
      ELSE
        (* Exponentially spaced sigmas from coarse to fine *)
        VAR
          frac := FLOAT(k, LONGREAL) / FLOAT(nLevels - 1, LONGREAL);
          sigma := maxSigma * Math.exp(-frac * Math.log(maxSigma / 0.5d0));
        BEGIN
          levels[k] := Smooth(g, sigma);
        END;
      END;
    END;
    RETURN levels;
  END MultiRes;

PROCEDURE RawLevel(g: T): Level =
  BEGIN
    RETURN Smooth(g, 0.0d0);
  END RawLevel;

PROCEDURE BandPass(READONLY coarse, fine: Level): Level =
  VAR
    lev : Level;
    nx := fine.nx;
    ny := fine.ny;
  BEGIN
    lev.sigma := fine.sigma;
    lev.nx := nx;
    lev.ny := ny;
    lev.grid := NEW(REF ARRAY OF ARRAY OF LONGREAL, nx, ny);
    FOR i := 0 TO nx - 1 DO
      FOR j := 0 TO ny - 1 DO
        lev.grid[i][j] := fine.grid[i][j] - coarse.grid[i][j];
      END;
    END;
    RETURN lev;
  END BandPass;

PROCEDURE GetBounds(g: T; VAR xMin, xMax, yMin, yMax: LONGREAL) =
  BEGIN
    xMin := g.xMin; xMax := g.xMax;
    yMin := g.yMin; yMax := g.yMax;
  END GetBounds;

PROCEDURE GetMask(g: T): REF ARRAY OF ARRAY OF BOOLEAN =
  BEGIN RETURN g.mask; END GetMask;

PROCEDURE WriteGrid(READONLY lev: Level; path: TEXT;
                    xMin, xMax, yMin, yMax: LONGREAL;
                    xyScale: LONGREAL := 1.0d0;
                    zScale: LONGREAL := 1.0d0;
                    mask: REF ARRAY OF ARRAY OF BOOLEAN := NIL)
    RAISES {GridError} =
  VAR
    wr : Wr.T;
    nx := lev.nx;
    ny := lev.ny;
    dx := (xMax - xMin) / FLOAT(nx, LONGREAL);
    dy := (yMax - yMin) / FLOAT(ny, LONGREAL);
  BEGIN
    TRY
      wr := FileWr.Open(path);
    EXCEPT
    | OSError.E =>
        RAISE GridError("cannot open: " & path);
    END;
    TRY
      FOR i := 0 TO nx - 1 DO
        VAR x := (xMin + (FLOAT(i, LONGREAL) + 0.5d0) * dx) * xyScale; BEGIN
          FOR j := 0 TO ny - 1 DO
            VAR y := (yMin + (FLOAT(j, LONGREAL) + 0.5d0) * dy) * xyScale; BEGIN
              IF mask # NIL AND NOT mask[i][j] THEN
                Wr.PutText(wr, Fmt.LongReal(x) & " "
                             & Fmt.LongReal(y) & " NaN\n");
              ELSE
                Wr.PutText(wr, Fmt.LongReal(x) & " "
                             & Fmt.LongReal(y) & " "
                             & Fmt.LongReal(lev.grid[i][j] * zScale) & "\n");
              END;
            END;
          END;
          Wr.PutText(wr, "\n");
        END;
      END;
      Wr.Close(wr);
    EXCEPT
    | Wr.Failure =>
        RAISE GridError("write error: " & path);
    END;
  END WriteGrid;

PROCEDURE WriteGnuplotScript(path: TEXT;
                             levels: REF ARRAY OF Level;
                             baseName: TEXT;
                             xMin, xMax, yMin, yMax: LONGREAL)
    RAISES {GridError} =
  VAR
    wr : Wr.T;
    nL := NUMBER(levels^);
  BEGIN
    TRY
      wr := FileWr.Open(path);
    EXCEPT
    | OSError.E =>
        RAISE GridError("cannot open: " & path);
    END;
    TRY
      Wr.PutText(wr, "# Multiresolution contour plot\n");
      Wr.PutText(wr, "# Generated by plydemo\n\n");
      Wr.PutText(wr, "set terminal pdfcairo size 12,"
                    & Fmt.Int(4 * nL) & " font ',10'\n");
      Wr.PutText(wr, "set output '" & baseName & "_contours.pdf'\n\n");

      Wr.PutText(wr, "set multiplot layout "
                    & Fmt.Int(nL) & ",1\n\n");

      Wr.PutText(wr, "set view map\n");
      Wr.PutText(wr, "set contour base\n");
      Wr.PutText(wr, "unset surface\n");
      Wr.PutText(wr, "set cntrparam levels auto 20\n");
      Wr.PutText(wr, "set xrange [" & Fmt.LongReal(xMin) & ":"
                    & Fmt.LongReal(xMax) & "]\n");
      Wr.PutText(wr, "set yrange [" & Fmt.LongReal(yMin) & ":"
                    & Fmt.LongReal(yMax) & "]\n");
      Wr.PutText(wr, "unset key\n");
      Wr.PutText(wr, "unset clabel\n");
      Wr.PutText(wr, "set format z ''\n\n");

      FOR k := 0 TO nL - 1 DO
        VAR
          dataFile := baseName & "_level" & Fmt.Int(k) & ".dat";
          sigmaStr : TEXT;
        BEGIN
          IF k = nL - 1 THEN
            sigmaStr := "raw";
          ELSE
            sigmaStr := "sigma=" & Fmt.LongReal(levels[k].sigma, prec := 1);
          END;
          Wr.PutText(wr, "set title 'Level " & Fmt.Int(k)
                        & " (" & sigmaStr & ")'\n");
          Wr.PutText(wr, "splot '" & dataFile & "' with lines lc 'black'\n\n");
        END;
      END;

      Wr.PutText(wr, "unset multiplot\n");
      Wr.Close(wr);
    EXCEPT
    | Wr.Failure =>
        RAISE GridError("write error: " & path);
    END;
  END WriteGnuplotScript;

BEGIN
END HeightGrid.
