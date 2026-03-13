; Copyright (c) 2026 Mika Nystrom

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  product.scm -- Product LTS composition and deadlock checking
;;
;;  Composes per-process LTSs (from lts.scm) into a product LTS
;;  following the .sys system topology, and checks for deadlock via
;;  BFS exploration.
;;
;;  CSP parallel composition rule (slack-1 channels):
;;    - Channel sync: if sender can (send c) and receiver can (recv c),
;;      both advance simultaneously.  Product action is (sync c).
;;    - Tau interleave: any instance with a tau transition advances
;;      alone; other components stay put.
;;    - Deadlock: a product state with no successors.
;;
;;  Usage:
;;    (check-deadlock! "build_prodcons.sys")  -> #t or trace
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  1. Port-to-channel renaming
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (rename-action act renaming)
  ;; Rename port symbols in an action using renaming alist.
  ;; renaming = ((port-sym . chan-sym) ...)
  (cond ((eq? act 'tau) 'tau)
        ((and (pair? act) (memq (car act) '(send recv)))
         (let ((mapping (assq (cadr act) renaming)))
           (if mapping
               (list (car act) (cdr mapping))
               act)))
        (else act)))

(define (rename-lts lts renaming)
  ;; Returns a new LTS with port names replaced by channel names.
  ;; renaming = ((port-sym . chan-sym) ...)
  (let ((new-trans
         (map (lambda (t)
                (list (car t)
                      (rename-action (cadr t) renaming)
                      (caddr t)))
              (lts-transitions lts)))
        (new-alpha
         (map (lambda (a) (rename-action a renaming))
              (lts-alphabet lts))))
    (make-lts (lts-states lts)
              (lts-initial lts)
              new-alpha
              new-trans)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  2. Transition index (fast state -> transitions lookup)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (build-transition-index lts)
  ;; Returns a hash table: state-symbol -> ((action . target) ...)
  (let ((tbl (make-hash-table 100 atom-hash)))
    (for-each
     (lambda (t)
       (let* ((src (car t))
              (act (cadr t))
              (dst (caddr t))
              (existing (tbl 'retrieve src)))
         (if (eq? existing '*hash-table-search-failed*)
             (tbl 'add-entry! src (list (cons act dst)))
             (tbl 'add-entry! src (cons (cons act dst) existing)))))
     (lts-transitions lts))
    tbl))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  3. Product state helpers
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (make-product-state-key states)
  ;; Convert list of state symbols to a single key symbol.
  ;; E.g., (L6 L16) -> symbol "L6:L16"
  (string->symbol
   (let loop ((ss states) (acc ""))
     (if (null? ss)
         acc
         (loop (cdr ss)
               (if (string=? acc "")
                   (symbol->string (car ss))
                   (string-append acc ":" (symbol->string (car ss)))))))))

(define (replace-nth lst n val)
  ;; Replace the nth element (0-indexed) in lst with val.
  (if (= n 0)
      (cons val (cdr lst))
      (cons (car lst) (replace-nth (cdr lst) (- n 1) val))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  4. Product successor computation
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (product-successors product-state indices channel-map)
  ;; product-state: list of state symbols, one per instance
  ;; indices: list of transition-index hash tables, one per instance
  ;; channel-map: list of (channel-sym sender-idx receiver-idx)
  ;; Returns: list of (action . new-product-state) pairs
  (let ((successors '())
        (n (length product-state)))

    ;; 1. Tau interleaving: for each instance with a tau transition
    (let loop ((i 0) (ss product-state) (idxs indices))
      (if (< i n)
          (let* ((state (car ss))
                 (idx (car idxs))
                 (moves (idx 'retrieve state)))
            (if (not (eq? moves '*hash-table-search-failed*))
                (for-each
                 (lambda (move)
                   (if (eq? (car move) 'tau)
                       (set! successors
                             (cons (cons 'tau
                                         (replace-nth product-state i
                                                      (cdr move)))
                                   successors))))
                 moves))
            (loop (+ i 1) (cdr ss) (cdr idxs)))))

    ;; 2. Channel synchronization
    (for-each
     (lambda (ch-entry)
       (let* ((ch-name  (car ch-entry))
              (send-idx (cadr ch-entry))
              (recv-idx (caddr ch-entry))
              (send-state (list-ref product-state send-idx))
              (recv-state (list-ref product-state recv-idx))
              (send-tbl (list-ref indices send-idx))
              (recv-tbl (list-ref indices recv-idx))
              (send-moves (send-tbl 'retrieve send-state))
              (recv-moves (recv-tbl 'retrieve recv-state)))
         (if (and (not (eq? send-moves '*hash-table-search-failed*))
                  (not (eq? recv-moves '*hash-table-search-failed*)))
             ;; Look for matching send/recv on this channel
             (for-each
              (lambda (sm)
                (if (equal? (car sm) (list 'send ch-name))
                    (for-each
                     (lambda (rm)
                       (if (equal? (car rm) (list 'recv ch-name))
                           (let ((new-ps (replace-nth
                                          (replace-nth product-state
                                                       send-idx (cdr sm))
                                          recv-idx (cdr rm))))
                             (set! successors
                                   (cons (cons (list 'sync ch-name) new-ps)
                                         successors)))))
                     recv-moves)))
              send-moves))))
     channel-map)

    successors))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  5. Counterexample tracing
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (trace-path parent-map init-key deadlock-key)
  ;; Trace back from deadlock to initial state via parent map.
  ;; Returns list of (product-state-key . action) pairs, initial first.
  (let loop ((key deadlock-key) (trace (list (cons deadlock-key 'deadlock))))
    (if (eq? key init-key)
        trace
        (let ((entry (parent-map 'retrieve key)))
          (if (eq? entry '*hash-table-search-failed*)
              trace  ;; shouldn't happen
              (let ((parent-key (car entry))
                    (action     (cdr entry)))
                (loop parent-key
                      (cons (cons parent-key action) trace))))))))

(define (format-product-action act)
  ;; Format a product-level action for display.
  (cond ((eq? act 'tau) "tau")
        ((eq? act 'deadlock) "DEADLOCK")
        ((and (pair? act) (eq? 'sync (car act)))
         (string-append (symbol->string (cadr act)) "!?"))
        (else (format-action act))))

(define (print-counterexample trace instances)
  ;; Print each step: product state + action taken.
  (dis dnl "=== Counterexample Trace ===" dnl)
  (dis "Instance order: ")
  (let iloop ((insts instances) (first #t))
    (if (not (null? insts))
        (begin
          (if (not first) (dis ", "))
          (dis (inst-name (car insts)))
          (iloop (cdr insts) #f))))
  (dis dnl dnl)
  (let ((step 0))
    (for-each
     (lambda (entry)
       (let ((state-key (car entry))
             (action    (cdr entry)))
         (dis "  " (number->string step) ". "
              (symbol->string state-key)
              " --" (format-product-action action) "-->" dnl)
         (set! step (+ step 1))))
     trace))
  (dis "===========================" dnl dnl))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  6. Helpers for system navigation
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (find-proc-by-name processes name)
  ;; Find a process record by name (string) in the process list.
  (cond ((null? processes) #f)
        ((string=? (proc-name (car processes)) name)
         (car processes))
        (else (find-proc-by-name (cdr processes) name))))

(define (find-port-by-name ports name)
  ;; Find a port record by name (string) in the port list.
  (cond ((null? ports) #f)
        ((string=? (port-name (car ports)) name)
         (car ports))
        (else (find-port-by-name (cdr ports) name))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  7. Main deadlock checker
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (check-deadlock! sys-file)
  ;; Parse a .sys file, compose per-process LTSs into a product LTS,
  ;; and check for deadlock via BFS.
  ;; Returns #t if deadlock-free, or a counterexample trace list.

  (dis "check-deadlock!: parsing " sys-file " ..." dnl)
  (let ((sys (parse-sys-file sys-file)))

    (dis "check-deadlock!: validating ..." dnl)
    (validate-system! sys)

    ;; Extract per-type LTSs
    (let* ((type-lts-alist (extract-system-lts! sys-file))
           (instances  (sys-instances sys))
           (channels   (sys-channels sys))
           (processes  (sys-processes sys))
           (sname      (sys-name sys))
           (n          (length instances)))

      ;; For each instance: look up LTS by type, build renaming, apply
      (let ((instance-lts-list
             (map (lambda (inst)
                    (let* ((pname    (inst-proc-name inst))
                           (cell-name (string-append sname "." pname))
                           (entry    (assoc cell-name type-lts-alist))
                           (type-lts (if entry (cdr entry)
                                         (error "check-deadlock!: no LTS for "
                                                cell-name)))
                           ;; Build renaming: port-symbol -> channel-symbol
                           (renaming
                            (map (lambda (b)
                                   (cons (string->symbol (car b))
                                         (string->symbol (cdr b))))
                                 (inst-bindings inst))))
                      (rename-lts type-lts renaming)))
                  instances)))

        ;; Build channel map: for each channel, find sender and receiver
        ;; instance indices by checking port directions
        (let ((channel-map
               (let cloop ((chs channels) (result '()))
                 (if (null? chs)
                     (reverse result)
                     (let* ((ch (car chs))
                            (ch-name-str (chan-name ch))
                            (sender-idx  #f)
                            (receiver-idx #f))

                       ;; Search instances for sender/receiver
                       (let iloop ((i 0) (insts instances))
                         (if (not (null? insts))
                             (let* ((inst (car insts))
                                    (pname (inst-proc-name inst))
                                    (proc  (find-proc-by-name processes pname))
                                    (bindings (inst-bindings inst)))
                               (for-each
                                (lambda (b)
                                  (if (string=? (cdr b) ch-name-str)
                                      (let ((port (find-port-by-name
                                                   (proc-ports proc)
                                                   (car b))))
                                        (if (string=? (port-dir port) "out")
                                            (set! sender-idx i))
                                        (if (string=? (port-dir port) "in")
                                            (set! receiver-idx i)))))
                                bindings)
                               (iloop (+ i 1) (cdr insts)))))

                       ;; Only add to channel-map if both endpoints found
                       (if (and sender-idx receiver-idx)
                           (cloop (cdr chs)
                                  (cons (list (string->symbol ch-name-str)
                                              sender-idx receiver-idx)
                                        result))
                           (cloop (cdr chs) result)))))))

          ;; Build transition indices for each instance LTS
          (let ((indices (map build-transition-index instance-lts-list)))

            ;; BFS exploration from initial product state
            (let* ((init-state (map lts-initial instance-lts-list))
                   (init-key   (make-product-state-key init-state))
                   (visited    (make-hash-table 1000 atom-hash))
                   (parent     (make-hash-table 1000 atom-hash))
                   (queue      (list init-state))
                   (explored   0)
                   (deadlock   #f))

              (visited 'add-entry! init-key #t)

              ;; BFS loop
              (let bfs ()
                (if (and (not (null? queue)) (not deadlock))
                    (let* ((current (car queue))
                           (succs (product-successors current
                                                      indices
                                                      channel-map)))
                      (set! queue (cdr queue))
                      (set! explored (+ explored 1))

                      (if (null? succs)
                          ;; Deadlock found
                          (set! deadlock current)
                          ;; Process successors
                          (begin
                            (for-each
                             (lambda (succ)
                               (let* ((act (car succ))
                                      (new-state (cdr succ))
                                      (new-key (make-product-state-key
                                                new-state)))
                                 (if (eq? (visited 'retrieve new-key)
                                          '*hash-table-search-failed*)
                                     (begin
                                       (visited 'add-entry! new-key #t)
                                       (parent 'add-entry! new-key
                                               (cons (make-product-state-key
                                                      current)
                                                     act))
                                       (set! queue
                                             (append queue
                                                     (list new-state)))))))
                             succs)
                            (bfs))))))

              (dis "check-deadlock!: explored "
                   (number->string explored) " product states" dnl)

              (if deadlock
                  (begin
                    (dis "check-deadlock!: DEADLOCK FOUND!" dnl)
                    (let ((trace (trace-path parent init-key
                                            (make-product-state-key
                                             deadlock))))
                      (print-counterexample trace instances)
                      trace))
                  (begin
                    (dis "check-deadlock!: system is deadlock-free." dnl)
                    #t)))))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(dis "product.scm loaded." dnl)
