; Copyright (c) 2026 Mika Nystrom

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  symbolic.scm -- BDD-based symbolic deadlock checking
;;
;;  Encodes the product LTS state space as BDDs and uses fixed-point
;;  reachability to detect deadlocked states.  Handles exponentially
;;  many states in compact BDD form, complementing the explicit-state
;;  checker in product.scm.
;;
;;  Uses partitioned transition relations to avoid forming a monolithic
;;  transition BDD.  Each partition covers one instance (tau) or two
;;  instances (channel sync), without explicit frame conditions —
;;  non-participating instances' state is preserved implicitly by
;;  only quantifying/renaming the participating variables.
;;
;;  Usage:
;;    (check-deadlock-symbolic! "build_prodcons.sys")  -> #t or #f
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  1. BDD helpers
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (bdd-exists bdd var)
  ;; Existential quantification: exists var. bdd
  ;; = Or(bdd[var=T], bdd[var=F])
  (BDD.Or (BDD.MakeTrue bdd var) (BDD.MakeFalse bdd var)))

(define (bdd-exists-list bdd vars)
  ;; Existentially quantify out a list of variables.
  (if (null? vars)
      bdd
      (bdd-exists-list (bdd-exists bdd (car vars)) (cdr vars))))

(define (bdd-compose bdd old new)
  ;; Substitute variable 'old' with variable 'new' in bdd.
  ;; bdd[old/new] = ITE(new, bdd|old=T, bdd|old=F)
  (BDD.Or (BDD.And new (BDD.MakeTrue bdd old))
           (BDD.And (BDD.Not new) (BDD.MakeFalse bdd old))))

(define (bdd-rename bdd old-vars new-vars)
  ;; Sequentially rename each old-var to new-var.
  (if (null? old-vars)
      bdd
      (bdd-rename (bdd-compose bdd (car old-vars) (car new-vars))
                  (cdr old-vars)
                  (cdr new-vars))))

(define (bits-needed n)
  ;; Number of bits to encode n states (ceil(log2(n)), min 1).
  (if (<= n 1)
      1
      (let loop ((b 1) (k 2))
        (if (>= k n) b (loop (+ b 1) (* k 2))))))

