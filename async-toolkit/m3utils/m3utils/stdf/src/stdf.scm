; Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information.
; SPDX-License-Identifier: Apache-2.0

(require-modules "basic-defs" "m3" "display" "hashtable" "struct" "set")
(load "../src/common.scm")

;;
;; types cf and c12 are not used
;; n1 only appears in an array
;;

(load "../src/stdf-language.scm")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (m3-field-type f)
  (if (list? f)
      (let* ((idx (scheme->m3l (cadr f)))
             (m3tn (scheme->m3  (caddr f))))
        (string-append "REF ARRAY OF Stdf" m3tn ".T"))
      (string-append "Stdf" (scheme->m3 f) ".T" )))

(define (m3-field-type-intf f)
  (if (list? f)
      (let* ((idx (scheme->m3l (cadr f)))
             (m3tn (scheme->m3  (caddr f))))
        (string-append "REF ARRAY OF StdfTypes." m3tn))
      (string-append "Stdf" (scheme->m3 f))))

(define (produce-field-decl fieldspec)
  ;; field is 2-entry list: scm-nm scm-typ-nm
  (let* ((m3fn (scheme->m3l (car fieldspec)))
         (m3tn (m3-field-type (cadr fieldspec))))
    (string-append m3fn " : " m3tn ";")
    )
  )

(define (caddadr x) (car (cddadr x)))

