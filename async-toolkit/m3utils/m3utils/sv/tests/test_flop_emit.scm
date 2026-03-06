(load "sv/src/svbase.scm")
(load "sv/src/svbv.scm")
(load "sv/src/svemit.scm")

;;; Parse the ALU pipeline module and synthesize the combinational cone

(define ast (read-sv-file "/tmp/flop-demo/alu_pipe.ast.scm"))
(define mod (car ast))

(bv-env-reset!)
(width-reset!)

(define name (module-name mod))
(define ports (module-ports mod))
(define body (module-body-items mod))

(extract-port-widths ports)
(extract-decl-widths body)

(define port-sigs (collect-port-signals ports))

;; For flop-to-flop synthesis: the "inputs" to the combinational cone
;; are all input ports EXCEPT clk, plus any signals read but not
;; driven purely combinationally (i.e., current-state flop outputs).
;; Here: a_q, b_q, op_q are inputs; count/result is both input (Q) and output (D).
;;
;; Since the always_ff reads 'result' (it appears in the case RHS would if
;; there were a feedback path), and 'clk' is just the clock, we filter clk out.

(define inputs
  (sv-filter (lambda (p)
               (and (eq? 'input (car p))
                    (not (eq? 'clk (cadr p)))))
             port-sigs))
(define outputs
  (sv-filter (lambda (p) (eq? 'output (car p))) port-sigs))

;; Create BDD variables for inputs (the Q-side of the flop boundary)
(for-each (lambda (p) (bv-lookup (cadr p))) inputs)

;; Synthesize: extracts combinational cone from always_ff
(define assigns (bv-synth-combinational body))

(displayln "  Combinational cone (flop-to-flop path):")
(displayln "    Inputs (Q-side):  " (sv-join ", " (map (lambda (p)
  (string-append (symbol->string (cadr p))
                 "[" (number->string (width-get (cadr p))) "]")) inputs)))
(displayln "    Outputs (D-side): " (sv-join ", " (map (lambda (a)
  (string-append (symbol->string (car a))
                 "[" (number->string (length (cdr a))) "]")) assigns)))

(define total-input-bits
  (fold-left + 0 (map (lambda (p) (width-get (cadr p))) inputs)))
(displayln "    Total: " (number->string total-input-bits) " input bits -> "
           (number->string (fold-left + 0 (map (lambda (a) (length (cdr a))) assigns)))
           " output bits")

(for-each
  (lambda (a)
    (display "    ")
    (display (symbol->string (car a)))
    (display ": ")
    (display (number->string (length (cdr a))))
    (display " bits, ")
    (display (number->string
               (fold-left + 0
                 (map (lambda (b) (bdd-size b)) (cdr a)))))
    (displayln " BDD nodes"))
  assigns)

;; Emit gate-level SV (combinational only -- no flops)
(define gate-sv
  (emit-gate-module (symbol->string name) inputs outputs assigns))

(displayln "")
(displayln "--- Gate-level SV (combinational cone) ---")
(displayln gate-sv)

(let ((port (open-output-file "/tmp/flop-demo/alu_pipe_gates.sv")))
  (display gate-sv port)
  (close-output-port port))

(displayln "  Written to /tmp/flop-demo/alu_pipe_gates.sv")
(displayln "  Internal MUX nodes: " (number->string *emit-counter*))
