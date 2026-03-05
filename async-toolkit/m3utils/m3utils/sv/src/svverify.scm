;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; svverify.scm -- Functional equivalence verifier
;;
;; Author : Claude / Mika Nystroem
;; Date   : March 2026
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; This file implements a self-contained functional equivalence
;; checker that verifies gate-level netlists against their BDD
;; specifications without requiring any external simulator.
;;
;; APPROACH
;; --------
;; For each output signal, we have two representations:
;;
;;   1. A BDD (Binary Decision Diagram) -- the "golden" reference
;;      computed by the synthesizer from the RTL source.
;;
;;   2. A gate netlist -- the structural implementation produced
;;      by the technology mapper (svgates.scm).
;;
;; The verifier exhaustively evaluates BOTH representations for
;; every possible input combination and checks that they agree.
;; For N input variables, this means 2^N evaluations.
;;
;; BDD EVALUATION
;; --------------
;; A BDD is evaluated by walking the graph from root to leaf:
;;   - At each node, read the current value of the decision variable
;;   - Take the "high" branch if the variable is 1, "low" if 0
;;   - A TRUE leaf returns 1, a FALSE leaf returns 0
;;
;; GATE NETLIST EVALUATION
;; -----------------------
;; The gate netlist (*netlist*) is a list of gate instances.
;; We topologically evaluate each gate, propagating signal values
;; through the network from primary inputs to primary outputs.
;;
;; This verifier is useful because:
;;   - It catches bugs in the BDD-to-gate mapping
;;   - It runs inside mscheme with no external dependencies
;;   - It provides exact counterexample vectors on failure
;;   - It validates the entire synthesis pipeline end-to-end
;;
;; Usage:
;;   > (load "sv/src/svbase.scm")
;;   > (load "sv/src/svsynth.scm")
;;   > (load "sv/src/svgates.scm")
;;   > (load "sv/src/svverify.scm")
;;   > (verify-synthesis "/tmp/mymodule_ast.scm")
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 1. BDD EVALUATOR
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (eval-bdd bdd env) -- evaluate a BDD under a variable assignment.
;; env is an association list: ((var-name-string . 0-or-1) ...)
;; Returns 0 or 1.
(define (eval-bdd bdd env)
  (cond
    ((bdd-true? bdd)  1)
    ((bdd-false? bdd) 0)
    (else
      (let* ((var (bdd-node-var bdd))
             (var-name (bdd-name var))
             (entry (assoc var-name env)))
        (if (not entry)
            (begin (display "WARNING: eval-bdd: unbound variable: ")
                   (display var-name)
                   (newline)
                   0)
            (if (= (cdr entry) 1)
                (eval-bdd (bdd-high bdd) env)
                (eval-bdd (bdd-low bdd) env)))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 2. GATE NETLIST EVALUATOR
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Evaluate a single gate given input values.
;; Returns the output value (0 or 1).
(define (eval-gate-fn cell-type inputs)
  (cond
    ((equal? cell-type "INV")
     (if (= (car inputs) 1) 0 1))
    ((equal? cell-type "BUF")
     (car inputs))
    ((equal? cell-type "AND2")
     (if (and (= (car inputs) 1) (= (cadr inputs) 1)) 1 0))
    ((equal? cell-type "OR2")
     (if (or (= (car inputs) 1) (= (cadr inputs) 1)) 1 0))
    ((equal? cell-type "NAND2")
     (if (and (= (car inputs) 1) (= (cadr inputs) 1)) 0 1))
    ((equal? cell-type "NOR2")
     (if (or (= (car inputs) 1) (= (cadr inputs) 1)) 0 1))
    ((equal? cell-type "XOR2")
     (if (= (car inputs) (cadr inputs)) 0 1))
    ((equal? cell-type "XNOR2")
     (if (= (car inputs) (cadr inputs)) 1 0))
    ((equal? cell-type "MUX2")
     ;; MUX2: A=low-input, B=high-input, S=select
     ;; inputs order: A B S
     (let ((a (car inputs)) (b (cadr inputs)) (s (caddr inputs)))
       (if (= s 1) b a)))
    ((equal? cell-type "TIEH") 1)
    ((equal? cell-type "TIEL") 0)
    (else
      (display "WARNING: eval-gate-fn: unknown cell: ")
      (display cell-type)
      (newline)
      0)))

;; (gate-input-ports cell-type) -- return list of input port names
;; in evaluation order.
(define (gate-input-ports cell-type)
  (cond
    ((equal? cell-type "INV")   '("A"))
    ((equal? cell-type "BUF")   '("A"))
    ((equal? cell-type "AND2")  '("A" "B"))
    ((equal? cell-type "OR2")   '("A" "B"))
    ((equal? cell-type "NAND2") '("A" "B"))
    ((equal? cell-type "NOR2")  '("A" "B"))
    ((equal? cell-type "XOR2")  '("A" "B"))
    ((equal? cell-type "XNOR2") '("A" "B"))
    ((equal? cell-type "MUX2")  '("A" "B" "S"))
    ((equal? cell-type "TIEH")  '())
    ((equal? cell-type "TIEL")  '())
    (else '())))

;; (gate-output-port cell-type) -- return the output port name.
(define (gate-output-port cell-type) "Y")

;; (eval-netlist netlist env) -- evaluate a gate netlist.
;; netlist is the *netlist* list from svgates.scm:
;;   ((cell-type inst-name ((port . wire) ...)) ...)
;; env is an assoc list: ((wire-name . value) ...)
;; Returns the updated env with all internal wires resolved.
(define (eval-netlist netlist env)
  (let ((wire-vals env))
    ;; Process gates in order (they're reversed in *netlist*)
    (for-each
      (lambda (gate)
        (let* ((cell-type (car gate))
               (conns (caddr gate))
               (in-ports (gate-input-ports cell-type))
               (out-port (gate-output-port cell-type)))
          ;; Look up input values
          (let ((in-vals
                  (map (lambda (port-name)
                         (let* ((conn (assoc port-name conns))
                                (wire (if conn (cdr conn) #f))
                                (val-entry (if wire (assoc wire wire-vals) #f)))
                           (if val-entry
                               (cdr val-entry)
                               (begin
                                 (display "WARNING: eval-netlist: unresolved wire: ")
                                 (display wire)
                                 (newline)
                                 0))))
                       in-ports)))
            ;; Compute output
            (let* ((out-val (eval-gate-fn cell-type in-vals))
                   (out-conn (assoc out-port conns))
                   (out-wire (if out-conn (cdr out-conn) #f)))
              (if out-wire
                  (set! wire-vals
                        (cons (cons out-wire out-val) wire-vals)))))))
      (reverse netlist))
    wire-vals))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 3. EXHAUSTIVE EQUIVALENCE CHECKER
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (make-input-vectors var-names) -- generate all 2^N input
;; combinations for the given variable names.
;; Returns a list of alists: (((name . val) ...) ...)
(define (make-input-vectors var-names)
  (if (null? var-names)
      '(())
      (let ((rest (make-input-vectors (cdr var-names)))
            (name (car var-names)))
        (append
          (map (lambda (v) (cons (cons name 0) v)) rest)
          (map (lambda (v) (cons (cons name 1) v)) rest)))))

;; (format-vector vec) -- format an input vector for display.
(define (format-vector vec)
  (sv-join " "
    (map (lambda (e)
           (string-append (car e) "=" (number->string (cdr e))))
         vec)))

;; (verify-bdd-vs-netlist name bdd netlist input-names)
;; Exhaustively verify that a gate netlist produces the same
;; output as a BDD for all input combinations.
;; Returns #t if all match, #f if any mismatch found.
(define (verify-bdd-vs-netlist name bdd netlist input-names output-wire)
  (let* ((vectors (make-input-vectors input-names))
         (n-vectors (length vectors))
         (pass #t)
         (fail-count 0))
    (display "  Verifying ")
    (display name)
    (display " (")
    (display (number->string n-vectors))
    (display " vectors)...")
    (for-each
      (lambda (vec)
        ;; Evaluate BDD
        (let* ((bdd-result (eval-bdd bdd vec))
               ;; Evaluate gate netlist
               (wire-env (eval-netlist netlist vec))
               (gate-entry (assoc output-wire wire-env))
               (gate-result (if gate-entry (cdr gate-entry) -1)))
          (if (not (= bdd-result gate-result))
              (begin
                (set! pass #f)
                (set! fail-count (+ fail-count 1))
                (if (<= fail-count 5)
                    (begin
                      (newline)
                      (display "    MISMATCH: ")
                      (display (format-vector vec))
                      (display " => BDD=")
                      (display (number->string bdd-result))
                      (display " gates=")
                      (display (number->string gate-result))))))))
      vectors)
    (if pass
        (begin (display " PASS") (newline))
        (begin
          (newline)
          (display "    FAIL: ")
          (display (number->string fail-count))
          (display "/")
          (display (number->string n-vectors))
          (display " mismatches")
          (newline)))
    pass))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 4. FULL SYNTHESIS + VERIFY PIPELINE
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (verify-synthesis filename) -- load an AST, synthesize to gates,
;; and verify equivalence for all outputs.
(define (verify-synthesis filename)
  (define ast (read-sv-file filename))
  (define mod (car ast))
  (verify-module mod))

;; (verify-module mod) -- synthesize and verify a single module.
(define (verify-module mod)
  (bdd-env-reset!)
  (gate-reset!)

  (define name (module-name mod))
  (define ports (collect-port-signals (module-ports mod)))
  (define body (module-body-items mod))
  (define outputs (sv-filter (lambda (p) (eq? 'output (car p))) ports))
  (define inputs (sv-filter (lambda (p) (eq? 'input (car p))) ports))

  (define in-names (map (lambda (p) (symbol->string (cadr p))) inputs))
  (define out-names (map (lambda (p) (symbol->string (cadr p))) outputs))

  ;; Create BDD variables for inputs
  (for-each (lambda (p) (bdd-lookup (cadr p))) inputs)

  ;; Build BDDs for combinational logic
  (define bdd-assigns (synth-combinational body))

  (displayln "")
  (displayln "=== Verifying module: " (symbol->string name) " ===")
  (displayln "  Inputs:  " (sv-join ", " in-names))
  (displayln "  Outputs: " (sv-join ", " out-names))
  (displayln "  Assignments: " (number->string (length bdd-assigns)))

  ;; For each output, map to gates and verify
  (define all-pass #t)
  (for-each
    (lambda (asgn)
      (let* ((sig-name (symbol->string (car asgn)))
             (bdd (cdr asgn)))

        ;; Reset gate state for this output
        (gate-reset!)

        ;; Map BDD to gates
        (let ((out-wire (map-bdd-to-gates bdd)))

          ;; Verify
          (let ((ok (verify-bdd-vs-netlist
                      sig-name bdd *netlist* in-names out-wire)))
            (if (not ok) (set! all-pass #f))))))
    bdd-assigns)

  (displayln "")
  (if all-pass
      (displayln "=== Module " (symbol->string name) ": ALL PASS ===")
      (displayln "=== Module " (symbol->string name) ": FAILURES DETECTED ==="))
  (displayln "")
  all-pass)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 5. BUILT-IN UNIT TESTS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (run-verify-unit-tests) -- test the verifier on known-good
;; BDD-to-gate mappings for all basic gate types.
(define (run-verify-unit-tests)
  (displayln "")
  (displayln "========================================")
  (displayln "  svverify.scm -- Unit Tests")
  (displayln "========================================")

  (define pass-count 0)
  (define fail-count 0)

  (define (check name bdd input-names)
    (gate-reset!)
    (let* ((out-wire (map-bdd-to-gates bdd))
           (ok (verify-bdd-vs-netlist name bdd *netlist* input-names out-wire)))
      (if ok
          (set! pass-count (+ pass-count 1))
          (set! fail-count (+ fail-count 1)))))

  ;; Create fresh BDD variables
  (define a (bdd-var "a"))
  (define b (bdd-var "b"))
  (define c (bdd-var "c"))
  (define d (bdd-var "d"))

  ;; Test each gate pattern
  (check "const-true"  (bdd-true)  '())
  (check "const-false" (bdd-false) '())
  (check "wire"        a           '("a"))
  (check "NOT"         (bdd-not a) '("a"))
  (check "AND"         (bdd-and a b) '("a" "b"))
  (check "OR"          (bdd-or a b)  '("a" "b"))
  (check "XOR"         (bdd-xor a b) '("a" "b"))
  (check "NAND"        (bdd-not (bdd-and a b)) '("a" "b"))
  (check "NOR"         (bdd-not (bdd-or a b))  '("a" "b"))
  (check "XNOR"        (bdd-not (bdd-xor a b)) '("a" "b"))
  (check "IMPLIES"     (bdd-implies a b)       '("a" "b"))
  (check "ITE"         (bdd-ite a b c)         '("a" "b" "c"))
  (check "MUX4"        (bdd-ite a (bdd-ite b c d) (bdd-ite b d c))
                        '("a" "b" "c" "d"))
  (check "XOR-chain"   (bdd-xor a (bdd-xor b (bdd-xor c d)))
                        '("a" "b" "c" "d"))
  (check "complex"     (bdd-or (bdd-and a b) (bdd-xor c d))
                        '("a" "b" "c" "d"))
  (check "majority"    (bdd-or (bdd-and a b)
                               (bdd-or (bdd-and b c) (bdd-and a c)))
                        '("a" "b" "c"))
  (check "parity"      (bdd-xor (bdd-xor a b) (bdd-xor c d))
                        '("a" "b" "c" "d"))

  (displayln "")
  (displayln "========================================")
  (displayln "  Results: " (number->string pass-count) " pass, "
             (number->string fail-count) " fail")
  (displayln "========================================")
  (displayln ""))
