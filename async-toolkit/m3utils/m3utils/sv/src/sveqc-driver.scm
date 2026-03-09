;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; sveqc-driver.scm -- Equivalence checking driver
;;
;; Performs round-trip equivalence checking on a single module:
;;   1. Parse RTL AST, extract port info + widths
;;   2. Build BDDs for each output (bv-synth-combinational)
;;   3. Emit gate-level SV (emit-gate-module from svemit.scm)
;;   4. Write gate-level SV to temp file
;;   5. Report: for each output, BDD node count
;;
;; Two-file mode (set *sveqc-ref-file*):
;;   1. Parse both ASTs
;;   2. Build BDDs from each (sharing input variables)
;;   3. Compare output BDDs bit-by-bit
;;
;; Globals expected:
;;   *sveqc-ast-file*   -- primary AST file (required)
;;   *sveqc-ref-file*   -- reference AST file (optional, for 2-file mode)
;;   *sveqc-gate-file*  -- output gate-level SV file (optional)
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(load "sv/src/svbase.scm")
(load "sv/src/svbv.scm")
(load "sv/src/svemit.scm")

;; Compare two bit-vectors for BDD equality
(define (eqc-bv-equal? a b)
  (cond
    ((and (null? a) (null? b)) #t)
    ((or (null? a) (null? b)) #f)
    ((not (bdd-equal? (car a) (car b))) #f)
    (else (eqc-bv-equal? (cdr a) (cdr b)))))


;;; ================================================================
;;; SINGLE-FILE MODE: self-equivalence (synth + report)
;;; ================================================================

(define (eqc-self-check ast-file)
  (define ast (read-sv-file ast-file))
  (define mod (car ast))

  (bv-env-reset!)
  (width-reset!)

  (define name (module-name mod))
  (define params (module-params mod))
  (define ports (module-ports mod))
  (define body (module-body-items mod))

  ;; Process parameters first (for parametric widths)
  (if params (extract-param-defaults params))
  (extract-port-widths ports)
  (extract-decl-widths body)

  (define port-sigs (collect-port-signals ports))
  (define inputs (sv-filter (lambda (p) (eq? 'input (car p))) port-sigs))
  (define outputs (sv-filter (lambda (p) (eq? 'output (car p))) port-sigs))

  ;; Create BDD variables for inputs
  (for-each (lambda (p) (bv-lookup (cadr p))) inputs)

  ;; Build BDDs
  (define assigns (bv-synth-combinational body))

  (displayln "=== EQC: " (symbol->string name) " ===")
  (displayln "  Inputs:  " (number->string (length inputs)))
  (displayln "  Outputs: " (number->string (length outputs)))

  ;; Report per-output info
  (define total-nodes 0)
  (for-each
    (lambda (a)
      (let* ((sig (car a))
             (bv (cdr a))
             (w (length bv))
             (nodes (fold-left + 0 (map bdd-size bv))))
        (set! total-nodes (+ total-nodes nodes))
        (display "  ")
        (display (symbol->string sig))
        (display " [")
        (display (number->string w))
        (display " bits]: ")
        (display (number->string nodes))
        (displayln " BDD nodes")))
    assigns)

  (displayln "  Total BDD nodes: " (number->string total-nodes))

  ;; Emit gate-level SV if *sveqc-gate-file* was set
  (if (string? *sveqc-gate-file*)
      (let ((gate-sv (emit-gate-module (symbol->string name)
                                        inputs outputs assigns)))
        (let ((port (open-output-file *sveqc-gate-file*)))
          (display gate-sv port)
          (close-output-port port))
        (displayln "  Gate-level SV written to " *sveqc-gate-file*)))

  (displayln "  PASS (synthesis complete)")
  assigns)


;;; ================================================================
;;; TWO-FILE MODE: compare two designs
;;; ================================================================

(define (eqc-two-file ast-file ref-file)
  (displayln "=== EQC: Two-file comparison ===")

  ;; Parse first design
  (define ast-1 (read-sv-file ast-file))
  (define mod-1 (car ast-1))

  (bv-env-reset!)
  (width-reset!)

  (define name-1 (module-name mod-1))
  (define params-1 (module-params mod-1))
  (if params-1 (extract-param-defaults params-1))
  (extract-port-widths (module-ports mod-1))
  (extract-decl-widths (module-body-items mod-1))

  (define ps-1 (collect-port-signals (module-ports mod-1)))
  (define in-1 (sv-filter (lambda (p) (eq? 'input (car p))) ps-1))

  ;; Create shared input BDD variables
  (for-each (lambda (p) (bv-lookup (cadr p))) in-1)

  ;; Build BDDs for design 1
  (define assigns-1 (bv-synth-combinational (module-body-items mod-1)))
  (displayln "  Design 1: " (symbol->string name-1)
             " (" (number->string (length assigns-1)) " outputs)")

  ;; Save input env
  (define saved-env
    (sv-filter (lambda (e) (memq (car e) (map cadr in-1))) *bv-env*))

  ;; Parse second design
  (define ast-2 (read-sv-file ref-file))
  (define mod-2 (car ast-2))

  (bv-env-restore! saved-env)
  (width-reset!)

  (define name-2 (module-name mod-2))
  (define params-2 (module-params mod-2))
  (if params-2 (extract-param-defaults params-2))
  (extract-port-widths (module-ports mod-2))
  (extract-decl-widths (module-body-items mod-2))

  ;; Build BDDs for design 2
  (define assigns-2 (bv-synth-combinational (module-body-items mod-2)))
  (displayln "  Design 2: " (symbol->string name-2)
             " (" (number->string (length assigns-2)) " outputs)")

  ;; Compare
  (displayln "")
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
              (displayln ": NOT FOUND in design 2")
              (set! all-pass #f))
            (let* ((bv2 (cdr a2))
                   (w (min (length bv1) (length bv2)))
                   (match (let loop ((i 0) (b1 bv1) (b2 bv2))
                            (if (= i w) #t
                                (if (bdd-equal? (car b1) (car b2))
                                    (loop (+ i 1) (cdr b1) (cdr b2))
                                    #f)))))
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
      (displayln "=== EQUIVALENCE VERIFIED ===")
      (displayln "=== EQUIVALENCE FAILED ==="))
  all-pass)


;;; ================================================================
;;; MAIN
;;; ================================================================

;; *sveqc-ast-file* must be set before loading this driver.
;; For two-file mode, also set *sveqc-ref-file* and *sveqc-mode* to "two-file".
;; Default: single-file self-check.
(if (eq? *sveqc-mode* 'two-file)
    (eqc-two-file *sveqc-ast-file* *sveqc-ref-file*)
    (eqc-self-check *sveqc-ast-file*))
