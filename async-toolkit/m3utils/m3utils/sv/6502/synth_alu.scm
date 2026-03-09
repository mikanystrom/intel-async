;; synth_alu.scm -- Synthesize 6502 ALU and verify
;;
;; Loads ALU.sv AST, builds BDDs, emits gate-level SV,
;; and reports per-output BDD complexity.

(load "sv/src/svbase.scm")
(load "sv/src/svbv.scm")
(load "sv/src/svemit.scm")

(define ast (read-sv-file "/tmp/6502_ALU.ast.scm"))
(define mod (car ast))

(define assigns (bv-synth-module mod))

;; Emit gate-level SV
(define port-sigs (collect-port-signals (module-ports mod)))
(define inputs (sv-filter (lambda (p) (eq? 'input (car p))) port-sigs))
(define outputs (sv-filter (lambda (p) (eq? 'output (car p))) port-sigs))

(let ((port (open-output-file "/tmp/6502_ALU_gates.sv")))
  (emit-gate-module-to-port (symbol->string (module-name mod))
                            inputs outputs assigns port)
  (close-output-port port))

(displayln "")
(displayln "Gate-level SV written to /tmp/6502_ALU_gates.sv")
(displayln "Internal gate nodes: " (number->string *emit-counter*))
