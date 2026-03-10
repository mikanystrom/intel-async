(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE SvgWriter;

IMPORT Projection, GeoCoord, GeoFeature, Wr, Fmt, Text, Thread, FileWr, OSError, Math;

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
    geom     : ProjGeometry;
    name     : TEXT;
    cssClass : TEXT;
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
                            VAR bb : BBox;
                            isRing : BOOLEAN := FALSE;
                            discRadius : LONGREAL := 0.0d0) : ProjPointArray =
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

    (* First pass: project all points *)
    FOR i := 0 TO n - 1 DO
      result[i].penLift := FALSE;
      result[i].valid := proj.forward(coords[i], xy);
      (* Always store projected coords.  Projections like Orthographic
         and Mercator compute meaningful xy even for invalid points
         (back-hemisphere or clamped polar coordinates). *)
      result[i].x := xy.x;
      result[i].y := -xy.y;
      IF result[i].valid THEN
        ExtendBBox(bb, result[i].x, result[i].y);
      END;
    END;

    (* Recovery pass (non-disc polygon rings only): make invalid points
       valid if their projected coordinates are meaningful.  This keeps
       rings intact for correct SVG fill.  For example, Mercator clamps
       extreme latitudes and computes xy even when returning FALSE —
       these clamped points extend off-screen below the viewport.
       Recovered points are NOT included in the bounding box.
       Skip for disc mode — Orthographic back-hemisphere points have
       "folded" xy that would create artifacts; disc boundary arcs
       handle those gaps correctly. *)
    IF isRing AND discRadius <= 0.0d0 THEN
      FOR i := 0 TO n - 1 DO
        IF NOT result[i].valid AND
           ABS(result[i].x) < 50.0d0 AND ABS(result[i].y) < 50.0d0 THEN
          result[i].valid := TRUE;
        END;
      END;
    END;

    (* Second pass: detect segments that cross invisible territory
       or the antimeridian.  For each pair of consecutive valid points,
       sample several intermediate geographic points and check whether
       they all project as valid.  If any sample is invisible, the
       segment crosses behind the globe — mark for a pen lift. *)
    prevValid := -1;
    FOR i := 0 TO n - 1 DO
      IF result[i].valid THEN
        IF prevValid >= 0 THEN
          (* Check 1: antimeridian crossing (|delta-lon| > pi).
             Skip for polygon rings — the fill handles cross-map
             segments correctly, and pen lifts would break the ring. *)
          dlon := coords[i].lon - coords[prevValid].lon;
          IF NOT isRing AND (dlon > Pi OR dlon < -Pi) THEN
            result[i].penLift := TRUE;
          ELSE
            (* Check 2: multi-sample visibility -- test several points
               along the segment (at 1/8, 2/8, ... 7/8) to catch arcs
               that dip behind the globe even when endpoints are visible. *)
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
  END ProjectCoordArray;

(* ---- Antimeridian splitting for polygon rings ---- *)
(*
   After projection, polygon rings that cross the antimeridian have
   consecutive valid points with |dx| > π.  Without splitting, SVG
   draws a line across the entire map.

   The algorithm detects these crossings in projected x-space and
   splits each ring into sub-rings, one per side of the antimeridian.
   Each sub-ring is closed: it includes interpolated crossing points
   at x = ±π (the map edge), so the Z closure runs along the edge
   and is invisible.

   Special case: a globe-spanning ring (e.g., Antarctica encircling
   the south pole) crosses the antimeridian exactly once.  It cannot
   be split into two sides.  Instead the ring is rearranged so the
   crossing is at the start/end, and bottom-edge closure points are
   added so the Z closure runs along the map edge off-screen.
*)

CONST
  MaxCrossings = 50;
  BottomEdgeY = -100.0d0;  (* far off-screen in projected coords *)
  TopEdgeY    =  100.0d0;

