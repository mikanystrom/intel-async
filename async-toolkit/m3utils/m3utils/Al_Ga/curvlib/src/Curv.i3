(* Copyright (c) 2026 Mika Nystrom.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

INTERFACE Curv;

IMPORT TriMesh, Facet;

(* Per-vertex curvature estimation and anomaly detection.

   Curvature is estimated in the rotated (z-up) frame using the
   cotangent-weighted discrete Laplacian on the height field.  For
   a nearly-planar facet, the Laplacian of the height z(x,y)
   approximates 2H where H is the mean curvature.

   Anomalies are vertices whose height residual (after subtracting
   a best-fit quadratic surface) exceeds a threshold in standard
   deviations. *)

TYPE
  T <: REFANY;

  Stats = RECORD
    meanCurv   : LONGREAL;  (* mean of per-vertex curvatures *)
    minCurv    : LONGREAL;
    maxCurv    : LONGREAL;
    stdCurv    : LONGREAL;  (* standard deviation of curvatures *)
    meanHeight : LONGREAL;  (* mean height residual after quadratic fit *)
    stdHeight  : LONGREAL;  (* std dev of residual *)
    nAnomalies : CARDINAL;  (* number of anomalous vertices *)
  END;

  Anomaly = RECORD
    vertex   : CARDINAL;
    x, y     : LONGREAL;    (* position in rotated frame *)
    height   : LONGREAL;    (* residual height *)
    curvature: LONGREAL;
  END;

PROCEDURE Analyze(mesh: TriMesh.T; facet: Facet.T;
                  threshold: LONGREAL := 3.0d0): T;
  (* Compute curvature and detect anomalies.
     threshold is in standard deviations of the height residual. *)

PROCEDURE GetStats(c: T): Stats;

PROCEDURE GetCurvature(c: T; i: CARDINAL): LONGREAL;
  (* Per-vertex curvature. *)

PROCEDURE GetCurvatures(c: T): REF ARRAY OF LONGREAL;

PROCEDURE GetResidual(c: T; i: CARDINAL): LONGREAL;
  (* Height residual after quadratic fit. *)

PROCEDURE GetResiduals(c: T): REF ARRAY OF LONGREAL;

PROCEDURE NAnomalies(c: T): CARDINAL;

PROCEDURE GetAnomaly(c: T; k: CARDINAL): Anomaly;
  (* k-th detected anomaly, 0-based. *)

END Curv.
