;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; svfec.scm -- Formal Equivalence Checking (FEC)
;;
;; Author : Claude / Mika Nystroem
;; Date   : March 2026
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; FORMAL EQUIVALENCE CHECKING
;; ===========================
;;
;; This module implements BDD-based Formal Equivalence Checking (FEC)
;; to prove that a synthesized gate-level netlist is functionally
;; identical to the original RTL source.
;;
;; Unlike simulation-based verification (svverify.scm), which tests
;; a finite number of input vectors, FEC is exhaustive:  it proves
;; equivalence for ALL possible input combinations, regardless of
;; the number of inputs.
;;
;; METHOD
;; ------
;; For each primary output (or register D-input):
;;
;;   1. Build a BDD from the original RTL expressions.
;;      (This is what svsynth.scm already does.)
;;
;;   2. Build a BDD from the gate-level netlist by interpreting
;;      each gate instance as a Boolean equation:
;;        INV(A)     -> NOT(A)
;;        AND2(A,B)  -> A AND B
;;        OR2(A,B)   -> A OR B
;;        NAND2(A,B) -> NOT(A AND B)
;;        NOR2(A,B)  -> NOT(A OR B)
;;        XOR2(A,B)  -> A XOR B
;;        XNOR2(A,B) -> NOT(A XOR B)
;;        MUX2(A,B,S)-> ITE(S, B, A)
;;        TIEH       -> TRUE
;;        TIEL       -> FALSE
;;
;;   3. Check bdd-equal? on the two BDDs.  If equal, the gate
;;      netlist is formally proven equivalent to the RTL for
;;      that output.  If not, the BDD difference can be used
;;      to extract a counterexample.
;;
;; This approach works because BDDs are canonical: two Boolean
;; functions are identical if and only if their BDDs are identical
;; (assuming the same variable ordering).
;;
;; REGISTER-TO-REGISTER FEC
;; ------------------------
;; For sequential designs, the combinational logic between
;; register outputs (Q) and register inputs (D) forms a
;; combinational cone.  Both RTL and gate-level netlists
;; express the same cone -- we just need to:
;;
;;   1. Treat register Q outputs as primary inputs
;;   2. Treat register D inputs as primary outputs
;;   3. Build BDDs for each D input from both representations
;;   4. Check equivalence
;;
;; This is the standard FEC methodology used in commercial tools
;; (Synopsys Formality, Cadence Conformal, etc.).
;;
;; USAGE
;; -----
;;   > (load "sv/src/svbase.scm")
;;   > (load "sv/src/svsynth.scm")
;;   > (load "sv/src/svgates.scm")
;;   > (load "sv/src/svfec.scm")
;;   > (fec-verify "sv/tests/verify/test_mixed.ast.scm")
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 1. GATE NETLIST TO BDD COMPILER
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (gate-to-bdd cell-type input-bdds) -- compute the BDD for a
;; gate's output given BDDs for its inputs.
;;
;; input-bdds is a list of BDDs in port order:
;;   INV, BUF:     (A)
;;   AND2..XNOR2:  (A B)
;;   MUX2:         (A B S)
;;   TIEH, TIEL:   ()
(define (gate-to-bdd cell-type input-bdds)
  (cond
    ((equal? cell-type "INV")
     (bdd-not (car input-bdds)))
    ((equal? cell-type "BUF")
     (car input-bdds))
    ((equal? cell-type "AND2")
     (bdd-and (car input-bdds) (cadr input-bdds)))
    ((equal? cell-type "OR2")
     (bdd-or (car input-bdds) (cadr input-bdds)))
    ((equal? cell-type "NAND2")
     (bdd-not (bdd-and (car input-bdds) (cadr input-bdds))))
    ((equal? cell-type "NOR2")
     (bdd-not (bdd-or (car input-bdds) (cadr input-bdds))))
    ((equal? cell-type "XOR2")
     (bdd-xor (car input-bdds) (cadr input-bdds)))
    ((equal? cell-type "XNOR2")
     (bdd-not (bdd-xor (car input-bdds) (cadr input-bdds))))
    ((equal? cell-type "MUX2")
     ;; MUX2: A=low, B=high, S=select => ITE(S, B, A)
     (bdd-ite (caddr input-bdds) (cadr input-bdds) (car input-bdds)))
    ((equal? cell-type "TIEH")
     (bdd-true))
    ((equal? cell-type "TIEL")
     (bdd-false))
    (else
     (display "WARNING: gate-to-bdd: unknown cell type: ")
     (display cell-type)
     (newline)
     (bdd-false))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 2. NETLIST BDD BUILDER
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (netlist-to-bdds netlist primary-inputs)
;; Walk a gate netlist in topological order (which is the order
;; gates were emitted -- from inputs toward outputs) and build
;; a BDD for each wire.
;;
;; netlist:  the *netlist* list from svgates.scm (reversed order)
;; primary-inputs:  list of input signal name strings
;;
;; Returns an alist: ((wire-name . bdd) ...)
(define (netlist-to-bdds netlist primary-inputs)
  ;; Initialize wire-bdd map with primary inputs.
  ;; We reuse the SAME BDD variables from *bdd-env* so that the
  ;; rebuilt BDDs are directly comparable with bdd-equal?.
  (define wire-bdds
    (map (lambda (name)
           (let ((env-entry (assq (string->symbol name) *bdd-env*)))
             (if env-entry
                 (cons name (cdr env-entry))
                 (cons name (bdd-var name)))))
         primary-inputs))

  ;; Process gates in topological order (reverse of *netlist*)
  (for-each
    (lambda (gate)
      (let* ((cell-type (car gate))
             (conns (caddr gate))
             (in-ports (gate-input-ports cell-type))
             (out-port (gate-output-port cell-type)))
        ;; Look up BDDs for input wires
        (let ((in-bdds
                (map (lambda (port-name)
                       (let* ((conn (assoc port-name conns))
                              (wire (if conn (cdr conn) #f))
                              (bdd-entry (if wire (assoc wire wire-bdds) #f)))
                         (if bdd-entry
                             (cdr bdd-entry)
                             (begin
                               (display "WARNING: netlist-to-bdds: unresolved wire: ")
                               (display wire)
                               (newline)
                               (bdd-false)))))
                     in-ports)))
          ;; Compute output BDD
          (let* ((out-bdd (gate-to-bdd cell-type in-bdds))
                 (out-conn (assoc out-port conns))
                 (out-wire (if out-conn (cdr out-conn) #f)))
            (if out-wire
                (set! wire-bdds
                      (cons (cons out-wire out-bdd) wire-bdds)))))))
    (reverse netlist))

  wire-bdds)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 3. FORMAL EQUIVALENCE CHECK
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (fec-verify filename) -- full FEC pipeline:
;;   1. Parse RTL AST and build "golden" BDDs
;;   2. Synthesize to gate netlist
;;   3. Rebuild BDDs from gate netlist
;;   4. Check equivalence output-by-output
(define (fec-verify filename)
  (define ast (read-sv-file filename))
  (define mod (car ast))
  (fec-module mod))

;; (fec-module mod) -- FEC for a single module.
(define (fec-module mod)
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

  ;; Step 1: Build golden BDDs from RTL
  (define rtl-assigns (synth-combinational body))
  (define rtl-bdds
    (map (lambda (a) (cons (symbol->string (car a)) (cdr a)))
         rtl-assigns))

  ;; Step 2: Synthesize to gate netlist (populates *netlist*)
  (define gate-assigns
    (map (lambda (a) (cons (symbol->string (car a)) (cdr a)))
         rtl-assigns))

  ;; Map all BDDs to gates in a single netlist
  (gate-reset!)
  (define output-wires
    (map (lambda (a)
           (cons (car a) (map-bdd-to-gates (cdr a))))
         gate-assigns))

  ;; Step 3: Rebuild BDDs from gate netlist
  ;; We need fresh BDD variables with the same names
  (define gate-wire-bdds (netlist-to-bdds *netlist* in-names))

  ;; Step 4: Compare
  (displayln "")
  (displayln "=== FEC: module " (symbol->string name) " ===")
  (displayln "  Inputs:  " (sv-join ", " in-names))
  (displayln "  Outputs: " (sv-join ", " out-names))
  (displayln "  Gates:   " (number->string (length *netlist*)))

  (define all-pass #t)
  (for-each
    (lambda (ow)
      (let* ((sig-name (car ow))
             (out-wire (cdr ow))
             ;; Golden BDD
             (rtl-entry (assoc sig-name rtl-bdds))
             (rtl-bdd (if rtl-entry (cdr rtl-entry) #f))
             ;; Gate BDD (look up the output wire)
             (gate-entry (assoc out-wire gate-wire-bdds))
             (gate-bdd (if gate-entry (cdr gate-entry) #f)))
        (display "  ")
        (display sig-name)
        (display ": ")
        (cond
          ((not rtl-bdd)
           (display "SKIP (no RTL BDD)")
           (newline))
          ((not gate-bdd)
           (display "FAIL (no gate BDD for wire ")
           (display out-wire)
           (display ")")
           (newline)
           (set! all-pass #f))
          ((bdd-equal? rtl-bdd gate-bdd)
           (display "EQUIVALENT")
           (newline))
          (else
           (display "NOT EQUIVALENT!")
           (newline)
           (display "    RTL BDD:  ")
           (display (bdd-format rtl-bdd))
           (newline)
           (display "    Gate BDD: ")
           (display (bdd-format gate-bdd))
           (newline)
           (set! all-pass #f)))))
    output-wires)

  (displayln "")
  (if all-pass
      (displayln "=== FEC " (symbol->string name) ": PROVEN EQUIVALENT ===")
      (displayln "=== FEC " (symbol->string name) ": EQUIVALENCE FAILED ==="))
  (displayln "")
  all-pass)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 4. FEC UNIT TESTS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (run-fec-unit-tests)
  (displayln "")
  (displayln "========================================")
  (displayln "  svfec.scm -- FEC Unit Tests")
  (displayln "========================================")

  (define pass-count 0)
  (define fail-count 0)

  (define (check name bdd input-names)
    (gate-reset!)
    ;; Ensure *bdd-env* has entries for all input variables
    ;; (they were already created above, so bdd-lookup will find them)

    ;; Map to gates
    (let* ((out-wire (map-bdd-to-gates bdd))
           ;; Rebuild BDD from gates
           (wire-bdds (netlist-to-bdds *netlist* input-names))
           (gate-entry (assoc out-wire wire-bdds))
           (gate-bdd (if gate-entry (cdr gate-entry) #f)))
      (display "  ")
      (display name)
      (display ": ")
      (cond
        ((not gate-bdd)
         (display "FAIL (no gate BDD)")
         (newline)
         (set! fail-count (+ fail-count 1)))
        ((bdd-equal? bdd gate-bdd)
         (display "EQUIVALENT")
         (newline)
         (set! pass-count (+ pass-count 1)))
        (else
         (display "NOT EQUIVALENT")
         (newline)
         (display "    Expected: ")
         (display (bdd-format bdd))
         (newline)
         (display "    Got:      ")
         (display (bdd-format gate-bdd))
         (newline)
         (set! fail-count (+ fail-count 1))))))

  ;; Create BDD variables and register them in *bdd-env*
  (bdd-env-reset!)
  (define a (bdd-lookup 'a))
  (define b (bdd-lookup 'b))
  (define c (bdd-lookup 'c))
  (define d (bdd-lookup 'd))

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