PROCEDURE SplitOneRing(ring : ProjPointArray) : ProjRingArray =
  VAR
    n : INTEGER;
    prevValidI, firstValidI : INTEGER;
    crossCount : INTEGER;
    cI1 : ARRAY [0..MaxCrossings-1] OF INTEGER;
    cI2 : ARRAY [0..MaxCrossings-1] OF INTEGER;
    cY  : ARRAY [0..MaxCrossings-1] OF LONGREAL;
    cFromRight : ARRAY [0..MaxCrossings-1] OF BOOLEAN;
  BEGIN
    IF ring = NIL OR NUMBER(ring^) < 3 THEN
      VAR r := NEW(ProjRingArray, 1); BEGIN
        r[0] := ring; RETURN r
      END;
    END;
    n := NUMBER(ring^);
    crossCount := 0;

    (* Find antimeridian crossings between consecutive valid points *)
    prevValidI := -1;
    firstValidI := -1;
    FOR i := 0 TO n - 1 DO
      IF ring[i].valid THEN
        IF firstValidI < 0 THEN firstValidI := i END;
        IF prevValidI >= 0 AND
           ABS(ring[i].x - ring[prevValidI].x) > Pi THEN
          IF crossCount < MaxCrossings THEN
            cI1[crossCount] := prevValidI;
            cI2[crossCount] := i;
            cFromRight[crossCount] := ring[prevValidI].x > 0.0d0;
            VAR x1 := ring[prevValidI].x;
                y1 := ring[prevValidI].y;
                x2 := ring[i].x;
                y2 := ring[i].y;
                t : LONGREAL;
            BEGIN
              IF x1 > 0.0d0 THEN
                t := (Pi - x1) / ((x2 + 2.0d0 * Pi) - x1);
              ELSE
                t := (-Pi - x1) / ((x2 - 2.0d0 * Pi) - x1);
              END;
              IF t < 0.0d0 THEN t := 0.0d0
              ELSIF t > 1.0d0 THEN t := 1.0d0 END;
              cY[crossCount] := y1 + t * (y2 - y1);
            END;
            INC(crossCount);
          END;
        END;
        prevValidI := i;
      END;
    END;

    (* Check wrap-around: last valid point → first valid point *)
    IF firstValidI >= 0 AND prevValidI >= 0 AND
       firstValidI # prevValidI AND
       ABS(ring[firstValidI].x - ring[prevValidI].x) > Pi THEN
      IF crossCount < MaxCrossings THEN
        cI1[crossCount] := prevValidI;
        cI2[crossCount] := firstValidI;
        cFromRight[crossCount] := ring[prevValidI].x > 0.0d0;
        VAR x1 := ring[prevValidI].x;
            y1 := ring[prevValidI].y;
            x2 := ring[firstValidI].x;
            y2 := ring[firstValidI].y;
            t : LONGREAL;
        BEGIN
          IF x1 > 0.0d0 THEN
            t := (Pi - x1) / ((x2 + 2.0d0 * Pi) - x1);
          ELSE
            t := (-Pi - x1) / ((x2 - 2.0d0 * Pi) - x1);
          END;
          IF t < 0.0d0 THEN t := 0.0d0
          ELSIF t > 1.0d0 THEN t := 1.0d0 END;
          cY[crossCount] := y1 + t * (y2 - y1);
        END;
        INC(crossCount);
      END;
    END;

    IF crossCount = 0 THEN
      VAR r := NEW(ProjRingArray, 1); BEGIN
        r[0] := ring; RETURN r
      END;
    END;

    IF crossCount = 1 THEN
      RETURN RearrangeGlobeSpanning(ring, n,
                                    cI1[0], cI2[0], cY[0],
                                    cFromRight[0]);
    END;

    IF crossCount MOD 2 # 0 THEN
      (* Odd > 1: rare, return original as fallback *)
      VAR r := NEW(ProjRingArray, 1); BEGIN
        r[0] := ring; RETURN r
      END;
    END;

    (* Even crossings: split into sub-rings between crossing pairs *)
    RETURN SplitAtCrossings(ring, n, crossCount,
                            cI1, cI2, cY, cFromRight);
  END SplitOneRing;

