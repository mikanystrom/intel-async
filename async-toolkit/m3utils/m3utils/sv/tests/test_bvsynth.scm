(load "sv/src/svbase.scm")
(load "sv/src/svbv.scm")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Verification by symbolic BDD comparison.
;;
;; We build BDDs two independent ways from the same AST:
;;   1. expr->bv (the synthesizer under test, from svbv.scm)
;;   2. ref-expr->bv (a reference implementation here)
;;
;; Both use the same BDD variables for inputs.  Since BDDs are
;; canonical, if two BDDs represent the same Boolean function they
;; are the same object.  So we just compare with bdd-equal? --
;; no enumeration of 2^N input vectors needed.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Reference BDD builder -- deliberately simple, independent of svbv.scm.
;;; Uses the same bv-lookup / width-get globals (shared BDD variables),
;;; but implements every operator from scratch.

(define (ref-expr->bv node)
  (cond
    ;; Number literal
    ((number? node)
     (ref-bv-const node 32))

    ;; Symbol
    ((symbol? node)
     (let ((s (symbol->string node)))
       (cond
         ((string-index s #\')
          (let ((p (parse-sv-number node)))
            (ref-bv-const (car p) (cdr p))))
         ((equal? s "0") (ref-bv-const 0 1))
         ((equal? s "1") (ref-bv-const 1 1))
         (else (bv-lookup node)))))

    ((not (pair? node))
     (ref-bv-const 0 1))

    ;; (id name)
    ((eq? 'id (car node))
     (bv-lookup (cadr node)))

    ;; Bitwise NOT: (~ expr)
    ((eq? '~ (car node))
     (map bdd-not (ref-expr->bv (cadr node))))

    ;; Bitwise AND: (& a b)
    ((eq? '& (car node))
     (let* ((a (ref-expr->bv (cadr node)))
            (b (ref-expr->bv (caddr node)))
            (w (max (length a) (length b))))
       (map bdd-and (ref-resize a w) (ref-resize b w))))

    ;; Bitwise OR: (| a b)
    ((eq? '| (car node))
     (let* ((a (ref-expr->bv (cadr node)))
            (b (ref-expr->bv (caddr node)))
            (w (max (length a) (length b))))
       (map bdd-or (ref-resize a w) (ref-resize b w))))

    ;; Bitwise XOR: (^ a b)
    ((eq? '^ (car node))
     (let* ((a (ref-expr->bv (cadr node)))
            (b (ref-expr->bv (caddr node)))
            (w (max (length a) (length b))))
       (map bdd-xor (ref-resize a w) (ref-resize b w))))

    ;; Reduction AND: (&-reduce expr)
    ((eq? '&-reduce (car node))
     (let ((bv (ref-expr->bv (cadr node))))
       (list (fold-left bdd-and (bdd-true) bv))))

    ;; Reduction OR: (|-reduce expr)
    ((eq? '|-reduce (car node))
     (let ((bv (ref-expr->bv (cadr node))))
       (list (fold-left bdd-or (bdd-false) bv))))

    ;; Reduction XOR: (^-reduce expr)
    ((eq? '^-reduce (car node))
     (let ((bv (ref-expr->bv (cadr node))))
       (list (fold-left bdd-xor (bdd-false) bv))))

    ;; Addition: (+ a b) -- ripple-carry adder
    ((eq? '+ (car node))
     (let* ((a (ref-expr->bv (cadr node)))
            (b (ref-expr->bv (caddr node)))
            (w (max (length a) (length b)))
            (a1 (ref-resize a w))
            (b1 (ref-resize b w)))
       (ref-ripple-add a1 b1 (bdd-false) w)))

    ;; Subtraction: (- a b) -- a + ~b with carry-in=1
    ((eq? '- (car node))
     (let* ((a (ref-expr->bv (cadr node)))
            (b (ref-expr->bv (caddr node)))
            (w (max (length a) (length b)))
            (a1 (ref-resize a w))
            (b1 (map bdd-not (ref-resize b w))))
       (ref-ripple-add a1 b1 (bdd-true) w)))

    ;; Equality: (== a b)
    ((eq? '== (car node))
     (let* ((a (ref-expr->bv (cadr node)))
            (b (ref-expr->bv (caddr node)))
            (w (max (length a) (length b)))
            (a1 (ref-resize a w))
            (b1 (ref-resize b w)))
       (list (fold-left bdd-and (bdd-true)
                        (map (lambda (x y) (bdd-not (bdd-xor x y)))
                             a1 b1)))))

    ;; Less-than: (< a b) -- unsigned
    ((eq? '< (car node))
     (let* ((a (ref-expr->bv (cadr node)))
            (b (ref-expr->bv (caddr node)))
            (w (max (length a) (length b)))
            (a1 (ref-resize a w))
            (b1 (map bdd-not (ref-resize b w))))
       ;; a < b iff carry-out of (a + ~b + 1) is 0
       (let ((carry (ref-carry-out a1 b1 (bdd-true) w)))
         (list (bdd-not carry)))))

    ;; Greater-than: (> a b)
    ((eq? '> (car node))
     ;; a > b  <==>  b < a
     (ref-expr->bv (list '< (caddr node) (cadr node))))

    ;; Ternary: (?: cond then else)
    ((eq? '?: (car node))
     (let* ((c-bv (ref-expr->bv (cadr node)))
            (c (fold-left bdd-or (bdd-false) c-bv))
            (t (ref-expr->bv (caddr node)))
            (e (ref-expr->bv (cadddr node)))
            (w (max (length t) (length e))))
       (map (lambda (tb eb) (bdd-ite c tb eb))
            (ref-resize t w) (ref-resize e w))))

    ;; Bit index: (index expr idx)
    ((eq? 'index (car node))
     (let* ((base (ref-expr->bv (cadr node)))
            (idx (caddr node)))
       (if (and (number? idx) (>= idx 0) (< idx (length base)))
           (list (list-ref base idx))
           (list (bdd-false)))))

    ;; Part select: (range expr hi lo)
    ((eq? 'range (car node))
     (let* ((base (ref-expr->bv (cadr node)))
            (hi (caddr node))
            (lo (cadddr node)))
       (if (and (number? hi) (number? lo)
                (>= lo 0) (< hi (length base)) (>= hi lo))
           (list-head (list-tail base lo) (+ 1 (- hi lo)))
           (ref-bv-const 0 (+ 1 (- hi lo))))))

    ;; Left shift: (<< a amt)
    ((eq? '<< (car node))
     (let* ((a (ref-expr->bv (cadr node)))
            (amt (caddr node))
            (n (if (number? amt) amt
                   (car (parse-sv-number amt))))
            (w (length a)))
       (if (>= n w)
           (make-list w (bdd-false))
           (append (make-list n (bdd-false))
                   (list-head a (- w n))))))

    ;; Right shift: (>> a amt)
    ((eq? '>> (car node))
     (let* ((a (ref-expr->bv (cadr node)))
            (amt (caddr node))
            (n (if (number? amt) amt
                   (car (parse-sv-number amt))))
            (w (length a)))
       (if (>= n w)
           (make-list w (bdd-false))
           (append (list-tail a n)
                   (make-list n (bdd-false))))))

    ;; Fallback
    (else (ref-bv-const 0 1))))


;;; Reference helpers

(define (ref-bv-const val width)
  (let loop ((i 0) (v val) (acc '()))
    (if (= i width) acc
        (loop (+ i 1) (quotient v 2)
              (append acc (list (if (= 1 (remainder v 2))
                                   (bdd-true) (bdd-false))))))))

(define (ref-resize bv w)
  (let ((cur (length bv)))
    (cond
      ((= cur w) bv)
      ((< cur w) (append bv (make-list (- w cur) (bdd-false))))
      (else (list-head bv w)))))

;; Ripple-carry add, returning w bits (drop carry)
(define (ref-ripple-add a b cin w)
  (let loop ((i 0) (carry cin) (acc '()))
    (if (= i w) acc
        (let* ((ai (list-ref a i))
               (bi (list-ref b i))
               (sum (bdd-xor (bdd-xor ai bi) carry))
               (cout (bdd-or (bdd-and ai bi)
                             (bdd-or (bdd-and ai carry)
                                     (bdd-and bi carry)))))
          (loop (+ i 1) cout (append acc (list sum)))))))

;; Just the carry-out
(define (ref-carry-out a b cin w)
  (let loop ((i 0) (carry cin))
    (if (= i w) carry
        (let* ((ai (list-ref a i))
               (bi (list-ref b i))
               (cout (bdd-or (bdd-and ai bi)
                             (bdd-or (bdd-and ai carry)
                                     (bdd-and bi carry)))))
          (loop (+ i 1) cout)))))


;;; Find the expression assigned to a signal in the body
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


;;; Verify a module: compare synthesized BDDs against reference BDDs
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

  ;; Create BDD vars for inputs (shared by both implementations)
  (for-each (lambda (p) (bv-lookup (cadr p))) inputs)

  ;; Build BDDs via synthesizer
  (define assigns (bv-synth-combinational body))

  (display "  Module: ")
  (displayln (symbol->string name))

  (define all-pass #t)

  (for-each
    (lambda (asgn)
      (let* ((sig-name (car asgn))
             (synth-bv (cdr asgn))
             (out-width (length synth-bv)))

        ;; Find the AST expression for this signal
        (define expr (find-assign-expr sig-name body))

        (if (not expr)
            (begin
              (display "    ")
              (display (symbol->string sig-name))
              (displayln ": SKIP (no assign found)"))
            (let* ((ref-bv (ref-resize (ref-expr->bv expr) out-width))
                   (match (ref-bv-equal? synth-bv ref-bv)))
              (display "    ")
              (display (symbol->string sig-name))
              (display " [")
              (display (number->string out-width))
              (display " bits]: ")
              (if match
                  (displayln "PASS")
                  (begin
                    (displayln "FAIL")
                    (set! all-pass #f)))))))
    assigns)

  all-pass)

;; Compare two bit-vectors for BDD equality, bit by bit
(define (ref-bv-equal? a b)
  (cond
    ((and (null? a) (null? b)) #t)
    ((or (null? a) (null? b)) #f)
    ((not (bdd-equal? (car a) (car b))) #f)
    (else (ref-bv-equal? (cdr a) (cdr b)))))


;;; ================================================================
;;; RUN ALL TESTS
;;; ================================================================

(displayln "")
(displayln "=============================================")
(displayln "  Bit-Vector Synthesis Verification Suite")
(displayln "  (symbolic BDD comparison -- no enumeration)")
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
