;; synth_cpu_cones.scm -- Analyze and synthesize 6502 CPU combinational cones
;;
;; Synthesizes the decode cones (branch_taken, is_rmw, is_store, continuous
;; assigns).  The execution logic block (cone 2) is skipped because the
;; 8-bit carry chains in ADC/SBC/CMP cause BDD blowup.

(load "sv/src/svbase.scm")
(load "sv/src/svbv.scm")
(load "sv/src/svemit-c.scm")

(define ast (read-sv-file *cpu-ast-file*))
(define mod (car ast))

(bv-env-reset!)
(width-reset!)

(define name (module-name mod))
(define ports (module-ports mod))
(define body (module-body-items mod))

(extract-port-widths ports)
(extract-decl-widths body)

(displayln "=== CPU Module: " (symbol->string name) " ===")
(displayln "")

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
                     *bv-func-table*))
         (displayln "Registered function: " (symbol->string fname))))))
  body)

;; Pre-create BDD variables for all input ports so they survive
;; bv-env-restore! calls during case/if compilation.
(define ps (collect-port-signals ports))
(for-each (lambda (p) (if (eq? 'input (car p)) (bv-lookup (cadr p)))) ps)

;; Synthesize each always_comb block individually
;; Enable carry cuts and case decomposition for complex blocks
(set! *bv-cut-threshold* 200)

(define cone-num 0)
(define total-nodes 0)
(define all-assigns '())

;; Continuous assigns first (wire-level decoders like aaa=opcode[7:5])
;; so that always_comb blocks see computed values, not fresh variables.
(displayln "")
(displayln "--- Continuous assigns ---")
(for-each
  (lambda (item)
    (if (and (pair? item) (eq? 'assign (car item)))
        (let* ((asgn (cadr item))
               (sigs (lvalue-signals (cadr asgn)))
               (bv (expr->bv (caddr asgn))))
          (for-each
            (lambda (s)
              (let* ((rbv (bv-resize bv (width-get s)))
                     (nodes (fold-left + 0 (map bdd-size rbv))))
                (set! total-nodes (+ total-nodes nodes))
                (set! all-assigns (cons (cons s rbv) all-assigns))
                (bv-env-put! s rbv)
                (displayln "  " (symbol->string s) " ["
                           (number->string (length rbv)) " bits]: "
                           (number->string nodes) " BDD nodes")))
            sigs))))
  body)

(for-each
  (lambda (item)
    (if (and (pair? item) (eq? 'always_comb (car item)))
        (begin
          (set! cone-num (+ cone-num 1))
          (displayln "")
          (displayln "--- Combinational cone " (number->string cone-num) " ---")
          (let ((assigns (stmt->bv-assigns (cadr item))))
            (set! all-assigns (append all-assigns assigns))
            (for-each
              (lambda (a)
                (let* ((sig (car a))
                       (bv (cdr a))
                       (w (length bv))
                       (nodes (fold-left + 0 (map bdd-size bv))))
                  (set! total-nodes (+ total-nodes nodes))
                  (displayln "  " (symbol->string sig) " ["
                             (number->string w) " bits]: "
                             (number->string nodes) " BDD nodes")))
              assigns)))))
  body)

(displayln "")
(displayln "=== Total BDD nodes: " (number->string total-nodes) " ===")
(displayln "=== Synthesized outputs: " (number->string (length all-assigns)) " ===")

;; Generate C eval if output file specified
(if *cpu-output-file*
    (begin
      (displayln "")
      (displayln "Generating C evaluation functions...")
      (define comb-inputs
        (map (lambda (name) (list 'input name))
             '(opcode P aaa)))
      (define oport (open-output-file *cpu-output-file*))
      (emit-c-eval-to-port "cpu_6502_decode" comb-inputs all-assigns oport)
      (close-output-port oport)
      (displayln "Written to " *cpu-output-file*)))
