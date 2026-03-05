;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; svread.scm -- Read and analyze SystemVerilog S-expression output
;;
;; Usage:
;;   svfe --scm file.sv > /tmp/out.scm
;;   mscheme:  (load "svread.scm")
;;             (define ast (read-sv-file "/tmp/out.scm"))
;;             (lint-all ast)
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Utility: display with newline
(define (displayln . args)
  (for-each display args)
  (newline))

;; Utility: filter
(define (sv-filter pred lst)
  (cond
    ((null? lst) '())
    ((pred (car lst)) (cons (car lst) (sv-filter pred (cdr lst))))
    (else (sv-filter pred (cdr lst)))))

;; Utility: delete duplicates
(define (sv-delete-dups lst)
  (cond
    ((null? lst) '())
    ((member (car lst) (cdr lst)) (sv-delete-dups (cdr lst)))
    (else (cons (car lst) (sv-delete-dups (cdr lst))))))

;; Utility: last element
(define (sv-last lst)
  (if (null? (cdr lst)) (car lst) (sv-last (cdr lst))))

;; Utility: flatten one level
(define (sv-append-all lsts)
  (apply append lsts))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; File I/O
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (read-all port)
  (define result '())
  (define (loop)
    (define expr (read port))
    (if (eof-object? expr)
        (reverse result)
        (begin (set! result (cons expr result))
               (loop))))
  (loop))

(define (read-sv-file filename)
  (define port (open-input-file filename))
  (define result (read-all port))
  (close-input-port port)
  result)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; AST predicates
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (sv-module? node)
  (and (pair? node) (eq? 'module (car node))))

(define (sv-package? node)
  (and (pair? node) (eq? 'package (car node))))

(define (sv-interface? node)
  (and (pair? node) (eq? 'interface (car node))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Signal collection from ports
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (find-id-in-list lst)
  ;; Find the first (id ...) form in a list
  (cond
    ((null? lst) #f)
    ((and (pair? (car lst)) (eq? 'id (caar lst))) (car lst))
    (else (find-id-in-list (cdr lst)))))

(define (collect-port-signals ports)
  (if (not (and (pair? ports) (eq? 'ports (car ports))))
      '()
      (sv-filter pair?
        (map (lambda (p)
               (if (and (pair? p) (eq? 'port (car p)))
                   (let ((id-form (find-id-in-list (cddr p))))
                     (if id-form
                         (list (cadr p) (cadr id-form))
                         #f))
                   #f))
             (cdr ports)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Signal collection from declarations
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (collect-decl-signals body)
  (define result '())
  (for-each
   (lambda (item)
     (if (and (pair? item) (eq? 'decl (car item)))
         (for-each
          (lambda (x)
            (if (and (pair? x) (eq? 'id (car x)))
                (set! result (cons (list 'local (cadr x)) result))))
          (cddr item))))
   body)
  (reverse result))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Assignment collection
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (lvalue-signals lv)
  (cond
    ((not (pair? lv)) '())
    ((eq? 'id (car lv)) (list (cadr lv)))
    ((eq? 'concat (car lv))
     (sv-append-all (map lvalue-signals (cdr lv))))
    (else
     ;; index, range, member etc -- recurse on second element
     (if (> (length lv) 1)
         (lvalue-signals (cadr lv))
         '()))))

(define (collect-assigns-in-stmt stmt)
  (cond
    ((not (pair? stmt)) '())
    ((eq? '= (car stmt))
     (lvalue-signals (cadr stmt)))
    ((eq? '<= (car stmt))
     (lvalue-signals (cadr stmt)))
    ((eq? 'begin (car stmt))
     ;; skip optional block name (symbol) if present
     (sv-append-all (map collect-assigns-in-stmt
                         (if (and (pair? (cdr stmt)) (symbol? (cadr stmt)))
                             (cddr stmt)
                             (cdr stmt)))))
    ((eq? 'if (car stmt))
     (append (collect-assigns-in-stmt (caddr stmt))
             (if (> (length stmt) 3)
                 (collect-assigns-in-stmt (cadddr stmt))
                 '())))
    ((eq? 'case (car stmt))
     (sv-append-all (map collect-assigns-case-item (cddr stmt))))
    ((eq? 'casez (car stmt))
     (sv-append-all (map collect-assigns-case-item (cddr stmt))))
    ((eq? 'for (car stmt))
     (collect-assigns-in-stmt (sv-last stmt)))
    (else '())))

(define (collect-assigns-case-item ci)
  (if (and (pair? ci) (> (length ci) 1))
      (collect-assigns-in-stmt (cadr ci))
      '()))

(define (collect-all-assigns body)
  (define result '())
  (for-each
   (lambda (item)
     (cond
       ((and (pair? item) (eq? 'assign (car item)))
        (set! result (append (lvalue-signals (cadr (cadr item))) result)))
       ((and (pair? item)
             (memq (car item) '(always_ff always_comb always_latch always)))
        (set! result (append (collect-assigns-in-stmt (sv-last item)) result)))))
   body)
  (sv-delete-dups result))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Lint checks
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Find a tagged form in a list by its car symbol
(define (find-tagged tag lst)
  (cond
    ((null? lst) #f)
    ((and (pair? (car lst)) (eq? tag (caar lst))) (car lst))
    (else (find-tagged tag (cdr lst)))))

;; Get module body items (everything after ports)
(define (module-body-items mod)
  (define (skip-headers lst)
    (cond
      ((null? lst) '())
      ((and (pair? (car lst))
            (memq (caar lst) '(parameters ports import)))
       (skip-headers (cdr lst)))
      ((symbol? (car lst)) (skip-headers (cdr lst))) ;; skip name
      (else lst)))
  (skip-headers (cdr mod)))

(define (lint-module mod)
  (define name    (cadr mod))
  (define ports   (collect-port-signals (find-tagged 'ports (cdr mod))))
  (define body    (module-body-items mod))
  (define decls   (collect-decl-signals body))
  (define assigns (collect-all-assigns  body))
  (define outputs (sv-filter (lambda (p) (eq? 'output (car p))) ports))
  (define inputs  (sv-filter (lambda (p) (eq? 'input (car p))) ports))

  (displayln "=== Module: " (symbol->string name) " ===")

  ;; Check for undriven outputs
  (for-each
   (lambda (o)
     (if (not (member (cadr o) assigns))
         (displayln "  WARNING: output '"
                    (symbol->string (cadr o))
                    "' is never driven")))
   outputs)

  ;; Report signal counts
  (displayln "  Ports: " (number->string (length ports))
             " (in: " (number->string (length inputs))
             " out: " (number->string (length outputs)) ")")
  (displayln "  Local signals: " (number->string (length decls)))
  (displayln "  Assigned signals: " (number->string (length assigns))))

(define (lint-all nodes)
  (for-each
   (lambda (node)
     (cond
       ((sv-module? node)    (lint-module node))
       ((sv-package? node)
        (displayln "=== Package: " (symbol->string (cadr node)) " ==="))
       ((sv-interface? node)
        (displayln "=== Interface: " (symbol->string (cadr node)) " ==="))))
   nodes))
