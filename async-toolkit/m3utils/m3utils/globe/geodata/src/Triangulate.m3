(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE Triangulate;

IMPORT GeoCoord, GeoFeature, TriMesh, GreatCircle, Math;

(* ---- Growable buffers ---- *)

TYPE
  TriBuf = RECORD
    data  : REF ARRAY OF TriMesh.Triangle;
    count : INTEGER := 0;
  END;

  VertBuf = RECORD
    data  : REF ARRAY OF TriMesh.Vertex;
    count : INTEGER := 0;
  END;

  EdgeEntry = RECORD
    i1, i2 : INTEGER;        (* vertex indices, i1 < i2 *)
    mid    : TriMesh.Vertex;
  END;

  EdgeTable = RECORD
    data  : REF ARRAY OF EdgeEntry;
    count : INTEGER := 0;
  END;

PROCEDURE InitTriBuf(VAR buf : TriBuf; cap : INTEGER) =
  BEGIN
    buf.data := NEW(REF ARRAY OF TriMesh.Triangle, cap);
    buf.count := 0;
  END InitTriBuf;

PROCEDURE AddTri(VAR buf : TriBuf; READONLY tri : TriMesh.Triangle) =
  VAR newData : REF ARRAY OF TriMesh.Triangle;
  BEGIN
    IF buf.count >= NUMBER(buf.data^) THEN
      newData := NEW(REF ARRAY OF TriMesh.Triangle, NUMBER(buf.data^) * 2);
      SUBARRAY(newData^, 0, buf.count) := SUBARRAY(buf.data^, 0, buf.count);
      buf.data := newData;
    END;
    buf.data[buf.count] := tri;
    INC(buf.count);
  END AddTri;

PROCEDURE InitVertBuf(VAR buf : VertBuf; cap : INTEGER) =
  BEGIN
    buf.data := NEW(REF ARRAY OF TriMesh.Vertex, cap);
    buf.count := 0;
  END InitVertBuf;

PROCEDURE AddVert(VAR buf : VertBuf; v : TriMesh.Vertex) : INTEGER =
  VAR
    newData : REF ARRAY OF TriMesh.Vertex;
    idx : INTEGER;
  BEGIN
    IF buf.count >= NUMBER(buf.data^) THEN
      newData := NEW(REF ARRAY OF TriMesh.Vertex, NUMBER(buf.data^) * 2);
      SUBARRAY(newData^, 0, buf.count) := SUBARRAY(buf.data^, 0, buf.count);
      buf.data := newData;
    END;
    idx := buf.count;
    v.idx := idx;
    buf.data[idx] := v;
    INC(buf.count);
    RETURN idx;
  END AddVert;

PROCEDURE InitEdgeTable(VAR tbl : EdgeTable; cap : INTEGER) =
  BEGIN
    tbl.data := NEW(REF ARRAY OF EdgeEntry, cap);
    tbl.count := 0;
  END InitEdgeTable;

PROCEDURE FindEdgeMid(VAR tbl : EdgeTable;
                      i1, i2 : INTEGER) : TriMesh.Vertex =
  VAR a, b : INTEGER;
  BEGIN
    IF i1 < i2 THEN a := i1; b := i2 ELSE a := i2; b := i1 END;
    FOR k := 0 TO tbl.count - 1 DO
      IF tbl.data[k].i1 = a AND tbl.data[k].i2 = b THEN
        RETURN tbl.data[k].mid;
      END;
    END;
    RETURN NIL;
  END FindEdgeMid;

PROCEDURE AddEdgeMid(VAR tbl : EdgeTable;
                     i1, i2 : INTEGER;
                     mid : TriMesh.Vertex) =
  VAR
    a, b : INTEGER;
    newData : REF ARRAY OF EdgeEntry;
  BEGIN
    IF i1 < i2 THEN a := i1; b := i2 ELSE a := i2; b := i1 END;
    IF tbl.count >= NUMBER(tbl.data^) THEN
      newData := NEW(REF ARRAY OF EdgeEntry, NUMBER(tbl.data^) * 2);
      SUBARRAY(newData^, 0, tbl.count) := SUBARRAY(tbl.data^, 0, tbl.count);
      tbl.data := newData;
    END;
    tbl.data[tbl.count] := EdgeEntry{i1 := a, i2 := b, mid := mid};
    INC(tbl.count);
  END AddEdgeMid;

(* ---- Vertex creation ---- *)

CONST
  (* Clamp polar latitudes just past Mercator's MaxLat (1.5707) so that
     Mercator.forward() returns FALSE for these vertices.  MeshProject
     then recovers them for rendering but keeps them out of the bbox,
     preventing extreme y values from stretching the viewport. *)
  MaxLat = 1.5708d0;   (* ≈ 90.0° — just past the Mercator limit *)
  Pi = 3.141592653589793d0;
  PoleBridgeStep = 0.17453d0;  (* ~10° in radians *)

PROCEDURE GrowBuf(VAR buf : REF ARRAY OF TriMesh.Vertex;
                  out : INTEGER) =
  VAR newBuf : REF ARRAY OF TriMesh.Vertex;
  BEGIN
    IF out >= NUMBER(buf^) THEN
      newBuf := NEW(REF ARRAY OF TriMesh.Vertex, NUMBER(buf^) * 2);
      SUBARRAY(newBuf^, 0, out) := SUBARRAY(buf^, 0, out);
      buf := newBuf;
    END;
  END GrowBuf;

PROCEDURE RingToVertices(coords : GeoFeature.CoordArray)
    : REF ARRAY OF TriMesh.Vertex =
  VAR
    n : INTEGER;
    tmp : REF ARRAY OF TriMesh.Vertex;
    buf : REF ARRAY OF TriMesh.Vertex;
    v : TriMesh.Vertex;
    ll, bridgeLL : GeoCoord.LatLon;
    dx, dy, dz, dist2 : LONGREAL;
    rawDLon, absRawDLon, stepLon : LONGREAL;
    nSteps, out : INTEGER;
    result : REF ARRAY OF TriMesh.Vertex;
  BEGIN
    IF coords = NIL THEN RETURN NIL END;
    n := NUMBER(coords^);
    (* GeoJSON rings repeat the first point as the last; strip it *)
    IF n > 1 AND
       coords[0].lat = coords[n - 1].lat AND
       coords[0].lon = coords[n - 1].lon THEN
      DEC(n);
    END;
    IF n < 3 THEN RETURN NIL END;

    (* First pass: create vertices, clamping polar latitudes *)
    tmp := NEW(REF ARRAY OF TriMesh.Vertex, n);
    FOR i := 0 TO n - 1 DO
      v := NEW(TriMesh.Vertex);
      ll := coords[i];
      IF ll.lat > MaxLat THEN ll.lat := MaxLat
      ELSIF ll.lat < -MaxLat THEN ll.lat := -MaxLat
      END;
      v.ll := ll;
      v.xyz := GeoCoord.LatLonToXYZ(ll);
      v.idx := i;
      tmp[i] := v;
    END;

    (* Second pass: dedup consecutive same-XYZ vertices, but expand
       "pole bridges" — pairs at polar latitude with a longitude gap
       > π — into intermediate vertices at the clamped latitude.
       Antarctica has (-90,180) followed by (-90,-180): same XYZ on the
       sphere, but the polygon intends to sweep across the full bottom
       of the map.  We replace the degenerate pair with ~36 vertices
       at the clamped latitude spanning 360° of longitude. *)
    buf := NEW(REF ARRAY OF TriMesh.Vertex, n + 200);
    out := 0;
    buf[0] := tmp[0];
    INC(out);

    FOR i := 1 TO n - 1 DO
      dx := tmp[i].xyz.x - tmp[i - 1].xyz.x;
      dy := tmp[i].xyz.y - tmp[i - 1].xyz.y;
      dz := tmp[i].xyz.z - tmp[i - 1].xyz.z;
      dist2 := dx * dx + dy * dy + dz * dz;

      IF dist2 > 1.0d-12 THEN
        (* Distinct points — keep *)
        GrowBuf(buf, out);
        buf[out] := tmp[i];
        INC(out);
      ELSE
        (* Same XYZ — check for pole bridge *)
        rawDLon := tmp[i].ll.lon - tmp[i - 1].ll.lon;
        absRawDLon := ABS(rawDLon);
        IF absRawDLon > Pi THEN
          (* Pole bridge: insert intermediate vertices at clamped lat *)
          nSteps := CEILING(absRawDLon / PoleBridgeStep);
          IF nSteps < 2 THEN nSteps := 2 END;
          stepLon := rawDLon / FLOAT(nSteps, LONGREAL);
          FOR k := 1 TO nSteps - 1 DO
            bridgeLL.lat := tmp[i - 1].ll.lat;
            bridgeLL.lon := tmp[i - 1].ll.lon
                            + FLOAT(k, LONGREAL) * stepLon;
            v := NEW(TriMesh.Vertex);
            v.ll := bridgeLL;
            v.xyz := GeoCoord.LatLonToXYZ(bridgeLL);
            v.idx := out;
            GrowBuf(buf, out);
            buf[out] := v;
            INC(out);
          END;
          (* Add the endpoint *)
          GrowBuf(buf, out);
          buf[out] := tmp[i];
          INC(out);
        ELSE
          (* True duplicate — skip (dedup) *)
        END;
      END;
    END;

    (* Wrap-around check: last vs first *)
    IF out > 1 THEN
      dx := buf[out - 1].xyz.x - buf[0].xyz.x;
      dy := buf[out - 1].xyz.y - buf[0].xyz.y;
      dz := buf[out - 1].xyz.z - buf[0].xyz.z;
      dist2 := dx * dx + dy * dy + dz * dz;
      IF dist2 < 1.0d-12 THEN DEC(out) END;
    END;

    IF out < 3 THEN RETURN NIL END;

    (* Compact result *)
    result := NEW(REF ARRAY OF TriMesh.Vertex, out);
    FOR i := 0 TO out - 1 DO
      buf[i].idx := i;
      result[i] := buf[i];
    END;
    RETURN result;
  END RingToVertices;

(* ---- Spherical geometry helpers ---- *)

PROCEDURE TripleProduct(READONLY a, b, c : GeoCoord.XYZ) : LONGREAL =
  (* Dot(Cross(a, b), c) — signed volume of parallelepiped.
     Positive when a, b, c form a right-handed system. *)
  BEGIN
    RETURN (a.y * b.z - a.z * b.y) * c.x +
           (a.z * b.x - a.x * b.z) * c.y +
           (a.x * b.y - a.y * b.x) * c.z;
  END TripleProduct;

PROCEDURE ArcLen(READONLY a, b : GeoCoord.XYZ) : LONGREAL =
  VAR d := GreatCircle.Dot(a, b);
  BEGIN
    IF d > 1.0d0 THEN d := 1.0d0 END;
    IF d < -1.0d0 THEN d := -1.0d0 END;
    RETURN Math.acos(d);
  END ArcLen;

(* ---- Ear clipping ---- *)

PROCEDURE RingSign(verts : REF ARRAY OF TriMesh.Vertex) : LONGREAL =
  (* Return +1.0 for CCW ring (outward normal), -1.0 for CW. *)
  VAR
    n := NUMBER(verts^);
    nx, ny, nz : LONGREAL := 0.0d0;
    j : INTEGER;
    c : GeoCoord.XYZ;
    dot : LONGREAL;
  BEGIN
    FOR i := 0 TO n - 1 DO
      j := (i + 1) MOD n;
      c := GreatCircle.Cross(verts[i].xyz, verts[j].xyz);
      nx := nx + c.x;
      ny := ny + c.y;
      nz := nz + c.z;
    END;
    dot := nx * verts[0].xyz.x + ny * verts[0].xyz.y + nz * verts[0].xyz.z;
    IF dot >= 0.0d0 THEN RETURN 1.0d0 ELSE RETURN -1.0d0 END;
  END RingSign;

PROCEDURE PointInSphericalTri(READONLY p, a, b, c : GeoCoord.XYZ;
                              sign : LONGREAL) : BOOLEAN =
  (* True if p is strictly inside spherical triangle abc with given winding. *)
  VAR d1, d2, d3 : LONGREAL;
  BEGIN
    d1 := TripleProduct(a, b, p) * sign;
    d2 := TripleProduct(b, c, p) * sign;
    d3 := TripleProduct(c, a, p) * sign;
    RETURN d1 > 0.0d0 AND d2 > 0.0d0 AND d3 > 0.0d0;
  END PointInSphericalTri;

PROCEDURE EarClip(verts : REF ARRAY OF TriMesh.Vertex;
                  VAR triBuf : TriBuf) =
  VAR
    n := NUMBER(verts^);
    sign : LONGREAL;
    prev, next : REF ARRAY OF INTEGER;
    remaining, maxIter : INTEGER;
    i, pi, ni : INTEGER;
    isEar : BOOLEAN;
    tri : TriMesh.Triangle;
    j : INTEGER;
  BEGIN
    IF n < 3 THEN RETURN END;
    sign := RingSign(verts);

    (* Doubly-linked list via prev/next index arrays *)
    prev := NEW(REF ARRAY OF INTEGER, n);
    next := NEW(REF ARRAY OF INTEGER, n);
    FOR k := 0 TO n - 1 DO
      prev[k] := (k + n - 1) MOD n;
      next[k] := (k + 1) MOD n;
    END;

    remaining := n;
    maxIter := n * n;  (* safety bound *)
    i := 0;
    WHILE remaining > 3 AND maxIter > 0 DO
      DEC(maxIter);
      pi := prev[i];
      ni := next[i];

      (* Check if vertex i is an ear *)
      isEar := FALSE;
      IF TripleProduct(verts[pi].xyz, verts[i].xyz, verts[ni].xyz)
           * sign > 0.0d0 THEN
        (* Convex vertex — check no other vertex lies inside *)
        isEar := TRUE;
        j := next[ni];
        WHILE j # pi DO
          IF PointInSphericalTri(verts[j].xyz,
                                 verts[pi].xyz, verts[i].xyz, verts[ni].xyz,
                                 sign) THEN
            isEar := FALSE;
            EXIT;
          END;
          j := next[j];
        END;
      END;

      IF isEar THEN
        tri.v[0] := verts[pi];
        tri.v[1] := verts[i];
        tri.v[2] := verts[ni];
        AddTri(triBuf, tri);
        (* Remove vertex i *)
        next[pi] := ni;
        prev[ni] := pi;
        DEC(remaining);
        i := ni;
      ELSE
        i := next[i];
      END;
    END;

    (* Last triangle *)
    IF remaining = 3 THEN
      pi := prev[i];
      ni := next[i];
      tri.v[0] := verts[pi];
      tri.v[1] := verts[i];
      tri.v[2] := verts[ni];
      AddTri(triBuf, tri);
    END;
  END EarClip;

(* ---- Subdivision ---- *)

PROCEDURE MakeMidpoint(a, b : TriMesh.Vertex) : TriMesh.Vertex =
  (* Create a new vertex at the spherical midpoint of a and b. *)
  VAR
    mid : TriMesh.Vertex;
    mx, my, mz : LONGREAL;
  BEGIN
    mx := (a.xyz.x + b.xyz.x) * 0.5d0;
    my := (a.xyz.y + b.xyz.y) * 0.5d0;
    mz := (a.xyz.z + b.xyz.z) * 0.5d0;
    mid := NEW(TriMesh.Vertex);
    mid.xyz := GreatCircle.Normalize(GeoCoord.XYZ{x := mx, y := my, z := mz});
    mid.ll := GeoCoord.XYZToLatLon(mid.xyz);
    RETURN mid;
  END MakeMidpoint;

PROCEDURE GetOrCreateMidpoint(a, b : TriMesh.Vertex;
                              VAR verts : VertBuf;
                              VAR edges : EdgeTable) : TriMesh.Vertex =
  VAR mid : TriMesh.Vertex;
  BEGIN
    mid := FindEdgeMid(edges, a.idx, b.idx);
    IF mid # NIL THEN RETURN mid END;
    mid := MakeMidpoint(a, b);
    EVAL AddVert(verts, mid);
    AddEdgeMid(edges, a.idx, b.idx, mid);
    RETURN mid;
  END GetOrCreateMidpoint;

PROCEDURE SubdivideRec(READONLY tri : TriMesh.Triangle;
                       maxArc : LONGREAL;
                       VAR tris : TriBuf;
                       VAR verts : VertBuf;
                       VAR edges : EdgeTable;
                       depth : INTEGER) =
  (* Recursively subdivide a triangle until all edges <= maxArc.
     Split the longest edge, producing two triangles. *)
  VAR
    len : ARRAY [0..2] OF LONGREAL;
    longest : INTEGER;
    maxLen : LONGREAL;
    mid : TriMesh.Vertex;
    t1, t2 : TriMesh.Triangle;
    a, b, c : INTEGER;  (* indices into tri.v for the split *)
  BEGIN
    IF depth > 20 THEN
      (* Safety limit — emit as-is *)
      AddTri(tris, tri);
      RETURN;
    END;

    len[0] := ArcLen(tri.v[0].xyz, tri.v[1].xyz);
    len[1] := ArcLen(tri.v[1].xyz, tri.v[2].xyz);
    len[2] := ArcLen(tri.v[2].xyz, tri.v[0].xyz);

    longest := 0;
    maxLen := len[0];
    IF len[1] > maxLen THEN longest := 1; maxLen := len[1] END;
    IF len[2] > maxLen THEN longest := 2; maxLen := len[2] END;

    IF maxLen <= maxArc THEN
      AddTri(tris, tri);
      RETURN;
    END;

    (* Split edge 'longest'.  a-b is the edge to split, c is opposite. *)
    a := longest;
    b := (longest + 1) MOD 3;
    c := (longest + 2) MOD 3;

    mid := GetOrCreateMidpoint(tri.v[a], tri.v[b], verts, edges);

    (* Two new triangles: (a, mid, c) and (mid, b, c) *)
    t1.v[0] := tri.v[a];  t1.v[1] := mid;        t1.v[2] := tri.v[c];
    t2.v[0] := mid;        t2.v[1] := tri.v[b];  t2.v[2] := tri.v[c];

    SubdivideRec(t1, maxArc, tris, verts, edges, depth + 1);
    SubdivideRec(t2, maxArc, tris, verts, edges, depth + 1);
  END SubdivideRec;

(* ---- Public interface ---- *)

PROCEDURE PolygonToMesh(rings : REF ARRAY OF GeoFeature.CoordArray;
                        maxArcLen : LONGREAL) : TriMesh.Mesh =
  VAR
    mesh : TriMesh.Mesh;
    verts : VertBuf;
    earTris : TriBuf;
    subTris : TriBuf;
    edges : EdgeTable;
    ringVerts : REF ARRAY OF TriMesh.Vertex;
  BEGIN
    IF rings = NIL OR NUMBER(rings^) = 0 THEN
      mesh.tris := NEW(REF ARRAY OF TriMesh.Triangle, 0);
      mesh.verts := NEW(REF ARRAY OF TriMesh.Vertex, 0);
      RETURN mesh;
    END;

    InitVertBuf(verts, 256);
    InitTriBuf(earTris, 256);

    (* Ear-clip each ring independently.  CCW outer rings produce CCW
       triangles; CW hole rings produce CW triangles.  With nonzero
       fill-rule the CW triangles subtract from the outer area. *)
    FOR r := 0 TO LAST(rings^) DO
      ringVerts := RingToVertices(rings[r]);
      IF ringVerts # NIL THEN
        (* Register vertices in the shared buffer *)
        FOR k := 0 TO LAST(ringVerts^) DO
          EVAL AddVert(verts, ringVerts[k]);
        END;
        EarClip(ringVerts, earTris);
      END;
    END;

    (* Subdivide *)
    IF maxArcLen > 0.0d0 AND earTris.count > 0 THEN
      InitTriBuf(subTris, earTris.count * 4);
      InitEdgeTable(edges, earTris.count * 3);
      FOR i := 0 TO earTris.count - 1 DO
        SubdivideRec(earTris.data[i], maxArcLen,
                     subTris, verts, edges, 0);
      END;
    ELSE
      subTris := earTris;
    END;

    (* Package result *)
    mesh.tris := NEW(REF ARRAY OF TriMesh.Triangle, subTris.count);
    SUBARRAY(mesh.tris^, 0, subTris.count) :=
      SUBARRAY(subTris.data^, 0, subTris.count);
    mesh.verts := NEW(REF ARRAY OF TriMesh.Vertex, verts.count);
    SUBARRAY(mesh.verts^, 0, verts.count) :=
      SUBARRAY(verts.data^, 0, verts.count);

    RETURN mesh;
  END PolygonToMesh;

BEGIN
END Triangulate.
