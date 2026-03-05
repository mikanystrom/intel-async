; Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information.
; SPDX-License-Identifier: Apache-2.0

(define *n5-n* 32)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; WARNING: The value below is a FICTITIOUS PLACEHOLDER.
;; It is a MADE-UP number to stand in for proprietary data.
;; DO NOT USE FOR PRODUCTION YIELD ESTIMATES.
;; The real value is subject to NDA and is not in this repository.
;; Contact your TSMC representative for further information.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define *n5-saturation-D0* 0.075)  ;; FICTITIOUS - not a real TSMC value
;; TSMC official value is CENSORED
;; the dummy value above is chosen to be plausible but is NOT real

(define *tsmc-large-die-correction* -0.02)

(define *n5-be-D0* (+ *n5-saturation-D0* *tsmc-large-die-correction*))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Mika's model matching code
;;
;; The idea of the below code is to match the observed TSMC yield figures
;; for a largish silicon die, for which I would assume that TSMC wants to
;; publish relatively accurate data.  We choose 500 sq. mm as the baseline.
;; We in addition assume that alpha=0.07 per TOM's "mature technology"
;; guidelines.  TOM suggests alpha can go down as low as 0.02 in very mature
;; technologies.  Note that alpha < D0 leads to interesting math (improper
;; integrals).
;;

(define *alpha* 0.07)
;; guess from Mika/TOM -- see above

(define *poisson-alpha* 10)
;; big but not so big that powers, etc., blow up

(define *match-area* 500) ;; match the TSMC yield model at this area

(define (match-stapper D)
  (YieldModel.Stapper *match-area* D *n5-n* *alpha*))

(define (match-poisson D)
  (YieldModel.Stapper *match-area* D *n5-n* *poisson-alpha*))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; the following are test formulas for N5
(define stapper-d0
  (solve (make-target match-stapper
                      (YieldModel.BoseEinstein *match-area* *n5-be-D0* *n5-n*))
         0.01 0.15)
  )

(define poisson-d0
  (solve (make-target match-poisson
                      (YieldModel.BoseEinstein *match-area* *n5-be-D0* *n5-n*))
         0.01 0.15)
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (make-params tgt-area b-e-d0 n stapper-alpha)
  ;; for a given Bose-Einstein (alpha=1) D0 @ given tgt-area and n
  ;; compute D0 for a matching Stapper yield with stapper-alpha
  ;; return
  ;; (stapper-d0 stapper-alpha)
  (let* ((matcher
          (lambda(D)(YieldModel.Stapper tgt-area D n stapper-alpha)))

         (stapper-D0
          (solve (make-target matcher
                              (YieldModel.BoseEinstein tgt-area b-e-d0 n))
                 0.01 0.15)))

    `(,stapper-D0 ,stapper-alpha ,n)))

(define params `((,stapper-d0 ,*alpha*) (,poisson-d0 ,*poisson-alpha*)))

;; build the official parameter sets for N5

(define *n5-params* `(,(make-params *match-area* *n5-be-D0* *n5-n* *alpha*)
;;                      ,(make-params *match-area* *n5-be-D0* *n5-n* *poisson-alpha*)
                      ))

(define params *n5-params*)

(define 9/16 (/ 9 16))
(define 6/16 (/ 6 16))
(define 6/8 (/ 6 8))
(define 15/16 (/ 15 16))

