; Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information.
; SPDX-License-Identifier: Apache-2.0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; bigint.scm
;;
;; Integer arithmetic for the CSP compiler, using mscheme's native
;; exact integer tower (fixnum + GMP bignum).
;;
;; Previously wrapped BigInt.T; now uses native Scheme exact integers
;; with bitwise-and, bitwise-ior, bitwise-xor, bitwise-not,
;; arithmetic-shift, integer-length builtins from mscheme.
;;

(define (bigint-dbg . x)
;;    (apply dis x)
  )


;;
;; fundamental constants -- now plain exact integers
;;

(define *bigm1* -1)
(define *big0*   0)
(define *big1*   1)
(define *big2*   2)

(define (bigint? x)
  ;; test for exact integer
  (and (number? x) (exact? x)))

(define (force-bigint x)
  (cond ((null? x) x)
        ((and (number? x) (exact? x)) x)
        ((number? x) (inexact->exact (round x)))
        (else x)))

(define (make-big x)
  (cond ((null? x) (error "make-big of nil"))
        ((and (number? x) (exact? x)) x)
        ((number? x) (inexact->exact (round x)))
        (else (error "make-big: not a number: " x))))

(define (big<< x sa)
  (arithmetic-shift x sa))

(define (big>> x sa)
  (arithmetic-shift x (- sa)))

(define (dumb-binop-range op)
  (lambda (a b)
    (bigint-dbg "dumb-binop-range " op " " a " " b dnl)
    (let* ((all-pairs   (cartesian-product a b))
           (all-results (map eval (map (lambda(x)(cons op x)) all-pairs)))
           (min-res     (apply big-min all-results))
           (max-res     (apply big-max all-results)))
      (bigint-dbg "all-pairs   : " all-pairs dnl)
      (bigint-dbg "all-results : " all-results dnl)
      (bigint-dbg "min-res     : " min-res dnl)
      (bigint-dbg "max-res     : " max-res dnl)

      (list min-res max-res))))

(define (big-compare a b) (cond ((< a b) -1) ((> a b) 1) (else 0)))

(define big>  >)
(define big<  <)
(define big>= >=)
(define big<= <=)
(define big=  =)

(define big-neg?  negative?)
(define big-zero? zero?)

(define (big/ a b)
  (cond
   ((zero? b) 0) ;; weird CSP semantics for dbZ
   (else (quotient a b))))

(define (big% a b)
  (cond ((zero? b) 0) ;; more weird CSP semantics
        (else (remainder a b))))

(define (big** a b)
  (cond
   ((zero? a) 0) ;; covers 0**0 - weird CSP semantics
   (else (expt a b))))

