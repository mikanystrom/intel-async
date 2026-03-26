;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; structs
;;
;;
;; struct-decl is a definition of a struct type
;; for now, we support both desugared and "raw" struct decls
;; the (weak) reason is that we need to do a lot of constant folding, etc.,
;; to know what the actual types are, since they can be parameterized.
;;

(define (struct-decl? struct-decl)
  (and (pair? struct-decl)
       (eq? 'structure-decl (car struct-decl))))

(define (structdecl? struct-decl)  ;; desugared version
  (and (pair? struct-decl)
       (eq? 'structdecl (car struct-decl))))

(define (structdecl-width struct-decl)
  (let* ((fields (cddr struct-decl))
         (ftypes (map get-decl1-type fields))
         (widths (map get-type-width ftypes))
         )
    (if (exists (curry > 1) widths)
        -1 ;; if any component is negative, the whole thing is -1
        (apply + widths)
        )
    )
  )

(define (struct-field-width fd)
  (let ((ty (get-decl1-type fd)))
    (get-type-width ty)))

(define (get-type-width ty)
  (cond ((boolean-type? ty) 1)
        
        ((integer-type? ty)
         (let ((bw (cadddr ty)))
           (if (null? bw)
               -1
               bw)))
        
        ((array-type? ty)
         (let* ((extent (array-extent ty))
                (min (cadr extent))
                (max (caddr extent))
                (ok (and (bigint? min) (bigint? max))))
           (if ok (* (+ 1 (- max min))
                     (get-type-width (array-elemtype ty))))))

        ((struct-type? ty)
         (let* ((snm  (caddr ty))
                (sdef (lookup-struct-decl snm))
                )
           (structdecl-width sdef)))

        (else -1)
        );;dnoc
  )

(define (lookup-struct-decl id)
  (dis "lookup-struct-decl : id : " id dnl)
  (cons 'structdecl
        (assoc id (map cdr *the-struct-decls*))))

(define (check-is-struct-decl struct-decl)
  (if (not (struct-decl? struct-decl))
      (error "not a struct-decl : " struct-decl)))

(define (get-struct-decl-name struct-decl)
  (cond ((struct-decl? struct-decl) (cadr struct-decl))

        ((structdecl? struct-decl) (cadr struct-decl))

        (else (error "not a struct-decl : " struct-decl)))
  )

(define (get-struct-decl-fields struct-decl)
  (cond ((struct-decl? struct-decl)
         ;; unconverted, so desugar declarators
         (map CspDeclarator.Lisp
              (map convert-declarator
                   (apply append (caddr struct-decl)))))

        ((structdecl? struct-decl) (cddr struct-decl))

        
        (else (error "not a struct-decl : " struct-decl))
        );;dnoc
  )

(define (get-struct-decl-field-type struct-decl fld)
  (define (recurse p)
    (cond ((null? p) #f)
          ((equal? (cadar p) `(id ,fld)) (caddar p))
          (else (recurse (cdr p)))))

  (recurse (get-struct-decl-fields struct-decl)))

;; struct is a reference to a struct type (an instance declaration)
(define (struct? struct)
  (and (pair? struct)
       (eq? 'structure (car struct))))

(define (check-is-struct struct)
  (if (not (struct? struct))
      (error "not a struct : " struct)))

(define (get-struct-name struct)
  (check-is-struct struct)
  (caddr struct))

(define (get-struct-const struct)
  (check-is-struct struct)
  (cadr struct))

                         

