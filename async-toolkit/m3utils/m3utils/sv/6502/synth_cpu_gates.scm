;; synth_cpu_gates.scm -- Synthesize 6502 CPU cones and emit gate-level SV
;;
;; Same as synth_cpu_cones.scm but adds gate-level SV emission via svemit.scm.
;;
;; Requires: *cpu-ast-file* = path to CPU AST
;;           *cpu-gate-file* = path to write gate-level SV

(load "sv/src/svbase.scm")
(load "sv/src/svbv.scm")
(load "sv/src/svemit.scm")

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

;; Process localparams and functions (same as synth_cpu_cones.scm)
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
               (set! *bv-env* (cons (cons n bv) *bv-env*))))))
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

;; Enable carry cuts for complex arithmetic
(set! *bv-cut-threshold* 200)

(define cone-num 0)
(define total-nodes 0)
(define all-assigns '())

;; Synthesize always_comb blocks
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

;; Continuous assigns
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
                (set! *bv-env* (cons (cons s rbv) *bv-env*))
                (displayln "  " (symbol->string s) " ["
                           (number->string (length rbv)) " bits]: "
                           (number->string nodes) " BDD nodes")))
            sigs))))
  body)

(displayln "")
(displayln "=== Total BDD nodes: " (number->string total-nodes) " ===")
(displayln "=== Synthesized outputs: " (number->string (length all-assigns)) " ===")

;; Helper: parse "opcode[3]" -> ("opcode" . 3) or "foo" -> ("foo" . #f)
(define (parse-var-name vn)
  (let ((bracket (let loop ((i (- (string-length vn) 1)))
                   (if (< i 0) #f
                       (if (char=? (string-ref vn i) #\[) i
                           (loop (- i 1)))))))
    (if bracket
        (cons (substring vn 0 bracket)
              (string->number (substring vn (+ bracket 1)
                                         (- (string-length vn) 1))))
        (cons vn #f))))

;; Collect actual BDD input variables from all cones
;; These are the signals the combinational logic depends on
;; (register outputs, module inputs) — NOT the module port list.
(define all-var-names (collect-bdd-vars all-assigns))

;; Filter out cut variables and output signals — those are internal wires
(define output-names (map car all-assigns))
(define (is-cut-var? name)
  (and (> (string-length name) 5)
       (string=? (substring name 0 5) "_cut_")))
(define (is-output-var? name)
  (let* ((parsed (parse-var-name name))
         (base (string->symbol (car parsed))))
    (memq base output-names)))

(define var-names
  (sv-filter (lambda (v) (and (not (is-cut-var? v))
                               (not (is-output-var? v))))
             all-var-names))
(displayln "")
(displayln "BDD input variables: " (number->string (length var-names)))
(for-each (lambda (v) (displayln "  " v)) var-names)

(define (group-var-names var-names)
  ;; Returns ((base-name . max-index) ...) in order
  (define groups '())
  (for-each
    (lambda (vn)
      (let* ((parsed (parse-var-name vn))
             (base (car parsed))
             (idx (cdr parsed))
             (existing (assoc base groups)))
        (if existing
            (if (and idx (> idx (cdr existing)))
                (set-cdr! existing idx))
            (set! groups (cons (cons base (if idx idx 0)) groups)))))
    var-names)
  (reverse groups))

(define var-groups (group-var-names var-names))
(define inputs
  (map (lambda (grp)
         (let* ((base (car grp))
                (max-idx (cdr grp))
                (w (+ max-idx 1)))
           (width-set! (string->symbol base) w)
           (list 'input (string->symbol base))))
       var-groups))

(define outputs
  (map (lambda (a) (list 'output (car a))) all-assigns))

;; Emit gate-level SV directly to file (avoids O(n^2) string concat)
(displayln "")
(displayln "Emitting gate-level SV...")
(let ((port (open-output-file *cpu-gate-file*)))
  (emit-gate-module-to-port "cpu_6502" inputs outputs all-assigns port)
  (close-output-port port))

(displayln "Gate-level SV written to " *cpu-gate-file*)
(displayln "Internal gate nodes: " (number->string *emit-counter*))
