(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

(* Implementation notes:
 *
 * ComputeCurvatures: cotangent-weighted discrete Laplace-Beltrami
 * with mixed Voronoi area normalization, per Meyer et al. (2003).
 * The cotangent Laplacian was introduced for mesh processing by
 * Desbrun et al. (1999).
 *
 * ComputeResiduals: least-squares fit of z = ax^2+bxy+cy^2+dx+ey+f
 * via 6x6 normal equations with Gaussian elimination (partial pivot).
 *
 * DetectAnomalies: statistical outlier detection on the residual
 * field at a user-specified sigma threshold. *)

MODULE Curv;

IMPORT TriMesh, Facet, Vec3, Math;

REVEAL T = BRANDED "Curv" REF RECORD
  nVerts     : CARDINAL;
  curvatures : REF ARRAY OF LONGREAL;
  residuals  : REF ARRAY OF LONGREAL;
  anomalies  : REF ARRAY OF Anomaly;
  nAnomalies : CARDINAL;
  stats      : Stats;
END;

PROCEDURE Analyze(mesh: TriMesh.T; facet: Facet.T;
                  threshold: LONGREAL := 3.0d0): T =
  VAR
    c  := NEW(T);
    nV := TriMesh.NVertices(mesh);
  BEGIN
    c.nVerts := nV;

    (* Step 1: Cotangent Laplacian curvature *)
    c.curvatures := ComputeCurvatures(mesh, facet);

    (* Step 2: Fit quadratic surface z = ax^2 + bxy + cy^2 + dx + ey + f
       and compute residuals *)
    c.residuals := ComputeResiduals(facet);

    (* Step 3: Detect anomalies *)
    DetectAnomalies(c, facet, threshold);

    (* Step 4: Compute statistics *)
    ComputeStats(c);

    RETURN c;
  END Analyze;

PROCEDURE Cot(READONLY a, b: Vec3.T): LONGREAL =
  (* Cotangent of angle between vectors a and b. *)
  VAR
    d := Vec3.Dot(a, b);
    c := Vec3.Length(Vec3.Cross(a, b));
  BEGIN
    IF ABS(c) < 1.0d-30 THEN RETURN 0.0d0; END;
    RETURN d / c;
  END Cot;

PROCEDURE ComputeCurvatures(mesh: TriMesh.T; facet: Facet.T)
    : REF ARRAY OF LONGREAL =
  (* Cotangent-weighted discrete Laplacian, normalized by mixed
     Voronoi area.  For a Monge patch, the z-component of the
     Laplacian-Beltrami gives 2H, so we compute:

       H_i = (1 / 2 A_i) * sum_j (cot a_ij + cot b_ij)(z_j - z_i)

     where a_ij, b_ij are the angles opposite edge (i,j) in
     the two adjacent triangles, and A_i is the mixed Voronoi
     area.  Result has units of 1/length. *)
  VAR
    nV   := TriMesh.NVertices(mesh);
    nF   := TriMesh.NFaces(mesh);
    curv := NEW(REF ARRAY OF LONGREAL, nV);
    area := NEW(REF ARRAY OF LONGREAL, nV);  (* mixed Voronoi area *)
    v0, v1, v2 : CARDINAL;
    p0, p1, p2 : Vec3.T;
    h0, h1, h2 : LONGREAL;
    cotA, cotB, cotC : LONGREAL;
    faceArea : LONGREAL;
  BEGIN
    FOR i := 0 TO nV - 1 DO
      curv[i] := 0.0d0;
      area[i] := 0.0d0;
    END;

    (* Iterate over faces, accumulate cotangent weights *)
    FOR f := 0 TO nF - 1 DO
      TriMesh.GetFace(mesh, f, v0, v1, v2);

      p0 := Facet.GetTransformed(facet, v0);
      p1 := Facet.GetTransformed(facet, v1);
      p2 := Facet.GetTransformed(facet, v2);

      h0 := p0.z;
      h1 := p1.z;
      h2 := p2.z;

      (* Cotangents of angles at each vertex of this triangle *)
      cotA := Cot(Vec3.Sub(p1, p0), Vec3.Sub(p2, p0));  (* angle at v0 *)
      cotB := Cot(Vec3.Sub(p0, p1), Vec3.Sub(p2, p1));  (* angle at v1 *)
      cotC := Cot(Vec3.Sub(p0, p2), Vec3.Sub(p1, p2));  (* angle at v2 *)

      (* Edge (v0, v1): opposite angle is at v2, cot = cotC
         Edge (v1, v2): opposite angle is at v0, cot = cotA
         Edge (v0, v2): opposite angle is at v1, cot = cotB *)

      (* Accumulate cotangent-weighted height differences *)
      curv[v0] := curv[v0] + cotC * (h1 - h0) + cotB * (h2 - h0);
      curv[v1] := curv[v1] + cotC * (h0 - h1) + cotA * (h2 - h1);
      curv[v2] := curv[v2] + cotB * (h0 - h2) + cotA * (h1 - h2);

      (* Mixed Voronoi area per Meyer et al. (2003).
         For a non-obtuse triangle, each vertex gets its Voronoi
         region: A_vor(v0) = (1/8)(|e01|^2 cot(angle at v2)
                                  + |e02|^2 cot(angle at v1)).
         For an obtuse triangle, the obtuse vertex gets half the
         triangle area; the other two split the remaining half. *)
      faceArea := TriMesh.GetFaceInfo(mesh, f).area;
      VAR
        dot0 := Vec3.Dot(Vec3.Sub(p1, p0), Vec3.Sub(p2, p0));
        dot1 := Vec3.Dot(Vec3.Sub(p0, p1), Vec3.Sub(p2, p1));
        dot2 := Vec3.Dot(Vec3.Sub(p0, p2), Vec3.Sub(p1, p2));
      BEGIN
        IF dot0 < 0.0d0 THEN
          (* Obtuse at v0 *)
          area[v0] := area[v0] + faceArea / 2.0d0;
          area[v1] := area[v1] + faceArea / 4.0d0;
          area[v2] := area[v2] + faceArea / 4.0d0;
        ELSIF dot1 < 0.0d0 THEN
          (* Obtuse at v1 *)
          area[v0] := area[v0] + faceArea / 4.0d0;
          area[v1] := area[v1] + faceArea / 2.0d0;
          area[v2] := area[v2] + faceArea / 4.0d0;
        ELSIF dot2 < 0.0d0 THEN
          (* Obtuse at v2 *)
          area[v0] := area[v0] + faceArea / 4.0d0;
          area[v1] := area[v1] + faceArea / 4.0d0;
          area[v2] := area[v2] + faceArea / 2.0d0;
        ELSE
          (* Non-obtuse: Voronoi area *)
          VAR
            e01sq := Vec3.LengthSq(Vec3.Sub(p1, p0));
            e02sq := Vec3.LengthSq(Vec3.Sub(p2, p0));
            e12sq := Vec3.LengthSq(Vec3.Sub(p2, p1));
          BEGIN
            area[v0] := area[v0]
              + (e01sq * cotC + e02sq * cotB) / 8.0d0;
            area[v1] := area[v1]
              + (e01sq * cotC + e12sq * cotA) / 8.0d0;
            area[v2] := area[v2]
              + (e02sq * cotB + e12sq * cotA) / 8.0d0;
          END;
        END;
      END;
    END;

    (* Normalize: H = (1 / 2A) * sum_cotangent_weighted_diffs *)
    FOR i := 0 TO nV - 1 DO
      IF area[i] > 0.0d0 THEN
        curv[i] := curv[i] / (2.0d0 * area[i]);
      END;
    END;

    RETURN curv;
  END ComputeCurvatures;

PROCEDURE ComputeResiduals(facet: Facet.T): REF ARRAY OF LONGREAL =
  (* Fit z = ax^2 + bxy + cy^2 + dx + ey + f by least squares,
     then residual[i] = z[i] - fitted[i].
     We solve the 6x6 normal equations directly. *)
  VAR
    nV   := Facet.NVertices(facet);
    res  := NEW(REF ARRAY OF LONGREAL, nV);
    x, y, z : LONGREAL;
    (* Normal equation accumulators: A^T A (6x6) and A^T b (6x1) *)
    ATA : ARRAY [0..5] OF ARRAY [0..5] OF LONGREAL;
    ATb : ARRAY [0..5] OF LONGREAL;
    row : ARRAY [0..5] OF LONGREAL;
    coeff : ARRAY [0..5] OF LONGREAL;
  BEGIN
    (* Initialize *)
    FOR i := 0 TO 5 DO
      ATb[i] := 0.0d0;
      FOR j := 0 TO 5 DO ATA[i][j] := 0.0d0; END;
    END;

    (* Accumulate *)
    FOR i := 0 TO nV - 1 DO
      Facet.GetXY(facet, i, x, y);
      z := Facet.GetHeight(facet, i);
      row[0] := x * x;
      row[1] := x * y;
      row[2] := y * y;
      row[3] := x;
      row[4] := y;
      row[5] := 1.0d0;
      FOR r := 0 TO 5 DO
        ATb[r] := ATb[r] + row[r] * z;
        FOR c := 0 TO 5 DO
          ATA[r][c] := ATA[r][c] + row[r] * row[c];
        END;
      END;
    END;

    (* Solve ATA * coeff = ATb by Gaussian elimination with pivoting *)
    SolveLinear6(ATA, ATb, coeff);

    (* Compute residuals *)
    FOR i := 0 TO nV - 1 DO
      Facet.GetXY(facet, i, x, y);
      z := Facet.GetHeight(facet, i);
      VAR fitted := coeff[0] * x * x + coeff[1] * x * y
                  + coeff[2] * y * y + coeff[3] * x
                  + coeff[4] * y + coeff[5];
      BEGIN
        res[i] := z - fitted;
      END;
    END;

    RETURN res;
  END ComputeResiduals;

PROCEDURE SolveLinear6(VAR A: ARRAY [0..5] OF ARRAY [0..5] OF LONGREAL;
                       VAR b: ARRAY [0..5] OF LONGREAL;
                       VAR x: ARRAY [0..5] OF LONGREAL) =
  (* Gaussian elimination with partial pivoting for a 6x6 system. *)
  VAR
    tmp : LONGREAL;
    maxVal, absVal : LONGREAL;
    maxRow : CARDINAL;
  BEGIN
    (* Forward elimination *)
    FOR col := 0 TO 5 DO
      (* Find pivot *)
      maxVal := ABS(A[col][col]);
      maxRow := col;
      FOR row := col + 1 TO 5 DO
        absVal := ABS(A[row][col]);
        IF absVal > maxVal THEN
          maxVal := absVal;
          maxRow := row;
        END;
      END;

      (* Swap rows *)
      IF maxRow # col THEN
        FOR k := 0 TO 5 DO
          tmp := A[col][k]; A[col][k] := A[maxRow][k]; A[maxRow][k] := tmp;
        END;
        tmp := b[col]; b[col] := b[maxRow]; b[maxRow] := tmp;
      END;

      (* Eliminate below *)
      IF ABS(A[col][col]) > 1.0d-30 THEN
        FOR row := col + 1 TO 5 DO
          VAR factor := A[row][col] / A[col][col]; BEGIN
            FOR k := col TO 5 DO
              A[row][k] := A[row][k] - factor * A[col][k];
            END;
            b[row] := b[row] - factor * b[col];
          END;
        END;
      END;
    END;

    (* Back substitution *)
    FOR i := 5 TO 0 BY -1 DO
      x[i] := b[i];
      FOR j := i + 1 TO 5 DO
        x[i] := x[i] - A[i][j] * x[j];
      END;
      IF ABS(A[i][i]) > 1.0d-30 THEN
        x[i] := x[i] / A[i][i];
      ELSE
        x[i] := 0.0d0;
      END;
    END;
  END SolveLinear6;

PROCEDURE DetectAnomalies(c: T; facet: Facet.T;
                          threshold: LONGREAL) =
  VAR
    nV := c.nVerts;
    mean, variance, std : LONGREAL;
    count : CARDINAL := 0;
    x, y : LONGREAL;
    buf : REF ARRAY OF Anomaly;
  BEGIN
    (* Compute mean and std of residuals *)
    mean := 0.0d0;
    FOR i := 0 TO nV - 1 DO
      mean := mean + c.residuals[i];
    END;
    mean := mean / FLOAT(nV, LONGREAL);

    variance := 0.0d0;
    FOR i := 0 TO nV - 1 DO
      VAR d := c.residuals[i] - mean; BEGIN
        variance := variance + d * d;
      END;
    END;
    variance := variance / FLOAT(nV, LONGREAL);
    std := Math.sqrt(variance);

    (* Count anomalies *)
    IF std > 0.0d0 THEN
      FOR i := 0 TO nV - 1 DO
        IF ABS(c.residuals[i] - mean) > threshold * std THEN
          INC(count);
        END;
      END;
    END;

    (* Collect anomalies *)
    buf := NEW(REF ARRAY OF Anomaly, count);
    VAR k : CARDINAL := 0; BEGIN
      IF std > 0.0d0 THEN
        FOR i := 0 TO nV - 1 DO
          IF ABS(c.residuals[i] - mean) > threshold * std THEN
            Facet.GetXY(facet, i, x, y);
            buf[k] := Anomaly{vertex := i,
                               x := x, y := y,
                               height := c.residuals[i],
                               curvature := c.curvatures[i]};
            INC(k);
          END;
        END;
      END;
    END;

    c.anomalies := buf;
    c.nAnomalies := count;
  END DetectAnomalies;

PROCEDURE ComputeStats(c: T) =
  VAR
    nV := c.nVerts;
    nF := FLOAT(nV, LONGREAL);
    sumC, sumCSq, minC, maxC : LONGREAL;
    sumR, sumRSq : LONGREAL;
  BEGIN
    sumC := 0.0d0; sumCSq := 0.0d0;
    minC := c.curvatures[0]; maxC := c.curvatures[0];
    sumR := 0.0d0; sumRSq := 0.0d0;

    FOR i := 0 TO nV - 1 DO
      VAR cv := c.curvatures[i]; rv := c.residuals[i]; BEGIN
        sumC := sumC + cv;
        sumCSq := sumCSq + cv * cv;
        IF cv < minC THEN minC := cv; END;
        IF cv > maxC THEN maxC := cv; END;
        sumR := sumR + rv;
        sumRSq := sumRSq + rv * rv;
      END;
    END;

    c.stats.meanCurv := sumC / nF;
    c.stats.minCurv := minC;
    c.stats.maxCurv := maxC;
    c.stats.stdCurv := Math.sqrt(sumCSq / nF - (sumC / nF) * (sumC / nF));
    c.stats.meanHeight := sumR / nF;
    c.stats.stdHeight := Math.sqrt(sumRSq / nF - (sumR / nF) * (sumR / nF));
    c.stats.nAnomalies := c.nAnomalies;
  END ComputeStats;

(* ---- Accessors ---- *)

PROCEDURE GetStats(c: T): Stats =
  BEGIN RETURN c.stats; END GetStats;

PROCEDURE GetCurvature(c: T; i: CARDINAL): LONGREAL =
  BEGIN RETURN c.curvatures[i]; END GetCurvature;

PROCEDURE GetCurvatures(c: T): REF ARRAY OF LONGREAL =
  BEGIN RETURN c.curvatures; END GetCurvatures;

PROCEDURE GetResidual(c: T; i: CARDINAL): LONGREAL =
  BEGIN RETURN c.residuals[i]; END GetResidual;

PROCEDURE GetResiduals(c: T): REF ARRAY OF LONGREAL =
  BEGIN RETURN c.residuals; END GetResiduals;

PROCEDURE NAnomalies(c: T): CARDINAL =
  BEGIN RETURN c.nAnomalies; END NAnomalies;

PROCEDURE GetAnomaly(c: T; k: CARDINAL): Anomaly =
  BEGIN RETURN c.anomalies[k]; END GetAnomaly;

BEGIN
END Curv.
