(load "sv/src/svbase.scm")
(load "sv/src/svbv.scm")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Phase 2: Parse gate-level SV, build BDDs, compare with behavioral.
;;
;; IMPORTANT: bdd-var creates a NEW variable each time, even for the
;; same name.  So both modules must share the same *bv-env* for input
;; variables.  We build the behavioral BDDs first, then for the gate-
;; level module we only reset *width-map* (not *bv-env*) so the same
;; BDD variables are reused.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Build BDDs for behavioral module

(displayln "--- Behavioral module ---")
(define ast-1 (read-sv-file "/tmp/roundtrip/test_add4.ast.scm"))
(define mod-1 (car ast-1))

(bv-env-reset!)
(width-reset!)

(extract-port-widths (module-ports mod-1))
(extract-decl-widths (module-body-items mod-1))

(define ps-1 (collect-port-signals (module-ports mod-1)))
(define in-1 (sv-filter (lambda (p) (eq? 'input (car p))) ps-1))
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

;; Save the input BDD variable bindings
(define saved-input-env
  (sv-filter (lambda (e) (memq (car e) (map cadr in-1))) *bv-env*))

;;; Build BDDs for gate-level module
;;; Reset env but KEEP input variable bindings so same BDD nodes are reused

(displayln "")
(displayln "--- Gate-level module ---")
(define ast-2 (read-sv-file "/tmp/roundtrip/roundtrip_gates.ast.scm"))
(define mod-2 (car ast-2))

;; Reset synthesis state but restore input variable bindings
(bv-env-restore! saved-input-env)
(width-reset!)

(extract-port-widths (module-ports mod-2))
(extract-decl-widths (module-body-items mod-2))

;; Don't re-create input vars -- they're already in *bv-env* from above
(define assigns-2 (bv-synth-combinational (module-body-items mod-2)))

;; Find sum in assigns-2
(define sum-assigns
  (sv-filter (lambda (a) (eq? 'sum (car a))) assigns-2))

(for-each
  (lambda (a)
    (display "  ")
    (display (symbol->string (car a)))
    (display ": ")
    (display (number->string (length (cdr a))))
    (displayln " bits"))
  sum-assigns)

;;; Compare

(displayln "")
(displayln "--- Comparison ---")

(define all-pass #t)

(for-each
  (lambda (a1)
    (let* ((sig (car a1))
           (bv1 (cdr a1))
           ;; Find the LAST entry for this signal (after threading, there may
           ;; be multiple entries; the last one from bv-synth-combinational
           ;; is the final assignment)
           (a2-all (sv-filter (lambda (a) (eq? sig (car a))) assigns-2))
           (a2 (if (null? a2-all) #f (car (reverse a2-all)))))
      (if (not a2)
          (begin
            (display "  ")
            (display (symbol->string sig))
            (displayln ": NOT FOUND in gate-level")
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
                               (display ": beh=")
                               (display (bdd-format (car b1)))
                               (display " gate=")
                               (displayln (bdd-format (car b2)))
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
  assigns-1)

(displayln "")
(if all-pass
    (displayln "=== ROUND-TRIP VERIFIED: behavioral = gate-level ===")
    (displayln "=== ROUND-TRIP FAILED ==="))
