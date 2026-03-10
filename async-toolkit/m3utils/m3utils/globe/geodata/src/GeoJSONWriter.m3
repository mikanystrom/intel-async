(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE GeoJSONWriter;

IMPORT Projection, GeoCoord, GeoFeature, Wr, Fmt, Text, Thread, FileWr, OSError;

<*FATAL Thread.Alerted, Wr.Failure*>

PROCEDURE WriteFile(path : TEXT;
                    READONLY fc : GeoFeature.FeatureCollection;
                    proj : Projection.T) =
  VAR wr : Wr.T;
  BEGIN
    TRY
      wr := FileWr.Open(path);
    EXCEPT
      OSError.E => RETURN
    END;
    WriteWr(wr, fc, proj);
    Wr.Close(wr);
  END WriteFile;

PROCEDURE WriteWr(wr : Wr.T;
                  READONLY fc : GeoFeature.FeatureCollection;
                  proj : Projection.T) =
  BEGIN
    Wr.PutText(wr, "{\"type\":\"FeatureCollection\",\"features\":[\n");
    IF fc.features # NIL THEN
      FOR i := 0 TO LAST(fc.features^) DO
        IF i > 0 THEN Wr.PutText(wr, ",\n") END;
        WriteFeature(wr, fc.features[i], proj);
      END;
    END;
    Wr.PutText(wr, "\n]}\n");
  END WriteWr;

PROCEDURE WriteFeature(wr : Wr.T;
                       READONLY f : GeoFeature.Feature;
                       proj : Projection.T) =
  BEGIN
    Wr.PutText(wr, "{\"type\":\"Feature\",\"geometry\":");
    WriteGeometry(wr, f.geometry, proj);
    Wr.PutText(wr, ",\"properties\":{");
    IF f.name # NIL AND NOT TextEmpty(f.name) THEN
      Wr.PutText(wr, "\"name\":" & QuoteText(f.name));
    END;
    Wr.PutText(wr, "}}");
  END WriteFeature;

PROCEDURE WriteGeometry(wr : Wr.T;
                        READONLY g : GeoFeature.Geometry;
                        proj : Projection.T) =
  BEGIN
    CASE g.kind OF
    | GeoFeature.GeometryKind.Point =>
      Wr.PutText(wr, "{\"type\":\"Point\",\"coordinates\":");
      IF g.coords # NIL AND NUMBER(g.coords^) > 0 THEN
        WriteProjectedCoord(wr, g.coords[0], proj);
      ELSE
        Wr.PutText(wr, "[0,0]");
      END;
      Wr.PutText(wr, "}");

    | GeoFeature.GeometryKind.LineString =>
      Wr.PutText(wr, "{\"type\":\"LineString\",\"coordinates\":");
      WriteProjectedCoordArray(wr, g.coords, proj);
      Wr.PutText(wr, "}");

    | GeoFeature.GeometryKind.Polygon =>
      Wr.PutText(wr, "{\"type\":\"Polygon\",\"coordinates\":");
      WriteProjectedRings(wr, g.rings, proj);
      Wr.PutText(wr, "}");

    | GeoFeature.GeometryKind.MultiPoint =>
      Wr.PutText(wr, "{\"type\":\"MultiPoint\",\"coordinates\":");
      WriteProjectedCoordArray(wr, g.coords, proj);
      Wr.PutText(wr, "}");

    | GeoFeature.GeometryKind.MultiLineString =>
      Wr.PutText(wr, "{\"type\":\"MultiLineString\",\"coordinates\":");
      WriteProjectedRings(wr, g.rings, proj);
      Wr.PutText(wr, "}");

    | GeoFeature.GeometryKind.MultiPolygon =>
      (* Write as MultiLineString for simplicity — the rings are already flattened *)
      Wr.PutText(wr, "{\"type\":\"MultiPolygon\",\"coordinates\":");
      IF g.rings # NIL THEN
        Wr.PutText(wr, "[[");
        FOR i := 0 TO LAST(g.rings^) DO
          IF i > 0 THEN Wr.PutText(wr, "],[") END;
          WriteProjectedCoordArrayInner(wr, g.rings[i], proj);
        END;
        Wr.PutText(wr, "]]");
      ELSE
        Wr.PutText(wr, "[]");
      END;
      Wr.PutText(wr, "}");
    END
  END WriteGeometry;

PROCEDURE WriteProjectedCoord(wr : Wr.T;
                              READONLY ll : GeoCoord.LatLon;
                              proj : Projection.T) =
  VAR xy : GeoCoord.XY;
  BEGIN
    IF proj.forward(ll, xy) THEN
      Wr.PutText(wr, "[" & Fmt.LongReal(xy.x, Fmt.Style.Fix, 6) & "," &
                            Fmt.LongReal(xy.y, Fmt.Style.Fix, 6) & "]");
    ELSE
      Wr.PutText(wr, "null");
    END
  END WriteProjectedCoord;

PROCEDURE WriteProjectedCoordArray(wr : Wr.T;
                                   coords : GeoFeature.CoordArray;
                                   proj : Projection.T) =
  BEGIN
    Wr.PutText(wr, "[");
    WriteProjectedCoordArrayInner(wr, coords, proj);
    Wr.PutText(wr, "]");
  END WriteProjectedCoordArray;

PROCEDURE WriteProjectedCoordArrayInner(wr : Wr.T;
                                        coords : GeoFeature.CoordArray;
                                        proj : Projection.T) =
  VAR first := TRUE;
  BEGIN
    IF coords # NIL THEN
      FOR i := 0 TO LAST(coords^) DO
        VAR xy : GeoCoord.XY;
        BEGIN
          IF proj.forward(coords[i], xy) THEN
            IF NOT first THEN Wr.PutText(wr, ",") END;
            Wr.PutText(wr, "[" & Fmt.LongReal(xy.x, Fmt.Style.Fix, 6) & "," &
                                  Fmt.LongReal(xy.y, Fmt.Style.Fix, 6) & "]");
            first := FALSE;
          END
        END
      END
    END
  END WriteProjectedCoordArrayInner;

PROCEDURE WriteProjectedRings(wr : Wr.T;
                              rings : REF ARRAY OF GeoFeature.CoordArray;
                              proj : Projection.T) =
  BEGIN
    Wr.PutText(wr, "[");
    IF rings # NIL THEN
      FOR i := 0 TO LAST(rings^) DO
        IF i > 0 THEN Wr.PutText(wr, ",") END;
        WriteProjectedCoordArray(wr, rings[i], proj);
      END;
    END;
    Wr.PutText(wr, "]");
  END WriteProjectedRings;

PROCEDURE TextEmpty(t : TEXT) : BOOLEAN =
  BEGIN
    RETURN t = NIL OR Text.Length(t) = 0
  END TextEmpty;

PROCEDURE QuoteText(t : TEXT) : TEXT =
  BEGIN
    RETURN "\"" & EscapeJSON(t) & "\""
  END QuoteText;

PROCEDURE EscapeJSON(t : TEXT) : TEXT =
  VAR
    result : TEXT := "";
    c : CHAR;
  BEGIN
    IF t = NIL THEN RETURN "" END;
    FOR i := 0 TO Text.Length(t) - 1 DO
      c := Text.GetChar(t, i);
      IF c = '\"' THEN
        result := result & "\\\"";
      ELSIF c = '\\' THEN
        result := result & "\\\\";
      ELSIF c = '\n' THEN
        result := result & "\\n";
      ELSIF c = '\r' THEN
        result := result & "\\r";
      ELSIF c = '\t' THEN
        result := result & "\\t";
      ELSE
        result := result & Text.FromChar(c);
      END
    END;
    RETURN result
  END EscapeJSON;

BEGIN
END GeoJSONWriter.
