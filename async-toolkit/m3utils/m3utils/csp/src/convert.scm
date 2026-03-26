; Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information.
; SPDX-License-Identifier: Apache-2.0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (convert-structure-decl s)
  (let ((ident  (cadr s))
        (fields (map car (caddr s)))
        (seq    (init-seq 'CspStructDeclaratorSeq.T)))

    (map (curry seq 'addhi) (map convert-field-decl fields))

    seq
    (CspAst.StructureDeclaration ident (seq '*m3*))
    )
  )

(define (force-boolean x)
  (cond ((and (number? x) (exact? x) (= -1 x))
         #t)

        ((and (number? x) (exact? x) (= 0 x))
         #f)

        (else x)))

(define (convert-field-decl fd)
  (let ((fn   (cadadr fd))
        (ty   (caddr fd))
        (dir  (cadddr fd))
        (init (caddddr fd))
        )
    (CspAst.StructDeclarator
     fn
     (convert-type ty)
     (if (null? init) '() (convert-expr init))
     (convert-dir dir))
    )
  )

(define (convert-stmt s . last)
  (set! *s* s)
  (set! *last* last)
;;  (dis "CONVERT : " s dnl)

  (if (eq? s 'skip)

      ;; special case for skip, only token allowed on its own
      (CspAst.SkipStmt)

      ;; not a skip -- handle it properly
      (begin
        (if (not (pair? s))
            (begin
              (set! *bad-s* s)
              (set! *bad-last* last)
              (error "Not a statement : " s dnl "last : " last)))
        
        (let ((kw (car s))
              (args (cdr s))
              )
;;          (dis "kw is " kw dnl)
          
          (case kw
            
            ((sequence parallel) ;; sequential and parallel composition
             (let ((seq (init-seq 'CspStatementSeq.T)))
               (map (lambda(ss)
                      (seq 'addhi (convert-stmt ss s)))
                    args
                    )
               ((if (eq? kw 'sequence)
                    CspAst.SequentialStmt
                    CspAst.ParallelStmt)
                (seq '*m3*))
               
               ))

            ((assign) ;; simple assignment
             (CspAst.AssignmentStmt (convert-expr (car args))
                                    (convert-expr (cadr args))
                                )
             )

            ((assign-operate) 
             (CspAst.AssignOperateStmt
              (convert-expr (cadr args))
              (convert-expr (caddr args))
              (convert-binop (car args))
              ))

            ((loop) ;; this is from the Java, convert to parallel or sequential
             (let ((idxvar (car args))
                   (range  (cadr args))
                   (sep-id (caddr args))
                   (stmt   (cadddr args)))

               ((cond ((= sep-id 0) CspAst.SequentialLoop)
                      ((= sep-id 1) CspAst.ParallelLoop)
                      (else (error "convert-stmt : unknown loop type " sep-id)))
                idxvar
                (convert-range range)
                (convert-stmt stmt s))))

            ((sequential-loop parallel-loop) ;; what we will compile
             (let ((idxvar (car args))
                   (range  (cadr args))
                   (stmt   (caddr args)))
               ((case kw
                  ((sequential-loop) CspAst.SequentialLoop)
                  ((parallel-loop) CspAst.ParallelLoop)
                  (else (error)))
                idxvar
                (convert-range range)
                (convert-stmt stmt s))
               ))

            ;; the next two are just syntactic sugar
            ;;
            ;; we desugar them here, so the rest of the code doesn't have
            ;; to handle them.

            ((increment) ;; desugar to assign-operate
             (convert-stmt (list 'assign-operate '+ (car args) *big1*)
                           s)
             )

            ((decrement) ;; desugar to assign-operate
             (convert-stmt (list 'assign-operate '- (car args) *big1*)
                           s)
             )

            ((var) ;; desugar to var1
             (if (= 1 (length (cadr s)))
                 
                 (convert-var-stmt s)
                 
                 (convert-stmt (flatten-var-stmt s) s))
             )

            ((var1) ;; this is a simplified declaration
             (convert-var1-stmt s))

            ((structure-decl)
             (convert-structure-decl s)
             )

            ((recv)
             ;; null receive is OK (just completes the handshake)
             (CspAst.RecvStmt (convert-expr (car args))
                              (convert-expr-or-null (cadr args))))

            ((send) (CspAst.SendStmt (convert-expr (car args))
                                     (convert-expr (cadr args))))

            ((do if nondet-if nondet-do)
             (let ((seq (init-seq 'CspGuardedCommandSeq.T)))
               (map (lambda (gc)
                      (seq 'addhi
                           (CspAst.GuardedCommand

                            (let* ((guard (car gc)) ;; convert -1 to #t
                                   (expr-guess 
                                    (convert-expr (force-boolean guard))))
                              expr-guess
                              )
                            
                            
                            (convert-stmt (cadr gc) s))))
                    args)

               (let ((maker
                      (case kw
                        ((do) CspAst.DetRepetitionStmt)
                        ((if) CspAst.DetSelectionStmt)
                        ((nondet-do) CspAst.NondetRepetitionStmt)
                        ((nondet-if) CspAst.NondetSelectionStmt)
                        )))

                 (maker (seq '*m3*)))
               ))

            ((eval) ;; this is ONLY used for function evaluations
             (CspAst.ExpressionStmt (convert-expr (car args))))
            
            (else (set! *bad-s* s)
                  (set! *bad-last* last)
                  (error "convert-stmt : unknown statement " s))
            )
          )
        )
      ))

(define *last-x* #f)

(define *all-x* '())

(define *rest* #f)

(define *last-a* #f)

(define (convert-binop sym)
  (case sym
    ((-) 'Sub) ;; unary op has a different name...
    ((+) 'Add)
    ((/) 'Div)
    ((%) 'Rem)
    ((*) 'Mul)
    ((==) 'EQ)
    ((!=) 'NE)
    ((<) 'LT)
    ((>) 'GT)
    ((>=) 'GE)
    ((<=) 'LE)
    ((&) 'And)
    ((&&) 'CondAnd)
    ((|) 'Or) ;;|)
    ((||) 'CondOr)
    ((^) 'Xor)
    ((<<) 'SHL)
    ((>>) 'SHR)
    ((**) 'Pow)
    (else (error " BinExpr " (car x)))))

(define (convert-expr x)
  (set! *last-x* x)
  (set! *all-x* (cons x *all-x*))

;;  (dis "EXPR : " x dnl)

  (cond ((null? x) (error "convert-expr : x is null"))

        ((and (number? x) (exact? x))  (CspAst.IntegerExpr x))

        ((string? x) (CspAst.StringExpr x))

        ((eq? x 'else) (CspAst.ElseExpr))

        ((eq? x #t) (CspAst.BooleanExpr #t))

        ((eq? x #f) (CspAst.BooleanExpr #f))

        ((pair? x)

         ;; a pair...
         (case (car x)
           ((probe) (CspAst.ProbeExpr (convert-expr (cadr x))))

           ((array-access) (CspAst.ArrayAccessExpr (convert-expr (cadr x))
                                                   (convert-expr (caddr x))))

           ((id) (CspAst.IdentifierExpr (cadr x)))

           ((member-access) (CspAst.MemberAccessExpr (convert-expr (cadr x))
                                                     (caddr x)))
           ((structure-access) (CspAst.StructureAccessExpr (convert-expr (cadr x))
                                                     (caddr x)))

           ((apply call-intrinsic)
            (let ((fx     (convert-expr (cadr x)))
                  (rest   (cddr x))
                  (argseq (init-seq 'CspExpressionSeq.T)))

              (set! *rest* rest)
              (map
               (lambda(a)
                 (set! *last-a* a)
                 (argseq 'addhi (convert-expr a)))
               rest)
              (CspAst.FunctionCallExpr fx (argseq '*m3*))
              )
            )


           ((loop-expression)
            (CspAst.LoopExpr (cadr x)
                             (convert-range (caddr x))
                             (convert-binop (cadddr x))
                             (convert-expr (caddddr x))
                             ))

           ((recv-expression)
            (CspAst.RecvExpr (convert-expr (cadr x))))
           
           ((peek)
            (CspAst.PeekExpr (convert-expr (cadr x))))

           ((bits)
            (let ((base (convert-expr (cadr x)))
                  (min  (convert-expr-or-null (caddr x)))
                  (max  (convert-expr (cadddr x))))
              (CspAst.BitRangeExpr base (if (null? min) max min) max)
              )
            )
           
           ((not) (CspAst.UnaExpr 'Not (convert-expr (cadr x))))

           ((-)
            ;; - is special

            (if (null? (cddr x))
                (CspAst.UnaExpr 'Neg (convert-expr (cadr x)))
                (CspAst.BinExpr 'Sub (convert-expr (cadr x))
                                     (convert-expr (caddr x)))))

           ((+ / % * == != < > >= <= & && | || ^ == << >> **) ;; |
            (CspAst.BinExpr
             (convert-binop (car x))
             (convert-expr (cadr x))
             (convert-expr (caddr x))))
           
           (else (error "convert-expr : unknown keyword " (car x) " : " x ))
           )
         )
        
        (else (error "dunno that type " x) )
        )
  )
  
(define (convert-expr-or-null x)
  (if (null? x) '() (convert-expr x)))

(define (convert-dir dir)
  (case dir
    ((none)  'None)
    ((in)    'In)
    ((out)   'Out)
    ((inout) 'InOut)
    (else (error "convert-dir : unknown direction : " dir))
    )
  )

(define (convert-range r)
  (if (or (not (pair? r))
          (not (eq? (car r) 'range)))
      (error "convert-range : not a range : " r)
      `((min . ,(convert-expr (cadr r)))
        (max . ,(convert-expr (caddr r))))))

(define (convert-type type)
  (cond
   ((pair? type)
    (case (car type)
      ((array)       (CspAst.ArrayType (convert-range (cadr type))
                                       (convert-type (caddr type))))
      ((channeltype) (CspAst.ChannelType (cadr type) (convert-dir (caddr type))))
      ((integer)     (let ((isConst (cadr type))
                           (isSigned (caddr type))
                           (dw       (cadddr type))
                           (interval (caddddr type)))
                       
                       (CspAst.IntegerType
                        isConst
                        isSigned
                        (if (null? dw) '() (convert-expr dw))
                        (not (null? interval))
                        (if (null? interval)
                            '(() ())
                            (list (car interval) (cadr interval))))))

      ((boolean) (CspAst.BooleanType (cadr type)))
      ((string) (CspAst.StringType (cadr type)))      
      
      ((node-array)  (CspAst.NodeType #t (caddr type) (convert-dir (cadr type))))
      ((node)        (CspAst.NodeType #f 1 (convert-dir (cadr type))))
      ((structure)   (CspAst.StructureType (cadr type)
                                           (symbol->string (caddr type))))
      (else (error "convert-type : unknown type (pair) : " type))
      )
    )
    
   (else (error "convert-type : unknown type : " type))
   )
  )

;;
;; make a few routines to initialize default values of various types.
;; should generate a sequence of statements to initialize a variable of
;; the given type.  Note that structures may have nonzero initial values.
;;

(define *last-decl* #f)

(define (convert-declarator decl)
  (set! *last-decl* decl)
;;  (dis "convert-declarator : " decl dnl)
  (case (car decl)
    ((decl)
     (let ((ident (cadr decl))
           (type  (caddr decl))
           (dir   (cadddr decl))
           (expr  (caddddr decl)))
       (CspAst.Declarator
        (if (or (not (pair? ident))
                (not (eq? (car ident) 'id)))
            (error "convert-declarator : unexpected identifier in declarator : " ident)
            (cadr ident))
        (convert-type type)
        (convert-dir  dir))
       ))
    ((decl1)
     (let ((ident (cadr decl))
           (type  (caddr decl))
           (dir   (cadddr decl)))
       (CspAst.Declarator
        (if (or (not (pair? ident))
                (not (eq? (car ident) 'id)))
            (error "convert-declarator : unexpected identifier in declarator : " ident)
            (cadr ident))
        (convert-type type)
        (convert-dir  dir))
       ))
    (else (error "convert-declarator : dont know declarator : " decl))
    )
  )

(define (convert-struct-declarator decl)
  (set! *last-decl* decl)
  (dis "convert-declarator : " decl dnl)
  (let ((ident (cadr decl))
        (type  (caddr decl))
        (dir   (cadddr decl))
        (expr  (caddddr decl)))
    (CspAst.StructDeclarator
     (if (or (not (pair? ident))
             (not (eq? (car ident) 'id)))
         (error "convert-declarator : unexpected identifier in declarator : " ident)
         (cadr ident))
     (convert-type type)
     (if (null? expr) '() (convert-expr expr))
     (convert-dir  dir))
    )
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

