;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; svlint.scm -- Lint checks for SystemVerilog ASTs
;;
;; Author : Claude / Mika Nystroem
;; Date   : March 2026
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; This file implements RTL lint checks on the S-expression ASTs
;; produced by svfe --scm.  It requires svbase.scm to be loaded
;; first (for AST navigation and signal collection).
;;
;; Currently implemented checks:
;;
;;   1. Undriven outputs
;;      Output ports that are never assigned anywhere in the module.
;;
;;   2. Blocking assigns in always_ff
;;      Blocking (=) assignments in sequential blocks, which should
;;      use non-blocking (<=) to avoid simulation/synthesis mismatch.
;;
;;   3. Non-blocking assigns in always_comb
;;      Non-blocking (<=) assignments in combinational blocks, which
;;      should use blocking (=) to model combinational logic.
;;
;; Usage:
;;
;;   > (load "sv/src/svbase.scm")
;;   > (load "sv/src/svlint.scm")
;;   > (define ast (read-sv-file "/tmp/mymodule_ast.scm"))
;;   > (lint-all ast)
;;   === Module: mymodule ===
;;     WARNING: output 'foo' is never driven
;;     Ports: 8 (in: 5 out: 3)
;;     Local signals: 12
;;     Assigned signals: 14
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; ASSIGNMENT TYPE CHECKING
;;
;; SystemVerilog has strict rules about which assignment types are
;; allowed in which contexts:
;;
;;   always_ff    : only non-blocking (<=) assignments
;;   always_comb  : only blocking (=) assignments
;;   always_latch : only blocking (=) assignments
;;
;; Using the wrong type is a common RTL bug:
;;   - Blocking in always_ff can cause simulation/synthesis mismatch
;;   - Non-blocking in always_comb creates unintended latches
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (find-blocking-in-stmt stmt) -- find signals with blocking (=)
;; assignments in a statement tree.  Used to check always_ff blocks,
;; where only non-blocking (<=) should be used.
;;
;; Returns a list of signal name symbols.
(define (find-blocking-in-stmt stmt)
  (cond
    ((not (pair? stmt)) '())
    ;; Found a blocking assign -- this is the violation
    ((eq? '= (car stmt))
     (lvalue-signals (cadr stmt)))
    ;; Non-blocking is correct in always_ff, skip it
    ((eq? '<= (car stmt)) '())
    ((eq? 'begin (car stmt))
     (sv-append-all
      (map find-blocking-in-stmt (begin-stmts stmt))))
    ((eq? 'if (car stmt))
     (append (find-blocking-in-stmt (caddr stmt))
             (if (> (length stmt) 3)
                 (find-blocking-in-stmt (cadddr stmt))
                 '())))
    ((memq (car stmt) '(case casez casex))
     (sv-append-all (map (lambda (ci)
                           (if (and (pair? ci) (> (length ci) 1))
                               (find-blocking-in-stmt (cadr ci))
                               '()))
                         (cddr stmt))))
    ((eq? 'for (car stmt))
     (find-blocking-in-stmt (sv-last stmt)))
    (else '())))

;; (find-nonblocking-in-stmt stmt) -- find signals with non-blocking
;; (<=) assignments in a statement tree.  Used to check always_comb
;; blocks, where only blocking (=) should be used.
;;
;; Returns a list of signal name symbols.
(define (find-nonblocking-in-stmt stmt)
  (cond
    ((not (pair? stmt)) '())
    ;; Found a non-blocking assign -- this is the violation
    ((eq? '<= (car stmt))
     (lvalue-signals (cadr stmt)))
    ;; Blocking is correct in always_comb, skip it
    ((eq? '= (car stmt)) '())
    ((eq? 'begin (car stmt))
     (sv-append-all
      (map find-nonblocking-in-stmt (begin-stmts stmt))))
    ((eq? 'if (car stmt))
     (append (find-nonblocking-in-stmt (caddr stmt))
             (if (> (length stmt) 3)
                 (find-nonblocking-in-stmt (cadddr stmt))
                 '())))
    ((memq (car stmt) '(case casez casex))
     (sv-append-all (map (lambda (ci)
                           (if (and (pair? ci) (> (length ci) 1))
                               (find-nonblocking-in-stmt (cadr ci))
                               '()))
                         (cddr stmt))))
    ((eq? 'for (car stmt))
     (find-nonblocking-in-stmt (sv-last stmt)))
    (else '())))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; LINT DRIVER
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (lint-module mod) -- run all lint checks on a single module.
;; Prints warnings and a summary to standard output.
(define (lint-module mod)
  (define name    (module-name mod))
  (define ports   (collect-port-signals (module-ports mod)))
  (define body    (module-body-items mod))
  (define decls   (collect-decl-signals body))
  (define assigns (collect-all-assigns  body))
  (define outputs (sv-filter (lambda (p) (eq? 'output (car p))) ports))
  (define inputs  (sv-filter (lambda (p) (eq? 'input (car p))) ports))

  (displayln "=== Module: " (symbol->string name) " ===")

  ;; Check 1: undriven outputs
  (for-each
   (lambda (o)
     (if (not (member (cadr o) assigns))
         (displayln "  WARNING: output '"
                    (symbol->string (cadr o))
                    "' is never driven")))
   outputs)

  ;; Check 2: blocking assigns in always_ff
  (for-each
   (lambda (item)
     (if (and (pair? item) (eq? 'always_ff (car item)))
         (for-each
          (lambda (sig)
            (displayln "  WARNING: blocking assign to '"
                       (symbol->string sig)
                       "' in always_ff"))
          (sv-delete-dups (find-blocking-in-stmt (sv-last item))))))
   body)

  ;; Check 3: non-blocking assigns in always_comb
  (for-each
   (lambda (item)
     (if (and (pair? item) (eq? 'always_comb (car item)))
         (for-each
          (lambda (sig)
            (displayln "  WARNING: non-blocking assign to '"
                       (symbol->string sig)
                       "' in always_comb"))
          (sv-delete-dups (find-nonblocking-in-stmt (sv-last item))))))
   body)

  ;; Summary
  (displayln "  Ports: " (number->string (length ports))
             " (in: " (number->string (length inputs))
             " out: " (number->string (length outputs)) ")")
  (displayln "  Local signals: " (number->string (length decls)))
  (displayln "  Assigned signals: " (number->string (length assigns))))

;; (lint-all nodes) -- run lint checks on all top-level AST nodes.
;; Handles modules, packages, and interfaces.
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
