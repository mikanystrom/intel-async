;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; svbase.scm -- Base semantic analysis for SystemVerilog ASTs
;;
;; Author : Claude / Mika Nystroem
;; Date   : March 2026
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; This file provides the foundational utilities for working with
;; S-expression ASTs produced by svfe --scm.  It is loaded by all
;; other sv*.scm scripts and provides:
;;
;;   - File I/O (reading svfe output)
;;   - AST predicates and navigation
;;   - Signal collection (ports, declarations, assignments)
;;   - Statement traversal helpers
;;
;; The higher-level tools (linting, code generation, etc.) are in
;; separate files that load this one:
;;
;;   svlint.scm   -- lint checks
;;   svgen.scm    -- SystemVerilog regeneration from AST
;;
;; Usage with mscheme:
;;
;;   > (load "sv/src/svbase.scm")
;;   > (define ast (read-sv-file "/tmp/mymodule_ast.scm"))
;;   > (sv-module? (car ast))
;;   #t
;;   > (cadr (car ast))      ;; module name
;;   mymodule
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(require-modules "basic-defs")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; 1. UTILITY FUNCTIONS
;;
;; Basic list utilities and output helpers.  Prefixed with sv- to
;; avoid name clashes with user code or other Scheme libraries.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; *nl* -- a one-character string containing a newline.
;; mscheme does not interpret \n in string literals, so we build
;; the newline character via integer->char.
(define *nl* (list->string (list (integer->char 10))))

;; (displayln arg ...) -- display all arguments followed by a newline.
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

;; (sv-join sep lst) -- join a list of strings with separator SEP.
;; Example: (sv-join ", " '("a" "b" "c")) => "a, b, c"
(define (sv-join sep lst)
  (cond
    ((null? lst) "")
    ((null? (cdr lst)) (car lst))
    (else (string-append (car lst) sep (sv-join sep (cdr lst))))))

;; (sv-indent n str) -- prepend N*2 spaces to STR.
(define (sv-indent n str)
  (define (spaces k)
    (if (<= k 0) "" (string-append "  " (spaces (- k 1)))))
  (string-append (spaces n) str))


;; (string-index s ch) -- return index of first occurrence of ch in s, or #f.
(define (string-index s ch)
  (let loop ((i 0))
    (if (>= i (string-length s)) #f
        (if (char=? (string-ref s i) ch) i
            (loop (+ i 1))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; 2. FILE I/O
;;
;; Read S-expressions from files.  svfe emits one S-expression per
;; top-level construct (module, package, etc.), so a typical file
;; produces a list of several forms.
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

(define (sv-typedef? node)
  (and (pair? node) (eq? 'typedef (car node))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; 4. AST NAVIGATION
;;
;; The module S-expression layout is:
;;
;;   (module <name> [<import>...] [<parameters>] [<ports>] <body>...)
;;
;; Header elements (imports, parameters, ports) are tagged forms
;; that can appear in varying order.  Body items follow all headers.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (module-name mod) -- return the module name (a symbol).
(define (module-name mod) (cadr mod))

;; (module-params mod) -- return the (parameters ...) form, or #f.
(define (module-params mod) (find-tagged 'parameters (cdr mod)))

;; (module-ports mod) -- return the (ports ...) form, or #f.
(define (module-ports mod) (find-tagged 'ports (cdr mod)))

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

;; (find-bare-before-id lst) -- find a bare symbol preceding an (id) form.
;; Handles (port dir name (id)) where name is a bare symbol.
(define (find-bare-before-id lst)
  (cond
    ((null? lst) #f)
    ((and (symbol? (car lst))
          (not (null? (cdr lst)))
          (pair? (cadr lst))
          (eq? 'id (caadr lst)))
     (car lst))
    (else (find-bare-before-id (cdr lst)))))

;; (find-id-in-list lst) -- find the first (id ...) form in a list.
;; Used to locate the signal name within a port declaration that
;; contains type qualifiers, dimensions, etc. before the identifier.
;; Handles the dir_only:bare case where the format is (name (id))
;; -- when (id) has no name, the preceding bare symbol is the name.
(define (find-id-in-list lst)
  (cond
    ((null? lst) #f)
    ((and (pair? (car lst)) (eq? 'id (caar lst)))
     (if (null? (cdar lst))
         #f   ;; (id) with no name -- caller should use preceding symbol
         (car lst)))
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
                   ;; For dir_only:bare format (port dir name (id)),
                   ;; find-id-in-list returns #f; use last bare symbol before (id).
                   (let ((id-form (find-id-in-list (cddr p))))
                     (if id-form
                         (list (cadr p) (cadr id-form))
                         (let ((bare (find-bare-before-id (cddr p))))
                           (if bare
                               (list (cadr p) bare)
                               #f))))
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
;; 7. STATEMENT TRAVERSAL
;;
;; Helpers for recursively walking statement trees.  These are used
;; by both the signal collector and the lint checks.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

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

;; (lvalue-signals lv) -- extract base signal names from an lvalue.
;; Returns a list of symbols.
;;
;; Lvalues can be:
;;   (id name)                  -- simple signal => (name)
;;   (index lv idx)             -- bit/array select => recurse on lv
;;   (range lv hi lo)           -- part select => recurse on lv
;;   (field lv member)          -- struct member => recurse on lv
;;   (concat lv1 lv2 ...)       -- concatenation => all base names
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


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; 8. SIGNAL COLLECTION -- ASSIGNMENTS
;;
;; To check for undriven signals, we find every signal name that
;; appears on the left-hand side of an assignment anywhere in the
;; module.  This includes:
;;
;;   - Continuous assigns:   (assign (= <lvalue> <expr>))
;;   - Blocking assigns:     (= <lvalue> <expr>)    in always_comb
;;   - Non-blocking assigns: (<= <lvalue> <expr>)   in always_ff
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

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
