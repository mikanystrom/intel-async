;; verify_alu_roundtrip.scm -- Round-trip equivalence check for 6502 ALU
;;
;; Builds BDDs from behavioral ALU AST and gate-level ALU AST,
;; sharing input BDD variables, then compares output-by-output.
;;
;; Requires: *alu-beh-ast* = path to behavioral AST
;;           *alu-gate-ast* = path to gate-level AST

(load "sv/src/svbase.scm")
(load "sv/src/svbv.scm")

;;; Phase 1: Behavioral BDDs

(displayln "--- Behavioral ALU ---")
(define ast-1 (read-sv-file *alu-beh-ast*))
(define mod-1 (car ast-1))

(bv-env-reset!)
(width-reset!)

(extract-port-widths (module-ports mod-1))
(extract-decl-widths (module-body-items mod-1))

(define ps-1 (collect-port-signals (module-ports mod-1)))
(define in-1 (sv-filter (lambda (p) (eq? 'input (car p))) ps-1))
(define out-1 (sv-filter (lambda (p) (eq? 'output (car p))) ps-1))

(for-each (lambda (p) (bv-lookup (cadr p))) in-1)
(define assigns-1 (bv-synth-combinational (module-body-items mod-1)))

(define output-names (map cadr out-1))
(define output-assigns-1
  (sv-filter (lambda (a) (memq (car a) output-names)) assigns-1))

(for-each
  (lambda (a)
    (let* ((sig (car a))
           (bv (cdr a))
           (nodes (fold-left + 0 (map bdd-size bv))))
      (displayln "  " (symbol->string sig) " ["
                 (number->string (length bv)) " bits]: "
                 (number->string nodes) " BDD nodes")))
  output-assigns-1)

;; Save input BDD variable bindings
(define saved-input-env
  (sv-filter (lambda (e) (memq (car e) (map cadr in-1))) *bv-env*))

;;; Phase 2: Gate-level BDDs

(displayln "")
(displayln "--- Gate-level ALU ---")
(define ast-2 (read-sv-file *alu-gate-ast*))
(define mod-2 (car ast-2))

;; Reset synthesis state but keep input variable bindings
(set! *bv-env* saved-input-env)
(width-reset!)

(extract-port-widths (module-ports mod-2))
(extract-decl-widths (module-body-items mod-2))

(define assigns-2 (bv-synth-combinational (module-body-items mod-2)))

(for-each
  (lambda (a)
    (let* ((sig (car a))
           (bv (cdr a))
           (nodes (fold-left + 0 (map bdd-size bv))))
      (displayln "  " (symbol->string sig) " ["
                 (number->string (length bv)) " bits]: "
                 (number->string nodes) " BDD nodes")))
  (sv-filter (lambda (a) (memq (car a) output-names)) assigns-2))

;;; Phase 3: Compare

(displayln "")
(displayln "--- Comparison ---")

(define all-pass #t)

(for-each
  (lambda (a1)
    (let* ((sig (car a1))
           (bv1 (cdr a1))
           (a2-all (sv-filter (lambda (a) (eq? sig (car a))) assigns-2))
           (a2 (if (null? a2-all) #f (car (reverse a2-all)))))
      (if (not a2)
          (begin
            (displayln "  " (symbol->string sig) ": NOT FOUND in gate-level")
            (set! all-pass #f))
          (let* ((bv2 (cdr a2))
                 (w (min (length bv1) (length bv2)))
                 (match
                   (let loop ((i 0) (b1 bv1) (b2 bv2))
                     (if (= i w) #t
                         (if (bdd-equal? (car b1) (car b2))
                             (loop (+ i 1) (cdr b1) (cdr b2))
                             (begin
                               (displayln "    bit " (number->string i)
                                          " MISMATCH")
                               #f))))))
            (display "  ")
            (display (symbol->string sig))
            (display " [")
            (display (number->string w))
            (display " bits]: ")
            (if match
                (displayln "MATCH")
                (begin
                  (displayln "MISMATCH")
                  (set! all-pass #f)))))))
  output-assigns-1)

(displayln "")
(if all-pass
    (displayln "=== ALU ROUND-TRIP VERIFIED ===")
    (displayln "=== ALU ROUND-TRIP FAILED ==="))
