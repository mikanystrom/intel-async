(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE Main;

IMPORT Ply, TriMesh, Facet, Curv, Segment, HeightGrid, Vec3;
IMPORT Params, Process, Stdio, Wr, Fmt, Thread, Rd, Text, FileWr, OSError;

<*FATAL Wr.Failure, Rd.Failure, Thread.Alerted, Ply.ParseError*>

PROCEDURE Put(t: TEXT) =
  BEGIN Wr.PutText(Stdio.stdout, t); END Put;

PROCEDURE PutLR(x: LONGREAL; prec: CARDINAL := 6) =
  BEGIN Put(Fmt.LongReal(x, prec := prec)); END PutLR;

PROCEDURE PutLn() =
  BEGIN Put("\n"); END PutLn;

PROCEDURE Run() =
  VAR
    path    : TEXT;
    ply     : Ply.T;
    mesh    : TriMesh.T;
    doSegment := FALSE;
    doContour := FALSE;
    contourOut : TEXT := NIL;
    angleThresh := 15.0d0;
    minVerts : CARDINAL := 100;
    anomalyThresh := 3.0d0;
    maxTilt := 30.0d0;
    nCells : CARDINAL := 16384;
    nLevels : CARDINAL := 4;
    xyScale : LONGREAL := 0.001d0;  (* nm to um by default *)
  BEGIN
    IF Params.Count < 2 THEN
      Wr.PutText(Stdio.stderr,
        "usage: plydemo [options] <file.ply>\n" &
        "  -segment            segment surface into grain faces\n" &
        "  -contour <outdir>   write multiresolution contour plots\n" &
        "  -ncells <n>         approx grid cells (default 16384)\n" &
        "  -levels <n>         number of resolution levels (default 4)\n" &
        "  -angle <degrees>    normal angle threshold (default 15)\n" &
        "  -minverts <n>       minimum region size (default 100)\n" &
        "  -maxtilt <degrees>  max tilt from vertical (default 30)\n" &
        "  -threshold <sigma>  anomaly threshold (default 3.0)\n" &
        "  -scale <factor>     xy scale to microns (default 0.001 = nm)\n" &
        "                      use 1.0 if input is already in microns\n");
      Process.Exit(1);
    END;

    (* Parse arguments *)
    VAR i := 1; BEGIN
      WHILE i < Params.Count DO
        VAR arg := Params.Get(i); BEGIN
          IF Text.Equal(arg, "-segment") THEN
            doSegment := TRUE;
          ELSIF Text.Equal(arg, "-contour") AND i + 1 < Params.Count THEN
            INC(i); contourOut := Params.Get(i); doContour := TRUE;
          ELSIF Text.Equal(arg, "-ncells") AND i + 1 < Params.Count THEN
            INC(i); nCells := ROUND(ScanLR(Params.Get(i)));
          ELSIF Text.Equal(arg, "-levels") AND i + 1 < Params.Count THEN
            INC(i); nLevels := ROUND(ScanLR(Params.Get(i)));
          ELSIF Text.Equal(arg, "-angle") AND i + 1 < Params.Count THEN
            INC(i); angleThresh := ScanLR(Params.Get(i));
          ELSIF Text.Equal(arg, "-minverts") AND i + 1 < Params.Count THEN
            INC(i); minVerts := ROUND(ScanLR(Params.Get(i)));
          ELSIF Text.Equal(arg, "-maxtilt") AND i + 1 < Params.Count THEN
            INC(i); maxTilt := ScanLR(Params.Get(i));
          ELSIF Text.Equal(arg, "-threshold") AND i + 1 < Params.Count THEN
            INC(i); anomalyThresh := ScanLR(Params.Get(i));
          ELSIF Text.Equal(arg, "-scale") AND i + 1 < Params.Count THEN
            INC(i); xyScale := ScanLR(Params.Get(i));
          ELSE
            path := arg;
          END;
        END;
        INC(i);
      END;
    END;

    IF path = NIL THEN
      Wr.PutText(Stdio.stderr, "error: no input file\n");
      Process.Exit(1);
    END;

    (* Load *)
    Put("loading: " & path & "\n");
    ply := Ply.ReadFile(path);
    Put("  vertices: " & Fmt.Int(ply.header.nVertices) & "\n");
    Put("  faces:    " & Fmt.Int(ply.header.nFaces) & "\n");

    (* Build mesh *)
    Put("building mesh...\n");
    mesh := TriMesh.FromPly(ply);
    Put("  total area: "); PutLR(TriMesh.TotalArea(mesh)); PutLn();

    IF doContour THEN
      DoContour(mesh, contourOut, nCells, nLevels, xyScale);
    ELSIF doSegment THEN
      DoSegmentation(mesh, angleThresh, anomalyThresh, minVerts, maxTilt);
    ELSE
      DoSingleFace(mesh, anomalyThresh);
    END;
  END Run;

PROCEDURE DoContour(mesh: TriMesh.T; outDir: TEXT;
                    nCells, nLevels: CARDINAL;
                    xyScale: LONGREAL) =
  <*FATAL HeightGrid.GridError*>
  VAR
    facet  : Facet.T;
    hg     : HeightGrid.T;
    levels : REF ARRAY OF HeightGrid.Level;
    n      : Vec3.T;
  BEGIN
    n := TriMesh.MeanNormal(mesh);
    Put("  mean normal: (");
    PutLR(n.x, 4); Put(", "); PutLR(n.y, 4); Put(", "); PutLR(n.z, 4);
    Put(")\n");

    Put("fitting plane, rotating to z-up...\n");
    facet := Facet.Analyze(mesh);

    Put("gridding height field (~" & Fmt.Int(nCells) & " cells)...\n");
    hg := HeightGrid.FromFacet(facet, nCells);

    Put("computing " & Fmt.Int(nLevels) & " resolution levels...\n");
    levels := HeightGrid.MultiRes(hg, nLevels);

    (* Also compute curvature and residual grids *)
    Put("computing curvature...\n");
    VAR
      curv := Curv.Analyze(mesh, facet, 3.0d0);
      curvGrid := HeightGrid.FromFacetWithValues(
                    facet, Curv.GetCurvatures(curv), nCells);
      residGrid := HeightGrid.FromFacetWithValues(
                    facet, Curv.GetResiduals(curv), nCells);
      curvSmooth := HeightGrid.Smooth(curvGrid, 2.0d0);
    BEGIN
      VAR
        baseName := outDir & "/face";
        xMin, xMax, yMin, yMax : LONGREAL;
      BEGIN
        HeightGrid.GetBounds(hg, xMin, xMax, yMin, yMax);

        (* Scale to microns for display; curvature to 1/mm *)
        VAR
          s  := xyScale;
          mk := HeightGrid.GetMask(hg);
        BEGIN
          FOR k := 0 TO nLevels - 1 DO
            VAR dataFile := baseName & "_level" & Fmt.Int(k) & ".dat"; BEGIN
              Put("  writing " & dataFile & "\n");
              HeightGrid.WriteGrid(levels[k], dataFile,
                                   xMin, xMax, yMin, yMax,
                                   xyScale := s, zScale := s,
                                   mask := mk);
            END;
          END;

          VAR curvFile := baseName & "_curvature.dat"; BEGIN
            Put("  writing " & curvFile & "\n");
            (* curvature is 1/input_unit, scale to 1/mm for display *)
            HeightGrid.WriteGrid(curvSmooth, curvFile,
                                 xMin, xMax, yMin, yMax,
                                 xyScale := s, zScale := 1.0d3 / s,
                                 mask := mk);
          END;

          VAR residFile := baseName & "_residual.dat"; BEGIN
            Put("  writing " & residFile & "\n");
            HeightGrid.WriteGrid(HeightGrid.RawLevel(residGrid), residFile,
                                 xMin, xMax, yMin, yMax,
                                 xyScale := s, zScale := s,
                                 mask := mk);
          END;

          (* Band-pass decomposition: difference between successive levels *)
          FOR k := 0 TO nLevels - 2 DO
            VAR
              band := HeightGrid.BandPass(levels[k], levels[k + 1]);
              bandFile := baseName & "_band" & Fmt.Int(k) & ".dat";
            BEGIN
              Put("  writing " & bandFile & "\n");
              HeightGrid.WriteGrid(band, bandFile,
                                   xMin, xMax, yMin, yMax,
                                   xyScale := s, zScale := s,
                                   mask := mk);
            END;
          END;

          (* Anomaly points file *)
          VAR
            nA := Curv.NAnomalies(curv);
            anomFile := baseName & "_anomalies.dat";
          BEGIN
            Put("  writing " & anomFile
                  & " (" & Fmt.Int(nA) & " points)\n");
            WriteAnomalyFile(anomFile, curv, s);
          END;
        END;

        VAR scriptPath := baseName & "_contours.gp"; BEGIN
          Put("  writing " & scriptPath & "\n");
          HeightGrid.WriteGnuplotScript(scriptPath, levels, baseName,
                                        xMin, xMax, yMin, yMax);
        END;
      END;
    END;

    Put("done. Run: gnuplot " & outDir & "/face_contours.gp\n");
  END DoContour;

PROCEDURE DoSingleFace(mesh: TriMesh.T; threshold: LONGREAL) =
  VAR
    facet : Facet.T;
    curv  : Curv.T;
    stats : Curv.Stats;
    n     : Vec3.T;
    a     : Curv.Anomaly;
  BEGIN
    n := TriMesh.MeanNormal(mesh);
    Put("  mean normal: (");
    PutLR(n.x, 4); Put(", "); PutLR(n.y, 4); Put(", "); PutLR(n.z, 4);
    Put(")\n");

    Put("fitting plane, rotating to z-up...\n");
    facet := Facet.Analyze(mesh);

    VAR heights := Facet.GetHeights(facet);
        hMin, hMax : LONGREAL;
        nV := Facet.NVertices(facet);
    BEGIN
      hMin := heights[0]; hMax := heights[0];
      FOR i := 1 TO nV - 1 DO
        IF heights[i] < hMin THEN hMin := heights[i]; END;
        IF heights[i] > hMax THEN hMax := heights[i]; END;
      END;
      Put("  height range: "); PutLR(hMin, 2);
      Put(" .. "); PutLR(hMax, 2); PutLn();
      Put("  height span:  "); PutLR(hMax - hMin, 2); PutLn();
    END;

    Put("computing curvature (threshold = ");
    PutLR(threshold, 1); Put(" sigma)...\n");
    curv := Curv.Analyze(mesh, facet, threshold);
    stats := Curv.GetStats(curv);

    Put("\n=== Curvature Statistics ===\n");
    Put("  mean:  "); PutLR(stats.meanCurv); PutLn();
    Put("  std:   "); PutLR(stats.stdCurv); PutLn();
    Put("  min:   "); PutLR(stats.minCurv); PutLn();
    Put("  max:   "); PutLR(stats.maxCurv); PutLn();

    Put("\n=== Height Residual (after quadratic fit) ===\n");
    Put("  mean:  "); PutLR(stats.meanHeight); PutLn();
    Put("  std:   "); PutLR(stats.stdHeight); PutLn();

    Put("\n=== Anomalies ===\n");
    Put("  detected: " & Fmt.Int(stats.nAnomalies) & " vertices\n");

    IF stats.nAnomalies > 0 THEN
      VAR nShow := MIN(stats.nAnomalies, 10); BEGIN
        Put("  first " & Fmt.Int(nShow) & ":\n");
        FOR k := 0 TO nShow - 1 DO
          a := Curv.GetAnomaly(curv, k);
          Put("    v=" & Fmt.Pad(Fmt.Int(a.vertex), 8));
          Put("  residual="); PutLR(a.height, 2);
          Put("  curv="); PutLR(a.curvature, 4);
          PutLn();
        END;
      END;
    END;
  END DoSingleFace;

PROCEDURE DoSegmentation(mesh: TriMesh.T;
                         angleThresh, anomalyThresh: LONGREAL;
                         minVerts: CARDINAL;
                         maxTilt: LONGREAL) =
  VAR
    seg : Segment.T;
    nR  : CARDINAL;
    r   : Segment.Region;
    n   : Vec3.T;
  BEGIN
    Put("\nsegmenting (angle="); PutLR(angleThresh, 1);
    Put(" deg, minVerts=" & Fmt.Int(minVerts));
    Put(", maxTilt="); PutLR(maxTilt, 1); Put(" deg)...\n");

    seg := Segment.Run(mesh, angleThresh, minVerts, maxTilt);
    nR := Segment.NRegions(seg);

    Put("  found " & Fmt.Int(nR) & " regions\n\n");

    (* Summary table *)
    Put("  region  vertices    area          tilt    normal\n");
    Put("  ------  --------    ----          ----    ------\n");
    FOR k := 0 TO nR - 1 DO
      r := Segment.GetRegion(seg, k);
      n := r.meanNormal;
      Put("  " & Fmt.Pad(Fmt.Int(k), 6));
      Put("  " & Fmt.Pad(Fmt.Int(r.nVertices), 8));
      Put("    "); PutLR(r.area, 4);
      Put("  "); PutLR(r.tiltAngle, 1); Put("d");
      Put("  ("); PutLR(n.x, 3); Put(", "); PutLR(n.y, 3);
      Put(", "); PutLR(n.z, 3); Put(")");
      PutLn();
    END;

    (* Analyze each region *)
    Put("\n=== Per-region analysis ===\n");
    FOR k := 0 TO MIN(nR, 10) - 1 DO
      r := Segment.GetRegion(seg, k);
      Put("\n--- Region " & Fmt.Int(k)
            & " (" & Fmt.Int(r.nVertices) & " vertices) ---\n");
      AnalyzeRegion(mesh, seg, k, anomalyThresh);
    END;

    IF nR > 10 THEN
      Put("\n(" & Fmt.Int(nR - 10) & " more regions not shown)\n");
    END;
  END DoSegmentation;

PROCEDURE AnalyzeRegion(mesh: TriMesh.T; seg: Segment.T;
                        k: CARDINAL; threshold: LONGREAL) =
  (* Build a sub-mesh from region k's faces and run the full
     facet + curvature pipeline on it. *)
  VAR
    faceIdxs := Segment.GetRegionFaces(seg, k, mesh);
    nF := NUMBER(faceIdxs^);
    vertIdxs := Segment.GetRegionVertices(seg, k);
    nV := NUMBER(vertIdxs^);
    (* Build vertex remap: old index -> new dense index *)
    remap := NEW(REF ARRAY OF INTEGER, TriMesh.NVertices(mesh));
    subPly : Ply.T;
    subMesh : TriMesh.T;
    facet : Facet.T;
    curv : Curv.T;
    stats : Curv.Stats;
    v0, v1, v2 : CARDINAL;
  BEGIN
    FOR i := 0 TO TriMesh.NVertices(mesh) - 1 DO remap[i] := -1; END;
    FOR i := 0 TO nV - 1 DO remap[vertIdxs[i]] := i; END;

    (* Build a minimal Ply.T for the sub-region *)
    subPly.header.nVertices := nV;
    subPly.header.nFaces := nF;
    subPly.header.nFloatProps := 3;
    subPly.header.nAllProps := 3;
    subPly.header.properties := NEW(REF ARRAY OF Ply.Property, 3);
    subPly.header.properties[0] := Ply.Property{name := "x",
      kind := Ply.PropKind.Float, floatIdx := 0};
    subPly.header.properties[1] := Ply.Property{name := "y",
      kind := Ply.PropKind.Float, floatIdx := 1};
    subPly.header.properties[2] := Ply.Property{name := "z",
      kind := Ply.PropKind.Float, floatIdx := 2};

    subPly.vertices := NEW(Ply.Vertices, nV * 3);
    FOR i := 0 TO nV - 1 DO
      VAR p := TriMesh.GetPosition(mesh, vertIdxs[i]); BEGIN
        subPly.vertices[3 * i + 0] := FLOAT(p.x, REAL);
        subPly.vertices[3 * i + 1] := FLOAT(p.y, REAL);
        subPly.vertices[3 * i + 2] := FLOAT(p.z, REAL);
      END;
    END;

    subPly.faces := NEW(Ply.Faces, nF * 3);
    FOR i := 0 TO nF - 1 DO
      TriMesh.GetFace(mesh, faceIdxs[i], v0, v1, v2);
      subPly.faces[3 * i + 0] := remap[v0];
      subPly.faces[3 * i + 1] := remap[v1];
      subPly.faces[3 * i + 2] := remap[v2];
    END;

    subMesh := TriMesh.FromPly(subPly);
    facet := Facet.Analyze(subMesh);
    curv := Curv.Analyze(subMesh, facet, threshold);
    stats := Curv.GetStats(curv);

    VAR heights := Facet.GetHeights(facet);
        hMin, hMax : LONGREAL;
    BEGIN
      hMin := heights[0]; hMax := heights[0];
      FOR i := 1 TO nV - 1 DO
        IF heights[i] < hMin THEN hMin := heights[i]; END;
        IF heights[i] > hMax THEN hMax := heights[i]; END;
      END;
      Put("  height span: "); PutLR(hMax - hMin, 2); PutLn();
    END;
    Put("  curvature:   mean="); PutLR(stats.meanCurv, 4);
    Put("  std="); PutLR(stats.stdCurv, 4); PutLn();
    Put("  residual:    std="); PutLR(stats.stdHeight, 2); PutLn();
    Put("  anomalies:   " & Fmt.Int(stats.nAnomalies) & "\n");
  END AnalyzeRegion;

PROCEDURE WriteAnomalyFile(path: TEXT; curv: Curv.T;
                           xyScale: LONGREAL) =
  <*FATAL Wr.Failure*>
  VAR
    wr : Wr.T;
    a  : Curv.Anomaly;
    nA := Curv.NAnomalies(curv);
  BEGIN
    TRY
      wr := FileWr.Open(path);
    EXCEPT
    | OSError.E => Put("  error: cannot open " & path & "\n"); RETURN;
    END;
    Wr.PutText(wr, "# x(um) y(um) residual(um) curvature(1/mm)\n");
    FOR k := 0 TO nA - 1 DO
      a := Curv.GetAnomaly(curv, k);
      Wr.PutText(wr, Fmt.LongReal(a.x * xyScale) & " "
                    & Fmt.LongReal(a.y * xyScale) & " "
                    & Fmt.LongReal(a.height * xyScale) & " "
                    & Fmt.LongReal(a.curvature * 1.0d3 / xyScale) & "\n");
    END;
    Wr.Close(wr);
  END WriteAnomalyFile;

PROCEDURE ScanLR(t: TEXT): LONGREAL =
  VAR
    val := 0.0d0;
    frac := 0.0d0;
    fracDiv := 1.0d0;
    sign := 1.0d0;
    inFrac := FALSE;
    ch : CHAR;
  BEGIN
    FOR i := 0 TO Text.Length(t) - 1 DO
      ch := Text.GetChar(t, i);
      IF ch = '-' AND i = 0 THEN
        sign := -1.0d0;
      ELSIF ch = '.' THEN
        inFrac := TRUE;
      ELSIF ch >= '0' AND ch <= '9' THEN
        IF inFrac THEN
          fracDiv := fracDiv * 10.0d0;
          frac := frac + FLOAT(ORD(ch) - ORD('0'), LONGREAL) / fracDiv;
        ELSE
          val := val * 10.0d0 + FLOAT(ORD(ch) - ORD('0'), LONGREAL);
        END;
      END;
    END;
    RETURN sign * (val + frac);
  END ScanLR;

BEGIN
  Run();
END Main.
