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

(define *emit-wires* '())
(define *emit-assigns* '())
(define *emit-decls* '())
(define *emit-counter* 0)

(define (emit-reset!)
  (set! *emit-wires* '())
  (set! *emit-assigns* '())
  (set! *emit-decls* '())
  (set! *emit-counter* 0))

;; Memoize using bdd-equal? (handles complemented edges correctly)
(define (emit-lookup bdd)
  (let loop ((lst *emit-wires*))
    (if (null? lst) #f
        (if (bdd-equal? bdd (caar lst))
            (cdar lst)
            (loop (cdr lst))))))

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
              (set! *emit-wires* (cons (cons bdd name) *emit-wires*))
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

;; Emit a complete gate-level module.
;; output-bvs is ((sig-name . bdd-list) ...)
(define (emit-gate-module mod-name inputs outputs output-bvs)
  (define nl (list->string (list (integer->char 10))))
  (define lines '())
  (define (emit s) (set! lines (cons s lines)))

  (emit-reset!)

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

  ;; Module header
  (emit (string-append "module " mod-name "_gates ("))

  (for-each
    (lambda (inp)
      (let* ((name (cadr inp))
             (w (width-get name)))
        (if (= w 1)
            (emit (string-append "  input " (symbol->string name) ","))
            (emit (string-append "  input ["
                                 (number->string (- w 1))
                                 ":0] " (symbol->string name) ",")))))
    inputs)

  (for-each
    (lambda (out)
      (let* ((name (cadr out))
             (w (width-get name)))
        (if (= w 1)
            (emit (string-append "  output " (symbol->string name) ","))
            (emit (string-append "  output ["
                                 (number->string (- w 1))
                                 ":0] " (symbol->string name) ",")))))
    outputs)

  ;; Remove trailing comma
  (let ((last (car lines)))
    (set! lines (cons (substring last 0 (- (string-length last) 1))
                      (cdr lines))))
  (emit ");")
  (emit "")

  ;; Wire declarations
  (for-each (lambda (d) (emit d)) (reverse *emit-decls*))
  (if (> (length *emit-decls*) 0) (emit ""))

  ;; Gate assigns
  (for-each (lambda (a) (emit a)) (reverse *emit-assigns*))
  (emit "")

  ;; Output wiring -- group bits per signal, use concatenation
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

  (define grouped (group-output-wires output-wires))
  (for-each
    (lambda (grp)
      (let* ((sig (car grp))
             (bit-wires (cdr grp))
             (w (length bit-wires)))
        (if (= w 1)
            (emit (string-append "  assign " (symbol->string sig)
                                 " = " (cdar bit-wires) ";"))
            (let* ((sorted (reverse bit-wires))
                   (wire-list (map cdr sorted))
                   (concat-str (sv-join ", " wire-list)))
              (emit (string-append "  assign " (symbol->string sig)
                                   " = {" concat-str "};"))))))
    grouped)

  (emit "")
  (emit "endmodule")

  (let loop ((ls (reverse lines)) (acc ""))
    (if (null? ls) acc
        (loop (cdr ls) (string-append acc (car ls) nl)))))
