(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE Curv;

IMPORT TriMesh, Facet;

(* Per-vertex curvature estimation and anomaly detection.

   Mean curvature H is estimated using the cotangent-weighted discrete
   Laplace-Beltrami operator, normalized by the mixed Voronoi area:

     H_i = (1 / 2 A_i) * sum_j (cot alpha_ij + cot beta_ij)(z_j - z_i)

   where alpha_ij, beta_ij are the angles opposite edge (i,j) in the
   two adjacent triangles, and A_i is the mixed Voronoi area.  The
   result has units of 1/length (inverse radius of curvature).

   References:
     Meyer, M., Desbrun, M., Schroeder, P., Barr, A.H. (2003),
     "Discrete Differential-Geometry Operators for Triangulated
     2-Manifolds", Visualization and Mathematics III, Springer,
     pp. 35-57.  (Cotangent Laplacian and mixed Voronoi area.)

     Desbrun, M., Meyer, M., Schroeder, P., Barr, A.H. (1999),
     "Implicit Fairing of Irregular Meshes using Diffusion and
     Curvature Flow", SIGGRAPH.  (Cotangent weights for mesh
     Laplacian.)

   Anomalies are vertices whose height residual (after subtracting
   a best-fit quadratic surface z = ax^2 + bxy + cy^2 + dx + ey + f)
   exceeds a threshold in standard deviations. *)

TYPE
  T <: REFANY;

  Stats = RECORD
    meanCurv   : LONGREAL;  (* mean of per-vertex curvatures *)
    minCurv    : LONGREAL;  (* minimum curvature *)
    maxCurv    : LONGREAL;  (* maximum curvature *)
    stdCurv    : LONGREAL;  (* standard deviation of curvatures *)
    meanHeight : LONGREAL;  (* mean height residual after quadratic fit *)
    stdHeight  : LONGREAL;  (* std dev of height residual *)
    nAnomalies : CARDINAL;  (* number of anomalous vertices *)
  END;

  Anomaly = RECORD
    vertex   : CARDINAL;     (* vertex index in the mesh *)
    x, y     : LONGREAL;     (* position in rotated frame *)
    height   : LONGREAL;     (* residual height (actual - quadratic fit) *)
    curvature: LONGREAL;     (* mean curvature at this vertex *)
  END;

PROCEDURE Analyze(mesh: TriMesh.T; facet: Facet.T;
                  threshold: LONGREAL := 3.0d0): T;
  (* Requires: mesh and facet refer to the same geometry;
               facet was produced by Facet.Analyze(mesh).
     Ensures:  computes per-vertex curvature (cotangent Laplacian,
               Meyer mixed Voronoi area); fits a quadratic surface
               to the height field; computes residuals; detects
               anomalies where |residual - mean| > threshold * sigma.
               Curvature values have units of 1/length in the
               mesh's native coordinate system. *)

PROCEDURE GetStats(c: T): Stats;
  (* Ensures: returns aggregate statistics over all vertices. *)

PROCEDURE GetCurvature(c: T; i: CARDINAL): LONGREAL;
  (* Requires: i < number of vertices.
     Ensures:  returns the mean curvature H at vertex i (1/length). *)

PROCEDURE GetCurvatures(c: T): REF ARRAY OF LONGREAL;
  (* Ensures: returns array of all per-vertex curvatures.
              NUMBER(result^) = number of vertices. *)

PROCEDURE GetResidual(c: T; i: CARDINAL): LONGREAL;
  (* Requires: i < number of vertices.
     Ensures:  returns the height residual at vertex i
               (actual height minus quadratic fit). *)

PROCEDURE GetResiduals(c: T): REF ARRAY OF LONGREAL;
  (* Ensures: returns array of all per-vertex residuals.
              NUMBER(result^) = number of vertices. *)

PROCEDURE NAnomalies(c: T): CARDINAL;
  (* Ensures: returns the number of detected anomalies. *)

PROCEDURE GetAnomaly(c: T; k: CARDINAL): Anomaly;
  (* Requires: k < NAnomalies(c).
     Ensures:  returns the k-th detected anomaly (0-based). *)

END Curv.
