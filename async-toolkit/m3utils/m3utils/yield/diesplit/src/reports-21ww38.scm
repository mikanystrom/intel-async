; Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information.
; SPDX-License-Identifier: Apache-2.0

;;
;; look at the N3 design idea
;; monolithic central die with four N5 serdes tiles
;;

(require-modules "m3")
(load "tfc-yield.scm")
(load "yield.scm")
(load "direct-yield.scm")
(load "reports-code.scm")
(load "defs-21ww07.scm") ;; N5 params

(load "tfc-yield-2.scm")
;;(load "reports-21ww25.scm")

(define *n5-n3-logic-improvement* 0.333) ;; N5:N3::(1 + .7):1 s.b. 0.75 -> 0.333
(define *n5-n3-ram-improvement* 0.176)   ;; N5:N3::(1 + 0.2) : 1 s.b. 0.85 -> 0.176
(define *n5-n3-channel-improvement* 0.2) ;; use ram, since they are wiring ltd?
(define *n5-n3-serdes-improvement* 0.1)

;; from Anurag 11/9/21: N3/N5 areas:
;; logic std cell     0.71
;; SRAM + periphery   0.82
;; analog             0.90

;; design is a list of lists

(define *last-design* '())

(define (convert-n5-to-n3 design)
  (set! *last-design* design)
  ;;(dis "converting : " design dnl)
  (cond ((null? design) '())
        ((and (list? design)
              (> (length design) 1)
              (number? (cadr design))
              (not (eq? (car design) 'scale))
              )
         ;; an actual size spec
         ;; take it apart into label and params
         (cons (car design) (apply convert-n5-n3-size (cdr design)))
         )
        ((list? design) (map convert-n5-to-n3 design))
        (else design))
  )

(define (convert-n5-n3-size area . optional)
   (let ((ram-area          0)
         (channel-area      0)
         (serdes-area       0)
         (channel-nfactor-ratio   (/ 9 32))
         (repaired-ram-k   .6);;.6 ;;area includes ram-area
         (serdes-k         .8)
         (repair           'dummy)
         (repair-cost      'dummy)
         )

     (do-overrides! optional (current-environment)) 
     
     (let* ((logic-area
             (- area ram-area channel-area serdes-area))

            (new-logic-area   (improve-area logic-area *n5-n3-logic-improvement*) )
            (new-ram-area     (improve-area ram-area   *n5-n3-ram-improvement*) )
            (new-channel-area (improve-area channel-area *n5-n3-channel-improvement*) )
            (new-serdes-area  (improve-area serdes-area *n5-n3-serdes-improvement*))

            (new-area (+ new-logic-area new-ram-area new-channel-area new-serdes-area)))

       (cons new-area (cons-if-nonzero 'ram-area new-ram-area
                                       (cons-if-nonzero 'channel-area new-channel-area
                                                        (cons-if-nonzero 'serdes-area new-serdes-area
                                                                         '())))))))

(define (cons-if-nonzero symbol value tail)
  (if (= 0 value)
      tail
      (cons symbol
            (cons value
                  tail))))

(define (improve-area area by)
  (/ area (+ 1 by)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (tfc-model-n3) (convert-n5-to-n3 (tfc-model)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; helper routines to pull out various bits of a design by name
;;

;; the following two are each other's complement

(define (extract-labeled-block label design)
  (cond ((null? design) '())
        
        ((and (list? design) (> (length design) 1) (eq? label (car design)))
         design)
        
        ((list? design)
         (let loop ((p design))
           (if (null? p)
               '()
               (let ((this (extract-labeled-block label (car p))))
                 (if (null? this) (loop (cdr p)) this)))))
        
        (else '())))

(define (remove-labeled-block label design)
  (cond ((null? design) '())

        ((and (list? design)(eq? label (car design)))
         '())

        ((list? design)
         (let loop ((p design)
                    (res '()))
           (cond ((null? p)
                  (reverse res))

                 (else
                  (let ((this (remove-labeled-block label (car p))))
                    (if (null? this)
                        (loop (cdr p) res)
                        (loop (cdr p) (cons this res))))))))

        (else design)))

(define (add-block block design)
  (append (list (car design) block) (cdr design)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;

(define (n3-core-tfc)
  (convert-n5-to-n3 (remove-labeled-block 'serdes (tfc-model))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Set basic yield parameters for N3.
;; Methodology here follows N5 methodology from defs-21ww07.scm.
;;
;; Basically we are matching TSMC's yield numbers for a die of a given size,
;; using alpha=0.07, somewhat arbitrarily chosen.
;;
;; An alternative approach would be to match TSMC's yield numbers for dice of
;; two different sizes, solving the simultaneous equations for alpha and D0.
;;

;; the following is the set of parameters for N3
;; the TSMC yield model is the same as for N7 and N5 w.r.t. die size correction
;; (per email from CherSian)
;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; WARNING: ALL VALUES BELOW ARE FICTITIOUS PLACEHOLDERS.
;; They are MADE-UP numbers to stand in for proprietary data.
;; DO NOT USE FOR PRODUCTION YIELD ESTIMATES.
;; The real values are subject to NDA and are not in this repository.
;; Contact your TSMC representative for further information.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define *n3-17m-n* 34.00)        ;; FICTITIOUS - not a real value
(define *n3-18m-n* 36.00)        ;; FICTITIOUS - not a real value

(define *n3-d0-2023q3*   0.100)  ;; FICTITIOUS - not a real TSMC value
(define *n3-d0-2024q3*   0.080)  ;; FICTITIOUS - not a real TSMC value
(define *n3-d0-2025q4*   0.065)  ;; FICTITIOUS - not a real TSMC value


;; let's work in 18M, 2024
;; no let's do it in 2025Q4
(define *n3-chosen-d0* *n3-d0-2025q4*)

(define *n3-be-D0* (+ *n3-chosen-d0* *tsmc-large-die-correction*))
  
(define *n3-params* `(,(make-params *match-area*
                                    *n3-be-D0*
                                    *n3-18m-n*
                                    *alpha*)
;;                      ,(make-params *match-area*
;;                                    *n3-be-D0*
;;                                    *n3-18m-n*
;;                                    *poisson-alpha*)
                      ))

(define *alpha*          0.07) ;; see defs-21ww07.scm
(define *poisson-alpha* 10)

(define *ref-area* 500) ;; we match models at 500 mm^2

(define (match-stapper D) (YieldModel.Stapper 500 D *n3-18m-n* *alpha*))

(define *stapper-n3-d0*
  (solve (make-target match-stapper
                      (YieldModel.BoseEinstein
                       *ref-area*
                       (+ *n3-chosen-d0* (tsmc-d0-correction *ref-area*))
                       *n3-18m-n*))
         0.01 0.15))

(define tile-d2d-overhead-area 30) ;; area to connect to tiles, in N5 units

(define tile-d2d-overhead-spec
  `(tile-d2d ,tile-d2d-overhead-area serdes-area , tile-d2d-overhead-area))

(define (convert-to-tiles model)
  (remove-labeled-block 'serdes (add-block tile-d2d-overhead-spec (model))))
   
(define (tfc-with-tiles-model) (convert-to-tiles tfc-model))

(define (n5-bloated-with-tiles-model) (make-downbin tfc-with-tiles-model `(tfc-bloated (big (scale ,*bloat-factor* tfc)))))

(define (n5-bloated-lrhalf-model) (make-downbin lrhalf-25t-model `(bloated-lrhalf (big (scale ,*bloat-factor* lrhalf-25t)))))

(define (n5-bloated-eohalf-model) (make-downbin eohalf-25t-model `(bloated-eohalf (big (scale ,*bloat-factor* eohalf-25t)))))

(define (n5-bloated-lrhalf-with-tiles-model) (convert-to-tiles n5-bloated-lrhalf-model))

(define (n5-bloated-eohalf-with-tiles-model) (convert-to-tiles n5-bloated-eohalf-model))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (n3-tfc-with-tiles-model) (convert-n5-to-n3 (tfc-with-tiles-model)))

(define (n3-bloated-lrhalf-with-tiles-model) (convert-n5-to-n3 (n5-bloated-lrhalf-with-tiles-model)))

(define (n3-bloated-eohalf-with-tiles-model) (convert-n5-to-n3 (n5-bloated-eohalf-with-tiles-model)))

;;(define *n5-params* params)

;;(define *n3-params* `((,*n3-chosen-d0* ,*poisson-alpha*)
;;                      (,*stapper-n3-d0*  ,*alpha*)))


(define *bloat-factor* 1.15)

(define (make-scaled-model named from-model factor)
  `(,named (scale ,factor ,from-model)))

(define (n3-bloated-model) (make-downbin n3-tfc-with-tiles-model `(tfc-bloated (big (scale ,*bloat-factor* tfc)))))

;; this is running a report for the core die only in N3
(define (run-reports-n3) (report-yields-for-params
                          (n3-tfc-with-tiles-model)
                          *n3-params*
                          `(,(n3-bloated-model)
                            ,(n3-bloated-lrhalf-with-tiles-model)
                            ,(n3-bloated-eohalf-with-tiles-model))))

;; this is running a report for the core die only in N5
(define (run-core-reports-n5)  (report-yields-for-params
                          (tfc-with-tiles-model)
                          *n5-params*
                          `(,(n5-bloated-with-tiles-model)
                            ,(n5-bloated-lrhalf-with-tiles-model)
                            ,(n5-bloated-eohalf-with-tiles-model))))

(define (run-full-reports-n5) (report-yields-for-params
                               (n5-bloated-with-tiles-model)
                               *n5-params*
                               `(,(n5-bloated-lrhalf-model)
                                 ,(n5-bloated-eohalf-model))))


(define (serdes-model)
  (extract-labeled-block 'serdes (tfc-model)))

(define (split-serdes-model split-factor)
  (make-scaled-model 'split-serdes (serdes-model) (/ 1 split-factor)))

(define *serdes-tile-count* 4)

(define (serdes-tile-model)
  (add-block
   (let ((d2d-area (/ tile-d2d-overhead-area *serdes-tile-count*)))
     `(serdes-tile-d2d ,d2d-area serdes-area ,d2d-area))
   (split-serdes-model *serdes-tile-count*)))
  
  

(define (run-serdes-tile-report-n5)
  (report-yields-for-params
   (serdes-tile-model)
   *n5-params*
   `()))
