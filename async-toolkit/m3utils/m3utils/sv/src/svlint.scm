;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; svlint.scm -- Lint checks for SystemVerilog ASTs
;;
;; Author : Claude / Mika Nystroem
;; Date   : March 2026
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; This file implements RTL lint checks on the S-expression ASTs
;; produced by svfe --scm.  It requires svbase.scm to be loaded
;; first (for AST navigation and signal collection).
;;
;; Checks:
;;
;;   1. Undriven outputs       -- output ports with no driver
;;   2. Blocking in always_ff  -- blocking (=) in sequential blocks
;;   3. Non-blocking in comb   -- non-blocking (<=) in always_comb
;;   4. Unused signals         -- declared signals never read
;;   5. Multiple drivers       -- signal assigned in >1 always/assign
;;   6. Latch inference        -- incomplete if/case in always_comb
;;   7. Width mismatches       -- LHS/RHS width differ in assignments
;;
;; Usage:
;;
;;   > (load "sv/src/svbase.scm")
;;   > (load "sv/src/svlint.scm")
;;   > (define ast (read-sv-file "/tmp/mymodule_ast.scm"))
;;   > (lint-all ast)
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; ASSIGNMENT TYPE CHECKING
;;
;; SystemVerilog has strict rules about which assignment types are
;; allowed in which contexts:
;;
;;   always_ff    : only non-blocking (<=) assignments
;;   always_comb  : only blocking (=) assignments
;;   always_latch : only blocking (=) assignments
;;
;; Using the wrong type is a common RTL bug:
;;   - Blocking in always_ff can cause simulation/synthesis mismatch
;;   - Non-blocking in always_comb creates unintended latches
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (find-blocking-in-stmt stmt) -- find signals with blocking (=)
;; assignments in a statement tree.  Used to check always_ff blocks,
;; where only non-blocking (<=) should be used.
;;
;; Returns a list of signal name symbols.
(define (find-blocking-in-stmt stmt)
  (cond
    ((not (pair? stmt)) '())
    ;; Found a blocking assign -- this is the violation
    ((eq? '= (car stmt))
     (lvalue-signals (cadr stmt)))
    ;; Non-blocking is correct in always_ff, skip it
    ((eq? '<= (car stmt)) '())
    ((eq? 'begin (car stmt))
     (sv-append-all
      (map find-blocking-in-stmt (begin-stmts stmt))))
    ((eq? 'if (car stmt))
     (append (find-blocking-in-stmt (caddr stmt))
             (if (> (length stmt) 3)
                 (find-blocking-in-stmt (cadddr stmt))
                 '())))
    ((memq (car stmt) '(case casez casex))
     (sv-append-all (map (lambda (ci)
                           (if (and (pair? ci) (> (length ci) 1))
                               (find-blocking-in-stmt (cadr ci))
                               '()))
                         (cddr stmt))))
    ((eq? 'for (car stmt))
     (find-blocking-in-stmt (sv-last stmt)))
    (else '())))

;; (find-nonblocking-in-stmt stmt) -- find signals with non-blocking
;; (<=) assignments in a statement tree.  Used to check always_comb
;; blocks, where only blocking (=) should be used.
;;
;; Returns a list of signal name symbols.
(define (find-nonblocking-in-stmt stmt)
  (cond
    ((not (pair? stmt)) '())
    ;; Found a non-blocking assign -- this is the violation
    ((eq? '<= (car stmt))
     (lvalue-signals (cadr stmt)))
    ;; Blocking is correct in always_comb, skip it
    ((eq? '= (car stmt)) '())
    ((eq? 'begin (car stmt))
     (sv-append-all
      (map find-nonblocking-in-stmt (begin-stmts stmt))))
    ((eq? 'if (car stmt))
     (append (find-nonblocking-in-stmt (caddr stmt))
             (if (> (length stmt) 3)
                 (find-nonblocking-in-stmt (cadddr stmt))
                 '())))
    ((memq (car stmt) '(case casez casex))
     (sv-append-all (map (lambda (ci)
                           (if (and (pair? ci) (> (length ci) 1))
                               (find-nonblocking-in-stmt (cadr ci))
                               '()))
                         (cddr stmt))))
    ((eq? 'for (car stmt))
     (find-nonblocking-in-stmt (sv-last stmt)))
    (else '())))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; UNUSED SIGNAL DETECTION
;;
;; Collect all signal names read in expressions (RHS of assigns,
;; conditions, index expressions, etc.).
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (collect-read-signals-expr expr) -- signals read in an expression
(define (collect-read-signals-expr expr)
  (cond
    ((not (pair? expr)) '())
    ((eq? 'id (car expr)) (list (cadr expr)))
    ((eq? 'sys (car expr)) '())
    (else (sv-append-all (map collect-read-signals-expr (cdr expr))))))

;; (collect-read-signals-stmt stmt) -- signals read in a statement
(define (collect-read-signals-stmt stmt)
  (cond
    ((not (pair? stmt)) '())
    ((or (eq? '= (car stmt)) (eq? '<= (car stmt)))
     ;; RHS is read, LHS lvalue index expressions are also reads
     (append (collect-read-signals-expr (caddr stmt))
             (collect-lvalue-reads (cadr stmt))))
    ((eq? 'begin (car stmt))
     (sv-append-all (map collect-read-signals-stmt (begin-stmts stmt))))
    ((eq? 'if (car stmt))
     (append (collect-read-signals-expr (cadr stmt))
             (collect-read-signals-stmt (caddr stmt))
             (if (> (length stmt) 3)
                 (collect-read-signals-stmt (cadddr stmt))
                 '())))
    ((memq (car stmt) '(case casez casex unique-case priority-case))
     (append (collect-read-signals-expr (cadr stmt))
             (sv-append-all
               (map (lambda (ci)
                      (if (and (pair? ci) (> (length ci) 1))
                          (append (collect-read-signals-expr (car ci))
                                  (collect-read-signals-stmt (cadr ci)))
                          '()))
                    (cddr stmt)))))
    ((eq? 'for (car stmt))
     (collect-read-signals-stmt (sv-last stmt)))
    (else '())))

;; (collect-lvalue-reads lv) -- read signals in lvalue index/range exprs
(define (collect-lvalue-reads lv)
  (cond
    ((not (pair? lv)) '())
    ((eq? 'id (car lv)) '())  ;; base name is a write, not a read
    ((eq? 'index (car lv))
     (append (collect-lvalue-reads (cadr lv))
             (collect-read-signals-expr (caddr lv))))
    ((eq? 'range (car lv))
     (append (collect-lvalue-reads (cadr lv))
             (collect-read-signals-expr (caddr lv))
             (collect-read-signals-expr (cadddr lv))))
    ((eq? 'concat (car lv))
     (sv-append-all (map collect-lvalue-reads (cdr lv))))
    (else (if (> (length lv) 1) (collect-lvalue-reads (cadr lv)) '()))))

;; (collect-sens-signals sens) -- signals in sensitivity list
;; e.g. (sens (posedge (id clk)) (negedge (id rst_n))) -> (clk rst_n)
(define (collect-sens-signals sens)
  (if (not (and (pair? sens) (eq? 'sens (car sens)))) '()
      (sv-append-all
        (map (lambda (s)
               (cond
                 ((and (pair? s) (memq (car s) '(posedge negedge))
                       (pair? (cdr s)))
                  (collect-read-signals-expr (cadr s)))
                 ((and (pair? s) (eq? 'id (car s)))
                  (list (cadr s)))
                 (else '())))
             (cdr sens)))))

;; (collect-all-reads body) -- all signals read anywhere in module body
(define (collect-all-reads body)
  (define result '())
  (for-each
    (lambda (item)
      (cond
        ((and (pair? item) (eq? 'assign (car item)))
         (let ((asgn (cadr item)))
           (set! result (append (collect-read-signals-expr (caddr asgn))
                                (collect-lvalue-reads (cadr asgn))
                                result))))
        ((and (pair? item)
              (memq (car item) '(always_ff always_comb always_latch always)))
         ;; Include sensitivity list signals as reads
         (let ((sens (if (and (> (length item) 1) (pair? (cadr item))
                              (eq? 'sens (car (cadr item))))
                         (cadr item) #f)))
           (if sens
               (set! result (append (collect-sens-signals sens) result))))
         (set! result (append (collect-read-signals-stmt (sv-last item))
                              result)))))
    body)
  (sv-delete-dups result))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; MULTIPLE DRIVER DETECTION
;;
;; A signal driven in more than one always/assign block is a
;; potential synthesis error (except in generate blocks).
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (collect-per-block-assigns body) -- returns list of (block-type . signal-list)
(define (collect-per-block-assigns body)
  (define result '())
  (define blk-num 0)
  (for-each
    (lambda (item)
      (cond
        ((and (pair? item) (eq? 'assign (car item)))
         (let ((sigs (lvalue-signals (cadr (cadr item)))))
           (set! blk-num (+ blk-num 1))
           (set! result (cons (cons blk-num sigs) result))))
        ((and (pair? item)
              (memq (car item) '(always_ff always_comb always_latch always)))
         (let ((sigs (collect-assigns-in-stmt (sv-last item))))
           (set! blk-num (+ blk-num 1))
           (set! result (cons (cons blk-num (sv-delete-dups sigs)) result))))))
    body)
  (reverse result))

;; (find-multi-driven body) -- signals assigned in >1 block
(define (find-multi-driven body)
  (let* ((blocks (collect-per-block-assigns body))
         (all-sigs (sv-delete-dups (sv-append-all (map cdr blocks)))))
    (sv-filter
      (lambda (sig)
        (> (length (sv-filter (lambda (blk) (memq sig (cdr blk))) blocks)) 1))
      all-sigs)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; LATCH INFERENCE DETECTION
;;
;; An if without else, or a case without default (and not covering
;; all values), in always_comb / always @(*) infers a latch.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (find-latches-in-stmt stmt) -- return signals that may be latched
;; due to incomplete assignment coverage in if/case.
(define (find-latches-in-stmt stmt)
  (cond
    ((not (pair? stmt)) '())
    ((or (eq? '= (car stmt)) (eq? '<= (car stmt))) '())
    ((eq? 'begin (car stmt))
     (sv-append-all (map find-latches-in-stmt (begin-stmts stmt))))
    ((eq? 'if (car stmt))
     (if (<= (length stmt) 3)
         ;; if without else -- signals assigned only in the then branch
         ;; are latched
         (let ((then-sigs (collect-assigns-in-stmt (caddr stmt))))
           (sv-delete-dups then-sigs))
         ;; if with else -- recurse into both branches
         (append (find-latches-in-stmt (caddr stmt))
                 (find-latches-in-stmt (cadddr stmt)))))
    ((memq (car stmt) '(case casez casex unique-case priority-case))
     ;; Check for missing default
     (let* ((items (cddr stmt))
            (has-default (let loop ((is items))
                           (if (null? is) #f
                               (if (and (pair? (car is))
                                        (eq? 'default (caar is)))
                                   #t
                                   (loop (cdr is)))))))
       (if has-default
           ;; Has default -- recurse into case items
           (sv-append-all
             (map (lambda (ci)
                    (if (and (pair? ci) (> (length ci) 1))
                        (find-latches-in-stmt (cadr ci))
                        '()))
                  items))
           ;; No default -- all assigned signals may be latched
           (sv-delete-dups
             (sv-append-all
               (map (lambda (ci)
                      (if (and (pair? ci) (> (length ci) 1))
                          (collect-assigns-in-stmt (cadr ci))
                          '()))
                    items))))))
    ((eq? 'for (car stmt))
     (find-latches-in-stmt (sv-last stmt)))
    (else '())))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; WIDTH MISMATCH DETECTION
;;
;; Uses parse-dim-width from svbv.scm (loaded separately) if available,
;; otherwise uses a local width map.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Local width map for lint (doesn't require svbv.scm)
(define *lint-width-map* '())

(define (lint-width-reset!)
  (set! *lint-width-map* '()))

(define (lint-width-set! name w)
  (set! *lint-width-map* (cons (cons name w) *lint-width-map*)))

(define (lint-width-get name)
  (let ((entry (assq name *lint-width-map*)))
    (if entry (cdr entry) 1)))

;; Parse [hi:lo] dimension to width
(define (lint-parse-dim dim-sym)
  (if (not (symbol? dim-sym)) #f
      (let ((s (symbol->string dim-sym)))
        (let ((len (string-length s)))
          (if (and (> len 2)
                   (equal? (substring s 0 1) "[")
                   (equal? (substring s (- len 1) len) "]"))
              (let loop ((i 1) (hi-chars '()))
                (if (>= i (- len 1)) #f
                    (if (equal? (substring s i (+ i 1)) ":")
                        (let ((hi (string->number
                                    (list->string (reverse hi-chars))))
                              (lo (string->number
                                    (substring s (+ i 1) (- len 1)))))
                          (if (and hi lo) (+ 1 (- hi lo)) #f))
                        (loop (+ i 1)
                              (cons (string-ref s i) hi-chars)))))
              #f)))))

;; Find a [hi:lo] token in a list
(define (lint-find-dims lst)
  (cond
    ((null? lst) #f)
    ((and (symbol? (car lst))
          (let ((s (symbol->string (car lst))))
            (and (> (string-length s) 0)
                 (equal? (substring s 0 1) "["))))
     (car lst))
    (else (lint-find-dims (cdr lst)))))

;; Extract widths from port declarations
(define (lint-extract-port-widths ports-form)
  (if (not (and (pair? ports-form) (eq? 'ports (car ports-form))))
      '()
      (for-each
        (lambda (p)
          (if (and (pair? p) (eq? 'port (car p)))
              (let ((dims (lint-find-dims (cddr p)))
                    (id-form (find-id-in-list (cddr p))))
                (let ((name (if id-form (cadr id-form)
                                (find-bare-before-id (cddr p))))
                      (width (if dims (lint-parse-dim dims) 1)))
                  (if (and name width)
                      (lint-width-set! name width))))))
        (cdr ports-form))))

;; Extract widths from local declarations
(define (lint-extract-decl-widths body)
  (for-each
    (lambda (item)
      (if (and (pair? item) (eq? 'decl (car item)))
          (let ((type-form (if (and (pair? (cdr item)) (pair? (cadr item)))
                               (cadr item) #f))
                (ids (sv-filter (lambda (x) (and (pair? x) (eq? 'id (car x))))
                                (cddr item))))
            (let ((width (if type-form
                             (let ((d (lint-find-dims type-form)))
                               (if d (lint-parse-dim d) 1))
                             1)))
              (for-each
                (lambda (id-form)
                  (if (and (pair? (cdr id-form)) (symbol? (cadr id-form)))
                      (lint-width-set! (cadr id-form) width)))
                ids)))))
    body))

;; Estimate expression width (simplified -- returns #f if unknown)
(define (lint-expr-width expr)
  (cond
    ((number? expr) 32)
    ((symbol? expr)
     (let ((s (symbol->string expr)))
       (if (string-index s #\:)
           ;; Sized literal like 4:b0011
           (let ((apos (string-index s #\:)))
             (string->number (substring s 0 apos)))
           (lint-width-get expr))))
    ((not (pair? expr)) 1)
    ((eq? 'id (car expr)) (lint-width-get (cadr expr)))
    ((memq (car expr) '(& | ^))
     (let ((a (lint-expr-width (cadr expr)))
           (b (lint-expr-width (caddr expr))))
       (if (and a b) (max a b) #f)))
    ((memq (car expr) '(+ -))
     (let ((a (lint-expr-width (cadr expr)))
           (b (lint-expr-width (caddr expr))))
       (if (and a b) (max a b) #f)))
    ((memq (car expr) '(== != < > <= >=)) 1)
    ((memq (car expr) '(&& ||)) 1)
    ((memq (car expr) '(~ !))
     (lint-expr-width (cadr expr)))
    ((eq? '?: (car expr))
     (let ((t (lint-expr-width (caddr expr)))
           (e (lint-expr-width (cadddr expr))))
       (if (and t e) (max t e) #f)))
    ((eq? 'concat (car expr))
     (let ((ws (map lint-expr-width (cdr expr))))
       (if (memq #f ws) #f
           (apply + ws))))
    ((eq? 'index (car expr)) 1)
    ((eq? 'range (car expr))
     (let ((hi (caddr expr)) (lo (cadddr expr)))
       (if (and (number? hi) (number? lo))
           (+ 1 (- hi lo)) #f)))
    (else #f)))

;; *lint-width-warnings* -- accumulated width mismatch warnings (global)
(define *lint-width-warnings* '())

;; (lint-width-check-stmt stmt) -- check width mismatches in assigns
(define (lint-width-check-stmt stmt)
  (cond
    ((not (pair? stmt)) #f)
    ((or (eq? '= (car stmt)) (eq? '<= (car stmt)))
     (let* ((lv (cadr stmt))
            (rv (caddr stmt))
            (lv-sigs (lvalue-signals lv))
            (lv-w (if (null? lv-sigs) #f (lint-width-get (car lv-sigs))))
            (rv-w (lint-expr-width rv)))
       (if (and lv-w rv-w (not (= lv-w rv-w)) (> lv-w 1) (> rv-w 1))
           (set! *lint-width-warnings*
                 (cons (list (car lv-sigs) lv-w rv-w) *lint-width-warnings*)))))
    ((eq? 'begin (car stmt))
     (for-each lint-width-check-stmt (begin-stmts stmt)))
    ((eq? 'if (car stmt))
     (lint-width-check-stmt (caddr stmt))
     (if (> (length stmt) 3)
         (lint-width-check-stmt (cadddr stmt))))
    ((memq (car stmt) '(case casez casex unique-case priority-case))
     (for-each (lambda (ci)
                 (if (and (pair? ci) (> (length ci) 1))
                     (lint-width-check-stmt (cadr ci))))
               (cddr stmt)))
    ((eq? 'for (car stmt))
     (lint-width-check-stmt (sv-last stmt)))))

;; Width mismatch check for whole body
(define (lint-width-mismatches body)
  (set! *lint-width-warnings* '())
  (for-each
    (lambda (item)
      (cond
        ((and (pair? item) (eq? 'assign (car item)))
         (lint-width-check-stmt (cadr item)))
        ((and (pair? item)
              (memq (car item) '(always_ff always_comb always_latch always)))
         (lint-width-check-stmt (sv-last item)))))
    body)
  *lint-width-warnings*)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; LINT DRIVER
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Global warning counter for structured output
(define *lint-warnings* 0)

(define (lint-warn msg)
  (set! *lint-warnings* (+ *lint-warnings* 1))
  (displayln "  WARNING: " msg))

;; (lint-module mod) -- run all lint checks on a single module.
(define (lint-module mod)
  (define name    (module-name mod))
  (define ports   (collect-port-signals (module-ports mod)))
  (define body    (module-body-items mod))
  (define decls   (collect-decl-signals body))
  (define assigns (collect-all-assigns  body))
  (define outputs (sv-filter (lambda (p) (eq? 'output (car p))) ports))
  (define inputs  (sv-filter (lambda (p) (eq? 'input (car p))) ports))

  ;; Initialize width map for this module
  (lint-width-reset!)
  (lint-extract-port-widths (module-ports mod))
  (lint-extract-decl-widths body)

  (displayln "=== Module: " (symbol->string name) " ===")

  ;; Check 1: undriven outputs
  (for-each
   (lambda (o)
     (if (not (member (cadr o) assigns))
         (lint-warn (string-append "output '"
                    (symbol->string (cadr o))
                    "' is never driven"))))
   outputs)

  ;; Check 2: blocking assigns in always_ff
  (for-each
   (lambda (item)
     (if (and (pair? item) (eq? 'always_ff (car item)))
         (for-each
          (lambda (sig)
            (lint-warn (string-append "blocking assign to '"
                       (symbol->string sig)
                       "' in always_ff")))
          (sv-delete-dups (find-blocking-in-stmt (sv-last item))))))
   body)

  ;; Check 3: non-blocking assigns in always_comb / always @(*)
  (for-each
   (lambda (item)
     (cond
       ((and (pair? item) (eq? 'always_comb (car item)))
        (for-each
         (lambda (sig)
           (lint-warn (string-append "non-blocking assign to '"
                      (symbol->string sig)
                      "' in always_comb")))
         (sv-delete-dups (find-nonblocking-in-stmt (sv-last item)))))
       ;; also check always @(*)
       ((and (pair? item) (eq? 'always (car item))
             (pair? (cdr item)) (pair? (cadr item))
             (eq? 'sens (car (cadr item)))
             (member '* (cdr (cadr item))))
        (for-each
         (lambda (sig)
           (lint-warn (string-append "non-blocking assign to '"
                      (symbol->string sig)
                      "' in always @(*)")))
         (sv-delete-dups (find-nonblocking-in-stmt (sv-last item)))))))
   body)

  ;; Check 4: unused signals
  (let ((reads (collect-all-reads body)))
    ;; Check local decls
    (for-each
      (lambda (d)
        (let ((sig (cadr d)))
          (if (and (not (memq sig reads))
                   (not (memq sig assigns)))
              (lint-warn (string-append "signal '"
                         (symbol->string sig)
                         "' is declared but never used")))))
      decls)
    ;; Check input ports
    (for-each
      (lambda (p)
        (let ((sig (cadr p)))
          (if (not (memq sig reads))
              (lint-warn (string-append "input '"
                         (symbol->string sig)
                         "' is never read")))))
      inputs))

  ;; Check 5: multiple drivers
  (let ((multi (find-multi-driven body)))
    (for-each
      (lambda (sig)
        (lint-warn (string-append "signal '"
                   (symbol->string sig)
                   "' has multiple drivers")))
      multi))

  ;; Check 6: latch inference in always_comb / always @(*)
  (for-each
   (lambda (item)
     (cond
       ((and (pair? item) (eq? 'always_comb (car item)))
        (for-each
         (lambda (sig)
           (lint-warn (string-append "possible latch on '"
                      (symbol->string sig)
                      "' in always_comb (incomplete if/case)")))
         (sv-delete-dups (find-latches-in-stmt (sv-last item)))))
       ((and (pair? item) (eq? 'always (car item))
             (pair? (cdr item)) (pair? (cadr item))
             (eq? 'sens (car (cadr item)))
             (member '* (cdr (cadr item))))
        (for-each
         (lambda (sig)
           (lint-warn (string-append "possible latch on '"
                      (symbol->string sig)
                      "' in always @(*) (incomplete if/case)")))
         (sv-delete-dups (find-latches-in-stmt (sv-last item)))))))
   body)

  ;; Check 7: width mismatches (best-effort)
  (let ((wm (lint-width-mismatches body)))
    (for-each
      (lambda (w)
        (if (pair? w)
            (lint-warn (string-append "width mismatch on '"
                       (symbol->string (car w))
                       "': LHS=" (number->string (cadr w))
                       " RHS=" (number->string (caddr w))))))
      wm))

  ;; Summary
  (displayln "  Ports: " (number->string (length ports))
             " (in: " (number->string (length inputs))
             " out: " (number->string (length outputs)) ")")
  (displayln "  Local signals: " (number->string (length decls)))
  (displayln "  Assigned signals: " (number->string (length assigns))))

;; (lint-all nodes) -- run lint checks on all top-level AST nodes.
(define (lint-all nodes)
  (set! *lint-warnings* 0)
  (for-each
   (lambda (node)
     (cond
       ((sv-module? node)    (lint-module node))
       ((sv-package? node)
        (displayln "=== Package: " (symbol->string (cadr node)) " ==="))
       ((sv-interface? node)
        (displayln "=== Interface: " (symbol->string (cadr node)) " ==="))))
   nodes)
  (displayln "")
  (displayln "Total warnings: " (number->string *lint-warnings*)))
