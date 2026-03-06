; Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information.
; SPDX-License-Identifier: Apache-2.0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  cspbuild.scm -- Scheme-native system builder for CSP
;;
;;  Parses .sys files describing a system of communicating processes,
;;  runs cspfe to produce .scm intermediate files, patches cellinfo
;;  with port definitions, writes .procs files, and drives the
;;  compilation pipeline through drive! and cm3.
;;
;;  Load after setup.scm:
;;    (load "cspbuild.scm")
;;    (build-system! "hello.sys")
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  1. Utilities
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (escape-name name)
  ;; Escape special characters in a cell name for use as a filename.
  ;; Matches the encoding used by M3Ident.Escape:
  ;;   "Hello.WORLD"    -> "Hello_46_WORLD"
  ;;   "foo(bar)"       -> "foo_40_bar_41_"
  ;;   "a(1,2)"         -> "a_40_1_44_2_41_"
  (let loop ((i 0) (result ""))
    (if (= i (string-length name))
        result
        (let ((c (string-ref name i)))
          (loop (+ i 1)
                (string-append
                 result
                 (cond ((char=? c #\.) "_46_")
                       ((char=? c #\() "_40_")
                       ((char=? c #\)) "_41_")
                       ((char=? c #\,) "_44_")
                       ((char=? c #\ ) "_20_")
                       (else (string c)))))))))

(define (sys-error msg . args)
  (error (apply string-append "cspbuild: " msg
                (map (lambda (a)
                       (if (string? a) a
                           (stringify a)))
                     args))))

(define (get-option options key default)
  ;; Extract a keyword option from a flat options list.
  ;; (get-option '(slack 2 run #t) 'slack 1) => 2
  (let loop ((opts options))
    (cond ((null? opts) default)
          ((and (symbol? (car opts)) (eq? (car opts) key))
           (if (null? (cdr opts))
               (sys-error "missing value for option '"
                          (symbol->string key) "'")
               (cadr opts)))
          (else (loop (cdr opts))))))

;; Record accessors for the system data model:
;;   (system NAME (CHANNELS...) (PROCESSES...) (INSTANCES...))
(define (sys-name sys)       (cadr sys))
(define (sys-channels sys)   (caddr sys))
(define (sys-processes sys)  (cadddr sys))
(define (sys-instances sys)  (car (cddddr sys)))

;; Channel: (channel NAME WIDTH SLACK)
(define (chan-name ch)  (cadr ch))
(define (chan-width ch) (caddr ch))
(define (chan-slack ch) (cadddr ch))

;; Process: (process NAME BODY (PORT ...))
(define (proc-name pr)  (cadr pr))
(define (proc-body pr)  (caddr pr))
(define (proc-ports pr) (cadddr pr))

;; Port: (port NAME DIR WIDTH)
(define (port-name pt)  (cadr pt))
(define (port-dir pt)   (caddr pt))
(define (port-width pt) (cadddr pt))

;; Instance: (instance NAME PROC-NAME ((PORT . CHAN) ...))
(define (inst-name inst)     (cadr inst))
(define (inst-proc-name inst)(caddr inst))
(define (inst-bindings inst) (cadddr inst))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  2. Tokenizer
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define *sys-keywords*
  '("system" "process" "begin" "end" "var" "channel"
    "port" "in" "out" "slack"))

(define (sys-tokenize port)
  ;; Tokenize a .sys file.  Returns a list of (kind value line) tokens.
  ;; kind: ident keyword int string body punct eof
  ;;
  ;; Inline CSP bodies are delimited by %[% ... %]% and returned as a
  ;; single (body "raw text" line) token.  The raw text is passed to
  ;; cspfe verbatim.  The scanner tracks string literals inside the
  ;; body so that a %]% inside a CSP string does not end the body.

  (define line 1)

  (define (peek) (peek-char port))
  (define (advance)
    (let ((c (read-char port)))
      (if (and (char? c) (char=? c #\newline))
          (set! line (+ line 1)))
      c))

  (define (skip-line-comment)
    (let loop ()
      (let ((c (advance)))
        (if (or (eof-object? c) (char=? c #\newline))
            'done
            (loop)))))

  (define (skip-block-comment)
    ;; (* ... *) with nesting
    (let loop ((depth 1))
      (let ((c (advance)))
        (cond ((eof-object? c)
               (sys-error "unterminated (* comment"))
              ((and (char=? c #\() (char? (peek)) (char=? (peek) #\*))
               (advance) (loop (+ depth 1)))
              ((and (char=? c #\*) (char? (peek)) (char=? (peek) #\)))
               (advance) (if (> depth 1) (loop (- depth 1))))
              (else (loop depth))))))

  (define (read-ident first-char)
    (let loop ((chars (list first-char)))
      (let ((c (peek)))
        (if (and (char? c)
                 (or (char-alphabetic? c) (char-numeric? c)
                     (char=? c #\_)))
            (begin (advance) (loop (cons c chars)))
            (list->string (reverse chars))))))

  (define (read-integer first-char)
    (let loop ((chars (list first-char)))
      (let ((c (peek)))
        (if (and (char? c) (char-numeric? c))
            (begin (advance) (loop (cons c chars)))
            (string->number (list->string (reverse chars)))))))

  (define (read-string-lit)
    ;; Opening " already consumed
    (let loop ((chars '()))
      (let ((c (advance)))
        (cond ((eof-object? c)
               (sys-error "unterminated string literal"))
              ((char=? c #\")
               (list->string (reverse chars)))
              ((char=? c #\\)
               (loop (cons (advance) chars)))
              (else (loop (cons c chars)))))))

  (define (read-csp-body)
    ;; Opening %[% already consumed.  Read raw characters until %]%.
    ;; Track CSP string literals so %]% inside a string is not
    ;; mistaken for the end delimiter.
    (let ((start-line line))
      (let loop ((chars '()) (in-string #f))
        (let ((c (advance)))
          (cond
           ((eof-object? c)
            (sys-error "unterminated %[% body starting at line "
                       (number->string start-line)))
           ;; inside a CSP string literal
           (in-string
            (cond
             ((char=? c #\\)
              (let ((c2 (advance)))
                (loop (cons c2 (cons c chars)) #t)))
             ((char=? c #\")
              (loop (cons c chars) #f))
             (else
              (loop (cons c chars) #t))))
           ;; entering a CSP string literal
           ((char=? c #\")
            (loop (cons c chars) #t))
           ;; possible %]% delimiter
           ((char=? c #\%)
            (if (and (char? (peek)) (char=? (peek) #\]))
                (begin
                  (advance) ;; consume ]
                  (if (and (char? (peek)) (char=? (peek) #\%))
                      (begin
                        (advance) ;; consume final %
                        (list 'body
                              (list->string (reverse chars))
                              start-line))
                      ;; false alarm: %] without trailing %
                      (loop (cons #\] (cons #\% chars)) in-string)))
                ;; bare % in CSP (modulo operator)
                (loop (cons c chars) in-string)))
           (else
            (loop (cons c chars) in-string)))))))

  (define (next-token)
    (let ((c (peek)))
      (cond
       ((eof-object? c) (list 'eof "" line))
       ((char-whitespace? c) (advance) (next-token))
       ;; // line comment
       ((char=? c #\/)
        (advance)
        (if (and (char? (peek)) (char=? (peek) #\/))
            (begin (skip-line-comment) (next-token))
            (sys-error "unexpected '/' at line "
                       (number->string line))))
       ;; %[% inline CSP body
       ((char=? c #\%)
        (advance)
        (if (and (char? (peek)) (char=? (peek) #\[))
            (begin
              (advance) ;; consume [
              (if (and (char? (peek)) (char=? (peek) #\%))
                  (begin
                    (advance) ;; consume %
                    (read-csp-body))
                  (sys-error "expected %[% at line "
                             (number->string line))))
            (sys-error "unexpected '%' at line "
                       (number->string line))))
       ;; identifier or keyword
       ((char-alphabetic? c)
        (advance)
        (let ((word (read-ident c)))
          (if (member word *sys-keywords*)
              (list 'keyword word line)
              (list 'ident word line))))
       ;; integer
       ((char-numeric? c)
        (advance)
        (list 'int (read-integer c) line))
       ;; string literal
       ((char=? c #\")
        (advance)
        (list 'string (read-string-lit) line))
       ;; punctuation
       ((char=? c #\;) (advance) (list 'punct ";" line))
       ((char=? c #\:) (advance) (list 'punct ":" line))
       ((char=? c #\,) (advance) (list 'punct "," line))
       ((char=? c #\.) (advance) (list 'punct "." line))
       ;; ( -- may start a (* block comment *)
       ((char=? c #\()
        (advance)
        (if (and (char? (peek)) (char=? (peek) #\*))
            (begin (advance) (skip-block-comment) (next-token))
            (list 'punct "(" line)))
       ((char=? c #\))
        (advance) (list 'punct ")" line))
       ;; = or =>
       ((char=? c #\=)
        (advance)
        (if (and (char? (peek)) (char=? (peek) #\>))
            (begin (advance) (list 'punct "=>" line))
            (list 'punct "=" line)))
       (else
        (advance)
        (sys-error "unexpected character '"
                   (string c) "' at line " (number->string line))))))

  ;; Collect all tokens into a list
  (let loop ((tokens '()))
    (let ((tok (next-token)))
      (if (eq? (car tok) 'eof)
          (reverse (cons tok tokens))
          (loop (cons tok tokens))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  3. Parser
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Token stream: mutable cell holding a list of tokens.
;; Wrapping in a list allows mutation via set-car!
(define (make-token-stream tokens)
  (list tokens))

(define (ts-peek ts) (caar ts))
(define (ts-advance! ts)
  (let ((tok (caar ts)))
    (set-car! ts (cdar ts))
    tok))

(define (ts-peek-kind ts)  (car (ts-peek ts)))
(define (ts-peek-value ts) (cadr (ts-peek ts)))
(define (ts-peek-line ts)  (caddr (ts-peek ts)))

(define (ts-expect! ts kind value)
  (let ((tok (ts-advance! ts)))
    (if (and (eq? (car tok) kind) (equal? (cadr tok) value))
        tok
        (sys-error "expected " value " but got '"
                   (cadr tok) "' at line " (number->string (caddr tok))))))

(define (ts-expect-kind! ts kind)
  (let ((tok (ts-advance! ts)))
    (if (eq? (car tok) kind)
        tok
        (sys-error "expected " (symbol->string kind) " but got '"
                   (cadr tok) "' at line " (number->string (caddr tok))))))

(define (parse-sys-file filename)
  (let* ((p (open-input-file filename))
         (tokens (sys-tokenize p)))
    (close-input-port p)
    (let ((ts (make-token-stream tokens)))
      (parse-system ts))))

(define (parse-system ts)
  ;; system_file = "system" IDENT ";" { declaration } "begin" instance_list "end" "."
  (ts-expect! ts 'keyword "system")
  (let ((name (cadr (ts-expect-kind! ts 'ident))))
    (ts-expect! ts 'punct ";")
    (let loop ((channels '()) (processes '()))
      (cond
       ;; "begin" -> switch to instance list
       ((and (eq? (ts-peek-kind ts) 'keyword)
             (equal? (ts-peek-value ts) "begin"))
        (ts-advance! ts)
        (let ((instances (parse-instance-list ts)))
          (ts-expect! ts 'keyword "end")
          (ts-expect! ts 'punct ".")
          (list 'system name
                (reverse channels) (reverse processes) instances)))
       ;; "var" -> channel declaration
       ((and (eq? (ts-peek-kind ts) 'keyword)
             (equal? (ts-peek-value ts) "var"))
        (let ((ch (parse-channel-decl ts)))
          (loop (cons ch channels) processes)))
       ;; "process" -> process declaration
       ((and (eq? (ts-peek-kind ts) 'keyword)
             (equal? (ts-peek-value ts) "process"))
        (let ((pr (parse-process-decl ts)))
          (loop channels (cons pr processes))))
       (else
        (sys-error "unexpected '" (ts-peek-value ts)
                   "' at line " (number->string (ts-peek-line ts))))))))

(define (parse-channel-decl ts)
  ;; "var" IDENT ":" "channel" "(" INTEGER ")" [ "slack" INTEGER ] ";"
  (ts-expect! ts 'keyword "var")
  (let ((name (cadr (ts-expect-kind! ts 'ident))))
    (ts-expect! ts 'punct ":")
    (ts-expect! ts 'keyword "channel")
    (ts-expect! ts 'punct "(")
    (let ((width (cadr (ts-expect-kind! ts 'int))))
      (ts-expect! ts 'punct ")")
      (let ((slack
             (if (and (eq? (ts-peek-kind ts) 'keyword)
                      (equal? (ts-peek-value ts) "slack"))
                 (begin (ts-advance! ts)
                        (cadr (ts-expect-kind! ts 'int)))
                 1)))
        (ts-expect! ts 'punct ";")
        (list 'channel name width slack)))))

(define (parse-process-decl ts)
  ;; "process" IDENT "=" process_body { port_decl } ";"
  (ts-expect! ts 'keyword "process")
  (let ((name (cadr (ts-expect-kind! ts 'ident))))
    (ts-expect! ts 'punct "=")
    (let ((body (parse-process-body ts)))
      (let loop ((ports '()))
        (if (and (eq? (ts-peek-kind ts) 'keyword)
                 (equal? (ts-peek-value ts) "port"))
            (loop (cons (parse-port-decl ts) ports))
            (begin
              (ts-expect! ts 'punct ";")
              (list 'process name body (reverse ports))))))))

(define (parse-process-body ts)
  ;; STRING_LIT | %[% csp_text %]%
  (cond
   ((eq? (ts-peek-kind ts) 'string)
    (list 'external (cadr (ts-advance! ts))))
   ((eq? (ts-peek-kind ts) 'body)
    (list 'inline (cadr (ts-advance! ts))))
   (else
    (sys-error "expected string or %[% but got '"
               (ts-peek-value ts) "' at line "
               (number->string (ts-peek-line ts))))))

(define (parse-port-decl ts)
  ;; "port" direction IDENT ":" "channel" "(" INTEGER ")"
  (ts-expect! ts 'keyword "port")
  (let ((dir (cadr (ts-advance! ts))))  ;; "in" or "out"
    (let ((name (cadr (ts-expect-kind! ts 'ident))))
      (ts-expect! ts 'punct ":")
      (ts-expect! ts 'keyword "channel")
      (ts-expect! ts 'punct "(")
      (let ((width (cadr (ts-expect-kind! ts 'int))))
        (ts-expect! ts 'punct ")")
        (list 'port name dir width)))))

(define (parse-instance-list ts)
  ;; { "var" IDENT ":" IDENT [ "(" binding_list ")" ] ";" }
  (let loop ((instances '()))
    (if (and (eq? (ts-peek-kind ts) 'keyword)
             (equal? (ts-peek-value ts) "var"))
        (begin
          (ts-advance! ts)
          (let ((iname (cadr (ts-expect-kind! ts 'ident))))
            (ts-expect! ts 'punct ":")
            (let ((pname (cadr (ts-expect-kind! ts 'ident))))
              (let ((bindings
                     (if (and (eq? (ts-peek-kind ts) 'punct)
                              (equal? (ts-peek-value ts) "("))
                         (begin (ts-advance! ts)
                                (let ((b (parse-binding-list ts)))
                                  (ts-expect! ts 'punct ")")
                                  b))
                         '())))
                (ts-expect! ts 'punct ";")
                (loop (cons (list 'instance iname pname bindings)
                            instances))))))
        (reverse instances))))

(define (parse-binding-list ts)
  ;; binding { "," binding }
  (let ((first (parse-binding ts)))
    (let loop ((bindings (list first)))
      (if (and (eq? (ts-peek-kind ts) 'punct)
               (equal? (ts-peek-value ts) ","))
          (begin (ts-advance! ts)
                 (loop (cons (parse-binding ts) bindings)))
          (reverse bindings)))))

(define (parse-binding ts)
  ;; IDENT "=>" IDENT
  (let ((pname (cadr (ts-expect-kind! ts 'ident))))
    (ts-expect! ts 'punct "=>")
    (let ((cname (cadr (ts-expect-kind! ts 'ident))))
      (cons pname cname))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  4. Validator
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (find-port name ports)
  (cond ((null? ports) #f)
        ((equal? (cadr (car ports)) name) (car ports))
        (else (find-port name (cdr ports)))))

(define (validate-system! sys)
  (let ((channels  (sys-channels sys))
        (processes (sys-processes sys))
        (instances (sys-instances sys)))

    ;; Build lookup tables (alists)
    (let ((chan-tbl (map (lambda (ch) (cons (chan-name ch) ch)) channels))
          (proc-tbl (map (lambda (pr) (cons (proc-name pr) pr)) processes)))

      ;; Validate each instance
      (for-each
       (lambda (inst)
         (let* ((iname    (inst-name inst))
                (pname    (inst-proc-name inst))
                (bindings (inst-bindings inst))
                (proc-ent (assoc pname proc-tbl)))

           ;; Check process type exists
           (if (not proc-ent)
               (sys-error "instance '" iname
                          "' references unknown process '" pname "'"))

           (let ((pr (cdr proc-ent)))
             ;; Check each binding
             (for-each
              (lambda (binding)
                (let ((bport (car binding))
                      (bchan (cdr binding)))
                  ;; Channel must exist
                  (if (not (assoc bchan chan-tbl))
                      (sys-error "instance '" iname
                                 "' binds to unknown channel '" bchan "'"))
                  ;; Port must exist on process
                  (let ((pt (find-port bport (proc-ports pr))))
                    (if (not pt)
                        (sys-error "instance '" iname
                                   "' binds unknown port '" bport
                                   "' of process '" pname "'"))
                    ;; Widths must match
                    (let ((ch (cdr (assoc bchan chan-tbl))))
                      (if (not (= (chan-width ch) (port-width pt)))
                          (sys-error "width mismatch: channel '"
                                     bchan "' width "
                                     (number->string (chan-width ch))
                                     " vs port '" bport "' width "
                                     (number->string (port-width pt))))))))
              bindings)

             ;; All ports must be bound
             (for-each
              (lambda (pt)
                (if (not (assoc (port-name pt) bindings))
                    (sys-error "port '" (port-name pt)
                               "' of process '" pname
                               "' unbound in instance '" iname "'")))
              (proc-ports pr)))))
       instances))
    'ok))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  5. Cellinfo construction and SCM patching
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define *standard-ports*
  '((port-definition Vdd in (node #f 1))
    (port-definition GND in (node #f 1))
    (port-definition _RESET in (node #f 1))
    (port-definition START in (node #f 1))
    (port-definition DLY in (node #f 1))
    (port-definition CAPTURE in (node #f 1))
    (port-definition PASSTHRU in (node #f 1))
    (port-definition INJECT in (node #f 1))))

(define (make-channel-portdef name dir width)
  ;; Build a port-definition for a channel port.
  ;; Sub-port directions (C=out, q=out, a=in, D=out) are constant
  ;; regardless of the top-level port direction.  This matches the
  ;; format in the reference .scm files.
  ;;
  ;; The channel type is stored as:
  ;;   (channel standard.channel.bd (WIDTH) 1 MAXVAL f (sub-ports...))
  ;; where standard.channel.bd is a symbol and (WIDTH) is a list.
  ;; This is because cspfe writes "standard.channel.bd(32)" which
  ;; Scheme reads as the symbol standard.channel.bd followed by
  ;; the list (32).
  (let ((maxval (expt 2 width))
        (dir-sym (string->symbol dir)))
    (list 'port-definition (string->symbol name) dir-sym
          (list 'channel
                'standard.channel.bd
                (list width)
                1 maxval 'f
                (list (list 'port-definition 'C 'out
                            (list 'structure 'standard.channel.bdc
                                  (list (list 'port-definition 'q 'out
                                              (list 'node #f 1))
                                        (list 'port-definition 'a 'in
                                              (list 'node #f 1)))))
                      (list 'port-definition 'D 'out
                            (list 'node #t width)))))))

(define (build-cellinfo-ports proc-record)
  ;; Build the complete port-definition list for a cellinfo:
  ;; channel ports first, then standard ports.
  (append
   (map (lambda (pt)
          (make-channel-portdef (port-name pt) (port-dir pt) (port-width pt)))
        (proc-ports proc-record))
   *standard-ports*))

(define (patch-cellinfo! cell-data proc-record)
  ;; cell-data = ("name" (csp ...) (cellinfo "name" "name" () (port-defs...)))
  ;; Replace the port-defs list in the cellinfo with our constructed one.
  (let ((cellinfo (caddr cell-data))
        (new-ports (build-cellinfo-ports proc-record)))
    ;; cellinfo = (cellinfo "name" "name" () (port-defs...))
    ;; cddddr gets the tail containing (port-defs...)
    (set-car! (cddddr cellinfo) new-ports)
    cell-data))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  6. SCM file generation (cspfe invocation + patching)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (find-cspfe)
  ;; Locate the cspfe binary relative to M3UTILS
  (string-append (Env.Get "M3UTILS")
                 "/csp/cspparse/ARM64_DARWIN/cspfe"))

(define (shell-quote s)
  ;; Simple quoting: wrap in single quotes, escaping embedded single quotes
  (string-append "'" s "'"))

(define (run-cspfe! csp-file cell-name scm-file)
  (let* ((cmd (string-append (find-cspfe)
                             " --scm --name " (shell-quote cell-name)
                             " " (shell-quote csp-file)
                             " > " (shell-quote scm-file)))
         (ret (system cmd)))
    (if (not (= ret 0))
        (sys-error "cspfe failed (exit " (number->string ret)
                   ") for " csp-file))))

(define (generate-scm! proc-record sys-name tmp-dir)
  ;; Generate a .scm file for one process type.
  ;; The .scm is written to the current directory (where drive! expects it).
  ;; tmp-dir is used for intermediate .csp files from inline bodies.
  ;; Returns the escaped module name.
  (let* ((pname     (proc-name proc-record))
         (body      (proc-body proc-record))
         (cell-name (string-append sys-name "." pname))
         (escaped   (escape-name cell-name))
         (scm-file  (string-append escaped ".scm")))

    ;; Determine CSP source
    (let ((csp-file
           (cond
            ((eq? (car body) 'external) (cadr body))
            ((eq? (car body) 'inline)
             (let ((tmp-path (string-append tmp-dir escaped ".csp")))
               (let ((p (open-output-file tmp-path)))
                 (display (cadr body) p)
                 (newline p)
                 (close-output-port p))
               tmp-path))
            (else
             (sys-error "unknown body type: "
                        (symbol->string (car body)))))))

      ;; Run cspfe to produce the .scm file
      (run-cspfe! csp-file cell-name scm-file)

      ;; If process has channel ports, read back and patch cellinfo
      (if (not (null? (proc-ports proc-record)))
          (let* ((inp       (open-input-file scm-file))
                 (cell-data (read-big-int inp)))
            (close-input-port inp)
            (patch-cellinfo! cell-data proc-record)
            (let ((outp (open-output-file scm-file)))
              (write cell-data outp)
              (close-output-port outp))))

      escaped)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  7. .procs file generation
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (write-procs-file! sys)
  ;; Write a .procs file describing all instances and their port bindings.
  ;; Written to the current directory (where drive! expects it).
  ;; Format per line: x.INST sys.PROC escaped_name [PORT=x.CHAN.C.q ...]
  (let* ((name       (sys-name sys))
         (instances  (sys-instances sys))
         (procs-file (string-append (escape-name name) ".procs"))
         (p          (open-output-file procs-file)))

    (for-each
     (lambda (inst)
       (let* ((iname     (inst-name inst))
              (pname     (inst-proc-name inst))
              (bindings  (inst-bindings inst))
              (cell-name (string-append name "." pname))
              (escaped   (escape-name cell-name)))

         ;; instance hierarchy name
         (display (string-append "x." iname) p)
         (display " " p)
         ;; cell type
         (display cell-name p)
         (display " " p)
         ;; escaped filename (without .scm extension)
         (display escaped p)
         ;; port bindings: PORT=x.CHAN.C.q
         (for-each
          (lambda (binding)
            (display " " p)
            (display (car binding) p)
            (display "=" p)
            (display (string-append "x." (cdr binding) ".C.q") p))
          bindings)
         (newline p)))
     instances)

    (close-output-port p)
    procs-file))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  8. Build driver
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (build-system! sys-file . options)
  ;; Main entry point.  Parses a .sys file, validates, generates .scm
  ;; and .procs files, runs the compiler, and builds with cm3.
  ;;
  ;; Options (keyword-value pairs):
  ;;   'slack N       -- channel slack (default: *default-slack*)
  ;;   'run #t        -- run the simulator after building
  ;;   'verbose #t    -- print extra progress info
  (let ((opt-slack   (get-option options 'slack *default-slack*))
        (opt-run     (get-option options 'run #f))
        (opt-verbose (get-option options 'verbose #f)))

    ;; 1. Parse
    (dis "cspbuild: parsing " sys-file " ..." dnl)
    (let ((sys (parse-sys-file sys-file)))

      (if opt-verbose
          (dis "cspbuild: system '" (sys-name sys) "': "
               (number->string (length (sys-channels sys))) " channels, "
               (number->string (length (sys-processes sys))) " processes, "
               (number->string (length (sys-instances sys))) " instances"
               dnl))

      ;; 2. Validate
      (dis "cspbuild: validating ..." dnl)
      (validate-system! sys)

      ;; 3. Create output directories
      (let ((tmp-dir (string-append (sys-name sys) ".tmp/")))
        (system (string-append "mkdir -p " (shell-quote tmp-dir)))
        (system "mkdir -p build/src")

        ;; 4. Generate .scm files for each process type
        ;; .scm files go in current dir (where drive! expects them)
        (dis "cspbuild: generating .scm files ..." dnl)
        (for-each
         (lambda (pr)
           (dis "cspbuild:   " (proc-name pr) dnl)
           (generate-scm! pr (sys-name sys) tmp-dir))
         (sys-processes sys))

        ;; 5. Write .procs file (in current dir)
        (dis "cspbuild: writing .procs file ..." dnl)
        (let ((procs-file (write-procs-file! sys)))

          ;; 6. Compile via drive!
          (dis "cspbuild: compiling via drive! ..." dnl)
          (set! *default-slack* opt-slack)
          (drive! procs-file)

          ;; 7. Build with cm3
          (dis "cspbuild: building with cm3 ..." dnl)
          (let ((ret (system "cd build/src && cm3 -build -override")))
            (if (not (= ret 0))
                (sys-error "cm3 build failed (exit "
                           (number->string ret) ")")))

          ;; 8. Optionally run the simulator
          (if opt-run
              (begin
                (dis "cspbuild: running simulator ..." dnl)
                (system "./build/src/ARM64_DARWIN/sim")))

          (dis "cspbuild: done." dnl)
          'ok)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(dis "cspbuild loaded." dnl)
