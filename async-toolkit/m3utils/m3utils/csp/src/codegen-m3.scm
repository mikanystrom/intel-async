; Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information.
; SPDX-License-Identifier: Apache-2.0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 
;; Code generator for CSP compiler.
;;
;; Generates Modula-3 code for CM3 (Critical Mass Modula-3) with
;; Modula-Scheme package installed.
;;
;; Target is a 64-bit machine of any architecture.  Detailed
;; architecture or endianness should not matter.
;;
;; Author : mika.nystroem@intel.com
;; May, 2025
;;

(define *default-slack* 1)
;;(define *default-slack* (* 100 1000))
;;(define *default-slack* 10)
;;(define *default-slack* 1000)
;; we should get slack from the CSP source code, but for now we don't,
;; so we do it this way

(define *target-word-size* 64) ;; word size of target machine
(define *bwsz*    *target-word-size*)
(define *bwszm1*  (xnum-- *bwsz* 1))

(define m3-word-min 0)
(define m3-word-max (xnum--(xnum-<< 1 *bwsz*) 1))

(define m3-integer-min (xnum-- (xnum-<< *big1* *bwszm1*)))
(define m3-integer-max (xnum-- (xnum-<< *big1* *bwszm1*) *big1*))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (m3-expand-type type)
  (cond ((boolean-type? type) "BOOLEAN")
        ((string-type?  type) "TEXT")
        ((integer-type? type) (m3-expand-int-type type))
        ((array-type?   type) (m3-expand-array-type type))
        ((struct-type?  type) (m3-expand-struct-type type)) ;; hmm
        (else (error "Unknown type " type))
        )
  )

