;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; svread.scm -- Backward-compatible entry point
;;
;; This file loads both svbase.scm and svlint.scm, providing the
;; same API as the original monolithic svread.scm.
;;
;; For new code, prefer loading the individual files:
;;   (load "sv/src/svbase.scm")   -- base utilities and AST navigation
;;   (load "sv/src/svlint.scm")   -- lint checks
;;   (load "sv/src/svgen.scm")    -- SystemVerilog regeneration
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(load "sv/src/svbase.scm")
(load "sv/src/svlint.scm")
