; Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information.
; SPDX-License-Identifier: Apache-2.0

(require-modules "basic-defs" "display" "mergesort")

(define *e* '()) ;; debug assistance

(define (pow x n) (Math.pow x n))

(define sq-mm-per-sq-inch (* 25.4 25.4))

(define n5-d0   0.065) ;; testing
(define n5-n       32)
(define n5-alpha 0.05)

(define (stapper0_05 a d0 n) (YieldModel.Stapper a d0 n 0.05))

(define (stapper0_02 a d0 n) (YieldModel.Stapper a d0 n 0.02))

(define *model* stapper0_05)

(define (yield a)
  (*model* a n5-d0 n5-n))

(define *area* 800)

(define (PA) (yield (/ *area* 2)))

(define PB PA)

(define (PC) (yield *area*))

(define (PBp) (- 1 (PB)))

(define (PAgBp) (/ (- (PA) (PC)) (PBp)))

(define (A-ratio) (/ (PAgBp) (PA)))

(define (PAuB) (+ (PA) (PB) (- (PC))))

(define (PApiBp) (- 1 (PAuB)))

(define (PApgBp) (/ (PApiBp) (PBp)))

(define (PAp) (- 1 (PA)))

(define (tsmc-d0-correction a) ;; CENSORED
  (cond ((> a 400) -0.030)
        ((> a 300) -0.025)
        ((> a 200) -0.020)
        ((> a 100) -0.010) ;; see Jeremy's script
        (else       0)
        )
  )

(define (tsmc-yield a d0 n)
  ;; incorporate the TSMC d0 correction, rough formula (not checked)

  (define (d-correction a) (tsmc-d0-correction a))

  (YieldModel.BoseEinstein a (+ (d-correction a) d0) n))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  
(define (choose n k)
  (let loop ((d 1)             ;; Denominator
             (u (+ n (- k) 1)) ;; nUmerator
             (p 1)             ;; Product
             )
    (if (> d k) (begin ;;(dis "choose: " (round p) dnl)
                       (round p))
        (loop (+ d 1) (+ u 1) (* p (/ u d))))))

(define (sum lo hi f)
  (let loop ((s 0)
             (i lo))
    (if (= i hi)
        (+ s (f i))
        (loop (+ s (f i)) (+ i 1)))))

(define false #f)

(define (lookup key table)
  (let ((record (assoc key (cdr table))))
    (if record
        (cdr record)
        false)))

(define (assoc key records)
  (cond ((null? records) false)
        ((equal? key (caar records)) (car records))
        (else (assoc key (cdr records)))))

(define (make-table)
  (list '*table*))

(define (insert! key value table)
  (let ((record (assoc key (cdr table))))
    (if record
        (set-cdr! record value)
        (set-cdr! table
                  (cons (cons key value) (cdr table)))))
  'ok)

(define (memoize f)
  (let ((table (make-table)))
    (lambda (x)
      (let ((previously-computed-result (lookup x table)))
        (or previously-computed-result
            (let ((result (f x)))
              (insert! x result table)
              result))))))

;;(define (memoize f) f)

(define (make-yield-calculator Y)
  (lambda(A N M)

    (define Pi
      (memoize
       (lambda (k)
         (if (= k N)
             (Y (* N A))
             
             (- (Y (* k A))
                (sum (+ k 1)
                     N
                     (lambda(j)(* (choose (- N k) (- N j)) (Pi j)))))))))

    (sum M N (lambda(i) (* (choose N i) (Pi i)))))
  )

(define (kronecker n) (lambda (k) (if (= n k) 1 0)))

(define (find-yield-expression N M)
  (let loop ((i M)
             (q '()))
    (if (> i N)
        (cons '+ q)
        (loop (+ i 1)
              (cons (list '*
                          (round ((make-yield-calculator (kronecker i)) 1 N M))
                          (list 'Y i))
                    q)
              )
        )))
    

(define (my-yield A) (YieldModel.Stapper A 0.10 32 0.02))

(define (binomial-yield Y A N M)
  (sum M N (lambda(k)(* (choose N k) (pow (Y A) k) (pow (- 1 (Y A)) (- N k))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; dont think we use this one:

(define (binomial-yield-term A N M)
  (let* ((ym (make-power-term A))
         (-ym (*-term -1-term ym)))
    (sum-term M
              N
              (lambda(k)(*-term (make-number-term (choose N k))
                                (*-term (^-term ym k)
                                        (^-term
                                         (+-term 1-term -ym)
                                         (- N k))))))))


(define the-binomial-yield-model '())

(define (Gamma x) (Math.exp (Math.gamma x)))

(define (upper-limit x y)
  (/ (Gamma (+ y 1))
     (- (Gamma (+ y 1)) (* (Gamma (+ y (- x) 1)) (Gamma (+ x 1))))))

(define (ex16of18 Y)
  (+ (* 136 (Y 18)) (* -288 (Y 17)) (* 153 (Y 16))))


