; Copyright (c) 2026 Mika Nystrom

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  saturation.scm -- MDD-based symbolic deadlock checking using
;;  the saturation algorithm (Ciardo et al. 2001).
;;
;;  Multi-valued Decision Diagrams with one level per process
;;  instance; each level has domain = number of local states.
;;  Saturation fires events level-by-level bottom-up, achieving
;;  fixed points locally before composing upward.  This gives
;;  100-1000x memory improvement over BDDs for asynchronous systems.
;;
;;  Usage:
;;    (check-deadlock-saturation! "build_dining_det.sys")  -> #t or #f
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  1. Level ordering
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; For dining philosophers (and similar ring topologies), interleave
;; communicating processes on adjacent levels to minimise sync event
;; span.  For general topologies, use the instance order from the
;; .sys file.

(define (build-comm-graph instances channels)
  ;; Build adjacency list: instance i <-> instance j if they share a channel.
  ;; channels here is the channel-map: ((ch-sym sender-idx receiver-idx) ...)
  ;; Returns a vector of n lists, where v[i] = sorted list of neighbors of i.
  (let* ((n (length instances))
         (adj (make-vector n '())))
    (for-each
     (lambda (ch)
       (let ((si (cadr ch))
             (ri (caddr ch)))
         (if (not (memv ri (vector-ref adj si)))
             (vector-set! adj si (cons ri (vector-ref adj si))))
         (if (not (memv si (vector-ref adj ri)))
             (vector-set! adj ri (cons si (vector-ref adj ri))))))
     channels)
    adj))

(define (detect-ring-topology adj n)
  ;; Check if the graph is a single ring: every node has degree 2
  ;; and the graph is connected.  Returns the ring order if so, #f otherwise.
  (if (< n 3)
      #f  ;; need at least 3 nodes for a ring
      (let ((all-deg-2
             (let loop ((i 0))
               (if (= i n) #t
                   (if (= (length (vector-ref adj i)) 2)
                       (loop (+ i 1))
                       #f)))))
        (if (not all-deg-2)
            #f
            ;; Walk the ring from node 0
            (let walk ((current 0) (prev -1) (order '()) (count 0))
              (if (= count n)
                  (if (= current 0)
                      (reverse order)  ;; closed ring
                      #f)              ;; not a ring
                  (let ((next (let ((nbrs (vector-ref adj current)))
                                (if (= (car nbrs) prev)
                                    (cadr nbrs)
                                    (car nbrs)))))
                    (walk next current (cons current order) (+ count 1)))))))))

(define (greedy-span-ordering adj n)
  ;; FORCE-like greedy ordering: start with the instance with the most
  ;; connections, greedily place connected instances adjacent.
  ;; Returns a permutation list: element k = instance index at MDD level k.
  (let ((placed (make-vector n #f))
        (order '()))

    ;; Find the instance with the most connections (center of mass)
    (let ((start 0)
          (max-deg 0))
      (let loop ((i 0))
        (if (< i n)
            (let ((deg (length (vector-ref adj i))))
              (if (> deg max-deg)
                  (begin (set! start i) (set! max-deg deg)))
              (loop (+ i 1)))))

      ;; BFS from start, placing neighbors greedily
      (vector-set! placed start #t)
      (set! order (list start))

      (let bfs ((queue (list start)))
        (if (not (null? queue))
            (let* ((current (car queue))
                   (rest (cdr queue))
                   (new-neighbors '()))
              ;; Add unplaced neighbors
              (for-each
               (lambda (nbr)
                 (if (not (vector-ref placed nbr))
                     (begin
                       (vector-set! placed nbr #t)
                       (set! order (cons nbr order))
                       (set! new-neighbors (cons nbr new-neighbors)))))
               (vector-ref adj current))
              (bfs (append rest (reverse new-neighbors))))))

    ;; Any isolated instances not yet placed
    (let loop ((i 0))
      (if (< i n)
          (begin
            (if (not (vector-ref placed i))
                (set! order (cons i order)))
            (loop (+ i 1)))))

    (reverse order))))

(define (compute-level-ordering instances channels)
  ;; Legacy entry point: identity ordering.
  ;; Use compute-level-ordering-from-channel-map for optimized ordering.
  (let ((n (length instances)))
    (let loop ((i 0) (acc '()))
      (if (= i n) (reverse acc) (loop (+ i 1) (cons i acc))))))

(define (compute-level-ordering-from-channel-map channel-map n)
  ;; Compute optimized level ordering from the channel map.
  ;; channel-map: list of (channel-sym sender-idx receiver-idx)
  ;; n: number of instances
  ;; Returns: permutation list where element k = MDD level for instance k.
  ;; Uses greedy BFS from the most-connected instance to minimize sync span.
  (if (null? channel-map)
      ;; No channels: identity
      (let loop ((i 0) (acc '()))
        (if (= i n) (reverse acc) (loop (+ i 1) (cons i acc))))

      (let* ((adj (make-vector n '())))
        ;; Build adjacency
        (for-each
         (lambda (ch)
           (let ((si (cadr ch))
                 (ri (caddr ch)))
             (if (not (memv ri (vector-ref adj si)))
                 (vector-set! adj si (cons ri (vector-ref adj si))))
             (if (not (memv si (vector-ref adj ri)))
                 (vector-set! adj ri (cons si (vector-ref adj ri))))))
         channel-map)

        ;; Use greedy BFS ordering to minimize sync event span
        (let ((order (greedy-span-ordering adj n)))
          (dis "  level ordering: greedy BFS" dnl)
          (let ((perm (make-vector n 0)))
            (let loop ((k 0) (o order))
              (if (null? o)
                  (vector->list perm)
                  (begin
                    (vector-set! perm (car o) k)
                    (loop (+ k 1) (cdr o))))))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  2. Event construction from LTS transitions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (build-mdd-events instance-lts-list channel-map level-perm)
  ;; Build MDDEvent objects from LTS transitions.
  ;; level-perm maps instance-index -> MDD level.
  ;; Returns a list of MDDEvent.T objects.

  (let ((n (length instance-lts-list))
        (events '()))

    ;; Tau events: for each instance, collect all tau transitions
    (let iloop ((i 0) (ltss instance-lts-list))
      (if (< i n)
          (let* ((lts (car ltss))
                 (states (lts-states lts))
                 (state-map (let sloop ((ss states) (j 0) (acc '()))
                              (if (null? ss) (reverse acc)
                                  (sloop (cdr ss) (+ j 1)
                                         (cons (cons (car ss) j) acc)))))
                 (level (list-ref level-perm i))
                 (entries '()))
            (for-each
             (lambda (tr)
               (let ((src (car tr))
                     (act (cadr tr))
                     (dst (caddr tr)))
                 (if (eq? act 'tau)
                     (let ((from-idx (cdr (assq src state-map)))
                           (to-idx   (cdr (assq dst state-map))))
                       (set! entries (cons (cons from-idx to-idx) entries))))))
             (lts-transitions lts))
            (if (not (null? entries))
                (let ((matrix (make-mdd-matrix entries)))
                  (set! events (cons (MDDEvent.NewTauEvent level matrix)
                                     events))))
            (iloop (+ i 1) (cdr ltss)))))

    ;; Sync events: for each channel, find send/recv pairs
    (for-each
     (lambda (ch-entry)
       (let* ((ch-name  (car ch-entry))
              (si       (cadr ch-entry))
              (ri       (caddr ch-entry))
              (lts-s    (list-ref instance-lts-list si))
              (lts-r    (list-ref instance-lts-list ri))
              (states-s (lts-states lts-s))
              (states-r (lts-states lts-r))
              (smap-s   (let sloop ((ss states-s) (j 0) (acc '()))
                          (if (null? ss) (reverse acc)
                              (sloop (cdr ss) (+ j 1)
                                     (cons (cons (car ss) j) acc)))))
              (smap-r   (let sloop ((ss states-r) (j 0) (acc '()))
                          (if (null? ss) (reverse acc)
                              (sloop (cdr ss) (+ j 1)
                                     (cons (cons (car ss) j) acc)))))
              (level-s  (list-ref level-perm si))
              (level-r  (list-ref level-perm ri))
              (top-level (max level-s level-r))
              (bot-level (min level-s level-r))
              ;; Determine which is top and which is bottom
              (top-is-sender (= level-s top-level))
              (top-entries '())
              (bot-entries '()))
         ;; Find all send/recv pairs on this channel
         (for-each
          (lambda (st)
            (if (equal? (cadr st) (list 'send ch-name))
                (for-each
                 (lambda (rt)
                   (if (equal? (cadr rt) (list 'recv ch-name))
                       (let* ((s-from (cdr (assq (car st) smap-s)))
                              (s-to   (cdr (assq (caddr st) smap-s)))
                              (r-from (cdr (assq (car rt) smap-r)))
                              (r-to   (cdr (assq (caddr rt) smap-r))))
                         (if top-is-sender
                             (begin
                               (set! top-entries
                                     (cons (cons s-from s-to) top-entries))
                               (set! bot-entries
                                     (cons (cons r-from r-to) bot-entries)))
                             (begin
                               (set! top-entries
                                     (cons (cons r-from r-to) top-entries))
                               (set! bot-entries
                                     (cons (cons s-from s-to) bot-entries)))))))
                 (lts-transitions lts-r))))
          (lts-transitions lts-s))
         (if (and (not (null? top-entries)) (not (null? bot-entries)))
             (let ((top-matrix (make-mdd-matrix top-entries))
                   (bot-matrix (make-mdd-matrix bot-entries)))
               (set! events (cons (MDDEvent.NewSyncEvent
                                   top-level bot-level
                                   top-matrix bot-matrix)
                                  events))))))
     channel-map)

    (reverse events)))

(define (make-mdd-matrix entries)
  ;; Convert a list of (from . to) pairs to an MDDEvent.Matrix.
  ;; The Scheme stubs expect a list of Entry records represented
  ;; as alists with 'from and 'to symbol keys.
  (map (lambda (e) (list (cons 'from (car e)) (cons 'to (cdr e))))
       entries))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  3. Helpers
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (make-list n val)
  ;; R7RS make-list: create a list of n copies of val.
  (let loop ((i 0) (acc '()))
    (if (= i n) acc (loop (+ i 1) (cons val acc)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  4. Main entry point
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (check-deadlock-saturation! sys-file)
  ;; MDD/saturation-based symbolic deadlock checking.
  ;; Returns #t if deadlock-free, #f if deadlock exists.

  (dis "check-deadlock-saturation!: parsing " sys-file " ..." dnl)
  (let ((sys (parse-sys-file sys-file)))

    (dis "check-deadlock-saturation!: validating ..." dnl)
    (validate-system! sys)

    (let* ((type-lts-alist (extract-system-lts! sys-file))
           (instances  (sys-instances sys))
           (channels   (sys-channels sys))
           (processes  (sys-processes sys))
           (sname      (sys-name sys))
           (n          (length instances)))

      ;; Build renamed LTSs
      (let ((instance-lts-list
             (map (lambda (inst)
                    (let* ((pname     (inst-proc-name inst))
                           (cell-name (string-append sname "." pname))
                           (entry     (assoc cell-name type-lts-alist))
                           (type-lts  (if entry (cdr entry)
                                         (error "check-deadlock-saturation!: no LTS for "
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

          ;; Compute level ordering (using channel-map for optimized ordering)
          (let ((level-perm (compute-level-ordering-from-channel-map
                             channel-map n)))

            (dis "check-deadlock-saturation!: "
                 (number->string n) " instances, "
                 (number->string (length channel-map)) " channels" dnl)

            ;; Report per-instance info
            (let iloop ((i 0) (ltss instance-lts-list))
              (if (not (null? ltss))
                  (begin
                    (dis "  instance " (number->string i)
                         " -> MDD level " (number->string (list-ref level-perm i))
                         ": " (number->string (length (lts-states (car ltss))))
                         " states" dnl)
                    (iloop (+ i 1) (cdr ltss)))))

            ;; Set up MDD forest
            ;; Reorder domains by MDD level
            (let* ((ordered-lts
                    (let ((v (make-vector n)))
                      (let loop ((i 0) (ltss instance-lts-list))
                        (if (null? ltss)
                            (vector->list v)
                            (begin
                              (vector-set! v (list-ref level-perm i) (car ltss))
                              (loop (+ i 1) (cdr ltss)))))))
                   (dom-list (map (lambda (lts) (length (lts-states lts)))
                                  ordered-lts)))
              ;; SetLevels expects (n, list-of-cardinals)
              (MDD.SetLevels n dom-list)

              (dis "check-deadlock-saturation!: MDD forest with "
                   (number->string n) " levels" dnl)

              ;; Build events
              (dis "check-deadlock-saturation!: building events ..." dnl)
              (let ((events (build-mdd-events instance-lts-list
                                              channel-map level-perm)))

                (dis "check-deadlock-saturation!: "
                     (number->string (length events)) " events" dnl)

                ;; Build initial state as MDD singleton
                ;; Each instance starts at state 0 (initial state)
                ;; level-perm is identity, so init is all 0s
                (let ((init-values (make-list n 0)))
                  (let ((init-mdd (MDD.Singleton init-values)))

                    ;; Run saturation
                    (dis "check-deadlock-saturation!: running saturation ..." dnl)
                    (let* ((t-sat-0 (Time.Now))
                           (reached (MDDSaturation.ComputeReachable
                                     init-mdd events))
                           (t-sat-1 (Time.Now)))

                      (dis "check-deadlock-saturation!: reachable set: "
                           (number->string (MDD.Size reached))
                           " MDD nodes (saturation: "
                           (number->string (- t-sat-1 t-sat-0)) "s)" dnl)

                      ;; Compute deadlocked states directly (incremental subtraction)
                      (let* ((t-dl-0 (Time.Now))
                             (deadlocked (MDDSaturation.ComputeDeadlocked
                                          reached events))
                             (t-dl-1 (Time.Now)))
                        (dis "check-deadlock-saturation!: deadlock detection: "
                             (number->string (- t-dl-1 t-dl-0)) "s" dnl)

                        (if (not (MDD.IsEmpty deadlocked))
                            (begin
                              (dis "check-deadlock-saturation!: DEADLOCK FOUND"
                                   " (deadlock MDD size: "
                                   (number->string (MDD.Size deadlocked))
                                   ")" dnl)
                              #f)
                            (begin
                              (dis "check-deadlock-saturation!: system is deadlock-free."
                                   dnl)
                              #t))))))))))))))
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(dis "saturation.scm loaded." dnl)
