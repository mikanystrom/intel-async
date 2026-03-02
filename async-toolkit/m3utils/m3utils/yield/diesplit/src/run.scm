; Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information.
; SPDX-License-Identifier: Apache-2.0

(load "yield.scm")
(load "tfc-yield.scm")
(load "tfc-yield-2.scm")

;; Workaround: Polynomial.LaTeXFmt crashes with nil dereference in
;; Mpfr.FormatInt on ARM64_DARWIN.  Redefine decorate-yield to skip
;; LaTeX formatting (not needed for text reports).
(define (decorate-yield yr model ym)
  (let* ((config (car yr))
         (poly   (cadr yr))
         (area   (compute-total-area model config))
         (y      (Mpfr.GetLR (eval-yield poly ym) 'N)))
    (cons area (cons y (cons "" yr)))))

(load "reports.scm")
