; Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information.
; SPDX-License-Identifier: Apache-2.0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; cspc.scm
;;
;; CSP "compiler" (still in quotes for now)
;;
;; Author : Mika Nystrom <mika.nystroem@intel.com>
;; March, 2025
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; This is the main file of the compiler
;; BUT this is NOT the file you load into your scheme interpreter.
;; Instead, please load "setup.scm" in the same directory.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; The CSP compiler in brief
;; =========================
;;
;; The source language is "Fulcrum-CSP", Fulcrum/Intel's dialect of
;; Martin's Communicating Hardware Processes (CHP) language (Martin
;; 1986).
;; 
;; The target is machine language.  The intermediate form output by
;; this compiler is standard Modula-3 code referencing certain
;; constructs from the Intel m3utils package.  The code generation
;; part is kept in a separate (large) module called codegen-m3.scm to
;; simplify the porting of the compiler to generate another target
;; language, such as ANSI C99.
;;
;;
;; Technical description of the compiler
;; =====================================
;;
;; General strategy: Java has been enhanced to emit scheme-compatible
;; S-expressions.  We parse the S-expressions, convert to the Modula-3
;; objects, convert back to Scheme (the back and forth is mostly a
;; consistency check of our own code.
;;
;; The steps performed are:
;;
;; 1. desugaring
;;    a. x++ and x += c are desugared into x = x + 1 and x = x + c
;;    b. int x=5, y; are desugared to int x; x = 5; int y;
;;
;;    uniquifying block variable names
;;
;;
;; 2. expression sequencing
;;    -- expression sequences need to be constructed for all expressions
;;    -- result should be three-address code (effectively)
;;
;; 3. function inlining
;;    -- functions need to be inlined per Verilog copy-in/copy-out semantics
;; 
;; (repeat steps 2 and 3 until fixed point -- or sequence functions first)
;;
;; 4. type evaluation
;;    -- the type of every three-address operation to be elucidated
;;       (both input and output)
;;
;; 5. block extraction
;;    -- sequential code blocks between suspension points to be computed
;;
;; 6. liveness computation
;;    -- liveness of temporaries to be computed: local to block or
;;       visible across blocks?
;;
;; 7. code generation (see codegen-m3.scm)
;;
;; Many details have been left out above.
;;
;; A good place to start understanding this code is by reviewing the
;; routine compile! below and do-m3! in codegen-m3.scm.  A normal compilation
;; proceeds through three major steps:
;;
;; loaddata!  -- load S-expression from the filesystem
;; compile!   -- run the compiler front-end
;; do-m3!     -- run the compiler back-end (code generator)
;;
;; The expected result is Modula-3 code in a buildable directory, together
;; with an m3makefile.  If your system is set up correctly, the steps after
;; compiling will be
;;
;; cd <build-dir>
;; cm3 -x
;; ../<derived-dir>/sim
;;
;; normally, on an amd64 Linux system, <derived-dir> is AMD64_LINUX
;;
;;
;; PROCESS SUSPENSION AND REACTIVATION
;; ===================================
;;
;; A basic design element is how to deal with suspended processes.
;; A process can suspend in three or four ways:
;;
;; i  - on an if statement (including a "wait" [X] = [X -> skip])
;; 
;; ii - on a receive X?_
;;
;; iii- partial suspension on re-joining after a comma A,B;C
;;
;; iv - sleeping for a "wait(n)" statement (not really suspension)
;;
;; The most interesting and tricky is case i- an if statement.  An
;; if can only be suspended on probes, since there are no global
;; variables shared between processes (other than point-to-point channels).
;; (This is a fundamental design feature of CSP.)
;;
;; (Actually it is not 100% true that we can only suspend on probes.
;; We can also suspenend on bare "Node"s.  This allows, e.g., the
;; implementation of HSE in CSP.  This type of action is not currently
;; supported, but will be soon.  However, it will never be supported
;; in an efficient way.  This is simply not the right way of using CSP.)
;;
;; Since only probes can cause a suspended if to wake up, we can
;; evaluate an if by thinking of it as a fork in the code that, based on
;; the result of evaluating all the guards, picks one branch and executes
;; that or else suspends waiting for another update.  The if is thus
;; registered as the waiter on all the probes that appear in its guards.
;;
;; We can draw the further conclusion from this discussion that an if
;; statement without probes in the guards can be implemented without
;; any suspend/release actions (as a simple if...then...else
;; in the manner of Pascal or C).
;;
;; What remains is to discuss the implementation of "else".  "else" is
;; an addition to CSP made by Fulcrum.  There are three ways of considering
;; implementing else:
;;
;; i   - we could implement else simply as "true" and evaluate the guards
;;       always in textual sequence.  The problem with this is that we
;;       would find it difficult to detect whether guards were multiply
;;       true, if we cared to do that.
;;
;; ii  - we could implement else as a syntactic negation of the disjunction
;;       of all previous guards, but this would be inefficient.
;;
;; iii - we could implement else as its own special expression object.
;;       I think this is the approach we will choose.
;;
;; See the accompanying file selection.txt for more information on ifs,
;; dos.
;;
;;
;; UNDECLARED VARIABLES
;; ====================
;;
;; Undeclared variables appearing anywhere in the process text are
;; treated as if they were declared as signed integers (CSP "int"
;; type) at the beginning of the process (and initialized to zero).
;;
;; There is a trap here regarding the CSP integer types:
;;
;; int     -- infinite-precision, signed integer
;;            (representing a number from Z)
;;
;; int(N)  -- N-bit precision UNSIGNED integer, in the range 0..2^N-1
;;
;; sint(N) -- N-bit precision SIGNED integer in two's complement, in the
;;            range -2^(N-1) .. 2^(N-1) - 1
;;
;; Note that "int" is more like a "sint(N)" than it is like an "int(N)"
;;
;; A key aspect of the CSP language is that N can be any value---wide
;; integers are fully supported by the language.
;;
;;
;; FUNCTION-CALL INLINING
;; ======================
;;
;; Function calls have to be inlined.  This is not just for efficiency,
;; but because functions can block, on sends, receives, and selections.
;;
;; 
;; EXPRESSION UNFOLDING/SEQUENCING
;; ===============================
;;
;; We need to unfold expressions so they can be evaluated sequentially
;; in a form of 3-address code.  This will allow the intermediate types
;; of the expressions to be derived, which is needed for code generation.
;;
;; Expression unfolding is complicated by a few things.
;;
;; 1. It interacts in a nasty way with function calls and function inlining
;;
;; 2. Receive expressions
;;
;; 3. Loop expressions
;;
;;
;; REPRESENTATIONS
;; ===============
;;
;; The Java S-expression generator generates a parse tree basically
;; replicating the Java AST types from the com/avlsi/csp/ast
;; directory.  These types contain quite a bit of syntactic sugar.  We
;; desugar the tree in a seemingly roundabout way: convert the tree to
;; Modula-3 types using the CspAst interface, then dump out a new
;; S-expression by calling the .lisp() method of the CspSyntax
;; interface.  Part of the reason to do this is to avail ourselves of
;; the strict typechecking of Modula-3 but also to allow future,
;; faster implementations, closer to machine language than the very
;; flexible but likely quite slow code that we have here in the Scheme
;; environment.
;;
;;
;; GENERALLY HAIRY STUFF
;; =====================
;;
;; Lots of things, really, but one of the trickiest is the parallel loop
;;
;; <,i:lo..hi: S(i)>;
;;
;; This parallel loop is especially difficult because the amount of
;; parallelism needed for implementation is known only at execution
;; time.  Otherwise, the block structure of the program, including
;; branching and joining of the locus/loci of control, is known at
;; compile time.  But the parallel loop introduces dynamic
;; parallelism, and dynamic memory allocation.
;;
;; Currently, we handle the parallel loop expression simply, through
;; an implementation restriction.  We handle parallel loops ONLY for
;; the cases where lo and hi are known at compile time.  We handle
;; these loops then simply by unrolling (and uniquification of any
;; variables introduced into scopes created inside the loop
;; statement).
;;
;; The sequential loop can be desugared to a regular do loop.  The
;; variable scoping rules imply that the dummy index can be declared
;; locally to the do loop.  Note that this means we need to introduce
;; some sort of block for variable declarations.  Ho hum...
;;
;; Loop expressions can be desugared during expression unfolding.
;;
;; The multiple steps listed above interact in a way that requires
;; them to be called multiple times until a fixpoint is reached, which
;; ought to be the finished program, ready for code generation.
;;
;; Well, let's hope it works!
;;
;; THINGS NOT YET DONE (AS OF 5/22/2025)
;; =====================================
;;
;; 1. Structured channels -- only bd(N) is supported at the moment
;; 2. Interface Nodes (getting the value of, setting the value of, waiting on)
;; 3. Slack directives in the CSP (I don't even know where to find them)
;;
;; END OF TECHNICAL DESCRIPTION
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; the following are the basic Scheme modules we need.

(require-modules "basic-defs" "m3" "hashtable" "set"
                 "display" "symbol-append.scm" "clarify.scm")
(require-modules "fold.scm")

(define sa string-append)
;; we use this a LOT, let's have shorthand  -- it's needed in some modules
;; so we can't move it down

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; component Scheme modules to load:
;; 

(load "pickle.scm")           ;; dump/restore environment
(load "higher-order.scm")     ;; basic higher order functions
(load "name-generator.scm")   ;; name generation
(load "set-ops.scm")          ;; sets of atoms
(load "pp.scm")               ;; pretty printing

;; the following are components of the compiler itself
;; refer to the individual component files for more information 

(load "bigint.scm")
(load "loops.scm")
(load "visit.scm")
(load "simplify.scm")
(load "expr.scm")
(load "analyze.scm")
(load "rename.scm")
(load "expr.scm")
(load "type.scm")
(load "bits.scm")
(load "handle-assign.scm")
(load "clarify.scm")
(load "inline.scm")
(load "symtab.scm")
(load "sensitivity.scm")
(load "selection.scm")          
(load "do.scm")
(load "choose.scm")
(load "dead.scm")  
(load "fold-constants.scm")
(load "vars.scm")
(load "pack.scm")
(load "blocking.scm")
(load "globals.scm")
(load "convert.scm")
(load "ports.scm")
(load "codegen.scm")
(load "comms.scm")
(load "functions.scm")
(load "structs.scm")

(load "codegen-m3.scm")
(load "driver.scm")     ;; main entry point is here
(load "lts.scm")        ;; LTS extraction for formal verification
(load "product.scm")    ;; product LTS composition + deadlock checking
(load "symbolic.scm")   ;; BDD-based symbolic deadlock checking

(define *reload-name*   "cspc.scm")

(define (reload) (load *reload-name*))
;; (reload) reloads the compiler text, useful for compiler development

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; some relevant code from the Java version of the system:
;;
;;            } else if (name.equals("string")) {
;;               preamble.add(createVarStatement(temp, new StringType()));
;;            } else if (name.equals("print") || name.equals("assert") ||
;;                       name.equals("cover") || name.equals("unpack")) {
;;                noReturn = true;
;;            } else if (name.equals("pack")) {
;;                preamble.add(createVarStatement(temp,
;;                                                new TemporaryIntegerType())); 
;;            }
;;
;; also see com/avlsi/csp/util/RefinementResolver.java

(define special-functions     ;; these are special functions per Harry
  '(string
    print
    assert
    cover   // what's this?
    pack
    unpack
    readHexInts
    ;; there are more...
    ))

