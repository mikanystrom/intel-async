;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; svlint-driver.scm -- Standalone driver for svlint
;;
;; Loads svbase.scm and svlint.scm, reads an AST file, and runs
;; all lint checks.  Invoked by run-svlint.sh via svsynth.
;;
;; The AST filename is passed via the global *svlint-ast-file*
;; which is set by the wrapper before loading this file.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(load "sv/src/svbase.scm")
(load "sv/src/svlint.scm")

(define ast (read-sv-file *svlint-ast-file*))
(lint-all ast)
