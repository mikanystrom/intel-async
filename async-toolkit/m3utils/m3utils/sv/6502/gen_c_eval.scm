;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; gen_c_eval.scm -- Generate C evaluation functions for 6502 ALU
;;
;; Parses ALU.sv AST, builds BDDs, and emits C evaluation functions
;; that compute the same logic as the RTL.
;;
;; Output: written to *gen-c-output-file*
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(load "sv/src/svbase.scm")
(load "sv/src/svbv.scm")
(load "sv/src/svemit-c.scm")

;; Read ALU AST
(define alu-ast (read-sv-file *gen-c-ast-file*))
(define alu-mod (car alu-ast))

(bv-env-reset!)
(width-reset!)

(define name (module-name alu-mod))
(define ports (module-ports alu-mod))
(define body (module-body-items alu-mod))

(extract-port-widths ports)
(extract-decl-widths body)

(define port-sigs (collect-port-signals ports))
(define inputs (sv-filter (lambda (p) (eq? 'input (car p))) port-sigs))
(define outputs (sv-filter (lambda (p) (eq? 'output (car p))) port-sigs))

;; Create BDD variables
(for-each (lambda (p) (bv-lookup (cadr p))) inputs)

;; Build BDDs
(displayln "Building BDDs for " (symbol->string name) "...")
(define assigns (bv-synth-combinational body))

;; Report
(for-each
  (lambda (a)
    (let* ((sig (car a))
           (bv (cdr a))
           (w (length bv))
           (nodes (fold-left + 0 (map bdd-size bv))))
      (displayln "  " (symbol->string sig) " [" (number->string w)
                 " bits]: " (number->string nodes) " BDD nodes")))
  assigns)

;; Generate C header -- write directly to file port
(displayln "Generating C evaluation functions...")
(define oport (open-output-file *gen-c-output-file*))
(emit-c-eval-to-port (symbol->string name) inputs assigns oport)
(close-output-port oport)
(displayln "Written to " *gen-c-output-file*)
