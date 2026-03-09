(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE SvgWriter;

IMPORT Projection, GeoCoord, GeoFeature, Wr, Fmt, Text, Thread, FileWr, OSError;

<*FATAL Thread.Alerted, Wr.Failure*>

CONST
  Pi = 3.141592653589793d0;

(* ---- Projected point storage for two-pass architecture ---- *)

TYPE
  ProjPoint = RECORD
    x, y : LONGREAL;
    valid : BOOLEAN;
    penLift : BOOLEAN;  (* force pen lift before drawing to this point *)
  END;

  ProjPointArray = REF ARRAY OF ProjPoint;
  ProjRingArray  = REF ARRAY OF ProjPointArray;

  ProjGeometry = RECORD
    kind   : GeoFeature.GeometryKind;
    coords : ProjPointArray;
    rings  : ProjRingArray;
  END;

  ProjFeature = RECORD
    geom : ProjGeometry;
    name : TEXT;
  END;

  ProjFeatureArray = REF ARRAY OF ProjFeature;

  BBox = RECORD
    minX, minY, maxX, maxY : LONGREAL;
    empty : BOOLEAN;
  END;

(* ---- Pass 1: Project all coordinates, compute bounding box ---- *)

PROCEDURE ExtendBBox(VAR bb : BBox; x, y : LONGREAL) =
  BEGIN
    IF bb.empty THEN
      bb.minX := x; bb.maxX := x;
      bb.minY := y; bb.maxY := y;
      bb.empty := FALSE;
    ELSE
      IF x < bb.minX THEN bb.minX := x END;
      IF x > bb.maxX THEN bb.maxX := x END;
      IF y < bb.minY THEN bb.minY := y END;
      IF y > bb.maxY THEN bb.maxY := y END;
    END;
  END ExtendBBox;

PROCEDURE ProjectCoordArray(coords : GeoFeature.CoordArray;
                            proj : Projection.T;
                            VAR bb : BBox) : ProjPointArray =
  VAR
    n : INTEGER;
    result : ProjPointArray;
    xy : GeoCoord.XY;
    mid : GeoCoord.LatLon;
    dlon : LONGREAL;
    prevValid : INTEGER;
  BEGIN
    IF coords = NIL THEN RETURN NIL END;
    n := NUMBER(coords^);
    result := NEW(ProjPointArray, n);

    (* First pass: project all points *)
    FOR i := 0 TO n - 1 DO
      result[i].penLift := FALSE;
      IF proj.forward(coords[i], xy) THEN
        (* Negate Y: geographic Y up, SVG Y down *)
        result[i].x := xy.x;
        result[i].y := -xy.y;
        result[i].valid := TRUE;
        ExtendBBox(bb, result[i].x, result[i].y);
      ELSE
        result[i].valid := FALSE;
      END;
    END;

    (* Second pass: detect segments that cross invisible territory
       or the antimeridian.  For each pair of consecutive valid points,
       check whether the geographic midpoint projects as valid and whether
       the segment crosses the antimeridian.  If not, mark the second
       point for a pen lift. *)
    prevValid := -1;
    FOR i := 0 TO n - 1 DO
      IF result[i].valid THEN
        IF prevValid >= 0 THEN
          (* Check 1: antimeridian crossing (|delta-lon| > pi) *)
          dlon := coords[i].lon - coords[prevValid].lon;
          IF dlon > Pi OR dlon < -Pi THEN
            result[i].penLift := TRUE;
          ELSE
            (* Check 2: midpoint visibility -- if the geographic midpoint
               of the segment does not project as valid, the segment
               crosses invisible territory (e.g. behind the globe). *)
            mid.lat := (coords[prevValid].lat + coords[i].lat) * 0.5d0;
            mid.lon := (coords[prevValid].lon + coords[i].lon) * 0.5d0;
            IF NOT proj.forward(mid, xy) THEN
              result[i].penLift := TRUE;
            END;
          END;
        END;
        prevValid := i;
      END;
    END;

    RETURN result
  END ProjectCoordArray;

PROCEDURE ProjectRings(rings : REF ARRAY OF GeoFeature.CoordArray;
                       proj : Projection.T;
                       VAR bb : BBox) : ProjRingArray =
  VAR
    n : INTEGER;
    result : ProjRingArray;
  BEGIN
    IF rings = NIL THEN RETURN NIL END;
    n := NUMBER(rings^);
    result := NEW(ProjRingArray, n);
    FOR i := 0 TO n - 1 DO
      result[i] := ProjectCoordArray(rings[i], proj, bb);
    END;
    RETURN result
  END ProjectRings;

PROCEDURE ProjectAll(READONLY fc : GeoFeature.FeatureCollection;
                     proj : Projection.T;
                     VAR bb : BBox) : ProjFeatureArray =
  VAR
    n : INTEGER;
    result : ProjFeatureArray;
  BEGIN
    bb.empty := TRUE;
    IF fc.features = NIL THEN RETURN NIL END;
    n := NUMBER(fc.features^);
    result := NEW(ProjFeatureArray, n);
    FOR i := 0 TO n - 1 DO
      result[i].name := fc.features[i].name;
      result[i].geom.kind := fc.features[i].geometry.kind;
      CASE fc.features[i].geometry.kind OF
      | GeoFeature.GeometryKind.Point,
        GeoFeature.GeometryKind.MultiPoint,
        GeoFeature.GeometryKind.LineString =>
        result[i].geom.coords := ProjectCoordArray(
            fc.features[i].geometry.coords, proj, bb);
        result[i].geom.rings := NIL;
      | GeoFeature.GeometryKind.Polygon,
        GeoFeature.GeometryKind.MultiLineString,
        GeoFeature.GeometryKind.MultiPolygon =>
        result[i].geom.coords := NIL;
        result[i].geom.rings := ProjectRings(
            fc.features[i].geometry.rings, proj, bb);
      END;
    END;
    RETURN result
  END ProjectAll;

(* ---- Pass 2: Scale, translate, emit SVG ---- *)

TYPE
  Transform = RECORD
    scale, offX, offY : LONGREAL;
  END;

PROCEDURE ComputeTransform(READONLY bb : BBox;
                           READONLY cfg : Config) : Transform =
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
    IF scaleX < scaleY THEN
      t.scale := scaleX;
    ELSE
      t.scale := scaleY;
    END;
    (* Center the map in the viewport *)
    t.offX := cfg.margin + (drawW - bboxW * t.scale) / 2.0d0 - bb.minX * t.scale;
    t.offY := cfg.margin + (drawH - bboxH * t.scale) / 2.0d0 - bb.minY * t.scale;
    RETURN t
  END ComputeTransform;

PROCEDURE TX(x : LONGREAL; READONLY t : Transform) : LONGREAL =
  BEGIN
    RETURN x * t.scale + t.offX
  END TX;

PROCEDURE TY(y : LONGREAL; READONLY t : Transform) : LONGREAL =
  BEGIN
    RETURN y * t.scale + t.offY
  END TY;

PROCEDURE F(v : LONGREAL) : TEXT =
  BEGIN
    RETURN Fmt.LongReal(v, Fmt.Style.Fix, 2)
  END F;

PROCEDURE EscapeXML(t : TEXT) : TEXT =
  VAR
    result : TEXT := "";
    c : CHAR;
  BEGIN
    IF t = NIL THEN RETURN "" END;
    FOR i := 0 TO Text.Length(t) - 1 DO
      c := Text.GetChar(t, i);
      IF c = '&' THEN
        result := result & "&amp;";
      ELSIF c = '<' THEN
        result := result & "&lt;";
      ELSIF c = '>' THEN
        result := result & "&gt;";
      ELSIF c = '\"' THEN
        result := result & "&quot;";
      ELSE
        result := result & Text.FromChar(c);
      END;
    END;
    RETURN result
  END EscapeXML;

PROCEDURE TextEmpty(t : TEXT) : BOOLEAN =
  BEGIN
    RETURN t = NIL OR Text.Length(t) = 0
  END TextEmpty;

(* ---- SVG element emitters ---- *)

PROCEDURE EmitPoint(wr : Wr.T;
                    READONLY p : ProjPoint;
                    READONLY t : Transform;
                    READONLY cfg : Config;
                    name : TEXT) =
  BEGIN
    IF NOT p.valid THEN RETURN END;
    Wr.PutText(wr, "<circle class=\"feature\"");
    IF name # NIL AND NOT TextEmpty(name) THEN
      Wr.PutText(wr, " data-name=\"" & EscapeXML(name) & "\"");
    END;
    Wr.PutText(wr, " cx=\"" & F(TX(p.x, t)) &
                    "\" cy=\"" & F(TY(p.y, t)) &
                    "\" r=\"" & F(cfg.pointRadius) & "\"/>\n");
  END EmitPoint;

PROCEDURE EmitMultiPoint(wr : Wr.T;
                         coords : ProjPointArray;
                         READONLY t : Transform;
                         READONLY cfg : Config;
                         name : TEXT) =
  BEGIN
    IF coords = NIL THEN RETURN END;
    Wr.PutText(wr, "<g class=\"feature\"");
    IF name # NIL AND NOT TextEmpty(name) THEN
      Wr.PutText(wr, " data-name=\"" & EscapeXML(name) & "\"");
    END;
    Wr.PutText(wr, ">\n");
    FOR i := 0 TO LAST(coords^) DO
      IF coords[i].valid THEN
        Wr.PutText(wr, "<circle cx=\"" & F(TX(coords[i].x, t)) &
                        "\" cy=\"" & F(TY(coords[i].y, t)) &
                        "\" r=\"" & F(cfg.pointRadius) & "\"/>\n");
      END;
    END;
    Wr.PutText(wr, "</g>\n");
  END EmitMultiPoint;

PROCEDURE EmitLineStringPath(wr : Wr.T;
                             coords : ProjPointArray;
                             READONLY t : Transform) =
  (* Emits M/L path commands for a single linestring.
     Lifts pen (M instead of L) when:
     - previous point was invalid (needMove)
     - midpoint visibility or antimeridian check failed (penLift) *)
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

PROCEDURE EmitPolygonRingPath(wr : Wr.T;
                              coords : ProjPointArray;
                              READONLY t : Transform) =
  (* Emits M/L/Z for a polygon ring, skipping invalid points.
     Lifts pen when penLift is set (midpoint visibility or antimeridian). *)
  VAR needMove := TRUE;
      hasPoints := FALSE;
  BEGIN
    IF coords = NIL THEN RETURN END;
    FOR i := 0 TO LAST(coords^) DO
      IF coords[i].valid THEN
        IF needMove OR coords[i].penLift THEN
          Wr.PutText(wr, "M" & F(TX(coords[i].x, t)) &
                         "," & F(TY(coords[i].y, t)));
          needMove := FALSE;
          hasPoints := TRUE;
        ELSE
          Wr.PutText(wr, " L" & F(TX(coords[i].x, t)) &
                          "," & F(TY(coords[i].y, t)));
        END;
      ELSE
        needMove := TRUE;
      END;
    END;
    IF hasPoints THEN Wr.PutText(wr, " Z") END;
  END EmitPolygonRingPath;

PROCEDURE EmitLineString(wr : Wr.T;
                         coords : ProjPointArray;
                         READONLY t : Transform;
                         name : TEXT) =
  BEGIN
    Wr.PutText(wr, "<path class=\"feature\"");
    IF name # NIL AND NOT TextEmpty(name) THEN
      Wr.PutText(wr, " data-name=\"" & EscapeXML(name) & "\"");
    END;
    Wr.PutText(wr, " d=\"");
    EmitLineStringPath(wr, coords, t);
    Wr.PutText(wr, "\"/>\n");
  END EmitLineString;

PROCEDURE EmitPolygon(wr : Wr.T;
                      rings : ProjRingArray;
                      READONLY t : Transform;
                      name : TEXT) =
  BEGIN
    IF rings = NIL THEN RETURN END;
    Wr.PutText(wr, "<path class=\"feature\" fill-rule=\"evenodd\"");
    IF name # NIL AND NOT TextEmpty(name) THEN
      Wr.PutText(wr, " data-name=\"" & EscapeXML(name) & "\"");
    END;
    Wr.PutText(wr, " d=\"");
    FOR i := 0 TO LAST(rings^) DO
      EmitPolygonRingPath(wr, rings[i], t);
    END;
    Wr.PutText(wr, "\"/>\n");
  END EmitPolygon;

PROCEDURE EmitMultiLineString(wr : Wr.T;
                              rings : ProjRingArray;
                              READONLY t : Transform;
                              name : TEXT) =
  BEGIN
    IF rings = NIL THEN RETURN END;
    Wr.PutText(wr, "<path class=\"feature\"");
    IF name # NIL AND NOT TextEmpty(name) THEN
      Wr.PutText(wr, " data-name=\"" & EscapeXML(name) & "\"");
    END;
    Wr.PutText(wr, " d=\"");
    FOR i := 0 TO LAST(rings^) DO
      EmitLineStringPath(wr, rings[i], t);
    END;
    Wr.PutText(wr, "\"/>\n");
  END EmitMultiLineString;

PROCEDURE EmitMultiPolygon(wr : Wr.T;
                           rings : ProjRingArray;
                           READONLY t : Transform;
                           name : TEXT) =
  BEGIN
    IF rings = NIL THEN RETURN END;
    Wr.PutText(wr, "<path class=\"feature\" fill-rule=\"evenodd\"");
    IF name # NIL AND NOT TextEmpty(name) THEN
      Wr.PutText(wr, " data-name=\"" & EscapeXML(name) & "\"");
    END;
    Wr.PutText(wr, " d=\"");
    FOR i := 0 TO LAST(rings^) DO
      EmitPolygonRingPath(wr, rings[i], t);
    END;
    Wr.PutText(wr, "\"/>\n");
  END EmitMultiPolygon;

(* ---- Public procedures ---- *)

PROCEDURE WriteFile(path : TEXT;
                    READONLY fc : GeoFeature.FeatureCollection;
                    proj : Projection.T;
                    READONLY cfg : Config) =
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

PROCEDURE MarkWrapAround(coords : ProjPointArray;
                         maxDist2 : LONGREAL) =
  (* Mark pen lifts for segments that wrap around the projection boundary.
     This catches antimeridian crossings in oblique projections where the
     geographic antimeridian check (|dlon| > pi) doesn't apply.
     A segment is considered a wrap-around if its projected-space distance
     exceeds maxDist2 (= (maxDim/3)^2, i.e., more than 1/3 of the map). *)
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

PROCEDURE MarkWrapAroundAll(features : ProjFeatureArray;
                            maxDist2 : LONGREAL) =
  BEGIN
    IF features = NIL THEN RETURN END;
    FOR i := 0 TO LAST(features^) DO
      CASE features[i].geom.kind OF
      | GeoFeature.GeometryKind.Point,
        GeoFeature.GeometryKind.MultiPoint =>
        (* no paths to check *)
      | GeoFeature.GeometryKind.LineString =>
        MarkWrapAround(features[i].geom.coords, maxDist2);
      | GeoFeature.GeometryKind.Polygon,
        GeoFeature.GeometryKind.MultiLineString,
        GeoFeature.GeometryKind.MultiPolygon =>
        IF features[i].geom.rings # NIL THEN
          FOR j := 0 TO LAST(features[i].geom.rings^) DO
            MarkWrapAround(features[i].geom.rings[j], maxDist2);
          END;
        END;
      END;
    END;
  END MarkWrapAroundAll;

PROCEDURE WriteWr(wr : Wr.T;
                  READONLY fc : GeoFeature.FeatureCollection;
                  proj : Projection.T;
                  READONLY cfg : Config) =
  VAR
    bb : BBox;
    features : ProjFeatureArray;
    t : Transform;
    maxDim, maxDist2 : LONGREAL;
  BEGIN
    (* Pass 1: project all coordinates, compute bounding box,
       and mark segments that cross invisible territory *)
    features := ProjectAll(fc, proj, bb);

    (* Pass 1b: mark segments that wrap around the projection boundary.
       Uses the bounding box (now known) to set a distance threshold at
       maxDim/3 in projected space.  This catches antimeridian crossings
       in oblique projections where the geographic check doesn't apply. *)
    IF NOT bb.empty THEN
      maxDim := bb.maxX - bb.minX;
      IF bb.maxY - bb.minY > maxDim THEN maxDim := bb.maxY - bb.minY END;
      maxDist2 := maxDim * maxDim / 9.0d0;  (* (maxDim/3)^2 *)
      MarkWrapAroundAll(features, maxDist2);
    END;

    (* Compute transform to fit bounding box into viewport *)
    t := ComputeTransform(bb, cfg);

    (* Pass 2: emit SVG *)
    Wr.PutText(wr, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    Wr.PutText(wr, "<svg xmlns=\"http://www.w3.org/2000/svg\"" &
                    " width=\"" & Fmt.Int(cfg.width) &
                    "\" height=\"" & Fmt.Int(cfg.height) &
                    "\" viewBox=\"0 0 " & Fmt.Int(cfg.width) &
                    " " & Fmt.Int(cfg.height) & "\">\n");

    (* Background *)
    Wr.PutText(wr, "<rect width=\"100%\" height=\"100%\" fill=\"" &
                    EscapeXML(cfg.background) & "\"/>\n");

    (* Style block *)
    Wr.PutText(wr, "<style>\n");
    Wr.PutText(wr, ".feature { stroke: " & cfg.stroke &
                    "; fill: " & cfg.fill &
                    "; stroke-width: " & F(cfg.strokeWidth) & "; }\n");
    Wr.PutText(wr, "</style>\n");

    (* Features *)
    IF features # NIL THEN
      FOR i := 0 TO LAST(features^) DO
        CASE features[i].geom.kind OF
        | GeoFeature.GeometryKind.Point =>
          IF features[i].geom.coords # NIL AND
             NUMBER(features[i].geom.coords^) > 0 THEN
            EmitPoint(wr, features[i].geom.coords[0], t, cfg,
                      features[i].name);
          END;
        | GeoFeature.GeometryKind.MultiPoint =>
          EmitMultiPoint(wr, features[i].geom.coords, t, cfg,
                         features[i].name);
        | GeoFeature.GeometryKind.LineString =>
          EmitLineString(wr, features[i].geom.coords, t,
                         features[i].name);
        | GeoFeature.GeometryKind.Polygon =>
          EmitPolygon(wr, features[i].geom.rings, t,
                      features[i].name);
        | GeoFeature.GeometryKind.MultiLineString =>
          EmitMultiLineString(wr, features[i].geom.rings, t,
                              features[i].name);
        | GeoFeature.GeometryKind.MultiPolygon =>
          EmitMultiPolygon(wr, features[i].geom.rings, t,
                           features[i].name);
        END;
      END;
    END;

    Wr.PutText(wr, "</svg>\n");
  END WriteWr;

BEGIN
END SvgWriter.