(define (m3-expand-array-type type)
  ;; this isnt right, this is just an open array
  ;; -- we often need the range.
  (string-append "ARRAY OF " (m3-expand-type (caddr type))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; map identifiers (we could do this so much better directly in M3)
;;

(define (string->integer str1)
  ;; single character symbol sym1
  (char->integer (car (string->list str1))))

(define (symbol->integer sym1)
  ;; single character symbol sym1
  (string->integer (symbol->string sym1)))

(define m3-ident
  ;; this particular piece of code is implemented in M3 for efficiency
  (compose M3Ident.Escape symbol->string))

(define m3-struct (compose (curry sa "struct_") m3-ident))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 
;;
;;

(define (m3-write-port-decl w pdef)
  (w "    " (pad 40 (m3-ident (get-port-id pdef)))
     " : "
     (m3-convert-port-type-array (get-port-def-type pdef))
     " "
     (m3-convert-port-type-scalar (get-port-def-type pdef))
     ".Ref (*:= NIL*) ;" dnl
     )
  (w "    " "(*" (stringify pdef) "*)" dnl)
  )

(define (m3-format-port-ass pdef)
  (let ((ident (m3-ident (get-port-id pdef))))
    (string-append ident " := " ident)
    )
  )

(define (bf x)
  ;; format an exact integer in base 10
  (number->string x 10))

(define (m3-format-hex x)
  ;; format an exact integer as uppercase hex digits (no prefix)
  (CitTextUtils.ToUpper (number->string (abs x) 16)))

(define (m3-format-literal x base)
  ;; format as M3 literal: [sign]<base>_<digits>
  (let ((sign (if (negative? x) "-" ""))
        (prefix (string-append (number->string base 10) "_"))
        (digits (CitTextUtils.ToUpper (number->string (abs x) base))))
    (string-append sign prefix digits)))

(define (m3-native-literal expr)
  (if (not (bigint? expr))
      (error "not a constant integer : " expr)
      (m3-format-literal expr 16)
      );;fi
  )

(define (m3-map-decltype type)
  ;; returns interface
  (cond ((string-type?  type) "CspString")
        ((boolean-type? type) "CspBoolean")

        ((array-type?   type)
         (m3-map-decltype (array-elemtype type)))
        
        
        ((struct-type?  type)
         #f
         )
        
        ((integer-type? type)
         (let ((width (cadddr type)))
           (cond ((not (bigint? width)) "DynamicInt")
                 ((caddr type)
                  (string-append "SInt" (bf width)))
                 (else
                  (string-append "UInt" (bf width)))
                 );;dnoc
           );;tel
         )
        (else (error "m3-map-decltype : unknown type to map : " type))
        );;dnoc
  )

(define (m3-mask-native-assign lhs-type rhs)
  (if (not (integer-type? lhs-type)) (error))

  (let* ((signed  (caddr lhs-type))
         (width   (cadddr lhs-type))
         (m3-type (m3-map-decltype lhs-type))
         (sx0    (if signed (sa m3-type "Ops.SignExtend") ""))
         )
         

    (cond ((not (bigint? width)) (error))

          (else (sa sx0
                    "(Word.And("
                    rhs
                    " , "
                    m3-type
                    ".Mask)) "
                    ))
          )
    )
  )

(define (m3-map-declbuild type)
  ;; returns interface to build
  (cond ((string-type?  type) #f)
        ((boolean-type? type) #f)
        ((array-type?   type) #f)
        ((struct-type?  type) #f)
        ((integer-type? type)
         (let ((width (cadddr type)))
           (cond ((not (bigint? width)) #f)
                 ((caddr type)
                  (cons 'SInt width))
                 (else
                  (cons 'UInt width))
                 );;dnoc
           );;tel
         )
        (else (error "m3-map-declbuild : unknown type to map : " type))
        );;dnoc
  )

(define (m3-make-array-decl lo hi of)
  (sa "ARRAY [ " lo " .. " hi " ] OF " of )
  )

(define *m3t* #f)
                     
(define (m3-type type)
  (set! *m3t* type)
  (let ((decltype (m3-map-decltype type)))
    (cond
          ((array-type? type)
           (let ((extent (array-extent type))
                 (elem   (array-elemtype type)))

             (m3-make-array-decl 
              (m3-native-literal (cadr extent))
              (m3-native-literal (caddr extent))
              (m3-type elem))
             
             );;tel
           )

          ((struct-type? type)
           (m3-struct (struct-type-name type)))

          (decltype (sa decltype ".T"))
          
          (else (error))
          );;dnoc
    );;tel
  )
           
(define (m3-convert-vardecl v1)
  (dis "m3-convert-vardecl : v1 : " v1 dnl)
  (let ((id (get-var1-id v1))
        (ty (get-decl1-type (get-var1-decl1 v1)))
        )
    (string-append (pad 40 (m3-ident id)) " : " (m3-type ty) " (*" (stringify v1) "*);")
    )
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define get-field-id cadadr)

(define get-field-type caddr)

(define get-field-dir cadddr) ;; shd. return 'none

(define get-field-init cddddr) ;; returns a list of one elem or '()

(define (m3-convert-fielddecl fd)
  (dis "m3-convert-fielddecl : fd : " fd dnl)
  (let ((id (get-field-id   fd))
        (ty (get-field-type fd))
        )
    (string-append (pad 40 (m3-ident id)) " : " (m3-type ty) " (*" (stringify fd) "*);")
    )
  )

(define (m3-convert-pack-unpack w m3nm sd)
  ;; generate the routines for packing/unpacking structs
  
    (w "PROCEDURE " m3nm "_unpack_dynamic(VAR s : " m3nm "; x, scratch : DynamicInt.T) : DynamicInt.T =" dnl
       "  BEGIN" dnl)
    (map (yrruc w ";" dnl)
         (m3-make-unpack-body 'dynamic "s" "x" sd))
    (w
     "    RETURN x" dnl
     "  END " m3nm "_unpack_dynamic;" dnl
     dnl
     "CONST " m3nm "_unpack_wide = " m3nm "_unpack_dynamic;" dnl
     dnl
       )
    
    (w "PROCEDURE " m3nm "_unpack_native(VAR s : " m3nm "; x : NativeInt.T) : NativeInt.T =" dnl
       "  BEGIN" dnl)
    (map (yrruc w ";" dnl)
         (m3-make-unpack-body 'native "s" "x" sd))
    (w
     "    RETURN x" dnl
     "  END " m3nm "_unpack_native;" dnl
       dnl
       )

    
    (w "PROCEDURE " m3nm "_pack_dynamic(x, scratch : DynamicInt.T; READONLY s : " m3nm ") : DynamicInt.T =" dnl
       "  BEGIN" dnl)

    (map (yrruc w ";" dnl)
         (m3-make-pack-body 'dynamic "x" "s" sd))

    (w
     "    RETURN x" dnl
     "  END " m3nm "_pack_dynamic;" dnl
     dnl
     "CONST " m3nm "_pack_wide = " m3nm "_pack_dynamic;" dnl
     dnl
       )

    (w "PROCEDURE " m3nm "_pack_native(x : NativeInt.T; READONLY s : " m3nm ") : NativeInt.T =" dnl
       "  BEGIN" dnl)
       (map (yrruc w ";" dnl)
            (m3-make-pack-body 'native "x" "s" sd))
       (w
     "    RETURN x" dnl
     "  END " m3nm "_pack_native;" dnl
       dnl
       )
)

(define (m3-convert-structdecl pc sd)
  ;;
  ;; make all the routines associated with a struct type
  ;;
  ;; That is:
  ;; -- pack/unpack
  ;; -- initialization
  ;; -- assignment
  ;;
  
  (dis "m3-convert-structdecl : sd    : " sd dnl)
  (let* ((nm    (cadr sd))
         (m3nm  (m3-struct nm))
         (fds   (cddr sd))
         (wx    (Wx.New))
         (width (structdecl-width sd))
         )
    (define (w . x) (Wx.PutText wx (apply string-append x)))

    (dis "m3-convert-structdecl : width : " width dnl)

    (w "TYPE " m3nm " = RECORD" dnl)
    (map (yrruc (curry w "  ") dnl)
         (map m3-convert-fielddecl fds))
    (w "END;" dnl
       dnl)

    (if (> width 0)
        (m3-convert-pack-unpack w m3nm sd))

    (w "PROCEDURE " m3nm "_initialize(VAR s : " m3nm ") = " dnl
       "  BEGIN" dnl)
    (map (yrruc w ";" dnl)
         (m3-make-init-body pc "s" sd))
    (w
       "  END " m3nm "_initialize;" dnl
       dnl
       )
    
    (w "PROCEDURE " m3nm "_assign(VAR tgt : " m3nm " ; READONLY src : " m3nm " ) = " dnl
       "  BEGIN" dnl)
    (map (yrruc w ";" dnl)
         (m3-make-assign-body pc "tgt" "src" sd))
    (w
       "  END " m3nm "_assign;" dnl
       dnl
       )
    (Wx.ToText wx)
    )
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; struct pack/unpack details
;;

(define *sd* #f)

(define (m3-make-pack-field class m3tgt m3src fd)
  (let* ((ty     (get-decl1-type fd))

         (aty    (array-base-type ty))
         (adims  (array-dims ty))

         (id     (get-decl1-id fd))
         (m3id   (m3-ident id))
         (packer (m3-type-packer "pack" class (if aty aty ty)))
         (scrtch (if (eq? 'dynamic class) "scratch , " ""))
         )
    ;; If it is an array, we need to build the array calls
    ;; using the code from m3-initialize-array

    (m3-initialize-array
     (lambda(txt)
       (sa m3tgt " := " packer "(" m3tgt " , " scrtch txt  ")"))
     (sa m3src "." m3id)
     adims
     'pack_field
     )
    )
  )

(define (m3-make-unpack-field class m3tgt m3src fd)
  (let* ((ty     (get-decl1-type fd))

         (aty    (array-base-type ty))
         (adims  (array-dims ty))

         (id     (get-decl1-id fd))
         (m3id   (m3-ident id))
         (packer (m3-type-packer "unpack" class (if aty aty ty)))
         (scrtch (if (eq? 'dynamic class) ", scratch " ""))
         )
    ;; If it is an array, we need to build the array calls
    ;; using the code from m3-initialize-array

    (m3-initialize-array
     (lambda(txt)
       (sa m3src " := " packer "(" txt" , x " scrtch ")"))
     (sa m3tgt "." m3id)
     (- adims)
     'unpack_field
     )
    )
  )

(define (m3-type-packer whch class type)
  (let ((sfx (symbol->string class)))
    (cond ((integer-type? type)
           (sa (m3-map-decltype type) "Ops." whch "_" sfx))
          
          ((boolean-type? type)
           (sa (m3-map-decltype type) "." whch "_" sfx))
          
          ((struct-type? type)
           (sa (m3-struct (caddr type)) "_" whch "_" sfx))

          (else (error "m3-type-packer : no proc for packing " type))
          
          );;dnoc
    );;tel
  )

(define (m3-make-pack-body class m3tgt m3src sd)
  (set! *sd* sd)
  (dis "m3-make-pack-body : sd : " (stringify sd) dnl)
  (let ((fields (cddr sd)))
    ;; here we want to walk the fields, calling the type packer for
    ;; each field. (m3-make-pack-field)
    
    (map (curry m3-make-pack-field class m3tgt m3src) fields)
    )
  )

(define (m3-make-unpack-body class m3tgt m3src sd)
  (set! *sd* sd)
  (dis "m3-make-unpack-body : sd : " (stringify sd) dnl)
  (let ((fields (cddr sd)))
    ;; here we want to walk the fields, calling the type packer for
    ;; each field. (m3-make-pack-field)
    
    (map (curry m3-make-unpack-field class m3tgt m3src) (reverse fields))
    )
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; struct initialization details
;;

(define (m3-make-init-field pc m3tgt fd)
  (let* ((ty     (get-decl1-type fd))
         (aty    (array-base-type ty))
         (id     (get-decl1-id fd))
         (m3id   (m3-ident id))
         (iv     (get-decl1-init fd))
         (adims  (array-dims ty))
         )
          
    (define (m3init t)
      (cond
       ((struct-type? aty)
        (let* ((snm    (struct-type-name aty))
               (m3snm  (m3-struct snm))
               )
          (sa m3snm "_initialize(" t ")")
          );;tel*
        )
       
       ((null? iv) ;; iv is *always* null for arrays 
        (sa t ":= " (m3-default-init-value aty)))

       ;; below here, not an array, so aty = ty
       ((string-type? ty) (sa t ":= \"" iv "\""))
       
       ((boolean-type? ty)
        (sa t " := " (if iv "TRUE" "FALSE")))
       
       ((m3-natively-representable-type? ty)
        (sa t " := " (m3-native-literal iv)))
       
       ((integer-type? ty)
        (sa t " := Mpz.New(); "
            "Mpz.set(" t ", " (make-dynamic-constant! pc iv) ")"))
       
       (else (error "m3-make-init-field : can't initialize type : " ty dnl))
       );;dnoc
      );;enifed
    
  
  ;; If it is an array, we need to build the array calls
  ;; using the code from m3-initialize-array
  
  (m3-initialize-array
   m3init
   (sa m3tgt "." m3id)
   adims
   'init_field
   )
  );;*tel
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; struct assignment details
;;

(define (m3-make-assign-field pc m3tgt m3src fd)
  (dis "m3-make-assign-field : m3tgt : " m3tgt dnl)
  (dis "m3-make-assign-field : m3src : " m3src dnl)
  (dis "m3-make-assign-field : fd    : " fd dnl)
  (let* ((ty     (get-decl1-type fd))
         (aty    (array-base-type ty))
         (id     (get-decl1-id fd))
         (m3id   (m3-ident id))
         (iv     (get-decl1-init fd))
         (adims  (array-dims ty))
         )
    
    (define (m3ass t s)
      (cond
       ((struct-type? aty)
        
        (let* ((snm    (struct-type-name aty))
               (m3snm  (m3-struct snm))
               )
          (sa m3snm "_assign(" t " , " s ")")
          );;tel*
        )
       
       ((and
         (integer-type? aty)
         (not 
          (m3-natively-representable-type? aty)))
        
        (sa "Mpz.set(" t " , " s ")"))
       
       (else (sa t " := " s ))
       );;dnoc
      );;enifed
    
    ;; If it is an array, we need to build the array calls
    ;; using the code from m3-initialize-array
    
    (m3-initialize-array
     (lambda(txt)
       (m3ass (CitTextUtils.ReplacePrefix txt m3src m3tgt) txt))
     (sa m3src "." m3id)
     adims
     'assign_field
     )
    );;*tel
  )

(define (m3-default-init-value type)
  (cond ((string-type? type)  "\"\"")
        ((boolean-type? type) "FALSE")
        ((m3-natively-representable-type? type)
         "0")
        ((integer-type? type)
         "Mpz.NewInt(0)"
         )
        (else (error "m3-default-init-value : unknown type : " type))
        )
  )

(define (m3-make-init-body pc m3tgt sd)
  (set! *sd* sd)
  (dis "m3-make-init-body : sd : " (stringify sd) dnl)
  (let ((fields (cddr sd)))
    ;; here we want to walk the fields, calling the type packer for
    ;; each field. (m3-make-pack-field)
    
    (map (curry m3-make-init-field pc m3tgt) fields)
    )
  )

(define (m3-make-assign-body pc m3tgt m3src sd)
  (set! *sd* sd)
  (dis "m3-make-assign-body : sd : " (stringify sd) dnl)
  (let ((fields (cddr sd)))
    ;; here we want to walk the fields, calling the type packer for
    ;; each field. (m3-make-pack-field)
    
    (map (curry m3-make-assign-field pc m3tgt m3src) fields)
    )
  )


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; variable placement for the process
;;

(define (m3-frame-variables the-blocks the-decls cell-info)

  ;; the "frame variables" are the variables that need to be 
  ;; declared in the process frame.  They include:
  ;; (1) variables that are shared across blocks
  ;; (2) variables expensive to initialize : dynamic ints
  ;; (3) variables expensive to initialize : arrays

  (let* ((svars (get-shared-variables the-blocks cell-info))
         (dvars
          (map get-var1-id
               (filter
                (compose m3-dynamic-int-type? get-var1-type)
                the-decls)))
         (wvars
          (map get-var1-id
               (filter
                (compose m3-wide-int-type? get-var1-type)
                the-decls)))

         (avars
          (map get-var1-id
               (filter
                (compose array-type? get-var1-type)
                the-decls)))
         (tvars
          (map get-var1-id
               (filter
                (compose struct-type? get-var1-type)
                the-decls)))

          )
    (set-union svars dvars wvars avars tvars)
    )
  )

(define (m3-write-shared-locals w the-blocks cell-info the-decls)
  (let* ((shared-local-ids (m3-frame-variables the-blocks the-decls cell-info))
         (v1s              (map (curry find-decl the-decls) shared-local-ids))
         )
    (w "    (* shared locals list *)" dnl)
    (map (lambda(dt) (w "    " dt dnl))
         (map m3-convert-vardecl (filter identity v1s)))

    (w dnl
       "    (* dynamic scratchpad *)" dnl)
    (w "    " (pad 40 "a, b, c") " : DynamicInt.T;" dnl)
    );;*tel
  )

(define (m3-closure-type-text fork-count)

  ;; pass #f or the pair of (L<x> . <cnt>)
  (if fork-count
      (sa "ARRAY [ 0 .. ("(cdr fork-count)" - 1) ] OF Process.Closure" )
      "Closure")
  )

(define (m3-write-process-closure-list w the-blocks fork-counts)
  (w "    (* closures *)" dnl)

  (define (do-one-id lab-id)
    (dis "do-one-id : " lab-id dnl)
    (let* ((btag  (m3-ident lab-id))
           (count (assoc lab-id fork-counts))
           (type  (m3-closure-type-text count))
           )
      
      (w "    " (pad 40 btag "_Cl") " : "type";" dnl)
      );;*tel
    )
      
  (let ((the-ids
         (uniq eq? (map cadr (map get-block-label (cdr the-blocks))))))

    (map do-one-id the-ids)
    )
  )

(define (m3-write-process-fork-counters w fork-counts)
  (w "    (* fork counters *)" dnl)

  (map (lambda(fc)
         (let* ((cvar (m3-ident (symbol-append 'fork-counter- (car fc)))))
           (w "    " (pad 40 cvar) " : [ 0 .. " (cdr fc) " ];" dnl)
           );;*tel
         )
       fork-counts
       );;pam
  )

(define (m3-write-proc-public-frame-decl
         w port-tbl the-blocks cell-info the-decls fork-counts)
    
    (w dnl
       "TYPE" dnl)
    (w "  Frame <: PubFrame;" dnl
       dnl)
    (w "  PubFrame = Process.Frame OBJECT" dnl)
    (m3-write-port-list w cell-info)
    (w dnl)
    (w "  END;" dnl dnl)

  )

(define (m3-write-proc-private-frame-decl
         w port-tbl the-blocks cell-info the-decls fork-counts)
    
    (w dnl
       "REVEAL" dnl)
    (w "  Frame = PubFrame BRANDED Brand & \" Frame \" OBJECT" dnl)
    (m3-write-shared-locals w the-blocks cell-info the-decls)
    (w dnl)
    (m3-write-process-closure-list w the-blocks fork-counts)
    (w dnl)
    (m3-write-process-fork-counters w fork-counts)
    (w dnl)
    (w "  OVERRIDES" dnl)
    (w "    start := Start;" dnl)
    (w "  END;" dnl dnl)

  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (m3-write-block-decl w)
  (w dnl
     "TYPE Block = PROCEDURE (cl : Closure) : BOOLEAN;" dnl
     dnl)
  )

(define (get-all-labels the-blocks)
  (map cadr (filter identity (map (curry find-stmt 'label) the-blocks)))
  )

(define (get-fork-labels label-lst)
  (multi label-lst)
  )

(define (count-occurrences eq? lst of)
  (let loop ((p lst)
             (cnt 0))
    (cond ((null? p) cnt)
          ((eq? of (car p)) (loop (cdr p) (+ cnt 1)))
          (else             (loop (cdr p) cnt))
          )
    )
  )

(define (get-fork-label-counts the-blocks)
  (let* ((labels       (get-all-labels the-blocks))
         (fork-labels  (multi labels)))
    (map (lambda(m) (cons m
                          (count-occurrences eq? labels m)))
         fork-labels)))
  
(define (m3-write-closure-decl w)
  (w dnl
     "TYPE" dnl
     "  Closure = Process.Closure OBJECT" dnl
     "    frame  :  Frame;" dnl
     "    block  :  Block;" dnl
     "  OVERRIDES" dnl
     "    run := Run;" dnl
     "  END;" dnl
     dnl
     "PROCEDURE Run(cl : Closure) = BEGIN EVAL cl.block(cl) END Run;" dnl
     dnl
     )
  )

(define (m3-write-port-list w cell-info)
  (let ((plist (get-ports cell-info)))

    (w "    (* port list *)" dnl)
  
    (map (curry m3-write-port-decl w) plist) 
    )
  )

(define (m3-write-build-signature w cell-info)
  (w dnl
     "PROCEDURE Build( name : TEXT;" dnl)
  (m3-write-port-list w cell-info)
  (w ") : Frame ")
  )

(define (m3-write-start-signature w cell-info)
  (w dnl
     "PROCEDURE Start(frame : Frame)")
  )

(define (m3-write-build-decl w cell-info)
  (m3-write-build-signature w cell-info)
  (w ";" dnl dnl)
  )

(define (m3-write-start-decl w cell-info)
  (m3-write-start-signature w cell-info)
  (w ";" dnl dnl)
  )

(define (indent-writer w by) (lambda x (apply w (cons by x))))

(define (suffix-writer w by) (lambda x (apply w (append x (list by)))))

(define (m3-mark-reader-writer whch w pc id)
    ;;  (w "<*ASSERT " m3id ".reader = NIL*>" dnl)
  (let* ((cell-info (pc-cell-info pc))
         (port-tbl  (pc-port-tbl pc))
         (port-def  (port-tbl 'retrieve id))
         (m3id      (m3-ident id))
         (is-array  (array-port? port-def))
         )
    (define construct-operation
      (lambda(txt)
        (let ((res
               (case whch
                 ((writer)         (sa txt ".markWriter(frame)"))
                 ((reader)         (sa txt ".markReader(frame)"))
                 ((surrogate)
                  (sa txt " := CspChannel.CheckSurrogate("txt " , frame)"))
                 (else (error)))))
                  res)
        )
      )

    (if is-array
        (let ((dims (array-dims (get-port-channel port-def))))
          (dis "dims : " dims dnl)
          (dis "whch : " whch dnl)
          (w (m3-initialize-array
              construct-operation
              (sa "frame." m3id)
           dims
           'mark_rw
           ))
          )

        (w (construct-operation (sa "frame." m3id)) dnl)
        )

        (w     ";"       dnl)
        )
  )

(define (m3-mark-reader w pc id)
  (m3-mark-reader-writer 'reader w pc id))

(define (m3-mark-writer w pc id)
  (m3-mark-reader-writer 'writer w pc id))

(define (m3-check-surrogate w pc id)
  (m3-mark-reader-writer 'surrogate w pc id))
  

(define (get-port-channel pdef)
   (cadddr pdef))

(define (node-port? pdef)
  (or 
   (eq? 'node (car (get-port-channel pdef)))
   (and (array-port? pdef)
        (eq? 'node (car (array-channel-base (get-port-channel pdef)))))))

(define (array-channel-base cdef)
  (if (eq? 'array (car cdef))
      (array-channel-base (caddr cdef))
      cdef)
  )

(define (channel-port? pdef)
  (or 
   (eq? 'channel (car (get-port-channel pdef)))
   (and (array-port? pdef)
        (eq? 'channel (car (array-channel-base (get-port-channel pdef)))))))
  
(define (array-port? pdef)
  (eq? 'array (car (get-port-channel pdef))))

(define (m3-make-csp-channel cdef)
  (dis "m3-make-csp-channel : cdef : " cdef dnl)
  (cond ((eq? 'array (car cdef))
         (CspPort.NewArray
          (CspPort.NewRange (cadadr cdef) (caddadr cdef))
          (m3-make-csp-channel (caddr cdef))))

        ((eq? 'node (car cdef))
         (CspPort.NewScalar 'Node (caddr cdef) 'node))

        ((eq? 'channel (car cdef))
         (CspPort.NewScalar 'Channel (caaddr cdef) (cadr cdef)))

        (else (error "m3-make-csp-channel : " cdef)))
  )

(define td #f)

(define (m3-format-mpz-new arr-tbl id)
  (let* ((arrdef    (arr-tbl 'retrieve id))
         (arrdims   (if (eq? arrdef '*hash-table-search-failed*)
                        0
                        (array-dims arrdef))))
    
    (sa
     (m3-initialize-array
      (lambda(stuff) (sa stuff  " := Mpz.New()"))
      (sa "frame." (M3Ident.Escape (symbol->string id)))
      arrdims
      'mpz_new
      )
     ";" dnl
     )
    )
  )

(define (m3-write-start-defn w cell-info the-blocks pc)
  (m3-write-start-signature w cell-info)
  (w " = " dnl)
  (w "  BEGIN" dnl)

  ;;
  ;; here we need to insert CheckSurrogate for each Channel
  ;;

  (let* ((proc-ports (get-ports cell-info))
         (iw (indent-writer w "     "))
         (chanlist (filter channel-port? proc-ports))
         (ids      (map get-port-id chanlist)))
    (map (curry m3-check-surrogate iw pc) ids
         )
    (w dnl))
  
  (w "    Scheduler.Schedule(frame." (m3-ident (cadar the-blocks))"_Cl)" dnl)
  (w "  END Start;" dnl
     dnl
     )
  )
       
(define (m3-write-build-defn w
                             cell-info the-blocks the-decls fork-counts
                             arr-tbl
                             pc)
  (define *comma-indent* "                     ,")
  (let ((proc-ports (get-ports cell-info)))
    (m3-write-build-signature w cell-info)
    (w " = " dnl)
    (w "  BEGIN" dnl)
    (w "    WITH frame = NEW(Frame," dnl
       "                     typeName := Brand," dnl
       "                     name := name," dnl
       "                     id := Process.NextFrameId()" dnl)

    (let ((asslist (map m3-format-port-ass proc-ports)))
      (map (lambda(ass)
             (w *comma-indent* ass  dnl))
           asslist)
      );;tel

    (set! td the-decls)
    
    (let ((iw (indent-writer w *comma-indent*)))
      (iw "a := Mpz.New()" dnl)
      (iw "b := Mpz.New()" dnl)
      (iw "c := Mpz.New()" dnl)
      )
  
    (w "      ) DO" dnl
       dnl
       "frame.dummy := NEW(Closure, name := \"**DUMMY**\", frameId := frame.id, fr := frame);" dnl
       "CspSim.RegisterProcess(frame);" dnl
       dnl)

    (let*((dynamics (filter (compose m3-dynamic-int-type? get-var1-type)

                            the-decls))
          (wides (filter (compose m3-wide-int-type? get-var1-type)

                         the-decls))

          (mpzs (set-union dynamics wides))
          )

      ;; write in initialization of Mpz variables
      (dis "dynamics : " dynamics dnl)
      (dis "wides    : " wides dnl)
      (dis "mpzs     : " mpzs dnl)
      
      (map w
           (map (curry m3-format-mpz-new arr-tbl) (map get-var1-id mpzs)))
      );;tel

    ;; initialize structs
    (let* ((frame-vars (m3-frame-variables text9 *the-decls* *cellinfo*))
           (structs  (filter (compose (yrruc member frame-vars)
                                      get-var1-id)
                             (filter (compose struct-type?
                                              (compose array-base-type get-var1-type))
                                     the-decls))))
      (dis "frame-vars    : " frame-vars dnl)
      (dis "frame-structs : " structs dnl)
      (w "BEGIN" dnl)
      (map w (map m3-format-struct-init
                  (map get-var1-id structs)
                  (map get-var1-type structs)))
      (w " END;" dnl)
                  
      );;*tel

    ;; build body
    (let ((iw (indent-writer w "     ")))


      ;; mark channels as read and written by us
      
      (let* ((inlist (filter channel-port? (filter input-port? proc-ports)))
             (ids    (map get-port-id inlist))
             )
        (map (curry m3-mark-reader iw pc) ids)
        )
      (w dnl)
      
      (let* ((outlist (filter channel-port? (filter output-port? proc-ports)))
             (ids    (map get-port-id outlist))
             )
        (map (curry m3-mark-writer iw pc) ids)
        )

      (w dnl)

      (let* ((blk-labels 
              (uniq eq?
                    (map cadr
                         (map get-block-label (cdr the-blocks)))))
             (iiw (indent-writer iw (pad 22 "")))
             )
        (map
         (lambda(lab)
           (let ((m3lab (m3-ident lab))
                 (count (assoc lab fork-counts)))

             (if count

                 (begin ;; a fork
                   (iw  (pad 22 "frame." m3lab "_Cl")
                        " := " (m3-closure-type-text count) " { "dnl)
                   (count-execute
                    (cdr count)
                    (lambda(i)
                      (iw (pad 22 "") "   NEW(Closure," dnl)
                      (iiw "       name    := \"" lab "\"," dnl)
                      (iiw "       id      := Process.NextId()," dnl)
                      (iiw "       frameId := frame.id," dnl)
                      (iiw "       fr      := frame," dnl)
                      (iiw "       frame   := frame," dnl)
                      (iiw "       block   := Block_" m3lab "_" i "," dnl)
                      (iiw "       text    := Text_"  m3lab "_" i ")" dnl
                           (if (= i (- (cdr count) 1)) "" ",") ;; blah!
                           dnl)
                      
                      )
                    );;etucexe-tnuoc
                   (iw "};" dnl dnl)
                   (iw "CspSim.RegisterClosures(frame." m3lab "_Cl);" dnl
                       dnl)
                   );;nigeb
                 
                 (begin  ;; not a fork
                   (iw  (pad 22 "frame." m3lab "_Cl")
                        " := NEW(Closure," dnl)
                   (iiw "        name    := \"" lab "\"," dnl)
                   (iiw "        id      := Process.NextId()," dnl)
                   (iiw "        frameId := frame.id," dnl)
                   (iiw "        fr      := frame," dnl)
                   (iiw "        frame   := frame," dnl)
                   (iiw "        block   := Block_" m3lab "," dnl)
                   (iiw "        text    := Text_"  m3lab ");" dnl dnl)
                   (iw "CspSim.RegisterClosure(frame." m3lab "_Cl);" dnl
                       dnl)

                   );;nigeb
                 )
             )
           )
         blk-labels)
        );;*tel

      );;tel (iw)
    
    (w "      RETURN frame" dnl)
    (w "    END(*WITH*)" dnl)
    (w "  END Build;" dnl dnl)
    )
  )

(define (m3-write-imports w intfs)
  (dis "m3-write-imports : intfs : " intfs dnl)
  
  (w "<*NOWARN*>IMPORT CspCompiledProcess AS Process;" dnl)
  (w "<*NOWARN*>IMPORT CspCompiledScheduler1 AS Scheduler;" dnl)
  (w "<*NOWARN*>IMPORT CspSim;" dnl)
  (w "<*NOWARN*>IMPORT CspString, Fmt;" dnl)
  (w "<*NOWARN*>IMPORT CspBoolean;" dnl)
  (w "<*NOWARN*>IMPORT CspIntrinsics;" dnl)
  (w "<*NOWARN*>IMPORT CspDebug, Debug;" dnl)
  (w "<*NOWARN*>IMPORT NativeInt, DynamicInt;" dnl)
  (w "<*NOWARN*>IMPORT NativeInt AS NativeIntOps, DynamicInt AS DynamicIntOps;" dnl)
  (w "<*NOWARN*>IMPORT Word;" dnl)
  (w "<*NOWARN*>IMPORT Text;" dnl)
  (w "<*NOWARN*>IMPORT CspChannel;" dnl)
  (map (lambda(intf)(w "IMPORT " intf ";" dnl))
       (map format-intf-name intfs))
  )

(define *map-chantypes* ;; these are types generated by generics..
  '((UIntChan UInt Chan)
    (SIntChan SInt Chan)
    (UIntOps UInt Ops)
    (SIntOps SInt Ops))
  )

(define (format-intf-name intf-pair)
  (let* ((n  (car intf-pair))
         (w  (cdr intf-pair))
         (ws (number->string w))
         (m  (assoc n *map-chantypes*))
         )
    (if (eq? 'Node n)
        (sa "NodeUInt" (number->string w) " AS Node" ws)
        (if m
            (sa (format-intf-name (cons (cadr m) w))
                (symbol->string (caddr m)))
            (sa (symbol->string n) ws)
            )
        )
    )
  )

(define (m3-convert-port-type-array ptype)
  ;; return string name of interface that defines the channel type
  ;; requested by the CSP code

  (dis "m3-convert-port-type-array " ptype dnl)

  (if (array? ptype)
      (let ((extent (array-extent   ptype))
            (base   (array-elemtype ptype)))
        (m3-make-array-decl
         (m3-native-literal (cadr extent))
         (m3-native-literal (caddr extent))
         (m3-convert-port-type-array base)))
      "")
  )

(define (m3-convert-port-type-scalar ptype)
  ;; return string name of interface that defines the channel type
  ;; requested by the CSP code

  (dis "m3-convert-port-type-scalar " ptype dnl)

  (if (array? ptype)
      (m3-convert-port-type-scalar (caddr ptype))
      
      (let ((stype (port-type-short ptype)))
        (case (car stype)
          ((node) (string-append "Node" (number->string (cadr stype) 10)))
          ((bd)   (string-append "UInt" (number->string (cadr stype) 10) "Chan"))
          (else (error))
          )
        )
      )
  )

(define (m3-convert-port-type ptype)
  (sa (m3-convert-port-type-array ptype) (m3-convert-port-type-scalar ptype)))

(define cptbt #f)

(define (m3-convert-port-type-build ptype)
  (set! cptbt ptype)
  (dis "m3-convert-port-type-build : " ptype dnl)
  (if (array? ptype)
      (m3-convert-port-type-build (caddr ptype))
      (let ((stype (port-type-short ptype)))
        (case (car stype)
          ((node)  (cons 'Node ((cadr stype))))
          ((bd)    (cons 'UInt ((cadr stype))))
          (else (error))
          )
        )
      );;fi
  )

(define (m3-convert-port-ass-type ptype)
  ;; return string name of interface that defines the assignable data
  ;; on a port requested by the CSP code
  (dis "m3-convert-port-ass-type : " ptype dnl)
  (if (array? ptype)
      (m3-convert-port-ass-type (caddr ptype))

      (let ((stype (port-type-short ptype)))
        (case (car stype)
          ((node) (string-append "UInt" (number->string (cadr stype) 10)))
          ((bd)   (string-append "UInt" (number->string (cadr stype) 10)))
          (else (error))
          )
        )
      )
  )

(define (m3-convert-port-ass-bits ptype)
  (dis "m3-convert-port-ass-bits ptype " ptype dnl)
  (if (array? ptype)
      (m3-convert-port-ass-bits (caddr ptype))
      (let ((stype (port-type-short ptype)))
        (if (not (pair? stype))
            (error "m3-convert-port-ass-bits : bad type " ptype))
        (dis "m3-convert-port-ass-bits stype " stype dnl)
        ((cadr stype))))
  )

(define (m3-convert-port-ass-category ptype)
  (if (> (m3-convert-port-ass-bits ptype) *target-word-size*) 'wide 'native))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (declared-type pc expr)

  (dis "declared-type : expr " expr dnl)
  
  ;;
  ;; This is similar to derive-type in the front-end;
  ;; the difference is that derive-type actually ignores declared bit
  ;; widths, so that these can be inferred later.
  ;;
  ;; Here, we have already inferred the bit widths, so we need to pull
  ;; them out of our tables.
  ;; 
  
  (let ((symtab       (pc-symtab     pc))
        (cell-info    (pc-cell-info  pc))
        (struct-tbl   (pc-struct-tbl pc)))
    (if (not (designator? expr))
        (error "declared-type : not a designator : " expr))

    (let* ((declared-id (get-designator-id expr))
           (id-type     (symtab 'retrieve declared-id)))
      (cond ((array-access? expr)
             (let ((res
                    (peel-array (declared-type pc (array-accessee expr)))))
               (dis "declared-type array-access : res : " res dnl)
               res
               )
             )

            ((member-access? expr)
             (let* ((base-type (declared-type
                                pc (member-accessee expr) ))
                    (struct-def
                     (struct-tbl 'retrieve (get-struct-name base-type)))
                    
                    (struct-flds (get-struct-decl-fields struct-def))
                    (accesser   (member-accesser expr))
                    (res
                     (get-struct-decl-field-type struct-def accesser))
                    )
               (dis "declared-type member-access : res : " res dnl)
               res
               )
             )

            ((bits? expr) (error) )  ;; do we support LHS bits?  I forget...

            (else
             (dis "declared-type id-type : " id-type dnl)
             id-type)
            );;dnoc
         );;*let
    );;tel
  )

(define (m3-derive-type pc expr)
  (let ((symtab       (pc-symtab     pc))
        (cell-info    (pc-cell-info  pc))
        (struct-tbl   (pc-struct-tbl pc)))
    (derive-type expr (list symtab) '() struct-tbl cell-info)
    )
  )
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (m3-format-designator pc designator)
  ;; actually, we need to look up the designator to know
  ;; whether it is
  ;;
  ;; (1) a block local (which is just declared in a VAR in the block) or
  ;;
  ;; (2) a process local (shared across blocks) or
  ;;
  ;; (3) a parallel-loop dummy (which is accessed via a pointer from the block
  ;;     closure)
  ;;
  ;; (each of which has a different access method)

  (dis "m3-format-designator : " designator dnl)

  (cond ((ident? designator) (m3-format-varid pc (cadr designator)))

        ((array-access? designator)
         (sa (m3-format-designator pc (array-accessee designator))
             "[" (m3-compile-native-value pc (array-accessor designator)) "]"
             )
         )

        ;; need to add struct here

        ((member-access? designator)
         (sa (m3-format-designator pc (member-accessee designator))
             "."
             (m3-ident (member-accesser designator))))
        
        (else (error "m3-format-designator : not yet"))))

(define (m3-format-varid pc id)
  ;; given an id (as part of a designator) in Scheme,
  ;; generate a correctly formatted reference for it for the
  ;; compiled program, from within a block procedure

  (let ((the-scopes (pc-scopes pc)))
    (case (the-scopes 'retrieve id)
      ((*hash-table-search-failed*) (error "unknown id : " id))
      
      ((port)           (string-append "frame." (m3-ident id)))
      
      ((process)        (string-append "frame." (m3-ident id)))
      
      ((block)          (m3-ident id))
      
      ((parallel-dummy) ;; this is sketchy
       (string-append "cl." (m3-ident id)))
      
      (else (error))
      )
    )
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; integer types --
;;
;; these have a whole host of representations!
;;
;; narrow types are fundamentally INTEGERs (64 bits wide)
;; and the operations distinguish between Word.T and INTEGER.
;; This only really matters for integers exactly 64 bits wide.
;;
;; The present version of the compiler simplifies things a little bit
;; by representing unsigned 64-bit integers as wide integers, rather
;; than special-casing this specific type to be represented by an
;; INTEGER in memory (that's the way that the Word interface does it).
;;
;; So for native types, we have:
;;
;; narrow uint (0..63)
;; narrow sint (0..64)
;;
;; sint(64) is somewhat special, as it is just Modula-3's INTEGER type.
;; The other types are all represented as Modula-3 integer subranges.
;;
;; Wider integers than 64 bits are stored as dynamic integers, see below.
;; Assignments are range-checked and truncated as needed.
;;
;; wide uint (64..??)
;; wide sint (65..??)
;;
;; Finally, there are dynamic integers, which are stored as instances
;; of Mpz.T (GNU MP mpz_t C type wrapper).  These are not
;; range-checked or truncated when assigned, since they are specified
;; to grow without bound.
;;
;; dynamic int (0 .. +inf)
;;
;; The routines below classify the above types as either:
;;
;; 'native
;; 'wide
;; 'dynamic
;; 
;; Actual operations are the same between 'wide and 'dynamic ; what differs
;; is assginments with 'wide as lvalue.
;;
;; There's a further subtlety that's not fully captured by the
;; compiler: The widths of integers come from two sources: either an
;; integer variable is declared to be a specific width by the user, OR
;; the integer variable's width is inferred through interval arithmetic
;; (see interval.scm).  In the former case, it can happen that the compiled
;; code assigns a wider result to the narrow variable, and truncation is
;; to happen as per standard CSP rules (derived from C)---so masking is
;; part of the assignment operation.  But in the latter case, the width is
;; known in advance, and masking is not necessary---if masking is ever
;; necessary that is because of a bug in this compiler.  (So we could
;; use an assertion instead.)  I don't think we distinguish adequately
;; between the two cases, unfortunately.
;;

(define (m3-sint-type? t)
  (and (integer-type? t) (caddr t)))

(define (m3-uint-type? t)
  (and (integer-type? t) (not (caddr t)) (bigint? (cadddr t))))

(define (m3-dynamic-int-type? t)

  ;; this is really not quite right.  Anything wider than 63 bits
  ;; s.b. dynamic. (for the purposes this procedure is used.. need to
  ;; check on that)

  ;; also.. do the uses want the "stripped" type or the array type?
  
  (or
   (and (integer-type? t)
        ;;(not (caddr t))  ;; would be sint  ;; can have signed big ints from CAST
        (not (bigint? (cadddr t))))
   (and (array-type? t)
        (m3-dynamic-int-type? (array-elemtype t)))
   );;ro
  )

(define (m3-int-type-width t)
  (if (m3-dynamic-int-type? t) (error) ((cadddr t))))

(define (m3-natively-representable-type? t)
  ;; if a type is "narrow", we can do regular math on it

  ;; this means that the bit pattern matches the bit pattern of
  ;; a Modula-3 INTEGER, and that the operations do too

  ;; hmm there will be a very special case for operands that are
  ;; unsigned and exactly 64 bits wide.  Actually, we can represent
  ;; those as fixed wide integers, only exactly one word wide.
  ;; But for now, we don't do that!
  
  (and (integer-type? t)
       (not (m3-dynamic-int-type? t))
       (or (and (m3-sint-type? t)
                (<= (m3-int-type-width t) *target-word-size*))
           (and (m3-uint-type? t)
                (<= (m3-int-type-width t) (- *target-word-size* 1))))) ;; hmm.
  )

(define (m3-wide-int-type? t)
  (and (integer-type? t)
       (not (m3-dynamic-int-type?            t))
       (not (m3-natively-representable-type? t))
       );;dna
  )

(define (m3-compile-scalar-int-assign pc stmt)
  (dis "m3-compile-scalar-int-assign : " stmt dnl)
  (let* ((lhs (get-assign-lhs stmt))
         (lty (declared-type pc lhs))
         (rhs (get-assign-rhs stmt))
         )
    (dis "m3-compile-scalar-int-assign : lhs : " lhs dnl)
    (dis "m3-compile-scalar-int-assign : lty : " lty dnl)
    (dis "m3-compile-scalar-int-assign : rhs : " rhs dnl)

    (if (recv-expression? rhs) ;; special case
        (m3-compile-recv pc `(recv ,(cadr rhs) ,lhs))


        (cond ((m3-natively-representable-type? lty)
               (m3-compile-native-int-assign  pc stmt))
              
              ((m3-dynamic-int-type? lty)
               (m3-compile-dynamic-int-assign pc stmt))
              
              ((m3-wide-int-type? lty) ;; this may work because it re-checks type
               (m3-compile-dynamic-int-assign pc stmt))
              
              (else
               (error)))
        )
    )
  )

(define (operand-type pc expr)
  (if (literal? expr)
      (let ((lt (literal-type expr)))
        (if (integer-type? lt)
            (get-smallest-type (list expr expr))
            lt))
      (declared-type pc expr)))

(define (classify-expr-type pc expr)
  (let* ((ty (operand-type pc expr))
         (res (cond ((m3-natively-representable-type? ty) 'native)
                    ((m3-dynamic-int-type? ty)            'dynamic)
                    ((integer-type? ty)                   'wide)
                    (else (error "not an integer : " expr))
                    )
              )
         )
    (dis "classify-expr-type : " expr " -> " res dnl)
    res
    )
  )

(define (classify-operand-type pc ty)
  (let* (
         (res (cond ((m3-natively-representable-type? ty) 'native)
                    ((m3-dynamic-int-type? ty)            'dynamic)
                    ((integer-type? ty)                   'wide)
                    (else (error "not an integer : " expr))
                    )
              )
         )
    (dis "classify-operand-type : " ty " -> " res dnl)
    res
    )
  )

(define (max-type . x)
  (cond ((member 'dynamic x) 'dynamic)
        ((member 'wide    x) 'wide)
        (else (car x))))

(define (get-m3-int-intf t)
  (case t
    ((dynamic) "DynamicInt")
    ((wide)    "DynamicInt")
    ((native)  "NativeInt")
    (else (error "get-m3-int-intf : " t))
    )
  )

(define (m3-compile-convert-type from to m3scratch arg)
  (if (eq? from to)
      arg
      
      (sa (get-m3-int-intf to) ".Convert" (get-m3-int-intf from)
          "("
          (sa m3scratch ", ") 
          arg
          ")"
          )
      )
  )

(define (format-int-literal pc cat x)
  (case cat
    ((native)
     (Fmt.Int x 10))

    ((dynamic wide)
     (make-dynamic-constant! pc x))

    (else (error))
    )
  )

(define (m3-force-type pc cat m3scratch x)
  (if (literal? x)
      (format-int-literal pc cat x)
      (let ((x-category (classify-expr-type pc x)))
        (m3-compile-convert-type x-category
                                 cat
                                 m3scratch
                                 (m3-format-designator pc x)
                                 ))))

(define m3-binary-infix-ops '(+ / % * - 
                                )
  )

(define m3-binary-word-ops '(& ^ | ;;|
                               )
  )

(define (m3-map-word-op op)
  (case op
    ((&) "Word.And")
    ((|) "Word.Or") ;;|))
    ((^) "Word.Xor")
    )
  )
(define (m3-map-symbol-op op)
  (case op
    ((/) "DIV")
    ((%) "MOD")
    ((+) "+")
    ((*) "*")
    ((-) "-")
    )
  )

(define (m3-map-named-op op)
  (case op
    ((&)    "And")
    ((^)    "Xor")
    ((<<)   "Shl")
    ((**)   "Pow")
    ((|) ;; |)
            "Or")
    (else (error "m3-map-named-op : " op))
    );; esac
  )

(define (shift-op? op) (member op '(>> <<)))

(define m3-unary-ops '(-))

(define (m3-compile-native-binop cat builder op a-arg b-arg)
  (dis "m3-compile-native-binop : " cat " " op " " a-arg " " b-arg dnl)
  (cond ((and (eq? 'native cat) (member op m3-binary-infix-ops))
         (builder (sa "( " a-arg " " (m3-map-symbol-op op) " " b-arg " )")))
        
        ((and (eq? 'native cat) (eq? '>> op))
         (builder (sa "Word.Shift( " a-arg " , -( " b-arg " ) )")))

        ((and (eq? 'native cat) (eq? '<< op))
         (builder (sa "Word.Shift( " a-arg " , " b-arg " )")))

        ((and (eq? 'native cat) (member op m3-binary-word-ops))
         (builder (sa (m3-map-word-op op) "( " a-arg " , " b-arg " )")))
        
        (else (sa (m3-mpz-op op)
                  "( frame.c , "
                  a-arg " , " b-arg
                  " ); " (builder "Mpz.ToInteger(frame.c)") ))
        )
  )

(define (m3-compile-typed-binop pc builder op a b)
  ;; native only
  (dis "m3-compile-typed-binop : <- (" op " " a " " b ")" dnl)
  (let* ((op-type
          (max-type 'native
                    (classify-expr-type pc a)
                    (classify-expr-type pc b)))
         (opx
          (m3-compile-native-binop op-type
                                   builder
                                   op
                                   (m3-force-type pc op-type "frame.a" a)
                                   (m3-force-type pc op-type "frame.b" b))))
    opx
    )
  )

(define (m3-compile-native-unop cat builder op a-arg)
  (cond ((member op m3-unary-ops)
         (builder (sa "( " (m3-map-symbol-op op) " " a-arg " )")))
        (else (sa (m3-mpz-op op) "( frame.c , "
                   a-arg " ); " (builder "Mpz.ToInteger(frame.c)")))
        )
  )

(define (m3-compile-typed-unop pc builder op a)
  ;; native only
  (dis "m3-compile-typed-unop : <- (" op " " a ")" dnl)
  (let* ((op-type (max-type 'native (classify-expr-type pc a)))
         (opx     (m3-compile-native-unop op-type
                                          builder
                                          op
                                          (m3-force-type pc op-type "frame.a" a))))
    opx
    )
  )

(define (m3-compile-native-int-assign pc x)
  (dis "m3-compile-native-int-assign : x : " x dnl)
  ;; assign when lhs is native
  (let* ((lhs (get-assign-lhs x))
         (rhs (get-assign-rhs x))
    
         (ass-rng  (assignment-range (make-ass x) (pc-port-tbl pc)))

         (des      (get-designator-id lhs))
;;         (tgt-type ((pc-symtab pc) 'retrieve des))
         (tgt-type (declared-type pc lhs))
         (tgt-rng  (get-type-range tgt-type))
                  
         (in-range (range-contains? tgt-rng ass-rng))

         (comp-lhs 
          (sa (m3-format-designator pc lhs) " := "))

         (builder
          (lambda(rhs)
            (if in-range
                (sa comp-lhs rhs)
                (sa comp-lhs (m3-mask-native-assign tgt-type rhs))
                )))
         
         (result
          (cond ((or
                  (ident? rhs)
                  (member-access? rhs)
                  (array-access? rhs))
                 (builder (m3-force-type pc 'native "frame.a" rhs)))
        
                ((bigint? rhs)
                 (builder (number->string rhs 10)))
                
                ((binary-expr? rhs)
                 (m3-compile-typed-binop pc
                                         builder
                                         (car rhs)
                                         (cadr rhs)
                                         (caddr rhs)
                                         ))
                
                ((unary-expr? rhs)
                 (m3-compile-typed-unop pc
                                        builder
                                        (car rhs)
                                        (cadr rhs)))
                
                ((bits? rhs)
                 (builder (m3-compile-native-bits pc rhs)))
                
                (else (error "m3-compile-native-int-assign"))
                );;dnoc
          )
         )

    (dis "m3-compile-native-int-assign : x        : " x dnl)
    (dis "m3-compile-native-int-assign : ass-rng  : " ass-rng dnl)
    (dis "m3-compile-native-int-assign : in-range : " in-range dnl)
    (dis "m3-compile-native-int-assign : result   : " result dnl)
    
    result
    
    );;*tel
  )

(define (make-ass ass-stmt)
  (let* ((tgt     (get-designator-id (get-assign-lhs ass-stmt)))
         (an-ass  (car (*the-ass-tbl* 'retrieve tgt))))
    `(,ass-stmt ,(cadr an-ass) ,(caddr an-ass) ,(cadddr an-ass))))

(define dynamic-constant-count 0)

(define (make-dynamic-constant! pc bigint)
  (let ((nam
         (M3Ident.Escape (sa "constant"
                             (let ((id dynamic-constant-count))
                               (set! dynamic-constant-count
                                     (+ 1 dynamic-constant-count))
                               id)))))
    ((pc-constants pc) 'update-entry! nam bigint)
    nam
    )
  )

(define (m3-mpz-op op)
  (case op
    ;; binary ops:
    ((+)    "Mpz.add")
    ((-)    "Mpz.sub")
    ((*)    "Mpz.mul")
    ((/)    "DynamicInt.Quotient")
    ((%)    "DynamicInt.Remainder")
    ((&)    "Mpz.and")
    ((|)    "Mpz.ior") ;|))
    ((^)    "Mpz.xor")
    ((**)   "Mpz.pow")
    ((<<)   "Mpz.ShiftMpz")
    ((>>)   "Mpz.ShiftNegMpz")

    ;; unary ops: 
    ((uneg) "Mpz.neg")
    ((~)    "Mpz.com")
    (else (error))
    )
  )

(define (test-mpz op a b)
  (let ((ma (Mpz.New))
        (mb (Mpz.New))
        (mc (Mpz.New))
        (mpz-op (eval (string->symbol (m3-mpz-op op)))))
    
    (Mpz.init_set_si ma a)
    (Mpz.init_set_si mb b)

    (mpz-op mc ma mb)
    (Mpz.Format mc 'Decimal)
    )
  )

(define (dynamic-type-expr? pc expr)
  (eq? 'dynamic (classify-expr-type pc expr)))

;; wide expressions are represented as dynamic but have a specific bit width
(define (wide-type-expr? pc expr) 
  (eq? 'wide (classify-expr-type pc expr)))

(define (native-type-expr? pc expr)
  (eq? 'native (classify-expr-type pc expr)))

(define (m3-set-dynamic-value pc m3id expr)
  (cond ((bigint? expr)
         (sa "Mpz.set(" m3id ", " (make-dynamic-constant! pc expr) ")"))

        ((and (ident? expr) (dynamic-type-expr? pc expr)) #f)

        ((and (ident? expr) (wide-type-expr? pc expr)) #f)

        ((and (ident? expr) (native-type-expr? pc expr))
         (sa "Mpz.set_si(" m3id ", " (m3-format-designator pc expr) ")")
         )

        (else (error "can't set dynamic value : " m3id " <- " expr))
        )
  )

(define (m3-compile-dynamic-binop lhs pc mpz-op a b)
  (let* ((a-stmt (m3-set-dynamic-value pc "frame.a" a))
         (b-stmt (m3-set-dynamic-value pc "frame.b" b))
         (res
          (sa (if a-stmt (sa a-stmt "; ") "")
              (if b-stmt (sa b-stmt "; ") "")
              mpz-op
              "("
              lhs
              " , "
              (if a-stmt "frame.a" (m3-format-designator pc a))
              " , "
              (if b-stmt "frame.b" (m3-format-designator pc b))
              ")"
              ))
         )

    (dis "m3-compile-dynamic-binop : " res dnl)
;;    (error)
    
    res
    )      
  )

(define (m3-compile-dynamic-unop lhs pc mpz-op a)
  (let* ((a-stmt (m3-set-dynamic-value pc "frame.a" a))
         (res
          (sa (if a-stmt (sa a-stmt "; ") "")
              mpz-op
              "("
              lhs
              " , "
              (if a-stmt "frame.a" (m3-format-designator pc a))
              ")"
              ))
         )

    (dis "m3-compile-dynamic-unop : " res dnl)
;;    (error)
    
    res
    )      
  )

(define (m3-compile-dynamic-int-assign pc x)
  (dis "m3-compile-dynamic-int-assign : x : " x dnl)
  (let* ((lhs      (get-assign-lhs x))
         (rhs      (get-assign-rhs x))
         (comp-lhs (m3-format-designator pc lhs))
         (ass-rng  (assignment-range (make-ass x) (pc-port-tbl pc)))

         (des      (get-designator-id lhs))
;;         (tgt-type ((pc-symtab pc) 'retrieve des))
         (tgt-type (declared-type pc lhs))
         (tgt-rng  (get-type-range tgt-type))
         (m3-type  (m3-map-decltype tgt-type))

         (code     (cond
                    ((bigint? rhs)
                     (sa "Mpz.set(" comp-lhs ", " (make-dynamic-constant! pc rhs) ")")
                     )
                    
                    ((or (ident? rhs)
                         (member-access? rhs)
                         (array-access? rhs))
                     (sa "Mpz.set(" comp-lhs ", " (m3-force-type pc 'dynamic "frame.a" rhs) ")")
                     )
                    
                    ((binary-expr? rhs)
                     (m3-compile-dynamic-binop
                      comp-lhs pc (m3-mpz-op (car rhs)) (cadr rhs) (caddr rhs))
                     )
                    
                    ((unary-expr? rhs)
                     (let* ((op     (car rhs))
                            (map-op (if (eq? '- op) 'uneg op))
                            (m3-op  (m3-mpz-op map-op))
                            )
                       (m3-compile-dynamic-unop comp-lhs pc m3-op (cadr rhs))
                       );;*tel
                     )
     
                    (else (error "m3-compile-dynamic-int-assign : dunno RHS object : " rhs))
                    );;dnoc
                   )
                  
         (in-range (range-contains? tgt-rng ass-rng))

         ;; here we can add a call to push the result in range if it is wide
         ;; but not fully dynamic
         )

    (let ((final-result
           (if in-range
               code
               
               (sa "BEGIN" dnl
                   code ";" dnl
                   
                   m3-type ".ForceRange(" comp-lhs " , " comp-lhs ")" dnl
                   "END" dnl)
               )
           ))

      (dis "m3-compile-dynamic-int-assign : x        : " x dnl)
      (dis "m3-compile-dynamic-int-assign : in-range : " in-range dnl)
      (dis "m3-compile-dynamic-int-assign : final    : " final-result dnl)

      final-result
      )
    )
 )

(define (m3-initialize-array format-init name dimsarg dummy)
  ;;
  ;; name is the text name in m3 format
  ;; dims is the number of dimensions
  ;; dummy is the (symbol) prefix of the dummy
  ;; format-init takes one parameter, the name of the object to initialize
  ;;
  (let* ((dims (abs dimsarg))
         (dir  (if (= dims dimsarg) -1 1)))

    (let loop ((i 0)
               (what name)
               (index "")
               (indent "")
               (prefix "")
               (suffix "")
               )
      (cond ((= i dims) (sa prefix indent (format-init (sa name index)) suffix))
            
            (else
             (let ((frst (sa "FIRST(" what ")")))
               (loop
                (+ i 1)
                (sa what "[" frst "]")
                (sa index "[" (symbol->string dummy) i "]")
                (sa indent "  ")
                (sa prefix 
                    indent "FOR "(symbol->string dummy) i
                    (if (= dir 1)
                        (sa " :=  FIRST(" what ") TO LAST(" what ") DO"
                            dnl)
                        (sa " :=  LAST(" what ") TO FIRST(" what ") BY -1 DO"
                            dnl))
                    )
                (sa dnl indent "END"
                    suffix))
               );;tel
             );;esle
            );;dnoc
      );;tel
    );;tel
  )

(define (m3-compile-stringify-integer-value pc x)
  (if (bigint? x) ;; are the quotes right here?
      (sa "\"" (number->string x 10) "\"") 
  
      (let ((type (declared-type pc x)))
        (cond
         
         ((m3-natively-representable-type? type)
          (string-append
           "NativeInt.Format("
           (m3-compile-integer-value pc x)
           ", base := 10)"
           ))
         
         ((m3-dynamic-int-type? type)
          (string-append
           "DynamicInt.Format("
           (m3-compile-integer-value pc x)
           ", base := Mpz.FormatBase.Decimal)"
           ))
         
         (else
          (string-append
           "DynamicInt.Format("
           (m3-compile-integer-value pc x)
           ", base := Mpz.FormatBase.Decimal)"
           ))
         )
        )
      )
  )

(define (m3-compile-integer-value pc x)
  (define (err) (error "m3-compile-integer-value : can't map to integer : " x))
  
  (cond ((ident? x)  
         (let ((type (declared-type pc x)))
           (cond
            ((integer-type?  type)
             (m3-format-varid pc (cadr x)))

            (else (err))
            )
           )
         )

        (else (err))
        );;dnoc
  )

(define (+? x) (and (pair? x) (eq? '+ (car x))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; strings
;;

(define (m3-compile-string-expr pc x)
  (define (err) (error "m3-compile-string-expr : can't map to string : " x))
  
  (cond ((ident? x)  
         (let ((type (declared-type pc x)))
           (cond
            ((integer-type?  type)
             (m3-compile-stringify-integer-value pc x))

            ((string-type? type)
             (m3-format-varid pc (cadr x)))

            ((boolean-type? type)
             (sa "NativeInt.Format(CspBoolean.ToInteger("
                 (m3-format-varid pc (cadr x))
                 ") )"
                 )
             )

            (else (err))
            )
           )
         )

        ((or (array-access? x)
             (member-access? x))
         (m3-format-designator pc x))

        ((string? x) (stringify x))
        
        ((+? x)      (string-append
                      "CspString.Cat( "
                      (m3-compile-string-expr pc (cadr x))
                      " , "
                      (m3-compile-string-expr pc (caddr x))
                      " )"))

        ((bigint? x)
;;         (error) ;; shouldnt happen...
         (sa "\"" (number->string x 10) "\""))
        
        (else (err))
        );;dnoc
  )

(define (boolean-value? pc x)
  (cond ((boolean? x) #t)
        ((literal? x) #f)
        ((boolean-type? (declared-type pc x)))
        (else #f)))

(define (string-value? pc x)
  (cond ((string? x) #t)
        ((literal? x) #f)
        ((string-type? (declared-type pc x)))
        (else #f)))

(define (integer-value? pc x)
  (cond ((bigint? x) #t)
        ((literal? x) #f)
        ((integer-type? (declared-type pc x)))
        (else #f)))

(define (m3-compile-value pc int-class x)
  (dis "m3-compile-value " int-class " x : " (stringify x) dnl)
  (cond ((string? x) (stringify x))

        ((and (bigint? x) (eq? int-class 'native))
         (m3-format-literal x 16))

        ((and (bigint? x) (eq? int-class 'dynamic))
         (make-dynamic-constant! pc x))

        ((and (boolean? x) x)        "TRUE")

        ((and (boolean? x) (not x)) "FALSE")

        ((designator? x) (m3-format-designator pc x))

        (else (error "cannot compile value : " x))
        )
  )

(define (m3-compile-native-value pc x)
  ;; compile "x", an integer value, to something with native type
  (cond ((bigint? x)
         (m3-format-literal x 16))

        ((native-integer-value? pc x)
         (m3-format-designator pc x))

        ((dynamic-integer-value? pc x)
         (sa "Mpz.ToInteger(" (m3-format-designator pc x) ")" ))

        (else (error ("m3-compile-native-value : " x dnl)))
        );;dnoc
  )

(define (native-integer-value? pc x)
  (and (integer-value? pc x)
       (eq? 'native (classify-expr-type pc x))))

(define (dynamic-integer-value? pc x)
  (and (integer-value? pc x)
       (not (native-integer-value? pc x))))

(define (m3-compile-equals pc m3-lhs a b)
  ;; this is special, as operands can be boolean or integer

  (let* ((do-int (integer-value? pc a)))
    (cond (do-int ;; integer comparison
           (m3-compile-comparison pc m3-lhs "=" a b)
           
           );;tni-od
          
          (else   ;; not integer comparison, so boolean comparison

           (sa m3-lhs
               "( " (m3-compile-value pc 'x a)
               " = " (m3-compile-value pc 'x b)  " )" )
           );;esle
          );;dnoc
    );;*tel
  )

(define (m3-compile-comparison pc m3-lhs m3-cmp a b)
  ;; where cmp is one of '> '< '= '>= '<=

  (cond ((forall (curry native-integer-value? pc) (list a b))
         ;; native int comparison
         (sa m3-lhs
             "( "  (m3-compile-value pc 'native a)
             " " m3-cmp " "
             (m3-compile-value pc 'native b) " )")
         )
        
        (else ;; do it dynamic
         
         (let* ((a-stmt (m3-set-dynamic-value pc "frame.a" a))
                
                (b-stmt (m3-set-dynamic-value pc "frame.b" b))
                
                (res
                 (sa (if a-stmt (sa a-stmt "; ") "")
                     (if b-stmt (sa b-stmt "; ") "")
                     m3-lhs
                     "(Mpz.cmp("
                     (if a-stmt "frame.a" (m3-format-designator pc a))
                     " , "
                     (if b-stmt "frame.b" (m3-format-designator pc b))
                     ") " m3-cmp "  0)"
                     ));;ser
                )
           res);;*tel
         );;esle
        );; dnoc
  )

(define (m3-compile-boolean-numeric-binop pc m3-lhs op a b)
  (let ((m3-cmp (caddr (assoc op *boolean-numeric-binops*))))
    (m3-compile-comparison pc m3-lhs m3-cmp a b)
    )
  )

(define (m3-compile-boolean-logical-binop pc m3-lhs op a b)
  (let ((av    (m3-compile-value pc 'x a))
        (bv    (m3-compile-value pc 'x b))
        (m3-op (caddr (assoc op *boolean-logical-binops*))))
    (sa m3-lhs "( (" av ") " m3-op " (" bv ") )")
    );;tel
  )

(define *boolean-binop-map*
  '(
    (!= numeric "#" )
    (<  numeric "<" )
    (>  numeric ">" )
    (>= numeric ">=")
    (<= numeric "<=")
    (&  logical "AND")
    (|  logical "OR") ;;|)
    (&& logical "AND")
    (|| logical "OR") ;;|)
    (^  logical "#")
    )
  )
  
(define *boolean-numeric-binops*
  (filter (compose (curry eq? 'numeric) cadr) *boolean-binop-map*)
  )

(define *boolean-logical-binops*
  (filter (compose (curry eq? 'logical) cadr) *boolean-binop-map*)
  )

;; note that CSP (oddly) does not allow != between booleans.

(define (m3-compile-boolean-assign pc lhs rhs)
  (dis "m3-compile-boolean-assign : lhs : " lhs dnl)
  (dis "m3-compile-boolean-assign : rhs : " rhs dnl)
  (let ((m3-lhs (sa (m3-format-designator pc lhs) " := ")))
    (cond ((boolean? rhs)
           (sa m3-lhs (if rhs "TRUE" "FALSE")))

          ((bigint? rhs)
           (sa m3-lhs (if (big= rhs *big0*) "FALSE" "TRUE")))
          
          ((or (ident? rhs) ;; should cover arrays and structs, too
               (array-access? rhs)
               (member-access? rhs))
           (sa m3-lhs (m3-format-designator pc rhs)))
          
          ((and (pair? rhs) (eq? (car rhs) 'not))
           (sa m3-lhs "(NOT ( " (m3-compile-value pc 'x (cadr rhs)) " ) )"))
          
          ((and (pair? rhs) (eq? (car rhs) '==))
           (m3-compile-equals pc m3-lhs (cadr rhs) (caddr rhs)))
          
          ((and (pair? rhs)
                (= 3 (length rhs))
                (member (car rhs) (map car *boolean-numeric-binops*)))
           (m3-compile-boolean-numeric-binop pc m3-lhs
                                             (car rhs) (cadr rhs) (caddr rhs)))
          
          ((and (pair? rhs)
                (= 3 (length rhs))
                (member (car rhs) (map car *boolean-logical-binops*)))
           (m3-compile-boolean-logical-binop pc m3-lhs
                                             (car rhs) (cadr rhs) (caddr rhs)))


          ((probe? rhs)
           (let* (
                  (port-des     (get-probe-port rhs)) ;; doesnt work for arrays/structs

         
                  (port-tbl     (pc-port-tbl pc))
                  (port-id      (get-designator-id port-des))
                  (port-def     (port-tbl 'retrieve port-id))
                  (port-dir     (get-port-def-dir port-def))

                  (m3probe-side (case port-dir
                                  ((in) "RecvProbe")
                                  ((out) "SendProbe")
                                  (else (error port-dir))))
                  
                  (port-type    (get-port-def-type port-def))
                  (port-typenam (m3-convert-port-type-scalar port-type))
                  
                  (m3-pname     (m3-format-designator pc port-des))
                  )

             (dis "port-id  : " port-id dnl)
             (dis "port-def : " port-def dnl)

             (sa m3-lhs port-typenam "." m3probe-side "(" m3-pname " , cl)")
             );;*tel             
           )
          
          (else (error "m3-compile-boolean-assign : don't understand " rhs))
        );;dnoc
    );;tel
  )

(define *rhs* #f)
(define *lhs* #f)
(define *lty* #f)

(define (m3-compile-pack-assign pc lhs lty rhs)
  (set! *rhs* rhs)
  (set! *lhs* lhs)
  (set! *lty* lty)
  (dis "m3-compile-pack-assign " lhs " := " rhs dnl)
  (let*((class (classify-expr-type pc lhs))
        (s     (caddr rhs))
        (sty   (declared-type pc s))
        (snm   (struct-type-name sty))
        (m3snm (m3-struct snm))
        (m3lhs (m3-format-designator pc lhs))
        (m3rhs (m3-format-designator pc s))
        (zero-stmt
         (if (eq? 'native class)
             (sa m3lhs " := 0")
             (sa "Mpz.set_ui(" m3lhs ",0)")
             )
         )

        (scratch ;; Mpz scratchpad
         (if (eq? 'native class) "" "frame.a, ")
         )
        
        (res
         (sa 
          zero-stmt ";" dnl
          "      " m3lhs
          " := "
          m3snm "_pack_" (symbol->string class) "("
          m3lhs ", "
          scratch
          m3rhs
          ")"
          )
         )
        )

    (dis "m3-compile-pack-assign : res : " res dnl)
    res
;;    (error)
    )  
  )

(define (m3-compile-random-assign pc lhs lty rhs)
  (set! *rhs* rhs)
  (set! *lhs* lhs)
  (set! *lty* lty)
  (dis "m3-compile-random-assign " lhs " := " rhs dnl)
  (let*((lclass (classify-expr-type pc lhs))
        (b      (caddr rhs)) ;; # of bits requested
        (bclass (classify-expr-type pc b))
        (m3lhs  (m3-format-designator pc lhs))
        (m3lhs1 (if (eq? 'native lclass)
                    ""
                    (sa m3lhs ", ")))
                
        (m3b    (m3-force-type pc 'native "frame.a" b))

        
        (res
         (sa 
          "      " m3lhs
          " := "
          "CspIntrinsics.random_" (symbol->string lclass) "("
          m3lhs1 
          m3b
          ")"
          )
         )
        )

    (dis "m3-compile-random-assign : res : " res dnl)
    res
;;    (error)
    )  
  )

(define (m3-compile-readHexInts-assign pc lhs lty rhs)
  ;; rhs = (call-intrinsic readHexInts path maxN array)
  ;; lhs = count variable
  (dis "m3-compile-readHexInts-assign " lhs " := " rhs dnl)
  (let* ((path-expr (caddr rhs))
         (maxN-expr (cadddr rhs))
         (arr-expr  (car (cddddr rhs)))
         (m3-path   (if (string? path-expr)
                        (CitTextUtils.MakeM3Literal path-expr)
                        (m3-format-designator pc path-expr)))
         (m3-maxN   (m3-compile-value pc 'native maxN-expr))
         (m3-arr    (m3-format-designator pc arr-expr))
         (m3-lhs    (m3-format-designator pc lhs))
         ;; Determine element type of the array
         (arr-type  (declared-type pc arr-expr))
         (elem-type (if (array-type? arr-type) (caddr arr-type) arr-type))
         (elem-dyn  (m3-dynamic-int-type? elem-type))
         (lhs-dyn   (m3-dynamic-int-type? lty))
         ;; Generate appropriate assignment forms
         (copy-stmt (if elem-dyn
                        (sa "    Mpz.set_si(" m3-arr "[i_], hexArr_^[i_]);")
                        (sa "    " m3-arr "[i_] := hexArr_^[i_];")))
         (cnt-stmt  (if lhs-dyn
                        (sa "  Mpz.set_si(" m3-lhs ", NUMBER(hexArr_^));")
                        (sa "  " m3-lhs " := NUMBER(hexArr_^);"))))
    (sa "WITH hexArr_ = CspIntrinsics.readHexInts(frame, "
        m3-path ", " m3-maxN ") DO" dnl
        "  FOR i_ := 0 TO LAST(hexArr_^) DO" dnl
        copy-stmt dnl
        "  END;" dnl
        cnt-stmt dnl
        "END" dnl)))

(define (m3-compile-intrinsic-assign pc lhs lty rhs)
  (cond ((eq? 'pack (cadr rhs))
         (m3-compile-pack-assign pc lhs lty rhs))

        ((eq? 'random (cadr rhs))
         (m3-compile-random-assign pc lhs lty rhs))

        ((eq? 'readHexInts (cadr rhs))
         (m3-compile-readHexInts-assign pc lhs lty rhs))

        ((integer-type? lty)
         ;; if not pack or random we assume it returns a native int
         ;;
         ;; if LHS is integer, we need to ensure we can type-convert return
         ;; value
         
         (sa "WITH retval = " (m3-compile-intrinsic pc rhs) " DO" dnl
             
            (cond ((m3-dynamic-int-type? lty)
                   (sa
                    "  Mpz.set_ui(" (m3-format-designator pc lhs) " , retval)")
                   )
                  
                  ((native-type-expr? pc lhs)
                   
                   (sa "  " (m3-format-designator pc lhs) " := retval")
                   )
                  
                  (else (error "m3-compile-intrinsic-assign : don't know type " lty))
                  )
            dnl
            "END" dnl)
         )

        (else
         ;; not an integer, a simple assignment will do
         (sa (m3-format-designator pc lhs) " := "
             (m3-compile-intrinsic pc rhs)))
      );;dnoc
  )

(define (m3-compile-array-assign pc lhs rhs)
  (dis "m3-compile-array-assign " lhs " := " rhs dnl)
  (let* ((lty     (declared-type pc lhs))
         (lhs-des (m3-format-designator pc lhs))
         (rty     (declared-type pc rhs))
         (rhs-des (m3-format-designator pc rhs))
         (adims   (array-dims lty))
         )

    (dis "m3-compile-array-assign {" lty "} := {" rty "}" dnl)
    (dis "m3-compile-array-assign \"" lhs-des "\" := \"" rhs-des "\"" dnl)
    (dis "m3-compile-array-assign adims " adims dnl)
    (m3-initialize-array
     (lambda(txt)
       (m3-element-assignment lty rty
                             (CitTextUtils.ReplacePrefix txt rhs-des lhs-des)
                             txt)
       )
     rhs-des
     adims
     'array_assign
     )
    )
  )

(define (m3-element-assignment lty rty lhs-txt rhs-txt)
  (define (simple)
    (sa lhs-txt " := " rhs-txt)
    )

  (cond ((boolean-type? lty) (simple))
        ((string-type? lty) (simple))
        ((m3-natively-representable-type? lty) (simple))
        ((m3-dynamic-int-type? lty)
         (sa "Mpz.set( " lhs-txt " , " rhs-txt ")")
         )

        ((struct-type? lty)
         (let* ((snm    (struct-type-name lty))
                (m3snm  (m3-struct snm))
               )
          (sa m3snm "_assign(" lhs-txt " , " rhs-txt ")")
          );;tel*
         )
        
         (else (error "can't assign to array element " lhs-txt " of type " lty))
        )
  )

(define (m3-compile-assign pc stmt)
  (dis "m3-compile-assign : " (stringify stmt) dnl)
  (let* ((lhs (get-assign-lhs stmt))
         (lty (declared-type pc lhs))
         (rhs (get-assign-rhs stmt)))

    (dis "m3-compile-assign : lhs : " lhs dnl)
    (dis "m3-compile-assign : lty : " lty dnl)
    (dis "m3-compile-assign : rhs : " (stringify rhs) dnl)

    (cond ((call-intrinsic? rhs)
           (m3-compile-intrinsic-assign pc lhs lty rhs))
          
          ((boolean-type? lty)
           ;; value type, this is OK
           (m3-compile-boolean-assign pc lhs rhs))

          ((string-type? lty)
           ;; strings are immutable, so this is OK
           (sa (m3-format-designator pc lhs) " := "
               (m3-compile-string-expr pc rhs))
           )

          ((array-type? lty)
           (m3-compile-array-assign pc lhs rhs))

          ((struct-type? lty)
           (let* ((snm    (struct-type-name lty))
                  (m3snm  (m3-struct snm))
                  )
             (sa m3snm "_assign("
                 (m3-format-designator pc lhs)
                 " , "
                 (m3-format-designator pc rhs)
                 ")")        
                 )
           )
          
          ((integer-type? lty)
           (m3-compile-scalar-int-assign pc stmt))

          (else
           (error "???")))
    )
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; goto 
;; 

(define (m3-compile-goto pc stmt)
  (dis "m3-compile-goto" dnl)

  (let* ((is-fork (and (not (null? (cddr stmt)))
                       (eq? 'fork (caddr stmt))))
         (is-join (and (not (null? (cddr stmt)))
                       (eq? 'join (caddr stmt))))
         )

    (cond (is-fork (m3-compile-fork-goto  pc stmt))
          (is-join (m3-compile-join-goto  pc stmt))
          (else    (m3-compile-plain-goto pc stmt))
          )
    )
  )

(define  (m3-compile-plain-goto pc stmt)
    (string-append "Scheduler.Release (cl.frame." (m3-ident (cadr stmt)) "_Cl);"
                   " RETURN TRUE")
    )

(define  (m3-compile-fork-goto pc stmt)
  (let* ((fork-counter (sa "frame."
                           (m3-ident (symbol-append 'fork-counter-
                                                    (cadr stmt)))))
         (counter-lhs  (sa "<*ASSERT " fork-counter " = 0*> "
                           fork-counter " := "))
         )
    (string-append "BEGIN "  counter-lhs

                   "Scheduler.ReleaseFork(frame."
                   (m3-ident (cadr stmt)) "_Cl);"
                   " RETURN TRUE END")
    )
  )

(define  (m3-compile-join-goto pc stmt)
  (let* ((fork-counter (sa "frame."
                           (m3-ident (symbol-append 'fork-counter-
                                                    (cadddr stmt)))))
         (counter-lhs  (sa "<*ASSERT " fork-counter " # 0*> "
                           "DEC(" fork-counter ")"))
         )
    (string-append counter-lhs ";" dnl
                   "IF " fork-counter " = 0 THEN " dnl
                   "Scheduler.Release(cl.frame."
                   (m3-ident (cadr stmt)) "_Cl) " dnl
                   " END;" dnl
                   " RETURN TRUE")
    )
  )

(define (get-port-def-type pdef) (cadddr pdef))
(define (get-port-def-dir pdef) (caddr pdef))

(define *ss-rhs* #f)

(define (m3-compile-send pc stmt)
  (let* ((port-tbl     (pc-port-tbl pc))

         (port-des     (get-send-lhs stmt)) ;; doesnt work for arrays/structs
         (rhs          (get-send-rhs stmt))
         (port-id      (get-designator-id port-des))
         (port-def     (port-tbl 'retrieve port-id))
         (port-type    (get-port-def-type port-def))
         (port-typenam (m3-convert-port-type-scalar port-type))
         (copy-type    (m3-convert-port-ass-type port-type))
         (send-class   (classify-expr-type pc (get-send-rhs stmt)))
         
         (m3-pname     (m3-format-designator pc port-des))
         (port-class   (m3-convert-port-ass-category port-type))

         (literal      (literal? (get-send-rhs stmt)))
         )

    (set! *ss-rhs* rhs)
    
    (if literal
        (sa "IF NOT " port-typenam
            (let* ((ty    (operand-type pc rhs))
                   (int   (integer-type? ty))
                   (class (if int (classify-operand-type pc ty) #f)))
              (cond ((eq? class 'native)
                     (sa ".SendNative( " m3-pname ", "
                         (m3-compile-value pc 'native rhs)))
                    
                    ((eq? class 'dynamic)
                     (sa ".SendDynamic( " m3-pname ", "
                         (m3-compile-value pc 'native rhs)))
                    
                    ((boolean? rhs)
                     (sa ".SendBoolean( " m3-pname ", "
                         (m3-compile-value pc 'x rhs)))
                    
                    (else (error "can't send on channel: literal " rhs dnl))
                    );;dnoc
              );;*tel
            " , cl) THEN RETURN FALSE END"
            )
        
        (let* ((rhs-type     (declared-type pc rhs))
               (m3-rhs-type  (m3-map-decltype rhs-type)))
          (sa "VAR toSend : " 
              port-typenam ".Item; BEGIN" dnl
              m3-rhs-type "Ops.ToWordArray(" (m3-format-designator pc rhs) " , "
              "toSend);" dnl
              "IF NOT " port-typenam ".Send( " m3-pname " , toSend , cl ) THEN RETURN FALSE END" dnl
              "END"
              );;as
          );;tel
        );;fi
    );;*tel
  )

(define *rs* #f)

(define (m3-compile-recv pc stmt)
  (dis "m3-compile-recv : " stmt dnl)
  (set! *rs* stmt)
  (let* (
         (port-des     (get-recv-lhs stmt)) ;; doesnt work for arrays/structs
         (rhs          (get-recv-rhs stmt))
         
         (port-tbl     (pc-port-tbl pc))
         (port-id      (get-designator-id port-des))
         (port-def     (port-tbl 'retrieve port-id))
         (port-type    (get-port-def-type port-def))
         (port-typenam (m3-convert-port-type-scalar port-type))
         (copy-type    (m3-convert-port-ass-type port-type))
         
         (m3-pname     (m3-format-designator pc port-des))
         (port-class   (m3-convert-port-ass-category port-type))
         )
    (define (null-rhs)
      (sa "VAR toRecv : "
          port-typenam".Item; BEGIN " dnl
          "IF NOT "
          port-typenam ".Recv( " m3-pname " , toRecv , cl ) THEN RETURN FALSE END" dnl
          "END")
      )

    (define (nonnull-rhs)
      (let* ((rhs-type     (declared-type pc rhs))
             (m3-rhs-type  (m3-map-decltype rhs-type)))
        (sa "VAR toRecv : "
            port-typenam".Item; BEGIN IF NOT "
            port-typenam ".Recv( " m3-pname " , toRecv , cl ) THEN RETURN FALSE END;" dnl
            m3-rhs-type "Ops.FromWordArray(" (m3-format-designator pc rhs) " , "
            "toRecv) END"
            )
        )
      )

    (if (null? rhs) (null-rhs) (nonnull-rhs))
    )
  )

(define (m3-compile-eval pc stmt)
  (dis "m3-compile-eval : " stmt dnl)
  (let ((expr (cadr stmt)))
    (string-append "EVAL " (m3-compile-intrinsic pc expr))
    )
  )

(define (m3-compile-print-value pc x)
  ;; the rules for printing a value are different from
  ;; the rules for adding a value to a string
  (cond ((string? x) (stringify x))
        
        ((bigint? x)
         (sa "\"0x" (number->string (abs x) 16) "\""))
        
        ((and (boolean? x) x)       (m3-compile-print-value pc *bigm1*))
        
        ((and (boolean? x) (not x)) (m3-compile-print-value pc *big0*))

        ;; if we get here, x is not a literal
        ;;
        ;; we can print variables of the following CSP types:
        ;; bool, string, int

        ((boolean-value? pc x)
         (sa "\"0x\" & NativeInt.Format(CspBoolean.ToInteger(" (m3-format-designator pc x) "), 16)")
         )

        ((string-value? pc x)
         (m3-format-designator pc x)
         )
        
        ;; if we get here, x must be a number, and it is either native or
        ;; dynamic
        

        ((native-integer-value? pc x)
         (sa "\"0x\" & NativeInt.Format(" (m3-format-designator pc x) ", 16)")
         )
        
        ((dynamic-integer-value? pc x)
         (sa "\"0x\" & DynamicInt.FormatHexadecimal(" (m3-format-designator pc x) ")")
         )
        
        (else (error "cannot compile print-value : " x))
        )
  )

(define *ix* #f)
  
(define (m3-compile-intrinsic pc expr)
  (set! *ix* expr)
  (dis "m3-compile-intrinsic : " expr dnl)
  (if (not (call-intrinsic? expr)) (error "not an intrinsic : " expr))

  (let ((in-sym (cadr expr)))

    (case in-sym
      ((print)
       (sa "CspIntrinsics.print(frame, "
           (m3-compile-print-value pc (caddr expr))
           ")")

       )

      ((assert)
       (let ((message
              (if (null? (cdddr expr))
                  (CitTextUtils.MakeM3Literal (stringify expr))
                  (m3-compile-print-value pc (cadddr expr)))))
         (sa "CspIntrinsics.assert("
             (m3-compile-value pc 'x (force-boolean (caddr expr)))
             ", "
             message
             ")")
         )
       )
           
      ((walltime simtime)
       (sa  "CspIntrinsics." (symbol->string in-sym) "(frame)"))

      ((unpack)
       (let* ((lhs    (caddr expr))
              (rhs    (cadddr expr))
              (ty     (declared-type pc lhs))
              (snm    (struct-type-name ty))
              (m3snm  (m3-struct snm))
              (sfx    (classify-expr-type pc rhs))
              (scrtch (if (memq sfx '(dynamic wide)) " , frame.c " ""))
              (rhsstr

               (cond ((and (eq? sfx 'dynamic)
                           (bigint? rhs))
                      (make-dynamic-constant! pc rhs))

                     ((and (eq? sfx 'native)
                           (bigint? rhs))
                      (m3-format-literal rhs 16))

                     (else
                      (m3-format-designator pc rhs))))
              )

         (sa m3snm "_unpack_" (symbol->string sfx) "( frame."(m3-ident (cadr lhs))  " , " rhsstr scrtch " )(*m3-compile-intrinsic*)" )
         
         )
       )

      ((pack)
       "0"
       )

      ((string)
       ;; first convert base to native
       (let* ((val         (caddr expr))
              (base        (cadddr expr))
              (native-base (m3-compile-value pc 'native base)))
         (cond ((native-integer-value? pc val)
                (sa "CspIntrinsics.string_native(frame, "
                    (m3-compile-value pc 'native val) " , "
                    native-base
                    ")" )
                )

               ((dynamic-integer-value? pc val)
                (sa "CspIntrinsics.string_dynamic(frame, "
                    (m3-compile-value pc 'dynamic val) " , "
                    native-base
                    ")" )
                )

               (else (error)))
         );;*tel
       )

      (else (error "unknown intrinsic : " expr))
      
      );;esac
    
    );;tel
  )

(define (m3-compile-sequence pc stmt)
  (define wx (Wx.New))

  (define (w . x) (Wx.PutText wx (apply string-append x)))

  (let ((writer  (suffix-writer (indent-writer w "  ") "")))
    (w "BEGIN" dnl)

    (map (curry m3-compile-write-stmt writer pc) (cdr stmt))
    (w "END" dnl)
    )

  (Wx.ToText wx)
  )

(define (m3-compile-skip pc skip) "BEGIN (*skip*) END"  )

(define (m3-compile-sequential-loop pc seqloop)

  (let* ((dummy (get-loop-dummy seqloop))
         (range (get-loop-range seqloop))
         (stmt  (get-loop-stmt  seqloop))
         (desig (m3-format-designator pc `(id, dummy)))
         (native (native-type-expr? pc `(id ,dummy)))
         )

    (define (compile-stmt)
      (define wx (Wx.New))
      
      (define (w . x) (Wx.PutText wx (apply string-append x)))
      
      (m3-compile-write-stmt w pc stmt)
      
      (Wx.ToText wx)
      )
    
    (if native
        (sa ;; native integer FOR loop
         "FOR " desig
         " := " (m3-compile-value pc 'native (cadr range))
         " TO " (m3-compile-value pc 'native (caddr range))
         " DO" dnl
         (compile-stmt) dnl
         "END" dnl
         )

        (sa ;; dynamic integer FOR loop
         "BEGIN(*sequential-loop*)  Mpz.set("
         desig
         "," (m3-compile-value pc 'dynamic (cadr range)) "); "
         " WHILE Mpz.cmp( " desig " , "
         (m3-compile-value pc 'dynamic (caddr range)) ") # 1 DO " dnl
         (compile-stmt) dnl
         "Mpz.add_ui(" desig " , " desig " , 1)" dnl
         "END(*WHILE*) END(*sequential-loop*)" dnl
         )

        )
    )
  )


(define (m3-compile-lock-unlock whch pc stmt)
  (let* (
         (ports        (cdr stmt))
         )

    (let loop ((p ports)
               (res (sa "BEGIN " dnl)))
    
        (if (null? p)
            (sa res "END" dnl)
            
              (loop (cdr p)
                    (sa res
                        (m3-compile-lock-unlock-port whch pc (car p)) ";" dnl)
                    )
              );;fi
        );;tel
    );;*tel
  )

(define *pd* #f)

(define (m3-compile-lock-unlock-port whch pc id)
  (dis "m3-compile-lock-unlock-port : whch : " whch dnl)
  (dis "m3-compile-lock-unlock-port : id   : " id dnl)
  (let* ((port-des     `(id ,id))
         (port-tbl     (pc-port-tbl pc))
         (port-id      (get-designator-id port-des))
         (port-def     (port-tbl 'retrieve port-id))
         (port-type    (get-port-def-type port-def))
         (m3-pname     (m3-format-designator pc port-des))
         (port-typenam (m3-convert-port-type-scalar port-type))
         (adims        (array-dims port-type))
         )
    (set! *pd* port-def)

    (m3-initialize-array
     (lambda(txt) (sa port-typenam "." whch "(" txt " , cl)"))
     m3-pname
     adims
     'lock
     )
    )
  )

(define (m3-compile-waitfor pc stmt)
  (let* (
         (port-tbl     (pc-port-tbl pc))
         (ports        (cdr stmt))
         )

    ;;
    ;; the idea here is this..
    ;;
    ;; the waitfor is in a block of its own (it must be)
    ;; --a single process can't wait on a single channel twice concurrently
    ;;
    ;; entering the waitfor, we must have locked the ports of interest.
    ;;
    ;; if we don't need to wait, we unlock and proceed
    ;;
    ;; if we do need to wait, we ... remain locked and wait (atomically)
    ;; when we are awoken from wait, it is this same block, so we unwait
    ;; at the start (OK to unwait without waiting first)
    ;;
    ;; when we depart the waitfor, the ports must be unlocked and unwaited
    ;;
    ;; the wait is only active within this block, so that we don't wake
    ;; up the wrong code block.
    ;;
    ;; Note that: when we enter the block from elsewhere, we are not waiting.
    ;; But when we RETURN FALSE, we wait, so the next time we run, we enter
    ;; already waiting.  Unwait therefore has to be idempotent.
    ;; 
    
    (let loop ((p ports)
               (res (sa "VAR ready := 0; BEGIN " dnl)))
    
        (if (null? p)
            (sa
             (m3-compile-unwait pc `(XXX ,@ports)) ";" dnl
             res
             "IF ready = 0 THEN" dnl
             ;;(m3-compile-unlock pc `(XXX ,@ports)) ";" dnl
             (m3-compile-wait pc `(XXX ,@ports)) ";" dnl
             "  RETURN FALSE" dnl
             "ELSE" dnl
             (m3-compile-unlock pc `(XXX ,@ports)) dnl
             "END" dnl
             "END" dnl)
            (let* ((port-des `(id ,(car p)))
                   (port-id      (get-designator-id port-des))
                   (port-def     (port-tbl 'retrieve port-id))
                   (port-type    (get-port-def-type port-def))
                   (m3-pname     (m3-format-designator pc port-des))
                   (port-typenam (m3-convert-port-type-scalar port-type)))
              (loop (cdr p)
                    (sa res
                        (m3-compile-ready-port pc port-id) ";" dnl
                        )
                    )
              )
            )
        )
    )
  )

(define (m3-compile-ready-port pc id)
  (dis "m3-compile-ready-port : id   : " id dnl)
  (let* ((port-des     `(id ,id))
         (port-tbl     (pc-port-tbl pc))
         (port-id      (get-designator-id port-des))
         (port-def     (port-tbl 'retrieve port-id))
         (port-type    (get-port-def-type port-def))
         (m3-pname     (m3-format-designator pc port-des))
         (port-typenam (m3-convert-port-type-scalar port-type))
         (adims        (array-dims port-type))
         )
    (set! *pd* port-def)

    (m3-initialize-array
     (lambda(txt)
       (sa "IF " port-typenam ".Ready(" txt " , cl) THEN INC(ready) END" dnl)
       )
     m3-pname
     adims
     'lock
     )
    )
  )

(define m3-compile-lock   (curry m3-compile-lock-unlock "Lock"))

(define m3-compile-unlock (curry m3-compile-lock-unlock "Unlock"))

(define m3-compile-wait   (curry m3-compile-lock-unlock "Wait"))

(define m3-compile-unwait (curry m3-compile-lock-unlock "Unwait"))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  
(define (m3-compile-local-if pc stmt)

  (dis  dnl
        "m3-compile-local-if : " stmt dnl
        dnl)

  (define wx (Wx.New))

  (define (w . x) (Wx.PutText wx (apply string-append x)))
  
  (w "IF FALSE THEN" dnl)
  (let loop ((p (cdr stmt)))

    (define (command)
      (m3-compile-write-stmt (indent-writer w "  ") pc (cadar p)))

    (cond ((null? p) (w "END") (Wx.ToText wx)
           )
          
          ((eq? (caar p) 'else)
           (w "ELSE" dnl)
           (command)
           (loop (cdr p))
           )
          
          (else          
           (w "ELSIF " (m3-compile-value pc 'x (caar p)) " THEN" dnl)
           (command)
           (loop (cdr p))
           )
          );;dnoc
        );;tel
    )

(define (m3-compile-while pc stmt)
  (dis  dnl
        "m3-compile-while : " stmt dnl
        dnl)
  (define wx (Wx.New))

  (define (w . x) (Wx.PutText wx (apply string-append x)))

  (w "WHILE " (m3-compile-value pc 'x (cadr stmt)) " DO" dnl)
  (m3-compile-write-stmt (indent-writer w "  ") pc (caddr stmt))
  (w dnl
     "END(*WHILE*)")
     
  (Wx.ToText wx)
  )

               
(define (convert-sequential-loop-to-while seqloop)
  ;; unused for now (we can't call it from code generation---that's too late
  (let* ((dummy (get-loop-dummy seqloop))
         (range (get-loop-range seqloop))
         (stmt  (get-loop-stmt  seqloop)))
    `(sequence
       (assign (id ,dummy) ,(cadr range))
       (while (<= (id ,dummy) ,(caddr range))
              (sequence
                ,stmt
                (assign (id ,dummy) (+ ,*big1* (id ,dummy)))
                )
              )
       )
    )
  )

(define *known-stmt-types*
  '(recv send assign eval goto local-if while sequence sequential-loop skip
         structdecl lock unlock waitfor)
  )

(define (m3-space-comments txt)
  (CitTextUtils.Replace
   (CitTextUtils.Replace txt "(*" "( *")
   "*)" "* )"))

(define (m3-compile-write-stmt w pc stmt)
  (let (
        (stmt-type (get-stmt-type stmt))
        (iw        (indent-writer w "      "))
        )

    (dis "m3-compile-write-stmt : stmt : " (stringify stmt) dnl)
    
    (if (member stmt-type *known-stmt-types*)
        (iw ((eval (symbol-append 'm3-compile- stmt-type)) pc stmt) ";(*m3cws*)" dnl)
        (error "Unknown statement type in : " stmt)
        )          
  
    (iw "(* " (m3-space-comments (stringify stmt)) " *)" dnl dnl)
    )
  )

(define (m3-compile-structdecl pc stmt)
  "BEGIN END" ;; nothing for now
  )

(define (number->symbol x) (string->symbol (number->string x)))

(define (distinguish-labels label-lst)
  ;; here label-lst is a list of strings (not symbols)
  (let ((mls (multi label-lst)))
    (if (null? mls)
        label-lst
        (let loop ((p label-lst)
                   (res '())
                   (i 0))
          (cond ((null? p) (distinguish-labels (reverse res)))
                ((equal? (car mls) (car p))
                 (loop (cdr p)
                       (cons (sa (car p) "_" (number->string i))
                             res)
                       (+ i 1)))
                (else (loop (cdr p)
                            (cons (car p) res)
                            i))))
        );; fi
    )
  )

(define (m3-write-block w pc blk m3-label)

  ;; use the write procedure w
  ;; the process context pc
  ;; write the block blk
  ;; which is labelled m3-label, in Modula-3 code (a string)
  
  (dis (get-block-label blk) dnl)
  (dis "m3-write-block : blk : " (stringify blk) dnl)
  (dis "m3-write-block : lab : " (stringify m3-label) dnl)
  (let* ((lab         (cadr (get-block-label blk)))
         (btag        m3-label)
         (bnam        (string-append "Block_" btag))
         (tnam        (string-append "Text_" btag))
         (the-code    (cddr (filter-out-var1s blk)))

         (symtab      (pc-symtab pc))
         (the-scopes  (pc-scopes pc))
         (refvar-ids  (find-referenced-vars blk))
         (the-locals  (filter
                       (lambda(id)(eq? 'block (the-scopes 'retrieve id)))
                       refvar-ids))
         (structs

          ;; I think we have removed the structs from the blocks

          (filter  
                   (compose (yrruc member the-locals)
                            get-var1-id)
                   (filter (compose struct-type? (compose array-base-type
                                                          get-var1-type))
                             *the-decls*)))
         (v1s         (map make-var1-decl
                           the-locals
                           (map (curry symtab 'retrieve) the-locals)))
         );;*tel

    (dis "m3-write-block : the-locals : " the-locals dnl)
    (dis "m3-write-block : structs    : " structs dnl)

    (w
     "VAR " tnam " := Text.FromChars(" (MakeConstant.CharsFromText (stringify blk)) ");" dnl
     )
    (w "(* " dnl
       (m3-space-comments (ss blk))
       dnl
       " *)" dnl
       dnl)

    (w
     "PROCEDURE "bnam"(cl : Closure) : BOOLEAN =" dnl
     "  VAR" dnl)

    (map (lambda(dt) (w "    " dt dnl)) (map m3-convert-vardecl (filter identity v1s)))

    (w
     "  BEGIN" dnl
     "    WITH frame = cl.frame DO" dnl
     "      IF CspDebug.DebugSchedule THEN" dnl
     "         Debug.Out(Fmt.F(\"start %s:"lab"\" , frame.name))" dnl
     "      END;" dnl
     )
    ;; init local structs
    (map w (map m3-format-struct-init
                (map get-var1-id structs)
                (map get-var1-type structs)))
                  
    ;; the block text goes here
    (map (curry m3-compile-write-stmt w pc) the-code)

    (w 
     "    END(*WITH*);" dnl
     "    <*NOWARN*>RETURN TRUE(*handle fall-thru*)" dnl
     "  END " bnam ";(*m3wb*)" dnl
     dnl)
    )
  )

(define (m3-write-blocks w the-blocks pc)
  (let* ((wr-blks      (cdr the-blocks)) ;; skip the entry point
         (labs         (map cadr (map get-block-label wr-blks)))
         (m3-labs      (map m3-ident labs))
         (dist-m3-labs (distinguish-labels m3-labs))
         )
  (map (curry m3-write-block w pc) wr-blks dist-m3-labs)
  )
  )


(define (m3-make-intf mkfile-write intf)
  (dis "m3-make-intf : " intf dnl)
  (let ((intf-kind  (car intf))
        (intf-width (cdr intf)))
    (cond ((member intf-kind '(UInt SInt))
           (m3-write-int-intfs mkfile-write intf-kind intf-width))

          (else 'skip)
          )
    )
  )

(define (build-dir) "build/src/")

(define (m3-write-int-intfs mkfile-write intf-kind intf-width)
  (let* ((inm    (sa (symbol->string intf-kind) (number->string intf-width)))
         (intf   (cons intf-kind intf-width))
         (iwr    (FileWr.Open (sa (build-dir) inm ".i3")))
         (mwr    (FileWr.Open (sa (build-dir) inm ".m3")))
         (type   (int-intf->type intf))
         (native (m3-natively-representable-type? type))
         )
    
    (define (iw . x) (Wr.PutText iwr (apply string-append x)))
    (define (mw . x) (Wr.PutText mwr (apply string-append x)))

    (mkfile-write "Module      (\"" inm "\")" dnl
                  "SchemeStubs (\"" inm "\")" dnl
                  "Channel     (\"" inm "\" , \"" inm "\")" dnl
                  "Node        (\"" inm "\" , \"" inm "\")" dnl
                  "SchemeStubs (\"" inm "Chan\")" dnl
                  (if native
                      "NarrowIntOps"
                      "WideIntOps")  " (\"" inm "Ops\",\"" inm "\")" dnl
                  "SchemeStubs (\"" inm "Ops\")" dnl ;; CM3 issue #1205
                       
                  )
    
    (iw "INTERFACE " inm ";" dnl
        "IMPORT Mpz;" dnl
        "IMPORT NativeInt, DynamicInt;" dnl
        "<*NOWARN*>IMPORT Word;" dnl
       dnl)

    (iw "CONST Width    = " intf-width ";" dnl)
    (iw "CONST Signed   = " (Fmt.Bool (eq? intf-kind 'SInt)) ";" dnl)
    (iw "VAR(*CONST*)   Min, Max : Mpz.T;" dnl)
    
    (if native
        (let* ((range  (m3-get-intf-range intf))
               (lo-txt (m3-format-literal (car range)  16))
               (hi-txt (m3-format-literal (cadr range) 16))
               ) 
          (iw
           (cond ;; special cases per open issue in CM3
            ((and (eq? intf-kind 'SInt)
                  (= intf-width 64))
             (sa "TYPE T = INTEGER;" dnl))

            ((and (eq? intf-kind 'UInt)
                  (= intf-width 63))
             (sa "TYPE T = CARDINAL;" dnl))
                 
            (else (sa "TYPE T = [ " lo-txt " .. " hi-txt " ];" dnl))
            )
           dnl
           "CONST Wide     = FALSE;" dnl
           dnl
           )
           (iw "CONST Mask     = Word.Minus(Word.Shift(1, Width), 1);" dnl)
           (iw "CONST NotMask  = Word.Not(Mask);" dnl)
        )

        (iw
         dnl
         "TYPE T = DynamicInt.T;" dnl
         dnl
         "CONST Wide     = TRUE;" dnl
         dnl
         "VAR(*CONST*) Mask, NotMask : Mpz.T;" dnl
         dnl
        )
        )

    (iw "CONST Brand = \"" inm "\";" dnl
        dnl
        "PROCEDURE ForceRange(VAR tgt : T;  src : T);" dnl
        dnl
        )

    (iw dnl
        "END " inm "." dnl)
    (mw "MODULE " inm ";" dnl
        dnl
        "IMPORT Mpz;" dnl
        "IMPORT Word;" dnl
        "IMPORT CspDebug, Debug;" dnl
        "IMPORT NativeInt, DynamicInt;" dnl
        dnl)

    (if native
        (mw "PROCEDURE ForceRange(VAR tgt : T; src : T) =" dnl
            "  BEGIN tgt := Word.And(src, Mask) END ForceRange;" dnl
            dnl
            )
        
        (mw "PROCEDURE ForceRange(VAR tgt : T; src : T) =" dnl
            "  BEGIN" dnl
            "    Mpz.and(tgt, src, Mask);" dnl
            (if (eq? 'SInt intf-kind)
                (sa
                 "    IF Mpz.tstbit(tgt, Width - 1) = 1 THEN" dnl
                 "      Mpz.com(tgt, tgt);" dnl
                 "      Mpz.and(tgt, tgt, Mask);" dnl
                 "      Mpz.sub(tgt, tgt, One)" dnl
                 "    END" dnl)
                ""
                )
            "  END ForceRange;" dnl
            dnl)
        )

    (mw dnl
        "VAR One : T;" dnl
        "BEGIN" dnl
        )
    
        (let* ((range  (m3-get-intf-range intf))
               (lo-txt (m3-format-literal (car range)  16))
               (hi-txt (m3-format-literal (cadr range) 16))
               ) 
          (if native
              (begin
                (mw "  Min := Mpz.New();" dnl)
                (mw "  Max := Mpz.New();" dnl)
                (mw "  Mpz.init_set_si(Min, " lo-txt ");" dnl)
                (mw "  Mpz.init_set_si(Max, " hi-txt ");" dnl)
                (mw "  One := 1;" dnl)
                )
              (begin
                (mw "  Min := Mpz.New();" dnl)
                (mw "  Max := Mpz.New();" dnl)
                (mw "  EVAL Mpz.init_set_str(Min, \"" lo-txt "\", 16);" dnl)
                (mw "  EVAL Mpz.init_set_str(Max, \"" hi-txt "\", 16);" dnl)
                (mw "  Mask := Mpz.New();" dnl)
                (mw "  NotMask := Mpz.New();" dnl)
                (mw "  Mpz.set_ui   (Mask, 1);" dnl)
                (mw "  Mpz.LeftShift(Mask, Mask, Width);" dnl)
                (mw "  Mpz.sub_ui   (Mask, Mask, 1);" dnl)
                (mw "  Mpz.com      (NotMask, Mask);" dnl)
                (mw "  One := Mpz.NewInt(1);" dnl
                    dnl)
                        
              )
          )
        )
    (mw "END " inm "." dnl)
    (Wr.Close iwr)
    (Wr.Close mwr)
    )
  )

(define (m3-get-intf-range intf)
  (get-type-range (int-intf->type intf))
  )

(define (int-intf? intf)
  (member (car intf) '(UInt SInt)))

(define (int-intf->type intf)
  (case (car intf)
    ((UInt) (make-integer-type #f (cdr intf)))
    ((SInt) (make-integer-type #t (cdr intf)))
    (else (error))))

(define (m3-make-scope-map the-blocks the-decls cell-info)
  ;; a bound identifier can have four types of scope:
  ;; 1. block local
  ;; 2. process local
  ;; 3. parallel-loop dummy
  ;; 4. a port reference

  (define tbl (make-hash-table 100 atom-hash))

  (define (make-add! tag) (lambda(id)(tbl 'add-entry! id tag)))

  (map (make-add! 'block)
       (apply append (map get-loop-dummies the-blocks)))
  
  (map (make-add! 'port)
       (map get-port-id (get-ports cell-info)))

  (map (make-add! 'process)
       (m3-frame-variables the-blocks the-decls cell-info))

  (map (make-add! 'parallel-dummy)
       (apply append (map find-parallel-loop-dummies the-blocks)))

  (let* ((all-refs     (apply append (map find-referenced-vars the-blocks)))
         (block-locals (set-diff all-refs (tbl 'keys))))
    (map (make-add! 'block) block-locals)
    )

  tbl
  )

(define (find-parallel-loop-dummies prog)
  (define res '())
  (define (visit s)
    (if (eq? 'parallel-loop (get-stmt-type s))
        (begin (set! res (cons (get-loop-dummy s) res)) s)
        s)
    )

  (visit-stmt prog visit identity identity)
  res
  )

;;(define (make-decls) (gen-decls text9 *proposed-types* ))

(define (truncate-file fn) (Wr.Close (FileWr.Open fn)))

(define (append-text fn . text)
  (let ((wr (FileWr.OpenAppend fn)))
    (map (lambda(txt)(display txt wr)) text)
    (Wr.Close wr)
    )
  'ok
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; The PROCESS CONTEXT pc contains five things:
;; car     : a symtab built from the-decls
;; cadr    : the cell-info
;; caddr   : the struct-tbl
;; cadddr  : scopes for each variable
;; caddddr : the port table
;;

(define (make-proc-context
         symtab cell-info struct-tbl scopes port-tbl constants arrays)
  (list          symtab cell-info struct-tbl scopes port-tbl constants arrays))

(define pc-symtab      car)
(define pc-cell-info   cadr)
(define pc-struct-tbl  caddr)
(define pc-scopes      cadddr)
(define pc-port-tbl    caddddr)
(define pc-constants   cadddddr)
(define pc-arrays      caddddddr)

(define (write-m3overrides!)
  (let ((wr (FileWr.Open (sa (build-dir) "m3overrides"))))
    (Wr.PutText wr (sa "include(\"" *m3utils*"/m3overrides\")" dnl))
    (Wr.Close wr)
    )
  )

(define *m3-standard-packages*
  '("libm3"
    "cit_util"
    "parseparams"
    "simpletoken"
    "mscheme"
    "modula3scheme"
    "sstubgen"
    "parseparams"
    "cspsimlib"
    "mpfr"
    "cspgrammar"
    )
  )

(define *all-stubs*
  '(CspExpression CspExpressionPublic CspExpressionSeq
                  CspStatement CspStatementPublic CspStatementSeq CspType CspTypePublic CspStructMember CspStructMemberSeq CspAst CspGuardedCommand CspGuardedCommandSeq CspDeclaration CspDeclarationPublic CspDeclarationSeq CspDirection CspRange CspInterval CspDeclarator CspDeclaratorSeq CspStructDeclarator CspStructDeclaratorSeq CspSyntax CspPort CspPortSeq AtomCspPortSeqTbl TextCspPortSeqTbl FiniteInterval VaryBits DynamicInt WideInt NativeInt Debug Math Text TextWr FileWr Wr FileRd Rd TextRd SchemeEnvironment SchemeUtils Fmt Atom Word Env CitTextUtils FS FileFinder RegEx TextSeq Fingerprint Mpfr Wx Mpz
                  )
  )

(define *the-stubs*
  '(CspSyntax
    DynamicInt WideInt NativeInt
    Debug
    Math
    Text TextWr FileWr Wr FileRd Rd TextRd
    SchemeEnvironment
    Fmt Atom Word Env
    CitTextUtils
    FS
    RegEx TextSeq
    Fingerprint
    Mpfr Wx Mpz
    CspCompiledScheduler1
    CspChannelOps1
    TextPortTbl
    TextFrameTbl
    CspFrame
    CspCompiledProcess
    )
  )



(define (write-m3makefile-header!)
  (let ((wr (FileWr.Open (sa (build-dir) "m3makefile"))))

    (map (curry Wr.PutText wr)
         (map (lambda(intf)(sa "import(\"" intf "\")" dnl))
              *m3-standard-packages*))

    (define (w . x) (Wr.PutText wr (apply string-append x)))

    (w "m3_optimize(\"T\")" dnl)
    (w "interface(\"CspDebug\")" dnl)
    (w "build_generic_intf(\"CspChannelOps1\", \"CspChannelOps\", [], VISIBLE)" dnl)
    (w "build_generic_impl(\"CspChannelOps1\", \"CspChannelOps\", [\"CspDebug\"])" dnl)
    (w "build_generic_intf(\"CspCompiledScheduler1\", \"CspCompiledScheduler\", [], VISIBLE)" dnl)
    (w "build_generic_impl(\"CspCompiledScheduler1\", \"CspCompiledScheduler\", [\"CspDebug\"])" dnl)

    (w dnl)
    (Wr.PutChar wr dnl)
    
    (Wr.Close wr)
    )
  )

(define (write-m3makefile-footer!)
  (let ((wr (FileWr.OpenAppend (sa (build-dir) "m3makefile"))))
    (Wr.PutChar wr dnl)
    (map (lambda(sym)
           (Wr.PutText wr (sa "SchemeStubs(\"" (symbol->string sym) "\")" dnl)))
         *the-stubs*)
    (Wr.PutText wr (sa "ExportSchemeStubs (\"sim\")" dnl))
    (Wr.PutText wr (sa "importSchemeStubs ()" dnl))
    (Wr.PutText wr (sa "implementation (\"SimMain\")" dnl))
    (Wr.PutText wr (sa "program (\"sim\")" dnl))
    (Wr.Close wr)
    )
  )

(define (node->uint-intf intf)
  (if (eq? 'Node (car intf))
      (cons 'UInt (cdr intf))
      intf)
  )

(define (ops-intfs intfs)
  (filter identity
          (map
           (lambda(intf)
             (if (member (car intf) '(SInt UInt))
                 (cons (symbol-append (car intf) 'Ops) (cdr intf))
                 #f))
           intfs)
          )
  )

(define (find-structdecls blks)
  (apply append (map (curry find-stmts 'structdecl) blks)))

(define (base-type type)
  (if (array-type? type) (array-base-type type) type))

(define (m3-format-struct-init id stype)
  (let* ((snm   (struct-type-name (base-type stype)))
         (adims (array-dims stype))
         (m3snm (m3-struct snm))
         (m3id  (m3-ident id)))

    (sa "(*struct-init "m3id"*)" dnl
    (m3-initialize-array
     (lambda(txt)
       (sa "      " m3snm "_initialize( " txt " );" dnl))
     (sa "frame." m3id)
     adims
     'struct_init
     )
    )
    )
  )


(define *the-decls* #f)
(define *the-var-intfs* #f)

(define (m3-write-debug-template di3wr)
  (define (intf . x) (Wr.PutText di3wr (apply string-append x)))

  (intf "INTERFACE CspDebug;" dnl
        "CONST DebugSelect   = FALSE;" dnl
        "CONST DebugRecv     = FALSE;" dnl
        "CONST DebugSend     = FALSE;" dnl
        "CONST DebugProbe    = FALSE;" dnl
        "CONST DebugSchedule = FALSE;" dnl
        "CONST DebugLock     = FALSE;" dnl
        "END CspDebug." dnl
        )
)

(define (do-m3!)
  ;;
  ;; This is the main entry point for Modula-3 code generation.  We
  ;; assume that the whole compiler front-end has run (through
  ;; compile9!) and generated its results in text9.
  ;;
  ;; Here we generate the Modula-3 code for the process and write the
  ;; output into the appropriate .i3 and .m3 files.  We also edit the
  ;; m3makefile to include these files as necessary.
  ;;
  
  (set! *stage* 'do-m3!)
  (let* ((the-blocks text9)
         (cell-info  *cellinfo*)
         (port-tbl   *the-prt-tbl*)
         (the-decls  (gen-decls the-blocks *proposed-types*))
         (root       (m3-ident (string->symbol *the-proc-type-name*)))
         (i3fn       (string-append (build-dir) root ".i3"))
         (i3wr       (FileWr.Open i3fn))
         (di3fn      (string-append (build-dir) "CspDebug" ".i3"))
         (di3wr      (FileWr.Open di3fn))
         (m3fn       (string-append (build-dir) root ".m3"))
         (m3wr       (FileWr.Open m3fn))
         (ipfn       (string-append (build-dir) root ".imports"))
         (ipwr       (FileWr.Open ipfn))
         (fork-counts (get-fork-label-counts the-blocks))
         (the-scopes (m3-make-scope-map the-blocks the-decls cell-info))

         (m3-port-data-intfs
          (uniq equal?
                (map m3-convert-port-type-build
                     (map get-port-def-type
                          (port-tbl 'values)))))

         (m3-port-chan-intfs
          (set-union
;;           (map node->uint-intf
           (filter (lambda(pt)(eq? 'Node (car pt))) m3-port-data-intfs)
           ;;)
           
           (map (lambda(pt)(cons (symbol-append (car pt) 'Chan)
                                 (cdr pt)
                                 ))
                
                (filter (lambda(pt)(not (eq? 'Node (car pt))))
                        m3-port-data-intfs))))

         (m3-var-intfs
          (filter
           identity
           (uniq equal?
                 (map m3-map-declbuild
                      (map array-base-type
                           (map get-decl1-type
                                (map get-var1-decl1 the-decls)))))))

         ;; find the necessary interfaces from struct declarations:
         (sdecls    *the-struct-decls*)
         (sfields   (apply append (map cddr sdecls)))
         (sbases    (map base-type (map get-decl1-type sfields)))
         (m3-struct-intfs
          (filter identity (map m3-map-declbuild sbases)))

         ;; all-intfs0 is all the types we need to generate interfaces for
         (all-intfs0 (set-union m3-port-data-intfs
                                m3-var-intfs
                                m3-port-chan-intfs
                                m3-struct-intfs))

         ;; but we also need the Ops generics to be built:
         (all-intfs  (set-union all-intfs0 (ops-intfs all-intfs0)))

         ;; remove var1s and clean  up blocks
         (the-varfree-blocks (map filter-out-var1s the-blocks))
         (the-exec-blocks (remove-empty-blocks the-varfree-blocks))
         )

    (set! *the-decls* the-decls)
    (set! *the-var-intfs* m3-var-intfs)
    (set! text10 the-exec-blocks)

    (dis "do-m3! : m3-port-data-intfs : " m3-port-data-intfs dnl)
    (dis "do-m3! : m3-port-chan-intfs : " m3-port-chan-intfs dnl)
    (dis "do-m3! : m3-var-intfs       : " m3-var-intfs dnl)
    (dis "do-m3! : all-intfs          : " all-intfs dnl)
    
;;    (write-m3overrides!)
;;    (write-m3makefile-header!)

    ;; prepare needed custom interfaces

    (set! *ai* all-intfs)

    (let ((bld-intfs (uniq equal? (map node->uint-intf all-intfs))))
      (dis "tobuild : " bld-intfs dnl)
      (Wr.PutText ipwr (stringify bld-intfs))
;;      (map (curry m3-make-intf mkfile-write) bld-intfs)
      )


    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;;
    ;; writers for the process files
    
    (define (intf . x) (Wr.PutText i3wr (apply string-append x)))
    (define (modu . x) (Wr.PutText m3wr (apply string-append x)))
    (define (impo . x) (Wr.PutText ipwr (apply string-append x)))
    ;; interface file
    
    (intf "INTERFACE " root ";" dnl dnl)
    (intf "(*" dnl
          "FINGERPRINT " (fingerprint-string (stringify *cell*))  dnl
          "*)" dnl
          dnl
          )

    (m3-write-debug-template di3wr)
    
    (m3-write-imports intf m3-port-chan-intfs)

    (intf "CONST Brand    = \"" root "\";" dnl
          dnl)

    (m3-write-build-decl intf cell-info)

    (m3-write-start-decl intf cell-info)

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    (modu "MODULE " root ";" dnl dnl)
    (modu "(*" dnl
          "FINGERPRINT " (fingerprint-string (stringify *cell*))  dnl
          "*)" dnl
          dnl
          )

    (m3-write-imports    modu all-intfs)
    (modu "IMPORT Mpz;" dnl
          dnl)



    (m3-write-proc-public-frame-decl
     intf 
     port-tbl the-exec-blocks cell-info the-decls  fork-counts)
    
    (m3-write-proc-private-frame-decl
     modu
     port-tbl the-exec-blocks cell-info the-decls  fork-counts)
    
    (m3-write-block-decl      modu)
    (m3-write-closure-decl    modu)

    (let ((pc (make-proc-context
                         (m3-make-symtab the-decls *the-arr-tbl*)
                         cell-info
                         (make-object-hash-table get-struct-decl-name
                                                 (find-structdecls the-blocks))
                         the-scopes
                         (make-port-table cell-info)
                         (make-hash-table 100 Text.Hash)
                         *the-arr-tbl*
                         )))
      (set! *proc-context* pc)

      (let ((structs  (find-structdecls the-blocks)))
        (map (yrruc modu dnl) (map (curry m3-convert-structdecl pc) structs))
        )

      (m3-write-build-defn      modu
                                cell-info the-exec-blocks the-decls fork-counts
                                *the-arr-tbl*
                                pc)
      (m3-write-start-defn      modu
                                cell-info the-exec-blocks pc)
      (m3-write-blocks          modu the-exec-blocks pc)

      (map modu
           (map m3-gen-constant-init 
                ((pc-constants pc) 'keys)
                ((pc-constants pc) 'values)
                )
           )
    );;tel

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    
    (intf dnl "END " root "." dnl)

    (modu dnl "BEGIN END " root "." dnl)
    
    (Wr.Close di3wr)
    (Wr.Close i3wr)
    (Wr.Close m3wr)
    (Wr.Close ipwr)
    
    );;*tel
  
    
;;  (write-m3makefile-footer!)
  )

(define (m3-gen-constant-init m3-ident bigint)
  (sa "VAR "
      m3-ident " := Mpz.InitScan(\"" (number->string bigint 16) "\", 16);" dnl)
  )

(define (m3-make-symtab the-decls the-arrays)
  ;; at this point, the-decls contains declarations that are stripped
  ;; of their arrays, so we rebuild them from the array-decls
  (define tbl (make-hash-table 100 atom-hash))

  
  (map (lambda(v1)(tbl 'add-entry!
                       (get-var1-id v1)
                       (get-var1-type v1)))
       the-decls)
  tbl
  )

(define (find-decl decls id)
  (cond ((null? decls) #f)
        ((eq? id (get-var1-id (car decls))) (car decls))
        (else (find-decl (cdr decls) id)))
  )


;; the below is unused
(define (m3-write-node-intf mkfile-write intf-width)
  (let* ((inm (sa "Node" (number->string intf-width)))
         (iwr (FileWr.Open (sa (build-dir) inm ".i3"))))
    
    (define (w . x) (Wr.PutText iwr (apply string-append x)))

    (mkfile-write "Smodule (\"" inm "\")" dnl)
    
    (w "INTERFACE " inm ";" dnl)
    (w dnl
       "TYPE T = RECORD END;" dnl ;; what do we want here?
       dnl)
    (w "END " inm "." dnl)
    (Wr.Close iwr)
    )
  )

(define (find-filepaths dir pat)
  ;; find files in the directory matching the regex pattern pat
  ;; return them with the full relative path
  (let ((files (FileFinder.Find dir pat)))
    (map (curry string-append dir) files)
    )
  )

(define (m3-clear-build-area!)
  (define (clear)
    (map FS.DeleteFile (find-filepaths (build-dir) "^[^.]")))
  (define attempt
    (unwind-protect
     (clear)
     (lambda()'ok)
     (begin
       (dis "m3-clear-build-area! : warning : couldn't delete all files" dnl)
       (lambda()'fail)
       )
     )
    )
  (attempt)
  )

(define *imports-extension* "imports")

(define (derive-mod-name imp-fn)
  (let* ((len       (Text.Length imp-fn))
         (pfx-len   (Text.Length (build-dir)))
         (sfx-len   (+ 1 (Text.Length *imports-extension*))))
    (Text.Sub imp-fn pfx-len (- len pfx-len sfx-len))
    )
  )

(define (m3-write-makefile!)

  (define (mkfile-write . text)
    (apply (curry append-text (sa (build-dir) "/m3makefile")) text)
    )
  
  ;; scan build directory for .imports files
  ;; write the m3makefile
  (let* ((im-files  (find-filepaths
                     (build-dir)
                     (sa "\\." *imports-extension* "$")))
         ;; the imports files
         
         (mod-nams  (map derive-mod-name im-files))
         ;; derive module names from the imports files
         
         (im-data   (map read-importlist im-files))
         ;; load the actual imports we need to build
         
         (all-ims   (uniq equal? (apply append im-data)))
         ;; and this is the cleaned up list of import interfaces to build
         
         )
    
    (dis "m3-write-makefile : im-files : " (stringify im-files) dnl)
    (dis "m3-write-makefile : all-ims  : " all-ims dnl)

    ;; write m3overrides
    (write-m3overrides!)

    ;; and now the m3makefile
    (write-m3makefile-header!)

    ;; make code for the requested types, as well as the m3makefile entries
    (map (curry m3-make-intf mkfile-write) all-ims) 

    ;; record the modules we need to compile
    (map (lambda(root)
           (mkfile-write "Smodule (\"" root "\")" dnl))
         mod-nams)

    ;; close out the m3makefile
    (write-m3makefile-footer!)
    )

  'ok
  )

(define (do-compile-m3! nm . x)
  ;;
  ;; This is a helper routine that runs the entire compiler for a single
  ;; process.
  ;;
  ;; -- It first loads the process data from disk using loaddata1!
  ;; 
  ;; -- Then, it runs the compiler front end using compile!
  ;;
  ;; -- Next, it writes debug info in the form of .text9.scm
  ;;
  ;; -- Finally, it runs the code-generation stage that this file is mostly
  ;; dedicated to.
  ;;
  (let* ((modname   (loaddata0! nm))
         (loaded-fp (fingerprint-string (stringify *cell*)))
         (old-fp    (FingerprintFinder.Find (sa (build-dir) "/" modname ".m3")))
         )

    (cond ((and (not (null? old-fp))
                (equal? loaded-fp old-fp)
                (or (null? x) (not eq? 'force (car x)))
                )
           (dis go-grn-bold-term
                "=========  ALREADY UP-TO-DATE : " modname " , SKIPPING"
                reset-term
                dnl
                dnl)
           'skip)

          (else
           (set! *stage* 'loaddata!)
           (loaddata1!)
           (compile!)
           (write-object (sa (build-dir) "/" modname ".text9.scm") text9)
           (do-m3!)
           (pickle-globals! (sa (build-dir) "/" modname))
           'ok)
           
          );;dnoc
    );;*tel
  )

(define (restore-session! modname)
  (unpickle-globals! (sa (build-dir) "/" modname)))

(define (compile-csp! . x)
  ;;(m3-clear-build-area!)
  (map do-compile-m3! x)
  (m3-write-makefile!)
  (done-banner)
  'ok
  )

(define (test!)
  (reload)

  (compile-csp! "tests/first_proc_false.scm" "tests/first_proc_true.scm")

  )

(define (m3-write-main! builder-text)
  ;;
  ;; write the simulator Main: the entry point of the compiled program
  ;;
  (let ((mwr (FileWr.Open (sa (build-dir) "SimMain.m3"))))

    (define (mw . x) (Wr.PutText mwr (apply string-append x)))

    (mw "MODULE SimMain EXPORTS Main;" dnl)
    (mw "IMPORT CspCompiledScheduler1 AS Scheduler;" dnl)
    (mw "" dnl)
    (mw "IMPORT Fmt;" dnl)
    (mw "IMPORT ParseParams;" dnl)
    (mw "IMPORT Stdio;" dnl)
    (mw "IMPORT SchemeM3;" dnl)
    (mw "IMPORT SchemeStubs;" dnl)
    (mw "IMPORT ReadLine, SchemeReadLine;" dnl)
    (mw "IMPORT Debug;" dnl)
    (mw "IMPORT Scheme;" dnl)
    (mw "IMPORT Pathname;" dnl)
    (mw "IMPORT Thread;" dnl)
    (mw "IMPORT TextSeq;" dnl)
    (mw "IMPORT CspSim;" dnl)
    (mw "IMPORT CspWorker;" dnl)
    (mw "IMPORT CspMaster;" dnl)
    (mw "IMPORT TextSet;" dnl)

    (mw dnl)

    (mw builder-text) ;; this may contain IMPORTs

    (mw dnl)

    (mw "<*FATAL Thread.Alerted*>" dnl)
    (mw "" dnl)
    (mw "PROCEDURE GetPaths(extras : TextSeq.T) : REF ARRAY OF Pathname.T = " dnl)
    (mw "  CONST" dnl)
    (mw "    fixed = ARRAY OF Pathname.T { \"require\", \"m3\" };" dnl)
    (mw "  VAR" dnl)
    (mw "    res := NEW(REF ARRAY OF Pathname.T, NUMBER(fixed) + extras.size());" dnl)
    (mw "  BEGIN" dnl)
    (mw "    FOR i := 0 TO NUMBER(fixed) - 1 DO" dnl)
    (mw "      res[i] := fixed[i]" dnl)
    (mw "    END;" dnl)
    (mw "    FOR i := NUMBER(fixed) TO extras.size() + NUMBER(fixed) - 1 DO" dnl)
    (mw "      res[i] := extras.remlo()" dnl)
    (mw "    END;" dnl)
    (mw "    RETURN res" dnl)
    (mw "  END GetPaths;" dnl)
    (mw "" dnl)
    (mw "VAR" dnl)
    (mw "  pp       := NEW(ParseParams.T).init(Stdio.stderr);" dnl)
    (mw "  doScheme := FALSE;" dnl)
    (mw "  extra    := NEW(TextSeq.T).init();" dnl)
    (mw "  mt       : CARDINAL := 0;" dnl)
    (mw "  greedy   : BOOLEAN;" dnl)
    (mw "  nondet   : BOOLEAN;" dnl)
    (mw "  eager    : BOOLEAN;" dnl)
    (mw "  worker   : BOOLEAN;" dnl)
    (mw "  workerId : CARDINAL;" dnl)
    (mw "  master   : BOOLEAN;" dnl)
    (mw "  cmd      : TEXT;" dnl)
    (mw "  nworkers : CARDINAL;" dnl)
    (mw "  theWorker: CspWorker.T := NIL;" dnl)
    (mw "" dnl)
    (mw "BEGIN" dnl)
    (mw "  " dnl)
    (mw "  TRY" dnl)
    (mw "    IF    pp.keywordPresent(\"-worker\") THEN" dnl)
    (mw "      master   := FALSE;" dnl)
    (mw "      worker   := TRUE;" dnl)
    (mw "      workerId := pp.getNextInt()" dnl)
    (mw "    ELSIF pp.keywordPresent(\"-master\") THEN" dnl)
    (mw "      master   := TRUE;" dnl)
    (mw "      worker   := FALSE;" dnl)
    (mw "      nworkers := pp.getNextInt();" dnl)
    (mw "      cmd      := pp.getNext()" dnl)
    (mw "    END;" dnl)
    (mw "    greedy := pp.keywordPresent(\"-greedy\");" dnl)
    (mw "    nondet := pp.keywordPresent(\"-nondet\");" dnl)
    (mw "    eager  := pp.keywordPresent(\"-eager\");" dnl)
    (mw "    IF pp.keywordPresent(\"-mt\") THEN" dnl
        "       mt := pp.getNextInt()" dnl
        "    END;" dnl)
    (mw "    doScheme := pp.keywordPresent(\"-scm\");" dnl)
    (mw "    pp.skipParsed();" dnl)
    (mw "    WITH n = NUMBER(pp.arg^) - pp.next DO" dnl)
    (mw "      FOR i := 0 TO n - 1 DO" dnl)
    (mw "        extra.addhi(pp.getNext())" dnl)
    (mw "      END" dnl)
    (mw "    END;" dnl)
    (mw "    pp.finish()" dnl)
    (mw "  EXCEPT" dnl)
    (mw "    ParseParams.Error => Debug.Error(\"Can't parse command line\")" dnl)
    (mw "  END;" dnl)
    (mw "" dnl)
    (mw "  (********************  BUILD THE SIMULATION  ********************)" dnl)
    (mw "" dnl)
    (mw "  IF    worker THEN" dnl)
    (mw "    theWorker := NEW(CspWorker.T).init(id := workerId, bld := BuildSimulation);" dnl)
    (mw "    theWorker.awaitInitialization();" dnl)
    (mw "    Scheduler.SchedulingLoop(mt, greedy, nondet, eager, theWorker)" dnl)
    (mw "  ELSIF master THEN" dnl)
    (mw "    NEW(CspMaster.T).init(nworkers := nworkers," dnl
        "                          bld      := BuildSimulation," dnl
        "                          cmd      := cmd," dnl
        "                          mt       := mt       ).run()" dnl)
    (mw "  ELSE" dnl)
    (mw "    BuildSimulation();" dnl)
    (mw "" dnl)
    (mw "    IF doScheme THEN" dnl)
    (mw "      SchemeStubs.RegisterStubs();" dnl)
    (mw "      TRY" dnl)
    (mw "        WITH scm = NEW(SchemeM3.T).init(GetPaths(extra)^) DO" dnl)
    (mw "          SchemeReadLine.MainLoop(NEW(ReadLine.Default).init(), scm)" dnl)
    (mw "        END" dnl)
    (mw "      EXCEPT" dnl)
    (mw "        Scheme.E(err) => Debug.Error(\"Caught Scheme.E : \" & err)" dnl)
    (mw "      END" dnl)
    (mw "    ELSE" dnl)
    (mw "      Scheduler.SchedulingLoop(mt, greedy, nondet, eager, NIL)" dnl)
    (mw "    END" dnl)
    (mw "  END;" dnl)
    (mw "" dnl) 
    (mw "END SimMain." dnl)

    (Wr.Close mwr)
    )

  (let ((swr (FileWr.Open (sa (build-dir) "sim.scm"))))
    (Wr.PutText swr
                (sa "(load \"" *m3utils* "/" *pkg-path* "/sim.scm\")" dnl
                    dnl)
                )
    (Wr.Close swr)
    )
  
 'ok
  )

(define (get-module-cellinfo mod-name)
  (caddr (read-importlist (sa mod-name ".scm"))))

(define (get-module-ports mod-name)
  (caddddr (get-module-cellinfo mod-name)))

(define ppp #f)

(define (m3-make-csp-port pdef)
  (set! ppp pdef)
  (let ((ptype (cadddr pdef)))
    (CspPort.New (get-port-id pdef)                       ;; name
                 
                 (convert-dir (port-direction pdef))      ;; direction
                 
                 (m3-make-csp-channel (get-port-channel pdef))
                 
                 )
    )
  )

(define (m3-get-module-ports mod-name)
  (let ((seq (init-seq 'CspPortSeq.T)))
    (map (curry seq 'addhi)
         (map m3-make-csp-port (get-module-ports mod-name)))
    seq
    )
  )

(define (m3-make-module-intf-tbl mod-lst)
  (let ((the-port-tbl
         (obj-method-wrap (new-modula-object 'TextCspPortSeqTbl.Default)
                           'TextCspPortSeqTbl.Default))

        (the-port-seqs
         (map (lambda(x)(x '*m3*)) (map m3-get-module-ports mod-lst)))
        )
    (dis "m3-make-module-intf-tbl : mod-lst : " mod-lst dnl)
    (the-port-tbl 'init 100)
    
    (dis "m3-make-module-intf-tbl : mod-lst       : " mod-lst dnl)
    (dis "m3-make-module-intf-tbl : the-port-seqs : " the-port-seqs dnl)
    (map (curry the-port-tbl 'put) mod-lst the-port-seqs)

    the-port-tbl
  )
)
  
(define (fingerprint-string str)
  ;;
  ;; A cryptographically secure "fingerprint" of a string.  From the
  ;; DECSRC Vesta software management system.  See the DECSRC Modula-3
  ;; documentation for more details.
  ;; 
  (let ((fp (Fingerprint.FromText str)))
    (number->string
     (apply +
            (map (lambda(x)(* (Math.pow 256 (car x)) (cdr x))) (cdar fp))))))

(define (fs type)
  ;; a little bit of interactive debugging help.
  ;; (fs '<stmt-type>) will list all statements of type <stmt-type>
  ;; in text9.
  (apply append (map (curry find-stmts type) text9))
  )
