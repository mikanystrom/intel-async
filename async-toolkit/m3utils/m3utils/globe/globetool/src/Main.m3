(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE Main;

IMPORT Params, Text, Fmt, Wr, Stdio, Process;
IMPORT GeoCoord, Projection, GeoJSON, GeoJSONWriter, SvgWriter, GeoFeature;
IMPORT Equirectangular, Mercator, TransverseMercator;
IMPORT Stereographic, LambertConformalConic, AlbersEqualArea;
IMPORT AzimuthalEquidistant, Orthographic, Robinson;
IMPORT Oblique, Airport, GreatCircle, Thread;

<*FATAL Thread.Alerted, Wr.Failure*>

VAR
  projName    : TEXT := "equirectangular";
  inputFile   : TEXT := NIL;
  outputFile  : TEXT := NIL;
  centerLat   : LONGREAL := 0.0d0;
  centerLon   : LONGREAL := 0.0d0;
  lat1        : LONGREAL := 30.0d0;
  lat2        : LONGREAL := 60.0d0;
  obliqueA    : GeoCoord.LatLon;
  obliqueB    : GeoCoord.LatLon;
  useOblique  : BOOLEAN := FALSE;
  overlayEarthEq : BOOLEAN := FALSE;
  overlayProjEq  : BOOLEAN := FALSE;
  format      : TEXT := "geojson";
  svgConfig   : SvgWriter.Config;

PROCEDURE Usage() =
  BEGIN
    Wr.PutText(Stdio.stderr,
      "Usage: globetool [options]\n" &
      "  -projection <name>    Projection name (default: equirectangular)\n" &
      "  -input <file>         Input GeoJSON file\n" &
      "  -output <file>        Output file\n" &
      "  -format <fmt>         Output format: geojson or svg (default: geojson)\n" &
      "  -center <lat> <lon>   Center point in degrees (for azimuthal projections)\n" &
      "  -parallels <lat1> <lat2>  Standard parallels in degrees (for conic)\n" &
      "  -oblique <lat1> <lon1> <lat2> <lon2>  Two points defining custom equator\n" &
      "  -greatcircle <code1> <code2>  Airport codes (ICAO/IATA) for oblique equator\n" &
      "  -overlay-earth-equator       Add Earth's equator (lat=0) as a LineString\n" &
      "  -overlay-proj-equator        Add projection equator as a LineString\n" &
      "\n" &
      "SVG options (only with -format svg):\n" &
      "  -width <N>            SVG width in pixels (default: 1024)\n" &
      "  -height <N>           SVG height in pixels (default: 512)\n" &
      "  -stroke-width <N.N>   Stroke width (default: 0.5)\n" &
      "  -stroke <color>       Stroke color (default: #333333)\n" &
      "  -fill <color>         Fill color (default: none)\n" &
      "  -background <color>   Background color (default: #ffffff)\n" &
      "  -point-radius <N.N>   Point radius (default: 2.0)\n" &
      "\n" &
      "Projections: equirectangular, mercator, transversemercator, stereographic,\n" &
      "  lambertconformalconic, albersequalarea, azimuthalequidistant, orthographic,\n" &
      "  robinson\n" &
      "\n" &
      "Airport codes: use ICAO (4-letter) or IATA (3-letter) codes.\n" &
      "  Example: -greatcircle LHR NRT  (London Heathrow to Tokyo Narita)\n");
  END Usage;

PROCEDURE ResolveAirport(code : TEXT) : GeoCoord.LatLon =
  VAR a := Airport.Lookup(code);
  BEGIN
    IF a = NIL THEN
      Wr.PutText(Stdio.stderr, "Unknown airport code: " & code & "\n");
      Process.Exit(1);
    END;
    Wr.PutText(Stdio.stderr,
      "  " & a.iata & "/" & a.icao & " " & a.name & "\n");
    RETURN a.loc
  END ResolveAirport;

PROCEDURE ParseArgs() =
  VAR i := 1;
  BEGIN
    WHILE i < Params.Count DO
      VAR arg := Params.Get(i);
      BEGIN
        IF Text.Equal(arg, "-projection") AND i + 1 < Params.Count THEN
          INC(i); projName := ToLower(Params.Get(i));

        ELSIF Text.Equal(arg, "-input") AND i + 1 < Params.Count THEN
          INC(i); inputFile := Params.Get(i);

        ELSIF Text.Equal(arg, "-output") AND i + 1 < Params.Count THEN
          INC(i); outputFile := Params.Get(i);

        ELSIF Text.Equal(arg, "-center") AND i + 2 < Params.Count THEN
          INC(i); centerLat := ScanLongReal(Params.Get(i));
          INC(i); centerLon := ScanLongReal(Params.Get(i));

        ELSIF Text.Equal(arg, "-parallels") AND i + 2 < Params.Count THEN
          INC(i); lat1 := ScanLongReal(Params.Get(i));
          INC(i); lat2 := ScanLongReal(Params.Get(i));

        ELSIF Text.Equal(arg, "-oblique") AND i + 4 < Params.Count THEN
          INC(i);
          VAR oLat1 := ScanLongReal(Params.Get(i)); BEGIN INC(i);
          VAR oLon1 := ScanLongReal(Params.Get(i)); BEGIN INC(i);
          VAR oLat2 := ScanLongReal(Params.Get(i)); BEGIN INC(i);
          VAR oLon2 := ScanLongReal(Params.Get(i)); BEGIN
          obliqueA := GeoCoord.LatLonDeg(oLat1, oLon1);
          obliqueB := GeoCoord.LatLonDeg(oLat2, oLon2);
          useOblique := TRUE;
          END END END END;

        ELSIF Text.Equal(arg, "-greatcircle") AND i + 2 < Params.Count THEN
          INC(i);
          Wr.PutText(Stdio.stderr, "Resolving great circle airports:\n");
          obliqueA := ResolveAirport(Params.Get(i));
          INC(i);
          obliqueB := ResolveAirport(Params.Get(i));
          useOblique := TRUE;

        ELSIF Text.Equal(arg, "-format") AND i + 1 < Params.Count THEN
          INC(i); format := ToLower(Params.Get(i));

        ELSIF Text.Equal(arg, "-width") AND i + 1 < Params.Count THEN
          INC(i); svgConfig.width := ScanCardinal(Params.Get(i));

        ELSIF Text.Equal(arg, "-height") AND i + 1 < Params.Count THEN
          INC(i); svgConfig.height := ScanCardinal(Params.Get(i));

        ELSIF Text.Equal(arg, "-stroke-width") AND i + 1 < Params.Count THEN
          INC(i); svgConfig.strokeWidth := ScanLongReal(Params.Get(i));

        ELSIF Text.Equal(arg, "-stroke") AND i + 1 < Params.Count THEN
          INC(i); svgConfig.stroke := Params.Get(i);

        ELSIF Text.Equal(arg, "-fill") AND i + 1 < Params.Count THEN
          INC(i); svgConfig.fill := Params.Get(i);

        ELSIF Text.Equal(arg, "-background") AND i + 1 < Params.Count THEN
          INC(i); svgConfig.background := Params.Get(i);

        ELSIF Text.Equal(arg, "-point-radius") AND i + 1 < Params.Count THEN
          INC(i); svgConfig.pointRadius := ScanLongReal(Params.Get(i));

        ELSIF Text.Equal(arg, "-overlay-earth-equator") THEN
          overlayEarthEq := TRUE;

        ELSIF Text.Equal(arg, "-overlay-proj-equator") THEN
          overlayProjEq := TRUE;

        ELSIF Text.Equal(arg, "-help") OR Text.Equal(arg, "-h") THEN
          Usage();
          Process.Exit(0);

        ELSE
          Wr.PutText(Stdio.stderr, "Unknown argument: " & arg & "\n");
          Usage();
          Process.Exit(1);
        END
      END;
      INC(i);
    END;
  END ParseArgs;

PROCEDURE MakeProjection() : Projection.T =
  VAR
    center := GeoCoord.LatLonDeg(centerLat, centerLon);
    p : Projection.T;
  BEGIN
    IF Text.Equal(projName, "equirectangular") THEN
      p := Equirectangular.New();
    ELSIF Text.Equal(projName, "mercator") THEN
      p := Mercator.New();
    ELSIF Text.Equal(projName, "transversemercator") THEN
      p := TransverseMercator.New(centerLon * GeoCoord.DegToRad);
    ELSIF Text.Equal(projName, "stereographic") THEN
      p := Stereographic.New(center);
    ELSIF Text.Equal(projName, "lambertconformalconic") THEN
      p := LambertConformalConic.New(lat1 * GeoCoord.DegToRad,
                                     lat2 * GeoCoord.DegToRad,
                                     centerLat * GeoCoord.DegToRad,
                                     centerLon * GeoCoord.DegToRad);
    ELSIF Text.Equal(projName, "albersequalarea") THEN
      p := AlbersEqualArea.New(lat1 * GeoCoord.DegToRad,
                                lat2 * GeoCoord.DegToRad,
                                centerLat * GeoCoord.DegToRad,
                                centerLon * GeoCoord.DegToRad);
    ELSIF Text.Equal(projName, "azimuthalequidistant") THEN
      p := AzimuthalEquidistant.New(center);
    ELSIF Text.Equal(projName, "orthographic") THEN
      p := Orthographic.New(center);
    ELSIF Text.Equal(projName, "robinson") THEN
      p := Robinson.New();
    ELSE
      Wr.PutText(Stdio.stderr, "Unknown projection: " & projName & "\n");
      Process.Exit(1);
      p := Equirectangular.New();  (* unreachable *)
    END;

    IF useOblique THEN
      p := Oblique.FromTwoPoints(p, obliqueA, obliqueB);
    END;

    RETURN p
  END MakeProjection;

PROCEDURE ToLower(t : TEXT) : TEXT =
  VAR
    result : TEXT := "";
    c : CHAR;
  BEGIN
    FOR i := 0 TO Text.Length(t) - 1 DO
      c := Text.GetChar(t, i);
      IF c >= 'A' AND c <= 'Z' THEN
        c := VAL(ORD(c) - ORD('A') + ORD('a'), CHAR);
      END;
      result := result & Text.FromChar(c);
    END;
    RETURN result
  END ToLower;

PROCEDURE ScanLongReal(t : TEXT) : LONGREAL =
  VAR
    i := 0;
    n := Text.Length(t);
    sign := 1.0d0;
    intPart := 0.0d0;
    fracPart := 0.0d0;
    fracDiv := 1.0d0;
    hasDot := FALSE;
    c : CHAR;
  BEGIN
    IF i < n AND Text.GetChar(t, i) = '-' THEN
      sign := -1.0d0;
      INC(i);
    END;
    WHILE i < n DO
      c := Text.GetChar(t, i);
      IF c >= '0' AND c <= '9' THEN
        IF hasDot THEN
          fracDiv := fracDiv * 10.0d0;
          fracPart := fracPart + FLOAT(ORD(c) - ORD('0'), LONGREAL) / fracDiv;
        ELSE
          intPart := intPart * 10.0d0 + FLOAT(ORD(c) - ORD('0'), LONGREAL);
        END;
      ELSIF c = '.' THEN
        hasDot := TRUE;
      ELSE
        EXIT
      END;
      INC(i);
    END;
    RETURN sign * (intPart + fracPart)
  END ScanLongReal;

PROCEDURE ScanCardinal(t : TEXT) : CARDINAL =
  VAR
    i := 0;
    n := Text.Length(t);
    result : CARDINAL := 0;
    c : CHAR;
  BEGIN
    WHILE i < n DO
      c := Text.GetChar(t, i);
      IF c >= '0' AND c <= '9' THEN
        result := result * 10 + ORD(c) - ORD('0');
      ELSE
        EXIT
      END;
      INC(i);
    END;
    RETURN result
  END ScanCardinal;

CONST NumEquatorPts = 361;

PROCEDURE GenerateEquator() : GeoFeature.Feature =
  VAR
    f : GeoFeature.Feature;
    coords := NEW(GeoFeature.CoordArray, NumEquatorPts);
  BEGIN
    FOR i := 0 TO NumEquatorPts - 1 DO
      VAR lonDeg := -180.0d0 + FLOAT(i, LONGREAL); BEGIN
      coords[i] := GeoCoord.LatLonDeg(0.0d0, lonDeg);
      END;
    END;
    f.geometry.kind := GeoFeature.GeometryKind.LineString;
    f.geometry.coords := coords;
    f.geometry.rings := NIL;
    f.name := "Earth Equator";
    f.cssClass := "earth-equator";
    f.properties := NIL;
    RETURN f
  END GenerateEquator;

PROCEDURE GenerateProjEquator(READONLY rot : GreatCircle.Rotation) : GeoFeature.Feature =
  VAR
    f : GeoFeature.Feature;
    coords := NEW(GeoFeature.CoordArray, NumEquatorPts);
  BEGIN
    FOR i := 0 TO NumEquatorPts - 1 DO
      VAR lonDeg := -180.0d0 + FLOAT(i, LONGREAL);
          rotated := GeoCoord.LatLonDeg(0.0d0, lonDeg);
      BEGIN
      coords[i] := GreatCircle.RotateInverse(rot, rotated);
      END;
    END;
    f.geometry.kind := GeoFeature.GeometryKind.LineString;
    f.geometry.coords := coords;
    f.geometry.rings := NIL;
    f.name := "Projection Equator";
    f.cssClass := "proj-equator";
    f.properties := NIL;
    RETURN f
  END GenerateProjEquator;

BEGIN
  ParseArgs();

  IF inputFile = NIL THEN
    Wr.PutText(Stdio.stderr, "Error: -input is required\n");
    Usage();
    Process.Exit(1);
  END;
  IF outputFile = NIL THEN
    Wr.PutText(Stdio.stderr, "Error: -output is required\n");
    Usage();
    Process.Exit(1);
  END;

  VAR
    proj := MakeProjection();
    fc : GeoFeature.FeatureCollection;
  BEGIN
    TRY
      fc := GeoJSON.ReadFile(inputFile);
    EXCEPT
      GeoJSON.Error(msg) =>
        Wr.PutText(Stdio.stderr, "GeoJSON error: " & msg & "\n");
        Process.Exit(1);
    END;

    (* Add overlay features if requested *)
    VAR extra := 0; BEGIN
      IF overlayEarthEq THEN INC(extra) END;
      IF overlayProjEq THEN INC(extra) END;
      IF extra > 0 THEN
        VAR
          n := NUMBER(fc.features^);
          newArr := NEW(GeoFeature.FeatureArray, n + extra);
          idx := n;
        BEGIN
          SUBARRAY(newArr^, 0, n) := fc.features^;
          IF overlayEarthEq THEN
            newArr[idx] := GenerateEquator();
            INC(idx);
          END;
          IF overlayProjEq THEN
            IF useOblique THEN
              VAR rot := GreatCircle.ComputeRotation(obliqueA, obliqueB); BEGIN
              newArr[idx] := GenerateProjEquator(rot);
              END;
            ELSE
              newArr[idx] := GenerateEquator();
              newArr[idx].name := "Projection Equator";
            END;
            INC(idx);
          END;
          fc.features := newArr;
        END;
      END;
    END;

    Wr.PutText(Stdio.stdout,
      "Projection: " & proj.name & "\n" &
      "Features:   " & Fmt.Int(NUMBER(fc.features^)) & "\n" &
      "Output:     " & outputFile & "\n");

    IF Text.Equal(format, "svg") THEN
      SvgWriter.WriteFile(outputFile, fc, proj, svgConfig);
    ELSE
      GeoJSONWriter.WriteFile(outputFile, fc, proj);
    END;
  END;
END Main.
