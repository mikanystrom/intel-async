(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

(* Implementation notes:
 *
 * FromPly eagerly computes all derived quantities:
 *   - Per-face normals via cross product of edge vectors
 *   - Per-face areas as half the cross-product magnitude
 *   - Per-vertex normals as area-weighted averages of incident
 *     face normals (the standard approach; see e.g. Max, N. (1999),
 *     "Weights for Computing Vertex Normals from Facet Normals",
 *     J. Graphics Tools, 4(2), pp. 1-6)
 *   - 1-ring vertex adjacency via compressed sorted neighbor lists
 *   - Area-weighted centroid and mean normal
 *
 * BuildAdjacency: for each face, records 6 directed edges (2 per
 * vertex pair).  Edges are then sorted per-vertex and deduplicated
 * into a compressed adjacency structure (adjStart, adjList).
 * Sorting uses insertion sort since neighbor lists are small. *)

MODULE TriMesh;

IMPORT Ply, Vec3;

REVEAL T = BRANDED "TriMesh" REF RECORD
  nVerts     : CARDINAL;
  nFaces     : CARDINAL;
  positions  : REF ARRAY OF Vec3.T;
  faceIdx    : REF ARRAY OF ARRAY [0..2] OF CARDINAL;
  faceInfo   : REF ARRAY OF FaceInfo;
  vertNormal : REF ARRAY OF Vec3.T;
  (* Adjacency: compressed neighbor list.
     Vertex v's neighbors are adjList[adjStart[v] .. adjStart[v+1]-1]. *)
  adjStart   : REF ARRAY OF CARDINAL;
  adjList    : REF ARRAY OF CARDINAL;
  centroid   : Vec3.T;
  meanNormal : Vec3.T;
  totalArea  : LONGREAL;
END;

PROCEDURE FromPly(READONLY ply: Ply.T): T =
  VAR
    m    := NEW(T);
    nV   := ply.header.nVertices;
    nF   := ply.header.nFaces;
    x, y, z : REAL;
  BEGIN
    m.nVerts := nV;
    m.nFaces := nF;

    (* Extract vertex positions *)
    m.positions := NEW(REF ARRAY OF Vec3.T, nV);
    FOR i := 0 TO nV - 1 DO
      Ply.GetVertex(ply, i, x, y, z);
      m.positions[i] := Vec3.FromReal(x, y, z);
    END;

    (* Extract face indices *)
    m.faceIdx := NEW(REF ARRAY OF ARRAY [0..2] OF CARDINAL, nF);
    FOR i := 0 TO nF - 1 DO
      m.faceIdx[i][0] := ply.faces[3 * i];
      m.faceIdx[i][1] := ply.faces[3 * i + 1];
      m.faceIdx[i][2] := ply.faces[3 * i + 2];
    END;

    ComputeFaceInfo(m);
    ComputeVertexNormals(m);
    BuildAdjacency(m);
    ComputeGlobals(m);

    RETURN m;
  END FromPly;

PROCEDURE ComputeFaceInfo(m: T) =
  VAR
    p0, p1, p2 : Vec3.T;
    e1, e2, n  : Vec3.T;
    area       : LONGREAL;
  BEGIN
    m.faceInfo := NEW(REF ARRAY OF FaceInfo, m.nFaces);
    FOR i := 0 TO m.nFaces - 1 DO
      p0 := m.positions[m.faceIdx[i][0]];
      p1 := m.positions[m.faceIdx[i][1]];
      p2 := m.positions[m.faceIdx[i][2]];
      e1 := Vec3.Sub(p1, p0);
      e2 := Vec3.Sub(p2, p0);
      n := Vec3.Cross(e1, e2);
      area := Vec3.Length(n) * 0.5d0;
      m.faceInfo[i].area := area;
      IF area > 0.0d0 THEN
        m.faceInfo[i].normal := Vec3.Normalize(n);
      ELSE
        m.faceInfo[i].normal := Vec3.Zero;
      END;
    END;
  END ComputeFaceInfo;

PROCEDURE ComputeVertexNormals(m: T) =
  VAR
    acc : Vec3.T;
    fi  : FaceInfo;
  BEGIN
    m.vertNormal := NEW(REF ARRAY OF Vec3.T, m.nVerts);
    FOR i := 0 TO m.nVerts - 1 DO
      m.vertNormal[i] := Vec3.Zero;
    END;
    FOR i := 0 TO m.nFaces - 1 DO
      fi := m.faceInfo[i];
      acc := Vec3.Scale(fi.area, fi.normal);
      FOR j := 0 TO 2 DO
        VAR v := m.faceIdx[i][j]; BEGIN
          m.vertNormal[v] := Vec3.Add(m.vertNormal[v], acc);
        END;
      END;
    END;
    FOR i := 0 TO m.nVerts - 1 DO
      m.vertNormal[i] := Vec3.Normalize(m.vertNormal[i]);
    END;
  END ComputeVertexNormals;

PROCEDURE BuildAdjacency(m: T) =
  (* Build compressed 1-ring neighbor lists.  We use face connectivity:
     for each face, each pair of vertices is adjacent. *)
  VAR
    degree : REF ARRAY OF CARDINAL;
    pos    : REF ARRAY OF CARDINAL;
    total  : CARDINAL := 0;
  BEGIN
    degree := NEW(REF ARRAY OF CARDINAL, m.nVerts);
    FOR i := 0 TO m.nVerts - 1 DO degree[i] := 0; END;

    (* First pass: count edges per vertex (with duplicates). *)
    FOR i := 0 TO m.nFaces - 1 DO
      FOR j := 0 TO 2 DO INC(degree[m.faceIdx[i][j]], 2); END;
    END;

    (* Allocate starts *)
    m.adjStart := NEW(REF ARRAY OF CARDINAL, m.nVerts + 1);
    m.adjStart[0] := 0;
    FOR i := 0 TO m.nVerts - 1 DO
      m.adjStart[i + 1] := m.adjStart[i] + degree[i];
      total := m.adjStart[i + 1];
    END;

    (* Second pass: fill adjacency with duplicates *)
    VAR raw := NEW(REF ARRAY OF CARDINAL, total); BEGIN
      pos := NEW(REF ARRAY OF CARDINAL, m.nVerts);
      FOR i := 0 TO m.nVerts - 1 DO pos[i] := m.adjStart[i]; END;

      FOR i := 0 TO m.nFaces - 1 DO
        VAR
          v0 := m.faceIdx[i][0];
          v1 := m.faceIdx[i][1];
          v2 := m.faceIdx[i][2];
        BEGIN
          AddEdge(raw, pos, v0, v1);
          AddEdge(raw, pos, v0, v2);
          AddEdge(raw, pos, v1, v0);
          AddEdge(raw, pos, v1, v2);
          AddEdge(raw, pos, v2, v0);
          AddEdge(raw, pos, v2, v1);
        END;
      END;

      (* Deduplicate per vertex *)
      DeduplicateAdjacency(m, raw);
    END;
  END BuildAdjacency;

PROCEDURE AddEdge(raw: REF ARRAY OF CARDINAL;
                  pos: REF ARRAY OF CARDINAL;
                  from, to: CARDINAL) =
  BEGIN
    raw[pos[from]] := to;
    INC(pos[from]);
  END AddEdge;

PROCEDURE DeduplicateAdjacency(m: T; raw: REF ARRAY OF CARDINAL) =
  (* Sort each vertex's neighbor list and remove duplicates.
     Rebuild adjStart and adjList. *)
  VAR
    total : CARDINAL := 0;
    start, end_ : CARDINAL;
  BEGIN
    (* Sort each vertex's neighbors and count unique *)
    FOR v := 0 TO m.nVerts - 1 DO
      start := m.adjStart[v];
      end_ := m.adjStart[v + 1];
      IF end_ > start THEN
        SortCardinals(raw, start, end_ - 1);
      END;
      (* Count unique *)
      IF end_ > start THEN
        INC(total);  (* first element always counts *)
        FOR k := start + 1 TO end_ - 1 DO
          IF raw[k] # raw[k - 1] THEN INC(total); END;
        END;
      END;
    END;

    (* Build compact lists *)
    m.adjList := NEW(REF ARRAY OF CARDINAL, total);
    VAR
      newStart := NEW(REF ARRAY OF CARDINAL, m.nVerts + 1);
      pos : CARDINAL := 0;
    BEGIN
      FOR v := 0 TO m.nVerts - 1 DO
        newStart[v] := pos;
        start := m.adjStart[v];
        end_ := m.adjStart[v + 1];
        IF end_ > start THEN
          m.adjList[pos] := raw[start];
          INC(pos);
          FOR k := start + 1 TO end_ - 1 DO
            IF raw[k] # raw[k - 1] THEN
              m.adjList[pos] := raw[k];
              INC(pos);
            END;
          END;
        END;
      END;
      newStart[m.nVerts] := pos;
      m.adjStart := newStart;
    END;
  END DeduplicateAdjacency;

PROCEDURE SortCardinals(a: REF ARRAY OF CARDINAL;
                        lo, hi: CARDINAL) =
  (* Simple insertion sort -- neighbor lists are small. *)
  BEGIN
    FOR i := lo + 1 TO hi DO
      VAR
        key := a[i];
        j   := i;
      BEGIN
        WHILE j > lo AND a[j - 1] > key DO
          a[j] := a[j - 1];
          DEC(j);
        END;
        a[j] := key;
      END;
    END;
  END SortCardinals;

PROCEDURE ComputeGlobals(m: T) =
  VAR
    fi : FaceInfo;
    fc : Vec3.T;
  BEGIN
    m.centroid := Vec3.Zero;
    m.meanNormal := Vec3.Zero;
    m.totalArea := 0.0d0;

    FOR i := 0 TO m.nFaces - 1 DO
      fi := m.faceInfo[i];
      m.totalArea := m.totalArea + fi.area;
      m.meanNormal := Vec3.Add(m.meanNormal, Vec3.Scale(fi.area, fi.normal));

      (* Face centroid = average of three vertices *)
      fc := Vec3.Scale(1.0d0 / 3.0d0,
              Vec3.Add(m.positions[m.faceIdx[i][0]],
                Vec3.Add(m.positions[m.faceIdx[i][1]],
                         m.positions[m.faceIdx[i][2]])));
      m.centroid := Vec3.Add(m.centroid, Vec3.Scale(fi.area, fc));
    END;

    IF m.totalArea > 0.0d0 THEN
      m.centroid := Vec3.Scale(1.0d0 / m.totalArea, m.centroid);
    END;
    m.meanNormal := Vec3.Normalize(m.meanNormal);
  END ComputeGlobals;

(* ---- Accessors ---- *)

PROCEDURE NVertices(m: T): CARDINAL =
  BEGIN RETURN m.nVerts; END NVertices;

PROCEDURE NFaces(m: T): CARDINAL =
  BEGIN RETURN m.nFaces; END NFaces;

PROCEDURE GetPosition(m: T; i: CARDINAL): Vec3.T =
  BEGIN RETURN m.positions[i]; END GetPosition;

PROCEDURE GetFace(m: T; i: CARDINAL; VAR v0, v1, v2: CARDINAL) =
  BEGIN
    v0 := m.faceIdx[i][0];
    v1 := m.faceIdx[i][1];
    v2 := m.faceIdx[i][2];
  END GetFace;

PROCEDURE GetFaceInfo(m: T; i: CARDINAL): FaceInfo =
  BEGIN RETURN m.faceInfo[i]; END GetFaceInfo;

PROCEDURE GetVertexNormal(m: T; i: CARDINAL): Vec3.T =
  BEGIN RETURN m.vertNormal[i]; END GetVertexNormal;

PROCEDURE NeighborCount(m: T; v: CARDINAL): CARDINAL =
  BEGIN RETURN m.adjStart[v + 1] - m.adjStart[v]; END NeighborCount;

PROCEDURE GetNeighbor(m: T; v: CARDINAL; k: CARDINAL): CARDINAL =
  BEGIN RETURN m.adjList[m.adjStart[v] + k]; END GetNeighbor;

PROCEDURE Centroid(m: T): Vec3.T =
  BEGIN RETURN m.centroid; END Centroid;

PROCEDURE MeanNormal(m: T): Vec3.T =
  BEGIN RETURN m.meanNormal; END MeanNormal;

PROCEDURE TotalArea(m: T): LONGREAL =
  BEGIN RETURN m.totalArea; END TotalArea;

BEGIN
END TriMesh.
