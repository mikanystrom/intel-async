; Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information.
; SPDX-License-Identifier: Apache-2.0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; COMMON HELPERS
;;

;; deriv-dir is set by the calling program from the TARGET argument

(define (fromhex x) (Scan.Int (stringify x) 16))

(define (symbol-append . x) ;; permissive form, allow both symbol and string
  (string->symbol
   (eval
    (cons 'string-append
          (map (lambda (s)
                 (cond ((symbol? s) (symbol->string s))
                       ((string? s) s)
                       (else (error (string-append
                                     "not a string or symbol : " s)))))
               x)))))

(define sa string-append)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; FILE HANDLING

(define (cmp-files-safely fn1 fn2)
  (let ((res #f))
    (unwind-protect
     (set! res (cmp-files fn1 fn2)) () #f)
    res))

(define (rename-file-if-different fn1 fn2)
  (if (not (cmp-files-safely fn1 fn2))
      (fs-rename fn1 fn2) ;; copy the scratch over the target
      (FS.DeleteFile fn1) ;; else delete the scratch
      ))

(define (open-m3 nm)
  (let ((i-wr (filewr-open (symbol->string (symbol-append deriv-dir nm ".i3.tmp"))))
        (m-wr (filewr-open (symbol->string (symbol-append deriv-dir nm ".m3.tmp")))))
    (let ((m3m-wr (FileWr.OpenAppend (sa deriv-dir "derived.m3m"))))
      (dis "derived_interface(\""nm"\",VISIBLE)" dnl
           "derived_implementation(\""nm"\")" dnl
           m3m-wr)
      (wr-close m3m-wr))
          
                  
    (dis "INTERFACE " nm ";" dnl i-wr)
    (put-m3-imports i-wr)
    
    (dis "MODULE " nm ";" dnl m-wr)
    (put-m3-imports m-wr)
    
    (list i-wr m-wr nm deriv-dir)))

(define (put-m3-imports wr)
  (dis "(* IMPORTs *)" dnl
       dnl
       wr))

(define (close-m3 wrs)
  (let ((i-wr      (car wrs))
        (m-wr      (cadr wrs))
        (nm        (caddr wrs))
        (deriv-dir (cadddr wrs)))

    (dis dnl
         "CONST Brand = \"" nm "\";" dnl i-wr)
    (dis dnl
         "END " nm "." dnl i-wr)
    (dis dnl
         "BEGIN Do() END " nm "." dnl m-wr)
    (wr-close i-wr)
    (wr-close m-wr)
    (rename-file-if-different (sa deriv-dir nm ".i3.tmp")
                              (sa deriv-dir nm ".i3"))
    (rename-file-if-different (sa deriv-dir nm ".m3.tmp")
                              (sa deriv-dir nm ".m3"))
    ))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (intersperse lst sep)
  ;; this routine MUST BE tail-recursive, or we shall definitely
  ;; run out of stack space!
  (define (helper lst so-far)
    (cond ((null? lst) so-far)
          ((null? (cdr lst)) (cons (car lst) so-far))

          (else
           (helper (cdr lst)
                   (cons sep  (cons (car lst) so-far))))))
  (reverse (helper lst '()))
  )

(define (infixize string-list sep)
  (if (null? string-list) ""
      (apply sa
             (intersperse string-list sep))))     

(define (single-quote str)
  (string-append "'" str "'"))

(define (double-quote str)
  (string-append "\"" str "\""))