(define (produce-field-parse fieldspec)
  ;; field is 2-entry list: scm-nm scm-typ-nm
  (let* ((m3fn (scheme->m3l (car fieldspec)))
         (m3in (m3-field-type-intf (cadr fieldspec))))
    (if (list? (cadr fieldspec))
        (if (eq? (caddadr fieldspec) 'n1)
            ;; array of nibbles

            ;; array of non-nibbles
            (string-append
             "x." m3fn " := NEW(" m3tn ", x." (scheme->m3l (cadadr fieldspec))");" dnl
             "FOR i := FIRST(x." m3fn "^) TO LAST(x." m3fn "^) DO" dnl
             "  " m3in ".Parse(rd, len, x."m3fn"[i])" dnl
             "END")
            )
        ;; non-array
        (string-append
         m3in ".Parse(rd, len, x." m3fn ")" )
        )
    )
  )

(define (produce-record-decl field-list wr)
  (begin
    (let loop ((lst field-list))
      (if (null? lst)
          #t
          (begin
            (dis "  " (produce-field-decl (car lst)) dnl wr)
            (loop (cdr lst)))
          )
      )
    (dis "END;" dnl wr)
    #t
    );;nigeb
  )
    
 
;;(produce-record-decl stdf-record-header "" '())
;;(produce-record-decl (cadr file-attributes-record) (string-append "  hdr : StdfRecordHeader.T;" dnl) '())

(define (put-m3-imports wr)
  (dis "<*NOWARN*>IMPORT StdfU1, StdfU2, StdfU4, StdfN1, StdfCn;" dnl
       "<*NOWARN*>IMPORT StdfI2, StdfB1, StdfC1, StdfDn, StdfVn;" dnl
       "<*NOWARN*>IMPORT StdfI1, StdfR4, StdfI4, StdfBn;" dnl
       "<*NOWARN*>IMPORT StdfE, Rd, Thread, Wx, Fmt, Wr;" dnl
       dnl
       wr))

;; deriv-dir is set by the generator from the TARGET argument

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define parse-proc-name "Parse")
(define parse-proto "(rd : Rd.T; READONLY hdr : StdfRecordHeader.T; VAR len : CARDINAL; VAR t : T) RAISES { StdfE.E , Rd.EndOfFile, Rd.Failure, Thread.Alerted}")

(define parse-hdr-proc-name "Parse")
(define parse-hdr-proto "(rd : Rd.T; VAR len : CARDINAL; VAR t : T) RAISES { StdfE.E , Rd.EndOfFile, Rd.Failure, Thread.Alerted}")

(define parseobj-proc-name "ParseObject")
(define parseobj-proto "(rd : Rd.T; READONLY hdr : StdfRecordHeader.T; VAR len : CARDINAL) : StdfRecordObject.T RAISES { StdfE.E, Rd.EndOfFile, Rd.Failure, Thread.Alerted }")

(define formatwx-proc-name "FormatWx")
(define formatwx-proto "(wx : Wx.T; READONLY t : T)")

(define format-proc-name "Format")
(define format-proto "(READONLY t : T) : TEXT")

(define formatobj-proc-name "FormatObject")
(define formatobj-proto "(x : StdfRecordObject.T) : TEXT")

(define bytes-proc-name "Bytes")
(define bytes-proto "(READONLY t : T) : CARDINAL (* not incl header *)")

(define write-proc-name "Write")
(define write-proto "(wr : Wr.T; VAR t : T) RAISES { Wr.Failure, Thread.Alerted }")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (put-m3-proc whch .
                     wrs ;; i3 m3 ...
                     )
  (map (lambda(wr)
         (dis
          "PROCEDURE "
          (eval (symbol-append whch '-proc-name))
          (eval (symbol-append whch '-proto))
          wr))
       wrs)
  (dis ";" dnl (car wrs)) ;; i3
  (dis " =" dnl (cadr wrs)) ;; m3
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (make-header-code rec-nam)
  (let* ((rec (eval rec-nam))
         (wrs (open-m3 (string-append "Stdf" (scheme->m3 rec-nam))))
         (i-wr (car wrs))
         (m-wr (cadr wrs))
         (field-lens (map StdfTypeName.GetByteLength
                          (map symbol->string
                               (map cadr rec))))
         )

    (dis "TYPE T = " dnl i-wr)
    (dis "RECORD" dnl i-wr)
    (produce-record-decl rec i-wr)
    (dis dnl i-wr)
    
    ;; following leads to circular imports
    ;;  (dis "TYPE O = StdfRecordObject.T OBJECT rec : T END;" dnl
    ;;       dnl i-wr)
    
    (if (not (member? -1 field-lens))
        (dis "CONST Length = "
             (number->string (eval (cons '+ field-lens)))
             ";" dnl
             i-wr))
    
    (put-m3-proc 'parse-hdr i-wr m-wr)
    (dis "  BEGIN" dnl m-wr)
    (let loop ((lst rec))
      (if (null? lst)
          ""
          (let* ((rec (car lst))
                 (t (cadr rec))
                 (m3t (scheme->m3 t))
                 (m3f (scheme->m3l (car rec))))
            
            (dis "    Stdf" m3t ".Parse(rd, len, t." m3f ");" dnl m-wr)
            (loop (cdr lst))
            )
          
          )
      )
    (dis  "  END Parse;" dnl
          dnl
          m-wr)

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    (put-m3-proc 'format i-wr m-wr)
    (dis "  VAR wx := Wx.New(); BEGIN" dnl 
         "    FormatWx(wx, t);" dnl
         "    RETURN Wx.ToText(wx)" dnl
         "  END Format;" dnl
         dnl
         m-wr)

    (put-m3-proc 'formatwx i-wr m-wr)
    (dis "  BEGIN" dnl m-wr) 
    (let loop ((lst rec))
      (if (null? lst)
          ""
          (let* ((rec (car lst)))
            (emit-field-formatwx rec m-wr)
            (loop (cdr lst))
            )
          
          )
      );;tel
    (dis "  END FormatWx;" dnl
         dnl
         m-wr)
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    (put-m3-proc 'write i-wr m-wr)
    (dis "  BEGIN" dnl
         m-wr)

    (map (lambda(r)(emit-field-write r m-wr)) rec)

    (dis
         "  END Write;" dnl
         dnl
         m-wr)

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    
    (close-m3 wrs)
    )
  )

(define (get-type-len tdef)
  (if (symbol? tdef)
      (StdfTypeName.GetByteLength (symbol->string tdef))
      -1
      )
  )

(define (make-record-code rec-nam)
  (let* ((rec (cadr (eval rec-nam)))
         (wrs (open-m3 (string-append "Stdf" (scheme->m3 rec-nam))))
         (i-wr (car wrs))
         (m-wr (cadr wrs))
         (field-lens (map get-type-len
                          (map cadr rec)))
         )
    
    (dis "IMPORT StdfRecordObject, StdfRecordHeader;" dnl dnl i-wr)
    (dis "IMPORT StdfRecordObject, StdfRecordHeader;" dnl dnl m-wr)
    
    (dis "TYPE T = " dnl
         i-wr)
    (dis "RECORD" dnl
         "  header : StdfRecordHeader.T;" dnl i-wr)
    (produce-record-decl rec i-wr)
    (dis dnl i-wr)
    
    (if (not (member? -1 field-lens))
        (dis "CONST Length = "
             (number->string (eval (cons '+ field-lens)))
             ";" dnl
             i-wr))
    
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    (put-m3-proc 'parse i-wr m-wr)
    (dis "  BEGIN" dnl m-wr)
    (dis "    t.header := hdr;" dnl m-wr)
    (let loop ((lst rec))
      (if (null? lst)
          ""
          (let* ((rec (car lst)))
            (set! *e* rec)
            (emit-field-init rec m-wr)
            (loop (cdr lst))
            )
          
          )
      )
    (let loop ((lst rec))
      (if (null? lst)
          ""
          (let* ((rec (car lst)))
            (set! *e* rec)
            (emit-field-parse rec m-wr)
            (loop (cdr lst))
            )
          
          )
      )
    (dis  "  END Parse;" dnl
          dnl
          m-wr)

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    (put-m3-proc 'parseobj i-wr m-wr)
    (dis "TYPE O = StdfRecordObject.T OBJECT rec : T; END;" dnl dnl i-wr)
    (dis "  VAR res := NEW(O); BEGIN" dnl
         "    Parse(rd, hdr, len, res.rec);" dnl
         "    RETURN res" dnl
         "  END ParseObject;" dnl
         dnl
         m-wr)
    
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    (put-m3-proc 'format i-wr m-wr)
    (dis "  VAR wx := Wx.New(); BEGIN" dnl 
         "    FormatWx(wx, t);" dnl
         "    RETURN Wx.ToText(wx)" dnl
         "  END Format;" dnl
         dnl
         m-wr)

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    (put-m3-proc 'formatwx i-wr m-wr)
    (dis "  BEGIN" dnl m-wr)
    (let loop ((lst rec))
      (if (null? lst)
          ""
          (let* ((rec (car lst)))
            (set! *e* rec)
            (emit-field-formatwx rec m-wr)
            (loop (cdr lst))
            )
          
          )
      )
    (dis   "  END FormatWx;" dnl
         dnl
         m-wr)

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    (put-m3-proc 'formatobj i-wr m-wr)
    (dis "  BEGIN" dnl 
         "    RETURN Format(NARROW(x, O).rec)" dnl
         "  END FormatObject;" dnl
         dnl
         m-wr)

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    (put-m3-proc 'bytes i-wr m-wr)
    (dis "  VAR b : CARDINAL := 0; BEGIN" dnl m-wr)

    (map (lambda(r)(emit-field-bytes r m-wr)) rec)

    (dis
         "    RETURN b" dnl
         "  END Bytes;" dnl
         dnl
         m-wr)

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    (put-m3-proc 'write i-wr m-wr)
    (dis "  BEGIN" dnl
         "    t.header.recLen := Bytes(t);" dnl
         "    StdfRecordHeader.Write(wr, t.header);" dnl
         m-wr)

    (map (lambda(r)(emit-field-write r m-wr)) rec)

    (dis
         "  END Write;" dnl
         dnl
         m-wr)

    (close-m3 wrs)
    )
  )

(define *e* '())

(define (emit-field-formatwx rec wr)
  (let ((m3f (scheme->m3l (car rec)))
        (t (cadr rec)))
    (dis "    Wx.PutText(wx, \"" m3f ": \");" dnl wr)
    (if (symbol? t)
        (let ((m3t (scheme->m3 t)))
          (dis "    Wx.PutText(wx, Stdf" m3t ".Format(t." m3f "));" dnl wr)
          )
        (let ((a   (car t))
              (idx (cadr t))
              (m3t (scheme->m3 (caddr t))))
          (if (not (eq? a 'array)) (error "not an array spec : " t))
          (dis "    FOR i := FIRST(t." m3f "^) TO LAST(t." m3f "^) DO" dnl
               "      Wx.PutChar(wx, '\\n');" dnl
               "      Wx.PutChar(wx, '[');" dnl
               "      Wx.PutText(wx, Fmt.Int(i));" dnl
               "      Wx.PutText(wx, \"] : \");" dnl
               "      Wx.PutText(wx, Stdf" m3t ".Format(t." m3f "[i]));" dnl
               "    END;" dnl wr)
          )
        )
    (dis "    Wx.PutChar(wx, '\\n');" dnl wr)
    )
  )
               

(define must-init-types '(bn cn dn vn))

(define (emit-field-init rec wr)
  ;; initialize arrays to a length-zero array
  (let ((m3f (scheme->m3l (car rec)))
         (t (cadr rec)))
    (if (symbol? t)
        (if (member? t must-init-types)
            (dis "    t."m3f" := Stdf"(scheme->m3 t)".Default();" dnl
                 wr))
        (let ((a   (car t))
              (idx (cadr t))
              (m3t (scheme->m3 (caddr t))))

          (dis "    t."m3f" := NEW(REF ARRAY OF Stdf"m3t".T, 0);" dnl
               wr)
          )
        )
    )
  )

(define (emit-field-init rec wr) )
               
(define (emit-field-parse rec wr)
  (let ((m3f (scheme->m3l (car rec)))
         (t (cadr rec)))
    (if (symbol? t)
        (let ((m3t (scheme->m3 t)))
          (dis "    Stdf" m3t ".Parse(rd, len, t." m3f ");" dnl wr)
          )
        (let ((a   (car t))
              (idx (cadr t))
              (m3t (scheme->m3 (caddr t))))
          (if (not (eq? a 'array)) (error "not an array spec : " t))
          (if (number? idx)
              (dis "    t."m3f" := NEW(REF ARRAY OF Stdf"m3t".T, " (number->string idx)");" dnl wr)
              (dis "    t."m3f" := NEW(REF ARRAY OF Stdf"m3t".T, t." (scheme->m3l idx)");" dnl wr)
              )
          (if (eq? (caddr t) 'n1)
              (dis     "    StdfN1.ParseArray(rd, len, t."m3f"^);" dnl wr)
              
              (dis     "    FOR i := FIRST(t."m3f"^) TO LAST(t."m3f"^) DO" dnl
                       "      Stdf" m3t ".Parse(rd, len, t." m3f "[i])" dnl 
                       "    END;" dnl wr)
              )
          )
        ))
  'ok
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (emit-field-bytes rec wr)
  (let ((m3f (scheme->m3l (car rec)))
         (t (cadr rec)))
    (if (symbol? t)
        (let ((m3t (scheme->m3 t)))
          (dis "    INC(b,Stdf" m3t ".Bytes(t." m3f "));" dnl wr)
          )
        (let ((a   (car t))
              (idx (cadr t))
              (m3t (scheme->m3 (caddr t))))

          (if (not (eq? a 'array)) (error "not an array spec : " t))

          (if (eq? (caddr t) 'n1)
              ;; special case for Nibble array
              (dis     "    INC(b,StdfN1.BytesArray(t."m3f"^));" dnl wr)

              ;; else not a Nibble array, just get a single element and
              ;; multiply by N
              (begin
                (dis "    VAR n : CARDINAL; BEGIN" dnl wr)
                (if (number? idx)
                    (dis "      n := "(number->string idx)";" dnl wr)
                    (dis "      n := t."(scheme->m3l idx)";" dnl wr)
                    )
                (dis "      IF n # 0 THEN" dnl wr)
                (dis "        INC(b, n*Stdf"m3t".Bytes(t."m3f"[0]));" dnl wr)
                (dis "      END" dnl
                     "    END;" dnl
                     wr)
                )
              )
          )
        )
    )
  'ok
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (emit-field-write rec wr)
  (let ((m3f (scheme->m3l (car rec)))
         (t (cadr rec)))
    (if (symbol? t)
        (let ((m3t (scheme->m3 t)))
          (dis "    Stdf" m3t ".Write(wr, t." m3f ");" dnl wr)
          )
        (let ((a   (car t))
              (idx (cadr t))
              (m3t (scheme->m3 (caddr t))))

          (if (not (eq? a 'array)) (error "not an array spec : " t))

          (if (eq? (caddr t) 'n1)
              ;; special case for Nibble array
              (dis     "    StdfN1.WriteArray(wr, t."m3f"^);" dnl wr)

              ;; else not a Nibble array, write each element
              (begin
                (if (number? idx)
                    (dis "    <*ASSERT NUMBER(t."m3f"^)= "(number->string idx)"*>" dnl wr)
                    (dis "    <*ASSERT NUMBER(t."m3f"^)= t."(scheme->m3l idx)"*>" dnl wr)
                    )

                (dis "    FOR i := FIRST(t." m3f "^) TO LAST(t." m3f "^) DO" dnl

                     "      Stdf"m3t".Write(wr, t."m3f"[i]);" dnl
                     "    END;" dnl wr)
                
                )
              )
          )
        )
    )
  'ok
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (make-record-types)
  (let* ((wrs (open-m3 "StdfRecordTypes"))
         (i-wr (car wrs))
         (m-wr (cadr wrs)))

    (dis "IMPORT StdfRecordObject, StdfRecordHeader;" dnl dnl i-wr)
    (dis "IMPORT "
         (infixize (map (lambda(s)(string-append "Stdf" s)) (map scheme->m3 (map car stdf-record-types))) ", ")
         ";" dnl
         i-wr)
              
    (dis dnl
         "TYPE" dnl
         "  PF = PROCEDURE" parseobj-proto ";" dnl
         dnl
         "  FF = PROCEDURE" formatobj-proto ";" dnl
         dnl
         "  T = RECORD" dnl
         "    nm      : TEXT;" dnl
         "    enum    : Enum;" dnl
         "    recTyp  : CARDINAL;" dnl
         "    recSub  : CARDINAL;" dnl
         "    parser  : PF;" dnl
         "  END;" dnl
         dnl
         "  Enum = { " (infixize (map car (map eval (map car stdf-record-types))) ", ") " };" dnl
         dnl
         "CONST" dnl
         "  Names = ARRAY Enum OF TEXT { " (infixize (map double-quote (map car (map eval (map car stdf-record-types)))) ", ") " };" dnl
         dnl
         "  Types = ARRAY Enum OF T { " (infixize (map make-type-desc stdf-record-types) ", "  ) " };" dnl
         dnl
         "  Formatters = ARRAY Enum OF FF { " (infixize (map make-format-desc stdf-record-types) ", "  ) " };" dnl
         dnl
         i-wr)
  
  (close-m3 wrs)
  )
)

(define (make-type-desc rtyp)
  (let ((m3tn (scheme->m3 (car rtyp)))
      (rec (eval (car rtyp))))
    (string-append
     dnl "    T { \"Stdf"m3tn"\", "
     "Enum."(symbol->string (car rec))", "
     (number->string (cadr rtyp))", "
     (number->string (caddr rtyp))", "
     "Stdf"m3tn".ParseObject }")
    )
)
  
(define (make-format-desc rtyp)
  (let ((m3tn (scheme->m3 (car rtyp))))
    (string-append "Stdf"m3tn".FormatObject")
    )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(dis ">>>>>>>>>>>>>>>>>>>>  building STDF modules  >>>>>>>>>>>>>>>>>>>>" dnl '())

(map make-record-code (map car stdf-record-types))
(make-header-code 'record-header)
(make-record-types)

(dis "<<<<<<<<<<<<<<<<<<  done building STDF modules  <<<<<<<<<<<<<<<<<" dnl '())
