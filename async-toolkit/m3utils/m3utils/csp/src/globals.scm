; Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information.
; SPDX-License-Identifier: Apache-2.0

(define (globals-dbg . x)
  ;; (apply dis x)
  )

(define (array? type)
  (and (pair? type) (eq? 'array (car type))))

(define (index-hash lst)
  (apply + (map (lambda (x) (remainder (abs x) 1000000007)) lst)))

(define (get-index-list access)
  (if (and (pair? access) (eq? (car access) 'array-access))

      (let ((my-idx (caddr access))
            (rest   (get-index-list (cadr access))))

        (if (and rest (literal? my-idx)) ;; if not a literal, we fail.
            (cons my-idx rest)
            #f ;; failed
            ))
      '()))

(define (construct-globals-tbl the-inits)
  ;; a very simple CSP interpreter...
  ;; it just handles array declarations.

  (define tbl (make-hash-table 100 atom-hash))
  
  (define (handle-var1 v1)
    (globals-dbg "handle-var1 : " v1 dnl)

    (if (array? (get-var1-type v1))
        (tbl 'add-entry! (get-var1-id v1) (make-hash-table 100 index-hash)))
    )

  (define (handle-assign ass)
    (globals-dbg "handle-assign : " ass dnl)
    (set! a ass)
    (let ((lhs (get-assign-lhs ass)))
      (if (array-access? lhs)
          (let* ((ilist (get-index-list lhs))
                 (base  (get-designator-id lhs))
                 (data  (tbl 'retrieve base)))

            (data 'add-entry! ilist (get-assign-rhs ass)))))
            
    )
  
  (define (run-interpreter stmt)
    (case (get-stmt-type stmt)
      ((sequence)
       (map run-interpreter (cdr stmt)))

      ((skip)
       ;; skip
       )
      
      ((var1)
       (handle-var1 stmt))

      ((assign)
       (handle-assign stmt))

      (else (error "construct-globals-tbl interpreter can't handle statement : " stmt))))

  (run-interpreter the-inits)

  tbl
  )
