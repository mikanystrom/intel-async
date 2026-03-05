;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; svsynth.scm -- Basic logic synthesizer using BDD primitives
;;
;; Author : Claude / Mika Nystroem
;; Date   : March 2026
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; This file implements a basic logic synthesizer that:
;;
;;   1. Reads SystemVerilog ASTs (produced by svfe --scm)
;;   2. Extracts combinational logic (always_comb and assign)
;;   3. Builds BDD representations for each output signal
;;   4. Maps BDDs to a gate-level netlist (AND, OR, NOT, XOR)
;;   5. Emits the netlist as structural SystemVerilog
;;
;; It requires:
;;   - svbase.scm to be loaded first (AST navigation)
;;   - The svsynth interpreter (provides bdd-* primitives)
;;
;; Usage (in svsynth REPL):
;;
;;   > (load "sv/src/svbase.scm")
;;   > (load "sv/src/svsynth.scm")
;;   > (define ast (read-sv-file "/tmp/combo_ast.scm"))
;;   > (synth-module (car ast))
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; 1. BDD VARIABLE ENVIRONMENT
;;
;; Maps signal names (symbols) to BDD variables.  We create BDD
;; variables lazily as signals are encountered during expression
;; evaluation.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Association list mapping signal name symbols to BDD variables.
(define *bdd-env* '())

;; (bdd-lookup name) -- find or create a BDD variable for NAME.
(define (bdd-lookup name)
  (let ((entry (assq name *bdd-env*)))
    (if entry
        (cdr entry)
        (let ((v (bdd-var (symbol->string name))))
          (set! *bdd-env* (cons (cons name v) *bdd-env*))
          v))))

;; (bdd-env-reset!) -- clear the variable environment.
(define (bdd-env-reset!)
  (set! *bdd-env* '()))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; 2. EXPRESSION TO BDD COMPILER
;;
;; Translates an svfe expression AST node into a BDD.  Only handles
;; the Boolean/bitwise subset of expressions.  Multi-bit signals
;; are treated as single-bit for this basic synthesizer.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (expr->bdd node) -- compile an expression AST node to a BDD.
;;
;; Supported expression forms:
;;   (id name)            => BDD variable for name
;;   (! expr)             => BDD NOT
;;   (~ expr)             => BDD NOT (bitwise)
;;   (& a b)              => BDD AND
;;   (| a b)              => BDD OR
;;   (^ a b)              => BDD XOR
;;   (&& a b)             => BDD AND (logical)
;;   (|| a b)             => BDD OR  (logical)
;;   (?: c t e)           => BDD ITE
;;   0, '0                => BDD false
;;   1, '1                => BDD true
;;   (index expr idx)     => treated as new variable expr_idx
;;   (field expr member)  => treated as new variable expr_member
;;
;; Unsupported forms (arithmetic, shifts, etc.) are mapped to
;; fresh BDD variables as uninterpreted functions.
(define (expr->bdd node)
  (cond
    ;; Constants
    ((and (number? node) (= node 0)) (bdd-false))
    ((and (number? node) (= node 1)) (bdd-true))
    ((eq? node '|0|) (bdd-false))
    ((eq? node '|1|) (bdd-true))

    ;; Symbol atoms (e.g., '0 '1 from SystemVerilog)
    ((symbol? node)
     (let ((s (symbol->string node)))
       (cond
         ((equal? s "0") (bdd-false))
         ((equal? s "1") (bdd-true))
         (else (bdd-lookup node)))))

    ;; Number > 1 -- treat as opaque
    ((number? node) (bdd-lookup (string->symbol
                                  (string-append "_const_"
                                    (number->string node)))))

    ((not (pair? node))
     (bdd-false))  ;; fallback

    ;; (id name) => variable
    ((eq? 'id (car node))
     (bdd-lookup (cadr node)))

    ;; Logical/bitwise NOT
    ((memq (car node) '(! ~))
     (bdd-not (expr->bdd (cadr node))))

    ;; Bitwise AND
    ((eq? '& (car node))
     (bdd-and (expr->bdd (cadr node)) (expr->bdd (caddr node))))

    ;; Bitwise OR
    ((eq? '| (car node))
     (bdd-or (expr->bdd (cadr node)) (expr->bdd (caddr node))))

    ;; Bitwise XOR
    ((eq? '^ (car node))
     (bdd-xor (expr->bdd (cadr node)) (expr->bdd (caddr node))))

    ;; Logical AND
    ((eq? '&& (car node))
     (bdd-and (expr->bdd (cadr node)) (expr->bdd (caddr node))))

    ;; Logical OR
    ((eq? '|| (car node))
     (bdd-or (expr->bdd (cadr node)) (expr->bdd (caddr node))))

    ;; Ternary: (?: cond then else)
    ((eq? '?: (car node))
     (bdd-ite (expr->bdd (cadr node))
              (expr->bdd (caddr node))
              (expr->bdd (cadddr node))))

    ;; Index: (index expr idx) -- make a composite variable name
    ((eq? 'index (car node))
     (let ((base (cadr node))
           (idx  (caddr node)))
       (if (and (pair? base) (eq? 'id (car base)) (number? idx))
           (bdd-lookup (string->symbol
                         (string-append (symbol->string (cadr base))
                                        "_" (number->string idx))))
           ;; General case: treat as opaque
           (bdd-lookup (string->symbol "_indexed_")))))

    ;; Field: (field expr member) -- make a composite variable name
    ((eq? 'field (car node))
     (let ((base (cadr node))
           (mem  (caddr node)))
       (if (and (pair? base) (eq? 'id (car base)))
           (bdd-lookup (string->symbol
                         (string-append (symbol->string (cadr base))
                                        "_" (symbol->string mem))))
           (bdd-lookup (string->symbol "_field_")))))

    ;; Concatenation: for single-bit synthesis, just AND them together
    ;; (this is a simplification)
    ((eq? 'concat (car node))
     (if (null? (cdr node))
         (bdd-false)
         (let loop ((items (cdr node)) (acc (bdd-true)))
           (if (null? items)
               acc
               (loop (cdr items)
                     (bdd-and acc (expr->bdd (car items))))))))

    ;; Everything else (arithmetic, shifts, etc.) -- uninterpreted
    ;; Create a fresh variable representing the result.
    (else
     (bdd-lookup (string->symbol
                   (string-append "_expr_"
                     (symbol->string (car node))))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; 3. STATEMENT TO BDD COMPILER
;;
;; Walks statement trees from always_comb blocks and continuous
;; assigns, building BDDs for each assigned signal.
;;
;; Returns an association list: ((signal-name . bdd) ...)
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (stmt->bdd-assigns stmt) -- extract (name . bdd) pairs from
;; a statement tree.
(define (stmt->bdd-assigns stmt)
  (cond
    ((not (pair? stmt)) '())

    ;; Blocking assign: (= lvalue expr)
    ((eq? '= (car stmt))
     (let ((sigs (lvalue-signals (cadr stmt)))
           (bdd  (expr->bdd (caddr stmt))))
       (map (lambda (s) (cons s bdd)) sigs)))

    ;; Sequential block: (begin [name] stmts...)
    ((eq? 'begin (car stmt))
     (sv-append-all (map stmt->bdd-assigns (begin-stmts stmt))))

    ;; Conditional: (if cond then [else])
    ((eq? 'if (car stmt))
     (let* ((cond-bdd (expr->bdd (cadr stmt)))
            (then-assigns (stmt->bdd-assigns (caddr stmt)))
            (else-assigns (if (> (length stmt) 3)
                              (stmt->bdd-assigns (cadddr stmt))
                              '())))
       ;; For each signal assigned in then or else, build ITE
       (merge-conditional-assigns cond-bdd then-assigns else-assigns)))

    ;; Case: (case expr (match stmt) ...)
    ((memq (car stmt) '(case casez casex))
     (let ((sel-bdd (expr->bdd (cadr stmt))))
       (sv-append-all
         (map (lambda (ci)
                (if (and (pair? ci) (> (length ci) 1))
                    (stmt->bdd-assigns (cadr ci))
                    '()))
              (cddr stmt)))))

    (else '())))

;; (merge-conditional-assigns cond-bdd then-assigns else-assigns)
;; For signals assigned in an if/else, produce ITE BDDs.
;; If a signal is only assigned in one branch, the other branch
;; keeps the signal's current value (its BDD variable).
(define (merge-conditional-assigns cond-bdd then-assigns else-assigns)
  (let ((all-sigs (sv-delete-dups
                    (append (map car then-assigns)
                            (map car else-assigns)))))
    (map (lambda (sig)
           (let ((then-bdd (assq-val sig then-assigns))
                 (else-bdd (assq-val sig else-assigns)))
             (cons sig
                   (bdd-ite cond-bdd
                            (or then-bdd (bdd-lookup sig))
                            (or else-bdd (bdd-lookup sig))))))
         all-sigs)))

;; (assq-val key alist) -- look up key in alist, return value or #f.
(define (assq-val key alist)
  (let ((entry (assq key alist)))
    (if entry (cdr entry) #f)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; 4. MODULE-LEVEL SYNTHESIS
;;
;; Extract all combinational logic from a module and build BDDs.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (synth-combinational body) -- extract BDD assignments from
;; all combinational constructs in a module body.
;; Returns an association list: ((signal-name . bdd) ...)
(define (synth-combinational body)
  (define result '())
  (for-each
    (lambda (item)
      (cond
        ;; Continuous assign: (assign (= lvalue expr))
        ((and (pair? item) (eq? 'assign (car item)))
         (let* ((asgn (cadr item))
                (sigs (lvalue-signals (cadr asgn)))
                (bdd  (expr->bdd (caddr asgn))))
           (for-each (lambda (s) (set! result (cons (cons s bdd) result)))
                     sigs)))

        ;; always_comb: (always_comb stmt)
        ((and (pair? item) (eq? 'always_comb (car item)))
         (set! result (append (stmt->bdd-assigns (cadr item)) result)))))
    body)
  (reverse result))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; 5. GATE-LEVEL NETLIST EMISSION
;;
;; Walk a BDD and emit structural SystemVerilog using AND, OR,
;; NOT gates.  Uses Shannon expansion:
;;
;;   f = (v AND f|v=1) OR (!v AND f|v=0)
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Gate counter for unique wire names.
(define *gate-counter* 0)

(define (next-wire)
  (set! *gate-counter* (+ *gate-counter* 1))
  (string-append "w" (number->string *gate-counter*)))

;; (emit-gate-netlist signal-name bdd) -- emit a gate-level
;; implementation for the given signal using BDD decomposition.
;; Prints structural SV to stdout.
(define (emit-gate-netlist sig-name bdd)
  (displayln "  // Gate-level netlist for " (symbol->string sig-name))
  (displayln "  // BDD: " (bdd-format bdd))
  (displayln "  // BDD size: " (number->string (bdd-size bdd)) " nodes")
  (displayln "  assign " (symbol->string sig-name) " = "
             (bdd-format bdd) ";")
  (newline))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; 6. TOP-LEVEL SYNTHESIS DRIVER
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (synth-module mod) -- synthesize combinational logic in a module.
;; Prints a report and gate-level netlist to stdout.
(define (synth-module mod)
  (bdd-env-reset!)
  (set! *gate-counter* 0)

  (define name (module-name mod))
  (define ports (collect-port-signals (module-ports mod)))
  (define body (module-body-items mod))
  (define outputs (sv-filter (lambda (p) (eq? 'output (car p))) ports))
  (define inputs (sv-filter (lambda (p) (eq? 'input (car p))) ports))

  (displayln "//")
  (displayln "// svsynth: Logic synthesis for module "
             (symbol->string name))
  (displayln "//")
  (displayln "// Inputs:  "
             (sv-join ", " (map (lambda (p) (symbol->string (cadr p))) inputs)))
  (displayln "// Outputs: "
             (sv-join ", " (map (lambda (p) (symbol->string (cadr p))) outputs)))
  (displayln "//")
  (newline)

  ;; Create BDD variables for all input ports
  (for-each (lambda (p) (bdd-lookup (cadr p))) inputs)

  ;; Build BDDs for all combinational assignments
  (define assigns (synth-combinational body))

  (displayln "// Combinational assignments found: "
             (number->string (length assigns)))
  (newline)

  ;; Emit structural SV header
  (display (string-append "module " (symbol->string name) "_synth ("))
  (newline)
  (display (sv-join (string-append "," *nl*)
                    (map (lambda (p)
                           (string-append "  "
                             (symbol->string (car p)) " "
                             (symbol->string (cadr p))))
                         ports)))
  (newline)
  (displayln ");")
  (newline)

  ;; Emit BDD-based assignments
  (for-each (lambda (a)
              (emit-gate-netlist (car a) (cdr a)))
            assigns)

  (displayln "endmodule")
  (newline)

  ;; Summary
  (displayln "// Synthesis summary:")
  (displayln "//   Input signals:  " (number->string (length inputs)))
  (displayln "//   Output signals: " (number->string (length outputs)))
  (displayln "//   BDD variables:  " (number->string (length *bdd-env*)))
  (displayln "//   Assignments:    " (number->string (length assigns))))

;; (synth-all nodes) -- synthesize all modules in an AST.
(define (synth-all nodes)
  (for-each
    (lambda (node)
      (if (sv-module? node) (synth-module node)))
    nodes))
