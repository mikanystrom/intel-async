(* Copyright (c) 2026 Intel Corporation.  All rights reserved. *)
(* SPDX-License-Identifier: Apache-2.0 *)

MODULE Robinson;

IMPORT Math, GeoCoord, Projection;
<*NOWARN*> IMPORT ProjectionRep;

(* Robinson's tabulated values at 5-degree intervals from 0 to 90.
   PLEN = parallel length factor, PDFE = parallel distance from equator factor. *)

CONST
  N = 19;  (* 0, 5, 10, ..., 90 degrees = 19 entries *)
  PLEN = ARRAY [0..N-1] OF LONGREAL {
    1.0000d0, 0.9986d0, 0.9954d0, 0.9900d0, 0.9822d0,
    0.9730d0, 0.9600d0, 0.9427d0, 0.9216d0, 0.8962d0,
    0.8679d0, 0.8350d0, 0.7986d0, 0.7597d0, 0.7186d0,
    0.6732d0, 0.6213d0, 0.5722d0, 0.5322d0
  };
  PDFE = ARRAY [0..N-1] OF LONGREAL {
    0.0000d0, 0.0620d0, 0.1240d0, 0.1860d0, 0.2480d0,
    0.3100d0, 0.3720d0, 0.4340d0, 0.4958d0, 0.5571d0,
    0.6176d0, 0.6769d0, 0.7346d0, 0.7903d0, 0.8435d0,
    0.8936d0, 0.9394d0, 0.9761d0, 1.0000d0
  };

REVEAL
  T = Projection.T BRANDED Brand OBJECT
    lon0 : LONGREAL := 0.0d0;
  OVERRIDES
    forward := Forward;
    inverse := Inverse;
  END;

PROCEDURE Interpolate(absLatDeg : LONGREAL;
                      VAR plen, pdfe : LONGREAL) =
  VAR
    idx : LONGREAL := absLatDeg / 5.0d0;
    i   : INTEGER  := TRUNC(idx);
    frac : LONGREAL;
  BEGIN
    IF i >= N - 1 THEN
      plen := PLEN[N-1];
      pdfe := PDFE[N-1];
      RETURN
    END;
    frac := idx - FLOAT(i, LONGREAL);
    plen := PLEN[i] + frac * (PLEN[i+1] - PLEN[i]);
    pdfe := PDFE[i] + frac * (PDFE[i+1] - PDFE[i]);
  END Interpolate;

PROCEDURE Forward(self : T;
                  READONLY ll : GeoCoord.LatLon;
                  VAR xy : GeoCoord.XY) : BOOLEAN =
  VAR
    absLatDeg := ABS(ll.lat) * GeoCoord.RadToDeg;
    plen, pdfe : LONGREAL;
  BEGIN
    Interpolate(absLatDeg, plen, pdfe);
    xy.x := plen * GeoCoord.NormalizeLon(ll.lon - self.lon0);
    xy.y := pdfe * Math.Pi / 2.0d0;
    IF ll.lat < 0.0d0 THEN xy.y := -xy.y END;
    RETURN TRUE
  END Forward;

PROCEDURE Inverse(self : T;
                  READONLY xy : GeoCoord.XY;
                  VAR ll : GeoCoord.LatLon) : BOOLEAN =
  VAR
    targetPdfe := ABS(xy.y) / (Math.Pi / 2.0d0);
    i : INTEGER := 0;
    frac, plen, pdfe : LONGREAL;
    absLatDeg : LONGREAL;
  BEGIN
    IF targetPdfe > 1.0d0 THEN RETURN FALSE END;
    (* linear search in PDFE table *)
    WHILE i < N - 2 AND PDFE[i+1] < targetPdfe DO INC(i) END;
    IF ABS(PDFE[i+1] - PDFE[i]) < 1.0d-15 THEN
      frac := 0.0d0;
    ELSE
      frac := (targetPdfe - PDFE[i]) / (PDFE[i+1] - PDFE[i]);
    END;
    absLatDeg := (FLOAT(i, LONGREAL) + frac) * 5.0d0;
    Interpolate(absLatDeg, plen, pdfe);
    IF ABS(plen) < 1.0d-15 THEN RETURN FALSE END;
    ll.lon := GeoCoord.NormalizeLon(xy.x / plen + self.lon0);
    ll.lat := absLatDeg * GeoCoord.DegToRad;
    IF xy.y < 0.0d0 THEN ll.lat := -ll.lat END;
    RETURN TRUE
  END Inverse;

PROCEDURE New(lon0 : LONGREAL := 0.0d0) : T =
  BEGIN
    RETURN NEW(T, name := "Robinson", lon0 := lon0)
  END New;

BEGIN
END Robinson.
