;; svsop.scm -- SOP equation output for synthesized modules
;;
;; Converts BDD-synthesized outputs to minimized sum-of-products equations.
;; Uses SopBDD.ConvertBool + invariantSimplify via the bdd->sop primitive.
;;
;; When *bv-cut-threshold* is set, cut variables are emitted first as
;; intermediate equations, keeping all SOPs bounded in size.

(load "sv/src/svbase.scm")
(load "sv/src/svbv.scm")

;; *bv-cut-threshold* can be set here (after svbv.scm defines it as #f).
;; The run-svsop.sh wrapper injects (set! *bv-cut-threshold* N) at this point.
;; CUT-THRESHOLD-HOOK

(define ast (read-sv-file *cpu-ast-file*))
(define mod (car ast))

(bv-env-reset!)
(width-reset!)

(define name (module-name mod))
(define ports (module-ports mod))
(define body (module-body-items mod))

(extract-port-widths ports)
(extract-decl-widths body)

(display "=== SOP Equations: ")
(display (symbol->string name))
(display " ===")
(newline)

;; Process localparams
(for-each
  (lambda (item)
    (if (and (pair? item) (memq (car item) '(localparam parameter)))
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
                (set! *bv-env* (cons (cons n bv) *bv-env*)))))))
  body)

;; Process functions
(for-each
  (lambda (item)
    (if (and (pair? item) (eq? 'function (car item)))
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
                      *bv-func-table*)))))
  body)

;; Collect all combinational assigns
(define all-assigns '())

(for-each
  (lambda (item)
    (if (and (pair? item) (eq? 'always_comb (car item)))
        (let ((assigns (stmt->bv-assigns (cadr item))))
          (set! all-assigns (append all-assigns assigns)))))
  body)

;; Continuous assigns
(for-each
  (lambda (item)
    (if (and (pair? item) (eq? 'assign (car item)))
        (let* ((asgn (cadr item))
               (sigs (lvalue-signals (cadr asgn)))
               (bv (expr->bv (caddr asgn))))
          (for-each
            (lambda (s)
              (let ((rbv (bv-resize bv (width-get s))))
                (set! all-assigns (cons (cons s rbv) all-assigns))
                (set! *bv-env* (cons (cons s rbv) *bv-env*))))
            sigs))))
  body)

;; SOP threshold: above this many BDD nodes, skip minimization
(define *sop-min-threshold* 200)
;; SOP raw threshold: above this, skip SOP conversion entirely (too expensive)
(define *sop-raw-threshold* 500)

;; Emit one SOP equation for a single BDD
(define (emit-sop-eqn name bdd)
  (cond
    ((bdd-true? bdd)
     (display name) (display " = 1'b1;") (newline))
    ((bdd-false? bdd)
     (display name) (display " = 1'b0;") (newline))
    (else
     (let ((sz (bdd-size bdd)))
       (display name)
       (cond
         ((<= sz *sop-min-threshold*)
          (display " = ")
          (display (bdd->sop bdd))
          (display ";")
          (newline)
          (display "  // ")
          (display (bdd->sop-terms bdd))
          (display " products, ")
          (display (number->string sz))
          (display " BDD nodes"))
         ((<= sz *sop-raw-threshold*)
          (display " = ")
          (display (bdd->sop-raw bdd))
          (display ";")
          (newline)
          (display "  // raw, ")
          (display (number->string sz))
          (display " BDD nodes"))
         (else
          (display "  // SKIPPED: ")
          (display (number->string sz))
          (display " BDD nodes (too large for SOP)")))
       (newline)))))

;; Emit cut variable equations (intermediate wires)
(if (not (null? *bv-cuts*))
    (begin
      (newline)
      (display "--- Cut variables (")
      (display (number->string (length *bv-cuts*)))
      (display " intermediate wires) ---")
      (newline)
      (for-each
        (lambda (cut)
          (emit-sop-eqn (car cut) (cdr cut)))
        (reverse *bv-cuts*))
      (newline)
      (display "--- Output equations ---")
      (newline)))

;; Emit output SOP equations
(newline)
(for-each
  (lambda (a)
    (let* ((sig (car a))
           (bv (cdr a))
           (w (length bv))
           (sname (symbol->string sig)))
      (let loop ((i (- w 1)))
        (if (>= i 0)
            (let ((b (list-ref bv i))
                  (bitname (if (> w 1)
                               (string-append sname "["
                                 (number->string i) "]")
                               sname)))
              (emit-sop-eqn bitname b)
              (loop (- i 1)))))))
  all-assigns)

(newline)
(display "=== ")
(display (number->string (length *bv-cuts*)))
(display " cuts, ")
(display (number->string (length all-assigns)))
(display " outputs ===")
(newline)
