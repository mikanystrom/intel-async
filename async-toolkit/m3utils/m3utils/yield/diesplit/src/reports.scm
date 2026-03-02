; Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information.
; SPDX-License-Identifier: Apache-2.0

(load "reports-code.scm")

(define *n5-n* 32)

(define params `((0.075 1 ,*n5-n*) ;; B-E
                 (0.05 1 ,*n5-n*)
                 (0.10 1 ,*n5-n*)

                 (0.10 0.05 ,*n5-n*) ;; Stapper
                 (0.10 0.02 ,*n5-n*)
                 (0.10 0.01 ,*n5-n*)
                 (0.075 0.05 ,*n5-n*)
                 (0.075 0.02 ,*n5-n*)

                 (0.10 10 ,*n5-n*) ;; Poisson
                 (0.05 10 ,*n5-n*)
                 ))

(define basic-params `((0.05 1 ,*n5-n*) (0.075 0.05 ,*n5-n*) (0.05 10 ,*n5-n*)))

(report-yields-for-params
 (tfc-model)

 basic-params  ;; short list of techs
;params        ;; long list of techs
 
 (list (eohalf-25t-model) (lrhalf-25t-model))
 )

(report-yields-for-params
 (tfc-twodie-model)

 basic-params  ;; short list of techs
;params        ;; long list of techs
 
 ()
 )
