; Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information.
; SPDX-License-Identifier: Apache-2.0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; examples for test & debug
;;

(define some-field '(field INITIAL_W0_OFFSET 56 8))

(define some-reg
  '((cont POL_DIRECT_MAP_POL1)
         ((field CTOK_HI 40 24))
         ((field _RSVD1_ 37 3))
         ((field CTOK_LO 24 13))
         ((field _RSVD0_ 4 20))
         ((field CFG 0 4))
         )
  )

(define some-hier2
  `((cont hier) ,some-reg )
  )
         

(define some-array '((cont GLORT_CAM)
                          ((array 64)
                                 ((field KEY_INVERT 16 16))
                                 ((field KEY 0 16))
                                 )
                          )
  )


;; working structure
(dis "building fields-tree..." dnl)

(define fields-tree (treesum 'nfields the-map))

;;(define bits-tree (treesum 'nbits the-map))

;;(iter tl 11 fields-tree)

;;(iter fc 11 the-map)


(define hy '(7 (1) (1) (1) (1) (1) (1) (1))   )

(define (trunc-stringify x)  (error-append (stringify x)))

(define (array-marker a)
  (if (eq? (get-tag a) 'array) (cadar a) #f))

(define (zip-trees-old a b)
 ;; (if (not (tree-iso? a b)) (error "not tree-iso"))
  (cond ((null? a) '())
        ((atom? a) (cons a b))
        (else (cons (zip-trees-old (car a) (car b))
                    (zip-trees-old (cdr a) (cdr b))))))

(define (zip-trees a b)
  (cond ((null? a) '())
        (else (cons (cons (car a) (car b))
                    (map (lambda(x y) (zip-trees x y)) (cdr a) (cdr b))))))

(define (nuller x) '())

(define (build-zip t)
  (zip-trees (treemap array-marker t)
             (zip-trees (treesum 'nfields t)
                        (treemap nuller t))))

(define some-zip (build-zip some-array))

(define (zip-array? z)
  (let ((as (caadr z)))
    (and (car as) (/ (cadr as) (car as)))))

(define (get-zip-seq-offset z seq)
  (let loop ((p 0)
             (s seq)
             (q z))
    ;;(dis "p " (stringify p) " s " (stringify s) " q " (stringify q) dnl)
    (cond ((null? s) p)
          ((zip-array? q) =>
           (lambda (m) (loop (+ p (* (car s) m))
                             (cdr s)
                             (get-aux-child-by-cnt q 0))))
          (else (loop (+ p (accumulate + 0
                            (map cadar
                                 (get-aux-children-by-cnt q (car s)))))
                      (cdr s)
                      (get-aux-child-by-cnt q (car s)))))))
  
(define (fielddata->lsb fd)
  (+ (* 8 (cdr (assoc 'byte fd)))
     (cdr (assoc 'lsb fd))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; offset tree format
;;   -- this is the format for computing final addresses
;;   -- it includes all the arraying and size info needed
;;

;; make offset tree

(define (make-address-getter addresses)
  (lambda(x)
    (fielddata->lsb
     (FieldData.ArrayGet addresses x))))

(define (make-promise x)
  (list 'promise x))

(define (make-do opsym)
  (let ((op (eval opsym)))
    (lambda(a b)
      (if (and (number? a)(number? b))
          (op a b)
          (list opsym a b)))))

;;(define do- (make-do '-))
(define (do- a b)
  (define def (make-do '-))
  (if (equal? a b) 0 (def a b)))

;;(define do+ (make-do '+))
(define (do+ a b)
  (define def (make-do '+))
  (cond ((equal? a '0) b)
        ((equal? b '0) a)
        (else (def a b))))
      
(define (get-stride-bits array-spec indexer)
  ;; given a spec as follows
  ;; (base-addr elems . size)
  ;; compute element stride in bits
  (if (and (cadr array-spec)
           (> (cadr array-spec) 1))
      (let*  ((zeroth-field (car array-spec))
              (field-stride (/ (cddr array-spec)
                               (cadr array-spec)))
              (stride-field (do+ zeroth-field field-stride))
              (zeroth-bit (indexer zeroth-field))
              (stride-bit (indexer stride-field)))
        (do- stride-bit zeroth-bit))
      '()))

(define (make-offset-tree accum-tree array-tree fields-tree indexer)
  ;;
  ;; format of an elem here is
  ;; (<offset> #f)
  ;;     -- offset from parent for non-array
  ;; (<offset> <elems> . <bits-stride>)
  ;;     -- offset from parent, # of elements, stride in bits
  ;;
  ;; indexer is a procedure of one argument that maps the in-order
  ;; field index to a linear index in some space
  ;;
  (define (helper p b)
    (if (null? p)
        '()
        (let ((this-addr (indexer (caar p))))
          (cons (cons (do- this-addr b)
                      (cons (cadar p) (get-stride-bits (car p) indexer))
                      )
                (map (lambda(ff)(helper ff this-addr)) (cdr p))))))

  (helper (zip-trees accum-tree
                     (zip-trees array-tree fields-tree))
          0))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; use offset tree

(define (compute-array-pair-stride adesc idx)
  ;; format is (len . stride)
  ;; stride null for 0-length arrays
  (cond ((= idx 0) 0)
        ((or (< idx 0) (>= idx (car adesc)))
         (error "array index out of range : " idx " : " (stringify adesc)))
        (else  (* (cdr adesc) idx))))

(define (has-array-child? p)
  (and (cdr p)
       (= 1 (length (cdr p)))
       (car (cdaadr p))))
   
(define (compute-offset-from-seq ot seq)
  (define debug #f)
  
  (define (helper base p seq)
    (if debug
        (begin
          (dis "---" dnl)
          (dis "car p          : " (stringify (car p)) dnl)
          (dis "length (cdr p) : " (length (cdr p)) dnl)
          (dis "seq            : " (stringify seq)     dnl)
          )
        )
    
    (if (null? seq)
        base ;; done

        (if (has-array-child? p)
            ;; array case
            (let ((child (cadr p)))
              (if debug (dis "arr child      : " (trunc-stringify child) dnl))
              (helper
               (+ base (compute-array-pair-stride (cdar child) (car seq)))
               child
               (cdr seq)))

            ;; non-array case
            (let ((child (nth (cdr p) (car seq))))
              (if debug (dis "nonarr child   : " (trunc-stringify child) dnl))
              (helper
               (+ base (caar child))
               child
               (cdr seq))))))

  (helper 0 ot seq))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; test the offset tree
;;

(define zz (build-zip the-map))

(define the-array-tree (treemap array-marker the-map))

(define the-accum-tree (tree-accum fields-tree))


(define last-entry (FieldData.ArrayGet the-addresses
                                       (- (FieldData.ArraySize the-addresses)
                                          1)))
  
(dis "length of the-addresses " (FieldData.ArraySize the-addresses) dnl)

;; average width of field (including space) -- in bits
(define ave-width
  (* 8 (/ (+ (cdr (assoc 'byte last-entry))
             (/ (cdr (assoc 'wid last-entry)) 8))
          (+ (cdr (assoc 'id last-entry)) 1)))
  )

(dis "average width of fields " ave-width " bits" dnl)

(define the-chip-offset-tree
  (make-offset-tree the-accum-tree
                    the-array-tree
                    fields-tree
                    (make-address-getter the-addresses)))

(define the-fields-offset-tree
  (make-offset-tree the-accum-tree
                    the-array-tree
                    fields-tree
                    identity))

(define the-host-offset-tree
  (make-offset-tree the-accum-tree
                    the-array-tree
                    fields-tree
                    make-promise))


(define (make-spaces n)
  (if (= 0 n) "" (string-append " " (make-spaces (- n 1)))))

(define (compile-offset-c ot nm c-format port)
  (define (helper b t sp)
    (let ((ind (make-spaces (* 4 (+ 1 sp)))))
      (if (has-array-child? t)
          (let* ((child  (cadr t))
                 (aspec  (cdar child))
                 (stride (if (null? (cdr aspec))
                             "0xc0edbabe"
                             (cdr aspec)))
                 (size   (car aspec))
                 )
            (dis ind "{ /* array */" dnl
                 ind "  int idx = seq->d["(c-format sp)"];" dnl
                 ind "  if (idx == -1) return arr + "(c-format b)";" dnl
                 ind "  assert(idx >= 0 && idx < (int)"(c-format size)");" dnl
                 ind "  arr += idx * "(c-format stride)";" dnl
                 port )
            (helper b child (+ 1 sp))
            (dis ind "}" dnl
                 port)
            )
          (begin
            (dis ind "{ /*nonarray */" dnl
                 ind "  switch(seq->d["(c-format sp)"]) {" dnl
                 ind "    case -1: return arr + "(c-format b)"; break;" dnl
                 port)
            (let loop ((p     0)
                       (c     (cdr t)))
              (if (not (null? c))
                  (begin
                    (dis ind "    case " (c-format p)":" dnl
                         port)
                    (helper (do+ b (caaar c)) (car c) (+ 1 sp))
                    (loop (+ p 1) (cdr c)))
                  )
              )
            (dis ind "    default: assert(0); break;" dnl
                 ind "  }" dnl
                 ind "}" dnl
                 port)
            )
          )
      )
    )
  (dis "chipaddr_t" dnl nm"(const raggedindex_t *seq)" dnl
       "{" dnl
       "   chipaddr_t arr=ADDR_LITERAL(0);" dnl
       port)
  (helper 0 ot 0)
  (dis "}" dnl
       port)
  #t
  )

(define (compile-roffset-c ot nm c-format port)
  (define (helper b t sp)
    (let ((ind (make-spaces (* 4 (+ 1 sp)))))
      (cond
       ((null? (cdr t)) ;; no children
        (dis ind "seq->d["(c-format sp)"] = -1;" dnl
             ind "return a;" dnl
             port
        ))
       
       ((has-array-child? t) ;; child is array
        (let* ((child  (cadr t))
               (aspec  (cdar child))
               (stride (if (null? (cdr aspec)) "0xc0edbabe" (cdr aspec)))
               (size   (car aspec))
               )
          (dis ind "{ /* array */" dnl
               ind "  const chipaddr_t stride="(c-format stride)";" dnl
               ind "  const unsigned long idx = (a / stride) >= "(c-format size)" ? ("(c-format size)"-1):(a/stride);" dnl
               ind "  seq->d["(c-format sp)"] = idx;" dnl
               
               ind "  a -= idx * stride;" dnl
               port )
          (helper b child (+ 1 sp))
          (dis ind "}" dnl
               port)
          ))

       (else ;; non-array 
        (dis ind "{ /*nonarray */" dnl
             ind "  if(0) {}" dnl
             port)
        (let loop ((p     0)
                   (c     (cdr t)))
          (if (not (null? c))
              (begin
                (if (null? (cdr c))
                    (dis ind "  else {" dnl
                         port)
                    (dis ind "  else if(a < " (c-format (caaadr c))") {" dnl
                         port)
                    )
                (dis ind "    seq->d["(c-format sp)"] = "p";" dnl
                     ind "    a -= " (c-format (caaar c)) ";" dnl
                     port)
                (helper (do+ b (caaar c)) (car c) (+ 1 sp))
                (dis ind "  }" dnl port)
                (loop (+ p 1) (cdr c)))
              )
          )
        (dis ind "}" dnl
             port)
        )
       
       );;dnoc
      );;tel
    );; helper
  
  (dis "chipaddr_t" dnl nm"(chipaddr_t a, raggedindex_t *seq)" dnl
       "{" dnl
       port)
  (helper 0 ot 0)
  (dis "}" dnl
       port)
  #t
  )
  
(define symbols (make-symbol-set 100))

(define (make-number-hash-table size) (make-hash-table size identity))

(define (make-number-set size)
  (make-set (lambda()(make-number-hash-table size))))

(define sizes (make-number-set 100))

(define (record-symbols)
  (treemap
   (lambda(x)
     (let ((nm (get-name x)))
       (cond ((number? nm) (sizes   'insert! nm))
             ((symbol? nm) (symbols 'insert! nm))
             (else (error (error-append " : " (stringify nm)))))))
   the-map))

(define (make-c-sym-constant sym port)
  (dis "static const char       symbol_" sym "[]     = \"" sym "\";" dnl
       "static const arc_t      symbol_arc_" sym "   =  { symbol_" sym ", NULL };" dnl
       port
       )
  #t
  )

(define (dump-symbols port)
  (map (lambda(s)(make-c-sym-constant s port)) (symbols 'keys))
  #t
  )

(define (make-c-siz-constant sz port)
  (dis "static const arrayarc_t size_"sz"         = { " sz " };" dnl
       "static const arc_t      size_arc_"sz"     = { NULL, &size_"sz" };" dnl
       "static const arc_t     *size_arc_"sz"_a[] = { &size_arc_"sz", NULL };" dnl
       port)
  #t
  )

(define (dump-sizes port)
  (map (lambda(q)(make-c-siz-constant q port)) (sizes 'keys))
  #t
  )

(define (compile-child-arc-c nt nm port)
  (define *arcarray-cnt* 0)

  (define sym-arcarray-mem '()) ;; memoization-memory

  (define (make-sym-arcarray names)
    (let loop ((p sym-arcarray-mem))
      (cond ((null? p)
             (let ((nm (string-append "syms_arc_" *arcarray-cnt* "_a")))
               (dis "static const arc_t     *"nm"[] = { " port)
               (map (lambda(sym)(dis "&symbol_arc_" sym ", " port)) names)
               (dis "NULL };" dnl port)
               (set! *arcarray-cnt* (+ 1 *arcarray-cnt*))
               (set! sym-arcarray-mem (cons (cons names nm) sym-arcarray-mem))
               nm))
            ((equal? (caar p) names) (cdar p))
            (else (loop (cdr p))))))

  (define defer-port (TextWr.New))
  
  (define (has-array-child? q)
    (and (cdr q)
         (= 1 (length (cdr q)))
         (number? (caadr q))))
  
  (define (helper t sp)
    (let ((ind (make-spaces (* 2 (+ 1 sp)))))
      (if (has-array-child? t)
          (let* ((child  (cadr t))
                 (size   (caadr t))
                 )
            (dis ind "{ /* array */" dnl
                 ind "  int idx = seq->d["sp"];" dnl
                 ind "  if (idx == -1) return size_arc_"size"_a;" dnl
                 ind "  assert(idx >= 0 && idx < "size");" dnl
                 defer-port )
            (helper child (+ 1 sp))
            (dis ind "}" dnl
                 defer-port)
            )
          (begin
            (dis ind "{ /*nonarray */" dnl
                 ind "  switch(seq->d["sp"]) {" dnl
                 ind "    case -1: return "
                 (make-sym-arcarray (map car (cdr t)))
                 "; break;" dnl
                 defer-port)
            (let loop ((p     0)
                       (c     (cdr t)))
              (if (not (null? c))
                  (begin
                    (dis ind "    case " p":" dnl
                         defer-port)
                    (helper (car c) (+ 1 sp))
                    (loop (+ p 1) (cdr c)))
                  )
              )
            (dis ind "    default: assert(0); break;" dnl
                 ind "  }" dnl
                 ind "}" dnl
                 defer-port)
            )
          )
      )
    )
  (dis "const arc_t **" dnl nm"(const raggedindex_t *seq)" dnl
       "{" dnl
       defer-port)
  (helper nt 0)
  (dis "}" dnl
       defer-port)
  (dis (TextWr.ToText defer-port) port)
  #t
  )

(define name-tree (treemap get-name the-map))

(define *api-dir* "test_api/")

(define (open-c-files pfx)
  (let ((ifsym (string-append "_" (CitTextUtils.ToUpper pfx) "_H"))
        (res
         (cons (FileWr.Open (string-append *api-dir* pfx ".h"))
               (FileWr.Open (string-append *api-dir* pfx ".c")))))
    (dis "#include \""pfx".h\"" dnl
         "#include <assert.h>" dnl
         "#include \"raggedindex.h\"" dnl
         dnl
         (cdr res))

    (dis "#ifndef "ifsym dnl 
         "#define "ifsym dnl
         "#include \"raggedindex.h\"" dnl

         (car res))
    res))

(define (close-c-files files)
  (dis "#endif" dnl (car files))
  (Wr.Close (car files))
  (Wr.Close (cdr files)))

(define (c-formatter x)
  (cond ((number? x) (string-append (stringify x) "UL"))
        ((atom? x) x)
        (else (error (error-append "attempting to write to C : " x)))))

(define (format-c-expr x)
  (cond ((and (list? x)
              (eq? (car x) 'promise))
         (string-append "get_ptr_value(" (stringify (cadr x)) ")"))
        
        ((list? x)
         (string-append
          "("
          (format-c-expr (cadr x))
          (stringify (car x))
          (format-c-expr (caddr x))
          ")"))

        (else (stringify x))))
         

(define (make-c-expr-formatter wr0 wr1)
  (let ((mem '())
        (n 0)
        )
    (lambda(x)
      (if (pair? x)

          (let ((have-it (assoc x mem)))
            (if have-it
                (cdr have-it)
                (let ((new-var (string-append "hostptr_const" (stringify n))))
                  (set! n (+ n 1))
                  (dis "chipaddr_t " new-var ";" dnl wr0)
                  (dis "  " new-var " = " (format-c-expr x) ";" dnl wr1)
                  (set! mem (cons (cons x new-var) mem))
                  new-var
                  )
                )
            )
          
          (c-formatter x)))))


(define (build-hostptr-stuff)
  (let ((h-stream '())
        (c-stream '())
        (decls (TextWr.New))
        (inits (TextWr.New))
        (*setup-name* "hostptr_setup"))

    (define (open pfx)
      (let ((q (open-c-files pfx)))
        (set! h-stream (car q))
        (set! c-stream (cdr q))))

    (define (close)
      (close-c-files (cons h-stream c-stream)))
    
  (let* (
         (xfmt (make-c-expr-formatter decls inits))
         )
    
    (dis "*** compiling host offset tree..." dnl)
    (let ((nm "ragged2ptr"))
      (open nm)
      (dis "#include \"hostptr_setup.h\"" dnl
           dnl c-stream)
      
      (compile-offset-c the-host-offset-tree nm xfmt c-stream)
      (dis "chipaddr_t "nm"(const raggedindex_t *);" dnl h-stream)
      (close)
      )
    
    (dis "*** compiling reverse host offset tree..." dnl)
    (let ((nm "ptr2ragged"))
      (open nm)
      (dis "#include \"hostptr_setup.h\"" dnl
           dnl c-stream)
      
      (compile-roffset-c the-host-offset-tree nm xfmt c-stream)
      (dis "chipaddr_t "nm"(chipaddr_t, raggedindex_t *);" dnl h-stream)
      (close)
      )
    )

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  
  (open *setup-name*)
  (dis (TextWr.ToText decls) h-stream)

  (dis "#include <malloc.h>" dnl
       "#include \"inorderid2ragged.h\"" dnl
       "#include \"mby_top_map.h\"" dnl
       "#include \"hostptr_setup.h\"" dnl
       dnl c-stream)
  (dis dnl
       "static mby_top_map *proto;" dnl dnl c-stream)
  (dis dnl
       "static chipaddr_t" dnl
       "get_ptr_value(const chipaddr_t inorder)"dnl
       "{" dnl
       "  raggedindex_t ra;" dnl
       dnl
       "  inorderid2ragged(inorder, &ra);" dnl
       "  return (chipaddr_t)mby_top_map__getptr(proto, ra.d);" dnl
       "}" dnl
       dnl c-stream
       )
  
  (dis "void init_hostptr(void);" dnl h-stream)
  (dis "void" dnl
       "init_hostptr(void)" dnl
       "{" dnl
       "  proto = malloc(sizeof(mby_top_map));" dnl
       dnl
       c-stream)
  (dis (TextWr.ToText inits) c-stream)
  (dis "  free(proto);" dnl
       "}" dnl dnl
       c-stream)
  (close)
  )
  )

(define (doit)
  (let ((h-stream '())
        (c-stream '()))

    (define (open pfx)
      (let ((q (open-c-files pfx)))
        (set! h-stream (car q))
        (set! c-stream (cdr q))))

    (define (close)
      (close-c-files (cons h-stream c-stream)))
    
    (dis "*** building C code..." dnl)

    (define (b1) 
    (dis "*** compiling chip address offset tree..." dnl)
    (let* ((nm "ragged2addr")
           (p (open-c-files nm))
           (h-stream (car p))
           (c-stream (cdr p)))
      (compile-offset-c the-chip-offset-tree nm c-formatter c-stream)
      (dis "chipaddr_t "nm"(const raggedindex_t *);" dnl h-stream)
      (close-c-files p)
      )
    )

    (define (b2)
    (dis "*** compiling reverse chip address offset tree..." dnl)
    (let* ((nm "addr2ragged")
           (p (open-c-files nm))
           (h-stream (car p))
           (c-stream (cdr p)))

      (compile-roffset-c the-chip-offset-tree nm c-formatter c-stream)
      (dis "chipaddr_t "nm"(chipaddr_t, raggedindex_t *);" dnl h-stream)
      (close-c-files p)
      )
    )

    (define (b3)
    (dis "*** compiling in order field offset tree..." dnl)
    (let* ((nm "ragged2inorderid")
          (p (open-c-files nm))
           (h-stream (car p))
           (c-stream (cdr p)))
      (compile-offset-c the-fields-offset-tree nm c-formatter c-stream)
      (dis "chipaddr_t "nm"(const raggedindex_t *);" dnl h-stream)
      (close-c-files p)
      )
    )

    (define (b4)
    (dis "*** compiling reverse in order field offset tree..." dnl)
    (let* ((nm "inorderid2ragged")
          (p (open-c-files nm))
          (h-stream (car p))
          (c-stream (cdr p)))
      (compile-roffset-c the-fields-offset-tree nm c-formatter c-stream)
      (dis "chipaddr_t "nm"(chipaddr_t, raggedindex_t *);" dnl h-stream)
      (close-c-files p)
      )
    )

    (define (b5)
    (dis "*** setting up static symbols..." dnl)
    (let* ((nm "ragged2arcs")
          (p (open-c-files nm))
          (h-stream (car p))
          (c-stream (cdr p)))
      (record-symbols)
      (dump-symbols c-stream)
      (dump-sizes c-stream)

      (dis "*** compiling names tree..." dnl)
      (compile-child-arc-c name-tree nm c-stream)
      (dis "const arc_t **"nm"(const raggedindex_t *);" dnl h-stream)
      (close-c-files p)
      )
    )

    (define jobs (list b1 b2 b3 b4 b5))

    (map (lambda(j)(apply j '())) jobs)

    ;; the parallel implementation doesnt work but I dont know why...
    ;;(map at-join (map (lambda(j)(at-run 0 j '())) jobs))
    
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    (build-hostptr-stuff)

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

   )


)

