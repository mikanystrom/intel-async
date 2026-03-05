;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; svread.scm -- Read and analyze SystemVerilog S-expression ASTs
;;
;; Author : Claude / Mika Nystroem
;; Date   : March 2026
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; This file provides the Scheme side of the svfe pipeline:
;;
;;   SystemVerilog source (.sv)
;;     --> svfe --scm     (Modula-3/parserlib parser)
;;     --> S-expressions  (one per top-level construct)
;;     --> this file      (read, analyze, lint)
;;
;; The S-expression format is defined by svParseExt.e and mirrors
;; the grammar in sv.y.  The top-level forms are:
;;
;;   (module <name> [<imports>...] <params> <ports> <body-items>...)
;;   (package <name> <items>...)
;;   (interface <name> <params> <ports> <items>...)
;;   (typedef ...)
;;   (import ...)
;;
;; Within a module body, items include:
;;
;;   (decl <type> (id <name> [<dims>]) ...)   -- signal declarations
;;   (assign (= <lvalue> <expr>))             -- continuous assigns
;;   (always_ff  <sens> <stmt>)               -- sequential blocks
;;   (always_comb <stmt>)                     -- combinational blocks
;;   (always_latch <sens> <stmt>)             -- latch blocks
;;   (generate ...)                           -- generate regions
;;   (ident-item <type> <inst> ...)           -- module instantiations
;;   (function ...)                           -- function declarations
;;   (directive)                              -- compiler directives
;;
;; Statements are:
;;
;;   (= <lvalue> <expr>)                      -- blocking assign
;;   (<= <lvalue> <expr>)                     -- non-blocking assign
;;   (begin [<name>] <stmts>...)              -- sequential block
;;   (if <cond> <then> [<else>])              -- conditional
;;   (case <expr> (<match> <stmt>)...)        -- case/casez/casex
;;   (for <init> <cond> <step> <body>)        -- for loop
;;   (null)                                   -- empty statement
;;   (directive)                              -- compiler directive
;;
;; Expressions use prefix notation with these node types:
;;
;;   (id <name>)                              -- identifier
;;   <number-literal>                         -- e.g. 8'hFF, 32'd0
;;   (+ <a> <b>), (- <a> <b>), ...           -- arithmetic
;;   (== <a> <b>), (!= <a> <b>), ...         -- comparison
;;   (&& <a> <b>), (|| <a> <b>)              -- logical
;;   (& <a> <b>), (| <a> <b>), ...           -- bitwise
;;   (<< <a> <b>), (>> <a> <b>)              -- shift
;;   (?: <cond> <then> <else>)               -- ternary
;;   (~ <a>), (! <a>)                        -- unary
;;   (index <expr> <idx>)                    -- bit/array select
;;   (range <expr> <hi> <lo>)                -- part select
;;   (+: <expr> <base> <width>)              -- ascending part select
;;   (-: <expr> <base> <width>)              -- descending part select
;;   (field <expr> <member>)                 -- struct member access
;;   (concat <exprs>...)                     -- concatenation
;;   (replicate <count> <exprs>...)          -- replication
;;   (call <func> <args>...)                 -- function call
;;   (sys <name>)                            -- system function ($clog2 etc)
;;
;; Lvalues use the same (id ...), (index ...), (range ...),
;; (field ...), (concat ...) forms as expressions.
;;
;;
;; Usage with mscheme
;; ==================
;;
;; Generate the AST from a SystemVerilog file:
;;
;;   $ svfe --scm mymodule.sv > /tmp/mymodule_ast.scm
;;
;; Then in mscheme:
;;
;;   > (load "sv/src/svread.scm")
;;   > (define ast (read-sv-file "/tmp/mymodule_ast.scm"))
;;   > (lint-all ast)
;;   === Module: mymodule ===
;;     Ports: 8 (in: 5 out: 3)
;;     Local signals: 12
;;     Assigned signals: 14
;;
;; The AST is a plain Scheme list and can be traversed with standard
;; list operations (car, cdr, map, etc.).  For example:
;;
;;   > (define mod (car ast))           ;; first top-level form
;;   > (cadr mod)                       ;; module name (symbol)
;;   > (find-tagged 'ports (cdr mod))   ;; the (ports ...) form
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; 1. UTILITY FUNCTIONS
;;
;; These are basic list utilities that may not be available in all
;; Scheme implementations.  Prefixed with sv- to avoid name clashes.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (displayln arg ...) -- display all arguments followed by a newline.
;; mscheme does not interpret \n in strings, so we use (newline).
(define (displayln . args)
  (for-each display args)
  (newline))

;; (sv-filter pred lst) -- return elements of lst for which pred is true.
(define (sv-filter pred lst)
  (cond
    ((null? lst) '())
    ((pred (car lst)) (cons (car lst) (sv-filter pred (cdr lst))))
    (else (sv-filter pred (cdr lst)))))

;; (sv-delete-dups lst) -- remove duplicate elements (keeps last occurrence).
(define (sv-delete-dups lst)
  (cond
    ((null? lst) '())
    ((member (car lst) (cdr lst)) (sv-delete-dups (cdr lst)))
    (else (cons (car lst) (sv-delete-dups (cdr lst))))))

;; (sv-last lst) -- return the last element of a non-empty list.
(define (sv-last lst)
  (if (null? (cdr lst)) (car lst) (sv-last (cdr lst))))

;; (sv-append-all list-of-lists) -- concatenate a list of lists.
(define (sv-append-all lsts)
  (apply append lsts))

;; (find-tagged tag lst) -- find the first element whose car is TAG.
;; Returns the element or #f if not found.
;;
;; Example: (find-tagged 'ports '((parameters ...) (ports ...) ...))
;;          => (ports ...)
(define (find-tagged tag lst)
  (cond
    ((null? lst) #f)
    ((and (pair? (car lst)) (eq? tag (caar lst))) (car lst))
    (else (find-tagged tag (cdr lst)))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; 2. FILE I/O
;;
;; Read S-expressions from files.  The svfe parser emits one
;; S-expression per top-level construct (module, package, etc.)
;; so a typical file produces a list of several forms.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (read-all port) -- read all S-expressions from PORT until EOF.
;; Returns a list of the forms read, in order.
(define (read-all port)
  (define result '())
  (define (loop)
    (define expr (read port))
    (if (eof-object? expr)
        (reverse result)
        (begin (set! result (cons expr result))
               (loop))))
  (loop))

;; (read-sv-file filename) -- read all S-expressions from a file.
;; This is the main entry point for loading svfe output.
;;
;; Example: (define ast (read-sv-file "/tmp/mymodule_ast.scm"))
(define (read-sv-file filename)
  (define port (open-input-file filename))
  (define result (read-all port))
  (close-input-port port)
  result)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; 3. AST PREDICATES
;;
;; Recognize top-level constructs by their leading tag symbol.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (sv-module? node)
  (and (pair? node) (eq? 'module (car node))))

(define (sv-package? node)
  (and (pair? node) (eq? 'package (car node))))

(define (sv-interface? node)
  (and (pair? node) (eq? 'interface (car node))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; 4. AST NAVIGATION
;;
;; The module S-expression layout is:
;;
;;   (module <name> [<import>...] [<parameters>] [<ports>] <body>...)
;;
;; The header elements (imports, parameters, ports) are tagged forms
;; and can appear in varying order.  The body items follow after all
;; headers and are the "real content" of the module.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (module-body-items mod) -- extract the body items from a module,
;; skipping the name, imports, parameters, and ports header forms.
(define (module-body-items mod)
  (define (skip-headers lst)
    (cond
      ((null? lst) '())
      ;; Skip tagged header forms
      ((and (pair? (car lst))
            (memq (caar lst) '(parameters ports import)))
       (skip-headers (cdr lst)))
      ;; Skip bare symbols (the module name)
      ((symbol? (car lst)) (skip-headers (cdr lst)))
      ;; Everything else is body
      (else lst)))
  (skip-headers (cdr mod)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; 5. SIGNAL COLLECTION -- PORTS
;;
;; Port declarations in the AST look like:
;;
;;   (ports
;;     (port input logic [7:0] (id clk))
;;     (port output logic      (id dout [3:0]))
;;     (port-ident b)                             ;; inherited type
;;     (port-if axi_if.slave (id s))              ;; interface port
;;     ...)
;;
;; We extract (direction name) pairs from (port ...) forms.
;; The (port-ident ...) and (port-if ...) forms are not yet handled
;; since they require type propagation from the preceding port.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (find-id-in-list lst) -- find the first (id ...) form in a list.
;; Used to locate the signal name within a port declaration that
;; contains type qualifiers, dimensions, etc. before the identifier.
(define (find-id-in-list lst)
  (cond
    ((null? lst) #f)
    ((and (pair? (car lst)) (eq? 'id (caar lst))) (car lst))
    (else (find-id-in-list (cdr lst)))))

;; (collect-port-signals ports-form) -- extract (direction name) pairs
;; from a (ports ...) AST node.
;;
;; Returns a list of two-element lists: ((input clk) (output dout) ...)
;; Only handles (port dir type ... (id name)) forms; port-ident and
;; port-if are silently skipped.
(define (collect-port-signals ports)
  (if (not (and (pair? ports) (eq? 'ports (car ports))))
      '()
      (sv-filter pair?
        (map (lambda (p)
               (if (and (pair? p) (eq? 'port (car p)))
                   ;; (port direction type ... (id name dims))
                   ;; direction is (cadr p), (id ...) is somewhere in (cddr p)
                   (let ((id-form (find-id-in-list (cddr p))))
                     (if id-form
                         (list (cadr p) (cadr id-form))
                         #f))
                   #f))
             (cdr ports)))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; 6. SIGNAL COLLECTION -- DECLARATIONS
;;
;; Local declarations in the module body look like:
;;
;;   (decl (logic [7:0]) (id data_q) (id data_d))
;;   (decl wire [3:0]    (id addr))
;;
;; We scan for (id <name>) forms within (decl ...) items.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (collect-decl-signals body) -- extract (local name) pairs from
;; all (decl ...) items in a module body.
(define (collect-decl-signals body)
  (define result '())
  (for-each
   (lambda (item)
     (if (and (pair? item) (eq? 'decl (car item)))
         ;; Each (id name [dims]) after the type is a declared signal
         (for-each
          (lambda (x)
            (if (and (pair? x) (eq? 'id (car x)))
                (set! result (cons (list 'local (cadr x)) result))))
          (cddr item))))
   body)
  (reverse result))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; 7. SIGNAL COLLECTION -- ASSIGNMENTS
;;
;; To check for undriven signals, we need to find every signal name
;; that appears on the left-hand side of an assignment, anywhere in
;; the module.  This includes:
;;
;;   - Continuous assigns:  (assign (= <lvalue> <expr>))
;;   - Blocking assigns:    (= <lvalue> <expr>)     in always_comb
;;   - Non-blocking assigns: (<= <lvalue> <expr>)   in always_ff
;;
;; Lvalues can be:
;;   (id name)                  -- simple signal
;;   (index lv idx)             -- bit/array select: x[i]
;;   (range lv hi lo)           -- part select: x[7:0]
;;   (field lv member)          -- struct member: x.data
;;   (concat lv1 lv2 ...)       -- concatenation: {a, b}
;;
;; We recursively extract the base signal name(s) from any lvalue.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (lvalue-signals lv) -- extract base signal names from an lvalue.
;; Returns a list of symbols.
;;
;; For (id foo)           => (foo)
;; For (index (id x) i)   => (x)
;; For (concat (id a) (id b)) => (a b)
(define (lvalue-signals lv)
  (cond
    ((not (pair? lv)) '())
    ((eq? 'id (car lv)) (list (cadr lv)))
    ((eq? 'concat (car lv))
     (sv-append-all (map lvalue-signals (cdr lv))))
    (else
     ;; index, range, field, +: , -: etc. -- the base lvalue
     ;; is always the second element (first argument)
     (if (> (length lv) 1)
         (lvalue-signals (cadr lv))
         '()))))

;; (begin-stmts stmt) -- return the list of sub-statements from
;; a begin block, handling the optional block name.
;;
;; The S-expression for begin blocks is either:
;;   (begin <stmt1> <stmt2> ...)          -- no block name
;;   (begin <name> <stmt1> <stmt2> ...)   -- with block name
;;
;; We detect the named form by checking if (cadr stmt) is a symbol.
(define (begin-stmts stmt)
  (if (and (pair? (cdr stmt)) (symbol? (cadr stmt)))
      (cddr stmt)
      (cdr stmt)))

;; (collect-assigns-in-stmt stmt) -- recursively find all signal names
;; assigned (blocking or non-blocking) within a statement.
;; Returns a list of symbols (may contain duplicates).
(define (collect-assigns-in-stmt stmt)
  (cond
    ((not (pair? stmt)) '())
    ;; Blocking assign: (= <lvalue> <expr>)
    ((eq? '= (car stmt))
     (lvalue-signals (cadr stmt)))
    ;; Non-blocking assign: (<= <lvalue> <expr>)
    ((eq? '<= (car stmt))
     (lvalue-signals (cadr stmt)))
    ;; Sequential block: (begin [name] <stmts>...)
    ((eq? 'begin (car stmt))
     (sv-append-all (map collect-assigns-in-stmt (begin-stmts stmt))))
    ;; Conditional: (if <cond> <then> [<else>])
    ((eq? 'if (car stmt))
     (append (collect-assigns-in-stmt (caddr stmt))
             (if (> (length stmt) 3)
                 (collect-assigns-in-stmt (cadddr stmt))
                 '())))
    ;; Case statements: (case <expr> (<match> <stmt>) ...)
    ((memq (car stmt) '(case casez casex))
     (sv-append-all (map collect-assigns-case-item (cddr stmt))))
    ;; For loop: (for <init> <cond> <step> <body>)
    ((eq? 'for (car stmt))
     (collect-assigns-in-stmt (sv-last stmt)))
    (else '())))

;; (collect-assigns-case-item ci) -- extract assigned signals from
;; one case item.  A case item is (<match-expr> <statement>).
(define (collect-assigns-case-item ci)
  (if (and (pair? ci) (> (length ci) 1))
      (collect-assigns-in-stmt (cadr ci))
      '()))

;; (collect-all-assigns body) -- find all signal names assigned
;; anywhere in a module body (continuous assigns + procedural blocks).
;; Returns a de-duplicated list of symbols.
(define (collect-all-assigns body)
  (define result '())
  (for-each
   (lambda (item)
     (cond
       ;; Continuous assign: (assign (= <lvalue> <expr>))
       ((and (pair? item) (eq? 'assign (car item)))
        (set! result (append (lvalue-signals (cadr (cadr item))) result)))
       ;; Procedural blocks: always_ff, always_comb, always_latch, always
       ;; The statement is the last element of the always form
       ((and (pair? item)
             (memq (car item) '(always_ff always_comb always_latch always)))
        (set! result (append (collect-assigns-in-stmt (sv-last item))
                             result)))))
   body)
  (sv-delete-dups result))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; 8. ASSIGNMENT TYPE CHECKING
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
;; These functions traverse a statement tree looking for the wrong
;; assignment type.  They return a list of signal names that have
;; the forbidden assignment type.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (find-blocking-in-stmt stmt) -- find signals with blocking (=)
;; assignments in a statement tree.  Used to check always_ff blocks,
;; where only non-blocking (<=) should be used.
(define (find-blocking-in-stmt stmt)
  (cond
    ((not (pair? stmt)) '())
    ;; Found a blocking assign -- this is the violation
    ((eq? '= (car stmt))
     (lvalue-signals (cadr stmt)))
    ;; Non-blocking is fine in always_ff, skip
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
(define (find-nonblocking-in-stmt stmt)
  (cond
    ((not (pair? stmt)) '())
    ;; Found a non-blocking assign -- this is the violation
    ((eq? '<= (car stmt))
     (lvalue-signals (cadr stmt)))
    ;; Blocking is fine in always_comb, skip
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
;; 9. LINT CHECKS
;;
;; The linter runs several checks on each module:
;;
;;   1. Undriven outputs -- output ports that are never assigned
;;   2. Blocking in always_ff -- blocking (=) in sequential blocks
;;   3. Non-blocking in always_comb -- non-blocking (<=) in comb blocks
;;
;; Future checks could include:
;;   - Width mismatches (requires type propagation)
;;   - Latch inference (always_comb with incomplete assignments)
;;   - Multi-driven nets (same signal driven from multiple blocks)
;;   - Missing resets (always_ff without reset condition)
;;   - Unused declarations (declared but never read)
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (lint-module mod) -- run all lint checks on a single module.
;; Prints warnings and a summary to standard output.
(define (lint-module mod)
  (define name    (cadr mod))
  (define ports   (collect-port-signals (find-tagged 'ports (cdr mod))))
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
         (let ((bad (find-blocking-in-stmt (sv-last item))))
           (for-each
            (lambda (sig)
              (displayln "  WARNING: blocking assign to '"
                         (symbol->string sig)
                         "' in always_ff"))
            bad))))
   body)

  ;; Check 3: non-blocking assigns in always_comb
  (for-each
   (lambda (item)
     (if (and (pair? item) (eq? 'always_comb (car item)))
         (let ((bad (find-nonblocking-in-stmt (sv-last item))))
           (for-each
            (lambda (sig)
              (displayln "  WARNING: non-blocking assign to '"
                         (symbol->string sig)
                         "' in always_comb"))
            bad))))
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
