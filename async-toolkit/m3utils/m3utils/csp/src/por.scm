; Copyright (c) 2026 Mika Nystrom

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  por.scm -- Partial-Order Reduction for explicit-state deadlock checking
;;
;;  Reduces the number of product states explored by exploiting
;;  independence of transitions on disjoint process instances.
;;
;;  Two transitions are independent iff they touch disjoint sets of
;;  process instances.  The .sys channel topology directly gives the
;;  independence relation:
;;    - tau on instance i:           instance-set = {i}
;;    - sync on channel c (si, ri):  instance-set = {si, ri}
;;
;;  The ample set selector picks a subset of enabled transitions
;;  sufficient for deadlock checking (preserving C0: non-emptiness).
;;  For deadlock detection, the cycle condition C3 is not needed.
;;
;;  Usage:
;;    (check-deadlock-por! "build_prodcons.sys")  -> #t or trace
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  1. Transition representation with instance-set metadata
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; A por-transition is: (action new-product-state instance-set)
;; where instance-set is a sorted list of instance indices.

(define (make-por-transition action new-state instance-set)
  (list action new-state instance-set))

(define (por-trans-action t)       (car t))
(define (por-trans-new-state t)    (cadr t))
(define (por-trans-instance-set t) (caddr t))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  2. Product successors with instance-set metadata
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (product-successors-por product-state indices channel-map)
  ;; Like product-successors but returns por-transitions with instance-sets.
  ;; Returns: list of (action new-product-state instance-set)
  (let ((successors '())
        (n (length product-state)))

    ;; 1. Tau interleaving
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
                             (cons (make-por-transition
                                    'tau
                                    (replace-nth product-state i (cdr move))
                                    (list i))
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
              (recv-moves (recv-tbl 'retrieve recv-state))
              (inst-set (if (< send-idx recv-idx)
                            (list send-idx recv-idx)
                            (list recv-idx send-idx))))
         (if (and (not (eq? send-moves '*hash-table-search-failed*))
                  (not (eq? recv-moves '*hash-table-search-failed*)))
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
                                   (cons (make-por-transition
                                          (list 'sync ch-name)
                                          new-ps
                                          inst-set)
                                         successors)))))
                     recv-moves)))
              send-moves))))
     channel-map)

    successors))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  3. Independence checking
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (instance-sets-disjoint? s1 s2)
  ;; s1, s2 are sorted lists of instance indices.
  ;; Returns #t iff they share no elements.
  (cond ((null? s1) #t)
        ((null? s2) #t)
        ((= (car s1) (car s2)) #f)
        ((< (car s1) (car s2))
         (instance-sets-disjoint? (cdr s1) s2))
        (else
         (instance-sets-disjoint? s1 (cdr s2)))))

(define (transitions-independent? t1 t2)
  ;; Two transitions are independent iff their instance-sets are disjoint.
  (instance-sets-disjoint? (por-trans-instance-set t1)
                           (por-trans-instance-set t2)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  4. Ample set selection
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (build-instance-transitions-map transitions n)
  ;; Build a vector: instance-idx -> list of transitions touching that instance.
  (let ((v (make-vector n '())))
    (for-each
     (lambda (t)
       (for-each
        (lambda (i)
          (vector-set! v i (cons t (vector-ref v i))))
        (por-trans-instance-set t)))
     transitions)
    v))

(define (select-ample-set transitions n)
  ;; Select an ample set (subset of enabled transitions) for POR.
  ;;
  ;; Strategy: For each instance, check if all transitions touching
  ;; that instance are independent of all transitions NOT touching it.
  ;; If so, the transitions of that instance form an ample set.
  ;; Pick the instance giving the smallest ample set.
  ;;
  ;; POR conditions for deadlock (Peled 1993, Godefroid 1996):
  ;;   C0: ample(s) = {} iff enabled(s) = {}
  ;;   C1: along every path in the full graph starting from s,
  ;;       a transition dependent on some t in ample(s) cannot be
  ;;       executed before some transition in ample(s) is executed.
  ;;       (Guaranteed by: if ample(s) contains all transitions of
  ;;       instance i, and all are independent of transitions from
  ;;       other instances, then no dependent transition can fire first.)
  ;;   C2 (proviso): if s is not fully expanded, then ample(s) contains
  ;;       no transition that leads to a state on the current search stack.
  ;;       (Not needed for BFS-based deadlock detection.)

  (if (or (null? transitions) (null? (cdr transitions)))
      ;; 0 or 1 transitions: no reduction possible
      transitions
      (let* ((inst-map (build-instance-transitions-map transitions n))
             (best-instance #f)
             (best-size (+ (length transitions) 1)))

        ;; Try each instance that has transitions
        (let loop ((i 0))
          (if (< i n)
              (let ((inst-trans (vector-ref inst-map i)))
                (if (and (not (null? inst-trans))
                         (< (length inst-trans) best-size))
                    ;; Check if all transitions of instance i are
                    ;; independent of all transitions NOT touching i
                    (let ((all-indep
                           (let check ((ts transitions))
                             (if (null? ts)
                                 #t
                                 (let ((t (car ts)))
                                   (if (memv i (por-trans-instance-set t))
                                       ;; This transition touches i, skip
                                       (check (cdr ts))
                                       ;; Check independence with all inst-trans
                                       (let inner ((its inst-trans))
                                         (if (null? its)
                                             (check (cdr ts))
                                             (if (transitions-independent? t (car its))
                                                 (inner (cdr its))
                                                 #f)))))))))
                      (if all-indep
                          (begin
                            (set! best-instance i)
                            (set! best-size (length inst-trans))))))
                (loop (+ i 1)))))

        ;; If we found a valid ample set, use it; otherwise use full set
        (if best-instance
            (vector-ref inst-map best-instance)
            transitions))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  5. Main POR deadlock checker
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (check-deadlock-por! sys-file)
  ;; Like check-deadlock! but with partial-order reduction.
  ;; Returns #t if deadlock-free, or a counterexample trace list.

  (dis "check-deadlock-por!: parsing " sys-file " ..." dnl)
  (let ((sys (parse-sys-file sys-file)))

    (dis "check-deadlock-por!: validating ..." dnl)
    (validate-system! sys)

    (let* ((type-lts-alist (extract-system-lts! sys-file))
           (instances  (sys-instances sys))
           (channels   (sys-channels sys))
           (processes  (sys-processes sys))
           (sname      (sys-name sys))
           (n          (length instances)))

      ;; Build renamed LTSs (same as check-deadlock!)
      (let ((instance-lts-list
             (map (lambda (inst)
                    (let* ((pname    (inst-proc-name inst))
                           (cell-name (string-append sname "." pname))
                           (entry    (assoc cell-name type-lts-alist))
                           (type-lts (if entry (cdr entry)
                                         (error "check-deadlock-por!: no LTS for "
                                                cell-name)))
                           (renaming
                            (map (lambda (b)
                                   (cons (string->symbol (car b))
                                         (string->symbol (cdr b))))
                                 (inst-bindings inst))))
                      (rename-lts type-lts renaming)))
                  instances)))

        ;; Build channel map
        (let ((channel-map
               (let cloop ((chs channels) (result '()))
                 (if (null? chs)
                     (reverse result)
                     (let* ((ch (car chs))
                            (ch-name-str (chan-name ch))
                            (sender-idx  #f)
                            (receiver-idx #f))

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

                       (if (and sender-idx receiver-idx)
                           (cloop (cdr chs)
                                  (cons (list (string->symbol ch-name-str)
                                              sender-idx receiver-idx)
                                        result))
                           (cloop (cdr chs) result)))))))

          ;; Build transition indices
          (let ((indices (map build-transition-index instance-lts-list)))

            ;; BFS exploration with POR
            (let* ((init-state (map lts-initial instance-lts-list))
                   (init-key   (make-product-state-key init-state))
                   (visited    (make-hash-table 1000 atom-hash))
                   (parent     (make-hash-table 1000 atom-hash))
                   (queue      (obj-method-wrap
                                ((obj-method-wrap
                                  (new-modula-object 'RefSeq.T) 'RefSeq.T)
                                 'init 1000)
                                'RefSeq.T))
                   (explored   0)
                   (full-trans 0)
                   (por-trans  0)
                   (deadlock   #f))

              (visited 'add-entry! init-key #t)
              (queue 'addhi init-state)

              ;; BFS loop with ample set selection
              (let bfs ()
                (if (and (> (queue 'size) 0) (not deadlock))
                    (let* ((current (queue 'remlo))
                           (all-succs (product-successors-por
                                       current indices channel-map))
                           (ample (select-ample-set all-succs n)))
                      (set! explored (+ explored 1))
                      (set! full-trans (+ full-trans (length all-succs)))
                      (set! por-trans  (+ por-trans  (length ample)))

                      (if (null? all-succs)
                          ;; Deadlock: no transitions at all
                          (set! deadlock current)
                          ;; Process ample set successors
                          (begin
                            (for-each
                             (lambda (succ)
                               (let* ((act (por-trans-action succ))
                                      (new-state (por-trans-new-state succ))
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
                                       (queue 'addhi new-state)))))
                             ample)
                            (bfs))))))

              (dis "check-deadlock-por!: explored "
                   (number->string explored) " product states" dnl)
              (dis "check-deadlock-por!: transitions full="
                   (number->string full-trans) " por="
                   (number->string por-trans)
                   (if (> full-trans 0)
                       (string-append
                        " (reduction "
                        (number->string
                         (quotient (* 100 (- full-trans por-trans))
                                   full-trans))
                        "%)")
                       "")
                   dnl)

              (if deadlock
                  (begin
                    (dis "check-deadlock-por!: DEADLOCK FOUND!" dnl)
                    (let ((trace (trace-path parent init-key
                                            (make-product-state-key
                                             deadlock))))
                      (print-counterexample trace instances)
                      trace))
                  (begin
                    (dis "check-deadlock-por!: system is deadlock-free." dnl)
                    #t)))))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(dis "por.scm loaded." dnl)