(define (encode-pattern vars int-val)
  ;; BDD encoding: conjunction of variable polarities matching int-val's
  ;; bit pattern.  vars is a list of BDD variables, LSB first.
  (let loop ((vs vars) (v int-val) (acc (BDD.True)))
    (if (null? vs)
        acc
        (let ((bit (modulo v 2)))
          (loop (cdr vs)
                (quotient v 2)
                (BDD.And acc
                         (if (= bit 1) (car vs) (BDD.Not (car vs)))))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  2. Per-instance encoding
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (make-inst-encoding inst-idx states)
  ;; Build BDD encoding for one process instance.
  ;; Returns: (num-bits state-map curr-vars next-vars)
  ;;   state-map: alist ((state-sym . integer) ...)
  ;;   curr-vars, next-vars: lists of BDD variables
  (let* ((n (length states))
         (nbits (bits-needed n))
         (prefix (string-append "i" (number->string inst-idx)))
         ;; Create BDD variable pairs in interleaved order
         (vars (let loop ((b 0) (cvars '()) (nvars '()))
                 (if (= b nbits)
                     (cons (reverse cvars) (reverse nvars))
                     (let ((cv (BDD.New (string-append prefix "_c"
                                                       (number->string b))))
                           (nv (BDD.New (string-append prefix "_n"
                                                       (number->string b)))))
                       (loop (+ b 1) (cons cv cvars) (cons nv nvars))))))
         (curr-vars (car vars))
         (next-vars (cdr vars))
         ;; Map state symbols to integers 0..n-1
         (state-map (let loop ((ss states) (i 0) (acc '()))
                      (if (null? ss)
                          (reverse acc)
                          (loop (cdr ss) (+ i 1)
                                (cons (cons (car ss) i) acc))))))
    (list nbits state-map curr-vars next-vars)))

(define (encoding-nbits enc)    (car enc))
(define (encoding-state-map enc)(cadr enc))
(define (encoding-curr-vars enc)(caddr enc))
(define (encoding-next-vars enc)(cadddr enc))

(define (encode-curr enc state-sym)
  ;; BDD for "instance is in state state-sym" (current-state vars).
  (let ((idx (cdr (assq state-sym (encoding-state-map enc)))))
    (encode-pattern (encoding-curr-vars enc) idx)))

(define (encode-next enc state-sym)
  ;; BDD for "instance is in state state-sym" (next-state vars).
  (let ((idx (cdr (assq state-sym (encoding-state-map enc)))))
    (encode-pattern (encoding-next-vars enc) idx)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  3. Partition records
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Each partition: (type inst-indices bdd involved-curr-vars involved-next-vars)
;; type: 'tau or 'sync
;; inst-indices: list of instance indices (1 for tau, 2 for sync)
;; bdd: the partition's transition BDD (no frame conditions for uninvolved)
;; involved-curr-vars: curr-state BDD vars of participating instances
;; involved-next-vars: next-state BDD vars of participating instances

(define (make-partition type inst-indices bdd curr-vars next-vars)
  (list type inst-indices bdd curr-vars next-vars))

(define (partition-type p)       (car p))
(define (partition-instances p)  (cadr p))
(define (partition-bdd p)        (caddr p))
(define (partition-curr-vars p)  (cadddr p))
(define (partition-next-vars p)  (car (cddddr p)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  4. Partitioned transition relation
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (build-transition-partitions encodings renamed-lts-list channel-map)
  ;; Build partitioned transition relation: a list of partition records.
  ;; Each partition covers one instance (tau) or two instances (sync),
  ;; with no frame conditions for non-participating instances.
  (let ((n (length encodings))
        (partitions '()))

    ;; Tau transitions: one partition per instance, accumulating all
    ;; tau edges for that instance into a single BDD.
    (let iloop ((i 0) (ltss renamed-lts-list) (encs encodings))
      (if (< i n)
          (let ((enc (car encs))
                (lts (car ltss)))
            (let ((tau-bdd (BDD.False)))
              (for-each
               (lambda (tr)
                 (let ((src (car tr))
                       (act (cadr tr))
                       (dst (caddr tr)))
                   (if (eq? act 'tau)
                       (set! tau-bdd
                             (BDD.Or tau-bdd
                                     (BDD.And (encode-curr enc src)
                                              (encode-next enc dst)))))))
               (lts-transitions lts))
              ;; Only add partition if this instance has tau transitions
              (if (not (BDD.Equal tau-bdd (BDD.False)))
                  (set! partitions
                        (cons (make-partition 'tau (list i) tau-bdd
                                              (encoding-curr-vars enc)
                                              (encoding-next-vars enc))
                              partitions))))
            (iloop (+ i 1) (cdr ltss) (cdr encs)))))

    ;; Channel synchronizations: one partition per channel,
    ;; accumulating all send/recv pairs into a single BDD.
    (for-each
     (lambda (ch-entry)
       (let* ((ch-name  (car ch-entry))
              (si       (cadr ch-entry))
              (ri       (caddr ch-entry))
              (enc-s    (list-ref encodings si))
              (enc-r    (list-ref encodings ri))
              (lts-s    (list-ref renamed-lts-list si))
              (lts-r    (list-ref renamed-lts-list ri)))
         (let ((sync-bdd (BDD.False)))
           ;; Find all send/recv pairs on this channel
           (for-each
            (lambda (st)
              (if (equal? (cadr st) (list 'send ch-name))
                  (for-each
                   (lambda (rt)
                     (if (equal? (cadr rt) (list 'recv ch-name))
                         (set! sync-bdd
                               (BDD.Or sync-bdd
                                       (BDD.And
                                        (BDD.And (encode-curr enc-s (car st))
                                                 (encode-next enc-s (caddr st)))
                                        (BDD.And (encode-curr enc-r (car rt))
                                                 (encode-next enc-r (caddr rt))))))))
                   (lts-transitions lts-r))))
            (lts-transitions lts-s))
           (if (not (BDD.Equal sync-bdd (BDD.False)))
               (set! partitions
                     (cons (make-partition
                            'sync (list si ri) sync-bdd
                            (append (encoding-curr-vars enc-s)
                                    (encoding-curr-vars enc-r))
                            (append (encoding-next-vars enc-s)
                                    (encoding-next-vars enc-r)))
                           partitions))))))
     channel-map)

    (reverse partitions)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  5. Image computation
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (all-curr-vars encodings)
  (apply append (map encoding-curr-vars encodings)))

(define (all-next-vars encodings)
  (apply append (map encoding-next-vars encodings)))

(define (partitioned-image frontier partitions encodings)
  ;; Compute image using partitioned transition relation.  For each partition:
  ;;   1. Conjoin frontier with partition BDD (small: only involved vars)
  ;;   2. Quantify out participating curr-vars
  ;;   3. Rename participating next-vars to curr-vars
  ;;   4. OR into result
  ;; Non-participating curr-vars pass through unchanged — this IS the
  ;; frame condition: other instances keep their state.  No need to
  ;; build explicit frame BDDs.
  (let ((result (BDD.False)))
    (for-each
     (lambda (p)
       (let* ((involved-curr (partition-curr-vars p))
              (involved-next (partition-next-vars p))
              ;; Conjoin frontier with partition BDD — the partition
              ;; only mentions participating vars so the intermediate
              ;; is bounded by O(|frontier| * |partition|)
              (conj (BDD.And frontier (partition-bdd p)))
              ;; Quantify out participating curr-vars
              (img-partial (bdd-exists-list conj involved-curr))
              ;; Rename participating next-vars to curr-vars
              (img-renamed (bdd-rename img-partial involved-next involved-curr)))
         (set! result (BDD.Or result img-renamed))))
     partitions)
    result))

(define (symbolic-image-monolithic reached T encodings)
  ;; Original monolithic image computation (kept for reference).
  (let* ((conj (BDD.And reached T))
         (curr-vars (all-curr-vars encodings))
         (next-vars (all-next-vars encodings))
         (img-next (bdd-exists-list conj curr-vars))
         (img-curr (bdd-rename img-next next-vars curr-vars)))
    img-curr))

(define (partitioned-has-succ partitions)
  ;; Compute has-successor BDD from partitions.
  ;; A product state has a successor if ANY partition can fire.
  ;; Each partition's contribution (quantified over its next-vars) is a BDD
  ;; over only the participating curr-vars, which implicitly allows all
  ;; values for other instances — correct semantics for OR.
  (let ((result (BDD.False)))
    (for-each
     (lambda (p)
       (let ((p-has-succ (bdd-exists-list (partition-bdd p)
                                          (partition-next-vars p))))
         (set! result (BDD.Or result p-has-succ))))
     partitions)
    result))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  6. Main entry point
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (check-deadlock-symbolic! sys-file)
  ;; BDD-based symbolic deadlock checking.
  ;; Returns #t if deadlock-free, #f if deadlock exists.

  (dis "check-deadlock-symbolic!: parsing " sys-file " ..." dnl)
  (let ((sys (parse-sys-file sys-file)))

    (dis "check-deadlock-symbolic!: validating ..." dnl)
    (validate-system! sys)

    (let* ((type-lts-alist (extract-system-lts! sys-file))
           (instances  (sys-instances sys))
           (channels   (sys-channels sys))
           (processes  (sys-processes sys))
           (sname      (sys-name sys))
           (n          (length instances)))

      ;; Build renamed LTSs (reuse from product.scm)
      (let ((instance-lts-list
             (map (lambda (inst)
                    (let* ((pname     (inst-proc-name inst))
                           (cell-name (string-append sname "." pname))
                           (entry     (assoc cell-name type-lts-alist))
                           (type-lts  (if entry (cdr entry)
                                         (error "check-deadlock-symbolic!: no LTS for "
                                                cell-name)))
                           (renaming
                            (map (lambda (b)
                                   (cons (string->symbol (car b))
                                         (string->symbol (cdr b))))
                                 (inst-bindings inst))))
                      (rename-lts type-lts renaming)))
                  instances)))

        ;; Build encodings
        (let ((encodings
               (let loop ((i 0) (ltss instance-lts-list) (acc '()))
                 (if (null? ltss)
                     (reverse acc)
                     (loop (+ i 1) (cdr ltss)
                           (cons (make-inst-encoding i
                                   (lts-states (car ltss)))
                                 acc))))))

          ;; Build channel map (same logic as check-deadlock!)
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

            (dis "check-deadlock-symbolic!: "
                 (number->string n) " instances, "
                 (number->string (length channel-map)) " channels" dnl)

            ;; Report encoding sizes
            (let iloop ((i 0) (encs encodings) (ltss instance-lts-list))
              (if (not (null? encs))
                  (begin
                    (dis "  instance " (number->string i) ": "
                         (number->string (length (lts-states (car ltss))))
                         " states, "
                         (number->string (encoding-nbits (car encs)))
                         " bits" dnl)
                    (iloop (+ i 1) (cdr encs) (cdr ltss)))))

            ;; Build partitioned transition relation
            (dis "check-deadlock-symbolic!: building transition partitions ..." dnl)
            (let ((partitions (build-transition-partitions
                               encodings instance-lts-list channel-map)))

              (dis "check-deadlock-symbolic!: "
                   (number->string (length partitions)) " partitions" dnl)
              (let ploop ((ps partitions) (pi 0))
                (if (not (null? ps))
                    (let ((p (car ps)))
                      (dis "  partition " (number->string pi) " ("
                           (symbol->string (partition-type p)) "): "
                           (number->string (BDD.Size (partition-bdd p)))
                           " BDD nodes" dnl)
                      (ploop (cdr ps) (+ pi 1)))))

              ;; Compute has-successor from partitions
              (let ((has-succ (partitioned-has-succ partitions)))

                ;; Initial state: conjunction of all instances at initial state
                (let ((init-bdd
                       (let loop ((encs encodings) (ltss instance-lts-list)
                                  (acc (BDD.True)))
                         (if (null? encs)
                             acc
                             (loop (cdr encs) (cdr ltss)
                                   (BDD.And acc
                                            (encode-curr (car encs)
                                                         (lts-initial
                                                          (car ltss)))))))))

                  ;; Fixed-point reachability (frontier-based, partitioned image)
                  (dis "check-deadlock-symbolic!: computing reachability ..." dnl)
                  (let loop ((reached init-bdd) (frontier init-bdd) (iter 0))
                    (let* ((img (partitioned-image frontier partitions encodings))
                           (new-frontier (BDD.And img (BDD.Not reached)))
                           (new-reached (BDD.Or reached new-frontier)))
                      (dis "  iteration " (number->string iter)
                           ", reached BDD: "
                           (number->string (BDD.Size new-reached))
                           ", frontier BDD: "
                           (number->string (BDD.Size new-frontier)) dnl)
                      ;; Clear operation caches between iterations to reclaim
                      ;; memory from small intermediates
                      (BDD.ClearCaches)
                      (if (BDD.Equal new-frontier (BDD.False))
                          ;; Fixed point reached
                          (let ((deadlocked (BDD.And reached
                                                     (BDD.Not has-succ))))
                            (dis "check-deadlock-symbolic!: fixed point at iteration "
                                 (number->string iter) dnl)
                            (if (not (BDD.Equal deadlocked (BDD.False)))
                                (begin
                                  (dis "check-deadlock-symbolic!: DEADLOCK FOUND"
                                       " (deadlock BDD size: "
                                       (number->string (BDD.Size deadlocked))
                                       ")" dnl)
                                  #f)
                                (begin
                                  (dis "check-deadlock-symbolic!: system is deadlock-free."
                                       dnl)
                                  #t)))
                          ;; Continue iterating
                          (loop new-reached new-frontier (+ iter 1))))))))))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(dis "symbolic.scm loaded." dnl)