PROCEDURE RearrangeGlobeSpanning(ring : ProjPointArray;
                                  n : INTEGER;
                                  i1, i2 : INTEGER;
                                  cy : LONGREAL;
                                  fromRight : BOOLEAN) : ProjRingArray =
  (* Globe-spanning ring with 1 antimeridian crossing.
     Rearrange so the crossing is at the start/end, and add
     bottom-edge closure points so the Z closure is off-screen.

     The rearranged ring:
       crossPt_start, ring[i2]..ring[i1], crossPt_end,
       edge_corner_end, edge_corner_start
     Z closure connects edge_corner_start back to crossPt_start,
     a vertical line at the map edge — invisible. *)
  VAR
    numOrig, numPts : INTEGER;
    newRing : ProjPointArray;
    idx : INTEGER;
    startX, endX, edgeY : LONGREAL;
  BEGIN
    (* Count original points from i2 to i1 (wrapping around) *)
    IF i2 <= i1 THEN
      numOrig := i1 - i2 + 1;
    ELSE
      numOrig := (n - i2) + i1 + 1;
    END;
    numPts := numOrig + 4;  (* + 2 crossing pts + 2 edge corners *)
    newRing := NEW(ProjPointArray, numPts);
    idx := 0;

    (* Determine sides: if crossing from right→left, segment after
       is on the left side, so start at x=-π *)
    IF fromRight THEN
      startX := -Pi;  endX := Pi;
    ELSE
      startX := Pi;   endX := -Pi;
    END;

    (* Edge Y: go south for south-hemisphere crossings, north otherwise *)
    IF cy < 0.0d0 THEN edgeY := BottomEdgeY
    ELSE edgeY := TopEdgeY END;

    (* Crossing start point *)
    newRing[idx] := ProjPoint{startX, cy, TRUE, FALSE};
    INC(idx);

    (* Original points from i2 to i1 *)
    VAR i := i2; BEGIN
      LOOP
        newRing[idx] := ring[i];
        INC(idx);
        IF i = i1 THEN EXIT END;
        i := (i + 1) MOD n;
      END;
    END;

    (* Crossing end point *)
    newRing[idx] := ProjPoint{endX, cy, TRUE, FALSE};
    INC(idx);

    (* Bottom/top edge corners for off-screen Z closure *)
    newRing[idx] := ProjPoint{endX, edgeY, TRUE, FALSE};
    INC(idx);
    newRing[idx] := ProjPoint{startX, edgeY, TRUE, FALSE};
    INC(idx);

    VAR r := NEW(ProjRingArray, 1); BEGIN
      r[0] := newRing;
      RETURN r
    END;
  END RearrangeGlobeSpanning;

PROCEDURE SplitAtCrossings(ring : ProjPointArray;
                            n, crossCount : INTEGER;
                            READONLY cI1 : ARRAY OF INTEGER;
                            READONLY cI2 : ARRAY OF INTEGER;
                            READONLY cY  : ARRAY OF LONGREAL;
                            READONLY cFromRight : ARRAY OF BOOLEAN)
    : ProjRingArray =
  VAR
    result : ProjRingArray;
  BEGIN
    result := NEW(ProjRingArray, crossCount);
    FOR seg := 0 TO crossCount - 1 DO
      VAR nextSeg := (seg + 1) MOD crossCount;
          startI := cI2[seg];
          endI := cI1[nextSeg];
          edgeX : LONGREAL;
          numOrig, numPts : INTEGER;
          subRing : ProjPointArray;
          idx : INTEGER;
      BEGIN
        (* Determine side: crossing seg goes from right→left means
           segment after is on the LEFT, so edge is at -π *)
        IF cFromRight[seg] THEN edgeX := -Pi ELSE edgeX := Pi END;

        (* Count original points from startI to endI (wrapping) *)
        IF startI <= endI THEN
          numOrig := endI - startI + 1;
        ELSE
          numOrig := (n - startI) + endI + 1;
        END;
        numPts := numOrig + 2;  (* + 2 crossing points *)
        subRing := NEW(ProjPointArray, numPts);
        idx := 0;

        (* Crossing start point *)
        subRing[idx] := ProjPoint{edgeX, cY[seg], TRUE, FALSE};
        INC(idx);

        (* Original points *)
        VAR i := startI; BEGIN
          LOOP
            subRing[idx] := ring[i];
            INC(idx);
            IF i = endI THEN EXIT END;
            i := (i + 1) MOD n;
          END;
        END;

        (* Crossing end point *)
        subRing[idx] := ProjPoint{edgeX, cY[nextSeg], TRUE, FALSE};

        result[seg] := subRing;
      END;
    END;
    RETURN result
  END SplitAtCrossings;

