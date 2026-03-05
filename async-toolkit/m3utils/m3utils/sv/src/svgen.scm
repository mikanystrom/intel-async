;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; svgen.scm -- Regenerate SystemVerilog source from S-expression ASTs
;;
;; Author : Claude / Mika Nystroem
;; Date   : March 2026
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; This file converts S-expression ASTs (produced by svfe --scm)
;; back into readable SystemVerilog source code.  It serves as:
;;
;;   - A round-trip test of the parser (parse -> S-expr -> SV)
;;   - A pretty-printer for AST transformations done in Scheme
;;   - A reference for the S-expression format
;;
;; The output is not identical to the original source -- comments,
;; whitespace, and preprocessor directives are lost -- but it is
;; semantically equivalent and syntactically valid SystemVerilog.
;;
;; Requires svbase.scm to be loaded first.
;;
;; Usage:
;;
;;   > (load "sv/src/svbase.scm")
;;   > (load "sv/src/svgen.scm")
;;   > (define ast (read-sv-file "/tmp/mymodule_ast.scm"))
;;   > (sv-emit-all ast)
;;   module counter #( ... ) ( ... );
;;     ...
;;   endmodule
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; EXPRESSION EMITTER
;;
;; Converts expression AST nodes back to SystemVerilog syntax.
;; Returns a string.
;;
;; The expression node types are:
;;   (id name)                  =>  name
;;   number-literal             =>  8'hFF  (symbol, passed through)
;;   (+ a b)                    =>  (a + b)
;;   (?: c t e)                 =>  (c ? t : e)
;;   (index e i)                =>  e[i]
;;   (range e h l)              =>  e[h:l]
;;   (field e m)                =>  e.m
;;   (concat e1 e2 ...)         =>  {e1, e2, ...}
;;   (replicate n e1 ...)       =>  {n{e1, ...}}
;;   (call f a1 a2 ...)         =>  f(a1, a2, ...)
;;   (sys name)                 =>  $name
;;   etc.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Binary operator symbols in the AST and their SV equivalents.
(define *binary-ops*
  '((+  . " + ")  (-  . " - ")  (*  . " * ")  (/  . " / ")  (%  . " % ")
    (** . " ** ")
    (&& . " && ") (|| . " || ")
    (&  . " & ")  (|  . " | ")  (^  . " ^ ")
    (== . " == ") (!= . " != ") (=== . " === ") (!== . " !== ")
    (==? . " ==? ") (!=? . " !=? ")
    (<  . " < ")  (>  . " > ")  (<= . " <= ") (>= . " >= ")
    (<< . " << ") (>> . " >> ") (<<< . " <<< ") (>>> . " >>> ")
    (|-reduce . "|")))  ;; unary reduction |