(define nonblocking-intrinsics
  ;; these are the special functions that cannot block or error out
  '(string print pack unpack readHexInts))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


(define (loadfile reader fn)

  (let* ((p   (open-input-file fn))
         (res (reader    p)))
    (close-input-port p)
    res
    )
  )

(define (load-csp fn)
  (loadfile read-big-int fn)
  )

(define (load-normal fn) (loadfile read fn))

(define (read-importlist fn)
  (load-normal fn)
  )


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; pull apart the structure of a CSP process as generated by the Java
;;

(define (get-funcs       proc) (nth proc 1))
(define (get-structs     proc) (nth proc 2))
(define (get-refparents  proc) (nth proc 3))
(define (get-declparents proc) (nth proc 4))
(define (get-inits       proc) (nth proc 5))
(define (get-text        proc) (nth proc 6))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; close the process
;;
;; this is intended to work on and return the raw, unconverted,
;; not-yet-desugared s-expressions generated by the Java front-end.
;;

(define (close-text proc)
  ;; find the correct program text for this process
  (let loop ((p proc))
    (let ((this-text (get-text p)))
      (if (not (null? this-text))
          this-text
          (car (map loop (get-refparents p)))))))

(define (make-sequence . x)
  (cons 'sequence (filter (filter-not null?) x)))

(define (merge-all getter appender proc)
  ;; recursively merge "something" from my parents and me 
  (let* ((my-stuff (getter proc))
         (my-parents (append (get-declparents proc) (get-refparents proc)))
         (their-stuff (apply appender
                             (map (lambda(p)(merge-all getter appender p))
                                  my-parents))))
    (appender their-stuff my-stuff)))

  
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (atom-hash atom)
  (if (null? atom) (error "atom-hash : null atom")
      (Atom.Hash atom)))

(define (make-object-hash-table elem-namer lst)
  (let ((res (make-hash-table 100 atom-hash)))
    (map (lambda(elem)(res 'add-entry! (elem-namer elem) elem)) lst)
    res
    )
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (loaddata0! . nma)
  ;; this ends up loading the program into *the-text*

  (let  ((nm
          (if (null? nma)
              *the-prog-name*
              (begin 
              
                (set! *the-prog-name* (car nma))
                (car nma)
                )
              )
          )
         )
    (dis dnl "=========  LOADING PARSE TREE FROM " nm " ..." dnl)
    
    (set! *cell*  (load-csp nm))
    (set! *the-proc-type-name* (car *cell*))
    )
  (M3Ident.Escape *the-proc-type-name*)
  )

(define (loaddata1!)
  (set! *data* (cadr *cell*))       ;; the CSP code itself
  (set! *cellinfo* (caddr *cell*))  ;; the CAST ports
  
  (dis "=========  PARSE TREE LOADED SUCCESSFULLY " dnl dnl)
  
  (dis "=========  " *the-proc-type-name* dnl dnl)
  
  (switch-proc! *data*)
  
  (dis   dnl go-grn-bold-term
         "=========  INITIAL SETUP COMPLETE : run (compile!) when ready" dnl
         reset-term dnl)
  (set! text0 *the-text*)
  '*the-text*
  )

(define (loaddata! . nma)
  (apply loaddata0! nma)
  (loaddata1!)
  )

(define xxx #f)

(define *ascii-space* (car (string->list " ")))

(define (pad w . str)
  (Fmt.Pad (apply string-append str) w *ascii-space* 'Left))

(define (padr w . str)
  (Fmt.Pad (apply string-append str) w *ascii-space* 'Right))


(define (print-atomsize sym)
  (dis (pad  23 "Defined " sym) " : " )
  (dis (padr 10 (stringify (count-atoms (eval sym)))) " atoms" dnl))

(define *struct-text* #f)

(define (switch-proc! data)

  (print-atomsize '*data*)
  
  (map
   (lambda (sym)
     (let ((entry
            (apply (eval (symbol-append 'get- sym)) (list data))))
       (dis sym " ")
       (dis (count-atoms entry) " atoms" dnl)
       (eval (list 'set! sym 'entry))
       ))
   '(
;;     refparents
     )
   )
  
  (map
   (lambda (sym)
     (dis (string-append "(length " (symbol->string sym) ") = ")
          (eval (list 'length sym)) dnl))
   '(
     ;;     funcs structs refparents declparents inits text
     )
   )

  (set! *the-structs* (map cadr (merge-all get-structs append data)))

  (print-atomsize '*the-structs*)

  (define struct-text
    `(sequence
       ,@*the-structs*
       ,(close-text data))
    )

  (set! *struct-text* struct-text)
  
  (set! *the-text* (simplify-stmt (desugar-stmt struct-text)))

  (print-atomsize '*the-text*)
  

  (set! *the-funcs* (remove-duplicate-funcs
                      (merge-all get-funcs append data)))

  (print-atomsize '*the-funcs*)

  (set! *the-inits*   (remove-duplicate-inits
                       (simplify-stmt
                        (desugar-stmt
                         (merge-all get-inits make-sequence data)))))

  (print-atomsize '*the-inits*)

  (set! *the-initvars* (find-referenced-vars *the-inits*))

  (set! *the-func-tbl* (make-object-hash-table get-function-name *the-funcs*))

  (dis (*the-func-tbl* 'size) " functions loaded" dnl)
  
  (set! *the-struct-tbl* (make-object-hash-table get-struct-decl-name *the-structs*))

  (dis (*the-struct-tbl* 'size) " struct types loaded" dnl)

;;  (set! lisp0 (desugar-prog data))
;;  (set! lisp1 (simplify-stmt lisp0))

  'ok
    
  )

(define rdips #f)
(define rdi-vars #f)
(define rdi-inits #f)

(define (remove-duplicate-inits init-stmts)
  
  ;; I am doing it this way because the way the system is coded, init
  ;; statements can be inherited from multiple parents, because of
  ;; multiple inheritance of attribute cells.  These means that
  ;; attribute declarations and initializations may be inherited
  ;; through multiple paths and thereby appear multiply.
  
  (let ((vars  (make-symbol-set 100))
        (inits (make-designator-set 10000)))

    (set! rdi-vars vars)
    (set! rdi-inits inits)

    (define (previsitor s)
      (set! rdips s)
      (let ((st (get-stmt-type s)))
        (cond ((eq? st 'var1)
               (if (vars 'member? (get-var1-id s))
                   (begin
                     ;;(dis "delete " s dnl)
                     'delete)
                   (begin (vars 'insert! (get-var1-id s)) s)))
              ((eq? st 'assign)
               (if (inits 'member? (get-assign-designator s))
                   (begin
                     ;;(dis "delete " s dnl)
                     'delete)
                   (begin (inits 'insert! (get-assign-designator s)) s)))

              (else s))))

    (prepostvisit-stmt init-stmts
                       previsitor identity
                       identity   identity
                       identity   identity)

    ))

(define (remove-duplicate-funcs func-list)
  ;; funcs are duplicated (multiplicated) for the same reason that inits are
  (let ((names (make-symbol-set 100)))
    (filter
     (lambda(fd)(not (names 'insert! (get-function-name fd))))
     func-list)))

;; why aren't structs multiplicated?

(define (deep-copy x)
  (if (pair? x)
      (cons (deep-copy (car x)) (deep-copy (cdr x)))
      x))

(define (count-atoms p)
  (cond ((null? p) 0)
        ((pair? p) (+ (count-atoms (car p)) (count-atoms (cdr p))))
        (else 1)))

(define (skip) )

(define (make-var name type)
  (cons name type))

(define (make-var-hash-table size)
  (make-hash-table size (lambda(var)(atom-hash (car var)))))

(define *bad-s* #f)
(define *bad-last* #f)

(define *s* #f)
(define *last* #f)
(define *var-s* #f)

(define (init-seq type)
  (let ((res (obj-method-wrap (new-modula-object type) type)))
    (obj-method-wrap (res 'init 10) type)))

(define *last-var* #f)

(define (get-decl1-id   d) (cadadr d))
(define (get-decl1-type d) (caddr d))
(define (get-decl1-dir  d) (cadddr d))
(define (get-decl1-init d) (caddddr d))
  
(define (check-var1 s)
  (if (not (and (eq? 'var1 (get-stmt-type s)) (eq? 'id (caadadr s))))
      (error "malformed var1 : " s)))

(define (get-var1-decl1 s)
  (check-var1 s)
  (cadr s))

(define (get-var1-id s)
  (get-decl1-id (get-var1-decl1 s)))

(define (get-var1-type s)
  (get-decl1-type (get-var1-decl1 s)))

(define (get-var1-base-type s)
  ;; get the type of the variable declared by s,
  ;; unless it is an array, in which case get the type of the element
  (let ((ty (get-var1-type s)))
    (if (array-type? ty)
        (array-base-type ty)
        ty)
    )
  )

(define (convert-var-stmt s)
  (set! *last-var* s)

  (let ((decls (cadr s))
        (decl  (caadr s)))

    (if (not (= 1 (length decls)))
        (error "convert-var-stmt : need to convert single var decl : " s))

    ;; check whether it's an original declarator and if so if it
    ;; has an initial value
    (let ((var-result     (CspAst.VarStmt (convert-declarator decl)))
          (init-val       (caddddr decl)))

      ;; XXX what we should do here is insert a default initialization,
      ;; for objects that do not have explicit initialization.
      ;;
      ;; that initialization should depend on the type of the object
      ;;
      ;; trivial initialization is used for boolean, int, and string
      ;;
      ;; but (slightly) non-trivial initialization can be used for structs
      ;;
      ;; actually, I think we need to leave the initialization of structs
      ;; for the back-end.  At least that seems the smarter approach at
      ;; the moment.
      ;;
      
      (if (and (eq? (car decl) 'decl) (not (null? init-val)))
          (let ((assign-result
                 (convert-stmt (list 'assign (cadr decl) init-val)))
                (seq (init-seq 'CspStatementSeq.T)))
            (seq 'addhi var-result)
            (seq 'addhi assign-result)
            (CspAst.SequentialStmt (seq '*m3*)))

          var-result
          )
      )
    )
  )

(define (convert-var1-stmt s)
  (let ((decl  (cadr s)))
    (CspAst.VarStmt (convert-declarator decl))
    )
  )

(define (flatten-var-stmt s)
  ;; this desugars the var stmts to var1 stmts
  ;; (one decl per statement)
  (let ((the-sequence 
         (cons 'sequence
               (map
                (lambda(d)(list 'var (list d) (caddr s)))
                (cadr s)))))
    the-sequence
    )
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (check-assign-stmt s)
  (if (or (not (pair? s)) (not (eq? 'assign (car s))))
      (error "check-assign-stmt : not an assign : " s)))

(define *last-assign* #f)

(define (get-assign-designator s)
  (check-assign-stmt s)
  (cadr s))
  
(define (get-assign-id s)
  (set! *last-assign* s)
  (get-designator-id (get-assign-designator s)))

(define (get-assign-lhs a) (cadr a))
(define (get-assign-rhs a) (caddr a))

(define (get-send-lhs a) (cadr a))
(define (get-send-rhs a) (caddr a))

(define (make-send lhs rhs) (list 'send lhs rhs))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (get-assignop-op x) (cadr x))
(define (get-assignop-lhs x) (caddr x))
(define (get-assignop-increment x) (cadddr x))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define *ddd* #f)

(define (designator? x)
  ;; supported designators
  (or (ident? x) (bits? x) (array-access? x) (member-access? x)))

(define (get-designator-id x)
  ;; pull the identifier of the variable being modified out of a designator
  ;; can only be called on a designator
  (set! *ddd* x)
  (cond ((ident?         x)  (cadr x))
        ((bits?          x)  (get-designator-id (cadr x)))
        ((array-access?  x)  (get-designator-id (cadr x)))
        ((member-access? x)  (get-designator-id (cadr x)))
        (else (error "get-designator-id : not a designator : " x))))

(define (get-designator-depend-ids x)
  ;; put out all the identifiers needed to construct the designator,
  ;; other than the lvalue
  (cond ((ident?         x)  '())
        ((bits?          x)  (uniq eq?
                              (append
                               (get-designator-all-ids (caddr x))
                               (get-designator-all-ids (cadddr x)))))
         
        ((array-access?  x)  (get-designator-all-ids (caddr x)))
        ((member-access? x)  '())
        (else '())))

(define (get-designator-all-ids x) 
  ;; pull out all the identifiers used in a designator
  (uniq eq? (find-expr-ids x)))
  
(define (hash-designator d)
  ;; hash a designator
  (cond ((eq? 'id (car d)) (atom-hash (cadr d)))
        ((eq? 'bits (car d)) (atom-hash (cadr d)))
        ((eq? 'array-access (car d))
         (+ (* 2 (hash-designator (cadr d)))
            (if (bigint? (caddr d)) (* 57 (BigInt.ToLongReal (caddr d))) 511)))
        ((eq? 'member-access (car d)) (* 3 (hash-designator (cadr d))))
        (else (error "hash-designator : not done yet"))))

(define (make-designator-hash-table size)
  (make-hash-table size hash-designator))

(define (make-designator-set size)
  (make-set (lambda()(make-designator-hash-table size))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define vs #f)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (get-stmt-type stmt)
  (if (pair? stmt)
      (car stmt)
      'skip))

(define (find-stmt-ids lisp)
  ;; returns ids represented by program as a set-list
  (define ids '())
  
  (define (expr-visitor x)
;;     (dis "expr : " x dnl)

     (if (and (pair? x) (eq? 'id (car x)))
         (if (not (member? (cadr x) ids))
             (set! ids (cons (cadr x) ids))))
     x
  )

  (visit-stmt lisp identity expr-visitor identity)
  ids
  )

(define (find-expr-ids expr)
  (define ids '())
  
  (define (expr-visitor x)
;;     (dis "expr : " x dnl)

     (if (and (pair? x) (eq? 'id (car x)))
         (if (not (member? (cadr x) ids))
             (set! ids (cons (cadr x) ids))))
     x
  )

  (visit-expr expr identity expr-visitor identity)
  ids
  )

(define (find-applys lisp)
  (define applys '())

  (define (expr-visitor x)
;;    (dis (stringify x) dnl)
    (if  (apply? x)
        
        (begin
;;          (dis "found " (stringify x) dnl)
          (set! applys (cons x applys)))
        x)
    )

  (visit-stmt lisp identity expr-visitor identity)
  applys
  )


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define *analyze-result* #f)
(define *unused-globals* #f)
(define *undeclared* #f)

;; we can update the inits to only those that we actually need
(define *filtered-inits* #f)
(define *filtered-initvars* #f)

(define (make-var1 decl) `(var1 ,decl)) 

(define (make-var1-decl sym type)
  ;; vars don't have a direction
;;  (dis "make-var1-decl " type dnl)
  (make-var1 (make-decl sym type 'none)))

(define (make-decl sym type dir)
  `(decl1 (id ,sym) ,type ,dir))

(define *default-int-type*  '(integer #f #f () ()))
(define *const-int-type*  '(integer #t #f () ()))

(define *single-bit-type*  `(integer #f #f ,*big1* ()))

(define (make-default-var1 sym)
  ;; make a default (per CSP rules) variable declaration
  (make-var1 (make-decl sym *default-int-type* 'none)))

(define (predeclare prog undeclared)
   (cons 'sequence (append (map make-default-var1 undeclared) (list prog))))

(define (get-ports cell-info)
  (caddddr cell-info))

(define (get-port-id pdef) (cadr pdef))
  
(define (get-port-ids cell-info)
  (map get-port-id (get-ports cell-info)))

(define (find-var1-stmts lisp)
  (define var1s '())

  (define (stmt-visitor s)
    ;;(dis "stmt : " s dnl)
    
    (if (and (pair? s) (eq? 'var1 (car s)))
        (set! var1s (cons s var1s)))

    s
    )

  (visit-stmt lisp stmt-visitor identity identity)
  var1s
  )


(define (find-loop-indices lisp)
  (define idxs '())

  (define (stmt-visitor s)
    (cond ((member (get-stmt-type s) '(sequential-loop parallel-loop))
           (set! idxs (cons (cadr s) idxs)))

          ((member (get-stmt-type s) '(loop-expression))
           (set! idxs (cons (get-loopex-dummy s) idxs)))

          )
    )

  (visit-stmt lisp stmt-visitor identity identity)

  idxs
  )

(define *stop* #f)

(define uniquify-tg (make-name-generator "uniquify-temp"))

(define (uniquify-one stmt id tg)

  ;; this de-duplicates a multiply declared variable
  ;; by renaming all the instances to unique names
  
  (define (visitor s)
;;    (dis "here" dnl)
    (let ((num-decls (count-declarations id s)))
;;      (dis "num-decls of " id " " num-decls " : " (stringify s) dnl)
      (if (= num-decls 1)
          (cons 'cut
                (rename-id s id (symbol-append id '- (uniquify-tg 'next))))
          s)))

  (if (< (count-declarations id stmt) 2)
      (error "not defined enough times : " id " : in : " stmt))

  (prepostvisit-stmt stmt
                     visitor  identity
                     identity identity
                     identity identity)
)
                     
(define (uniquify-stmt stmt)
  (let ((tg    (make-name-generator "uniq"))
        (names (multi (find-declaration-vars stmt))))
    (let loop ((p names)
               (s stmt))
      (if (null? p)
          s
          (begin
;;            (dis "uniquifying " (car p) dnl)
            (loop (cdr p) (uniquify-one s (car p) tg)))))
    )
  )

(define (filter-unused lisp unused-ids)
  ;; filter out var1 and assign statements from a program
  (dis "filtering unused ids : " unused-ids dnl)
  (define (visitor s)
    (case (get-stmt-kw s)
      ((var1)   (if (member (get-var1-id   s) unused-ids) 'delete s))
      ((assign) (if (member (get-assign-id s) unused-ids) 'delete s))
      (else s))
    )
  (visit-stmt lisp visitor identity identity))

(define (filter-used lisp used-ids)
  ;; filter in var1 and assign statements from a program
  ;; for debugging mainly
  (dis "filtering used ids : " used-ids dnl)
  (define (visitor s)
    (case (get-stmt-kw s)
      ((var1)   (if (member (get-var1-id   s) used-ids) s 'delete))
      ((assign) (if (member (get-assign-id s) used-ids) s 'delete))
      (else s))
    )
  (visit-stmt lisp visitor identity identity))

              
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


(define (get-stmt-kw stmt)
  (if (eq? stmt 'skip)
      'skip
      (if (pair? stmt)

          (let ((res (car stmt)))
            (if (member res '(loop increment decrement var))
                (error "get-stmt-kw : need to desugar : " stmt))
            res)
            
          (error "get-stmt-kw : not a statement : " stmt))))


(define frame-kws
  ;; keywords that introduce a declaration block
  '(
;;    sequence parallel   ;; these do NOT introduce a declaration block
    do if nondet-if nondet-do
       parallel-loop sequential-loop
       loop-expression
       ))




(define *a*     #f)
(define *syms*  #f)

(define *x2* #f)
(define *x3* #f)

(define (ident? x)
  (and (pair? x) (eq? (car x) 'id)))

(define (make-ident sym) (list 'id sym))

(define *rhs* #f)

(define *lhs* #f)

(define (handle-assign-array-rhs a syms tg)
  (let loop ((p   (get-assign-rhs a))
             (res '())
             (seq '())
             )
    (cond ((and (eq? (car p) 'array-access)
                (simple-operand? (caddr p)))
           
           (loop (cdr p) (cons (car p) res))))))



(define sss '())
(define ttt '())


;; (reload)(loaddata! "expressions_p") (run-compiler *the-text* *cellinfo* *the-inits* *the-func-tbl* *the-struct-tbl cell-info*)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define *eval-s* '())
(define *eval-syms* '())

;; some trickery here

(define (if-wrap stmt)
  ;; wrap a statement in (if true) to make it a block
  `(if (#t ,stmt)))

(define ha-a #f)
(define ha-at #f)
(define ha-ft #f)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


(define (find-stmts oftype stmt)
  (let ((res '()))

    (define (visitor s)
      (if (or (eq? oftype s)
              (and (pair? s) (eq? oftype (car s))))
          (begin
            (set! res (cons s res))
            s
            )
          s))
    (visit-stmt stmt visitor identity identity)
    (reverse res)
    )
  )

(define (find-stmt oftype stmt)
  (let ((res #f))

    (define (visitor s)
      (if (or (eq? oftype s)
              (and (pair? s) (eq? oftype (car s))))
          (begin
            (set! res s)
            'cut
            )
          s))
    (visit-stmt stmt visitor identity identity)
    res
    )
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (done-banner)
  (dis go-grn-bold-term (run-command "banner **DONE**") reset-term dnl))

(define (compile-m3! nm)
  (do-compile-m3! nm)
  (done-banner)
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define *retrieve-defn-failed-sym* #f)
(define *retrieve-defn-failed-syms* #f)

(define (retrieve-defn sym syms)
  (let loop ((p syms))
    (if (null? p)
        (begin
          (set! *retrieve-defn-failed-sym* sym)
          (set! *retrieve-defn-failed-syms* syms)
          (error "retrieve-defn : sym not found : " sym)
          )
        
        (let ((this-result ((car p) 'retrieve sym)))
          (if (eq? this-result '*hash-table-search-failed*)
              (loop (cdr p))
              this-result)))))

(define (define-var! syms sym type)
  ((car syms) 'add-entry! sym type)
;;  (dis "define-var! " sym " : " type " /// frame : " ((car syms) 'keys) dnl)
  )

(define (get-symbols syms)
  (apply append (map (lambda(tbl)(tbl 'keys)) syms)))

(define (remove-fake-assignment to stmt)
  ;; change an assignment to "to" back to an eval

  (dis "remove-fake-assignment " to dnl)
  (dis "remove-fake-assignment " (stringify stmt) dnl)

  (define (visitor s)

;;    (dis "visiting " s dnl)
    
    (if (and (eq? (get-stmt-type s) 'assign)
             (ident? (get-assign-lhs s))
             (equal? `(id ,to) (get-assign-lhs s)))

        (let ((res (make-eval (get-assign-rhs s))))
          (dis "replacing " s " -> " res dnl)
          res)
        
        s)
    )
      
  (visit-stmt stmt visitor identity identity)
  
  )

(define (make-assign lhs rhs) `(assign ,lhs ,rhs))

(define (make-eval rhs) `(eval ,rhs))

(define (global-simplify the-inits the-text func-tbl struct-tbl cell-inf)
  (fixpoint-simplify-stmt the-text))

(define (remove-assign-operate the-inits the-text func-tbl struct-tbl cell-info)

  (define (visitor s)
    (if (and (eq? 'assign-operate (get-stmt-type s))
             (check-side-effects (get-assignop-lhs s)))
        (make-assign (get-assignop-lhs s)
                     `(,(get-assignop-op s)
                       ,(get-assignop-lhs s)
                       ,(get-assignop-increment s)))
        s)
    )

  (visit-stmt the-text visitor identity identity)
  )

(define (check-side-effects expr)
  ;; check whether an expression can have side effects
  ;; returns #t if the expression *definitely not* has side effects
  ;; returns #f if the expression *may* have side effects
  (define result #t)

  (define (visitor x)
    (if (pair? x)
        (case (car x)
          ((apply call-intrinsic recv-expression)

           ;; note that peek doesn't have side effects, but it may block

           (set! result #f)))))

  (visit-expr expr identity visitor identity)
  result
  )
  
  
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define nsgs '())

(define (get-guarded-gcs guarded)
  (cdr guarded))

(define (simple-guard? guard)
  (or (eq? 'else guard)
      (simple-operand? guard)))

(define (nonsimple-guards? s)
  (set! nsgs (cons s nsgs))
  ;; an if or do that has non-simple guards

  (let* ((gcs    (get-guarded-gcs s))
         (guards (map car gcs))
         (simple (map simple-guard? guards))
         (all-simple (eval (apply and simple))))
    (not all-simple)
    )
  )

(define (simplify-if the-inits prog func-tbl struct-tbl cell-info)

  (define (visitor s)
    (if (member (get-stmt-type s) '(if nondet-if))
        (make-selection-implementation s func-tbl cell-info)
        s
        )
    )
  
  (visit-stmt prog visitor identity identity)
  )

(define handle-eval-tg (make-name-generator "handle-eval-temp"))

(define (handle-eval s syms vals tg func-tbl struct-tbl cell-info)

  (dis "handle-eval " s dnl)

  (let* ((fake-var (handle-eval-tg 'next))
         (fake-assign (make-assign `(id ,fake-var) (cadr s)))
         (full-seq
          (handle-assign-rhs fake-assign syms vals tg func-tbl struct-tbl cell-info))
         (res (remove-fake-assignment fake-var full-seq)))

    (dis "handle-eval   s = " s dnl
         "handle-eval res = " res dnl)
         
    res
    )
  )

(define (display-success-0)
  (dis go-grn-bold-term
       "******************************************************************************" dnl)
  (dis
   "********************                                      ********************" dnl)
  (dis
   "********************   INITIAL TRANSFORMATIONS COMPLETE   ********************" dnl)
  (dis
   "********************                                      ********************" dnl)
  (dis
   "******************************************************************************" reset-term dnl)
  )

(define (display-success-1)
  (dis go-grn-bold-term
       "******************************************************************************" dnl)
  (dis
   "********************                                      ********************" dnl)
  (dis
   "********************  COMPILER HAS REACHED A FIXED POINT  ********************" dnl)
  (dis
   "********************                                      ********************" dnl)
  (dis
   "********************  !!!!  SYNTAX TRANSFORMATIONS  !!!!  ********************" dnl)
  (dis
   "********************  !!!!        COMPLETE          !!!!  ********************" dnl)
  (dis
   "********************                                      ********************" dnl)
  (dis
   "******************************************************************************" reset-term dnl)
  )

(define (display-success-2)
  (dis go-grn-bold-term
       "******************************************************************************" dnl)
  (dis
   "*******************                                         ******************" dnl)
  (dis
   "*******************  CONSTANT BINDING AND FOLDING COMPLETE  ******************" dnl)
  (dis
   "*******************            (PHASE ONE)                  ******************" dnl)
  (dis
   "*******************                                         ******************" dnl)
  (dis
   "******************************************************************************" reset-term dnl)
  )

(load "passes.scm")

(define *the-pass-results* '())

(define (run-compiler the-passes the-text cell-info the-inits func-tbl struct-tbl)

  ;; n.b. that we can't introduce uniquify-loop-dummies inside here
  ;; because that (and only that) transformation unconditionally changes
  ;; the program.  Maybe we can fix it, but for now our solution is to
  ;; only run that transformation at the outside of the program.
  
  (define syms '())

  (set! *the-pass-results* '())

  (define tg (make-name-generator "passes-temp"))
  
  (set! *a*    '())
  (set! *syms* '())

  (dis dnl "=========  START  =========" dnl dnl) 
  
  (define initvars (find-referenced-vars the-inits))
  ;; should not be repeated over and over... not when we don't change the-inits.

  (dis "analyze program : " dnl)

  (define lisp (analyze-program the-text cell-info initvars))

  ;; (dead-code) went here

    (display-success-0)
  

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


  (define (loop2 prog passes)
    (cond ((null? passes) prog)

          (else
           (loop2
            (let ((the-pass (car passes)))
              (run-pass the-pass prog cell-info the-inits func-tbl struct-tbl)
              )
            (cdr passes)
            ))))

  (let loop ((cur-prog lisp)
             (prev-prog '()))
    (if (equal? cur-prog prev-prog)
        (begin
          (display-success-1)
          cur-prog
          )
        
        (begin  ;; program not equal, must continue
          (dis *program-changed* dnl)
          (loop (loop2 cur-prog the-passes) cur-prog))))
  )

(define (run-pass the-pass prog cell-info the-inits func-tbl struct-tbl)
  (dis "========= COMPILER PASS : " the-pass " ===========" dnl)

  (define syms '())
  (define vals '())

  (define tg (make-name-generator "run-pass-temp"))
  
  (define (enter-frame!)
    (set! syms (cons (make-hash-table 100 atom-hash) syms))
    (set! vals (cons (make-hash-table 100 atom-hash) vals))
;;    (dis "enter-frame! " (length syms) dnl)
    )

  (define (exit-frame!)
    ;;    (dis "exit-frame! " (length syms) " " (map (lambda(tbl)(tbl 'keys)) syms) dnl)

;;    (dis "exit-frame! " (length syms) dnl)
    (set! syms (cdr syms))
    (set! vals (cdr vals))
    )

  (define (stmt-pre0 s)
;;    (dis "pre stmt  : " (stringify s) dnl)
    (stmt-check-enter s)

    (case (get-stmt-kw s)
      ((assign) (handle-assign-rhs s syms vals tg func-tbl struct-tbl cell-info))

      ((eval) ;; this is a function call, we make it a fake assignment.
;;       (dis "eval!" dnl)
       
       (dis "===== stmt-pre0 start " (stringify s) dnl)
       
       (let* ((fake-var (tg 'next))
              (fake-assign (make-assign `(id ,fake-var) (cadr s)))
              (full-seq   (handle-assign-rhs fake-assign syms vals tg func-tbl struct-tbl cell-info))
              (res (remove-fake-assignment fake-var full-seq)))

         (dis "===== stmt-pre0 fake  " (stringify fake-assign) dnl)
         (dis "===== stmt-pre0 full  " (stringify full-seq) dnl)
         (dis "===== stmt-pre0 done  " (stringify res) dnl)
         res
       ))
         

      (else s)
      )
    )

  (define (make-pre stmt-type pass)
    (lambda(stmt)
      ;; this takes a "pass" and wraps it up so the symbol table is maintained
;;      (dis "here!" dnl)
      (stmt-check-enter stmt)
      (if (or (eq? stmt-type '*)
              (eq? stmt-type (get-stmt-kw stmt)))

          (begin
;;            (dis "make-pre stmt-type " stmt-type dnl)
;;            (dis "make-pre stmt      " stmt dnl)
            
            (pass stmt syms vals tg func-tbl struct-tbl cell-info)
            )
          
          stmt)))
  
  (define (stmt-check-enter s)
;;    (dis go-red-bold-term "stmt-check-enter " (if (pair? s) (car s) s) reset-term dnl)
    (if (member (get-stmt-kw s) frame-kws) (enter-frame!))
    (case (get-stmt-kw s)
      ((var1)
;;       (dis "define-var! " (get-var1-id s) dnl)
       (define-var! syms (get-var1-id s) (get-var1-type s))
       )

      ((assign)
       ;; don't handle arrays yet... hmm.
       (if (ident? (get-assign-lhs s))
           (define-var! vals (cadr (get-assign-lhs s)) (get-assign-rhs s)))
       )
      
      ((loop-expression)
       (define-var! syms (get-loopex-dummy s) *default-int-type*)
       )

      ((waiting-if)
       (let ((dummies
              (map get-waiting-if-clause-dummy
                   (get-waiting-if-clauses s))))

         (map (lambda(nm)(define-var! syms nm '(boolean #f))) dummies))
       )

      ((parallel-loop sequential-loop)
;;       (dis "defining loop dummy : " (get-loop-dummy s) dnl)
       (define-var! syms (get-loop-dummy s) *default-int-type*))
         
      )
    )
  
  (define (stmt-post s)
;;    (dis "post stmt : " (get-stmt-kw s) dnl)
    (if (member (get-stmt-kw s) frame-kws) (exit-frame!))
    s
    )

  (let ((pass-result
         (cond  ((eq? 'global (car the-pass))
                 ((cadr the-pass) the-inits prog func-tbl struct-tbl cell-info)
                 )

                (else
                
                 (enter-frame!) ;; global frame
                 
                 ;; record interface objects
                 (let ((ports (caddddr cell-info)))
                   (map (lambda(pd)
                          (let ((pnm (cadr pd)))
;;                            (dis "defining port " pnm " : " pd dnl)
                            (define-var! syms pnm pd)))
                        ports))
                                
                 
                 ;; we should be able to save the globals from earlier...
;;                 (dis "initializations..." dnl)

                 (prepostvisit-stmt 
                  the-inits
                  stmt-pre0 stmt-post
                  identity identity
                  identity identity)
                 
;;                 (dis "program text..." dnl)
;;                 (set! debug #t)
                 
                 (let ((res
                        (prepostvisit-stmt prog
                                           (make-pre
                                            (car the-pass)
                                            (cadr the-pass))        stmt-post
                                            identity                identity
                                            identity                identity)))
                   (exit-frame!)
;;                   (set! debug #f)

                   res))
               
                )
         )
        )

    (set! *the-pass-results*
          (cons
           (list the-pass pass-result)
           *the-pass-results*))
                              
    pass-result
    )
  )

;; Select Graphic Rendition
(define sgr (list->string (list (integer->char 27))))

(define go-grn-bold-term (string-append sgr "[32;1m"))
(define go-red-bold-term (string-append sgr "[31;1m"))
(define reset-term       (string-append sgr "[0m"))

(define *program-changed*
    (string-append
              go-red-bold-term
             "============================  PROGRAM CHANGED"
              reset-term
              ))



(define (write-text sym)
  (let* ((fn (string-append sym ".dmp"))
         (wr (FileWr.Open fn)))
    (dis (stringify (eval sym)) wr)
    (Wr.Close wr)
    )
  )

(define (write-object fn obj)
  (dis "write-object -> " fn dnl)
  (let* ((wr (FileWr.Open fn)))
    (display (stringify obj) wr)
    (Wr.Close wr)
    )
  )

(define (mn) (make-name-generator "t"))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (print-identity x)
  (dis (stringify x) dnl)
  x
  )

(define (identifier? x)
  (if (and (pair? x) (eq? 'id (car x)))) x #f)

(define (binary-expr? x)
  (and
   (pair? x)
   (= 3 (length x))
   (or (unary-op? (car x)) (binary-op? (car x)))))

(define (binary-op? op)
  (case op
    ;; short-circuiting or and and have to be handled separately
    ((+ / % * == != < > >= <= & ^ == << >> ** | ; |
        )
     #t)
    (else #f)))

(define (unary-expr? x)
  (and
   (pair? x)
   (= 2 (length x))
   (unary-op? (car x))))

(define (unary-op? op)
  (case op
    ((not -) #t)
    (else #f)))

(define (apply? x)
  (and (pair? x) (eq? 'apply (car x))))

(define (call-intrinsic? x)
  (and (pair? x) (eq? 'call-intrinsic (car x))))

(define (get-apply-funcname x)
  (cadadr x))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


(define (desugar-stmt stmt)
  ((obj-method-wrap (convert-stmt stmt) 'CspSyntax.T) 'lisp))

(define (desugar-prog p)
  (if (not (and (pair? p) (eq? (car p) 'csp)))
      (error (string-append "Not a CSP program : " p)))

      (desugar-stmt (close-text p))
  )

(define testx '
  (+ (+ (+ (+ (+ (+ (+ (+ (+ (+ (+ (+ (+ "mesh_forward" "a") "b") "a") "c") "b") "a") "c") "b") "a") "c")"b") "a") "c")
  )

