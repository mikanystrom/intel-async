(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE Segment;

IMPORT TriMesh, Vec3, Math, SeedPQ;

TYPE SeedElt = SeedPQ.Elt OBJECT vertex: CARDINAL; END;

REVEAL T = BRANDED "Segment" REF RECORD
  nVerts   : CARDINAL;
  nRegions : CARDINAL;
  labels   : REF ARRAY OF INTEGER;
  regions  : REF ARRAY OF Region;
  vertSets : REF ARRAY OF REF ARRAY OF CARDINAL;
END;

TYPE
  RegionRec = RECORD
    nVertices  : CARDINAL;
    meanNormal : Vec3.T;      (* unnormalized accumulator *)
    area       : LONGREAL;
  END;

PROCEDURE Run(mesh: TriMesh.T;
              angleThreshold      : LONGREAL := 15.0d0;
              minVertices          : CARDINAL := 100;
              maxTiltFromVertical  : LONGREAL := 90.0d0): T =
  VAR
    s         := NEW(T);
    nV        := TriMesh.NVertices(mesh);
    cosThresh := Math.cos(angleThreshold * Math.Pi / 180.0d0);
    cosTilt   := Math.cos(maxTiltFromVertical * Math.Pi / 180.0d0);
    claimed   : REF ARRAY OF BOOLEAN;
    rawLabels : REF ARRAY OF INTEGER;
    rawBuf    : REF ARRAY OF RegionRec;
    nRaw      : CARDINAL := 0;
    pq        : SeedPQ.Default;
    pqElts    : REF ARRAY OF SeedElt;
  BEGIN
    s.nVerts := nV;
    claimed := NEW(REF ARRAY OF BOOLEAN, nV);
    rawLabels := NEW(REF ARRAY OF INTEGER, nV);
    rawBuf := NEW(REF ARRAY OF RegionRec, 4096);
    FOR i := 0 TO nV - 1 DO
      claimed[i] := FALSE;
      rawLabels[i] := -1;
    END;

    (* Build priority queue: priority = -(unclaimed neighbor count).
       Lower = better, so vertices with many neighbors come out first. *)
    pqElts := NEW(REF ARRAY OF SeedElt, nV);
    pq := NEW(SeedPQ.Default).init(nV);
    FOR v := 0 TO nV - 1 DO
      pqElts[v] := NEW(SeedElt);
      pqElts[v].priority := -TriMesh.NeighborCount(mesh, v);
      pqElts[v].vertex := v;
      pq.insert(pqElts[v]);
    END;

    (* Work queue for BFS *)
    VAR queue := NEW(REF ARRAY OF CARDINAL, nV); BEGIN
      LOOP
        (* Find next unclaimed seed from the priority queue *)
        VAR seed := ExtractSeed(pq, claimed); BEGIN
          IF seed < 0 THEN EXIT; END;

          VAR
            qHead : CARDINAL := 0;
            qTail : CARDINAL := 0;
            rec   : RegionRec;
          BEGIN
            rec.nVertices := 0;
            rec.meanNormal := Vec3.Zero;

            (* Seed the region *)
            queue[qTail] := seed; INC(qTail);
            claimed[seed] := TRUE;
            rawLabels[seed] := nRaw;
            rec.meanNormal := TriMesh.GetVertexNormal(mesh, seed);
            rec.nVertices := 1;

            (* BFS growth *)
            WHILE qHead < qTail DO
              VAR v := queue[qHead]; BEGIN
                INC(qHead);
                FOR k := 0 TO TriMesh.NeighborCount(mesh, v) - 1 DO
                  VAR u := TriMesh.GetNeighbor(mesh, v, k); BEGIN
                    IF NOT claimed[u] THEN
                      VAR
                        un := TriMesh.GetVertexNormal(mesh, u);
                        mn := Vec3.Normalize(rec.meanNormal);
                      BEGIN
                        IF Vec3.Dot(un, mn) >= cosThresh THEN
                          claimed[u] := TRUE;
                          rawLabels[u] := nRaw;
                          queue[qTail] := u; INC(qTail);
                          rec.meanNormal := Vec3.Add(rec.meanNormal, un);
                          INC(rec.nVertices);
                        END;
                      END;
                    END;
                  END;
                END;
              END;
            END;

            (* Compute area *)
            rec.area := ComputeRegionArea(mesh, rawLabels, nRaw);
            rawBuf[nRaw] := rec;
            INC(nRaw);
            IF nRaw >= NUMBER(rawBuf^) THEN EXIT; END;
          END;
        END;
      END;
    END;

    (* Filter by size and tilt, sort, remap *)
    BuildResult(s, mesh, rawLabels, rawBuf, nRaw, minVertices, cosTilt);

    RETURN s;
  END Run;

PROCEDURE ExtractSeed(pq: SeedPQ.Default;
                      claimed: REF ARRAY OF BOOLEAN): INTEGER =
  (* Pop elements from the PQ until we find one that isn't claimed,
     or the PQ is empty. *)
  BEGIN
    WHILE pq.size() > 0 DO
      TRY
        VAR elt: SeedElt := pq.deleteMin(); BEGIN
          IF NOT claimed[elt.vertex] THEN
            RETURN elt.vertex;
          END;
        END;
      EXCEPT
        SeedPQ.Empty => RETURN -1;
      END;
    END;
    RETURN -1;
  END ExtractSeed;

PROCEDURE ComputeRegionArea(mesh: TriMesh.T;
                            labels: REF ARRAY OF INTEGER;
                            regionId: CARDINAL): LONGREAL =
  VAR
    nF := TriMesh.NFaces(mesh);
    total := 0.0d0;
    v0, v1, v2 : CARDINAL;
  BEGIN
    FOR i := 0 TO nF - 1 DO
      TriMesh.GetFace(mesh, i, v0, v1, v2);
      IF labels[v0] = regionId AND
         labels[v1] = regionId AND
         labels[v2] = regionId THEN
        total := total + TriMesh.GetFaceInfo(mesh, i).area;
      END;
    END;
    RETURN total;
  END ComputeRegionArea;

PROCEDURE TiltAngle(READONLY n: Vec3.T): LONGREAL =
  (* Angle in degrees between normal n and the z-axis. *)
  VAR nz := Vec3.Normalize(n);
  BEGIN
    RETURN Math.acos(MIN(1.0d0, MAX(-1.0d0, ABS(nz.z))))
             * 180.0d0 / Math.Pi;
  END TiltAngle;

PROCEDURE BuildResult(s: T;
                      <*UNUSED*> mesh: TriMesh.T;
                      rawLabels: REF ARRAY OF INTEGER;
                      rawBuf: REF ARRAY OF RegionRec;
                      nRaw: CARDINAL;
                      minVertices: CARDINAL;
                      cosTilt: LONGREAL) =
  VAR
    kept : CARDINAL := 0;
    sortIdx : REF ARRAY OF CARDINAL;
    remap   : REF ARRAY OF INTEGER;
  BEGIN
    (* Count kept regions: large enough and within tilt limit *)
    FOR i := 0 TO nRaw - 1 DO
      VAR nrm := Vec3.Normalize(rawBuf[i].meanNormal); BEGIN
        IF rawBuf[i].nVertices >= minVertices AND
           ABS(nrm.z) >= cosTilt THEN
          INC(kept);
        END;
      END;
    END;

    s.nRegions := kept;
    s.regions := NEW(REF ARRAY OF Region, kept);
    s.vertSets := NEW(REF ARRAY OF REF ARRAY OF CARDINAL, kept);
    sortIdx := NEW(REF ARRAY OF CARDINAL, kept);
    remap := NEW(REF ARRAY OF INTEGER, nRaw);

    (* Collect kept region indices *)
    VAR k : CARDINAL := 0; BEGIN
      FOR i := 0 TO nRaw - 1 DO
        VAR nrm := Vec3.Normalize(rawBuf[i].meanNormal); BEGIN
          IF rawBuf[i].nVertices >= minVertices AND
             ABS(nrm.z) >= cosTilt THEN
            sortIdx[k] := i;
            INC(k);
          END;
        END;
      END;
    END;

    (* Sort by decreasing vertex count *)
    FOR i := 1 TO kept - 1 DO
      VAR
        key := sortIdx[i];
        j := i;
      BEGIN
        WHILE j > 0 AND
              rawBuf[sortIdx[j-1]].nVertices <
                rawBuf[key].nVertices DO
          sortIdx[j] := sortIdx[j-1];
          DEC(j);
        END;
        sortIdx[j] := key;
      END;
    END;

    (* Build remap and region records *)
    FOR i := 0 TO nRaw - 1 DO remap[i] := -1; END;
    FOR k := 0 TO kept - 1 DO
      VAR
        oldId := sortIdx[k];
        nrm := Vec3.Normalize(rawBuf[oldId].meanNormal);
      BEGIN
        remap[oldId] := k;
        s.regions[k] := Region{
          id := k,
          nVertices := rawBuf[oldId].nVertices,
          meanNormal := nrm,
          tiltAngle := TiltAngle(rawBuf[oldId].meanNormal),
          area := rawBuf[oldId].area};
      END;
    END;

    (* Remap vertex labels *)
    s.labels := NEW(REF ARRAY OF INTEGER, s.nVerts);
    FOR v := 0 TO s.nVerts - 1 DO
      VAR old := rawLabels[v]; BEGIN
        IF old >= 0 AND old < nRaw AND remap[old] >= 0 THEN
          s.labels[v] := remap[old];
        ELSE
          s.labels[v] := -1;
        END;
      END;
    END;

    (* Build per-region vertex lists *)
    FOR k := 0 TO kept - 1 DO
      VAR
        n := s.regions[k].nVertices;
        verts := NEW(REF ARRAY OF CARDINAL, n);
        pos : CARDINAL := 0;
      BEGIN
        FOR v := 0 TO s.nVerts - 1 DO
          IF s.labels[v] = k THEN
            verts[pos] := v;
            INC(pos);
          END;
        END;
        s.vertSets[k] := verts;
      END;
    END;
  END BuildResult;

(* ---- Accessors ---- *)

PROCEDURE NRegions(s: T): CARDINAL =
  BEGIN RETURN s.nRegions; END NRegions;

PROCEDURE GetRegion(s: T; k: CARDINAL): Region =
  BEGIN RETURN s.regions[k]; END GetRegion;

PROCEDURE GetLabel(s: T; v: CARDINAL): INTEGER =
  BEGIN RETURN s.labels[v]; END GetLabel;

PROCEDURE GetRegionVertices(s: T; k: CARDINAL): REF ARRAY OF CARDINAL =
  BEGIN RETURN s.vertSets[k]; END GetRegionVertices;

PROCEDURE GetRegionFaces(s: T; k: CARDINAL; mesh: TriMesh.T)
    : REF ARRAY OF CARDINAL =
  VAR
    nF := TriMesh.NFaces(mesh);
    count : CARDINAL := 0;
    v0, v1, v2 : CARDINAL;
  BEGIN
    FOR i := 0 TO nF - 1 DO
      TriMesh.GetFace(mesh, i, v0, v1, v2);
      IF s.labels[v0] = k AND s.labels[v1] = k AND s.labels[v2] = k THEN
        INC(count);
      END;
    END;
    VAR
      result := NEW(REF ARRAY OF CARDINAL, count);
      pos : CARDINAL := 0;
    BEGIN
      FOR i := 0 TO nF - 1 DO
        TriMesh.GetFace(mesh, i, v0, v1, v2);
        IF s.labels[v0] = k AND s.labels[v1] = k AND s.labels[v2] = k THEN
          result[pos] := i;
          INC(pos);
        END;
      END;
      RETURN result;
    END;
  END GetRegionFaces;

BEGIN
END Segment.
