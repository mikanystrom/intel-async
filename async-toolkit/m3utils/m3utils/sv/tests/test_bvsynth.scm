(load "sv/src/svbase.scm")
(load "sv/src/svbv.scm")

;;; Exhaustive verification: for all input combos, compare BDD evaluation
;;; against a reference Scheme computation.

;; Helper: string-index for scheme
(define (string-index-sv s ch)
  (let loop ((i 0))
    (if (>= i (string-length s)) #f
        (if (char=? (string-ref s i) ch) i
            (loop (+ i 1))))))

;; Bitwise ops for reference evaluator (mscheme may not have them natively)
(define (bitwise-and a b)
  (if (or (= a 0) (= b 0)) 0
      (+ (* 2 (bitwise-and (quotient a 2) (quotient b 2)))
         (if (and (= 1 (remainder a 2)) (= 1 (remainder b 2))) 1 0))))

(define (bitwise-or a b)
  (if (and (= a 0) (= b 0)) 0
      (+ (* 2 (bitwise-or (quotient a 2) (quotient b 2)))
         (if (or (= 1 (remainder a 2)) (= 1 (remainder b 2))) 1 0))))

(define (bitwise-xor a b)
  (if (and (= a 0) (= b 0)) 0
      (+ (* 2 (bitwise-xor (quotient a 2) (quotient b 2)))
         (if (not (= (remainder a 2) (remainder b 2))) 1 0))))

(define (bitwise-not-w a w)
  ;; NOT with explicit width mask
  (bitwise-xor a (- (expt 2 w) 1)))

(define (arithmetic-shift a n)
  (if (>= n 0)
      (* a (expt 2 n))
      (quotient a (expt 2 (- 0 n)))))

;; Reduction operators on integers of known width
(define (reduce-and-int val w)
  (if (= val (- (expt 2 w) 1)) 1 0))

(define (reduce-or-int val w)
  (if (= val 0) 0 1))

(define (reduce-xor-int val w)
  (let loop ((i 0) (v val) (acc 0))
    (if (= i w) acc
        (loop (+ i 1) (quotient v 2)
              (bitwise-xor acc (remainder v 2))))))