PROCEDURE SplitRingsAtAntimeridian(rings : ProjRingArray) : ProjRingArray =
  VAR
    n, totalOut : INTEGER;
    perRing : REF ARRAY OF ProjRingArray;
  BEGIN
    IF rings = NIL THEN RETURN NIL END;
    n := NUMBER(rings^);
    perRing := NEW(REF ARRAY OF ProjRingArray, n);
    totalOut := 0;
    FOR i := 0 TO n - 1 DO
      perRing[i] := SplitOneRing(rings[i]);
      INC(totalOut, NUMBER(perRing[i]^));
    END;
    (* Cannot short-circuit when totalOut = n because a globe-spanning
       ring (1 crossing) returns 1 rearranged ring — same count but
       different content.  Always build the result array. *)
    VAR result := NEW(ProjRingArray, totalOut);
        idx := 0;
    BEGIN
      FOR i := 0 TO n - 1 DO
        FOR j := 0 TO LAST(perRing[i]^) DO
          result[idx] := perRing[i][j];
          INC(idx);
        END;
      END;
      RETURN result
    END;
  END SplitRingsAtAntimeridian;

PROCEDURE ProjectRings(rings : REF ARRAY OF GeoFeature.CoordArray;
                       proj : Projection.T;
                       VAR bb : BBox;
                       discRadius : LONGREAL := 0.0d0) : ProjRingArray =
  VAR
    n : INTEGER;
    result : ProjRingArray;
  BEGIN
    IF rings = NIL THEN RETURN NIL END;
    n := NUMBER(rings^);
    result := NEW(ProjRingArray, n);
    FOR i := 0 TO n - 1 DO
      result[i] := ProjectCoordArray(rings[i], proj, bb,
                                     isRing := TRUE,
                                     discRadius := discRadius);
    END;
    (* For non-disc projections, split rings at the antimeridian.
       Disc projections (orthographic) handle clipping via boundary arcs. *)
    IF discRadius <= 0.0d0 THEN
      result := SplitRingsAtAntimeridian(result);
    END;
    RETURN result
  END ProjectRings;

PROCEDURE ProjectAll(READONLY fc : GeoFeature.FeatureCollection;
                     proj : Projection.T;
                     VAR bb : BBox;
                     discRadius : LONGREAL := 0.0d0) : ProjFeatureArray =
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
      result[i].cssClass := fc.features[i].cssClass;
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
            fc.features[i].geometry.rings, proj, bb,
            discRadius := discRadius);
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

PROCEDURE FeatureClass(cssClass : TEXT) : TEXT =
  (* Return the CSS class attribute value: "feature" or "feature <extra>" *)
  BEGIN
    IF TextEmpty(cssClass) THEN RETURN "feature" END;
    RETURN "feature " & cssClass
  END FeatureClass;

(* ---- SVG element emitters ---- *)

PROCEDURE EmitPoint(wr : Wr.T;
                    READONLY p : ProjPoint;
                    READONLY t : Transform;
                    READONLY cfg : Config;
                    name, cssClass : TEXT) =
  BEGIN
    IF NOT p.valid THEN RETURN END;
    Wr.PutText(wr, "<circle class=\"" & FeatureClass(cssClass) & "\"");
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
                         name, cssClass : TEXT) =
  BEGIN
    IF coords = NIL THEN RETURN END;
    Wr.PutText(wr, "<g class=\"" & FeatureClass(cssClass) & "\"");
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

