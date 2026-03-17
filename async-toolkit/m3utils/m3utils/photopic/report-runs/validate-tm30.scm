;; TM-30 validation script for photopic
;;
;; Usage (from photopic/src/):
;;   ../ARM64_DARWIN/photopic -scm -scmfile photopic.scm -grid -tm30 -scmfile ../report-runs/validate-tm30.scm
;;
;; Or from the REPL after loading photopic.scm with -grid -tm30:
;;   (load "../report-runs/validate-tm30.scm")
;;
;; Compares photopic TM-30 against colour-science reference values.
;; Reference values from validate-tm30.py (colour-science 0.4.7).

(dis "=== TM-30 Validation ===" dnl dnl)

;;; Helper: compute and display TM-30 for a grid spectrum
(define (validate-tm30 name sgrid expected-Rf expected-Rg)
  (let* ((tm30 (grid-calc-tm30 sgrid))
         (Rf   (car tm30))
         (Rg   (cadr tm30))
         (Rcs  (caddr tm30))
         (ref-temp-res (cadddr tm30))
         (cct  (car ref-temp-res))
         (Duv  (cadr ref-temp-res)))
    (dis "--- " name " ---" dnl)
    (dis "  CCT = " cct " K, Duv = " Duv dnl)
    (dis "  Rf  = " Rf  "  (expected: " expected-Rf ")" dnl)
    (dis "  Rg  = " Rg  "  (expected: " expected-Rg ")" dnl)
    (dis "  Rcs = (")
    (let loop ((i 0))
      (if (< i 16)
          (begin
            (dis " " (vector-ref Rcs i))
            (loop (+ i 1)))))
    (dis " )" dnl)
    (let ((dRf (abs (- Rf expected-Rf)))
          (dRg (abs (- Rg expected-Rg))))
      (dis "  |dRf| = " dRf (if (< dRf 2.0) "  OK" "  ** MISMATCH **") dnl)
      (dis "  |dRg| = " dRg (if (< dRg 2.0) "  OK" "  ** MISMATCH **") dnl))
    (dis dnl)))

;;; Test 1: Planckian 3000K — should give Rf ≈ 100, Rg ≈ 100
(dis "Test 1: Planckian 3000K (self-reference)" dnl)
(validate-tm30 "Planckian 3000K"
               (grid-blackbody 3000)
               100.0 100.0)

;;; Test 2: Planckian 2856K (Illuminant A) — Rf ≈ 100, Rg ≈ 100
(dis "Test 2: Planckian 2856K (Illuminant A)" dnl)
(validate-tm30 "Planckian 2856K"
               (grid-blackbody 2856)
               100.0 100.0)

;;; Test 3: FL2 (cool white fluorescent) — Rf ≈ 70.12, Rg ≈ 86.42
;;; Note: FL2 has CCT ≈ 4224K, which is in the Planckian/D-illuminant
;;; blend zone.  Our implementation uses pure Planckian as reference,
;;; so Rf/Rg may differ from colour-science for this illuminant.
(dis "Test 3: FL2 (Cool White Fluorescent)" dnl)
(let ((fl2-grid (spectrum->grid (FL 2))))
  (validate-tm30 "FL2" fl2-grid 70.12 86.42))

;;; Test 4: FL11 — Rf ≈ 80.04, Rg ≈ 101.06
;;; CCT ≈ 3999K, below the blend zone, should be accurate.
(dis "Test 4: FL11" dnl)
(let ((fl11-grid (spectrum->grid (FL 11))))
  (validate-tm30 "FL11" fl11-grid 80.04 101.06))

;;; Regression: verify CRI is unchanged
(dis "=== CRI Regression Check ===" dnl)
(let* ((fl2-grid (spectrum->grid (FL 2)))
       (cri (grid-calc-cri fl2-grid))
       (ri-8 (head 8 (cadr cri)))
       (ra (/ (apply + ri-8) 8)))
  (dis "FL2 CRI Ra = " ra " (should be ~64)" dnl))

(dis dnl "=== Done ===" dnl)

(exit)
