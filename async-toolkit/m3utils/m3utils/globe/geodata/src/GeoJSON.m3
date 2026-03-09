(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE GeoJSON;

IMPORT Json, GeoCoord, GeoFeature, Text, Fmt;

PROCEDURE ReadFile(path : TEXT) : GeoFeature.FeatureCollection RAISES {Error} =
  VAR root : Json.T;
  BEGIN
    TRY
      root := Json.ParseFile(path);
    EXCEPT
      Json.E => RAISE Error("Failed to parse JSON file: " & path);
    END;
    RETURN ParseRoot(root)
  END ReadFile;

PROCEDURE ReadText(text : TEXT) : GeoFeature.FeatureCollection RAISES {Error} =
  VAR root : Json.T;
  BEGIN
    TRY
      root := Json.ParseBuf(text);
    EXCEPT
      Json.E => RAISE Error("Failed to parse JSON text");
    END;
    RETURN ParseRoot(root)
  END ReadText;

PROCEDURE ParseRoot(root : Json.T) : GeoFeature.FeatureCollection RAISES {Error} =
  VAR
    typeNode := root.find("/type");
    typeName : TEXT;
  BEGIN
    IF typeNode = NIL THEN RAISE Error("Missing 'type' field") END;
    typeName := typeNode.value();
    IF Text.Equal(typeName, "FeatureCollection") THEN
      RETURN ParseFeatureCollection(root)
    ELSIF Text.Equal(typeName, "Feature") THEN
      VAR
        fc : GeoFeature.FeatureCollection;
        f := ParseFeature(root);
      BEGIN
        fc.features := NEW(GeoFeature.FeatureArray, 1);
        fc.features[0] := f;
        RETURN fc
      END
    ELSE
      (* Bare geometry *)
      VAR
        fc : GeoFeature.FeatureCollection;
        f : GeoFeature.Feature;
      BEGIN
        f.geometry := ParseGeometry(root);
        f.name := "";
        f.cssClass := "";
        f.properties := "";
        fc.features := NEW(GeoFeature.FeatureArray, 1);
        fc.features[0] := f;
        RETURN fc
      END
    END
  END ParseRoot;

(* Access the i-th element of a JSON array by index.
   The CM3 Json library's iterate() returns elements in lexicographic
   key order ("0","1","10","100",...,"2",...) which scrambles arrays
   with 10+ elements.  Using find("/" & Fmt.Int(i)) returns the
   correct element by its numeric index. *)
PROCEDURE ArrayGet(node : Json.T; i : CARDINAL) : Json.T =
  BEGIN
    RETURN node.find("/" & Fmt.Int(i))
  END ArrayGet;

PROCEDURE ParseFeatureCollection(node : Json.T) : GeoFeature.FeatureCollection
    RAISES {Error} =
  VAR
    featuresNode := node.find("/features");
    fc : GeoFeature.FeatureCollection;
    n : CARDINAL;
    child : Json.T;
  BEGIN
    IF featuresNode = NIL THEN RAISE Error("Missing 'features' array") END;
    n := featuresNode.size();
    fc.features := NEW(GeoFeature.FeatureArray, n);
    FOR i := 0 TO n - 1 DO
      child := ArrayGet(featuresNode, i);
      IF child = NIL THEN RAISE Error("Missing feature at index " & Fmt.Int(i)) END;
      fc.features[i] := ParseFeature(child);
    END;
    RETURN fc
  END ParseFeatureCollection;

PROCEDURE ParseFeature(node : Json.T) : GeoFeature.Feature RAISES {Error} =
  VAR
    f : GeoFeature.Feature;
    geomNode := node.find("/geometry");
    propsNode := node.find("/properties");
    nameNode, classNode : Json.T;
  BEGIN
    IF geomNode = NIL THEN RAISE Error("Feature missing 'geometry'") END;
    f.geometry := ParseGeometry(geomNode);

    IF propsNode # NIL THEN
      f.properties := propsNode.format();
      (* Try to extract a name *)
      nameNode := propsNode.find("/NAME");
      IF nameNode = NIL THEN nameNode := propsNode.find("/name") END;
      IF nameNode = NIL THEN nameNode := propsNode.find("/Name") END;
      IF nameNode # NIL THEN f.name := nameNode.value() ELSE f.name := "" END;
      (* Try to extract a CSS class hint *)
      classNode := propsNode.find("/_class");
      IF classNode # NIL THEN f.cssClass := classNode.value() ELSE f.cssClass := "" END;
    ELSE
      f.properties := "";
      f.name := "";
      f.cssClass := "";
    END;
    RETURN f
  END ParseFeature;

PROCEDURE ParseGeometry(node : Json.T) : GeoFeature.Geometry RAISES {Error} =
  VAR
    typeNode := node.find("/type");
    coordsNode := node.find("/coordinates");
    typeName : TEXT;
    g : GeoFeature.Geometry;
  BEGIN
    IF typeNode = NIL THEN RAISE Error("Geometry missing 'type'") END;
    typeName := typeNode.value();
    IF coordsNode = NIL THEN RAISE Error("Geometry missing 'coordinates'") END;

    IF Text.Equal(typeName, "Point") THEN
      g.kind := GeoFeature.GeometryKind.Point;
      g.coords := NEW(GeoFeature.CoordArray, 1);
      g.coords[0] := ParseCoordinate(coordsNode);

    ELSIF Text.Equal(typeName, "LineString") THEN
      g.kind := GeoFeature.GeometryKind.LineString;
      g.coords := ParseCoordArray(coordsNode);

    ELSIF Text.Equal(typeName, "Polygon") THEN
      g.kind := GeoFeature.GeometryKind.Polygon;
      g.rings := ParseRings(coordsNode);
      IF NUMBER(g.rings^) > 0 THEN g.coords := g.rings[0] END;

    ELSIF Text.Equal(typeName, "MultiPoint") THEN
      g.kind := GeoFeature.GeometryKind.MultiPoint;
      g.coords := ParseCoordArray(coordsNode);

    ELSIF Text.Equal(typeName, "MultiLineString") THEN
      g.kind := GeoFeature.GeometryKind.MultiLineString;
      g.rings := ParseRings(coordsNode);

    ELSIF Text.Equal(typeName, "MultiPolygon") THEN
      g.kind := GeoFeature.GeometryKind.MultiPolygon;
      g.rings := ParseMultiPolygonRings(coordsNode);

    ELSE
      RAISE Error("Unknown geometry type: " & typeName)
    END;
    RETURN g
  END ParseGeometry;

PROCEDURE ParseCoordinate(node : Json.T) : GeoCoord.LatLon RAISES {Error} =
  VAR
    n := node.size();
    child : Json.T;
    vals : ARRAY [0..2] OF LONGREAL;
    cnt : CARDINAL;
  BEGIN
    IF n > 3 THEN cnt := 3 ELSE cnt := n END;
    FOR i := 0 TO cnt - 1 DO
      child := ArrayGet(node, i);
      IF child = NIL THEN RAISE Error("Missing coordinate value") END;
      TRY
        IF child.kind() = Json.NodeKind.nkInt THEN
          vals[i] := FLOAT(child.getInt(), LONGREAL);
        ELSIF child.kind() = Json.NodeKind.nkFloat THEN
          vals[i] := child.getFloat();
        ELSE
          RAISE Error("Invalid coordinate value")
        END
      EXCEPT
        Json.E => RAISE Error("Invalid coordinate value")
      END;
    END;
    IF cnt < 2 THEN RAISE Error("Coordinate needs at least 2 values") END;
    (* GeoJSON is [longitude, latitude] *)
    RETURN GeoCoord.LatLonDeg(vals[1], vals[0])
  END ParseCoordinate;

PROCEDURE ParseCoordArray(node : Json.T) : GeoFeature.CoordArray RAISES {Error} =
  VAR
    n := node.size();
    arr := NEW(GeoFeature.CoordArray, n);
    child : Json.T;
  BEGIN
    FOR i := 0 TO n - 1 DO
      child := ArrayGet(node, i);
      IF child = NIL THEN RAISE Error("Missing coordinate at index " & Fmt.Int(i)) END;
      arr[i] := ParseCoordinate(child);
    END;
    RETURN arr
  END ParseCoordArray;

PROCEDURE ParseRings(node : Json.T) : REF ARRAY OF GeoFeature.CoordArray
    RAISES {Error} =
  VAR
    n := node.size();
    rings := NEW(REF ARRAY OF GeoFeature.CoordArray, n);
    child : Json.T;
  BEGIN
    FOR i := 0 TO n - 1 DO
      child := ArrayGet(node, i);
      IF child = NIL THEN RAISE Error("Missing ring at index " & Fmt.Int(i)) END;
      rings[i] := ParseCoordArray(child);
    END;
    RETURN rings
  END ParseRings;

PROCEDURE ParseMultiPolygonRings(node : Json.T) : REF ARRAY OF GeoFeature.CoordArray
    RAISES {Error} =
  (* Flatten MultiPolygon: array of polygons, each polygon is array of rings.
     We flatten to just an array of rings (outer rings + holes together). *)
  VAR
    nPolys := node.size();
    totalRings : CARDINAL := 0;
    polyChild, ringChild : Json.T;
    result : REF ARRAY OF GeoFeature.CoordArray;
    idx : CARDINAL := 0;
  BEGIN
    (* First pass: count total rings *)
    FOR p := 0 TO nPolys - 1 DO
      polyChild := ArrayGet(node, p);
      IF polyChild # NIL THEN
        totalRings := totalRings + polyChild.size();
      END;
    END;
    result := NEW(REF ARRAY OF GeoFeature.CoordArray, totalRings);
    (* Second pass: parse rings *)
    FOR p := 0 TO nPolys - 1 DO
      polyChild := ArrayGet(node, p);
      IF polyChild # NIL THEN
        FOR r := 0 TO polyChild.size() - 1 DO
          ringChild := ArrayGet(polyChild, r);
          IF ringChild = NIL THEN RAISE Error("Missing ring in MultiPolygon") END;
          result[idx] := ParseCoordArray(ringChild);
          INC(idx);
        END;
      END;
    END;
    RETURN result
  END ParseMultiPolygonRings;

BEGIN
END GeoJSON.
