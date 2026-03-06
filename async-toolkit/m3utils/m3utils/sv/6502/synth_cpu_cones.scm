;; synth_cpu_cones.scm -- Analyze combinational cones in 6502 CPU
;;
;; Loads the cpu.sv AST, identifies each combinational output,
;; builds BDDs, and reports cone complexity.

(load "sv/src/svbase.scm")
(load "sv/src/svbv.scm")

(define ast (read-sv-file "/tmp/6502_cpu.ast.scm"))
(define mod (car ast))

(define assigns (bv-synth-module mod))

(displayln "")
(displayln "=== 6502 CPU Combinational Cone Analysis ===")
(displayln "Total combinational outputs: " (number->string (length assigns)))

(define total-nodes 0)
(define max-nodes 0)
(define max-name "")

(for-each
  (lambda (a)
    (let* ((sig (car a))
           (bv (cdr a))
           (w (length bv))
           (nodes (fold-left + 0 (map bdd-size bv))))
      (set! total-nodes (+ total-nodes nodes))
      (if (> nodes max-nodes)
          (begin
            (set! max-nodes nodes)
            (set! max-name (symbol->string sig))))))
  assigns)

(displayln "Total BDD nodes across all cones: " (number->string total-nodes))
(displayln "Largest cone: " max-name " (" (number->string max-nodes) " nodes)")
