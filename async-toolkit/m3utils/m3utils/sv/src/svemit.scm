;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; svemit.scm -- BDD-to-gate-level SystemVerilog emitter
;;
;; Decomposes BDDs into Shannon expansion (MUX) gates:
;;   wire = (var & high_child) | (~var & low_child)
;;
;; Requires svbase.scm and svbv.scm (for width-get, bv-lookup, etc.)
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define *emit-assigns* '())
(define *emit-decls* '())
(define *emit-counter* 0)

;; Mutable binary trie for O(1) BDD hash -> wire name lookup.
;; Node: (value . (left . right)) where left=bit-0, right=bit-1.
(define *emit-trie-depth* 24)
(define *emit-trie* #f)

(define (make-trie-node) (cons #f (cons #f #f)))

(define (emit-reset!)
  (set! *emit-assigns* '())
  (set! *emit-decls* '())
  (set! *emit-counter* 0)
  (set! *emit-trie* (make-trie-node)))

(define (emit-trie-ref hash)
  (let loop ((node *emit-trie*) (h hash) (d *emit-trie-depth*))
    (if (not node) #f
        (if (= d 0) (car node)
            (if (= 0 (modulo h 2))
                (loop (cadr node) (quotient h 2) (- d 1))
                (loop (cddr node) (quotient h 2) (- d 1)))))))

(define (emit-trie-set! hash value)
  (let loop ((node *emit-trie*) (h hash) (d *emit-trie-depth*))
    (if (= d 0)
        (set-car! node value)
        (if (= 0 (modulo h 2))
            (let ((child (cadr node)))
              (if (not child)
                  (begin
                    (set! child (make-trie-node))
                    (set-car! (cdr node) child)))
              (loop child (quotient h 2) (- d 1)))
            (let ((child (cddr node)))
              (if (not child)
                  (begin
                    (set! child (make-trie-node))
                    (set-cdr! (cdr node) child)))
              (loop child (quotient h 2) (- d 1)))))))

(define (emit-lookup bdd)
  (emit-trie-ref (bdd-hash bdd)))

;; Collect all unique BDD variable names from a list of BDD outputs.
;; Returns a list of variable name strings (e.g. "opcode[0]", "P[3]").
;; Uses emit-trie infrastructure for fast dedup.
(define (collect-bdd-vars output-bvs)
  (define seen (make-trie-node))
  (define depth *emit-trie-depth*)
  (define vars '())
  (define (seen-ref h)
    (let loop ((node seen) (hh h) (d depth))
      (if (not node) #f
          (if (= d 0) (car node)
              (if (= 0 (modulo hh 2))
                  (loop (cadr node) (quotient hh 2) (- d 1))
                  (loop (cddr node) (quotient hh 2) (- d 1)))))))
  (define (seen-set! h)
    (let loop ((node seen) (hh h) (d depth))
      (if (= d 0)
          (set-car! node #t)
          (if (= 0 (modulo hh 2))
              (let ((child (cadr node)))
                (if (not child)
                    (begin
                      (set! child (make-trie-node))
                      (set-car! (cdr node) child)))
                (loop child (quotient hh 2) (- d 1)))
              (let ((child (cddr node)))
                (if (not child)
                    (begin
                      (set! child (make-trie-node))
                      (set-cdr! (cdr node) child)))
                (loop child (quotient hh 2) (- d 1)))))))
  (define (walk bdd)
    (cond
      ((bdd-true? bdd) #f)
      ((bdd-false? bdd) #f)
      (else
        (let ((h (bdd-hash bdd)))
          (if (not (seen-ref h))
              (begin
                (seen-set! h)
                (let* ((var (bdd-node-var bdd))
                       (var-name (bdd-name var)))
                  (if (not (member var-name vars))
                      (set! vars (cons var-name vars)))
                  (walk (bdd-high bdd))
                  (walk (bdd-low bdd)))))))))
  ;; Also walk cut BDDs to find their input variables
  (for-each
    (lambda (cut)
      (walk (cdr cut)))
    *bv-cuts*)
  (for-each
    (lambda (asgn)
      (for-each walk (cdr asgn)))
    output-bvs)
  (reverse vars))

;; Map a BDD to a wire name, emitting gate assigns as needed.
(define (bdd->wire bdd)
  (cond
    ((bdd-true? bdd) "1")
    ((bdd-false? bdd) "0")
    (else
      (let ((cached (emit-lookup bdd)))
        (if cached cached
            (let* ((var (bdd-node-var bdd))
                   (var-name (bdd-name var))
                   (hi (bdd-high bdd))
                   (lo (bdd-low bdd))
                   (hi-wire (bdd->wire hi))
                   (lo-wire (bdd->wire lo))
                   (name (string-append "_n"
                           (number->string *emit-counter*))))
              (set! *emit-counter* (+ *emit-counter* 1))
              (emit-trie-set! (bdd-hash bdd) name)
              (set! *emit-decls*
                    (cons (string-append "  wire " name ";")
                          *emit-decls*))
              (set! *emit-assigns*
                    (cons (string-append
                            "  assign " name " = ("
                            var-name " & " hi-wire
                            ") | (~" var-name " & " lo-wire ");")
                          *emit-assigns*))
              name))))))

;; Group output wires by signal name for concatenation.
(define (group-output-wires ows)
  (let loop ((ows ows) (acc '()))
    (if (null? ows) acc
        (let* ((ow (car ows))
               (sig (car ow))
               (i (cadr ow))
               (wire (caddr ow))
               (existing (assq sig acc)))
          (if existing
              (begin
                (set-cdr! existing
                          (append (cdr existing) (list (cons i wire))))
                (loop (cdr ows) acc))
              (loop (cdr ows)
                    (append acc (list (list sig (cons i wire))))))))))

;; Emit gate-level module directly to a port (avoids O(n^2) string concat).
;; output-bvs is ((sig-name . bdd-list) ...)
;;
;; Gate assigns are emitted in topological order: each cut's Shannon
;; expansion gates come first, then its cut wire assign, then the next
;; cut, then output BDD gates.  This ensures that sequential processing
;; (e.g. for round-trip verification) resolves all signals correctly.
(define (emit-gate-module-to-port mod-name inputs outputs output-bvs port)
  (define nl (list->string (list (integer->char 10))))
  (define (wr s) (display s port) (display nl port))

  (emit-reset!)

  ;; Process cuts one at a time, collecting gates and cut assigns
  ;; in proper interleaved order for topological correctness.
  (define all-gate-lines '())  ;; accumulated in reverse

  (define cut-wires '())
  (for-each
    (lambda (cut)
      (let* ((cut-name (car cut))
             (cut-bdd (cdr cut))
             ;; Snapshot *emit-assigns* length before processing this cut
             (before-len (length *emit-assigns*))
             (wire (bdd->wire cut-bdd))
             ;; New assigns from this cut
             (new-assigns (let loop ((lst *emit-assigns*) (n (- (length *emit-assigns*) before-len)) (acc '()))
                            (if (= n 0) acc
                                (loop (cdr lst) (- n 1) (cons (car lst) acc))))))
        ;; Add this cut's gates, then its cut wire assign
        (set! all-gate-lines (append (reverse new-assigns) all-gate-lines))
        (set! all-gate-lines
              (cons (string-append "  assign " cut-name " = " wire ";")
                    all-gate-lines))
        (set! cut-wires (cons (cons cut-name wire) cut-wires))))
    (reverse *bv-cuts*))

  ;; Snapshot: all assigns so far include cut-related gates
  (define cut-assigns-count (length *emit-assigns*))

  ;; Walk output BDDs
  (define output-wires '())
  (for-each
    (lambda (asgn)
      (let* ((sig (car asgn))
             (bv (cdr asgn))
             (w (length bv)))
        (let loop ((i 0) (bits bv))
          (if (< i w)
              (let ((wire (bdd->wire (car bits))))
                (set! output-wires
                      (cons (list sig i wire w) output-wires))
                (loop (+ i 1) (cdr bits)))))))
    output-bvs)
  (set! output-wires (reverse output-wires))

  ;; Remaining gate assigns (from output BDD processing)
  (define output-assigns
    (let loop ((lst *emit-assigns*) (n (- (length *emit-assigns*) cut-assigns-count)) (acc '()))
      (if (= n 0) acc
          (loop (cdr lst) (- n 1) (cons (car lst) acc)))))

  ;; Module header
  (wr (string-append "module " mod-name "_gates ("))

  (for-each
    (lambda (inp)
      (let* ((name (cadr inp))
             (w (width-get name)))
        (if (= w 1)
            (wr (string-append "  input " (symbol->string name) ","))
            (wr (string-append "  input ["
                               (number->string (- w 1))
                               ":0] " (symbol->string name) ",")))))
    inputs)

  ;; Last output port (no trailing comma)
  (define last-port-name (cadr (car (reverse outputs))))

  (for-each
    (lambda (out)
      (let* ((name (cadr out))
             (w (width-get name))
             (comma (if (eq? name last-port-name) "" ",")))
        (if (= w 1)
            (wr (string-append "  output " (symbol->string name) comma))
            (wr (string-append "  output ["
                               (number->string (- w 1))
                               ":0] " (symbol->string name) comma)))))
    outputs)

  (wr ");")
  (wr "")

  ;; Wire declarations (from Shannon expansion)
  (for-each (lambda (d) (wr d)) (reverse *emit-decls*))

  ;; Cut wire declarations
  (for-each
    (lambda (cw)
      (wr (string-append "  wire " (car cw) ";")))
    (reverse cut-wires))
  (if (or (> (length *emit-decls*) 0) (> (length cut-wires) 0))
      (wr ""))

  ;; Gate and cut assigns in topological order
  (for-each (lambda (a) (wr a)) (reverse all-gate-lines))
  (wr "")

  ;; Output BDD gate assigns
  (for-each (lambda (a) (wr a)) output-assigns)
  (wr "")

  ;; Output wiring
  (define grouped (group-output-wires output-wires))
  (for-each
    (lambda (grp)
      (let* ((sig (car grp))
             (bit-wires (cdr grp))
             (w (length bit-wires)))
        (if (= w 1)
            (wr (string-append "  assign " (symbol->string sig)
                               " = " (cdar bit-wires) ";"))
            (let* ((sorted (reverse bit-wires))
                   (wire-list (map cdr sorted))
                   (concat-str (sv-join ", " wire-list)))
              (wr (string-append "  assign " (symbol->string sig)
                                 " = {" concat-str "};"))))))
    grouped)

  (wr "")
  (wr "endmodule"))

;; Backward-compatible string version (fine for small modules).
;; For large modules, use emit-gate-module-to-port.
(define (emit-gate-module mod-name inputs outputs output-bvs)
  (let ((p (open-output-file "/tmp/svemit_tmp.sv")))
    (emit-gate-module-to-port mod-name inputs outputs output-bvs p)
    (close-output-port p))
  ;; Read back the file
  (let ((p (open-input-file "/tmp/svemit_tmp.sv")))
    (let loop ((chars '()))
      (let ((c (read-char p)))
        (if (eof-object? c)
            (begin (close-input-port p)
                   (list->string (reverse chars)))
            (loop (cons c chars)))))))