;; Evaluate SV expression on concrete integer values
;; env is ((name . int-value) ...)
;; width-env is ((name . width) ...)
(define (eval-sv-expr node env width-env)
  (define (lookup name)
    (let ((e (assq name env)))
      (if e (cdr e) 0)))
  (define (wid name)
    (let ((e (assq name width-env)))
      (if e (cdr e) 32)))
  (define (mask w) (- (expt 2 w) 1))

  (cond
    ((number? node) node)

    ((symbol? node)
     (let ((s (symbol->string node)))
       (cond
         ((string-index-sv s #\')
          (let ((p (parse-sv-number node)))
            (car p)))
         ((equal? s "0") 0)
         ((equal? s "1") 1)
         (else (lookup node)))))

    ((not (pair? node)) 0)

    ((eq? 'id (car node)) (lookup (cadr node)))

    ;; Bitwise NOT
    ((eq? '~ (car node))
     (let* ((a (eval-sv-expr (cadr node) env width-env))
            ;; Infer width from context: check if the sub-expr is an (id ...)
            (sub (cadr node))
            (w (if (and (pair? sub) (eq? 'id (car sub)))
                   (wid (cadr sub))
                   32)))
       (bitwise-and (bitwise-not-w a w) (mask w))))

    ;; Bitwise AND
    ((eq? '& (car node))
     (bitwise-and (eval-sv-expr (cadr node) env width-env)
                  (eval-sv-expr (caddr node) env width-env)))

    ;; Bitwise OR
    ((eq? '| (car node))
     (bitwise-or (eval-sv-expr (cadr node) env width-env)
                 (eval-sv-expr (caddr node) env width-env)))

    ;; Bitwise XOR
    ((eq? '^ (car node))
     (bitwise-xor (eval-sv-expr (cadr node) env width-env)
                  (eval-sv-expr (caddr node) env width-env)))

    ;; Addition
    ((eq? '+ (car node))
     (+ (eval-sv-expr (cadr node) env width-env)
        (eval-sv-expr (caddr node) env width-env)))

    ;; Subtraction
    ((eq? '- (car node))
     (- (eval-sv-expr (cadr node) env width-env)
        (eval-sv-expr (caddr node) env width-env)))

    ;; Equality
    ((eq? '== (car node))
     (if (= (eval-sv-expr (cadr node) env width-env)
            (eval-sv-expr (caddr node) env width-env)) 1 0))

    ;; Inequality
    ((eq? '!= (car node))
     (if (not (= (eval-sv-expr (cadr node) env width-env)
                 (eval-sv-expr (caddr node) env width-env))) 1 0))

    ;; Less-than (unsigned)
    ((eq? '< (car node))
     (if (< (eval-sv-expr (cadr node) env width-env)
            (eval-sv-expr (caddr node) env width-env)) 1 0))

    ;; Greater-than (unsigned)
    ((eq? '> (car node))
     (if (> (eval-sv-expr (cadr node) env width-env)
            (eval-sv-expr (caddr node) env width-env)) 1 0))

    ;; Ternary
    ((eq? '?: (car node))
     (if (not (= 0 (eval-sv-expr (cadr node) env width-env)))
         (eval-sv-expr (caddr node) env width-env)
         (eval-sv-expr (cadddr node) env width-env)))

    ;; Bit index: (index expr idx)
    ((eq? 'index (car node))
     (let ((base (eval-sv-expr (cadr node) env width-env))
           (idx (caddr node)))
       (if (number? idx)
           (bitwise-and 1 (arithmetic-shift base (- 0 idx)))
           0)))

    ;; Part select: (range expr hi lo)
    ((eq? 'range (car node))
     (let ((base (eval-sv-expr (cadr node) env width-env))
           (hi (caddr node))
           (lo (cadddr node)))
       (if (and (number? hi) (number? lo))
           (let* ((h hi)
                  (l lo)
                  (w (+ 1 (- h l))))
             (bitwise-and (mask w) (arithmetic-shift base (- 0 l))))
           0)))

    ;; Reduction AND
    ((eq? '&-reduce (car node))
     (let* ((sub (cadr node))
            (val (eval-sv-expr sub env width-env))
            (w (if (and (pair? sub) (eq? 'id (car sub)))
                   (wid (cadr sub)) 8)))
       (reduce-and-int val w)))

    ;; Reduction OR
    ((eq? '|-reduce (car node))
     (let ((val (eval-sv-expr (cadr node) env width-env)))
       (reduce-or-int val 8)))

    ;; Reduction XOR
    ((eq? '^-reduce (car node))
     (let* ((sub (cadr node))
            (val (eval-sv-expr sub env width-env))
            (w (if (and (pair? sub) (eq? 'id (car sub)))
                   (wid (cadr sub)) 8)))
       (reduce-xor-int val w)))

    ;; Left shift
    ((eq? '<< (car node))
     (let ((a (eval-sv-expr (cadr node) env width-env))
           (b (eval-sv-expr (caddr node) env width-env)))
       (arithmetic-shift a b)))

    ;; Right shift
    ((eq? '>> (car node))
     (let ((a (eval-sv-expr (cadr node) env width-env))
           (b (eval-sv-expr (caddr node) env width-env)))
       (arithmetic-shift a (- 0 b))))

    (else 0)))

;; Find the expression assigned to a signal in the body
(define (find-assign-expr sig body)
  (let loop ((items body))
    (if (null? items) #f
        (let ((item (car items)))
          (if (and (pair? item) (eq? 'assign (car item)))
              (let ((asgn (cadr item)))
                (if (and (pair? asgn) (eq? '= (car asgn))
                         (pair? (cadr asgn)) (eq? 'id (car (cadr asgn)))
                         (eq? sig (cadr (cadr asgn))))
                    (caddr asgn)
                    (loop (cdr items))))
              (loop (cdr items)))))))

;;; Verify a module from an AST file
(define (verify-bv-module-file filename)
  (define ast (read-sv-file filename))
  (define mod (car ast))

  (bv-env-reset!)
  (width-reset!)

  (define name (module-name mod))
  (define ports (module-ports mod))
  (define body (module-body-items mod))

  (extract-port-widths ports)
  (extract-decl-widths body)

  (define port-sigs (collect-port-signals ports))
  (define inputs (sv-filter (lambda (p) (eq? 'input (car p))) port-sigs))
  (define outputs (sv-filter (lambda (p) (eq? 'output (car p))) port-sigs))

  ;; Create BDD vars for inputs
  (for-each (lambda (p) (bv-lookup (cadr p))) inputs)

  ;; Build BDDs via synthesis
  (define assigns (bv-synth-combinational body))

  ;; Build input info list
  (define input-info
    (map (lambda (p) (cons (cadr p) (width-get (cadr p)))) inputs))

  ;; Total input bits
  (define total-bits
    (fold-left + 0 (map cdr input-info)))

  (define n-vectors (expt 2 total-bits))

  ;; Width env for reference evaluator
  (define width-env
    (map (lambda (p) (cons (cadr p) (width-get (cadr p))))
         (append inputs outputs)))

  (display "  Module: ")
  (display (symbol->string name))
  (display " (")
  (display (number->string total-bits))
  (display " input bits, ")
  (display (number->string n-vectors))
  (displayln " vectors)")

  (define all-pass #t)

  (for-each
    (lambda (asgn)
      (let* ((sig-name (car asgn))
             (bv (cdr asgn))
             (out-width (length bv))
             (out-mask (- (expt 2 out-width) 1))
             (pass #t)
             (fail-count 0))

        ;; Find the expression for this signal in the body
        (define expr (find-assign-expr sig-name body))

        (if (not expr)
            (begin
              (display "    ")
              (display (symbol->string sig-name))
              (displayln ": SKIP (no expression found)"))
            (begin
              ;; Test all input vectors
              (let vloop ((vec-num 0))
                (if (and (< vec-num n-vectors) (< fail-count 5))
                    (let* ((int-env (make-int-env vec-num input-info))
                           (bdd-env (make-bdd-env vec-num input-info))
                           ;; BDD result
                           (bdd-val (bitwise-and (eval-bv bv bdd-env) out-mask))
                           ;; Reference result
                           (ref-raw (eval-sv-expr expr int-env width-env))
                           ;; Handle negative results from subtraction
                           (ref-val (bitwise-and
                                      (if (< ref-raw 0)
                                          (+ ref-raw (expt 2 out-width))
                                          ref-raw)
                                      out-mask)))
                      (if (not (= bdd-val ref-val))
                          (begin
                            (set! pass #f)
                            (set! all-pass #f)
                            (set! fail-count (+ fail-count 1))
                            (display "    FAIL ")
                            (display (symbol->string sig-name))
                            (display " vec=")
                            (display (number->string vec-num))
                            (display " bdd=")
                            (display (number->string bdd-val))
                            (display " ref=")
                            (display (number->string ref-val))
                            (newline)))
                      (vloop (+ vec-num 1)))))

              (display "    ")
              (display (symbol->string sig-name))
              (if pass
                  (begin (display ": PASS (")
                         (display (number->string n-vectors))
                         (displayln " vectors)"))
                  (begin (display ": FAIL (")
                         (display (number->string fail-count))
                         (displayln " mismatches)")))))))
    assigns)

  all-pass)

;; Build an integer environment from a vector number
;; input-info is ((name . width) ...)
(define (make-int-env vec-num input-info)
  (let loop ((info input-info) (v vec-num) (acc '()))
    (if (null? info) acc
        (let* ((name (caar info))
               (w (cdar info))
               (mask (- (expt 2 w) 1))
               (val (bitwise-and v mask)))
          (loop (cdr info) (arithmetic-shift v (- 0 w))
                (cons (cons name val) acc))))))

;; Build a BDD variable environment from a vector number
(define (make-bdd-env vec-num input-info)
  (let loop ((info input-info) (v vec-num) (acc '()))
    (if (null? info) acc
        (let* ((name (caar info))
               (w (cdar info)))
          (let iloop ((i 0) (v2 v) (acc2 acc))
            (if (= i w)
                (loop (cdr info) v2 acc2)
                (let ((var-name (if (= w 1)
                                   (symbol->string name)
                                   (string-append (symbol->string name)
                                                  "[" (number->string i) "]"))))
                  (iloop (+ i 1) (quotient v2 2)
                         (cons (cons var-name (remainder v2 2)) acc2)))))))))

;;; ================================================================
;;; RUN ALL TESTS
;;; ================================================================

(displayln "")
(displayln "=============================================")
(displayln "  Bit-Vector Synthesis Verification Suite")
(displayln "=============================================")

(define *test-results* '())

(define (run-test name file)
  (displayln "")
  (displayln "--- " name " ---")
  (let ((result (verify-bv-module-file file)))
    (set! *test-results* (cons (cons name result) *test-results*))
    (if result
        (displayln "  RESULT: PASS")
        (displayln "  RESULT: *** FAIL ***"))))

(run-test "4-bit adder"       "/tmp/bvsynth-ast/test_add4.ast.scm")
(run-test "4-bit subtractor"  "/tmp/bvsynth-ast/test_sub4.ast.scm")
(run-test "4-bit bitwise ops" "/tmp/bvsynth-ast/test_bitwise4.ast.scm")
(run-test "4-bit comparator"  "/tmp/bvsynth-ast/test_cmp4.ast.scm")
(run-test "4-bit wide mux"    "/tmp/bvsynth-ast/test_mux4w.ast.scm")
(run-test "8-bit reductions"  "/tmp/bvsynth-ast/test_reduce8.ast.scm")
(run-test "4-bit shifts"      "/tmp/bvsynth-ast/test_shift4.ast.scm")
(run-test "8-bit range/index" "/tmp/bvsynth-ast/test_range4.ast.scm")

(displayln "")
(displayln "=============================================")
(displayln "  SUMMARY")
(displayln "=============================================")

(define *total-pass* 0)
(define *total-fail* 0)

(for-each
  (lambda (r)
    (display "  ")
    (display (car r))
    (if (cdr r)
        (begin (displayln ": PASS")
               (set! *total-pass* (+ *total-pass* 1)))
        (begin (displayln ": FAIL")
               (set! *total-fail* (+ *total-fail* 1)))))
  (reverse *test-results*))

(displayln "")
(display "  Total: ")
(display (number->string *total-pass*))
(display " passed, ")
(display (number->string *total-fail*))
(displayln " failed")
(displayln "=============================================")
