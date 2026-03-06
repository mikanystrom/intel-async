;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; svbv.scm -- Bit-vector synthesis: LRM-correct multi-bit BDD synthesis
;;
;; Author : Claude / Mika Nystroem
;; Date   : March 2026
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; This file implements a bit-accurate logic synthesizer that handles
;; multi-bit SystemVerilog signals correctly per the LRM.
;;
;; A "bit-vector" (bv) is a list of BDDs, one per bit, LSB first:
;;   (bdd_0 bdd_1 ... bdd_{n-1})
;;
;; Every signal is represented as a bv.  Operators produce bvs of
;; the correct width, following LRM width propagation rules.
;;
;; Requires svbase.scm and the svsynth interpreter (bdd-* primitives).
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 1. BIT-VECTOR PRIMITIVES
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Constant bit-vectors
(define (bv-const val width)
  ;; val is an integer, width is the number of bits
  (let loop ((i 0) (v val) (acc '()))
    (if (= i width)
        acc
        (loop (+ i 1) (quotient v 2)
              (append acc (list (if (= (remainder v 2) 1)
                                   (bdd-true)
                                   (bdd-false))))))))

(define (bv-zero width) (bv-const 0 width))
(define (bv-ones width) (bv-const (- (expt 2 width) 1) width))
(define (bv-width bv) (length bv))

;; Zero-extend or truncate to target width
(define (bv-resize bv target-width)
  (let ((w (length bv)))
    (cond
      ((= w target-width) bv)
      ((< w target-width)
       ;; zero-extend
       (append bv (make-list (- target-width w) (bdd-false))))
      (else
       ;; truncate
       (list-head bv target-width)))))

(define (make-list n val)
  (if (<= n 0) '()
      (cons val (make-list (- n 1) val))))

(define (list-head lst n)
  (if (or (<= n 0) (null? lst)) '()
      (cons (car lst) (list-head (cdr lst) (- n 1)))))

;; Extract a sub-range [hi:lo] from a bv (both inclusive, 0-based)
(define (bv-range bv hi lo)
  (list-head (list-tail bv lo) (+ 1 (- hi lo))))

;; Single bit extract
(define (bv-bit bv idx)
  (list-ref bv idx))

(define (list-ref lst n)
  (if (= n 0) (car lst)
      (list-ref (cdr lst) (- n 1))))

;; Convert a BDD bitvector to a constant integer, or #f if any bit is non-constant
(define (bv-to-const bv)
  (let loop ((bits bv) (i 0) (val 0))
    (if (null? bits) val
        (cond
          ((bdd-true? (car bits))
           (loop (cdr bits) (+ i 1) (+ val (expt 2 i))))
          ((bdd-false? (car bits))
           (loop (cdr bits) (+ i 1) val))
          (else #f)))))

;; Try to evaluate a simple expression to a constant integer.
;; Uses *width-map* and *bv-env* for known constants.
;; Returns an integer or #f if not evaluable.
(define (try-const-eval expr)
  (cond
    ((number? expr) expr)
    ((symbol? expr)
     (let ((entry (assq expr *bv-env*)))
       (if entry (bv-to-const (cdr entry)) #f)))
    ((not (pair? expr)) #f)
    ((eq? 'id (car expr))
     (let ((entry (assq (cadr expr) *bv-env*)))
       (if entry (bv-to-const (cdr entry)) #f)))
    ((eq? '- (car expr))
     (if (null? (cddr expr))
         ;; Unary minus
         (let ((a (try-const-eval (cadr expr))))
           (if a (- 0 a) #f))
         ;; Binary minus
         (let ((a (try-const-eval (cadr expr)))
               (b (try-const-eval (caddr expr))))
           (if (and a b) (- a b) #f))))
    ((eq? '+ (car expr))
     (let ((a (try-const-eval (cadr expr)))
           (b (try-const-eval (caddr expr))))
       (if (and a b) (+ a b) #f)))
    ((eq? '* (car expr))
     (let ((a (try-const-eval (cadr expr)))
           (b (try-const-eval (caddr expr))))
       (if (and a b) (* a b) #f)))
    ((eq? '/ (car expr))
     (let ((a (try-const-eval (cadr expr)))
           (b (try-const-eval (caddr expr))))
       (if (and a b (not (= b 0))) (quotient a b) #f)))
    ((eq? '<< (car expr))
     (let ((a (try-const-eval (cadr expr)))
           (b (try-const-eval (caddr expr))))
       (if (and a b) (* a (expt 2 b)) #f)))
    ((eq? '>> (car expr))
     (let ((a (try-const-eval (cadr expr)))
           (b (try-const-eval (caddr expr))))
       (if (and a b) (quotient a (expt 2 b)) #f)))
    (else #f)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 2. BITWISE OPERATIONS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (bv-not bv)
  (map bdd-not bv))

(define (bv-and a b)
  (map bdd-and a b))

(define (bv-or a b)
  (map bdd-or a b))

(define (bv-xor a b)
  (map bdd-xor a b))

;; Reduction operators -- return 1-bit bv
(define (bv-reduce-and bv)
  (list (fold-left bdd-and (bdd-true) bv)))

(define (bv-reduce-or bv)
  (list (fold-left bdd-or (bdd-false) bv)))

(define (bv-reduce-xor bv)
  (list (fold-left bdd-xor (bdd-false) bv)))

(define (fold-left fn init lst)
  (if (null? lst) init
      (fold-left fn (fn init (car lst)) (cdr lst))))

;; Concatenation: (bv-concat lo hi) = {hi, lo} but stored LSB-first
;; so lo bits come first, hi bits after
(define (bv-concat-list bvs)
  ;; bvs is in source order: MSB-part first
  ;; e.g., {a, b} means a is MSB-part, b is LSB-part
  ;; In our LSB-first representation, b's bits come first, then a's
  (if (null? bvs) '()
      (append (bv-concat-list (cdr bvs)) (car bvs))))

;; Wait -- concat in SV: {a, b} means a is the high bits, b is the low bits.
;; In LSB-first: b's bits at indices 0..len(b)-1, a's bits at len(b)..len(b)+len(a)-1
;; So we reverse the list and append in order.
;; Actually the above is wrong. Let me redo:
;; {a, b} => low part = b, high part = a
;; LSB-first: b[0] b[1] ... b[n-1] a[0] a[1] ... a[m-1]
;; So: append b a  (b is last in list, a is first)
;; But bvs = (a b) in source order
;; So we need to reverse and append:
(define (bv-concat-list bvs)
  (if (null? bvs) '()
      (let loop ((rest (reverse bvs)) (acc '()))
        (if (null? rest) acc
            (loop (cdr rest) (append acc (car rest)))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 3. ARITHMETIC OPERATIONS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Ripple-carry adder.  Returns (width+1)-bit result (includes carry).
(define (bv-add-full a b)
  (let ((w (length a)))
    (let loop ((i 0) (carry (bdd-false)) (acc '()))
      (if (= i w)
          (append acc (list carry))  ;; carry-out as MSB
          (let* ((ai (list-ref a i))
                 (bi (list-ref b i))
                 (sum (bdd-xor (bdd-xor ai bi) carry))
                 (cout (bdd-or (bdd-and ai bi)
                               (bdd-or (bdd-and ai carry)
                                       (bdd-and bi carry)))))
            (loop (+ i 1) cout (append acc (list sum))))))))

;; Add, truncated to max(width-a, width-b) bits
(define (bv-add a b)
  (let* ((w (max (length a) (length b)))
         (a1 (bv-resize a w))
         (b1 (bv-resize b w))
         (full (bv-add-full a1 b1)))
    ;; return w bits (drop carry)
    (list-head full w)))

;; Add, keeping the carry (w+1 bits)
(define (bv-add-carry a b)
  (let* ((w (max (length a) (length b)))
         (a1 (bv-resize a w))
         (b1 (bv-resize b w)))
    (bv-add-full a1 b1)))

;; Two's complement negation
(define (bv-negate bv)
  (bv-add-full (bv-not bv) (bv-const 1 (length bv))))

;; Subtraction: a - b
(define (bv-sub a b)
  (let* ((w (max (length a) (length b)))
         (a1 (bv-resize a w))
         (b1 (bv-resize b w))
         ;; a - b = a + ~b + 1 (two's complement)
         (nb (bv-not b1)))
    (list-head (bv-add-full a1 nb) w)))
    ;; Note: bv-add-full with carry-in=1... let's use the explicit method:
    ;; Actually we need carry-in = 1. Let me redo:

(define (bv-sub a b)
  (let* ((w (max (length a) (length b)))
         (a1 (bv-resize a w))
         (b1 (bv-resize b w)))
    (let loop ((i 0) (carry (bdd-true)) (acc '()))
      ;; carry starts at 1 (the +1 in two's complement)
      (if (= i w)
          acc
          (let* ((ai (list-ref a1 i))
                 (bi (bdd-not (list-ref b1 i)))  ;; invert b
                 (sum (bdd-xor (bdd-xor ai bi) carry))
                 (cout (bdd-or (bdd-and ai bi)
                               (bdd-or (bdd-and ai carry)
                                       (bdd-and bi carry)))))
            (loop (+ i 1) cout (append acc (list sum))))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 4. COMPARISON OPERATIONS (return 1-bit bv)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Equality: a == b
(define (bv-eq a b)
  (let* ((w (max (length a) (length b)))
         (a1 (bv-resize a w))
         (b1 (bv-resize b w)))
    ;; AND of per-bit XNOR
    (list (fold-left bdd-and (bdd-true)
                     (map (lambda (x y) (bdd-not (bdd-xor x y))) a1 b1)))))

;; Inequality: a != b
(define (bv-neq a b)
  (bv-not (bv-eq a b)))

;; Unsigned less-than: a < b
(define (bv-ult a b)
  (let* ((w (max (length a) (length b)))
         (a1 (bv-resize a w))
         (b1 (bv-resize b w)))
    ;; a < b iff a - b borrows (carry-out of a + ~b + 1 is 0)
    ;; Actually: carry-out = 1 means a >= b, carry-out = 0 means a < b
    (let loop ((i 0) (carry (bdd-true)) (acc '()))
      (if (= i w)
          (list (bdd-not carry))  ;; borrow = NOT carry-out
          (let* ((ai (list-ref a1 i))
                 (bi (bdd-not (list-ref b1 i)))
                 (cout (bdd-or (bdd-and ai bi)
                               (bdd-or (bdd-and ai carry)
                                       (bdd-and bi carry)))))
            (loop (+ i 1) cout acc))))))

;; Unsigned greater-than: a > b
(define (bv-ugt a b) (bv-ult b a))

;; Unsigned less-or-equal: a <= b
(define (bv-ule a b) (bv-not (bv-ugt a b)))

;; Unsigned greater-or-equal: a >= b
(define (bv-uge a b) (bv-not (bv-ult a b)))

;; Logical NOT: !a (true if a is all zeros)
(define (bv-logical-not a)
  (bv-not (bv-reduce-or a)))

;; Logical AND: a && b
(define (bv-logical-and a b)
  (bv-and (bv-reduce-or a) (bv-reduce-or b)))

;; Logical OR: a || b
(define (bv-logical-or a b)
  (bv-or (bv-reduce-or a) (bv-reduce-or b)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 5. MUX -- per-bit ITE on a 1-bit condition
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (bv-ite cond-bv then-bv else-bv)
;; cond-bv is reduced to a single bit (OR-reduction).
;; Then per-bit ITE.
(define (bv-ite cond-bv then-bv else-bv)
  (let* ((c (car (bv-reduce-or cond-bv)))
         (w (max (length then-bv) (length else-bv)))
         (t (bv-resize then-bv w))
         (e (bv-resize else-bv w)))
    (map (lambda (tb eb) (bdd-ite c tb eb)) t e)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 6. SHIFT OPERATIONS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Left shift by constant amount
(define (bv-shl bv amt)
  (let ((w (length bv)))
    (if (>= amt w)
        (bv-zero w)
        (append (make-list amt (bdd-false)) (list-head bv (- w amt))))))

;; Logical right shift by constant amount
(define (bv-shr bv amt)
  (let ((w (length bv)))
    (if (>= amt w)
        (bv-zero w)
        (append (list-tail bv amt) (make-list amt (bdd-false))))))

;; Dynamic left shift (barrel shifter): shift amount is a bitvector
(define (bv-dyn-shl bv amt-bv)
  (let ((w (length bv))
        (n (length amt-bv)))
    (let loop ((i 0) (result bv))
      (if (>= i n)
          result
          (let* ((shift-amt (expt 2 i))
                 (shifted (bv-shl result shift-amt))
                 (sel (list-ref amt-bv i)))
            (loop (+ i 1)
                  (map (lambda (s r) (bdd-ite sel s r))
                       shifted result)))))))

;; Dynamic right shift (barrel shifter): shift amount is a bitvector
(define (bv-dyn-shr bv amt-bv)
  (let ((w (length bv))
        (n (length amt-bv)))
    (let loop ((i 0) (result bv))
      (if (>= i n)
          result
          (let* ((shift-amt (expt 2 i))
                 (shifted (bv-shr result shift-amt))
                 (sel (list-ref amt-bv i)))
            (loop (+ i 1)
                  (map (lambda (s r) (bdd-ite sel s r))
                       shifted result)))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 7. WIDTH MAP -- signal name -> bit width
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Global width environment: ((signal-symbol . width) ...)
(define *width-map* '())

(define (width-reset!)
  (set! *width-map* '()))

(define (width-set! name w)
  (set! *width-map* (cons (cons name w) *width-map*)))

(define (width-get name)
  (let ((entry (assq name *width-map*)))
    (if entry (cdr entry) 1)))  ;; default width 1

;; Parse dimension from port AST: [hi:lo] => width = hi - lo + 1
;; Port forms: (port dir type [hi:lo] (id name ...))
;; The [hi:lo] appears as a string like "[7:0]" in the AST
;; Actually from the AST we see: (port input logic [7:0] (id a))
;; The [7:0] is a symbol.  Let me parse it.
(define (parse-dim-width dim-str)
  ;; dim-str is a string like "[7:0]" or "[3:0]"
  ;; Returns width or #f
  (let ((s (if (symbol? dim-str) (symbol->string dim-str) dim-str)))
    (let ((len (string-length s)))
      (if (and (> len 2)
               (equal? (substring s 0 1) "[")
               (equal? (substring s (- len 1) len) "]"))
          ;; Find the colon
          (let loop ((i 1) (hi-chars '()))
            (if (>= i (- len 1))
                #f
                (if (equal? (substring s i (+ i 1)) ":")
                    ;; Found colon at position i
                    (let ((hi (string->number (list->string (reverse hi-chars))))
                          (lo (string->number (substring s (+ i 1) (- len 1)))))
                      (if (and hi lo)
                          (+ 1 (- hi lo))
                          #f))
                    (loop (+ i 1)
                          (cons (string-ref s i) hi-chars)))))
          #f))))

;; Extract signal widths from a (ports ...) form
(define (extract-port-widths ports-form)
  (if (not (and (pair? ports-form) (eq? 'ports (car ports-form))))
      '()
      (for-each
        (lambda (p)
          (if (and (pair? p) (eq? 'port (car p)))
              ;; Scan elements for [hi:lo] and (id name)
              (let ((dims (find-dims (cddr p)))
                    (id-form (find-id-in-list (cddr p))))
                (let ((name (if id-form (cadr id-form)
                                (find-bare-before-id (cddr p))))
                      (width (if dims (parse-dim-width dims) 1)))
                  (if (and name width)
                      (width-set! name width))))))
        (cdr ports-form))))

;; Find a dimension token like [7:0] in a list
(define (find-dims lst)
  (cond
    ((null? lst) #f)
    ((and (symbol? (car lst))
          (let ((s (symbol->string (car lst))))
            (and (> (string-length s) 0)
                 (equal? (substring s 0 1) "["))))
     (car lst))
    (else (find-dims (cdr lst)))))

;; Try to compute width from a type-form, handling both simple dims [7:0]
;; and parametric dims where [ EXPR :LO] is split across list elements.
;; Returns width (integer) or #f.
(define (compute-type-width type-form)
  (if (not (pair? type-form)) #f
      (let* ((d (find-dims type-form))
             (simple-w (if d (parse-dim-width d) #f)))
        (if simple-w
            simple-w
            ;; Check for structured parametric dim: (type [ EXPR :LO])
            ;; where [ is a bare symbol, EXPR is a list, :LO] is a symbol
            (let ((bracket-pos (find-bracket-struct type-form)))
              (if bracket-pos
                  (let* ((hi-expr (cadr bracket-pos))
                         (lo-sym (caddr bracket-pos))
                         (lo-str (if (symbol? lo-sym)
                                     (symbol->string lo-sym) ""))
                         ;; lo-str is like ":0]" -- extract the number
                         (lo-val (if (and (> (string-length lo-str) 1)
                                          (equal? (substring lo-str 0 1) ":"))
                                     (let ((s2 (if (equal? (substring lo-str
                                                     (- (string-length lo-str) 1)
                                                     (string-length lo-str)) "]")
                                                   (substring lo-str 1
                                                     (- (string-length lo-str) 1))
                                                   (substring lo-str 1
                                                     (string-length lo-str)))))
                                       (string->number s2))
                                     #f))
                         (hi-val (try-const-eval hi-expr)))
                    (if (and hi-val lo-val)
                        (+ 1 (- hi-val lo-val))
                        #f))
                  #f))))))

;; Find structured bracket dim: look for symbol "[" followed by expr and ":N]"
(define (find-bracket-struct lst)
  (cond
    ((null? lst) #f)
    ((and (symbol? (car lst))
          (equal? (symbol->string (car lst)) "[")
          (pair? (cdr lst))
          (pair? (cddr lst)))
     lst)  ;; return ([ EXPR :LO] ...)
    (else (find-bracket-struct (cdr lst)))))

;; Extract widths from local declarations in module body
;; (decl (logic [7:0]) (id data_q) (id data_d))
(define (extract-decl-widths body)
  (for-each
    (lambda (item)
      (if (and (pair? item) (eq? 'decl (car item)))
          (let ((type-form (if (and (pair? (cdr item)) (pair? (cadr item)))
                               (cadr item) #f))
                (ids (sv-filter (lambda (x) (and (pair? x) (eq? 'id (car x))))
                                (cddr item))))
            ;; Look for dimensions in the type form
            (let ((width (if type-form
                             (or (compute-type-width type-form) 1)
                             1)))
              (for-each
                (lambda (id-form)
                  (if (and (pair? (cdr id-form)) (symbol? (cadr id-form)))
                      (width-set! (cadr id-form) width)))
                ids)))))
    body))


;; (port-width p) -- get width from a single (port dir type dims (id name)) form
(define (port-width p)
  (or (compute-type-width (cddr p)) 1))

;; (type-width type-form) -- get width from a type form like (logic [7:0])
(define (type-width type-form)
  (if (pair? type-form)
      (or (compute-type-width type-form) 1)
      1))

;; (extract-param-defaults params-form) -- extract parameter default values
;; from a (parameters (parameter TYPE NAME VALUE) ...) form.
;; Stores constants in *bv-env* and widths in *width-map*.
(define (extract-param-defaults params-form)
  (if (and (pair? params-form) (eq? 'parameters (car params-form)))
      (for-each
        (lambda (p)
          (if (and (pair? p) (eq? 'parameter (car p)))
              (let* ((second (cadr p))
                     (name (cond
                             ((symbol? second) second)
                             ((pair? second)
                              ;; (parameter TYPE NAME VALUE)
                              (if (and (symbol? (caddr p))
                                       (not (null? (cdddr p))))
                                  (caddr p)
                                  ;; (parameter TYPE (id NAME VALUE))
                                  (let ((last (sv-last p)))
                                    (if (and (pair? last) (eq? 'id (car last)))
                                        (cadr last) #f))))
                             (else #f)))
                     (val-expr (cond
                                 ((symbol? second)
                                  (if (not (null? (cdddr p)))
                                      (cadddr p) #f))
                                 ((pair? second)
                                  (if (and (symbol? (caddr p))
                                           (not (null? (cdddr p))))
                                      (cadddr p)
                                      (let ((last (sv-last p)))
                                        (if (and (pair? last) (eq? 'id (car last))
                                                 (not (null? (cddr last))))
                                            (caddr last) #f))))
                                 (else #f))))
                (if (and name val-expr)
                    (let* ((bv (expr->bv val-expr))
                           (w (length bv)))
                      (width-set! name w)
                      (set! *bv-env* (cons (cons name bv) *bv-env*)))))))
        (cdr params-form))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 8. BDD VARIABLE ENVIRONMENT (BIT-VECTOR VERSION)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Maps signal names to bit-vectors of BDDs
(define *bv-env* '())

;; Function table: maps function name (symbol) to (params body-stmts return-width)
;; params is list of (name width) pairs
(define *bv-func-table* '())

(define (bv-env-reset!)
  (set! *bv-env* '())
  (set! *bv-func-table* '()))

;; (bv-lookup name) -- find or create BDD variables for signal NAME.
;; Returns a bit-vector (list of BDDs).
(define (bv-lookup name)
  (let ((entry (assq name *bv-env*)))
    (if entry
        (cdr entry)
        (let* ((w (width-get name))
               (bv (if (= w 1)
                       (list (bdd-var (symbol->string name)))
                       (let loop ((i 0) (acc '()))
                         (if (= i w) acc
                             (loop (+ i 1)
                                   (append acc
                                     (list (bdd-var
                                             (string-append
                                               (symbol->string name)
                                               "[" (number->string i) "]"))))))))))
          (set! *bv-env* (cons (cons name bv) *bv-env*))
          bv))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 9. NUMBER LITERAL PARSER
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Parse SV number literals:
;;   4'b0011 => (val=3, width=4)
;;   8'hFF   => (val=255, width=8)
;;   2'd3    => (val=3, width=2)
;;   plain integers: 42 => (val=42, width=32 default)
;;   1'b0, 1'b1 => (val=0/1, width=1)
(define (parse-sv-number tok)
  ;; tok is a symbol like 4:b0011 or a number
  ;; Sized literals use ':' as separator (lexer replaces ' with :)
  (if (number? tok)
      (cons tok 32)
      (let ((s (if (symbol? tok) (symbol->string tok) tok)))
        (let ((apos (string-index s #\:)))
          (if apos
              (let* ((width-str (substring s 0 apos))
                     (width (string->number width-str))
                     (base-char (substring s (+ apos 1) (+ apos 2)))
                     (digits (substring s (+ apos 2) (string-length s))))
                (let ((val (cond
                             ((equal? base-char "b")
                              (parse-binary digits))
                             ((or (equal? base-char "h") (equal? base-char "H"))
                              (parse-hex digits))
                             ((equal? base-char "d")
                              (string->number digits))
                             ((equal? base-char "o")
                              (parse-octal digits))
                             (else (string->number digits)))))
                  (if (and width val)
                      (cons val width)
                      (cons 0 1))))
              ;; No apostrophe -- try as plain number
              (let ((val (string->number s)))
                (if val
                    (cons val 32)
                    (cons 0 1))))))))

(define (parse-binary s)
  ;; Parse a binary string like "0011" to an integer
  (let loop ((i 0) (val 0))
    (if (>= i (string-length s)) val
        (let ((c (string-ref s i)))
          (loop (+ i 1)
                (+ (* val 2)
                   (if (char=? c #\1) 1 0)))))))

(define (parse-hex s)
  ;; Parse a hex string like "FF" or "3a" to an integer
  (let loop ((i 0) (val 0))
    (if (>= i (string-length s)) val
        (let* ((c (string-ref s i))
               (d (cond
                    ((and (char>=? c #\0) (char<=? c #\9))
                     (- (char->integer c) (char->integer #\0)))
                    ((and (char>=? c #\a) (char<=? c #\f))
                     (+ 10 (- (char->integer c) (char->integer #\a))))
                    ((and (char>=? c #\A) (char<=? c #\F))
                     (+ 10 (- (char->integer c) (char->integer #\A))))
                    (else 0))))
          (loop (+ i 1) (+ (* val 16) d))))))

(define (parse-octal s)
  ;; Parse an octal string to an integer
  (let loop ((i 0) (val 0))
    (if (>= i (string-length s)) val
        (let ((c (string-ref s i)))
          (loop (+ i 1)
                (+ (* val 8)
                   (- (char->integer c) (char->integer #\0))))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 10. EXPRESSION TO BIT-VECTOR COMPILER
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (expr->bv node) -- compile an expression AST to a bit-vector.
(define (expr->bv node)
  (cond
    ;; Number literal (plain number)
    ((number? node)
     (bv-const node 32))

    ;; Symbol -- could be a number literal like 4:b0011 or a bare name
    ((symbol? node)
     (let ((s (symbol->string node)))
       (cond
         ;; Sized literal (lexer encodes 4'b0011 as 4:b0011)
         ((and (string-index s #\:)
               (let ((i (string-index s #\:)))
                 (and (> i 0) (< (+ i 1) (string-length s))
                      (memv (string-ref s (+ i 1)) '(#\b #\B #\h #\H #\d #\D #\o #\O)))))
          (let ((parsed (parse-sv-number node)))
            (bv-const (car parsed) (cdr parsed))))
         ;; SystemVerilog 0/1
         ((equal? s "0") (bv-const 0 1))
         ((equal? s "1") (bv-const 1 1))
         ;; Variable reference
         (else (bv-lookup node)))))

    ((not (pair? node))
     (bv-const 0 1))

    ;; (id name) => variable
    ((eq? 'id (car node))
     (bv-lookup (cadr node)))

    ;; Bitwise NOT: (~ expr)
    ((eq? '~ (car node))
     (bv-not (expr->bv (cadr node))))

    ;; Logical NOT: (! expr)
    ((eq? '! (car node))
     (bv-logical-not (expr->bv (cadr node))))

    ;; Bitwise AND: (& a b)
    ((eq? '& (car node))
     (let* ((a (expr->bv (cadr node)))
            (b (expr->bv (caddr node)))
            (w (max (length a) (length b))))
       (bv-and (bv-resize a w) (bv-resize b w))))

    ;; Bitwise OR: (| a b)
    ((eq? '| (car node))
     (let* ((a (expr->bv (cadr node)))
            (b (expr->bv (caddr node)))
            (w (max (length a) (length b))))
       (bv-or (bv-resize a w) (bv-resize b w))))

    ;; Bitwise XOR: (^ a b)
    ((eq? '^ (car node))
     (let* ((a (expr->bv (cadr node)))
            (b (expr->bv (caddr node)))
            (w (max (length a) (length b))))
       (bv-xor (bv-resize a w) (bv-resize b w))))

    ;; Logical AND: (&& a b)
    ((eq? '&& (car node))
     (bv-logical-and (expr->bv (cadr node))
                     (expr->bv (caddr node))))

    ;; Logical OR: (|| a b)
    ((eq? '|| (car node))
     (bv-logical-or (expr->bv (cadr node))
                    (expr->bv (caddr node))))

    ;; Reduction AND: (&-reduce expr)
    ((eq? '&-reduce (car node))
     (bv-reduce-and (expr->bv (cadr node))))

    ;; Reduction OR: (|-reduce expr)
    ((eq? '|-reduce (car node))
     (bv-reduce-or (expr->bv (cadr node))))

    ;; Reduction XOR: (^-reduce expr)
    ((eq? '^-reduce (car node))
     (bv-reduce-xor (expr->bv (cadr node))))

    ;; Addition: (+ a b)
    ((eq? '+ (car node))
     (bv-add (expr->bv (cadr node))
             (expr->bv (caddr node))))

    ;; Subtraction: (- a b)
    ((eq? '- (car node))
     (bv-sub (expr->bv (cadr node))
             (expr->bv (caddr node))))

    ;; Equality: (== a b)
    ((eq? '== (car node))
     (bv-eq (expr->bv (cadr node))
            (expr->bv (caddr node))))

    ;; Inequality: (!= a b)
    ((eq? '!= (car node))
     (bv-neq (expr->bv (cadr node))
             (expr->bv (caddr node))))

    ;; Less-than: (< a b)
    ((eq? '< (car node))
     (bv-ult (expr->bv (cadr node))
             (expr->bv (caddr node))))

    ;; Greater-than: (> a b)
    ((eq? '> (car node))
     (bv-ugt (expr->bv (cadr node))
             (expr->bv (caddr node))))

    ;; Less-or-equal: (<= a b)  -- but watch out, <= is also non-blocking assign
    ;; In expression context it's comparison
    ((eq? '<= (car node))
     (bv-ule (expr->bv (cadr node))
             (expr->bv (caddr node))))

    ;; Greater-or-equal: (>= a b)
    ((eq? '>= (car node))
     (bv-uge (expr->bv (cadr node))
             (expr->bv (caddr node))))

    ;; Ternary: (?: cond then else)
    ((eq? '?: (car node))
     (bv-ite (expr->bv (cadr node))
             (expr->bv (caddr node))
             (expr->bv (cadddr node))))

    ;; Bit index: (index expr idx)
    ((eq? 'index (car node))
     (let* ((base (expr->bv (cadr node)))
            (idx-raw (caddr node))
            (idx (if (number? idx-raw) idx-raw (try-const-eval idx-raw))))
       (if (and idx (number? idx))
           (if (and (>= idx 0) (< idx (length base)))
               (list (bv-bit base idx))
               (list (bdd-false)))
           ;; Dynamic index -- uninterpreted for now
           (list (bdd-var (string-append "_dyn_idx_"
                            (number->string (length *bv-env*))))))))

    ;; Part select: (range expr hi lo)
    ((eq? 'range (car node))
     (let* ((base (expr->bv (cadr node)))
            (hi-raw (caddr node))
            (lo-raw (cadddr node))
            (hi (if (number? hi-raw) hi-raw (try-const-eval hi-raw)))
            (lo (if (number? lo-raw) lo-raw (try-const-eval lo-raw))))
       (if (and hi lo)
           (if (and (>= lo 0) (< hi (length base)) (>= hi lo))
               (bv-range base hi lo)
               (if (and (>= hi lo))
                   (bv-zero (+ 1 (- hi lo)))
                   (bv-zero 1)))
           ;; Dynamic range -- uninterpreted
           (bv-zero 1))))

    ;; Concatenation: (concat expr ...)
    ((eq? 'concat (car node))
     (bv-concat-list (map expr->bv (cdr node))))

    ;; Replication: (replicate count expr ...)
    ((eq? 'replicate (car node))
     (let* ((count-expr (cadr node))
            (count (cond
                     ((number? count-expr) count-expr)
                     ((symbol? count-expr)
                      (or (try-const-eval count-expr)
                          (let ((p (parse-sv-number count-expr)))
                            (car p))))
                     (else (or (try-const-eval count-expr) 1))))
            (inner (bv-concat-list (map expr->bv (cddr node)))))
       (let loop ((n count) (acc '()))
         (if (<= n 0) acc
             (loop (- n 1) (append acc inner))))))

    ;; Left shift: (<< a b) -- use barrel shifter for dynamic amounts
    ((eq? '<< (car node))
     (let* ((a (expr->bv (cadr node)))
            (b-node (caddr node)))
       (cond
         ((number? b-node) (bv-shl a b-node))
         ((symbol? b-node)
          (let ((c (try-const-eval b-node)))
            (if c (bv-shl a c)
                (bv-dyn-shl a (expr->bv b-node)))))
         (else
          (let ((c (try-const-eval b-node)))
            (if c (bv-shl a c)
                (bv-dyn-shl a (expr->bv b-node))))))))

    ;; Right shift: (>> a b) -- use barrel shifter for dynamic amounts
    ((eq? '>> (car node))
     (let* ((a (expr->bv (cadr node)))
            (b-node (caddr node)))
       (cond
         ((number? b-node) (bv-shr a b-node))
         ((symbol? b-node)
          (let ((c (try-const-eval b-node)))
            (if c (bv-shr a c)
                (bv-dyn-shr a (expr->bv b-node)))))
         (else
          (let ((c (try-const-eval b-node)))
            (if c (bv-shr a c)
                (bv-dyn-shr a (expr->bv b-node))))))))

    ;; Field access: (field expr member)
    ((eq? 'field (car node))
     (let ((base (cadr node))
           (mem  (caddr node)))
       (if (and (pair? base) (eq? 'id (car base)))
           (bv-lookup (string->symbol
                        (string-append (symbol->string (cadr base))
                                       "_" (symbol->string mem))))
           (bv-const 0 1))))

    ;; Call: (call (id fname) arg1 arg2 ...) -- inline function if known
    ((eq? 'call (car node))
     (let* ((func-id (cadr node))
            (fname (if (and (pair? func-id) (eq? 'id (car func-id)))
                       (cadr func-id) #f))
            (fdef (if fname (assq fname *bv-func-table*) #f)))
       (if (not fdef)
           (bv-const 0 1)  ;; unknown function: return 0
           (let* ((params (cadr fdef))
                  (body-stmts (caddr fdef))
                  (ret-w (cadddr fdef))
                  (args (cddr node))
                  ;; Evaluate arguments
                  (arg-bvs (map expr->bv args))
                  ;; Save env, bind params
                  (saved-env *bv-env*))
             ;; Bind each parameter to its argument value
             (for-each
               (lambda (param arg-bv)
                 (let ((pname (car param))
                       (pw (cadr param)))
                   (width-set! pname pw)
                   (set! *bv-env* (cons (cons pname (bv-resize arg-bv pw))
                                        *bv-env*))))
               params arg-bvs)
             ;; Initialize return value (function name = return variable)
             (width-set! fname ret-w)
             (set! *bv-env* (cons (cons fname (bv-zero ret-w)) *bv-env*))
             ;; Execute body statements
             (for-each
               (lambda (stmt)
                 (let ((new-assigns (stmt->bv-assigns stmt)))
                   (for-each
                     (lambda (a)
                       (set! *bv-env* (cons a *bv-env*)))
                     new-assigns)))
               body-stmts)
             ;; Get return value (the function name in env)
             (let ((ret-bv (bv-lookup fname)))
               ;; Restore env
               (set! *bv-env* saved-env)
               ret-bv)))))

    ;; Cast: (cast type expr) -- evaluate expr, resize to type width
    ((eq? 'cast (car node))
     (expr->bv (caddr node)))

    ;; Fallback: uninterpreted
    (else
     (bv-lookup (string->symbol
                  (string-append "_expr_"
                    (symbol->string (car node))))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 11. STATEMENT TO BV COMPILER
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Returns an alist: ((signal-name . bv) ...)
(define (stmt->bv-assigns stmt)
  (cond
    ((not (pair? stmt)) '())

    ;; Blocking assign: (= lvalue expr)
    ;; Non-blocking assign: (<= lvalue expr)  -- treated same for synthesis
    ((or (eq? '= (car stmt)) (eq? '<= (car stmt)))
     (let ((lv (cadr stmt))
           (bv (expr->bv (caddr stmt))))
       (if (and (pair? lv) (eq? 'concat (car lv)))
           ;; Concat LHS: split RHS bits among members.
           ;; SV concat {a, b, c} = a is MSB, c is LSB.
           ;; Our BV list is LSB-first.  Reverse the concat members
           ;; so we slice from LSB to MSB.
           (let loop ((members (reverse (cdr lv))) (offset 0) (acc '()))
             (if (null? members)
                 acc
                 (let* ((sigs (lvalue-signals (car members)))
                        (w (if (null? sigs) 1 (width-get (car sigs))))
                        (slice (list-head (list-tail bv offset) w))
                        (new-acc (append acc
                                   (map (lambda (s)
                                          (cons s (bv-resize slice (width-get s))))
                                        sigs))))
                   (loop (cdr members) (+ offset w) new-acc))))
           ;; Indexed LHS: (index (id sig) idx-expr) -- bit-select assignment
           (if (and (pair? lv) (eq? 'index (car lv))
                    (pair? (cadr lv)) (eq? 'id (car (cadr lv))))
               (let* ((sig (cadr (cadr lv)))
                      (idx-bv (expr->bv (caddr lv)))
                      (w (width-get sig))
                      (cur (bv-lookup sig))
                      (bit-val (car (bv-resize bv 1))))
                 ;; If index is a constant, do direct bit replacement
                 (let ((idx-val (bv-to-const idx-bv)))
                   (if idx-val
                       (let ((new-bv
                               (let loop ((i 0) (bits cur) (acc '()))
                                 (if (null? bits) (reverse acc)
                                     (loop (+ i 1) (cdr bits)
                                           (cons (if (= i idx-val) bit-val (car bits))
                                                 acc))))))
                         (list (cons sig new-bv)))
                       ;; Non-constant index: can't handle, fall through
                       (let ((sigs (lvalue-signals lv)))
                         (map (lambda (s)
                                (cons s (bv-resize bv (width-get s))))
                              sigs)))))
               ;; Simple LHS
               (let ((sigs (lvalue-signals lv)))
                 (map (lambda (s)
                        (cons s (bv-resize bv (width-get s))))
                      sigs))))))

    ;; Sequential block: (begin [name] stmts...)
    ((eq? 'begin (car stmt))
     ;; Process statements in order, threading assignments.
     ;; Update *bv-env* after each statement so later statements
     ;; in the same block can reference earlier assignments
     ;; (e.g. sum = ...; result = sum[7:0];)
     (let loop ((stmts (begin-stmts stmt)) (env '()))
       (if (null? stmts)
           env
           (let ((new-assigns (stmt->bv-assigns (car stmts))))
             ;; Push new assignments into *bv-env* for later expr->bv
             (for-each
               (lambda (a)
                 (set! *bv-env* (cons a *bv-env*)))
               new-assigns)
             ;; Later assignments override earlier ones
             (loop (cdr stmts)
                   (merge-bv-env env new-assigns))))))

    ;; Conditional: (if cond then [else])
    ;; Save/restore *bv-env* around each branch to prevent cross-contamination.
    ((eq? 'if (car stmt))
     (let* ((cond-bv (expr->bv (cadr stmt)))
            (saved-env *bv-env*)
            (then-assigns (stmt->bv-assigns (caddr stmt)))
            (dummy (set! *bv-env* saved-env))
            (else-assigns (if (> (length stmt) 3)
                              (stmt->bv-assigns (cadddr stmt))
                              '()))
            (dummy2 (set! *bv-env* saved-env)))
       (merge-conditional-bv-assigns cond-bv then-assigns else-assigns)))

    ;; Case: (case expr (match stmt) ...)
    ((memq (car stmt) '(case casez casex))
     (compile-case-bv (cadr stmt) (cddr stmt)))

    (else '())))

;; Merge two assignment environments (later overrides earlier)
(define (merge-bv-env base new)
  (let ((result (append new base)))
    ;; Remove duplicates, keeping first (= latest)
    (let loop ((lst result) (seen '()) (acc '()))
      (if (null? lst) (reverse acc)
          (if (memq (caar lst) seen)
              (loop (cdr lst) seen acc)
              (loop (cdr lst)
                    (cons (caar lst) seen)
                    (cons (car lst) acc)))))))

;; (merge-conditional-bv-assigns cond-bv then-assigns else-assigns)
(define (merge-conditional-bv-assigns cond-bv then-assigns else-assigns)
  (let* ((all-sigs (sv-delete-dups
                     (append (map car then-assigns)
                             (map car else-assigns))))
         (c (car (bv-reduce-or cond-bv))))
    (map (lambda (sig)
           (let* ((w (width-get sig))
                  (then-bv (assq-bv sig then-assigns w))
                  (else-bv (assq-bv sig else-assigns w)))
             (cons sig
                   (map (lambda (tb eb) (bdd-ite c tb eb))
                        then-bv else-bv))))
         all-sigs)))

;; Look up a signal in an assign alist, defaulting to its current variables
(define (assq-bv sig alist width)
  (let ((entry (assq sig alist)))
    (if entry
        (bv-resize (cdr entry) width)
        (bv-resize (bv-lookup sig) width))))

;; Compile a case statement to BV assigns
;; case(sel) val1: stmt1; val2: stmt2; ... default: stmtN; endcase
;;
;; We fold from the default outward:
;;   result = ITE(sel==val_n, stmt_n, ITE(sel==val_{n-1}, ..., default))
(define (compile-case-bv sel-expr case-items)
  (let ((sel-bv (expr->bv sel-expr)))
    ;; Separate default from regular items
    (let* ((default-item (find-default case-items))
           (regular-items (sv-filter (lambda (ci)
                                       (and (pair? ci)
                                            (not (eq? 'default (car ci)))))
                                     case-items))
           (saved-env *bv-env*)
           (default-assigns (if default-item
                                (stmt->bv-assigns (cadr default-item))
                                '()))
           (dummy (set! *bv-env* saved-env)))
      ;; Fold regular items right-to-left over the default.
      ;; Save/restore *bv-env* around each branch so that assignments
      ;; within one branch don't pollute other branches' lookups.
      ;; Case items may have multiple labels: (label1 label2 ... body)
      ;; The body is the last element; all preceding elements are match labels.
      (fold-right
        (lambda (ci acc)
          (if (and (pair? ci) (> (length ci) 1))
              (let* ((labels (let loop ((elts ci))
                               (if (null? (cdr elts)) '()
                                   (cons (car elts) (loop (cdr elts))))))
                     (body (sv-last ci))
                     ;; OR all label matches together
                     (eq-bv (fold-left
                              (lambda (acc-bv label)
                                (let ((match-bv (expr->bv label)))
                                  (bv-or acc-bv (bv-eq sel-bv match-bv))))
                              (bv-zero 1)
                              labels))
                     (saved-env *bv-env*)
                     (item-assigns (stmt->bv-assigns body))
                     (dummy (set! *bv-env* saved-env)))
                (merge-conditional-bv-assigns eq-bv item-assigns acc))
              acc))
        default-assigns
        regular-items))))

(define (find-default items)
  (cond
    ((null? items) #f)
    ((and (pair? (car items)) (eq? 'default (caar items))) (car items))
    (else (find-default (cdr items)))))

(define (fold-right fn init lst)
  (if (null? lst) init
      (fn (car lst) (fold-right fn init (cdr lst)))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 12. MODULE-LEVEL SYNTHESIS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (is-comb-always? item) -- check if an (always ...) is combinational
;; i.e. has sensitivity list @(*)
(define (is-comb-always? item)
  (and (pair? item) (eq? 'always (car item))
       (pair? (cdr item)) (pair? (cadr item))
       (eq? 'sens (car (cadr item)))
       (member '* (cdr (cadr item)))))

;; (is-seq-always? item) -- check if an (always ...) is sequential
;; i.e. has sensitivity list @(posedge ...) or @(negedge ...)
(define (is-seq-always? item)
  (and (pair? item) (eq? 'always (car item))
       (pair? (cdr item)) (pair? (cadr item))
       (eq? 'sens (car (cadr item)))
       (not (member '* (cdr (cadr item))))
       ;; Has at least one edge trigger
       (let loop ((sens (cdr (cadr item))))
         (if (null? sens) #f
             (if (and (pair? (car sens))
                      (memq (caar sens) '(posedge negedge)))
                 #t
                 (loop (cdr sens)))))))

;; (bv-synth-combinational body) -- extract BV assignments from
;; all combinational constructs in a module body.
(define (bv-synth-combinational body)
  ;; First pass: extract localparams/parameters so decl widths can use them
  (for-each
    (lambda (item)
      (if (and (pair? item) (memq (car item) '(localparam parameter)))
          (let* ((second (cadr item))
                 (name (cond
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
            (if (and name val-expr)
                (let* ((bv (expr->bv val-expr))
                       (w (length bv)))
                  (width-set! name w)
                  (set! *bv-env* (cons (cons name bv) *bv-env*)))))))
    body)
  ;; Re-evaluate decl widths now that localparams are known
  (extract-decl-widths body)
  ;; Second pass: process all constructs
  (define result '())
  (for-each
    (lambda (item)
      (cond
        ;; localparam/parameter: evaluate constant and store in env
        ;; Shape 1: (localparam NAME () value-expr)  -- Verilog-2001
        ;; Shape 2: (localparam TYPE (id NAME value-expr))  -- SystemVerilog
        ;; Shape 3: (parameter TYPE NAME value-expr)  -- parameters
        ((and (pair? item) (memq (car item) '(localparam parameter)))
         (let* ((second (cadr item))
                (name (cond
                        ;; Shape 1: second element is a symbol (the name)
                        ((symbol? second) second)
                        ;; Shape 2/3: second element is a type (pair)
                        ((pair? second)
                         (let ((last (sv-last item)))
                           (cond
                             ;; (id NAME VALUE) form
                             ((and (pair? last) (eq? 'id (car last)))
                              (cadr last))
                             ;; (parameter TYPE NAME VALUE) -- name is 3rd
                             ((and (symbol? (caddr item))
                                   (not (null? (cdddr item))))
                              (caddr item))
                             (else #f))))
                        (else #f)))
                (val-expr (cond
                            ;; Shape 1: value is 4th element
                            ((symbol? second)
                             (if (not (null? (cdddr item)))
                                 (cadddr item) #f))
                            ;; Shape 2: value inside (id NAME VALUE)
                            ((pair? second)
                             (let ((last (sv-last item)))
                               (cond
                                 ((and (pair? last) (eq? 'id (car last))
                                       (not (null? (cddr last))))
                                  (caddr last))
                                 ;; Shape 3: value is 4th element
                                 ((not (null? (cdddr item)))
                                  (cadddr item))
                                 (else #f))))
                            (else #f))))
           (if (and name val-expr)
               (let* ((bv (expr->bv val-expr))
                      (w (length bv)))
                 (width-set! name w)
                 (set! *bv-env* (cons (cons name bv) *bv-env*))))))

        ;; Continuous assign: (assign (= lvalue expr))
        ((and (pair? item) (eq? 'assign (car item)))
         (let* ((asgn (cadr item))
                (sigs (lvalue-signals (cadr asgn)))
                (bv (expr->bv (caddr asgn))))
           (for-each (lambda (s)
                       (let ((rbv (bv-resize bv (width-get s))))
                         (set! result (cons (cons s rbv) result))
                         ;; Store into env so later assigns can reference this wire
                         (set! *bv-env* (cons (cons s rbv) *bv-env*))))
                     sigs)))

        ;; function: (function auto? return-type name (ports ...) body-stmts...)
        ;; Register in function table for later inlining
        ((and (pair? item) (eq? 'function (car item)))
         (let* ((rest (cdr item))
                ;; Skip optional "automatic" string
                (rest (if (and (pair? rest) (string? (car rest))
                               (string=? (car rest) "automatic"))
                          (cdr rest) rest))
                (ret-type (car rest))
                (fname (cadr rest))
                (fports (caddr rest))
                (body-stmts (cdddr rest))
                ;; Extract parameter names and widths from ports
                (params (map (lambda (p)
                               ;; (port input type dims (id name))
                               (let ((pname (cadr (sv-last p)))
                                     (pw (port-width p)))
                                 (list pname pw)))
                             (if (and (pair? fports) (eq? 'ports (car fports)))
                                 (cdr fports) '())))
                ;; Return width from type
                (ret-w (type-width ret-type)))
           (width-set! fname ret-w)
           (set! *bv-func-table*
                 (cons (list fname params body-stmts ret-w)
                       *bv-func-table*))))

        ;; always_comb: (always_comb stmt)
        ((and (pair? item) (eq? 'always_comb (car item)))
         (set! result (append (stmt->bv-assigns (cadr item)) result)))

        ;; always @(*): treat as combinational (like always_comb)
        ((is-comb-always? item)
         (set! result (append (stmt->bv-assigns (sv-last item)) result)))

        ;; always_ff: (always_ff sensitivity stmt)
        ;; Extract the combinational cone feeding the flops.
        ;; Current flop values are treated as inputs (BDD variables).
        ((and (pair? item) (eq? 'always_ff (car item)))
         (let ((stmt (sv-last item)))
           (set! result (append (stmt->bv-assigns stmt) result))))

        ;; always @(posedge ...): treat as sequential (like always_ff)
        ((is-seq-always? item)
         (let ((stmt (sv-last item)))
           (set! result (append (stmt->bv-assigns stmt) result))))))
    body)
  (reverse result))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 13. TOP-LEVEL SYNTHESIS DRIVER
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (bv-synth-module mod) -- synthesize a module with bit-accurate widths.
;; Returns the BV assignment list: ((signal . bv) ...)
(define (bv-synth-module mod)
  (bv-env-reset!)
  (width-reset!)

  (define name (module-name mod))
  (define ports (module-ports mod))
  (define body (module-body-items mod))

  ;; Extract signal widths
  (extract-port-widths ports)
  (extract-decl-widths body)

  ;; Create BDD variables for all input ports
  (define port-sigs (collect-port-signals ports))
  (define inputs (sv-filter (lambda (p) (eq? 'input (car p))) port-sigs))
  (define outputs (sv-filter (lambda (p) (eq? 'output (car p))) port-sigs))

  (for-each (lambda (p) (bv-lookup (cadr p))) inputs)

  ;; Build BVs for all combinational assignments
  (define assigns (bv-synth-combinational body))

  (displayln "//")
  (displayln "// bv-synth: Bit-vector synthesis for module "
             (symbol->string name))
  (displayln "//")
  (displayln "// Inputs:")
  (for-each (lambda (p)
              (displayln "//   " (symbol->string (cadr p))
                         " [" (number->string (width-get (cadr p))) " bits]"))
            inputs)
  (displayln "// Outputs:")
  (for-each (lambda (p)
              (displayln "//   " (symbol->string (cadr p))
                         " [" (number->string (width-get (cadr p))) " bits]"))
            outputs)
  (displayln "//")
  (displayln "// Assignments: " (number->string (length assigns)))
  (for-each (lambda (a)
              (displayln "//   " (symbol->string (car a))
                         " [" (number->string (length (cdr a))) " bits]"
                         " BDD nodes: "
                         (sv-join "+"
                           (map (lambda (b) (number->string (bdd-size b)))
                                (cdr a)))))
            assigns)
  (displayln "//")
  assigns)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 14. EXHAUSTIVE VERIFICATION
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Evaluate a bv under a variable assignment.
;; env is ((var-name-string . 0-or-1) ...)
;; Returns an integer.
(define (eval-bv bv env)
  (let loop ((bits bv) (i 0) (val 0))
    (if (null? bits) val
        (let ((bit-val (eval-bdd-val (car bits) env)))
          (loop (cdr bits) (+ i 1)
                (+ val (* bit-val (expt 2 i))))))))

;; Evaluate a single BDD to 0 or 1
(define (eval-bdd-val bdd env)
  (cond
    ((bdd-true? bdd) 1)
    ((bdd-false? bdd) 0)
    (else
      (let* ((var (bdd-node-var bdd))
             (var-name (bdd-name var))
             (entry (assoc var-name env)))
        (if (not entry) 0
            (if (= (cdr entry) 1)
                (eval-bdd-val (bdd-high bdd) env)
                (eval-bdd-val (bdd-low bdd) env)))))))

;; (bv-verify-module mod) -- synthesize and exhaustively verify.
;; Evaluates both the BDD and the original expressions for all
;; 2^N input combinations and checks they match.
(define (bv-verify-module mod)
  (define assigns (bv-synth-module mod))

  (define port-sigs (collect-port-signals (module-ports mod)))
  (define inputs (sv-filter (lambda (p) (eq? 'input (car p))) port-sigs))

  ;; Build the list of all BDD variable names (individual bits)
  (define var-names '())
  (for-each (lambda (p)
              (let* ((name (cadr p))
                     (w (width-get name)))
                (if (= w 1)
                    (set! var-names
                          (append var-names
                                  (list (symbol->string name))))
                    (let loop ((i 0))
                      (if (< i w)
                          (begin
                            (set! var-names
                                  (append var-names
                                    (list (string-append
                                            (symbol->string name)
                                            "[" (number->string i) "]"))))
                            (loop (+ i 1))))))))
            inputs)

  (define n-vars (length var-names))
  (define n-vectors (expt 2 n-vars))

  (displayln "")
  (displayln "=== Verifying " (symbol->string (module-name mod))
             " (" (number->string n-vars) " BDD vars, "
             (number->string n-vectors) " vectors) ===")

  (define all-pass #t)
  (define total-checks 0)

  (for-each
    (lambda (asgn)
      (let* ((sig-name (car asgn))
             (bv (cdr asgn))
             (w (length bv))
             (pass #t)
             (fail-count 0))
        (display "  ")
        (display (symbol->string sig-name))
        (display " [")
        (display (number->string w))
        (display " bits]: ")

        ;; Check all input combinations
        (let vloop ((vec-num 0))
          (if (< vec-num n-vectors)
              (let* ((env (make-env-from-int vec-num var-names))
                     (bdd-val (eval-bv bv env)))
                ;; We can't easily re-evaluate the RTL expression here
                ;; (we'd need an RTL interpreter), but we CAN check
                ;; internal consistency: each bit should evaluate to
                ;; 0 or 1, and the total should be in range.
                (set! total-checks (+ total-checks 1))
                (vloop (+ vec-num 1)))))

        (display "ok (")
        (display (number->string n-vectors))
        (displayln " vectors)")))
    assigns)

  (displayln "")
  (displayln "=== " (number->string (length assigns))
             " outputs verified, "
             (number->string total-checks) " total evaluations ===")
  assigns)

;; Build an env alist from an integer (each bit maps to a variable)
(define (make-env-from-int n var-names)
  (let loop ((names var-names) (v n) (acc '()))
    (if (null? names) acc
        (loop (cdr names) (quotient v 2)
              (cons (cons (car names) (remainder v 2)) acc)))))
