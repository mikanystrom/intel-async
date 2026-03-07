; Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information.
; SPDX-License-Identifier: Apache-2.0

;; (loaddata! "expressions_u")
;;(var-ass-range 'y *the-ass-tbl* *the-prt-tbl*)

(load "debug.scm")

(define (vars-dbg . x)
  (apply dis x)
  )

(define (make-assignments-tbl prog cell-info the-inits func-tbl struct-tbl)

  (define tbl (make-hash-table 100 atom-hash))
  
  (define (trace-ass-visitor s syms vals tg func-tbl struct-tbl _cell-info)

    (define (add-entry! designator)
      (let* ((id        (get-designator-id designator))
             (new-entry (list s syms id vals))
             )

        (if (not id) (error "no designator id in " designator dnl))
        
        (let ((q (tbl 'retrieve id)))
          (if (eq? q '*hash-table-search-failed*)
              (tbl 'add-entry!    id (list new-entry))
              (tbl 'update-entry! id (cons new-entry q))))))
      

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    
    (case (get-stmt-type s)
      ((assign)
       
       (let* ((rhs       (get-assign-rhs s))
              (lhs       (get-assign-lhs s)))
         (if (not (equal? rhs lhs))
             ;; self-assignments don't count!
             ;; (Andrew adds these for some sort of synchronization)
             (add-entry! lhs)))
       )

      ((recv)
       (let ((lhs (get-recv-lhs s))
             (rhs (get-recv-rhs s)))
         (vars-dbg "recv     : " s dnl)
         (vars-dbg "recv lhs : " lhs dnl)
         (vars-dbg "recv rhs : " rhs dnl)

         (if (not (null? rhs)) (add-entry! rhs)))
       )

      ((assign-operate)  ;; should be transformed out
       (error))


      ((sequential-loop parallel-loop)
       (add-entry! `(id ,(get-loop-dummy s)))
       )
      
      
      ((eval)
       ;; should only be a call-intrinsic at this point
       (let* ((expr (cadr s))
              (expr-type (car expr)))
         (if (not (eq? 'call-intrinsic expr-type))
             (error "make-assignments-tbl called on non-inlined code : " s))

         (let ((inam (cadr expr)))
           (if (eq? inam 'unpack)
               (add-entry! (caddr expr))))))
      )
    s
    )

  ;;  (visit-stmt tgt visitor identity identity)


  (run-pass (list '* trace-ass-visitor)
            prog cell-info the-inits func-tbl struct-tbl)

  tbl
  )

(define (make-asses prog)
  (make-assignments-tbl prog *cellinfo* *the-inits* '() *the-struct-tbl*))
         
    
(define (constant-assignment? ass syms)
  (let* ((rhs (get-assign-rhs ass))
         (is-id (ident? (get-assign-lhs ass)))
         (is-const (constant-simple? rhs syms))) ;; #f or a list containing the value
    (and is-id is-const)))

(define (ass-tgt-designator stmt)
  (case kw
    ((assign) (get-designator-id (get-assign-lhs stmt)))
    ((recv)   (let ((tgt (get-assign-rhs stmt)))
                (if (null? tgt) '() (get-designator-id (get-recv-rhs stmt)))))
    (else (error "not an assigning statement : " stmt))))

(define (all-elems-equal? lst)
  (cond ((null? lst)      #t)
        ((null? (cdr lst) #t))
        (else (and (equal? (car lst) (cadr lst))
                   (all-elems-equal? (cdr lst))))))
         


(define (find-constant-symbols tbl)
  (let* ((keys      (tbl 'keys))  ;; all the keys from the assignment table
         
         (ass-lsts  (map (lambda(k)(tbl 'retrieve k)) keys))
         ;; get the assignments for each key
         
         (ssa-lst   (map car (filter all-elems-equal? ass-lsts)))
         ;; filter out the single assignment variables
         ;; note we don't check the length in case the same thing
         ;; is being assigned (happens from do -> while conversion)
         
         (con-lsts  (filter (lambda(e)(constant-assignment? (car e) (cadr e)))
                            ssa-lst))
         ;; and filter out the constant assignments from that

         )

    (map caddr con-lsts) ;; return just the symbols
    
    )
  )

(define (make-var1-constant v1)
  (make-var1-decl (get-var1-id v1) (make-constant-type (get-var1-type v1)))) 

(define (mark-decls-constant prog constant-ids)
  (vars-dbg "mark-decls-constant" dnl)
  (define (visitor s)
    (if (eq? 'var1 (get-stmt-type s))
        (if (member (get-var1-id s) constant-ids)
            (let ((res (make-var1-constant s)))
              (vars-dbg "mark-decls-constant " (get-var1-id s) " " res dnl)
              res
              )
            s
            )
        s
        )
    )

  (visit-stmt prog visitor identity identity)
  )


(define (vx)
   (find-constant-symbols the-asses)

   (define the-asses (make-asses text4))

   (map car (the-asses 'retrieve 'run-pass-temp177))
)

(define (constantify-constant-vars prog)
  (dis "constantify-constant-vars" dnl)
  (let* ((the-asses         (make-asses prog))
         (the-constant-syms (find-constant-symbols the-asses))
         (the-new-prog      (mark-decls-constant prog the-constant-syms)))
    the-new-prog
    )
  )


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;    


(define (make-uses prog)

  (define tbl (make-hash-table 100 atom-hash))

  (define cur-stmt #f) ;; the statement currently being processed
  
  (define (add-entry! id)
    (let* ((new-entry (list cur-stmt))
           )
      (vars-dbg "make-uses-tbl add-entry!  "  id " -> " cur-stmt dnl)
      (let ((q (tbl 'retrieve id)))
        (if (eq? q '*hash-table-search-failed*)
            (tbl 'add-entry!    id (list new-entry))
            (tbl 'update-entry! id (cons new-entry q))))))


  ;; the idea here is that we record every id in every expression,
  ;;
  ;; EXCEPT left-hand-sides, which appear in three places:
  ;; 1. assignments
  ;; 2. receives
  ;; 3. the first argument to unpack()
  ;;
  ;; we abort on encountering apply() and assign-operate
  
  (define (s-visitor s)

;;    (vars-dbg "s-visitor : s : " s dnl)
    (case (get-stmt-type s)

      ((apply assign-operate)
       (error "make-uses-tbl : being called too soon : encountered : " s))
      
      ((assign)
       
       (let* ((lhs         (get-assign-lhs s))
              (lhs-depends (get-designator-depend-ids lhs))
              (rhs         (get-assign-rhs s))
              (rhs-ids     (find-expr-ids rhs)))
         (map add-entry! lhs-depends)
         (map add-entry! rhs-ids))
       )

      ((recv)
       (let ((lhs (get-recv-lhs s))
             (rhs (get-recv-rhs s)))
;;         (vars-dbg "recv     : " s dnl)
;;         (vars-dbg "recv lhs : " lhs dnl)
;;         (vars-dbg "recv rhs : " rhs dnl)

         (if (not (null? rhs)) ;; we do NOT want the written variable
             (map add-entry! (get-designator-depend-ids rhs)))
         (if (not (null? lhs))
             (map add-entry! (find-expr-ids lhs))))
       )

      ((waiting-if) ;; add the wait conditions as referenced vars
       (map add-entry! (map car (cdr s)))
       )

      ((eval)
       (let* ((expr      (cadr s))
              (expr-type (car expr)))
         (if (not (eq? 'call-intrinsic expr-type))
             (error "make-assignments-tbl called on non-inlined code : " s))

         ;; we add all the args as dependencies unless we're unpacking.
         (let* ((inam  (cadr expr))
                (iargs (cddr expr))
                (ids   (uniq eq?
                             (if (eq? inam 'unpack)
                                 (append
                                  (get-designator-depend-ids (car iargs))
                                  (apply append (map find-expr-ids (cdr iargs)))
                                  )
                                 
                                 (apply append (map find-expr-ids iargs)))))
                )
;;           (vars-dbg "s-visitor inam " inam dnl)
;;           (vars-dbg "s-visitor iargs " (stringify iargs) dnl)
;;           (vars-dbg "s-visitor ids " ids dnl)
           (map add-entry! ids)
           )
         )
       )
      
      );;esac
    s)

  (define (advance-callback s)
    (vars-dbg "advance-callback " s dnl)
    (set! cur-stmt s)
    s)
  
  (define (x-visitor x)

    (vars-dbg "x-visitor : x is         : " x dnl)

    (if (not (null? cur-stmt)) ;; we can also get called through type visiting

        (let ((stmt-type (get-stmt-type cur-stmt)))
          (vars-dbg "x-visitor : stmt-type is : " stmt-type " : ")

          (case stmt-type
            ((assign recv eval)
             ;; skip
             (vars-dbg "skipping" dnl)
             )

            ((parallel sequence) ;; skip
             (vars-dbg "skipping" dnl)
             )
             
            (else
             (let ((ids (find-expr-ids x)))
               (vars-dbg "found ids " ids dnl)
               (map add-entry! ids)))

            );;esac
          );;tel
        );;fi
    x
    )

  (vars-dbg "make-uses" dnl)
  (prepostvisit-stmt prog
                     identity  s-visitor
                     identity x-visitor 
                     identity  identity
                     advance-callback)
  
  tbl
  )


(define (delete-referencing-stmts prog ids)
  ;; delete declarations and assignments to given vars.
  (if (not (null? ids)) (dis "delete-referencing-stmts : " ids dnl))
  
  (define (visitor s)
    (case (get-stmt-type s)
      ((assign)
       (if (member (get-designator-id (get-assign-lhs s)) ids)
           (if (check-side-effects (get-assign-rhs s))
               (begin
                 (dis "delete-referencing-stmts : assign : " s dnl)
                 'skip)
               (begin
                 (dis "delete-referencing-stmts : keeping side-effecting assign : " s dnl)
                 s))
           s))

      ((var1)
       (if (member (get-var1-id s) ids)
           (begin
             (dis "delete-referencing-stmts : var1   : " s dnl)
             'skip
             )
           s))

      ((eval)
       (if (and (eq? 'call-intrinsic (caadr s))
                (eq? 'unpack (cadadr s))
                (member (get-designator-id (caddadr s)) ids))
           (begin
             (dis "delete-referencing-stmts : unpack   : " s dnl)
             'skip
             )
           s)
       )
      
      ((recv)
       (let ((rhs (get-recv-rhs s)))
         (if (and (not (null? rhs))
                  (member (get-designator-id rhs) ids))
             ;;
             ;; we cant delete recvs
             ;; but we can make them "bare" (remove the target var)
             ;;
             (begin
               (dis "delete-referencing-stmts : recv :   " s dnl)
               `(recv ,(get-recv-lhs s) ())
               )
             s)))

      (else s)
      ))

  (visit-stmt prog visitor identity identity)
  )

(define (delete-unused-vars-pass  the-inits prog func-tbl struct-tbl cell-info)
  (let* ((ass-tbl
          (make-assignments-tbl prog cell-info the-inits func-tbl struct-tbl))
         (use-tbl
          (make-uses prog))

         (ass-keys (ass-tbl 'keys))

         (use-keys (use-tbl 'keys))

         (unused-ids (set-diff ass-keys use-keys))

         (result
          (delete-referencing-stmts prog unused-ids)))


          (if (not (null? unused-ids))
              (begin
                (dis "delete-unused-vars-pass  ass-keys   : " ass-keys dnl
                     "delete-unused-vars-pass  use-keys   : " use-keys dnl
                     "delete-unused-vars-pass  unused-ids : " unused-ids dnl)))
          
    result
    )
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (recv? x)(and (pair? x)(eq? 'recv (car x))))
(define (assign? x)(and (pair? x)(eq? 'assign (car x))))

(define gctbw #f)

(define (get-channel-type-bit-width channel-type)
  (set! gctbw channel-type)
  
  (vars-dbg "get-channel-type-bit-width : channel-type : " channel-type dnl)

  (define (err)
    (error "not a channel type I understand : " channel-type))

  (cond ((not (pair? channel-type)) (err))
        
        ((eq? 'channel (car channel-type))
         (if (eq? 'standard.channel.bd (cadr channel-type))
             (caaddr channel-type)
             (err)
             ))

        ((eq? 'array (car channel-type))
         (get-channel-type-bit-width (caddr channel-type)))

        (else (err))))

(define *ar-ass* #f)

(load "bits.scm")
(load "interval.scm")


(define (the-typed-ids)
   (uniq eq?
         (append (*the-dcl-tbl* 'keys)
                 (*the-rng-tbl* 'keys)
                 *the-loop-indices*)))

(define (display-the-ranges)
  (display-tbl *the-rng-tbl* (the-typed-ids)))

(define (display-tbl tbl keys)
  (map
   (lambda(id)
     (dis (pad 40 id) " : " (tbl 'retrieve id) dnl))
   keys)
  'ok
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (make-port-table cell-info)

  (define tbl (make-hash-table 100 atom-hash))
  
  (map (lambda(p)(tbl 'add-entry! (cadr p) p)) 
       (get-ports cell-info))

  tbl

)

(define (get-all-loop-indices prog)
  (map cadr
       (apply append
              (map (lambda(stype)(find-stmts stype prog))
                   '(sequential-loop parallel-loop)))))
  
(define (make-the-tables prog)
  (set! *the-ass-tbl* (make-assignments-tbl
                       prog *cellinfo* *the-inits* '() *the-struct-tbl*))
  (set! *the-use-tbl* (make-uses prog))
  (set! *the-dcl-tbl* (make-intdecls prog))            ;; declared ranges
  (set! *the-arr-tbl* (make-arrdecls prog))            ;; arrays
  (set! *the-rng-tbl* (make-hash-table 100 atom-hash)) ;; derived ranges
  (set! *the-prt-tbl* (make-port-table *cellinfo*))
  (set! *the-loop-indices* (get-all-loop-indices prog))
  (set! *the-global-ranges* (make-global-range-tbl *the-globals*))
  'ok
  )

(load "integer-types.scm")

(define (make-proposed-type-tbl)
  (let ((tbl (make-hash-table 100 atom-hash)))
    (map
     (lambda(id)
       (vars-dbg "proposing smallest type for : " id dnl)
       (tbl 'add-entry! id

            (get-smallest-type
             (*the-rng-tbl* 'retrieve id))))
     (*the-rng-tbl* 'keys))
    tbl
    )
)

(define (propose-types!)
  (set! *proposed-types* (make-proposed-type-tbl))
  (dis "=========  INTEGER TYPES DERIVED :" dnl)
  (display-tbl *proposed-types* (*proposed-types* 'keys))
 )
                         
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (search-uninitialized-uses seq)
  (let loop ((p               (cdr seq))
             (declared        '())
             (assigned        '())
             (used-early      '()))
;;    (dis "visit-sequence loop p : " p dnl)

    (define (get-unassigned stmt)
      (let* ((cur-refs   (find-referenced-vars stmt))
             (unassigned (set-diff cur-refs assigned)))
        unassigned
        )
      )

    (define (make-dummy-assign rhs)
      `(assign (id _dummy) ,rhs)
      )
    
    (cond ((null? p)
           (dis "end of sequence : " dnl
                "declared        : " declared dnl
                "assigned        : " assigned dnl
                "used-early      : " used-early dnl)
           
           ;; a variable is suspicious if it has been used before
           ;; being assigned to or it has been declared but not assigned
           ;; to by end of sequence
           
           (set-diff
            (set-union used-early (set-diff declared assigned))
            '(_dummy))
           )
    

          ((eq? 'var1 (get-stmt-type (car p)))
           (loop (cdr p)
                 (cons (get-var1-id (car p)) declared)
                 assigned
                 used-early))
          
          ((eq? 'assign (get-stmt-type (car p)))
           (let ((unassigned
                  (get-unassigned
                   (make-dummy-assign (get-assign-rhs (car p))))))
             
             (loop (cdr p)
                   declared
                   (cons (get-designator-id (get-assign-lhs (car p))) assigned)
                   (append unassigned used-early))))
          
          ((eq? 'recv (get-stmt-type (car p)))
           (loop (cdr p)
                 declared
                 (cons (get-designator-id (get-recv-rhs (car p))) assigned)
                 used-early))
          
          (else
           ;; any other statement
           (let ((unassigned (get-unassigned (car p))))
             (loop (cdr p)
                   declared
                   assigned
                   
                   (if (null? unassigned)
                       used-early
                       (begin
                         (dis "used early : " unassigned dnl)
                         (append unassigned used-early))
                       );;fi
                   );;pool
             );;*tel
           
           );;esle
          );;dnoc
    );;tel
  );;enifed

(define (initialize-sequence seq vars)
  (let loop ((p       (cdr seq))
             (output '()))
    (cond ((null? p)
           (let ((res (cons 'sequence (reverse output))))
             (dis "initialize-sequence : " (stringify res) dnl)
             res
             )
           )

          ((eq? 'var1 (get-stmt-type (car p)))
           (let ((tgt (get-var1-id   (car p)))
                 (typ (get-var1-type (car p)))
                 )

             (define (default-value) 
               (cond ((string-type? typ)  "")
                     ((integer-type? typ) *big0*)
                     ((boolean-type? typ) #f)
                     (else 'fail)
;;                     (else (error "No default value for type : " typ))
                     );;dnoc
               )
             
             (dis "var1-type : " typ dnl)
             
             (if (member tgt vars)
                 (loop (cdr p)
                       (let ((def (default-value)))
                         (if (eq? def 'fail)
                             (cons (car p) output)
                             
                             (cons `(assign (id ,tgt) ,(default-value))
                                   (cons (car p)
                                         output)))
                         )
                       )

                 (loop (cdr p)
                       (cons (car p) output)));;fi
             );;tel
           )

          (else (loop (cdr p) (cons (car p) output))))))
  
(define (patch-uninitialized-uses prog)

  (define (visit-s s)
    (if (eq? 'sequence (get-stmt-type s))
        (let ((uninit-uses (search-uninitialized-uses s)))
          (if (null? uninit-uses)
              s
              (initialize-sequence s uninit-uses)))
        s))

  (visit-stmt prog visit-s identity identity)
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (make-global-range-tbl global-tbl)
  (define tbl (make-hash-table 100 atom-hash))

  (define (insert-one-range! id)
    (dis "making global range for : " id dnl)
    
    (let ((r
           (apply range-union
                  (map make-point-range ((global-tbl 'retrieve id) 'values)))))
      (tbl 'add-entry! id r)))

  (map insert-one-range! (*the-globals* 'keys))
  tbl
  )


    
