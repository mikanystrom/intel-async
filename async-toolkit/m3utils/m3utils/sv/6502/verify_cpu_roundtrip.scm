;; verify_cpu_roundtrip.scm -- Round-trip equivalence check for 6502 CPU cones
;;
;; Rebuilds behavioral BDDs from CPU AST, then builds gate-level BDDs
;; from the emitted gate-level SV AST, sharing input variables.
;;
;; Requires: *cpu-ast-file* = path to behavioral CPU AST
;;           *cpu-gate-ast* = path to gate-level AST

(load "sv/src/svbase.scm")
(load "sv/src/svbv.scm")

;;; Phase 1: Behavioral BDDs (same cone synthesis as synth_cpu_cones.scm)

(displayln "--- Behavioral CPU cones ---")
(define ast-1 (read-sv-file *cpu-ast-file*))
(define mod-1 (car ast-1))

(bv-env-reset!)
(width-reset!)

(define ports-1 (module-ports mod-1))
(define body-1 (module-body-items mod-1))

(extract-port-widths ports-1)
(extract-decl-widths body-1)

;; Process localparams and functions
(for-each
  (lambda (item)
    (cond
      ((and (pair? item) (memq (car item) '(localparam parameter)))
       (let* ((second (cadr item))
              (n (cond
                   ((symbol? second) second)
                   ((pair? second)
                    (let ((last (sv-last item)))
                      (cond
                        ((and (pair? last) (eq? 'id (car last)))
                         (cadr last))
                        ((and (symbol? (caddr item))
                              (not (null? (cdddr item))))
                         (caddr item))
                        (else #f))))
                   (else #f)))
              (val-expr (cond
                          ((symbol? second)
                           (if (not (null? (cdddr item)))
                               (cadddr item) #f))
                          ((pair? second)
                           (let ((last (sv-last item)))
                             (cond
                               ((and (pair? last) (eq? 'id (car last))
                                     (not (null? (cddr last))))
                                (caddr last))
                               ((not (null? (cdddr item)))
                                (cadddr item))
                               (else #f))))
                          (else #f))))
         (if (and n val-expr)
             (let* ((bv (expr->bv val-expr))
                    (w (length bv)))
               (width-set! n w)
               (bv-env-put! n bv)))))
      ((and (pair? item) (eq? 'function (car item)))
       (let* ((rest (cdr item))
              (rest (if (and (pair? rest) (string? (car rest))
                             (string=? (car rest) "automatic"))
                        (cdr rest) rest))
              (ret-type (car rest))
              (fname (cadr rest))
              (fports (caddr rest))
              (body-stmts (cdddr rest))
              (params (map (lambda (p)
                             (let ((pname (cadr (sv-last p)))
                                   (pw (port-width p)))
                               (list pname pw)))
                           (if (and (pair? fports) (eq? 'ports (car fports)))
                               (cdr fports) '())))
              (ret-w (type-width ret-type)))
         (width-set! fname ret-w)
         (set! *bv-func-table*
               (cons (list fname params body-stmts ret-w)
                     *bv-func-table*))))))
  body-1)

;; Pre-create BDD variables for all input ports so they survive
;; bv-env-restore! calls during case/if compilation.
(define ps-1 (collect-port-signals ports-1))
(define in-1 (sv-filter (lambda (p) (eq? 'input (car p))) ps-1))
(for-each (lambda (p) (bv-lookup (cadr p))) in-1)

;; Enable carry cuts
(set! *bv-cut-threshold* 200)

(define all-assigns-1 '())

;; Continuous assigns first (wire-level decoders)
(for-each
  (lambda (item)
    (if (and (pair? item) (eq? 'assign (car item)))
        (let* ((asgn (cadr item))
               (sigs (lvalue-signals (cadr asgn)))
               (bv (expr->bv (caddr asgn))))
          (for-each
            (lambda (s)
              (let* ((rbv (bv-resize bv (width-get s))))
                (set! all-assigns-1 (cons (cons s rbv) all-assigns-1))
                (bv-env-put! s rbv)))
            sigs))))
  body-1)

;; Synthesize always_comb blocks
(for-each
  (lambda (item)
    (if (and (pair? item) (eq? 'always_comb (car item)))
        (let ((assigns (stmt->bv-assigns (cadr item))))
          (set! all-assigns-1 (append all-assigns-1 assigns)))))
  body-1)

(displayln "Behavioral outputs: " (number->string (length all-assigns-1)))
(for-each
  (lambda (a)
    (displayln "  " (symbol->string (car a)) " ["
               (number->string (length (cdr a))) " bits]"))
  all-assigns-1)

;; Collect actual BDD input variables from the synthesized cones
(load "sv/src/svemit.scm")
(define var-names (collect-bdd-vars all-assigns-1))
(displayln "BDD input variables: " (number->string (length var-names)))

;; Inject cut variable BDDs into the env so they survive the restore.
;; (Cut vars are stored separately because bv-env-restore! during
;; if/case/function evaluation discards them from the regular env.)
(bv-cuts-inject-env!)

;; Save ALL env bindings that the gate module might need
;; This includes all BDD variables (register outputs, module inputs)
(define saved-env *bv-env*)

;;; Phase 2: Gate-level BDDs

(displayln "")
(displayln "--- Gate-level CPU cones ---")
(define ast-2 (read-sv-file *cpu-gate-ast*))
(define mod-2 (car ast-2))

;; Reset but keep ALL env bindings (so gate module reuses same BDD variables)
(bv-env-restore! saved-env)
(set! *bv-cuts* '())
(set! *bv-cut-threshold* #f)
(width-reset!)

(extract-port-widths (module-ports mod-2))
(extract-decl-widths (module-body-items mod-2))

;; Enable eviction: pre-scan RHS refs so intermediate wire BDDs are freed
;; after their last consumer.  Reduces peak live wires from ~59K to ~1.3K.
;; Also set the keep-set: only retain output signals (from behavioral model)
;; in the result list -- internal wires are evicted after their last use.
(bv-env-enable-eviction! (module-body-items mod-2))
(bv-synth-set-keep! (map car all-assigns-1))
(define assigns-2 (bv-synth-combinational (module-body-items mod-2)))
(bv-synth-clear-keep!)
(bv-env-disable-eviction!)

(displayln "Gate-level outputs: " (number->string (length assigns-2)))

;;; Phase 3: Compare

(displayln "")
(displayln "--- Comparison ---")

(define all-pass #t)
(define checked 0)

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
            (set! checked (+ checked 1))
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
  all-assigns-1)

(displayln "")
(displayln "Checked " (number->string checked) " outputs")
(if all-pass
    (displayln "=== CPU CONES ROUND-TRIP VERIFIED ===")
    (displayln "=== CPU CONES ROUND-TRIP FAILED ==="))