;; Unary operator symbols.
(define *unary-ops*
  '((~ . "~") (! . "!") (- . "-") (+ . "+")))

;; (emit-expr node) -- convert an expression AST node to a string.
(define (emit-expr node)
  (cond
    ;; Atoms: symbols become their string representation.
    ;; Numbers like 8'hFF are stored as symbols by the Scheme reader.
    ((symbol? node) (symbol->string node))
    ((number? node) (number->string node))
    ((string? node) node)
    ((not (pair? node)) "???")

    ;; (id name) => name
    ((eq? 'id (car node))
     (symbol->string (cadr node)))

    ;; (sys name) => $name
    ((eq? 'sys (car node))
     (string-append "$" (symbol->string (cadr node))))

    ;; (scoped pkg name) => pkg::name
    ((eq? 'scoped (car node))
     (string-append (symbol->string (cadr node))
                    "::" (symbol->string (caddr node))))

    ;; (?: cond then else) => (cond ? then : else)
    ((eq? '?: (car node))
     (string-append "(" (emit-expr (cadr node))
                    " ? " (emit-expr (caddr node))
                    " : " (emit-expr (cadddr node)) ")"))

    ;; (index expr idx) => expr[idx]
    ((eq? 'index (car node))
     (string-append (emit-expr (cadr node))
                    "[" (emit-expr (caddr node)) "]"))

    ;; (range expr hi lo) => expr[hi:lo]
    ((eq? 'range (car node))
     (string-append (emit-expr (cadr node))
                    "[" (emit-expr (caddr node))
                    ":" (emit-expr (cadddr node)) "]"))

    ;; (+: expr base width) => expr[base +: width]
    ((eq? '+: (car node))
     (string-append (emit-expr (cadr node))
                    "[" (emit-expr (caddr node))
                    " +: " (emit-expr (cadddr node)) "]"))

    ;; (-: expr base width) => expr[base -: width]
    ((eq? '-: (car node))
     (string-append (emit-expr (cadr node))
                    "[" (emit-expr (caddr node))
                    " -: " (emit-expr (cadddr node)) "]"))

    ;; (field expr member) => expr.member
    ((eq? 'field (car node))
     (string-append (emit-expr (cadr node))
                    "." (symbol->string (caddr node))))

    ;; (concat e1 e2 ...) => {e1, e2, ...}
    ((eq? 'concat (car node))
     (string-append "{" (sv-join ", " (map emit-expr (cdr node))) "}"))

    ;; (replicate n e1 ...) => {n{e1, ...}}
    ((eq? 'replicate (car node))
     (string-append "{" (emit-expr (cadr node))
                    "{" (sv-join ", " (map emit-expr (cddr node))) "}}"))

    ;; (call func arg1 arg2 ...) => func(arg1, arg2, ...)
    ((eq? 'call (car node))
     (string-append (emit-expr (cadr node))
                    "(" (sv-join ", " (map emit-expr (cddr node))) ")"))

    ;; Binary operators: (+ a b) => (a + b)
    ((assq (car node) *binary-ops*)
     (if (= (length (cdr node)) 1)
         ;; Unary use of a binary op (e.g., unary +, unary |)
         (string-append (cdr (assq (car node) *binary-ops*))
                        (emit-expr (cadr node)))
         ;; Normal binary
         (string-append "(" (emit-expr (cadr node))
                        (cdr (assq (car node) *binary-ops*))
                        (emit-expr (caddr node)) ")")))

    ;; Unary operators: (~ a) => ~a
    ((assq (car node) *unary-ops*)
     (string-append (cdr (assq (car node) *unary-ops*))
                    (emit-expr (cadr node))))

    ;; Fallback: just convert to string representation
    (else
     (define (to-str x)
       (cond ((symbol? x) (symbol->string x))
             ((number? x) (number->string x))
             ((pair? x) (emit-expr x))
             (else "???")))
     (string-append "/*?*/" (to-str node)))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; TYPE EMITTER
;;
;; Converts type AST nodes to SystemVerilog type strings.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (emit-packed-dims dims) -- emit packed dimension list.
;; dims is a string like "[7:0]" or "" from the AST.
(define (emit-dims-list lst)
  (cond
    ((null? lst) "")
    ((and (pair? (car lst)) (pair? (cdar lst)))
     ;; It's a range: [hi:lo]
     (string-append "[" (emit-expr (cadar lst))
                    ":" (emit-expr (caddar lst)) "]"
                    (emit-dims-list (cdr lst))))
    (else (string-append (emit-expr (car lst))
                         (emit-dims-list (cdr lst))))))

;; (emit-type node) -- convert a type AST node to a string.
;; Handles (logic signing dims), (int signing), (enum ...), etc.
(define (emit-type node)
  (cond
    ((not (pair? node)) (if (symbol? node) (symbol->string node) ""))
    ((memq (car node) '(logic reg bit))
     (string-append (symbol->string (car node))
                    (let ((s (cadr node)))
                      (if (and (symbol? s) (not (eq? s '||)))
                          (string-append " " (symbol->string s)) ""))
                    (let ((d (caddr node)))
                      (if (and (pair? d) d)
                          (string-append " " (emit-expr d)) ""))))
    ((memq (car node) '(int byte shortint longint))
     (string-append (symbol->string (car node))
                    (let ((s (cadr node)))
                      (if (symbol? s) (string-append " " (symbol->string s)) ""))))
    ((eq? 'integer (car node)) "integer")
    (else (emit-expr node))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; STATEMENT EMITTER
;;
;; Converts statement AST nodes to indented SystemVerilog.
;; Each function returns a list of strings (lines).
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (emit-stmt node indent) -- convert a statement to a list of
;; indented strings.  INDENT is the current nesting depth.
(define (emit-stmt node indent)
  (cond
    ((not (pair? node)) (list (sv-indent indent "/* ??? */")))

    ;; Blocking assign: (= lvalue expr)
    ((eq? '= (car node))
     (list (sv-indent indent
             (string-append (emit-expr (cadr node))
                            " = " (emit-expr (caddr node)) ";"))))

    ;; Non-blocking assign: (<= lvalue expr)
    ((eq? '<= (car node))
     (list (sv-indent indent
             (string-append (emit-expr (cadr node))
                            " <= " (emit-expr (caddr node)) ";"))))

    ;; Sequential block: (begin [name] stmts...)
    ((eq? 'begin (car node))
     (let* ((named (and (pair? (cdr node)) (symbol? (cadr node))))
            (name  (if named (cadr node) #f))
            (stmts (if named (cddr node) (cdr node))))
       (append
        (list (sv-indent indent
                (if name
                    (string-append "begin : " (symbol->string name))
                    "begin")))
        (sv-append-all (map (lambda (s) (emit-stmt s (+ indent 1))) stmts))
        (list (sv-indent indent "end")))))

    ;; Conditional: (if cond then [else])
    ((eq? 'if (car node))
     (let ((cond-s (emit-expr (cadr node)))
           (then-lines (emit-stmt (caddr node) indent))
           (has-else (> (length node) 3)))
       (append
        (list (sv-indent indent (string-append "if (" cond-s ")")))
        (map (lambda (l) (string-append "  " l)) then-lines)
        (if has-else
            (append
             (list (sv-indent indent "else"))
             (map (lambda (l) (string-append "  " l))
                  (emit-stmt (cadddr node) indent)))
            '()))))

    ;; Case: (case expr (match stmt) ...)
    ;; Also handles casez, casex, unique-case, priority-case
    ((memq (car node) '(case casez casex unique-case priority-case))
     (let ((kw (cond ((eq? 'unique-case (car node)) "unique case")
                     ((eq? 'priority-case (car node)) "priority case")
                     (else (symbol->string (car node))))))
       (append
        (list (sv-indent indent
                (string-append kw " (" (emit-expr (cadr node)) ")")))
        (sv-append-all
         (map (lambda (ci)
                (cond
                  ;; (default stmt)
                  ((and (pair? ci) (eq? 'default (car ci)))
                   (append
                    (list (sv-indent (+ indent 1) "default:"))
                    (emit-stmt (cadr ci) (+ indent 2))))
                  ;; (match-expr stmt)
                  ((and (pair? ci) (> (length ci) 1))
                   (append
                    (list (sv-indent (+ indent 1)
                            (string-append (emit-expr (car ci)) ":")))
                    (emit-stmt (cadr ci) (+ indent 2))))
                  (else '())))
              (cddr node)))
        (list (sv-indent indent "endcase")))))

    ;; For loop: (for init cond step body)
    ((eq? 'for (car node))
     (let ((init-s (emit-for-init (cadr node)))
           (cond-s (emit-expr (caddr node)))
           (step-s (emit-for-step (cadddr node))))
       (append
        (list (sv-indent indent
                (string-append "for ("
                               init-s "; " cond-s "; " step-s ")")))
        (emit-stmt (car (cddddr node)) (+ indent 1)))))

    ;; Null statement: (null)
    ((eq? 'null (car node))
     (list (sv-indent indent ";")))

    ;; Directive: (directive)
    ((eq? 'directive (car node))
     (list (sv-indent indent "/* directive */")))

    ;; Return: (return [expr])
    ((eq? 'return (car node))
     (if (> (length node) 1)
         (list (sv-indent indent
                 (string-append "return " (emit-expr (cadr node)) ";")))
         (list (sv-indent indent "return;"))))

    ;; Fallback
    (else (list (sv-indent indent
                  (string-append "/* unhandled: "
                                 (symbol->string (car node)) " */"))))))

;; (emit-for-init node) -- emit the initializer part of a for loop.
(define (emit-for-init node)
  (cond
    ((and (pair? node) (eq? 'decl (car node)))
     ;; (decl type name expr)
     (string-append (emit-type (cadr node)) " "
                    (symbol->string (caddr node))
                    " = " (emit-expr (cadddr node))))
    ((and (pair? node) (eq? '= (car node)))
     (string-append (emit-expr (cadr node))
                    " = " (emit-expr (caddr node))))
    (else (emit-expr node))))

;; (emit-for-step node) -- emit the step expression of a for loop.
(define (emit-for-step node)
  (cond
    ((and (pair? node) (eq? '++ (car node)))
     (string-append (emit-expr (cadr node)) "++"))
    ((and (pair? node) (eq? '-- (car node)))
     (string-append (emit-expr (cadr node)) "--"))
    ((and (pair? node) (eq? '= (car node)))
     (string-append (emit-expr (cadr node))
                    " = " (emit-expr (caddr node))))
    (else (emit-expr node))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; SENSITIVITY LIST EMITTER
;;
;; (sens (posedge clk) (negedge rst_n)) => @(posedge clk or negedge rst_n)
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (emit-sensitivity sens)
  (if (not (and (pair? sens) (eq? 'sens (car sens))))
      ""
      (let ((items (map (lambda (item)
                          (cond
                            ((and (pair? item) (eq? 'posedge (car item)))
                             (string-append "posedge " (emit-expr (cadr item))))
                            ((and (pair? item) (eq? 'negedge (car item)))
                             (string-append "negedge " (emit-expr (cadr item))))
                            ((eq? '* item) "*")
                            (else (emit-expr item))))
                        (cdr sens))))
        (string-append " @(" (sv-join " or " items) ")"))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; MODULE EMITTER
;;
;; Top-level function that emits a complete module declaration.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (emit-port-decl p) -- emit a single port declaration.
(define (emit-port-decl p)
  (cond
    ((and (pair? p) (eq? 'port (car p)))
     ;; (port dir type signing dims (id name [dims]))
     ;; We reconstruct: dir type signing dims name unpacked_dims
     (define dir (symbol->string (cadr p)))
     (define parts (cddr p))
     ;; Collect type tokens and find (id ...)
     (define (collect-parts lst)
       (cond
         ((null? lst) (cons '() #f))
         ((and (pair? (car lst)) (eq? 'id (caar lst)))
          (cons '() (car lst)))
         (else
          (let ((rest (collect-parts (cdr lst))))
            (cons (cons (car lst) (car rest)) (cdr rest))))))
     (define cp (collect-parts parts))
     (define type-parts (car cp))
     (define id-form (cdr cp))
     (define type-str (sv-join " " (map emit-expr type-parts)))
     (define name-str (if id-form (symbol->string (cadr id-form)) "???"))
     (define dims-str (if (and id-form (> (length id-form) 2))
                          (sv-join "" (map emit-expr (cddr id-form)))
                          ""))
     (string-append dir " " type-str
                    (if (> (string-length type-str) 0) " " "")
                    name-str dims-str))

    ((and (pair? p) (eq? 'port-ident (car p)))
     (symbol->string (cadr p)))

    ((and (pair? p) (eq? 'port-if (car p)))
     ;; (port-if axi_if.slave (id s))
     (let ((if-type (symbol->string (cadr p)))
           (id-form (caddr p)))
       (string-append if-type " " (symbol->string (cadr id-form)))))

    (else "/* ??? */")))

;; (emit-connection conn) -- emit a single port connection.
(define (emit-connection conn)
  (cond
    ((and (pair? conn) (eq? 'named (car conn)))
     (string-append "." (symbol->string (cadr conn))
                    "(" (emit-expr (caddr conn)) ")"))
    ((and (pair? conn) (eq? '.* (car conn)))
     ".*")
    (else (emit-expr conn))))

;; (sv-emit-module mod) -- emit a complete module to stdout.
(define (sv-emit-module mod)
  (define name (symbol->string (module-name mod)))
  (define params (module-params mod))
  (define ports (module-ports mod))
  (define body (module-body-items mod))

  ;; Module header
  (display (string-append "module " name))

  ;; Parameters
  (if (and params (pair? (cdr params)))
      (begin
        (displayln " #(")
        (define param-strs
          (map (lambda (p)
                 ;; (parameter type name expr) or similar
                 (if (and (pair? p) (eq? 'parameter (car p)))
                     (let ((type-s (if (pair? (cadr p))
                                       (string-append (emit-type (cadr p)) " ")
                                       ""))
                           (pname (symbol->string (caddr p)))
                           (pval  (emit-expr (cadddr p))))
                       (string-append "  parameter " type-s pname " = " pval))
                     "  /* ??? */"))
               (cdr params)))
        (display (sv-join (string-append "," *nl*) param-strs))
        (newline)
        (display ")"))
      (begin))

  ;; Ports
  (if (and ports (pair? (cdr ports)))
      (begin
        (displayln " (")
        (display (sv-join (string-append "," *nl*) (map (lambda (p)
                                       (string-append "  " (emit-port-decl p)))
                                     (cdr ports))))
        (newline)
        (displayln ");"))
      (displayln ";"))
  (newline)

  ;; Body items
  (for-each
   (lambda (item)
     (cond
       ;; Declaration: (decl type (id name dims) ...)
       ((and (pair? item) (eq? 'decl (car item)))
        (let* ((type-s (emit-type (cadr item)))
               (ids (sv-filter (lambda (x) (and (pair? x) (eq? 'id (car x))))
                               (cddr item)))
               (id-strs (map (lambda (id-form)
                               (let ((n (symbol->string (cadr id-form)))
                                     (d (if (> (length id-form) 2)
                                            (sv-join "" (map emit-expr (cddr id-form)))
                                            "")))
                                 (string-append n d)))
                             ids)))
          (displayln (sv-indent 1
                       (string-append type-s " " (sv-join ", " id-strs) ";")))))

       ;; Continuous assign: (assign (= lv expr))
       ((and (pair? item) (eq? 'assign (car item)))
        (let ((asgn (cadr item)))
          (displayln (sv-indent 1
                       (string-append "assign " (emit-expr (cadr asgn))
                                      " = " (emit-expr (caddr asgn)) ";")))))

       ;; always_ff: (always_ff sensitivity stmt)
       ((and (pair? item) (eq? 'always_ff (car item)))
        (displayln (sv-indent 1
                     (string-append "always_ff"
                                    (emit-sensitivity (cadr item)))))
        (for-each displayln (emit-stmt (caddr item) 2)))

       ;; always_comb: (always_comb stmt)
       ((and (pair? item) (eq? 'always_comb (car item)))
        (displayln (sv-indent 1 "always_comb"))
        (for-each displayln (emit-stmt (cadr item) 2)))

       ;; always_latch: (always_latch sensitivity stmt)
       ((and (pair? item) (eq? 'always_latch (car item)))
        (displayln (sv-indent 1
                     (string-append "always_latch"
                                    (emit-sensitivity (cadr item)))))
        (for-each displayln (emit-stmt (caddr item) 2)))

       ;; generate: (generate items...)
       ((and (pair? item) (eq? 'generate (car item)))
        (displayln (sv-indent 1 "generate"))
        (displayln (sv-indent 2 "/* generate body */"))
        (displayln (sv-indent 1 "endgenerate")))

       ;; typedef: handled at module level
       ((and (pair? item) (eq? 'typedef (car item)))
        (displayln (sv-indent 1 "/* typedef */")))

       ;; directive
       ((and (pair? item) (eq? 'directive (car item)))
        (displayln (sv-indent 1 "/* directive */")))

       ;; Everything else
       (else
        (if (pair? item)
            (displayln (sv-indent 1
                         (string-append "/* " (symbol->string (car item)) " ... */")))))))
   body)

  (newline)
  (displayln "endmodule")
  (newline))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; PACKAGE EMITTER
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (sv-emit-package pkg)
  (displayln "package " (symbol->string (cadr pkg)) ";")
  (displayln "  /* package body */")
  (displayln "endpackage")
  (newline))

(define (sv-emit-interface iface)
  (displayln "interface " (symbol->string (cadr iface)) ";")
  (displayln "  /* interface body */")
  (displayln "endinterface")
  (newline))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; TOP-LEVEL DRIVER
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (sv-emit-all nodes) -- emit all top-level AST nodes as
;; SystemVerilog to standard output.
(define (sv-emit-all nodes)
  (for-each
   (lambda (node)
     (cond
       ((sv-module? node)    (sv-emit-module node))
       ((sv-package? node)   (sv-emit-package node))
       ((sv-interface? node) (sv-emit-interface node))))
   nodes))
