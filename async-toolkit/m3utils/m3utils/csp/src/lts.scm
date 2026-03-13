; Copyright (c) 2026 Mika Nystrom

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  lts.scm -- Labelled Transition System extraction from compiled CSP
;;
;;  Extracts an explicit LTS from text9 (the compiled block list).
;;  An LTS is a tuple (S, s0, A, ->) where:
;;    S  = set of states (block labels)
;;    s0 = initial state
;;    A  = alphabet of actions (channel operations + tau)
;;    -> = transitions: S x A x S
;;
;;  After (compile!), text9 holds a list of blocks.  Each block:
;;    (sequence (label X) ... (goto Y))
;;  The first non-var1 statement determines the action on that edge.
;;
;;  Usage:
;;    (extract-lts text9 *cellinfo*)           -> lts-object
;;    (print-lts lts)                          -> void (prints to stdout)
;;    (write-lts-aut lts filename)             -> void (Aldebaran .aut)
;;    (extract-process-lts! scm-filename)      -> lts-object
;;    (extract-system-lts! sys-filename)       -> alist of (name . lts)
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  1. LTS construction helpers
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (make-lts states initial alphabet transitions)
  (list (cons 'states      states)
        (cons 'initial     initial)
        (cons 'alphabet    alphabet)
        (cons 'transitions transitions)))

(define (lts-states lts)      (cdr (assq 'states      lts)))
(define (lts-initial lts)     (cdr (assq 'initial     lts)))
(define (lts-alphabet lts)    (cdr (assq 'alphabet    lts)))
(define (lts-transitions lts) (cdr (assq 'transitions lts)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  2. Block analysis: extract action and successors from a block
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (block-label blk)
  ;; Return the label symbol from a block.
  ;; A block is either (label X) or (sequence (label X) ...).
  (cond ((label? blk)
         (cadr blk))
        ((sequence? blk)
         (let ((first (cadr blk)))
           (if (label? first)
               (cadr first)
               #f)))
        (else #f)))

(define (block-stmts blk)
  ;; Return the statements of a block (excluding the label).
  (cond ((label? blk)    '())
        ((sequence? blk) (cddr blk))
        (else            (list blk))))

(define (skip-var1s stmts)
  ;; Skip leading var1 declarations from a statement list.
  (cond ((null? stmts) '())
        ((and (pair? (car stmts))
              (eq? 'var1 (car (car stmts))))
         (skip-var1s (cdr stmts)))
        (else stmts)))

(define (extract-port-name port-expr)
  ;; Extract the port name symbol from a port expression:
  ;;   (id C)                  -> C
  ;;   (array-access (id C) N) -> C
  ;;   else                    -> ?
  (cond ((not (pair? port-expr)) '?)
        ((eq? 'id (car port-expr))
         (cadr port-expr))
        ((eq? 'array-access (car port-expr))
         (extract-port-name (cadr port-expr)))
        (else '?)))

(define (classify-action stmt)
  ;; Given a statement, return the LTS action label:
  ;;   (send (id C) ...)              -> (send C)
  ;;   (send (array-access (id C) N)) -> (send C)
  ;;   (recv (id C) ...)              -> (recv C)
  ;;   (waitfor ...)                  -> tau
  ;;   (waiting-if ...)               -> tau
  ;;   (lock ...)                     -> tau  (internal: waiting-if impl)
  ;;   else                           -> #f (not a blocking statement)
  (if (not (pair? stmt))
      #f
      (case (car stmt)
        ((send)    (list 'send (extract-port-name (cadr stmt))))
        ((recv)    (list 'recv (extract-port-name (cadr stmt))))
        ((waitfor) 'tau)
        ((waiting-if) 'tau)
        ((lock)    'tau)
        (else      #f))))

(define (find-block-action stmts)
  ;; Find the first blocking action in a list of statements.
  ;; Skips var1s, assigns, structdecls, evals — these are non-blocking
  ;; computation.  Returns the action label or 'tau if none found.
  (define (scan lst)
    (cond ((null? lst) 'tau)
          (else
           (let ((s (car lst)))
             (if (not (pair? s))
                 (scan (cdr lst))
                 (let ((act (classify-action s)))
                   (if act
                       act
                       (case (car s)
                         ((var1 assign structdecl eval while
                           local-if sequential-loop)
                          (scan (cdr lst)))
                         (else 'tau)))))))))
  (scan stmts))

(define (collect-gotos stmts)
  ;; Collect all goto targets reachable from a statement list.
  ;; Handles:
  ;;   (goto X)              -> (X)
  ;;   (local-if (G1 S1) (G2 S2) ...)  -> recursively collect from each Si
  ;;   sequences ending with goto or local-if
  (define targets '())

  (define (scan lst)
    (if (null? lst)
        'done
        (let ((s (car lst)))
          (cond
           ;; direct goto
           ((and (pair? s) (eq? 'goto (car s)))
            (set! targets (cons (cadr s) targets)))
           ;; local-if: recurse into each clause body
           ((and (pair? s) (eq? 'local-if (car s)))
            (for-each
             (lambda (clause)
               (let ((body (cdr clause)))
                 (for-each (lambda (b) (scan-stmt b)) body)))
             (cdr s)))
           ;; nested sequence: scan its contents
           ((sequence? s)
            (scan (cdr s)))
           (else 'skip))
          (scan (cdr lst)))))

  (define (scan-stmt s)
    (cond ((and (pair? s) (eq? 'goto (car s)))
           (set! targets (cons (cadr s) targets)))
          ((and (pair? s) (eq? 'local-if (car s)))
           (for-each
            (lambda (clause)
              (let ((body (cdr clause)))
                (for-each scan-stmt body)))
            (cdr s)))
          ((sequence? s)
           (scan (cdr s)))
          (else 'skip)))

  (scan stmts)
  ;; Remove duplicates
  (let loop ((ts targets) (result '()))
    (if (null? ts)
        (reverse result)
        (if (memq (car ts) result)
            (loop (cdr ts) result)
            (loop (cdr ts) (cons (car ts) result))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  3. Main extraction
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (extract-lts blocks cellinfo)
  ;; Extract an LTS from text9 (a list of blocks) and the cellinfo.
  ;;
  ;; text9 = ((goto START) block1 block2 ...)
  ;; where each block is (sequence (label X) ... (goto Y))
  ;; or just (label END) for terminal states.
  ;;
  ;; Returns an LTS object.

  (if (or (null? blocks) (not (pair? blocks)))
      (error "extract-lts: empty or invalid text9"))

  ;; The first element is (goto START) — gives us the initial state
  (let* ((entry    (car blocks))
         (initial  (if (and (pair? entry) (eq? 'goto (car entry)))
                       (cadr entry)
                       (error "extract-lts: first element is not (goto X): "
                              entry)))
         (rest     (cdr blocks)))

    ;; Walk each block, collect states, transitions, and alphabet
    (let ((states      '())
          (transitions '())
          (alphabet    '()))

      ;; Process each block
      (for-each
       (lambda (blk)
         (let ((lbl (block-label blk)))
           (if lbl
               (begin
                 ;; Add state
                 (if (not (memq lbl states))
                     (set! states (cons lbl states)))

                 ;; Get the block body and analyze
                 (let* ((stmts   (block-stmts blk))
                        (action  (find-block-action stmts))
                        (targets (collect-gotos stmts)))

                   ;; Add action to alphabet (if not tau)
                   (if (and (not (eq? action 'tau))
                            (not (member action alphabet)))
                       (set! alphabet (cons action alphabet)))

                   ;; Create transitions to each target
                   (for-each
                    (lambda (tgt)
                      ;; Ensure target state is registered
                      (if (not (memq tgt states))
                          (set! states (cons tgt states)))
                      (let ((trans (list lbl action tgt)))
                        (if (not (member trans transitions))
                            (set! transitions (cons trans transitions)))))
                    targets)

                   ;; If no targets and non-empty stmts, this is a terminal
                   ;; state (e.g., END).  No transitions needed.
                   )))))
       rest)

      ;; Build the LTS
      (make-lts (reverse states)
                initial
                (reverse alphabet)
                (reverse transitions)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  4. Action formatting
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (format-action act)
  ;; Format an action for display:
  ;;   (send C) -> "C!"
  ;;   (recv C) -> "C?"
  ;;   tau      -> "tau"
  (cond ((eq? act 'tau) "tau")
        ((and (pair? act) (eq? 'send (car act)))
         (string-append (symbol->string (cadr act)) "!"))
        ((and (pair? act) (eq? 'recv (car act)))
         (string-append (symbol->string (cadr act)) "?"))
        (else (stringify act))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  5. Pretty-printing
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (print-lts lts)
  ;; Print an LTS in human-readable form.
  (dis dnl "=== LTS ===" dnl)
  (dis "States:      " (stringify (lts-states lts)) dnl)
  (dis "Initial:     " (symbol->string (lts-initial lts)) dnl)
  (dis "Alphabet:    ")
  (for-each (lambda (a) (dis (format-action a) " ")) (lts-alphabet lts))
  (dis dnl)
  (dis "Transitions:" dnl)
  (for-each
   (lambda (trans)
     (let ((src (car trans))
           (act (cadr trans))
           (dst (caddr trans)))
       (dis "  " (symbol->string src)
            " --" (format-action act) "--> "
            (symbol->string dst) dnl)))
   (lts-transitions lts))
  (dis "  (" (number->string (length (lts-states lts))) " states, "
       (number->string (length (lts-transitions lts))) " transitions)"
       dnl)
  (dis "===========" dnl dnl))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  6. Aldebaran .aut output
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (write-lts-aut lts filename)
  ;; Write the LTS in Aldebaran .aut format:
  ;;   des (initial, num_transitions, num_states)
  ;;   (src, "label", dst)
  ;;   ...
  ;;
  ;; States are mapped to integers starting from 0.
  ;; The initial state is always mapped to 0.

  (let* ((states  (lts-states lts))
         (init    (lts-initial lts))
         (trans   (lts-transitions lts))
         (nstates (length states))
         (ntrans  (length trans)))

    ;; Build state-to-integer mapping.
    ;; Initial state gets index 0.
    (let ((state-map '())
          (next-id   0))

      ;; Assign 0 to initial state first
      (set! state-map (list (cons init 0)))
      (set! next-id 1)

      ;; Assign ids to remaining states
      (for-each
       (lambda (s)
         (if (not (assq s state-map))
             (begin
               (set! state-map (cons (cons s next-id) state-map))
               (set! next-id (+ next-id 1)))))
       states)

      ;; Write the file
      (let ((p (open-output-file filename)))
        ;; Header
        (display "des (0, " p)
        (display ntrans p)
        (display ", " p)
        (display nstates p)
        (display ")" p)
        (newline p)

        ;; Transitions
        (for-each
         (lambda (t)
           (let ((src-id (cdr (assq (car t)   state-map)))
                 (label  (format-action (cadr t)))
                 (dst-id (cdr (assq (caddr t) state-map))))
             (display "(" p)
             (display src-id p)
             (display ", \"" p)
             (display label p)
             (display "\", " p)
             (display dst-id p)
             (display ")" p)
             (newline p)))
         trans)

        (close-output-port p)
        (dis "Wrote " filename ": "
             (number->string nstates) " states, "
             (number->string ntrans) " transitions" dnl)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  7. Convenience: load .text9.scm directly
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (load-text9 filename)
  ;; Load a .text9.scm file (written by do-compile-m3!) and return its
  ;; contents as the text9 block list.
  (let* ((p   (open-input-file filename))
         (obj (read-big-int p)))
    (close-input-port p)
    obj))

(define (extract-lts-from-text9-file filename)
  ;; Load a .text9.scm file and extract its LTS.
  ;; cellinfo is not needed for basic extraction (port names come from
  ;; the send/recv statements directly).
  (let ((blocks (load-text9 filename)))
    (extract-lts blocks '())))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  8. Convenience: compile and extract
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (extract-process-lts! scm-file)
  ;; Load a .scm parse tree, compile it through all 9 phases, and
  ;; extract the LTS from the resulting text9.
  (loaddata0! scm-file)
  (loaddata1!)
  (compile!)
  (let ((lts (extract-lts text9 *cellinfo*)))
    (print-lts lts)
    lts))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  9. System-level extraction
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (extract-system-lts! sys-file)
  ;; Parse a .sys file, generate .scm files for each process type,
  ;; compile each, and return an alist of (cell-name . lts).
  ;;
  ;; This reuses the cspbuild infrastructure for parsing and .scm
  ;; generation, but stops after compile! (no code generation).

  (dis "extract-system-lts!: parsing " sys-file " ..." dnl)
  (let ((sys (parse-sys-file sys-file)))

    (dis "extract-system-lts!: validating ..." dnl)
    (validate-system! sys)

    (let ((tmp-dir (string-append (sys-name sys) ".tmp/"))
          (results '()))

      (system (string-append "mkdir -p " (shell-quote tmp-dir)))

      ;; For each process type, generate .scm, compile, extract LTS
      (for-each
       (lambda (pr)
         (let* ((pname     (proc-name pr))
                (cell-name (string-append (sys-name sys) "." pname))
                (escaped   (escape-name cell-name))
                (scm-file  (string-append escaped ".scm")))

           (dis "extract-system-lts!: processing " cell-name " ..." dnl)

           ;; Generate .scm (run cspfe, patch cellinfo)
           (generate-scm! pr (sys-name sys) tmp-dir)

           ;; Compile through all 9 phases
           (loaddata0! scm-file)
           (loaddata1!)
           (compile!)

           ;; Extract LTS
           (let ((lts (extract-lts text9 *cellinfo*)))
             (print-lts lts)
             (set! results (cons (cons cell-name lts) results)))))
       (sys-processes sys))

      (dis "extract-system-lts!: done. "
           (number->string (length results)) " process LTSs extracted." dnl)
      (reverse results))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(dis "lts.scm loaded." dnl)
