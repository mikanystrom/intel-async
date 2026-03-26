; Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information.
; SPDX-License-Identifier: Apache-2.0


(require-modules "basic-defs" "m3" "hashtable" "set" "display")


(define *m3utils*   (Env.Get "M3UTILS"))
(define *pkg-path*  "csp/src"          )

(set! **scheme-load-path** (cons (string-append *m3utils* "/" *pkg-path*)
                                 **scheme-load-path**))



;; BigInt initialization check removed -- using native exact integers

(define debug #f)

;; this stuff is really experimental.
(define *cell*        '())

(define *data*        '())
(define *cellinfo*    '())

(define funcs       '())
(define structs     '())
(define refparents  '())

(define declparents '()) ;; this is a special thing for env blocks

(define inits       '())
(define text        '())

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define *the-proc-type-name* #f)
(define *the-text*           #f)
(define *the-structs*        #f)
(define *the-funcs*          #f)
(define *the-inits*          #f)
(define *the-initvars*       #f)

(define *the-func-tbl*       #f)
(define *the-struct-tbl*     #f)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(dis dnl "=====  LOADING COMPILER ..." dnl dnl)
(load "cspc.scm")
(dis dnl "=====  COMPILER LOADED." dnl dnl)

(define setup-loaded #t)

;;(loaddata! "arrays_p1")
;;(loaddata! "functions_p00")


(define a 12)

;;(define csp (obj-method-wrap (convert-prog data) 'CspSyntax.T))

(define (do-analyze)
   (analyze-program lisp1 *cellinfo* *the-initvars*))


;; (reload)(loaddata! "castdecl_q")
;; (try-it *the-text* *cellinfo* *the-inits*)

(set-rt-error-mapping! #f)

(set-warnings-are-errors! #t)

(define lisp0 #f)
(define lisp1 #f)

;;(loaddata! *the-example*)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(if #f (begin
(define lispm1 (close-text *data*))
(define lisp0 (desugar-prog *data*))

(define lisp1 (simplify-stmt lisp0))

(define lisp2 (simplify-stmt
               ((obj-method-wrap (convert-stmt lisp1) 'CspSyntax.T) 'lisp)))

(define lisp3 (simplify-stmt
               ((obj-method-wrap (convert-stmt lisp2) 'CspSyntax.T) 'lisp)))

(define lisp4 (simplify-stmt
               ((obj-method-wrap (convert-stmt lisp3) 'CspSyntax.T) 'lisp)))

(if (not (equal? lisp1 lisp4)) (error "lisp1 and lisp4 differ!"))
))

;; (define b36 (BigInt.New 36))
;; (filter (lambda(s)(and (eq? 'SUPERSET (get-designator-id s)) (BigInt.Equal b36 (caddadr s)) (BigInt.Equal b15 (caddr s)))) z)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define *the-prog-name* #f)
(define inits1 #f)
(define text0 #f)
(define text1 #f)
(define text2 #f)
(define text3 #f)
(define text4 #f)
(define text5 #f)
(define text5.1 #f)
(define text5.2 #f)
(define text6 #f)
(define text7 #f)
(define text8 #f)
(define text9 #f)
(define text10 #f)

(define *the-ass-tbl* #f)
(define *the-use-tbl* #f)
(define *the-dcl-tbl* #f) ;; declared base types (arrays peeled)
(define *the-arr-tbl* #f) ;; declared array types
(define *the-prt-tbl* #f)
(define *the-rng-tbl* #f)
(define *the-loop-indices* #f)
(define *proposed-types* #f)

(define *the-globals* #f)
(define *the-global-ranges* #f)

(define *the-struct-decls* #f)

;; back-end data structures
(define *proc-context* #f)
(define *stage* #f)

(dis "  ===  TO RUN COMPILER: " dnl)
(dis "  ===  (loaddata! <csp-prefix>)" dnl)
(dis "  ===  (compile!)" dnl)
(dis dnl)
(dis "  ===  TO BUILD A PROCESS GRAPH: " dnl)
(dis "  ===  (drive! <procs-prefix>)" dnl)
(dis dnl dnl dnl)


(define *ai* #f)