(let () ;; don't pollute the global environment

  (define big+   +)
  (define big-   -)
  (define big*   *)
  (define big-min min)
  (define big-max max)
  (define big-pow expt)

  (define-global-symbol 'big+    big+)
  (define-global-symbol 'big-    big-)
  (define-global-symbol 'big*    big*)
  (define-global-symbol 'big-min big-min)
  (define-global-symbol 'big-max big-max)
  (define-global-symbol 'big-pow big-pow)

  ;; ops on finite ranges...
  (define-global-symbol 'frange+ (dumb-binop-range big+))
  (define-global-symbol 'frange- (dumb-binop-range big-))
  (define-global-symbol 'frange* (dumb-binop-range big*))
  (define-global-symbol 'frange/ (dumb-binop-range big/))

  )

(define big| bitwise-ior) ;; |)

(define big& bitwise-and)

(define big^ bitwise-xor)

(define (bigbits x a b)
  (let* ((w    (+ 1 (- b a)))
         (sx   (big>> x a))
         (mask (- (big<< 1 w) 1)))
    (big& sx mask)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; an extended number "xnum" is one of
;; 1. an exact integer
;; 2. -inf
;; 3. +inf
;; 4.  nan
;;
;; it is intended to represent any integer from the number line,
;; extended with +-inf and not-a-number.
;;
;; xnums are used in the interval arithmetic to determine the potential
;; range of values resulting from a particular arithmetic expression
;; in the source code
;;

;; the following defs allow us to (eval x) for any xnum x
(define +inf '+inf)
(define -inf '-inf)
(define nan  'nan)

(define *xnum-special-values* '(nan -inf +inf))

(define (make-xnum x)
  (cond ((and (number? x) (exact? x)) x)
        ((number? x) (inexact->exact (round x)))
        ((eq? '-inf x) x)
        ((eq? '+inf x) x)
        ((eq? 'nan  x) x)
        (else (error "make-xnum : not a legal xnum : " x)))
  )

(define (check-xnum x)
  (map (lambda(q)
         (if (not (or (and (number? x) (exact? x)) (member x '(-inf +inf nan))))
             (error "not an xnum : " x)))))

(define (xnum-infinite? x) (member x '(-inf +inf)))

(define (xnum-nan? x) (eq? 'nan x))

(define (xnum-finite? x) (and (not (xnum-nan?)) (not (xnum-infinite? x))))

(define (xnum-finites? lst) (apply and (map xnum-finite? lst)))

(define (xnum-compare a b)
  (check-xnum a)
  (check-xnum b)
  (cond ((eq? a b) 0)  ;; nan = nan
        ((eq? a '-inf) -1)
        ((eq? a '+inf) +1)
        ((eq? b '-inf) +1)
        ((eq? b '+inf) -1)
        ((member 'nan (list a b)) 0)  ;; hmm.....
        (else (big-compare a b))))


(define (xnum-zero? x) (and (number? x) (= x 0)))
(define (xnum-neg? x) (= -1 (xnum-compare x xnum-0)))
(define (xnum-pos? x) (= +1 (xnum-compare x xnum-0)))

(define xnum-0  0)
(define xnum-1  1)
(define xnum-m1 -1)

(define (xnum-+ a b)
  (let ((both (list a b)))
    (cond ((member 'nan both) 'nan)
          ((and (member '+inf both) (member '-inf both)) 'nan)
          ((member '+inf both) '+inf)
          ((member '-inf both) '-inf)
          ((xnum-zero? a) b)
          ((xnum-zero? b) a)
          (else (+ a b)))))

(define (xnum-uneg a)
  ;; negation
  (cond ((eq? a 'nan) 'nan)
        ((eq? a '+inf) '-inf)
        ((eq? a '-inf) '+inf)
        (else (- a))))

(define (xnum-sgn a)
  (cond ((eq? a 'nan)   0)
        ((eq? a '+inf) +1)
        ((eq? a '-inf) -1)
        (else (cond ((positive? a) 1) ((negative? a) -1) (else 0)))))

(define (xnum-abs a)
  (cond ((eq? a 'nan)   a)
        ((eq? a '+inf) '+inf)
        ((eq? a '-inf) '+inf)
        (else (abs a))))

(define (xnum-log2 a)
  ;; note this ROUNDS UP -- as in CSP.
  (cond ((eq? a 'nan)   a)
        ((eq? a '+inf) '+inf)
        ((eq? a '-inf) '+inf)
        (else (xnum-clog2 a))))


(define (xnum-- a . b)
  (if (null? b)
      (xnum-uneg a)
      (xnum-+ a (xnum-uneg (car b)))))

(define (xnum-* a b)
  (let* ((both (list a b))
         (babs  (map xnum-abs both))
         (bsgn  (map xnum-sgn both))
         (sgn   (apply * bsgn))
         (have-neg?  (member -1 bsgn))
         (have-nan (member 'nan both)))

    (cond (have-nan 'nan)

          ((eq? a xnum-m1) (xnum-uneg b))

          ;; { no nan }
          (have-neg? (xnum-* (make-xnum sgn) (apply xnum-* babs)))

          ;; { no nan & no neg }
          ((member '+inf both)
           (if (member xnum-0 both) 'nan  ;; inf times 0
                                    '+inf ;; inf times finite
               ))

          ;; { no nan & no neg & no inf }
          (else (* a b)))))

(define *xnum-special-values* '(nan +inf -inf))

(define (xnum-fin a)
  (cond ((member a *xnum-special-values*) a)
        ((xnum-zero? a) 0)
        (else 'fin)))

(define (xnum-/ a b)
  (let* ((both      (list a b))
         (bsgn      (map xnum-sgn both))
         (bfin      (map xnum-fin both))
         (sgn       (apply * bsgn))
         (have-neg  (member -1 bsgn))
         (have-nan  (member 'nan both)))

    (bigint-dbg "bfin : " bfin dnl)

    (cond (have-nan 'nan)

          ((eq? b xnum-1) a)

          ;; { no nan }
          (have-neg (xnum-* (make-xnum sgn)
                            (apply xnum-/ (map xnum-abs both))))

          ;; { no nan & no neg }

          ((equal? bfin '(0 0)) 'nan) ;; 0/0

          ((xnum-zero? a) xnum-0) ;; 0 / not-nan-not-zero

          ((xnum-zero? b) '+inf) ;; not-nan-not-zero / 0

          ((equal? bfin '(fin fin)) (big/ a b))

          ((equal? bfin '(+inf fin)) '+inf)

          ((equal? bfin '(fin +inf)) xnum-0)

          ((equal? bfin '(+inf +inf)) 'nan)

          (else (error "xnum-/ : dunno how to divide : " a "/" b))

          )
    )
  )

(define (xnum-pow a b)
  (let* ((both (list a b))
         (bfin      (map xnum-fin both))
         (have-nan (member 'nan both)))

    (cond (have-nan 'nan) ;; should (pow 1 nan) = 1 or nan?

          ;; { no nan }
          ((eq? a xnum-1) xnum-1)

          ((equal? bfin '(0 0)) 'nan)

          ((equal? bfin '(fin 0)) xnum-1)

          ((xnum-neg? b) (if (xnum-zero? a) 'nan xnum-0))

          ((equal? bfin '(-inf 0)) 'nan)

          ((equal? bfin '(+inf 0)) 'nan)

          ((equal? bfin '(fin +inf)) '+inf)

          ((equal? bfin '(0 +inf)) 'nan)

          (else (expt a b)))))

(define xnum-**  xnum-pow)

(define (xnum-< a b) (< (xnum-compare a b) 0))
(define (xnum-> a b) (> (xnum-compare a b) 0))
(define (xnum-<= a b) (<= (xnum-compare a b) 0))
(define (xnum->= a b) (>= (xnum-compare a b) 0))
(define (xnum-= a b) (= (xnum-compare a b) 0))

(define (xnum-msb-abs a)
  (case a
    ((nan) 'nan)
    ((-inf +inf) +inf)
    (else (integer-length (abs a)))))

(define (xnum-clog2 x) (+ 1 (xnum-msb-abs (xnum-- x 1))))

(define (xnum-max a . b)
  (define (do2 a b)
    (define blist (list a b))
    (cond
     ((member '+inf blist) '+inf)
     ((member 'nan blist) 'nan)
     ((eq? a '-inf) b)
     ((eq? b '-inf) a)
     (else (max a b))))

  (fold-left do2 a b))

(define (xnum-min a . b)

  (define (do2 a b)
    (define blist (list a b))
    (cond
     ((member '-inf blist) '-inf)
     ((member 'nan blist) 'nan)
     ((eq? a '+inf) b)
     ((eq? b '+inf) a)
     (else (min a b))))

  (fold-left do2 a b))

(define (xnum-<< x sa)
  (cond ((and (number? sa) (= 0 sa)) x)
        ((eq? x 'nan) 'nan)
        ((eq? x '-inf) '-inf)
        ((eq? x '+inf) '+inf)
        ((eq? sa 'nan) 'nan)
        ((eq? sa '+inf) '+inf)
        ((eq? sa '-inf) 0)
        (else (let* ((xlog2 (integer-length (abs x)))
                     (rlog2 (+ sa xlog2)))
                (if (> rlog2 *maximum-size*) +inf (arithmetic-shift x sa))))))

(define (xnum->> x sa) (xnum-<< x (xnum-uneg sa)))

(define (xnum-| a b) ;; |)
  (let ((blist (list a b)))
    (cond
     ((xnum-zero? a) b)
     ((xnum-zero? b) a)
     ((member? '+inf blist) +inf)
     ((member? '-inf blist) -inf)
     ((member? 'nan blist)  nan)
     (else (bitwise-ior a b)))))

(define (xnum-^ a b) ;; |)
  (let ((blist (list a b)))
    (cond
     ((xnum-zero? a) b)
     ((xnum-zero? b) a)
     ((member? '+inf blist) +inf)
     ((member? '-inf blist) -inf)
     ((member? 'nan blist)  nan)
     (else (bitwise-xor a b)))))

(define (xnum-& a b) ;; |)
  (let ((blist (list a b)))
    (cond
     ((xnum-zero? a) 0)
     ((xnum-zero? b) 0)
     ((member? '+inf blist) nan)
     ((member? '-inf blist) nan)
     ((member? 'nan blist)  nan)
     (else (bitwise-and a b)))))

(define (xnum-~ a)
  (cond
     ((xnum-zero? a) -1)
     ((and (number? a) (= a -1)) 0)
     ((eq? a '+inf) nan)
     ((eq? a '-inf) nan)
     (else (bitwise-not a))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; The interval code itself.
;; We somewhat illiterately call the intervals "ranges" (which is a bit
;; confusing, sorry).
;;
;; ranges run from a minimum xnum to a maximum xnum.
;; either end of the range or both can be infinite.
;;
;; A range is empty if its min exceeds its max.
;;
;; Since we only worry about integers, all ranges are countable and the
;; issue of open vs. closed intervals does not come up.
;;

(define (make-range min max)
  (check-xnum min)
  (check-xnum max)
  (list min max))

(define (make-point-range x)
  ;; a point-range is a range of a single value
  (list x x))

(define *range1* (make-point-range 1))
(define *rangem1* (make-point-range -1))

(define (range-min r) (car r))

(define (range-max r) (cadr r))

(define (range-neg-inf? r) (eq? '-inf (range-min r)))

(define (range-pos-inf? r) (eq? '+inf (range-max r)))

(define (range-empty? r) (xnum-< (range-max r) (range-min r)))

(define (range-nonempty? r) (not (range-empty? r)))

(define (range-infinite? r) (or (xnum-infinite? (range-min r))
                                (xnum-infinite? (range-max r))))

(define (range-nan? r) (member 'nan r))

(define (range-finite? r) (and (not range-nan? r)
                               (not (range-infinite? r))))

(define (range-eq? r s) (equal? r s))

(define (range-point? r) (and (not (range-nan? r))
                              (eq? (range-min r) (range-max r))))

(define (range-member? x r)
  (range-contains? r (make-point-range x)))

(define *range-one*           '(1 1))
(define *an-empty-range*      '(+inf -inf))
(define *range-zero*          '(0 0))
(define *range-bit*           '(0 1))
(define *range-unsigned-byte* '(0 255))

;; natural, pos, and neg DO NOT include zero.
(define *range-natural*    '(1     +inf))
(define *range-pos* *range-natural*)

(define *range-neg*        '(-inf    -1))
(define *range-nonneg*     '(0     +inf))
(define *range-nonpos*     '(-inf    0))

;; the entire number line:
(define *range-complete*   '(-inf        +inf))

(define (range-is-zero? r) (range-eq? r *range-zero*))

(define (range-contains-zero? r) (range-member? 0 r))

(define (range-one? f)  (range-eq? r *range-one*))

(define (range-contains? a b)
  (and (xnum-<= (range-min a) (range-min b))
       (xnum->= (range-max a) (range-max b))))

;; operate on ranges in the default way (take cartesian product of
;; results on extreme values)
(define (make-simple-range-binop op)
  (lambda (a b)
    (bigint-dbg "simple-range-binop " op " " a " " b dnl)
    (cond ((range-empty? a) a)
          ((range-empty? b) b)
          (else
           (let* ((all-pairs   (cartesian-product a b))
                  (all-results (map eval (map (lambda(x)(cons op x)) all-pairs)))
                  (min-res     (apply xnum-min all-results))
                  (max-res     (apply xnum-max all-results)))
             (bigint-dbg "all-pairs   : " all-pairs dnl)
             (bigint-dbg "all-results : " all-results dnl)
             (bigint-dbg "min-res     : " min-res dnl)
             (bigint-dbg "max-res     : " max-res dnl)

             (list min-res max-res))))))

(define (range-union ra . rb)
  (define (do2 ra rb)
    (make-range (xnum-min (range-min ra) (range-min rb))
                (xnum-max (range-max ra) (range-max rb))))

  (fold-left do2 ra rb))

(define (range-intersection ra . rb)
  (define (do2 ra rb)
    (make-range (xnum-max (range-min ra) (range-min rb))
                (xnum-min (range-max ra) (range-max rb))))
  (fold-left do2 ra rb))

(define (range-pos? r) (range-eq? r (range-intersection r *range-pos*)))
(define (range-neg? r) (range-eq? r (range-intersection r *range-neg*)))

(define (range-nonneg? r) (not (range-neg? r)))
(define (range-nonpos? r) (not (range-pos? r)))

(define (range-lo x)  `(-inf ,x))

(define (range-hi x)  `(,x +inf))

(define (range-remove r x) ;; remove x if at top or bottom of range
  (cond ((range-empty? r) r)
        ((not (range-member? x r)) r)
        ((eq? (car r) x)  (list
                           (xnum-+ x 1)
                           (cadr r)))
        ((eq? (cadr r) x) (list
                           (car r)
                           (xnum-- x 1)))
        (else r)))

(define (split-range r x)
  ;; return list of ranges split at x
  (if (range-member? x r)
      (filter range-nonempty?
              (list (range-intersection  (range-remove (range-lo x) x) r)
                    (make-point-range x)
                    (range-intersection  (range-remove (range-hi x) x) r)))
      r)
  )

(define (negate-range r)
  (list (xnum-uneg (cadr r)) (xnum-uneg (car r))))

(define (invert-range r)
  (list (xnum-~ (cadr r)) (xnum-~ (car r))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define range-+ (make-simple-range-binop xnum-+))

(define range-bin- (make-simple-range-binop xnum--))

(define (range-un- r)
  (make-range (xnum-- (cadr r)) (xnum-- (car r))))

(define (range-- a . b)
  (if (null? b) (range-un- a) (range-bin- a (car b))))



(define range-* (make-simple-range-binop xnum-*))

(define (range-extends? r x)
  ;; true iff r contains x but is not x
  (and (range-member? x r)
       (not (range-eq? r (make-point-range x)))))

(define (range-extend r x)
  ;; extend r by x
  (range-union r (make-point-range x)))

(define (range-/ a b)
  (let ((unsigned/ (make-simple-range-binop xnum-/)))
    (cond ((range-extends? a 0)
           (let* ((alist (split-range a 0))
                  (rlist (map (lambda(a)(range-/ a b)) alist)))
             (apply range-union rlist)))

          ((range-extends? b 0)
           (let* ((blist (split-range b 0))
                  (rlist (map (lambda(b)(range-/ a b)) blist)))
             (apply range-union rlist)))

          ((range-neg? a) (negate-range (range-/ (negate-range a) b)))

          ((range-neg? b) (negate-range (range-/ a (negate-range b))))

          ((and (eq? a *range-zero*) (eq? b *range-zero*))
           (unsigned/ a b ))

          (else (if (not (and (range-nonneg? a) (range-nonneg? b)))
                    (error
                     "attempting unsigned/ of non-positive ranges : " a b))
                (unsigned/ a b))
          )
    );tel
  )

(define (range-% a b)
  (cond ((range-extends? a 0)
         (let* ((alist (split-range a 0))
                (rlist (map (lambda(a)(range-% a b)) alist)))
           (apply range-union rlist)))

        ((range-extends? b 0)
           (let* ((blist (split-range b 0))
                  (rlist (map (lambda(b)(range-% a b)) blist)))
             (apply range-union rlist)))

        ((range-is-zero? a) a) ;; return zero range

        ((range-is-zero? b) b) ;; return zero range

        ;; result has sign of dividend

        ((range-neg? a) (negate-range (range-% (negate-range a) b)))

        ;; we get here, a is strictly positive,
        ;; b is strictly negative or positive

        ((range-neg? b) (range-% a (negate-range b)))

        ;; we get here, both ranges are positive

        (else (let* ((xa  (range-extend a 0))

                     (xb  (range-extend b 0))

                     (xbr (range-remove xb (range-max xb)))
                     ;; remove the max point of xb, since the remainder
                     ;; is always at least one less than the divisor
                     )

                ;; we extend whatever is left to zero and intersect that
                ;; we don't take finer patterns into account!
                (range-intersection xa xbr)
                ))
        ))

(define (range->> a b)
  (range-<< a (negate-range b)))

(define r-shl-a #f)
(define r-shl-b #f)

(define (range-<< a b)

  (set! r-shl-a a)
  (set! r-shl-b b)

;;  (error)

  (let ((pos<< (make-simple-range-binop xnum-<<)))
    (cond
     ((range-infinite? a) a)

     ((range-is-zero? a) a)

     ((range-infinite? b) *range-complete*)

     ((range-extends? a 0)
      (let* ((alist (split-range a 0))
             (rlist (map (lambda(a)(range-<< a b)) alist))
             (ilist (map invert-range rlist)))
        (apply range-union (append rlist ilist (list (pos<< a b))))))

     ((range-neg? a) (range-union
                      (pos<< a b)
                      (invert-range (range-<< (invert-range a) b))))

     ((and (eq? a *range-zero*) (eq? b *range-zero*))
      (pos<< a b ))

     (else (pos<< a b))
     );;dnoc
    );tel
  )

(define (range-| a b) ;; both pos
  (define xop xnum-|) ;; |)

  (if (or (range-infinite? a) (range-infinite? b))
      *range-complete*
      (let* ((amin (range-min a))
             (amax (range-max a))
             (bmin (range-min b))
             (bmax (range-max b))
             (rmin (xnum-min amin bmin))
             (rmax (xop (xnum-setallbits amax) (xnum-setallbits bmax))))
        (make-range rmin rmax))))

(define (range-& a b) ;; both pos
  (define xop xnum-&) ;; |)

  (cond ((range-infinite? a) b)
        ((range-infinite? b) a)
        (else
         (let* ((amin (range-min a))
                (amax (range-max a))
                (bmin (range-min b))
                (bmax (range-max b))
                (rmin (xop (xnum-clearallbits amin) (xnum-clearallbits bmin)))
                (rmax (xnum-max  ; |)
                       (xnum-setallbits amax) (xnum-setallbits bmax))))
           (make-range rmin rmax)))))

(define (range-^ a b)
  (define xop xnum-^) ;; |)

  (let* ((amin (range-min a))
         (amax (range-max a))
         (bmin (range-min b))
         (bmax (range-max b))

         (neg  (or (xnum-neg? amin) (xnum-neg? bmin)))
         (pos  (or (xnum-pos? amax) (xnum-pos? bmax)))

         (rmin (if neg
                   (xnum-min
                    (xnum-clearallbits amin)
                    (xnum-clearallbits bmin)
                    (xnum-~ (xnum-setallbits amax))
                    (xnum-~ (xnum-setallbits bmax))
                    )
                   0))
         (rmax (if pos
                   (xnum-max
                    (xnum-setallbits amax)
                    (xnum-setallbits bmax)
                    (xnum-~ (xnum-clearallbits amin))
                    (xnum-~ (xnum-clearallbits bmin))
                    )
                   -1))
         )
    (make-range rmin rmax)))

(define (range-not a)
  (negate-range (range-- a *range1*)))

(define (range-pos-& a b)
  ;; a and b are positive ranges
  (make-range 0 (xnum-min (range-max a) (range-max b))))

(define xnum-pos-& xnum-&)

(define (range-pos-| a b) ;|)
  ;; a and b are positive ranges
  (make-range 0 (xnum-setallbits (xnum-max (range-max a) (range-max b)))))

(define xnum-pos-| xnum-|) ;)


(define (xnum-setallbits x)
  ;; set all bits up to and including the highest set bit in x
  (cond ((eq? x +inf) -1)

        ((xnum-pos? x)
         (- (expt 2 (xnum-clog2 (+ x 1))) 1))
        ((xnum-zero? x) 0)
        ((xnum-neg? x) -1)
        (else (error))))

(define (xnum-clearallbits x)
  ;; clear all bits up to and including the highest clear bit in x
  (cond ((eq? x -inf) 0)
        ((xnum-neg? x)
         (xnum-~ (xnum-setallbits (xnum-~ x))))
        ((xnum-zero? x) 0)
        ((xnum-pos? x) 0)
        (else (error))))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (xnum-bits x lo hi)
  (cond ((xnum-zero? x) 0)
        ((eq? lo +inf) 0)
        ((eq? lo -inf) nan)
        ((eq? lo  nan) nan)

        ((eq? (xnum-> lo hi) #t) 0)

        ;; lo is finite
        ((not (xnum-zero? lo))
         (xnum-bits (xnum->> x lo) 0 (xnum-+ (xnum-- hi lo) 1)))

        ;; lo is zero
        ((eq? hi +inf) x)
        ((eq? hi -inf) 0)
        ((eq? hi nan) nan)

        ;; hi is finite
        ((xnum-> hi (xnum-log2 x))
         x)

        (else
         (bigbits x lo hi))

        );;dnoc
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


(define (convert-eval-xnum-binop q)
  (eval (cond ((eq? q 'make-range)   make-range)
              (else  (symbol-append 'xnum- q)))))

(define xex #f)
(define (xnum-eval expr)
  (set! xex expr)
  (cond ((and (number? expr) (exact? expr)) expr)
        ((number? expr) (inexact->exact (round expr)))
        ((string? expr) (string->number expr 10))

        ((and (pair? expr)
              (eq? 'apply (car expr)))
         (let* ((proc-expr (cadr expr))
                (proc-id   (cadr proc-expr))
                (xproc     (eval (symbol-append 'xnum- proc-id)))
                (result    (apply xproc (cddr expr))))
           result))

        ((and (list? expr) (= 3 (length expr)))
         (apply (convert-eval-xnum-binop (car expr))
                (map xnum-eval (cdr expr))))

        ((and (list? expr) (= 2 (length expr)) (eq? '- (car expr)))
         (xnum-uneg (xnum-eval (cadr expr))))

        ((= 2 (length expr))
         (apply (convert-eval-xnum-binop (car expr))
                (map xnum-eval (cdr expr))))

        (else (error "xnum-eval : can't handle : " expr))))

(define mult  1e11)
(define bmult (inexact->exact (round mult)))

(define *r* #f)
(define *rr* #f)

(define (xnum-random range)
  (let* ((rr (range-intersection  range *val-range*))
         (lo (car rr))
         (hi (cadr rr))
         (eq (eq? lo hi))
         (delta (if (eq? lo hi) 0 (xnum-- hi lo)))
         (r1    (random)))

    (cond ((< r1 0.1) (car range))  ;; may be -inf
          ((< r1 0.2) (cadr range)) ;; may be +inf
          (else
           (let* ((r2 (* mult (random)))
                  (b2 (inexact->exact (round r2)))
                  (x  (xnum-* b2 delta))
                  (y  (xnum-/ x  bmult))
                  (res (xnum-+ lo y))
                  )

             (set! *r* range)
             (set! *rr* rr)

             (bigint-dbg "range = " range dnl)
             (bigint-dbg "rr    = " rr dnl)
             (bigint-dbg "delta = " delta dnl)
             (bigint-dbg "eq    = " eq dnl)
             (bigint-dbg "r2    = " r2 dnl)
             (bigint-dbg "b2    = " b2 dnl)
             (bigint-dbg "x     = " x  dnl)
             (bigint-dbg "y     = " y  dnl)
             (bigint-dbg "lo    = " lo  dnl)
             (bigint-dbg "res   = " res dnl)
             res
             )
           )
          )
    )
  )

(define (range-random)
  ;; return a potentially infinite range
  (let* ((a0    (xnum-random *range-complete*))
         (a1    (xnum-random *range-complete*))
         (min   (xnum-min a0 a1))
         (max   (xnum-max a0 a1))
         (ra    (make-range min max)))
    (if (and (eq? min max)
             (xnum-infinite? min))
        ;; dont return -inf -inf or +inf +inf
        (range-random)
        ra)
    )
  )

(define *val-lo* -100)
(define *val-hi* +100)
(define *val-range* (make-range *val-lo* *val-hi*))
(define *val-pos* (make-range 1 *val-hi*))
(define *val-neg* (make-range *val-lo* -1))


(define (make-random-range r)
  (let* ((rand (range-random))
         (res (range-intersection r rand)))

    (if (range-empty? res) (make-random-range r) res)))

(define *fail-op* #f)
(define *fail-ra* #f)
(define *fail-rb* #f)
(define *fail-a*  #f)
(define *fail-b*  #f)
(define *fail-rc* #f)
(define *fail-c*  #f)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; some testing stuff

;;(if #t
(define (bs16 s) (string->number s 16))
(define (bf16 x) (number->string x 16))
(arithmetic-shift (bs16 "-c0edbabe") 4)
(arithmetic-shift (bs16 "-c0edbabe") -31)
;;(bf16 (arithmetic-shift (bs16 "-c0edbabe") -44))
;;)

(define bn inexact->exact)

