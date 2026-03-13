(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE SvgMeshWriter;

IMPORT Projection, GeoCoord, GeoFeature, SvgWriter,
       TriMesh, Triangulate, MeshProject,
       Wr, Fmt, Text, Thread, FileWr, OSError, Math;

<*FATAL Thread.Alerted, Wr.Failure*>

CONST
  Pi = 3.141592653589793d0;
  TwoPi = 6.283185307179586d0;
  MaxArcLen = 0.1d0;  (* ≈ 5.7° — subdivision threshold *)

(* ---- Projected-point types for non-polygon geometry ---- *)

TYPE
  ProjPoint = RECORD
    x, y  : LONGREAL;
    valid : BOOLEAN;
    penLift : BOOLEAN;
  END;

  ProjPointArray = REF ARRAY OF ProjPoint;
  ProjRingArray  = REF ARRAY OF ProjPointArray;

(* ---- Per-feature storage ---- *)

TYPE
  MeshFeature = RECORD
    kind     : GeoFeature.GeometryKind;
    mesh     : TriMesh.Mesh;        (* polygon/multipolygon *)
    outlines : ProjRingArray;       (* polygon border for stroke *)
    coords   : ProjPointArray;      (* point/linestring *)
    rings    : ProjRingArray;       (* multilinestring/multipoint *)
    name     : TEXT;
    cssClass : TEXT;
  END;

  MeshFeatureArray = REF ARRAY OF MeshFeature;

(* ---- Transform ---- *)

TYPE
  Transform = RECORD
    scale, offX, offY : LONGREAL;
  END;

PROCEDURE ComputeTransform(READONLY bb : MeshProject.BBox;
                           READONLY cfg : SvgWriter.Config) : Transform =
  VAR
    t : Transform;
    bboxW, bboxH, drawW, drawH, scaleX, scaleY : LONGREAL;
  BEGIN
    IF bb.empty THEN
      t.scale := 1.0d0;
      t.offX := FLOAT(cfg.width, LONGREAL) / 2.0d0;
      t.offY := FLOAT(cfg.height, LONGREAL) / 2.0d0;
      RETURN t
    END;
    bboxW := bb.maxX - bb.minX;
    bboxH := bb.maxY - bb.minY;
    drawW := FLOAT(cfg.width, LONGREAL) - 2.0d0 * cfg.margin;
    drawH := FLOAT(cfg.height, LONGREAL) - 2.0d0 * cfg.margin;
    IF bboxW < 1.0d-12 THEN bboxW := 1.0d0 END;
    IF bboxH < 1.0d-12 THEN bboxH := 1.0d0 END;
    scaleX := drawW / bboxW;
    scaleY := drawH / bboxH;
    IF scaleX < scaleY THEN t.scale := scaleX
    ELSE t.scale := scaleY
    END;
    t.offX := cfg.margin + (drawW - bboxW * t.scale) / 2.0d0
              - bb.minX * t.scale;
    t.offY := cfg.margin + (drawH - bboxH * t.scale) / 2.0d0
              - bb.minY * t.scale;
    RETURN t
  END ComputeTransform;

PROCEDURE TX(x : LONGREAL; READONLY t : Transform) : LONGREAL =
  BEGIN RETURN x * t.scale + t.offX END TX;

PROCEDURE TY(y : LONGREAL; READONLY t : Transform) : LONGREAL =
  BEGIN RETURN y * t.scale + t.offY END TY;

PROCEDURE F(v : LONGREAL) : TEXT =
  BEGIN RETURN Fmt.LongReal(v, Fmt.Style.Fix, 2) END F;

(* ---- Text helpers ---- *)

PROCEDURE EscapeXML(t : TEXT) : TEXT =
  VAR result : TEXT := "";  c : CHAR;
  BEGIN
    IF t = NIL THEN RETURN "" END;
    FOR i := 0 TO Text.Length(t) - 1 DO
      c := Text.GetChar(t, i);
      IF    c = '&'  THEN result := result & "&amp;";
      ELSIF c = '<'  THEN result := result & "&lt;";
      ELSIF c = '>'  THEN result := result & "&gt;";
      ELSIF c = '\"' THEN result := result & "&quot;";
      ELSE  result := result & Text.FromChar(c);
      END;
    END;
    RETURN result
  END EscapeXML;

PROCEDURE TextEmpty(t : TEXT) : BOOLEAN =
  BEGIN RETURN t = NIL OR Text.Length(t) = 0 END TextEmpty;

PROCEDURE EmitTitleClose(wr : Wr.T; tag, name : TEXT) =
  (* Close an element: self-closing if no name, else with <title>. *)
  BEGIN
    IF TextEmpty(name) THEN
      Wr.PutText(wr, "/>\n");
    ELSE
      Wr.PutText(wr, "><title>" & EscapeXML(name) &
                      "</title></" & tag & ">\n");
    END;
  END EmitTitleClose;

PROCEDURE FeatureClass(cssClass : TEXT) : TEXT =
  BEGIN
    IF TextEmpty(cssClass) THEN RETURN "feature" END;
    RETURN "feature " & cssClass
  END FeatureClass;

(* ---- Simple projection for non-polygon geometry ---- *)

PROCEDURE ProjectCoords(coords : GeoFeature.CoordArray;
                        proj : Projection.T;
                        VAR bb : MeshProject.BBox) : ProjPointArray =
  VAR
    n : INTEGER;
    result : ProjPointArray;
    xy : GeoCoord.XY;
    mid : GeoCoord.LatLon;
    dlon, frac : LONGREAL;
    prevValid : INTEGER;
  BEGIN
    IF coords = NIL THEN RETURN NIL END;
    n := NUMBER(coords^);
    result := NEW(ProjPointArray, n);
    FOR i := 0 TO n - 1 DO
      result[i].penLift := FALSE;
      result[i].valid := proj.forward(coords[i], xy);
      result[i].x := xy.x;
      result[i].y := -xy.y;
      IF result[i].valid THEN
        MeshProject.ExtendBBox(bb, result[i].x, result[i].y);
      END;
    END;
    (* Pen-lift detection for linestrings *)
    prevValid := -1;
    FOR i := 0 TO n - 1 DO
      IF result[i].valid THEN
        IF prevValid >= 0 THEN
          dlon := coords[i].lon - coords[prevValid].lon;
          IF dlon > Pi OR dlon < -Pi THEN
            result[i].penLift := TRUE;
          ELSE
            FOR k := 1 TO 7 DO
              frac := FLOAT(k, LONGREAL) / 8.0d0;
              mid.lat := coords[prevValid].lat +
                         (coords[i].lat - coords[prevValid].lat) * frac;
              mid.lon := coords[prevValid].lon +
                         (coords[i].lon - coords[prevValid].lon) * frac;
              IF NOT proj.forward(mid, xy) THEN
                result[i].penLift := TRUE;
                EXIT;
              END;
            END;
          END;
        END;
        prevValid := i;
      END;
    END;
    RETURN result
  END ProjectCoords;

PROCEDURE ProjectRingsSimple(rings : REF ARRAY OF GeoFeature.CoordArray;
                             proj : Projection.T;
                             VAR bb : MeshProject.BBox) : ProjRingArray =
  VAR
    n : INTEGER;
    result : ProjRingArray;
  BEGIN
    IF rings = NIL THEN RETURN NIL END;
    n := NUMBER(rings^);
    result := NEW(ProjRingArray, n);
    FOR i := 0 TO n - 1 DO
      result[i] := ProjectCoords(rings[i], proj, bb);
    END;
    RETURN result
  END ProjectRingsSimple;

(* ---- Non-polygon SVG emitters ---- *)

PROCEDURE EmitPoint(wr : Wr.T; READONLY p : ProjPoint;
                    READONLY t : Transform; READONLY cfg : SvgWriter.Config;
                    name, cssClass : TEXT) =
  BEGIN
    IF NOT p.valid THEN RETURN END;
    Wr.PutText(wr, "<circle class=\"" & FeatureClass(cssClass) & "\"");
    IF NOT TextEmpty(name) THEN
      Wr.PutText(wr, " data-name=\"" & EscapeXML(name) & "\"");
    END;
    Wr.PutText(wr, " cx=\"" & F(TX(p.x, t)) &
                    "\" cy=\"" & F(TY(p.y, t)) &
                    "\" r=\"" & F(cfg.pointRadius) & "\"");
    EmitTitleClose(wr, "circle", name);
  END EmitPoint;

PROCEDURE EmitMultiPoint(wr : Wr.T; coords : ProjPointArray;
                         READONLY t : Transform;
                         READONLY cfg : SvgWriter.Config;
                         name, cssClass : TEXT) =
  BEGIN
    IF coords = NIL THEN RETURN END;
    Wr.PutText(wr, "<g class=\"" & FeatureClass(cssClass) & "\"");
    IF NOT TextEmpty(name) THEN
      Wr.PutText(wr, " data-name=\"" & EscapeXML(name) & "\"");
    END;
    Wr.PutText(wr, ">\n");
    IF NOT TextEmpty(name) THEN
      Wr.PutText(wr, "<title>" & EscapeXML(name) & "</title>\n");
    END;
    FOR i := 0 TO LAST(coords^) DO
      IF coords[i].valid THEN
        Wr.PutText(wr, "<circle cx=\"" & F(TX(coords[i].x, t)) &
                        "\" cy=\"" & F(TY(coords[i].y, t)) &
                        "\" r=\"" & F(cfg.pointRadius) & "\"/>\n");
      END;
    END;
    Wr.PutText(wr, "</g>\n");
  END EmitMultiPoint;

PROCEDURE EmitLineStringPath(wr : Wr.T; coords : ProjPointArray;
                             READONLY t : Transform) =
  VAR needMove := TRUE;
  BEGIN
    IF coords = NIL THEN RETURN END;
    FOR i := 0 TO LAST(coords^) DO
      IF coords[i].valid THEN
        IF needMove OR coords[i].penLift THEN
          Wr.PutText(wr, "M" & F(TX(coords[i].x, t)) &
                         "," & F(TY(coords[i].y, t)));
          needMove := FALSE;
        ELSE
          Wr.PutText(wr, " L" & F(TX(coords[i].x, t)) &
                          "," & F(TY(coords[i].y, t)));
        END;
      ELSE
        needMove := TRUE;
      END;
    END;
  END EmitLineStringPath;

PROCEDURE EmitLineString(wr : Wr.T; coords : ProjPointArray;
                         READONLY t : Transform;
                         name, cssClass : TEXT) =
  BEGIN
    Wr.PutText(wr, "<path class=\"" & FeatureClass(cssClass) & "\"");
    IF NOT TextEmpty(name) THEN
      Wr.PutText(wr, " data-name=\"" & EscapeXML(name) & "\"");
    END;
    Wr.PutText(wr, " d=\"");
    EmitLineStringPath(wr, coords, t);
    Wr.PutText(wr, "\"");
    EmitTitleClose(wr, "path", name);
  END EmitLineString;

PROCEDURE EmitMultiLineString(wr : Wr.T; rings : ProjRingArray;
                              READONLY t : Transform;
                              name, cssClass : TEXT) =
  BEGIN
    IF rings = NIL THEN RETURN END;
    Wr.PutText(wr, "<path class=\"" & FeatureClass(cssClass) & "\"");
    IF NOT TextEmpty(name) THEN
      Wr.PutText(wr, " data-name=\"" & EscapeXML(name) & "\"");
    END;
    Wr.PutText(wr, " d=\"");
    FOR i := 0 TO LAST(rings^) DO
      EmitLineStringPath(wr, rings[i], t);
    END;
    Wr.PutText(wr, "\"");
    EmitTitleClose(wr, "path", name);
  END EmitMultiLineString;

(* ---- Mesh triangle emitters ---- *)

PROCEDURE EmitTriAt(wr : Wr.T;
                    READONLY x, y : ARRAY [0..2] OF LONGREAL;
                    xShift : LONGREAL;
                    READONLY t : Transform) =
  (* Emit "M v0 L v1 L v2 Z" for one triangle, x-shifted by xShift. *)
  BEGIN
    Wr.PutText(wr, "M" & F(TX(x[0] + xShift, t)) &
                    "," & F(TY(y[0], t)) &
                    " L" & F(TX(x[1] + xShift, t)) &
                    "," & F(TY(y[1], t)) &
                    " L" & F(TX(x[2] + xShift, t)) &
                    "," & F(TY(y[2], t)) & " Z");
  END EmitTriAt;

PROCEDURE TriOverlapsVP(READONLY x, y : ARRAY [0..2] OF LONGREAL;
                        xShift : LONGREAL;
                        READONLY vp : MeshProject.BBox) : BOOLEAN =
  (* Check if triangle AABB (x-shifted) overlaps the viewport. *)
  VAR
    minX, maxX, minY, maxY, sx : LONGREAL;
  BEGIN
    IF vp.empty THEN RETURN TRUE END;
    sx := x[0] + xShift;
    minX := sx; maxX := sx;
    FOR k := 1 TO 2 DO
      sx := x[k] + xShift;
      IF sx < minX THEN minX := sx END;
      IF sx > maxX THEN maxX := sx END;
    END;
    minY := y[0]; maxY := y[0];
    FOR k := 1 TO 2 DO
      IF y[k] < minY THEN minY := y[k] END;
      IF y[k] > maxY THEN maxY := y[k] END;
    END;
    RETURN minX <= vp.maxX AND maxX >= vp.minX AND
           minY <= vp.maxY AND maxY >= vp.minY;
  END TriOverlapsVP;

PROCEDURE EmitDebugTri(wr : Wr.T;
                      READONLY x, y : ARRAY [0..2] OF LONGREAL;
                      xShift : LONGREAL;
                      READONLY t : Transform;
                      id : TEXT;
                      name : TEXT;
                      cssClass : TEXT) =
  (* Emit a single triangle as its own <path> with an id for debugging. *)
  BEGIN
    Wr.PutText(wr, "<path id=\"" & id &
               "\" class=\"mesh-tri " & FeatureClass(cssClass) & "\"");
    IF NOT TextEmpty(name) THEN
      Wr.PutText(wr, " data-name=\"" & EscapeXML(name) & "\"");
    END;
    Wr.PutText(wr, " d=\"M" & F(TX(x[0] + xShift, t)) &
               "," & F(TY(y[0], t)) &
               " L" & F(TX(x[1] + xShift, t)) &
               "," & F(TY(y[1], t)) &
               " L" & F(TX(x[2] + xShift, t)) &
               "," & F(TY(y[2], t)) & " Z\"");
    EmitTitleClose(wr, "path", name);
  END EmitDebugTri;

PROCEDURE EmitMeshPolygon(wr : Wr.T;
                          READONLY mesh : TriMesh.Mesh;
                          READONLY t : Transform;
                          READONLY vp : MeshProject.BBox;
                          discMode : BOOLEAN;
                          xPeriodic : BOOLEAN;
                          showMesh : BOOLEAN;
                          featIdx : INTEGER;
                          name, cssClass : TEXT) =
  (* When showMesh is FALSE: emit all triangles as a single <path> with
     class "mesh-fill" (stroke:none hides seams).
     When showMesh is TRUE: emit each triangle as an individual <path>
     with a unique id for debugging.
     Disc mode: cull triangles where ALL vertices are invalid.
     Non-disc: x-unwrap + emit at positions overlapping viewport. *)
  VAR
    x : ARRAY [0..2] OF LONGREAL;
    y : ARRAY [0..2] OF LONGREAL;
    anyValid : BOOLEAN;
    triCount : INTEGER := 0;
    prefix : TEXT;
  BEGIN
    IF mesh.tris = NIL OR NUMBER(mesh.tris^) = 0 THEN RETURN END;

    prefix := "tri-" & Fmt.Int(featIdx) & "-";

    IF NOT showMesh THEN
      (* Batched mode: single <path> with all triangles *)
      Wr.PutText(wr, "<path class=\"mesh-fill " & FeatureClass(cssClass) &
                 "\" fill-rule=\"nonzero\"");
      IF NOT TextEmpty(name) THEN
        Wr.PutText(wr, " data-name=\"" & EscapeXML(name) & "\"");
      END;
      Wr.PutText(wr, " d=\"");
    END;

    FOR i := 0 TO LAST(mesh.tris^) DO
      FOR k := 0 TO 2 DO
        x[k] := mesh.tris[i].v[k].xy.x;
        y[k] := mesh.tris[i].v[k].xy.y;
      END;

      IF discMode THEN
        (* Cull only when ALL vertices are invalid — SVG clip-path
           handles clipping at the disc boundary *)
        anyValid := FALSE;
        FOR k := 0 TO 2 DO
          IF mesh.tris[i].v[k].valid THEN anyValid := TRUE END;
        END;
        IF anyValid THEN
          IF showMesh THEN
            EmitDebugTri(wr, x, y, 0.0d0, t,
                         prefix & Fmt.Int(triCount), name, cssClass);
          ELSE
            EmitTriAt(wr, x, y, 0.0d0, t);
          END;
          INC(triCount);
        END;
      ELSE
        IF xPeriodic THEN
          (* Cylindrical: x-unwrap vertices to be within π of vertex 0 *)
          FOR k := 1 TO 2 DO
            WHILE x[k] - x[0] > Pi DO x[k] := x[k] - TwoPi END;
            WHILE x[k] - x[0] < -Pi DO x[k] := x[k] + TwoPi END;
          END;
        END;
        (* Emit at the original position *)
        IF TriOverlapsVP(x, y, 0.0d0, vp) THEN
          IF showMesh THEN
            EmitDebugTri(wr, x, y, 0.0d0, t,
                         prefix & Fmt.Int(triCount), name, cssClass);
          ELSE
            EmitTriAt(wr, x, y, 0.0d0, t);
          END;
          INC(triCount);
        END;
        IF xPeriodic THEN
          (* Cylindrical: also emit at ±2π for wrap-around copies *)
          IF TriOverlapsVP(x, y, TwoPi, vp) THEN
            IF showMesh THEN
              EmitDebugTri(wr, x, y, TwoPi, t,
                           prefix & Fmt.Int(triCount) & "p", name, cssClass);
            ELSE
              EmitTriAt(wr, x, y, TwoPi, t);
            END;
          END;
          IF TriOverlapsVP(x, y, -TwoPi, vp) THEN
            IF showMesh THEN
              EmitDebugTri(wr, x, y, -TwoPi, t,
                           prefix & Fmt.Int(triCount) & "n", name, cssClass);
            ELSE
              EmitTriAt(wr, x, y, -TwoPi, t);
            END;
          END;
        END;
      END;
    END;

    IF NOT showMesh THEN
      Wr.PutText(wr, "\"");
      EmitTitleClose(wr, "path", name);
    END;
  END EmitMeshPolygon;

PROCEDURE EmitOutlineRings(wr : Wr.T;
                           outlines : ProjRingArray;
                           READONLY t : Transform;
                           name, cssClass : TEXT) =
  (* Emit polygon outlines as a stroked, unfilled <path>. *)
  BEGIN
    IF outlines = NIL THEN RETURN END;
    Wr.PutText(wr, "<path class=\"mesh-outline " &
               FeatureClass(cssClass) & "\"");
    IF NOT TextEmpty(name) THEN
      Wr.PutText(wr, " data-name=\"" & EscapeXML(name) & "\"");
    END;
    Wr.PutText(wr, " d=\"");
    FOR i := 0 TO LAST(outlines^) DO
      EmitLineStringPath(wr, outlines[i], t);
    END;
    Wr.PutText(wr, "\"");
    EmitTitleClose(wr, "path", name);
  END EmitOutlineRings;

(* ---- Wrap-around marking for linestrings ---- *)

PROCEDURE MarkWrapAround(coords : ProjPointArray;
                         maxDist2 : LONGREAL) =
  VAR
    prevX, prevY, dx, dy : LONGREAL;
    prevValid := -1;
  BEGIN
    IF coords = NIL THEN RETURN END;
    FOR i := 0 TO LAST(coords^) DO
      IF coords[i].valid THEN
        IF prevValid >= 0 AND NOT coords[i].penLift THEN
          dx := coords[i].x - prevX;
          dy := coords[i].y - prevY;
          IF dx * dx + dy * dy > maxDist2 THEN
            coords[i].penLift := TRUE;
          END;
        END;
        prevValid := i;
        prevX := coords[i].x;
        prevY := coords[i].y;
      END;
    END;
  END MarkWrapAround;

PROCEDURE MarkWrapAroundAll(features : MeshFeatureArray;
                            maxDist2 : LONGREAL) =
  BEGIN
    IF features = NIL THEN RETURN END;
    FOR i := 0 TO LAST(features^) DO
      CASE features[i].kind OF
      | GeoFeature.GeometryKind.Point,
        GeoFeature.GeometryKind.MultiPoint =>
        (* skip *)
      | GeoFeature.GeometryKind.LineString =>
        MarkWrapAround(features[i].coords, maxDist2);
      | GeoFeature.GeometryKind.MultiLineString =>
        IF features[i].rings # NIL THEN
          FOR j := 0 TO LAST(features[i].rings^) DO
            MarkWrapAround(features[i].rings[j], maxDist2);
          END;
        END;
      | GeoFeature.GeometryKind.Polygon,
        GeoFeature.GeometryKind.MultiPolygon =>
        (* Mark wrap-around on polygon outline rings *)
        IF features[i].outlines # NIL THEN
          FOR j := 0 TO LAST(features[i].outlines^) DO
            MarkWrapAround(features[i].outlines[j], maxDist2);
          END;
        END;
      END;
    END;
  END MarkWrapAroundAll;

(* ---- Public procedures ---- *)

PROCEDURE WriteFile(path : TEXT;
                    READONLY fc : GeoFeature.FeatureCollection;
                    proj : Projection.T;
                    READONLY cfg : SvgWriter.Config) =
  VAR wr : Wr.T;
  BEGIN
    TRY
      wr := FileWr.Open(path);
    EXCEPT
      OSError.E => RETURN
    END;
    WriteWr(wr, fc, proj, cfg);
    Wr.Close(wr);
  END WriteFile;

PROCEDURE WriteWr(wr : Wr.T;
                  READONLY fc : GeoFeature.FeatureCollection;
                  proj : Projection.T;
                  READONLY cfg : SvgWriter.Config) =
  VAR
    bb : MeshProject.BBox;
    features : MeshFeatureArray;
    t : Transform;
    n : INTEGER;
    meshBB, olBB : MeshProject.BBox;
    maxDim, maxDist2 : LONGREAL;
  BEGIN
    bb.empty := TRUE;
    IF fc.features = NIL THEN
      features := NIL;
    ELSE
      n := NUMBER(fc.features^);
      features := NEW(MeshFeatureArray, n);

      (* Pass 1: build meshes for polygons, project non-polygon coords *)
      FOR i := 0 TO n - 1 DO
        features[i].name := fc.features[i].name;
        features[i].cssClass := fc.features[i].cssClass;
        features[i].kind := fc.features[i].geometry.kind;

        CASE fc.features[i].geometry.kind OF
        | GeoFeature.GeometryKind.Point,
          GeoFeature.GeometryKind.MultiPoint,
          GeoFeature.GeometryKind.LineString =>
          features[i].coords := ProjectCoords(
              fc.features[i].geometry.coords, proj, bb);
          features[i].rings := NIL;
          features[i].outlines := NIL;

        | GeoFeature.GeometryKind.MultiLineString =>
          features[i].coords := NIL;
          features[i].rings := ProjectRingsSimple(
              fc.features[i].geometry.rings, proj, bb);
          features[i].outlines := NIL;

        | GeoFeature.GeometryKind.Polygon,
          GeoFeature.GeometryKind.MultiPolygon =>
          features[i].coords := NIL;
          features[i].rings := NIL;
          features[i].mesh := Triangulate.PolygonToMesh(
              fc.features[i].geometry.rings, MaxArcLen);
          meshBB := MeshProject.ProjectMesh(
              features[i].mesh, proj, cfg.discRadius);
          IF NOT meshBB.empty THEN
            MeshProject.ExtendBBox(bb, meshBB.minX, meshBB.minY);
            MeshProject.ExtendBBox(bb, meshBB.maxX, meshBB.maxY);
          END;
          (* Project outline rings for border stroke rendering.
             Use a separate bbox so raw outline coords (e.g. poles)
             don't affect the viewport calculation. *)
          olBB.empty := TRUE;
          features[i].outlines := ProjectRingsSimple(
              fc.features[i].geometry.rings, proj, olBB);
        END;
      END;
    END;

    (* Extend bbox for disc boundary *)
    IF cfg.discRadius > 0.0d0 THEN
      MeshProject.ExtendBBox(bb, -cfg.discRadius, -cfg.discRadius);
      MeshProject.ExtendBBox(bb, cfg.discRadius, cfg.discRadius);
    END;

    (* Mercator latitude clamp — override bbox y-bounds.
       Uses the Mercator formula y = ln(tan(lat) + sec(lat)) to
       compute the projected y at the given latitude bounds. *)
    IF cfg.mercatorMaxLat > 0.0d0 AND cfg.mercatorMaxLat < 90.0d0 THEN
      VAR latRad := cfg.mercatorMaxLat * GeoCoord.DegToRad;
          yVal := Math.log(Math.tan(latRad)
                           + 1.0d0 / Math.cos(latRad));
      BEGIN
        bb.minY := -yVal;  (* northern bound in SVG coords *)
        bb.empty := FALSE;
      END;
    END;
    IF cfg.mercatorMinLat < 0.0d0 AND cfg.mercatorMinLat > -90.0d0 THEN
      VAR latRad := (-cfg.mercatorMinLat) * GeoCoord.DegToRad;
          yVal := Math.log(Math.tan(latRad)
                           + 1.0d0 / Math.cos(latRad));
      BEGIN
        bb.maxY := yVal;  (* southern bound in SVG coords *)
        bb.empty := FALSE;
      END;
    END;

    (* Mark linestring and outline wrap-arounds *)
    IF NOT bb.empty THEN
      maxDim := bb.maxX - bb.minX;
      IF bb.maxY - bb.minY > maxDim THEN maxDim := bb.maxY - bb.minY END;
      maxDist2 := maxDim * maxDim / 9.0d0;
      MarkWrapAroundAll(features, maxDist2);
    END;

    t := ComputeTransform(bb, cfg);

    (* Pass 2: emit SVG *)
    Wr.PutText(wr, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    Wr.PutText(wr, "<svg xmlns=\"http://www.w3.org/2000/svg\"" &
                    " width=\"" & Fmt.Int(cfg.width) &
                    "\" height=\"" & Fmt.Int(cfg.height) &
                    "\" viewBox=\"0 0 " & Fmt.Int(cfg.width) &
                    " " & Fmt.Int(cfg.height) & "\"");
    Wr.PutText(wr, " style=\"background:#1a1a2e\"");
    Wr.PutText(wr, ">\n");

    (* Clip paths, background fills.
       Disc mode: clip features to the globe disc.
       Non-disc:  clip features to the viewport rect so triangles
                  extending beyond the projection bounds are hidden. *)
    IF cfg.discRadius > 0.0d0 THEN
      VAR cx := F(TX(0.0d0, t));
          cy := F(TY(0.0d0, t));
          r  := F(cfg.discRadius * t.scale);
      BEGIN
        Wr.PutText(wr, "<defs><clipPath id=\"globe-clip\">" &
                        "<circle cx=\"" & cx & "\" cy=\"" & cy &
                        "\" r=\"" & r & "\"/>" &
                        "</clipPath></defs>\n");
        Wr.PutText(wr, "<circle cx=\"" & cx & "\" cy=\"" & cy &
                        "\" r=\"" & r &
                        "\" fill=\"" & EscapeXML(cfg.background) &
                        "\"/>\n");
      END;
    ELSIF NOT bb.empty THEN
      VAR rx := F(TX(bb.minX, t));
          ry := F(TY(bb.minY, t));
          rw := F((bb.maxX - bb.minX) * t.scale);
          rh := F((bb.maxY - bb.minY) * t.scale);
      BEGIN
        Wr.PutText(wr, "<defs><clipPath id=\"vp-clip\">" &
                        "<rect x=\"" & rx & "\" y=\"" & ry &
                        "\" width=\"" & rw & "\" height=\"" & rh &
                        "\"/></clipPath></defs>\n");
        Wr.PutText(wr, "<rect x=\"" & rx & "\" y=\"" & ry &
                        "\" width=\"" & rw & "\" height=\"" & rh &
                        "\" fill=\"" & EscapeXML(cfg.background) &
                        "\"/>\n");
      END;
    END;

    (* Style — mesh rules come AFTER .secondary so stroke:none wins *)
    Wr.PutText(wr, "<style>\n");
    Wr.PutText(wr, ".feature { stroke: " & cfg.stroke &
                    "; fill: " & cfg.fill &
                    "; stroke-width: " & F(cfg.strokeWidth) & "; }\n");
    Wr.PutText(wr, ".secondary { stroke: #88aa88; }\n");
    IF cfg.showMesh THEN
      Wr.PutText(wr, ".mesh-tri { stroke-width: 0.2; }\n");
    ELSE
      Wr.PutText(wr, ".mesh-fill { stroke: none; }\n");
      Wr.PutText(wr, ".mesh-outline { fill: none; }\n");
    END;
    Wr.PutText(wr, ".earth-equator { stroke: #ff4444; fill: none; " &
                    "stroke-width: " &
                    F(cfg.strokeWidth * 1.5d0) & "; }\n");
    Wr.PutText(wr, ".proj-equator { stroke: #4488ff; fill: none; " &
                    "stroke-width: " &
                    F(cfg.strokeWidth * 1.5d0) & "; }\n");
    Wr.PutText(wr, ".marker { fill: #ff6600; stroke: #ffffff; " &
                    "stroke-width: 1.5; }\n");
    Wr.PutText(wr, ".marker-label { fill: #ffffff; stroke: #000000; " &
                    "stroke-width: 0.3; font: bold 11px sans-serif; }\n");
    Wr.PutText(wr, "</style>\n");

    IF cfg.discRadius > 0.0d0 THEN
      Wr.PutText(wr, "<g clip-path=\"url(#globe-clip)\">\n");
    ELSIF NOT bb.empty THEN
      Wr.PutText(wr, "<g clip-path=\"url(#vp-clip)\">\n");
    END;

    (* Emit features *)
    IF features # NIL THEN
      FOR i := 0 TO LAST(features^) DO
        CASE features[i].kind OF
        | GeoFeature.GeometryKind.Point =>
          IF features[i].coords # NIL AND
             NUMBER(features[i].coords^) > 0 THEN
            EmitPoint(wr, features[i].coords[0], t, cfg,
                      features[i].name, features[i].cssClass);
          END;
        | GeoFeature.GeometryKind.MultiPoint =>
          EmitMultiPoint(wr, features[i].coords, t, cfg,
                         features[i].name, features[i].cssClass);
        | GeoFeature.GeometryKind.LineString =>
          EmitLineString(wr, features[i].coords, t,
                         features[i].name, features[i].cssClass);
        | GeoFeature.GeometryKind.MultiLineString =>
          EmitMultiLineString(wr, features[i].rings, t,
                              features[i].name, features[i].cssClass);
        | GeoFeature.GeometryKind.Polygon,
          GeoFeature.GeometryKind.MultiPolygon =>
          EmitMeshPolygon(wr, features[i].mesh, t, bb,
                          cfg.discRadius > 0.0d0,
                          cfg.xPeriodic,
                          cfg.showMesh, i,
                          features[i].name, features[i].cssClass);
          IF NOT cfg.showMesh THEN
            (* Stroked outline (no fill — country borders) *)
            EmitOutlineRings(wr, features[i].outlines, t,
                             features[i].name, features[i].cssClass);
          END;
        END;
      END;
    END;

    IF cfg.discRadius > 0.0d0 OR NOT bb.empty THEN
      Wr.PutText(wr, "</g>\n");
    END;

    (* Emit airport/point markers — outside clip group so always visible *)
    IF cfg.markers # NIL THEN
      VAR xy : GeoCoord.XY;
          mx, my : LONGREAL;
      BEGIN
        FOR i := 0 TO LAST(cfg.markers^) DO
          IF proj.forward(cfg.markers[i].loc, xy) THEN
            mx := TX(xy.x, t);
            my := TY(-xy.y, t);
            Wr.PutText(wr, "<circle class=\"marker\" cx=\"" &
                            F(mx) & "\" cy=\"" & F(my) &
                            "\" r=\"4\"/>\n");
            IF NOT TextEmpty(cfg.markers[i].label) THEN
              Wr.PutText(wr, "<text class=\"marker-label\" x=\"" &
                              F(mx + 6.0d0) & "\" y=\"" &
                              F(my + 4.0d0) & "\">" &
                              EscapeXML(cfg.markers[i].label) &
                              "</text>\n");
            END;
          END;
        END;
      END;
    END;

    Wr.PutText(wr, "</svg>\n");
  END WriteWr;

BEGIN
END SvgMeshWriter.