PROCEDURE EmitBoundaryArc(wr : Wr.T;
                          x1, y1, x2, y2 : LONGREAL;
                          r : LONGREAL;
                          READONLY t : Transform) =
  (* Bridge a visibility gap in a polygon ring by following the disc
     boundary via the SHORTER arc.  Projects the exit point (x1,y1) and
     re-entry point (x2,y2) onto the boundary circle of radius r. *)
  VAR
    len1, len2 : LONGREAL;
    bx1, by1, bx2, by2 : LONGREAL;
    theta1, theta2, dtheta, theta : LONGREAL;
    nSteps : INTEGER;
  BEGIN
    len1 := Math.sqrt(x1 * x1 + y1 * y1);
    IF len1 > 1.0d-10 THEN
      bx1 := x1 * r / len1; by1 := y1 * r / len1;
    ELSE
      bx1 := r; by1 := 0.0d0;
    END;
    len2 := Math.sqrt(x2 * x2 + y2 * y2);
    IF len2 > 1.0d-10 THEN
      bx2 := x2 * r / len2; by2 := y2 * r / len2;
    ELSE
      bx2 := r; by2 := 0.0d0;
    END;
    (* Line to boundary *)
    Wr.PutText(wr, " L" & F(TX(bx1, t)) & "," & F(TY(by1, t)));
    (* Always take the shorter arc *)
    theta1 := Math.atan2(by1, bx1);
    theta2 := Math.atan2(by2, bx2);
    dtheta := theta2 - theta1;
    IF dtheta > Pi THEN dtheta := dtheta - 2.0d0 * Pi
    ELSIF dtheta < -Pi THEN dtheta := dtheta + 2.0d0 * Pi
    END;
    nSteps := TRUNC(ABS(dtheta) * 36.0d0 / Pi) + 1;
    FOR k := 1 TO nSteps DO
      theta := theta1 + dtheta * FLOAT(k, LONGREAL) / FLOAT(nSteps, LONGREAL);
      Wr.PutText(wr, " L" & F(TX(r * Math.cos(theta), t)) &
                      "," & F(TY(r * Math.sin(theta), t)));
    END;
    (* Line from boundary to re-entry point *)
    Wr.PutText(wr, " L" & F(TX(x2, t)) & "," & F(TY(y2, t)));
  END EmitBoundaryArc;

PROCEDURE EmitPolygonRingPath(wr : Wr.T;
                              coords : ProjPointArray;
                              READONLY t : Transform;
                              discRadius : LONGREAL) =
  (* Emits M/L for a polygon ring, skipping invalid points.
     In disc mode (discRadius > 0): bridges visibility gaps by following
     the disc boundary (shorter arc), keeping the path as a single closed
     subpath so SVG fill works correctly.  Also bridges the wrap-around
     gap between last visible point and first M point before Z closure.
     In standard mode: bridges gaps with straight L lines (no pen lifts)
     so the ring stays as a single closed subpath for correct SVG fill.
     The bridge lines typically extend off-screen (e.g., near poles in
     Mercator) and are clipped by the SVG viewport. *)
  VAR needMove := TRUE;
      hasPoints := FALSE;
      hasGap := FALSE;
      firstX, firstY : LONGREAL;
      lastX, lastY : LONGREAL;
  BEGIN
    IF coords = NIL THEN RETURN END;
    FOR i := 0 TO LAST(coords^) DO
      IF coords[i].valid THEN
        IF needMove OR coords[i].penLift THEN
          IF NOT hasPoints THEN
            (* First visible point *)
            Wr.PutText(wr, "M" & F(TX(coords[i].x, t)) &
                           "," & F(TY(coords[i].y, t)));
            hasPoints := TRUE;
            firstX := coords[i].x;
            firstY := coords[i].y;
            IF i > 0 THEN hasGap := TRUE END;
          ELSIF discRadius > 0.0d0 THEN
            (* Disc mode: bridge gap with shorter boundary arc *)
            EmitBoundaryArc(wr, lastX, lastY,
                           coords[i].x, coords[i].y,
                           discRadius, t);
          ELSE
            (* Standard mode: bridge gap with straight line.
               Keeps the ring as a single closed subpath so SVG
               fill works correctly.  The bridge line extends
               off-screen for polar gaps and is viewport-clipped. *)
            Wr.PutText(wr, " L" & F(TX(coords[i].x, t)) &
                            "," & F(TY(coords[i].y, t)));
          END;
          needMove := FALSE;
        ELSE
          Wr.PutText(wr, " L" & F(TX(coords[i].x, t)) &
                          "," & F(TY(coords[i].y, t)));
        END;
        lastX := coords[i].x;
        lastY := coords[i].y;
      ELSE
        needMove := TRUE;
        hasGap := TRUE;
      END;
    END;
    IF hasPoints THEN
      IF discRadius > 0.0d0 AND hasGap THEN
        (* Bridge the wrap-around gap (last visible → first M point) *)
        EmitBoundaryArc(wr, lastX, lastY, firstX, firstY,
                       discRadius, t);
      END;
      Wr.PutText(wr, " Z");
    END;
  END EmitPolygonRingPath;

