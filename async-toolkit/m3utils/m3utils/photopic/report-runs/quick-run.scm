;; Quick runs for report - 5 subdivision levels instead of 7
;; Produces spectra at dims 2,3,5,9,17,33

(load "../src/photopic.scm")

;; Override run-example! to use fewer iterations
(define (run-quick! cct min-cri min-r9)
  (run-example-iters! cct min-cri min-r9 5 specs->target
                      (string-append "_R9=" (stringify min-r9))))

(define pp
  (obj-method-wrap (LibertyUtils.DoParseParams) 'ParseParams.T))

(if (pp 'keywordPresent "-quick")
    (begin
      (define run-cct (pp 'getNextLongReal      0 1e6))
      (define run-cri (pp 'getNextLongReal -10000 100))
      (define run-r9  (pp 'getNextLongReal -10000 100))
      (run-quick! run-cct run-cri run-r9)
      (exit)))
