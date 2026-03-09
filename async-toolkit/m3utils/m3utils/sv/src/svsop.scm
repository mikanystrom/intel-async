;; svsop.scm -- SOP equation output for synthesized modules
;;
;; Converts BDD-synthesized outputs to equations.
;; Small BDDs (<=50 nodes): minimized SOP via bdd->sop.
;; Larger BDDs: syntax-directed MUX tree — one equation per BDD
;; decision node, with sharing.  Always fast, always bounded.
;;
;; When *bv-cut-threshold* is set, cut variables are emitted first as
;; intermediate equations, keeping all BDDs bounded in size.

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
                (bv-env-put! n bv))))))
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
                (bv-env-put! s rbv)))
            sigs))))
  body)

;; --- SOP emission ---

;; SOP threshold: BDDs at or below this size use minimized SOP.
;; Above this, emit as MUX tree (syntax-directed BDD walk).
(define *sop-min-threshold* 50)

;; --- MUX tree emission ---
;; Walks the BDD structure directly.  Each decision node becomes:
;;   wire = var & hi_wire | ~var & lo_wire
;; Shared subgraphs are emitted once (tracked via *mux-emitted*).
;; Always O(N) in BDD nodes — no SOP library, no blowup.

(define *mux-counter* 0)
(define *mux-emitted* '())

(define (find-mux-emitted bdd)
  (let loop ((lst *mux-emitted*))
    (if (null? lst) #f
        (if (bdd-equal? bdd (caar lst))
            (cdar lst)
            (loop (cdr lst))))))

;; Walk BDD, emit intermediate MUX equations, return name for this node.
(define (emit-mux-node prefix bdd)
  (cond
    ((bdd-true? bdd) "1'b1")
    ((bdd-false? bdd) "1'b0")
    (else
     (let ((cached (find-mux-emitted bdd)))
       (if cached cached
           (let* ((var-bdd (bdd-node-var bdd))
                  (vname (bdd-name var-bdd))
                  (hi (bdd-high bdd))
                  (lo (bdd-low bdd)))
             (cond
               ;; Leaf variable: hi=TRUE, lo=FALSE -> just the var name
               ((and (bdd-true? hi) (bdd-false? lo))
                (set! *mux-emitted* (cons (cons bdd vname) *mux-emitted*))
                vname)
               ;; Complemented leaf: hi=FALSE, lo=TRUE -> ~var
               ((and (bdd-false? hi) (bdd-true? lo))
                (let ((neg (string-append "~" vname)))
                  (set! *mux-emitted* (cons (cons bdd neg) *mux-emitted*))
                  neg))
               ;; General decision node: emit sub-equations, then MUX
               (else
                (let* ((hi-name (emit-mux-node prefix hi))
                       (lo-name (emit-mux-node prefix lo)))
                  (set! *mux-counter* (+ *mux-counter* 1))
                  (let ((my-name (string-append prefix "_n"
                                   (number->string *mux-counter*))))
                    ;; Simplify common cases
                    (display "  ")
                    (display my-name)
                    (display " = ")
                    (cond
                      ;; var & hi | ~var & 0 -> var & hi
                      ((string=? lo-name "1'b0")
                       (display vname) (display " & ") (display hi-name))
                      ;; var & 0 | ~var & lo -> ~var & lo
                      ((string=? hi-name "1'b0")
                       (display "~") (display vname)
                       (display " & ") (display lo-name))
                      ;; var & 1 | ~var & lo -> var | lo
                      ((string=? hi-name "1'b1")
                       (display vname)
                       (display " | ") (display lo-name))
                      ;; var & hi | ~var & 1 -> ~var | hi
                      ((string=? lo-name "1'b1")
                       (display "~") (display vname)
                       (display " | ") (display hi-name))
                      ;; General: var & hi | ~var & lo
                      (else
                       (display vname) (display " & ") (display hi-name)
                       (display " | ~") (display vname)
                       (display " & ") (display lo-name)))
                    (display ";")
                    (newline)
                    (set! *mux-emitted*
                          (cons (cons bdd my-name) *mux-emitted*))
                    my-name))))))))))

;; Emit a BDD as a MUX tree: intermediate wires + final assignment.
(define (emit-mux-eqn name bdd)
  (set! *mux-counter* 0)
  (set! *mux-emitted* '())
  (let ((sz (bdd-size bdd)))
    (display "  // MUX tree, ")
    (display (number->string sz))
    (display " BDD nodes")
    (newline)
    (let ((rhs (emit-mux-node name bdd)))
      (display name)
      (display " = ")
      (display rhs)
      (display ";")
      (newline))))

;; Emit one equation for a single BDD
(define (emit-sop-eqn name bdd)
  (cond
    ((bdd-true? bdd)
     (display name) (display " = 1'b1;") (newline))
    ((bdd-false? bdd)
     (display name) (display " = 1'b0;") (newline))
    (else
     (let ((sz (bdd-size bdd)))
       (if (<= sz *sop-min-threshold*)
           (begin
             (display name)
             (display " = ")
             (display (bdd->sop bdd))
             (display ";")
             (newline)
             (display "  // ")
             (display (bdd->sop-terms bdd))
             (display " products, ")
             (display (number->string sz))
             (display " BDD nodes")
             (newline))
           (emit-mux-eqn name bdd))))))

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