PROCEDURE EmitLineString(wr : Wr.T;
                         coords : ProjPointArray;
                         READONLY t : Transform;
                         name, cssClass : TEXT) =
  BEGIN
    Wr.PutText(wr, "<path class=\"" & FeatureClass(cssClass) & "\"");
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
                      name, cssClass : TEXT;
                      discRadius : LONGREAL) =
  BEGIN
    IF rings = NIL THEN RETURN END;
    Wr.PutText(wr, "<path class=\"" & FeatureClass(cssClass) & "\" fill-rule=\"evenodd\"");
    IF name # NIL AND NOT TextEmpty(name) THEN
      Wr.PutText(wr, " data-name=\"" & EscapeXML(name) & "\"");
    END;
    Wr.PutText(wr, " d=\"");
    FOR i := 0 TO LAST(rings^) DO
      EmitPolygonRingPath(wr, rings[i], t, discRadius);
    END;
    Wr.PutText(wr, "\"/>\n");
  END EmitPolygon;

PROCEDURE EmitMultiLineString(wr : Wr.T;
                              rings : ProjRingArray;
                              READONLY t : Transform;
                              name, cssClass : TEXT) =
  BEGIN
    IF rings = NIL THEN RETURN END;
    Wr.PutText(wr, "<path class=\"" & FeatureClass(cssClass) & "\"");
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
                           name, cssClass : TEXT;
                           discRadius : LONGREAL) =
  BEGIN
    IF rings = NIL THEN RETURN END;
    Wr.PutText(wr, "<path class=\"" & FeatureClass(cssClass) & "\" fill-rule=\"evenodd\"");
    IF name # NIL AND NOT TextEmpty(name) THEN
      Wr.PutText(wr, " data-name=\"" & EscapeXML(name) & "\"");
    END;
    Wr.PutText(wr, " d=\"");
    FOR i := 0 TO LAST(rings^) DO
      EmitPolygonRingPath(wr, rings[i], t, discRadius);
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
      | GeoFeature.GeometryKind.MultiLineString =>
        IF features[i].geom.rings # NIL THEN
          FOR j := 0 TO LAST(features[i].geom.rings^) DO
            MarkWrapAround(features[i].geom.rings[j], maxDist2);
          END;
        END;
      | GeoFeature.GeometryKind.Polygon,
        GeoFeature.GeometryKind.MultiPolygon =>
        (* Skip wrap-around marking for polygon rings — cross-map
           segments are needed for correct fill.  The disc boundary
           arc handles clipping for bounded projections. *)
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
    features := ProjectAll(fc, proj, bb, cfg.discRadius);

    (* Extend bbox to include disc boundary for bounded projections *)
    IF cfg.discRadius > 0.0d0 THEN
      ExtendBBox(bb, -cfg.discRadius, -cfg.discRadius);
      ExtendBBox(bb, cfg.discRadius, cfg.discRadius);
    END;

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
                    " " & Fmt.Int(cfg.height) & "\"");
    (* Set background on the SVG element itself so it fills the entire
       element even when CSS resizes it beyond the viewBox *)
    IF cfg.discRadius > 0.0d0 THEN
      Wr.PutText(wr, " style=\"background:#0a0a1a\"");
    ELSE
      Wr.PutText(wr, " style=\"background:" & EscapeXML(cfg.background) & "\"");
    END;
    Wr.PutText(wr, ">\n");

    (* Optional globe disc *)
    IF cfg.discRadius > 0.0d0 THEN
      VAR cx := F(TX(0.0d0, t));
          cy := F(TY(0.0d0, t));
          r  := F(cfg.discRadius * t.scale);
      BEGIN
        (* Clip path for the globe disc *)
        Wr.PutText(wr, "<defs><clipPath id=\"globe-clip\">" &
                        "<circle cx=\"" & cx & "\" cy=\"" & cy &
                        "\" r=\"" & r & "\"/>" &
                        "</clipPath></defs>\n");
        (* Ocean disc *)
        Wr.PutText(wr, "<circle cx=\"" & cx & "\" cy=\"" & cy &
                        "\" r=\"" & r &
                        "\" fill=\"" & EscapeXML(cfg.background) & "\"/>\n");
      END;
    END;

    (* Style block *)
    Wr.PutText(wr, "<style>\n");
    Wr.PutText(wr, ".feature { stroke: " & cfg.stroke &
                    "; fill: " & cfg.fill &
                    "; stroke-width: " & F(cfg.strokeWidth) & "; }\n");
    Wr.PutText(wr, ".secondary { stroke: #88aa88; }\n");
    Wr.PutText(wr, ".earth-equator { stroke: #ff4444; fill: none; stroke-width: " &
                    F(cfg.strokeWidth * 1.5d0) & "; }\n");
    Wr.PutText(wr, ".proj-equator { stroke: #4488ff; fill: none; stroke-width: " &
                    F(cfg.strokeWidth * 1.5d0) & "; }\n");
    Wr.PutText(wr, "</style>\n");

    (* Features — clipped to globe disc when applicable *)
    IF cfg.discRadius > 0.0d0 THEN
      Wr.PutText(wr, "<g clip-path=\"url(#globe-clip)\">\n");
    END;

    IF features # NIL THEN
      FOR i := 0 TO LAST(features^) DO
        CASE features[i].geom.kind OF
        | GeoFeature.GeometryKind.Point =>
          IF features[i].geom.coords # NIL AND
             NUMBER(features[i].geom.coords^) > 0 THEN
            EmitPoint(wr, features[i].geom.coords[0], t, cfg,
                      features[i].name, features[i].cssClass);
          END;
        | GeoFeature.GeometryKind.MultiPoint =>
          EmitMultiPoint(wr, features[i].geom.coords, t, cfg,
                         features[i].name, features[i].cssClass);
        | GeoFeature.GeometryKind.LineString =>
          EmitLineString(wr, features[i].geom.coords, t,
                         features[i].name, features[i].cssClass);
        | GeoFeature.GeometryKind.Polygon =>
          EmitPolygon(wr, features[i].geom.rings, t,
                      features[i].name, features[i].cssClass,
                      cfg.discRadius);
        | GeoFeature.GeometryKind.MultiLineString =>
          EmitMultiLineString(wr, features[i].geom.rings, t,
                              features[i].name, features[i].cssClass);
        | GeoFeature.GeometryKind.MultiPolygon =>
          EmitMultiPolygon(wr, features[i].geom.rings, t,
                           features[i].name, features[i].cssClass,
                           cfg.discRadius);
        END;
      END;
    END;

    IF cfg.discRadius > 0.0d0 THEN
      Wr.PutText(wr, "</g>\n");
    END;

    Wr.PutText(wr, "</svg>\n");
  END WriteWr;

BEGIN
END SvgWriter.
