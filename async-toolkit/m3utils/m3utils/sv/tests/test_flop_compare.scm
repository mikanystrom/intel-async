(load "sv/src/svbase.scm")
(load "sv/src/svbv.scm")

;;; Compare behavioral vs gate-level BDDs for the ALU pipeline.
;;; Both must share the same BDD variable objects for inputs.

;;; 1. Build behavioral BDDs

(displayln "--- Behavioral (always_ff cone) ---")
(define ast-1 (read-sv-file "/tmp/flop-demo/alu_pipe.ast.scm"))
(define mod-1 (car ast-1))

(bv-env-reset!)
(width-reset!)

(extract-port-widths (module-ports mod-1))
(extract-decl-widths (module-body-items mod-1))

(define ps-1 (collect-port-signals (module-ports mod-1)))
(define in-1 (sv-filter (lambda (p)
                           (and (eq? 'input (car p))
                                (not (eq? 'clk (cadr p)))))
                         ps-1))
(for-each (lambda (p) (bv-lookup (cadr p))) in-1)

(define assigns-1 (bv-synth-combinational (module-body-items mod-1)))
(for-each
  (lambda (a)
    (display "  ")
    (display (symbol->string (car a)))
    (display ": ")
    (display (number->string (length (cdr a))))
    (displayln " bits"))
  assigns-1)

;; Save input env
(define saved-input-env
  (sv-filter (lambda (e) (memq (car e) (map cadr in-1))) *bv-env*))


;;; 2. Build gate-level BDDs (reusing same BDD variables)

(displayln "")
(displayln "--- Gate-level (MUX decomposition) ---")
(define ast-2 (read-sv-file "/tmp/flop-demo/alu_pipe_gates.ast.scm"))
(define mod-2 (car ast-2))

(set! *bv-env* saved-input-env)
(width-reset!)

(extract-port-widths (module-ports mod-2))
(extract-decl-widths (module-body-items mod-2))

(define assigns-2 (bv-synth-combinational (module-body-items mod-2)))

(define result-assigns
  (sv-filter (lambda (a) (eq? 'result (car a))) assigns-2))
(for-each
  (lambda (a)
    (display "  ")
    (display (symbol->string (car a)))
    (display ": ")
    (display (number->string (length (cdr a))))
    (displayln " bits"))
  result-assigns)


;;; 3. Compare

(displayln "")
(displayln "--- BDD Comparison ---")

(define all-pass #t)

(for-each
  (lambda (a1)
    (let* ((sig (car a1))
           (bv1 (cdr a1))
           (a2-all (sv-filter (lambda (a) (eq? sig (car a))) assigns-2))
           (a2 (if (null? a2-all) #f (car (reverse a2-all)))))
      (if (not a2)
          (begin
            (display "  ")
            (display (symbol->string sig))
            (displayln ": NOT FOUND")
            (set! all-pass #f))
          (let* ((bv2 (cdr a2))
                 (w (min (length bv1) (length bv2)))
                 (match
                   (let loop ((i 0) (b1 bv1) (b2 bv2))
                     (if (= i w) #t
                         (if (bdd-equal? (car b1) (car b2))
                             (loop (+ i 1) (cdr b1) (cdr b2))
                             (begin
                               (display "    bit ")
                               (display (number->string i))
                               (displayln " MISMATCH")
                               #f))))))
            (display "  ")
            (display (symbol->string sig))
            (display " [")
            (display (number->string w))
            (display " bits]: ")
            (if match
                (displayln "MATCH  (bdd-equal? = #t)")
                (begin
                  (displayln "MISMATCH")
                  (set! all-pass #f)))))))
  assigns-1)

(displayln "")
(if all-pass
    (displayln "=== VERIFIED: behavioral always_ff = gate-level SV ===")
    (displayln "=== VERIFICATION FAILED ==="))
