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
;;  3. Frame conditions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (build-frame-bdd enc)
  ;; Frame condition: next-state equals current-state for this instance.
  ;; Conjunction of Equivalent(curr_k, next_k) for each bit k.
  (let loop ((cvs (encoding-curr-vars enc))
             (nvs (encoding-next-vars enc))
             (acc (BDD.True)))
    (if (null? cvs)
        acc
        (loop (cdr cvs) (cdr nvs)
              (BDD.And acc (BDD.Equivalent (car cvs) (car nvs)))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  4. Transition relation
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (build-all-frames encodings)
  ;; Precompute frame BDD for each instance.
  (map build-frame-bdd encodings))

(define (frame-for-all frames except-indices)
  ;; Conjunction of frame BDDs for all instances except those in except-indices.
  (let loop ((fs frames) (i 0) (acc (BDD.True)))
    (if (null? fs)
        acc
        (loop (cdr fs) (+ i 1)
              (if (memv i except-indices)
                  acc
                  (BDD.And acc (car fs)))))))

(define (build-transition-bdd encodings renamed-lts-list channel-map)
  ;; Build the full transition relation T(V, V') as a single BDD.
  (let ((frames (build-all-frames encodings))
        (n (length encodings)))

    (let ((T (BDD.False)))

      ;; Tau transitions: for each instance, each tau edge
      (let iloop ((i 0) (ltss renamed-lts-list) (encs encodings))
        (if (< i n)
            (let ((enc (car encs))
                  (lts (car ltss))
                  (tau-frame (frame-for-all frames (list i))))
              (for-each
               (lambda (tr)
                 (let ((src (car tr))
                       (act (cadr tr))
                       (dst (caddr tr)))
                   (if (eq? act 'tau)
                       (set! T (BDD.Or T
                                       (BDD.And
                                        (BDD.And (encode-curr enc src)
                                                 (encode-next enc dst))
                                        tau-frame))))))
               (lts-transitions lts))
              (iloop (+ i 1) (cdr ltss) (cdr encs)))))

      ;; Channel synchronizations
      (for-each
       (lambda (ch-entry)
         (let* ((ch-name  (car ch-entry))
                (si       (cadr ch-entry))
                (ri       (caddr ch-entry))
                (enc-s    (list-ref encodings si))
                (enc-r    (list-ref encodings ri))
                (lts-s    (list-ref renamed-lts-list si))
                (lts-r    (list-ref renamed-lts-list ri))
                (sync-frame (frame-for-all frames (list si ri))))
           ;; Find all send transitions on this channel
           (for-each
            (lambda (st)
              (if (equal? (cadr st) (list 'send ch-name))
                  ;; For each matching recv transition
                  (for-each
                   (lambda (rt)
                     (if (equal? (cadr rt) (list 'recv ch-name))
                         (set! T (BDD.Or T
                                         (BDD.And
                                          (BDD.And
                                           (BDD.And (encode-curr enc-s (car st))
                                                    (encode-next enc-s (caddr st)))
                                           (BDD.And (encode-curr enc-r (car rt))
                                                    (encode-next enc-r (caddr rt))))
                                          sync-frame)))))
                   (lts-transitions lts-r))))
            (lts-transitions lts-s))))
       channel-map)

      T)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  5. Image computation
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (all-curr-vars encodings)
  (apply append (map encoding-curr-vars encodings)))

(define (all-next-vars encodings)
  (apply append (map encoding-next-vars encodings)))

(define (symbolic-image reached T encodings)
  ;; Compute image: states reachable in one step from 'reached'.
  ;; 1. Conjoin reached with T
  ;; 2. Existentially quantify out current-state vars
  ;; 3. Rename next-state vars to current-state vars
  (let* ((conj (BDD.And reached T))
         (curr-vars (all-curr-vars encodings))
         (next-vars (all-next-vars encodings))
         ;; Project out current-state variables
         (img-next (bdd-exists-list conj curr-vars))
         ;; Rename next-state to current-state
         (img-curr (bdd-rename img-next next-vars curr-vars)))
    img-curr))

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

            ;; Build transition relation
            (dis "check-deadlock-symbolic!: building transition relation ..." dnl)
            (let ((T (build-transition-bdd encodings instance-lts-list
                                           channel-map)))

              (dis "check-deadlock-symbolic!: T has "
                   (number->string (BDD.Size T)) " BDD nodes" dnl)

              ;; Compute has-successor: states that have at least one successor
              (let ((next-vars (all-next-vars encodings)))
                (let ((has-succ (bdd-exists-list T next-vars)))

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

                    ;; Fixed-point reachability (frontier-based)
                    (dis "check-deadlock-symbolic!: computing reachability ..." dnl)
                    (let loop ((reached init-bdd) (frontier init-bdd) (iter 0))
                      (let* ((img (symbolic-image frontier T encodings))
                             (new-frontier (BDD.And img (BDD.Not reached)))
                             (new-reached (BDD.Or reached new-frontier)))
                        (dis "  iteration " (number->string iter)
                             ", reached BDD: "
                             (number->string (BDD.Size new-reached))
                             ", frontier BDD: "
                             (number->string (BDD.Size new-frontier)) dnl)
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
                            (loop new-reached new-frontier (+ iter 1)))))))))))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(dis "symbolic.scm loaded." dnl)
