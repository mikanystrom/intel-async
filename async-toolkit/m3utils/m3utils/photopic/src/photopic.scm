; Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information.
; SPDX-License-Identifier: Apache-2.0

(require-modules "display" "m3")

;;
;; code to compute energy content of a few types of visible light
;;
;; Mika Nystrom <mika@alum.mit.edu> January 2023
;;
;; This code is meant to interface with Modula-3 implementations
;; in the m3utils or cm3 repos.
;;

;;
;; some constants of nature
;; all units are SI base units unless otherwise noted
;;
(define c 299792458.0)       ;; speed of light in vacuum
(define h 6.62607015e-34)    ;; Planck's constant
(define k 1.380649e-23)      ;; Boltzmann's constant
(define pi (* 4 (atan 1)))   ;; the ratio of circumference to diameter of a circle  

(define l0 380e-9)           ;; blue limit of human vision 380nm
(define l1 770e-9)           ;; red limit of human vision  770nm
(define nu0 (/ c l0))        ;; frequency of blue
(define nu1 (/ c l1))        ;; frequency of red

(define (reload) (load "photopic.scm"))

;; the following from tfc-yield.scm
;; glue function to make it possible to pass Scheme functions into
;; Modula-3 code
(define (make-lrfunc-obj f)
  (let* ((func (lambda(*unused* x)(f x)))
         (min-obj (new-modula-object 'LRFunction.T `(eval . ,func) `(evalHint . ,func))))
    min-obj))

(define (make-lrvectorfield-obj f)
  (let* ((func (lambda(*unused* x)(f x)))
         (min-obj (new-modula-object 'LRVectorField.T `(eval . ,func) `(evalHint . ,func))))
    min-obj))

(define (unwrap-lrfunc lrf)
  (let ((w (obj-method-wrap lrf 'LRFunction.T)))
    (lambda(x) (w 'eval x))))
   
;; helper function to integrate a function
(define (integrate f a b)
  ;; integrate f from a to be in 2^lsteps
  (NR4p4.QromoMidpoint (make-lrfunc-obj f)
                       a
                       b))

(define (make-Bnu T)
  ;; B_nu(T) 
  ;; blackbody radiance per frequency
  (lambda(nu)(Blackbody.PlanckRadiance T nu)))

(define (make-Bl T)
  ;; blackbody radiance per wavelength
  (lambda(l)
    (let ((nu (/ c l)))
      (/ (Blackbody.PlanckRadiance T nu) (/  c (* nu nu))))))

(define (plot f a b fn . steps)
  ;; produce a file in gnuplot data format 
  ;; plot function f from a to b into file called fn
  (let* ((n (if (null? steps) 100 (car steps)))
         (step (/ (- b a) n))
         (wr (FileWr.Open fn))
         )
    (let loop ((p a))
      (if (< p b)
          (begin
            (Wr.PutText wr (string-append (stringify p)
                                          " "
                                          (stringify (f p))
                                          dnl))
            (loop (+ p step)))
          (Wr.Close wr)))))
    

(define (total-power-at-temp T)
  ;; integrate the power of a blackbody at temp T (per square meter?)
  (integrate (make-Bl T) (/ l0 10) (* l1 100)))

(define (visible-power-at-temp T)
  ;; integrate the power of a blackbody at temp T in the visible spectrum
  ;; per square meter?
  (integrate (make-Bl T)  l0 l1))

;; note that it doesn't really matter what the area is that we integrate over
;; since all we care about is the fraction of the light that is in a particular
;; wavelength range

(define (visible-fraction-at-temp T)
  (/ (visible-power-at-temp T) (total-power-at-temp T)))

(define (make-normal mu sigma)
  ;; a Gaussian that we can use for various test purposes
  (lambda (x)
    (let* ((factor (/ 1 (* sigma (sqrt (* 2 pi)))))
           (s     (/ (- x mu) sigma))
           (y      (exp (* -0.5 s s))))
      (* factor y))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; lumens per watt calcs
;;

(define (calc-lumens f)
  (define (integrand x)
    (* (f x) (CieSpectrum.PhotoConv x)))

  (integrate integrand l0 l1))

(define (visible-power f)
  (integrate f l0 l1))

(define (total-power f)
  (+ (integrate f (/ l0 10) l0)
     (visible-power f)
     (integrate f l1 (* l1 100))))

(define (visible-lumens-per-watt f)
  (/ (calc-lumens f)
     (visible-power f)))

(define (total-lumens-per-watt f)
  (/ (calc-lumens f)
     (total-power f)))

(define (total-blackbody-lpW T)
  (total-lumens-per-watt (make-Bl T)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Philips phosphor-converted LED loss model
;;
;; A blue LED at lambda-pump converts photons to longer wavelengths
;; via phosphors.  Each conversion incurs:
;;   - Stokes loss: energy ratio lambda/lambda-pump > 1
;;   - Quantum efficiency < 1 (not every pump photon makes an output photon)
;;
;; Cost per watt of optical output at wavelength lambda:
;;   C(lambda) = max(1, lambda / (lambda-pump * QE))
;;
;; Philips-corrected LER = K_m * integral(S*V) / integral(S*C)
;;

(define *pump-nm*   450e-9)  ;; blue LED pump wavelength [m]
(define *pump-qe*   0.90)    ;; average phosphor quantum efficiency

(define (philips-cost lambda)
  ;; watts of pump power needed per watt of output at lambda
  (if (<= lambda *pump-nm*)
      1.0
      (/ lambda (* *pump-nm* *pump-qe*))))

(define (philips-power f)
  ;; integrate f(lambda) * C(lambda) over visible range
  (integrate (lambda(x) (* (f x) (philips-cost x))) l0 l1))

(define (philips-lumens-per-watt f)
  ;; Philips-corrected luminous efficacy
  (/ (calc-lumens f) (philips-power f)))

(define (visible-blackbody-lpW T)
  (visible-lumens-per-watt (make-Bl T)))

(define (R9 l)
  ;; R9 color test spectrum
  (cdr (assoc 9 (Tcs.R l))))

(define (R n)
  ;; R(n) color test spectrum
  (lambda (l)
    (cdr (assoc n (Tcs.R l)))))

(define (FL n)
  (lambda (l)
    (cdr (assoc n (FlIlluminant.F l)))))

(define (make-plots)
  ;; run this to make some graphs
  (plot total-blackbody-lpW 1000 10000 "total_blackbody_lpw.dat")

  (plot visible-blackbody-lpW 1000 10000 "visible_blackbody_lpw.dat")
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; CIE XYZ
;;

;; a "spectrum" is a procedure of one argument that returns
;; an energy density in W/nm (units?)

(define (get-channel channel)
  (lambda(l) (cdr (assoc channel (CieXyz.Interpolate l) ))))

(define (get-channel-integral spectrum channel)
  (let* ((c         (lambda(l) (cdr (assoc channel (CieXyz.Interpolate l) ))))
         (integrand (lambda(l) (* (c l) (spectrum l)))))
    (integrate integrand l0 l1)))

;; all the various coordinate systems used...

(define (xyz->Yxy xyz)
  ;; (x,y,z) and (Y, x, y)
  (let* ((xint (car xyz))
         (yint (cadr xyz))
         (zint (caddr xyz))
         (sum (+ xint yint zint)))
    (list sum (/ xint sum) (/ yint sum))))

(define (calc-Yxy spectrum)
  ;; compute Yxy on a given spectrum function
  (let* ((xint (get-channel-integral spectrum 'x))
         (yint (get-channel-integral spectrum 'y))
         (zint (get-channel-integral spectrum 'z)))
    (xyz->Yxy (list xint yint zint))))

(define (Yxy->uv Yxy)
  ;; convert to 1960 CIE MacAdam uv 
  (let* ((x         (cadr  Yxy))
         (y         (caddr Yxy))
         (uv-denom  (+ (* -2 x) (* 12 y) 3))
         (u         (/ (* 4 x) uv-denom))
         (v         (/ (* 6 y) uv-denom)))
    (list u v)))

(define (Yxy->Yuv Yxy)
  ;; same as above with Y also in the result
  (let* ((Y         (car Yxy))
         (x         (cadr  Yxy))
         (y         (caddr Yxy))
         (uv-denom  (+ (* -2 x) (* 12 y) 3))
         (u         (/ (* 4 x) uv-denom))
         (v         (/ (* 6 y) uv-denom)))
    (list Y u v)))

(define (calc-uv spectrum)
  ;; MacAdam 1960 UCS coordinates
  ;; note, NOT the same as 1976 CIE Luv
  ;; used for CCT calcs
  (let* ((Yxy       (calc-Yxy spectrum)))
    (Yxy->uv Yxy)))
         
(define (make-T-uv-tbl step wr)
  ;; print the UV values for different temperatures
  ;; in Modula-3 syntax, ready to be made into an Interface
  (let ((lo 0)
        (hi 20000)
        (fmt (lambda(x) (Fmt.LongReal x 'Auto 6))))
    
    (let loop ((T lo))
      (if (> T hi)
          'ok
          (begin
            (let ((uv (calc-uv (make-Bl T))))
              (dis " T { " (fmt T) ", UV { " (fmt (car uv)) ", " (fmt (cadr uv)) " } }, " dnl wr))
            (loop (+ step T)))))))

(define (make-T-uv-interface)
  ;; build the M3 interface
  (let ((wr (FileWr.Open "temp_uv.m3")))
    (make-T-uv-tbl 50 wr)
    (Wr.Close wr)))

(define (temp-uv T)
  ;; extract the uv coordinates for a T K blackbody from the table
  ;; prepared above
  (let* ((tuv (TempUv.Interpolate T))
         (u   (cdr (assoc 'u (assoc 'uv tuv))))
         (v   (cdr (assoc 'v (assoc 'uv tuv)))))
    (list u v)))

(define (uv-norm uv T)
  ;; compute the Duv given that T is the CCT of the spectrum whose
  ;; uv is given in uv
  (let* ((tuv (temp-uv T))
         (du  (- (car  uv) (car  tuv)))
         (dv  (- (cadr uv) (cadr tuv)))
         (dsq (+ (* du du) (* dv dv))))
    (sqrt dsq)))
        
(define (search-T uv)
  ;; compute the CCT for a source given its MacAdam uv coordinates
  (let* ((f  (lambda(T)(uv-norm uv T)))
         (mf (make-lrfunc-obj f))
         (T (Bracket.SchemeBrent '((a . 10) (b . 1000) (c . 20000))
                                 mf
                                 1e-6)))
    (list (cdr (assoc 'x T)) (cdr (assoc 'y T)))
    )
  )

(define (Yuv->UVW Yuv uv0)
  ;; convert to UVW coordinates under a given white point
  ;; uv0 is the white point
  (let* ((Y (car Yuv))
         (u (cadr Yuv))
         (v (caddr Yuv))

         (u0 (car uv0))
         (v0 (cadr uv0))

         (W* (- (* 25 (Math.pow Y (/ 1 3))) 17))
         (U* (* 13 W* (- u u0)))
         (V* (* 13 W* (- v v0))))
    (list U* V* W*)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; simple operations on spectra
;;

(define (scale-spectrum a fact)
  (lambda(l)(* fact (a l))))

(define (combine-spectra a b op)
  (lambda(l)(op (a l)(b l))))

(define (multiply-spectra a b)
  (combine-spectra a b *))

(define (divide-spectra a b)
  (combine-spectra a b /))

(define (add-spectra a b)
  (combine-spectra a b +))

(define (weight-spectra a aw b bw)
  (add-spectra
   (scale-spectrum a aw)
   (scale-spectrum b bw)))

;; reflection rule for spectrum, it's the inner product
(define (reflected-tcs-spectrum i illuminant-spectrum)
  
  (multiply-spectra illuminant-spectrum (R i)))

;; normalize a spectrum so it has Y = 100 (needed for CRI calc)
(define (normalize-spectrum spectrum)
  (let* ((Yxy0 (calc-Yxy spectrum))
         (Y    (car Yxy0)))
    (lambda(l)(* (/ 100 Y)(spectrum l)))))

(define (calc-reflected-UVW sample normalized-spectrum uv0)
  (Yuv->UVW
   (Yxy->Yuv (calc-Yxy (multiply-spectra sample normalized-spectrum)))
   uv0))

;; convert to cd coordinates for color adaptation
(define (uv->cd uv)
  (let* ((u (car  uv))
         (v (cadr uv))
         (c (/ (+ 4 (- u) (* -10 v)) v))
         (d (/ (+ (* 1.708 v)(* -1.481 u) 0.404) v)))
    (list c d)))

;; perform von Kries color adaptation calculation
(define (adapted-uv ref-uv test-uv reflected-uv)
  (let* ((cd-r (uv->cd ref-uv))
         (cr   (car cd-r))
         (dr   (cadr cd-r))
         
         (cd-t (uv->cd test-uv))
         (ct   (car cd-t))
         (dt   (cadr cd-t))

         (cd-ti (uv->cd reflected-uv))
         (cti   (car cd-ti))
         (dti   (cadr cd-ti))

         (denom (+ 16.518 (* 1.481 (/ cr ct) cti) (* -1 (/ dr dt) dti)))
         
         (uci   (/ (+ 10.872 (* 0.404 (/ cr ct) cti) (* -4 (/ dr dt) dti))
                   denom))
                 

         (vci   (/ 5.520
                   denom)))

    (list uci vci)))

;; euclidean distance between two 3-vectors
(define (euclidean-3 a b)
  (let* ((dx (- (car a) (car b)))
         (dy (- (cadr a) (cadr b)))
         (dz (- (caddr a) (caddr b))))
    (Math.sqrt (+ (* dx dx) (* dy dy) (* dz dz)))))

(define debug #f)

(define (calc-cri spectrum)
  ;; put it all together. compute the CRI of a given
  ;; continuous spectrum
  
  (let* ((norm-spectrum     (normalize-spectrum spectrum))
         (test-Yxy          (calc-Yxy norm-spectrum))
         (test-uv           (Yxy->uv test-Yxy))
         (ref-temp-res      (search-T test-uv))
         (ref-temp          (car ref-temp-res))
         (ref-uv            (temp-uv ref-temp))
         (norm-ref-spectrum (normalize-spectrum (make-Bl ref-temp)))
         )

    (define (calc-one tcsi)
      (let* ((sample (R tcsi))

             (ref-reflected     (multiply-spectra sample norm-ref-spectrum))
             (ref-reflected-Yxy (calc-Yxy ref-reflected))
             (ref-UVW           (Yuv->UVW (Yxy->Yuv ref-reflected-Yxy) ref-uv))
             
             (reflected-spectrum (multiply-spectra sample norm-spectrum))
             (reflected-Yxy      (calc-Yxy reflected-spectrum))
             (reflected-Yuv      (Yxy->Yuv reflected-Yxy))
             (Y                  (car reflected-Yuv))
             
             (reflected-uv       (cdr reflected-Yuv))
             (reflected-UVW      (Yuv->UVW (cons Y reflected-uv) ref-uv))
             
             (cat-uv             (adapted-uv ref-uv test-uv reflected-uv))
             (cat-UVW            (Yuv->UVW (cons Y cat-uv) ref-uv))
             (delta-EUVW         (euclidean-3 cat-UVW ref-UVW))
             (Ri                 (+ 100 (* -4.6 delta-EUVW)))
             )
        (if debug
            (dis "TCS " tcsi " reflected-Yxy " reflected-Yxy dnl
                 "TCS " tcsi " reflected-Yuv " reflected-Yuv dnl
                 "TCS " tcsi " cat-uv        " cat-uv dnl
                 "TCS " tcsi " reference-UVW " ref-UVW dnl
                 "TCS " tcsi " reflected-UVW " reflected-UVW dnl
                 "TCS " tcsi " cat-UVW       " cat-UVW dnl
                 "TCS " tcsi " delta-EUVW    " delta-EUVW dnl
                 "R" tcsi " = " Ri dnl
                 
                 ))
        Ri)
      )
      
    (if debug
        (dis "test-Yxy     " test-Yxy dnl
             "test-uv      " test-uv dnl
             "ref-temp-res " ref-temp-res dnl
             "ref-uv       " ref-uv dnl))
    (list ref-temp-res (map calc-one '(1 2 3 4 5 6 7 8 9 10 11 12 13 14)))
    )
  )

(define (calc-Yri spectrum)
  ;; put it all together. compute the Y-ratio-i of a given
  ;; continuous spectrum
  
  (let* ((norm-spectrum     (normalize-spectrum spectrum))
         (test-Yxy          (calc-Yxy norm-spectrum))
         (test-uv           (Yxy->uv test-Yxy))
         (ref-temp-res      (search-T test-uv))
         (ref-temp          (car ref-temp-res))
         (ref-uv            (temp-uv ref-temp))
         (norm-ref-spectrum (normalize-spectrum (make-Bl ref-temp)))
         )

    (define (calc-one tcsi)
      (let* ((sample (R tcsi))

             (ref-reflected      (multiply-spectra sample norm-ref-spectrum))
             (ref-reflected-Yxy  (calc-Yxy ref-reflected))
             
             (reflected-spectrum (multiply-spectra sample norm-spectrum))
             (reflected-Yxy      (calc-Yxy reflected-spectrum))
             (Yri (/ (car reflected-Yxy) (car ref-reflected-Yxy)))               
             )
        Yri)
      )
      
    (if debug
        (dis "test-Yxy     " test-Yxy dnl
             "test-uv      " test-uv dnl
             "ref-temp-res " ref-temp-res dnl
             "ref-uv       " ref-uv dnl))
    (list ref-temp-res (map calc-one '(1 2 3 4 5 6 7 8 9 10 11 12 13 14)))
    )
  )

(define (calc-reflected-Yxy spectrum sample)
  (let* ((norm-spectrum      (normalize-spectrum spectrum))
         (reflected-spectrum (multiply-spectra sample norm-spectrum)))
    (calc-Yxy reflected-spectrum)))

(define *start-selection*  '(1 2 3 4 5 6 7 8 9 10 11 12 13 14))
(define *the-selection*  *start-selection*)
;; careful of off-by one errors

(define (filter-out elem selection)
  (map (lambda(x)(if (equal? x elem) #f x)) selection))


(define (compute-on-selection full-cri)
  (let loop ((p    *the-selection*)
             (q    full-cri)
             (sum         0)
             (n           0)
             (worst     100)
             (the-worst  -1))
    (cond ((null? p)
           (list (/ sum n) worst the-worst))
          ((not (car p))
           (loop (cdr p) (cdr q) sum n worst the-worst))
          (else
           (let ((elem (car q)))
             (loop (cdr p)
                   (cdr q)
                   (+ elem sum)
                   (+ n 1) 
                   (min elem worst)
                   (if (< elem worst) (car p) the-worst)))))))

(define (calc-specs spectrum)
  ;; produce the specs of a spectrum:
  ;; CRI(Ra)
  ;; worst Ri (i \in 1..8)
  ;; theoretical efficacy in lm/W
  ;; vector of CRi for i \in 1 .. 14
  (let* ((full-cri (calc-cri spectrum))
         (ref-temp (caar full-cri))
         (Duv      (cadar full-cri))
         (ri-8     (head 8 (cadr full-cri)))
         (worst-ri (apply min ri-8))
         (efficacy (total-lumens-per-watt spectrum))
         (cri-ra   (/ (apply + ri-8) 8))

         (cri-14   (/ (apply + (cadr full-cri)) 14))
         (worst-14 (apply min (cadr full-cri)))

         (sel-data (compute-on-selection (cadr full-cri)))
          
         )
    (append (list cri-ra worst-ri efficacy)
            full-cri
            (append (list cri-14 worst-14) sel-data))))

(define (trunc-spectrum spectrum lo hi)
  ;; truncate a given spectrum to the wavelengths given
  (lambda(l)
    (cond ((< l lo) 0)
          ((> l hi) 0)
          (else (spectrum l)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Grid-based integration (optional speedup)
;;
;; Instead of ~99 adaptive Romberg integrations per objective
;; evaluation, precompute weight vectors on a fixed 1nm grid and
;; use dot products.  Toggle with *use-grid*.
;;
;; At 1nm spacing, trapezoidal integration of smooth spectra against
;; the CIE functions matches Romberg to >6 significant figures.
;;

(define *use-grid* #f)  ;; #t = grid (fast), #f = Romberg (reference)

;;; grid parameters
(define *grid-lo*   380e-9)   ;; 380 nm (= l0)
(define *grid-hi*   770e-9)   ;; 770 nm (= l1)
(define *grid-step* 1e-9)     ;; 1 nm
(define *grid-n*    391)      ;; number of grid points

;;; pre-tabulated weight vectors (set by init-grid!)
(define *grid-lambdas*     #f)
(define *grid-x*           #f)  ;; CIE x-bar
(define *grid-y*           #f)  ;; CIE y-bar
(define *grid-z*           #f)  ;; CIE z-bar
(define *grid-photoconv*   #f)  ;; CieSpectrum.PhotoConv (K_m * V(lambda))
(define *grid-philips-c*   #f)  ;; Philips cost C(lambda)
(define *grid-tcs-xyz*     #f)  ;; vector of 14 (vx vy vz) triples,
                                ;;   pre-multiplied TCS_j * xyz

;;; TM-30 grid data (set by init-ces-grid!, lazy-loaded with -tm30)
(define *compute-tm30*     #f)  ;; #t when -tm30 flag present
(define *grid-ces-xyz*     #f)  ;; vector of 99 (vx vy vz) triples,
                                ;;   pre-multiplied CES_j * xyz_10deg

;;; vector operations

(define (vdot a b)
  ;; dot product with trapezoidal step => integral approximation
  (let loop ((i 0) (sum 0.0))
    (if (>= i *grid-n*)
        (* sum *grid-step*)
        (loop (+ i 1)
              (+ sum (* (vector-ref a i) (vector-ref b i)))))))

(define (vsum v)
  ;; sum(v) * step => integral of f
  (let loop ((i 0) (sum 0.0))
    (if (>= i *grid-n*)
        (* sum *grid-step*)
        (loop (+ i 1) (+ sum (vector-ref v i))))))

(define (vscale! v factor)
  (let loop ((i 0))
    (if (< i *grid-n*)
        (begin
          (vector-set! v i (* factor (vector-ref v i)))
          (loop (+ i 1))))))

(define (vcopy v)
  (let ((r (make-vector *grid-n*)))
    (let loop ((i 0))
      (if (< i *grid-n*)
          (begin
            (vector-set! r i (vector-ref v i))
            (loop (+ i 1)))))
    r))

;;; initialization — call once before using grid mode

(define (init-grid!)
  (set! *grid-lambdas*   (make-vector *grid-n*))
  (set! *grid-x*         (make-vector *grid-n*))
  (set! *grid-y*         (make-vector *grid-n*))
  (set! *grid-z*         (make-vector *grid-n*))
  (set! *grid-photoconv* (make-vector *grid-n*))
  (set! *grid-philips-c* (make-vector *grid-n*))

  ;; fill CIE functions and Philips cost
  (let loop ((i 0) (lam *grid-lo*))
    (if (< i *grid-n*)
        (begin
          (vector-set! *grid-lambdas* i lam)
          (let ((xyz (CieXyz.Interpolate lam)))
            (vector-set! *grid-x* i (cdr (assoc 'x xyz)))
            (vector-set! *grid-y* i (cdr (assoc 'y xyz)))
            (vector-set! *grid-z* i (cdr (assoc 'z xyz))))
          (vector-set! *grid-photoconv* i (CieSpectrum.PhotoConv lam))
          (vector-set! *grid-philips-c* i (philips-cost lam))
          (loop (+ i 1) (+ lam *grid-step*)))))

  ;; pre-multiply TCS_j(lambda) * xyz at each grid point
  (set! *grid-tcs-xyz* (make-vector 14))
  (let tloop ((j 0))
    (if (< j 14)
        (begin
          (let ((tx (make-vector *grid-n*))
                (ty (make-vector *grid-n*))
                (tz (make-vector *grid-n*)))
            (let iloop ((i 0) (lam *grid-lo*))
              (if (< i *grid-n*)
                  (begin
                    (let ((ri ((R (+ j 1)) lam)))
                      (vector-set! tx i (* ri (vector-ref *grid-x* i)))
                      (vector-set! ty i (* ri (vector-ref *grid-y* i)))
                      (vector-set! tz i (* ri (vector-ref *grid-z* i))))
                    (iloop (+ i 1) (+ lam *grid-step*)))))
            (vector-set! *grid-tcs-xyz* j (list tx ty tz)))
          (tloop (+ j 1)))))

  (dis "Grid initialized: " *grid-n* " points, "
       (* *grid-lo* 1e9) "-" (* *grid-hi* 1e9) " nm" dnl))

;;; sample a spectrum function onto the grid

(define (spectrum->grid f)
  (let ((v (make-vector *grid-n*)))
    (let loop ((i 0) (lam *grid-lo*))
      (if (< i *grid-n*)
          (begin
            (vector-set! v i (f lam))
            (loop (+ i 1) (+ lam *grid-step*)))))
    v))

;;; grid-based blackbody at temperature T (pure Scheme, no M3 calls)

(define (grid-blackbody T)
  (let ((v    (make-vector *grid-n*))
        (hkT  (/ h (* k T)))        ;; h/(kT), precompute
        (2hc2 (/ (* 2 h) (* c c)))) ;; 2h/c^2, precompute
    (let loop ((i 0) (lam *grid-lo*))
      (if (< i *grid-n*)
          (begin
            (let* ((nu   (/ c lam))
                   (x    (* hkT nu))
                   (Bnu  (/ (* 2hc2 nu nu nu) (- (exp x) 1)))
                   (Blam (/ (* Bnu nu nu) c)))
              (vector-set! v i Blam))
            (loop (+ i 1) (+ lam *grid-step*)))))
    v))

;;; grid-based XYZ and Yxy

(define (grid-xyz sgrid)
  (list (vdot sgrid *grid-x*)
        (vdot sgrid *grid-y*)
        (vdot sgrid *grid-z*)))

(define (grid-calc-Yxy sgrid)
  (xyz->Yxy (grid-xyz sgrid)))

;;; grid-based normalize: returns new grid with X+Y+Z = 100
;;; (matches normalize-spectrum which divides by car(calc-Yxy) = X+Y+Z)

(define (grid-normalize sgrid)
  (let* ((xyz (grid-xyz sgrid))
         (sum (+ (car xyz) (cadr xyz) (caddr xyz)))
         (ng  (vcopy sgrid)))
    (vscale! ng (/ 100.0 sum))
    ng))

;;; grid-based reflected XYZ for TCS j (1-indexed)

(define (grid-reflected-xyz sgrid-norm j)
  (let ((txyz (vector-ref *grid-tcs-xyz* (- j 1))))
    (list (vdot sgrid-norm (car   txyz))
          (vdot sgrid-norm (cadr  txyz))
          (vdot sgrid-norm (caddr txyz)))))

;;; grid-based CRI: same algorithm as calc-cri, dot products for integrals

(define (grid-calc-cri sgrid)
  (let* ((norm-sgrid     (grid-normalize sgrid))
         (test-Yxy       (grid-calc-Yxy norm-sgrid))
         (test-uv        (Yxy->uv test-Yxy))
         (ref-temp-res   (search-T test-uv))
         (ref-temp       (car ref-temp-res))
         (ref-uv         (temp-uv ref-temp))
         (bgrid          (grid-blackbody ref-temp))
         (norm-bgrid     (grid-normalize bgrid)))

    (define (calc-one tcsi)
      (let* ((ref-reflected-Yxy  (xyz->Yxy (grid-reflected-xyz norm-bgrid tcsi)))
             (ref-UVW            (Yuv->UVW (Yxy->Yuv ref-reflected-Yxy) ref-uv))

             (reflected-Yxy      (xyz->Yxy (grid-reflected-xyz norm-sgrid tcsi)))
             (reflected-Yuv      (Yxy->Yuv reflected-Yxy))
             (Y                  (car reflected-Yuv))
             (reflected-uv       (cdr reflected-Yuv))
             (reflected-UVW      (Yuv->UVW (cons Y reflected-uv) ref-uv))

             (cat-uv             (adapted-uv ref-uv test-uv reflected-uv))
             (cat-UVW            (Yuv->UVW (cons Y cat-uv) ref-uv))
             (delta-EUVW         (euclidean-3 cat-UVW ref-UVW))
             (Ri                 (+ 100 (* -4.6 delta-EUVW))))
        Ri))

    (list ref-temp-res
          (map calc-one '(1 2 3 4 5 6 7 8 9 10 11 12 13 14)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; TM-30 (IES/CIE 2017) Colour Fidelity and Gamut Metrics
;;
;; Uses 99 CES samples, CIE 1964 10-degree observer, CIECAM02,
;; and CAM02-UCS.  Grid-mode only.
;;

;;; Initialize CES weight vectors (call after init-grid! and loading ces99.scm)

(define (init-ces-grid!)
  ;; Pre-multiply CES_j(lambda) * xyz_10deg at each grid point.
  ;; Uses 10-degree CMFs (*cmf10-x/y/z*) from ces99.scm, not the
  ;; 2-degree CIE functions used for CRI.
  (set! *grid-ces-xyz* (make-vector *ces-count*))
  (let tloop ((j 0))
    (if (< j *ces-count*)
        (begin
          (let ((tx (make-vector *grid-n*))
                (ty (make-vector *grid-n*))
                (tz (make-vector *grid-n*))
                (refl (vector-ref *ces-reflectance* j)))
            (let iloop ((i 0))
              (if (< i *grid-n*)
                  (begin
                    (let ((ri (vector-ref refl i)))
                      (vector-set! tx i (* ri (vector-ref *cmf10-x* i)))
                      (vector-set! ty i (* ri (vector-ref *cmf10-y* i)))
                      (vector-set! tz i (* ri (vector-ref *cmf10-z* i))))
                    (iloop (+ i 1)))))
            (vector-set! *grid-ces-xyz* j (list tx ty tz)))
          (tloop (+ j 1)))))
  (dis "CES grid initialized: " *ces-count* " samples" dnl))

;;; Grid-based XYZ using 10-degree observer (for TM-30)

(define (grid-xyz-10deg sgrid)
  (list (vdot sgrid *cmf10-x*)
        (vdot sgrid *cmf10-y*)
        (vdot sgrid *cmf10-z*)))

;;; Grid-based reflected XYZ for CES j (0-indexed)

(define (grid-ces-reflected-xyz sgrid-norm j)
  (let ((txyz (vector-ref *grid-ces-xyz* j)))
    (list (vdot sgrid-norm (car   txyz))
          (vdot sgrid-norm (cadr  txyz))
          (vdot sgrid-norm (caddr txyz)))))

;;; Grid-based normalize using 10-degree observer

(define (grid-normalize-10deg sgrid)
  (let* ((Y (vdot sgrid *cmf10-y*))
         (ng (vcopy sgrid)))
    (vscale! ng (/ 100.0 Y))
    ng))

;;; atan2 — mscheme's atan ignores 2nd arg, so implement manually

(define (atan2 y x)
  (cond ((> x 0)         (atan (/ y x)))
        ((and (< x 0) (>= y 0)) (+ (atan (/ y x)) pi))
        ((and (< x 0) (< y 0))  (- (atan (/ y x)) pi))
        ((and (= x 0) (> y 0))  (/ pi 2))
        ((and (= x 0) (< y 0))  (/ pi -2))
        (else 0.0)))  ;; x=0, y=0: undefined, return 0

;;; 3x3 matrix-vector multiply: M * v, M is row-major list of 9 elements

(define (mat3x3-mul m v)
  (let ((x (car v)) (y (cadr v)) (z (caddr v)))
    (list (+ (* (list-ref m 0) x) (* (list-ref m 1) y) (* (list-ref m 2) z))
          (+ (* (list-ref m 3) x) (* (list-ref m 4) y) (* (list-ref m 5) z))
          (+ (* (list-ref m 6) x) (* (list-ref m 7) y) (* (list-ref m 8) z)))))

;;; CIECAM02 constants

;; CAT02 chromatic adaptation matrix
(define *M-CAT02*
  '( 0.7328  0.4296 -0.1624
    -0.7036  1.6975  0.0061
     0.003   0.0136  0.9834))

;; CAT02 inverse
(define *M-CAT02-inv*
  '( 1.09612382 -0.278869    0.18274518
     0.45436904  0.47353315  0.0720978
    -0.00962761 -0.00569803  1.01532564))

;; Hunt-Pointer-Estevez matrix (XYZ -> HPE cone space)
(define *M-HPE*
  '( 0.38971  0.68898 -0.07868
    -0.22981  1.18340  0.04641
     0.00000  0.00000  1.00000))

;; Combined M_HPE * M_CAT02^-1
(define *M-HPC*
  '( 0.7409791   0.21802516  0.04100575
     0.28535329  0.62420157  0.09044513
    -0.00962761 -0.00569803  1.01532564))

;; CIE 2017 viewing conditions
(define *cam-LA*  100)   ;; adapting luminance (cd/m2)
(define *cam-Yb*   20)   ;; background relative luminance
(define *cam-c*   0.69)  ;; surround factor (average)
(define *cam-Nc*  1.0)   ;; chromatic induction factor
(define *cam-F*   1.0)   ;; degree of adaptation factor

;;; CIECAM02 forward model
;;; Given XYZ of sample and XYZ_w of white point, returns (J M h-radians)

(define (ciecam02-forward XYZ XYZ-w)
  (let* (;; --- viewing condition parameters ---
         (LA    *cam-LA*)
         (Yb    *cam-Yb*)
         (k     (/ 1 (+ (* 5 LA) 1)))
         (FL    (+ (* 0.2 k k k k LA)
                   (* 0.1 (- 1 (* k k k k))
                      (Math.pow (* 5 LA) (/ 1 3)))))
         (n     (/ Yb 100.0))   ;; Yb/Yw where Yw=100 (normalized)
         (Nbb   (/ 0.725 (Math.pow n 0.2)))
         (Ncb   Nbb)
         (z     (+ 1.48 (Math.sqrt n)))

         ;; --- chromatic adaptation ---
         ;; degree of adaptation
         (D     (* *cam-F*
                   (- 1 (* (/ 1 3.6)
                            (exp (/ (+ (- LA) 42) 92))))))

         ;; white point adapted RGB
         (RGB-w  (mat3x3-mul *M-CAT02* XYZ-w))
         (Rw (car RGB-w)) (Gw (cadr RGB-w)) (Bw (caddr RGB-w))

         ;; adapted white RGB (D-scaled)
         (Dr (+ (* D (/ 100.0 Rw)) (- 1 D)))
         (Dg (+ (* D (/ 100.0 Gw)) (- 1 D)))
         (Db (+ (* D (/ 100.0 Bw)) (- 1 D)))

         ;; --- adapt the sample ---
         (RGB-s  (mat3x3-mul *M-CAT02* XYZ))
         (Rc (* (car RGB-s)   Dr))
         (Gc (* (cadr RGB-s)  Dg))
         (Bc (* (caddr RGB-s) Db))

         ;; --- adapt the white ---
         (Rwc (* Rw Dr))
         (Gwc (* Gw Dg))
         (Bwc (* Bw Db))

         ;; --- HPE cone responses ---
         (HPE-s  (mat3x3-mul *M-HPC* (list Rc Gc Bc)))
         (Rp (car HPE-s)) (Gp (cadr HPE-s)) (Bp (caddr HPE-s))

         (HPE-w  (mat3x3-mul *M-HPC* (list Rwc Gwc Bwc)))
         (Rpw (car HPE-w)) (Gpw (cadr HPE-w)) (Bpw (caddr HPE-w)))

    ;; --- nonlinear compression ---
    (define (compress x)
      (let* ((sign (if (>= x 0) 1 -1))
             (ax   (abs x))
             (p    (Math.pow (/ (* FL ax) 100.0) 0.42)))
        (* sign (/ (* 400 p) (+ 27.13 p)) )))

    (let* ((Ra (+ (compress Rp) 0.1))
           (Ga (+ (compress Gp) 0.1))
           (Ba (+ (compress Bp) 0.1))

           (Raw (+ (compress Rpw) 0.1))
           (Gaw (+ (compress Gpw) 0.1))
           (Baw (+ (compress Bpw) 0.1))

           ;; --- opponent channels ---
           (a  (+ Ra (* -12.0 (/ Ga 11.0)) (/ Ba 11.0)))
           (b  (/ (+ Ra Ga (* -2 Ba)) 9.0))

           ;; --- hue angle ---
           (h-rad (atan2 b a))
           (h-deg (let ((d (* (/ 180.0 pi) h-rad)))
                    (if (< d 0) (+ d 360) d)))

           ;; --- achromatic response ---
           (A  (* (+ (* 2 Ra) Ga (/ Ba 20.0) -0.305) Nbb))
           (Aw (* (+ (* 2 Raw) Gaw (/ Baw 20.0) -0.305) Nbb))

           ;; --- lightness ---
           (J  (* 100 (Math.pow (/ A Aw) (* *cam-c* z))))

           ;; --- eccentricity factor ---
           (et (/ (+ (cos (+ h-rad 2.0)) 3.8) 4.0))

           ;; --- chroma ---
           (t  (/ (* (/ 50000.0 13.0) *cam-Nc* Ncb et (Math.sqrt (+ (* a a) (* b b))))
                  (+ Ra Ga (* (/ 21.0 20.0) Ba))))
           (C  (* (Math.pow t 0.9)
                  (Math.pow (/ J 100.0) 0.5)
                  (Math.pow (- 1.64 (Math.pow 0.29 n)) 0.73)))

           ;; --- colorfulness ---
           (M  (* C (Math.pow FL 0.25))))

      (list J M h-rad))))

;;; CAM02-UCS transform: (J, M, h-rad) -> (J', a', b')
;;; Luo et al. (2006), CAM02-UCS coefficients: K_L=1.0, c1=0.007, c2=0.0228

(define (cam02-ucs JMh)
  (let* ((J (car JMh))
         (M (cadr JMh))
         (h (caddr JMh))
         (Jp (/ (* 1.7 J) (+ 1 (* 0.007 J))))
         (Mp (/ (log (+ 1 (* 0.0228 M))) 0.0228))
         (ap (* Mp (cos h)))
         (bp (* Mp (sin h))))
    (list Jp ap bp)))

;;; TM-30 Rf formula: softcapped fidelity index
;;; R_f = 10 * ln(exp((100 - 6.73 * deltaE') / 10) + 1)

(define (delta-E-to-Rf dE)
  (* 10 (log (+ (exp (/ (- 100 (* 6.73 dE)) 10)) 1))))

;;; Shoelace formula for polygon area from 16 hue-bin centroids

(define (shoelace-area pts)
  ;; pts is a vector of 16 (a' . b') pairs
  (let ((n (vector-length pts)))
    (let loop ((i 0) (sum 0.0))
      (if (>= i n)
          (/ (abs sum) 2.0)
          (let* ((j    (modulo (+ i 1) n))
                 (pi-v (vector-ref pts i))
                 (pj   (vector-ref pts j)))
            (loop (+ i 1)
                  (+ sum (- (* (car pi-v) (cdr pj))
                            (* (car pj) (cdr pi-v))))))))))

;;; CIE D-illuminant series: construct daylight spectrum from CCT
;;; SD(λ) = S0(λ) + M1·S1(λ) + M2·S2(λ)
;;; where M1,M2 are computed from chromaticity (xD,yD) on daylight locus

(define (grid-d-illuminant CCT)
  (let* (;; CCT -> xD (piecewise polynomial, CIE 015:2004)
         (T2 (* CCT CCT))
         (T3 (* T2 CCT))
         (xD (if (<= CCT 7000)
                  (+ 0.244063 (/ (* 0.09911e3) CCT)
                     (/ 2.9678e6 T2) (/ -4.607e9 T3))
                  (+ 0.23704  (/ (* 0.24748e3) CCT)
                     (/ 1.9018e6 T2) (/ -2.0064e9 T3))))
         ;; yD from Judd's quadratic
         (yD (+ (* -3.000 xD xD) (* 2.870 xD) -0.275))
         ;; M1, M2 coefficients
         (M  (+ 0.0241 (* 0.2562 xD) (* -0.7341 yD)))
         (M1 (/ (+ -1.3515 (* -1.7703 xD) (* 5.9114 yD)) M))
         (M2 (/ (+ 0.0300  (* -31.4424 xD) (* 30.0717 yD)) M))
         ;; construct spectrum
         (v (make-vector *grid-n*)))
    (let loop ((i 0))
      (if (< i *grid-n*)
          (begin
            (vector-set! v i (+ (vector-ref *d-basis-S0* i)
                                (* M1 (vector-ref *d-basis-S1* i))
                                (* M2 (vector-ref *d-basis-S2* i))))
            (loop (+ i 1)))))
    v))

;;; TM-30 reference illuminant: Planckian/D blend per CIE 2017
;;;   CCT < 4000:  Planckian
;;;   4000..5000:  blend (normalize by Y, then mix)
;;;   CCT > 5000:  D-series

(define (grid-tm30-reference CCT)
  (cond
    ((< CCT 4000) (grid-blackbody CCT))
    ((> CCT 5000) (grid-d-illuminant CCT))
    (else
     ;; blend zone: normalize both by Y (10-deg), then linear mix
     (let* ((planck  (grid-blackbody CCT))
            (daylit  (grid-d-illuminant CCT))
            (Yp      (vdot planck *cmf10-y*))
            (Yd      (vdot daylit *cmf10-y*))
            (m       (/ (- CCT 4000) 1000.0))  ;; 0 at 4000K, 1 at 5000K
            (result  (make-vector *grid-n*)))
       (let loop ((i 0))
         (if (< i *grid-n*)
             (begin
               (vector-set! result i
                 (+ (* (- 1.0 m) (/ (vector-ref planck i) Yp))
                    (* m          (/ (vector-ref daylit i) Yd))))
               (loop (+ i 1)))))
       result))))

;;; Main TM-30 calculation (grid-mode only)
;;; Returns: (Rf Rg Rcs-vector ref-temp-res)

(define (grid-calc-tm30 sgrid)
  (let* ((norm-sgrid     (grid-normalize-10deg sgrid))
         ;; CCT from 2-degree observer (per CIE 2017 spec)
         (test-Yxy       (grid-calc-Yxy (grid-normalize sgrid)))
         (test-uv        (Yxy->uv test-Yxy))
         (ref-temp-res   (search-T test-uv))
         (ref-temp       (car ref-temp-res))
         (bgrid          (grid-tm30-reference ref-temp))
         (norm-bgrid     (grid-normalize-10deg bgrid))

         ;; white point XYZ under test and reference (10-degree)
         (XYZ-w-test (grid-xyz-10deg norm-sgrid))
         (XYZ-w-ref  (grid-xyz-10deg norm-bgrid))

         ;; per-sample results
         (n-bins 16)
         (bin-width (/ (* 2 pi) n-bins))  ;; 22.5 degrees in radians

         ;; accumulators for hue bins
         (bin-count     (make-vector n-bins 0))
         (bin-dE-sum    (make-vector n-bins 0.0))
         (bin-at-sum    (make-vector n-bins 0.0))  ;; test a' sum
         (bin-bt-sum    (make-vector n-bins 0.0))  ;; test b' sum
         (bin-ar-sum    (make-vector n-bins 0.0))  ;; ref a' sum
         (bin-br-sum    (make-vector n-bins 0.0))  ;; ref b' sum
         (dE-total      0.0))

    ;; process each CES
    (let ces-loop ((j 0))
      (if (< j *ces-count*)
          (let* (;; reflected XYZ under test and reference
                 (xyz-test (grid-ces-reflected-xyz norm-sgrid j))
                 (xyz-ref  (grid-ces-reflected-xyz norm-bgrid j))

                 ;; CIECAM02 forward
                 (JMh-test (ciecam02-forward xyz-test XYZ-w-test))
                 (JMh-ref  (ciecam02-forward xyz-ref  XYZ-w-ref))

                 ;; CAM02-UCS
                 (Jpapbp-test (cam02-ucs JMh-test))
                 (Jpapbp-ref  (cam02-ucs JMh-ref))

                 ;; delta E in J'a'b' space
                 (dJp (- (car   Jpapbp-test) (car   Jpapbp-ref)))
                 (dap (- (cadr  Jpapbp-test) (cadr  Jpapbp-ref)))
                 (dbp (- (caddr Jpapbp-test) (caddr Jpapbp-ref)))
                 (dE  (Math.sqrt (+ (* dJp dJp) (* dap dap) (* dbp dbp))))

                 ;; assign to hue bin based on reference hue angle
                 (h-ref (caddr JMh-ref))
                 (h-pos (if (< h-ref 0) (+ h-ref (* 2 pi)) h-ref))
                 (bin   (min (- n-bins 1)
                             (truncate (floor (/ h-pos bin-width))))))

            ;; accumulate
            (set! dE-total (+ dE-total dE))
            (vector-set! bin-count  bin (+ (vector-ref bin-count  bin) 1))
            (vector-set! bin-dE-sum bin (+ (vector-ref bin-dE-sum bin) dE))
            (vector-set! bin-at-sum bin (+ (vector-ref bin-at-sum bin) (cadr  Jpapbp-test)))
            (vector-set! bin-bt-sum bin (+ (vector-ref bin-bt-sum bin) (caddr Jpapbp-test)))
            (vector-set! bin-ar-sum bin (+ (vector-ref bin-ar-sum bin) (cadr  Jpapbp-ref)))
            (vector-set! bin-br-sum bin (+ (vector-ref bin-br-sum bin) (caddr Jpapbp-ref)))

            (ces-loop (+ j 1)))))

    ;; compute Rf (average fidelity)
    (let* ((avg-dE (/ dE-total *ces-count*))
           (Rf     (delta-E-to-Rf avg-dE))

           ;; compute bin centroids and Rg
           (test-centroids (make-vector n-bins))
           (ref-centroids  (make-vector n-bins))
           (Rcs            (make-vector n-bins 0.0)))

      ;; compute centroids per bin
      (let bin-loop ((b 0))
        (if (< b n-bins)
            (let ((cnt (vector-ref bin-count b)))
              (if (> cnt 0)
                  (let ((at (/ (vector-ref bin-at-sum b) cnt))
                        (bt (/ (vector-ref bin-bt-sum b) cnt))
                        (ar (/ (vector-ref bin-ar-sum b) cnt))
                        (br (/ (vector-ref bin-br-sum b) cnt)))
                    (vector-set! test-centroids b (cons at bt))
                    (vector-set! ref-centroids  b (cons ar br))
                    ;; Rcs,hj = (test chroma - ref chroma) / ref chroma
                    (let ((Ct (Math.sqrt (+ (* at at) (* bt bt))))
                          (Cr (Math.sqrt (+ (* ar ar) (* br br)))))
                      (if (> Cr 0.001)
                          (vector-set! Rcs b (/ (- Ct Cr) Cr)))))
                  (begin
                    ;; empty bin: use angle midpoint at zero chroma
                    (let* ((mid-h (+ (* b bin-width) (/ bin-width 2.0))))
                      (vector-set! test-centroids b (cons 0.0 0.0))
                      (vector-set! ref-centroids  b (cons 0.0 0.0)))))
              (bin-loop (+ b 1)))))

      (let* ((test-area (shoelace-area test-centroids))
             (ref-area  (shoelace-area ref-centroids))
             (Rg        (if (> ref-area 1e-10)
                            (* 100 (/ test-area ref-area))
                            100.0)))

        (list Rf Rg Rcs ref-temp-res)))))

;;; grid-based luminous and efficacy quantities

(define (grid-calc-lumens sgrid)
  (vdot sgrid *grid-photoconv*))

(define (grid-visible-power sgrid)
  (vsum sgrid))

(define (grid-visible-lumens-per-watt sgrid)
  (/ (grid-calc-lumens sgrid) (grid-visible-power sgrid)))

(define (grid-philips-power sgrid)
  (let loop ((i 0) (sum 0.0))
    (if (>= i *grid-n*)
        (* sum *grid-step*)
        (loop (+ i 1)
              (+ sum (* (vector-ref sgrid i)
                        (vector-ref *grid-philips-c* i)))))))

(define (grid-philips-lumens-per-watt sgrid)
  (/ (grid-calc-lumens sgrid) (grid-philips-power sgrid)))

;;; grid-based calc-specs (same return format as calc-specs)

(define (grid-calc-specs sgrid)
  (let* ((full-cri (grid-calc-cri sgrid))
         (ref-temp (caar full-cri))
         (Duv      (cadar full-cri))
         (ri-8     (head 8 (cadr full-cri)))
         (worst-ri (apply min ri-8))
         ;; parametric spectra are truncated to visible range,
         ;; so total-lpw = visible-lpw
         (efficacy (grid-visible-lumens-per-watt sgrid))
         (cri-ra   (/ (apply + ri-8) 8))
         (cri-14   (/ (apply + (cadr full-cri)) 14))
         (worst-14 (apply min (cadr full-cri)))
         (sel-data (compute-on-selection (cadr full-cri)))
         (tm30-data (if *compute-tm30*
                        (grid-calc-tm30 sgrid)
                        #f)))
    (append (list cri-ra worst-ri efficacy)
            full-cri
            (append (list cri-14 worst-14) sel-data)
            (if tm30-data (list tm30-data) '()))))

;;; current sampled grid (set by specs-func when *use-grid* is #t)
(define *current-sgrid* #f)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Optimization code for use with COBYLA
;;

(define pspec '())
(define cur-dims '())
(define cur-base-spectrum '())

(define  (setup-pspec! dims base-spectrum)
  (set! cur-dims dims)
  (set! cur-base-spectrum base-spectrum)
  (set! pspec (ParametricSpectrum.New
               l0 l1 ;; optimization range
               dims   ;; how many dimensions
               base-spectrum ;; start func
               )
        )
  )

(define *p* '())

(define (set-zero!)
  (set! *p* (ParametricSpectrum.ZeroP pspec)))

;;;;;;;;;;;;;;;;;;;;

(define *test-spectrum* (trunc-spectrum (make-Bl 2700) l0 l1))

;;(setup-pspec! 20 test-spectrum)
;;(set-zero!)

;;;;;;;;;;;;;;;;;;;;

(define w '())

(define (setup-w!)
  (set! w (unwrap-lrfunc (ParametricSpectrum.GetFunc pspec *p*))))

(setup-w!)

(define (setup-problem! spectrum dims)
  (setup-pspec! dims spectrum)
  (set-zero!)
  (setup-w!)
  'ok
  )

(define (subdivide-problem!)
  (let ((new-dims (- (* cur-dims 2) 1))
        (new-p    (ParametricSpectrum.Subdivide *p*)))
    (setup-pspec! new-dims cur-base-spectrum)
    (set! *p* (ParametricSpectrum.Subdivide *p*))
    (setup-w!) 
    'ok
    ))
                  
(define (specs-func new-p)
  (ParametricSpectrum.SetVec *p* new-p)
  (if *use-grid*
      (begin
        (set! *current-sgrid* (spectrum->grid w))
        (grid-calc-specs *current-sgrid*))
      (calc-specs w)))

(define *target-cct*      2700)
(define *min-cri-ra*        82)
(define *min-r9*          -100)
(define *num-constraints*    6)

(define (specs->target specs)
  (let ((lpm    (caddr specs))
        (r9     (nth (car (cddddr specs)) 8))
        (cri    (car specs))
        (crmin  (cadr specs))
        (cct    (caar (cdddr specs)))
        (Duv    (cadar (cdddr specs)))
        )
    (dis specs dnl)
    (list (- (caddr specs))            ;; target var : efficacy
          (- cri   *min-cri-ra*)       ;; cri constraint
          (- r9    *min-r9*)           ;; cri constraint
          (- crmin (- *min-cri-ra* 10));; worst-component constraint
          (- cct (- *target-cct* 50))  ;; cct >= 2650
          (- (+ *target-cct* 50) cct)  ;; cct <= 2750
          (* 1000 (- 0.012 Duv))       ;; Duv <= 0.012 (weight 1000)
          )
        )
  )
      
(define (run rhobeg spec-evaluator)
  (let ((opt-func (lambda(p) (ParametricSpectrum.Scheme2Vec
                              (spec-evaluator (specs-func p))))))

                                   
    (COBYLA_M3.Minimize *p*                ;; state vector
                        *num-constraints*  
                        (make-lrvectorfield-obj opt-func)
                        rhobeg
                        0.0002 ;; rhoend
                        1000   ;; max steps
                        2      ;; iprint
                        )
    )
  )


(define (specs->target-r9 specs)
  (let ((lpm    (caddr specs))
        (r9     (nth (car (cddddr specs)) 8))
        (cri    (car specs))
        (crmin  (cadr specs))
        (cct    (caar (cdddr specs)))
        (Duv    (cadar (cdddr specs)))
        )
    (dis specs dnl)
    (list r9                          ;; target var : low R9
          (- cri   82)                ;; cri constraint
          (- crmin 72)                ;; worst-component constraint
          (- cct (- *target-cct* 50)) ;; cct >= 2650
          (- (+ *target-cct* 50) cct) ;; cct <= 2750
          (* 1000 (- 0.012 Duv))      ;; Duv <= 0.012 (weight 1000)
          (- lpm 90)                  ;; lpm >= 45 * 2
          )
        )
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Inverse problem: maximize R9 subject to CRI >= 80 and efficacy >= X
;;

(define *min-efficacy* 300)

(define (specs->max-r9 specs)
  (let ((lpm    (caddr specs))
        (r9     (nth (car (cddddr specs)) 8))
        (cri    (car specs))
        (crmin  (cadr specs))
        (cct    (caar (cdddr specs)))
        (Duv    (cadar (cdddr specs)))
        )
    (dis specs dnl)
    (list (- r9)                         ;; target: maximize R9
          (- cri   *min-cri-ra*)         ;; CRI(Ra) >= min-cri-ra
          (- crmin (- *min-cri-ra* 10))  ;; worst Ri >= min-cri-ra - 10
          (- cct (- *target-cct* 50))    ;; cct >= target - 50
          (- (+ *target-cct* 50) cct)    ;; cct <= target + 50
          (* 1000 (- 0.012 Duv))         ;; Duv <= 0.012
          (- lpm *min-efficacy*)         ;; efficacy >= min-efficacy
          )
        )
  )

;;
;; Philips-corrected version: uses the phosphor-converted LED cost model
;; in the efficacy constraint.  Instead of requiring uncorrected LER >= X,
;; we require Philips-corrected LER >= X.  This penalizes red-heavy spectra
;; since longer-wavelength photons cost more to produce via Stokes shift.
;;
;; Note: w is the global spectrum function, updated by specs-func before
;; this is called.
;;
(define (specs->max-r9-philips specs)
  (let ((r9     (nth (car (cddddr specs)) 8))
        (cri    (car specs))
        (crmin  (cadr specs))
        (cct    (caar (cdddr specs)))
        (Duv    (cadar (cdddr specs)))
        (lpm-philips (if *use-grid*
                        (grid-philips-lumens-per-watt *current-sgrid*)
                        (philips-lumens-per-watt w)))
        )
    (dis specs " Philips-LER=" lpm-philips dnl)
    (list (- r9)                             ;; target: maximize R9
          (- cri   *min-cri-ra*)             ;; CRI(Ra) >= min-cri-ra
          (- (+ *min-cri-ra* 2) cri)         ;; CRI(Ra) <= min-cri-ra + 2  (pin CRI)
          (- crmin (- *min-cri-ra* 10))      ;; worst Ri >= min-cri-ra - 10
          (- cct (- *target-cct* 50))        ;; cct >= target - 50
          (- (+ *target-cct* 50) cct)        ;; cct <= target + 50
          (* 1000 (- 0.012 Duv))             ;; Duv <= 0.012
          (- lpm-philips *min-efficacy*)     ;; Philips-corrected efficacy >= min
          )
        )
  )

(define (run-max-r9! cct min-cri min-efficacy)
  (set! *min-efficacy* min-efficacy)
  (run-example-iters! cct min-cri -100 *default-iters* specs->max-r9
                      (string-append "_maxR9_eff"
                                     (stringify (round min-efficacy))))
  )

(define (run-max-r9-philips! cct min-cri min-efficacy)
  (set! *num-constraints* 7)  ;; one extra: CRI upper bound
  (set! *min-efficacy* min-efficacy)
  (run-example-iters! cct min-cri -100 *default-iters* specs->max-r9-philips
                      (string-append "_maxR9P_eff"
                                     (stringify (round min-efficacy))))
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Inverse problem: maximize TM-30 Rf subject to CRI and efficacy
;;
;; Requires -grid -tm30 flags.  TM-30 data is at index 10 of specs:
;;   (list-ref specs 10) = (Rf Rg Rcs ref-temp-res)
;;

(define (specs->max-Rf specs)
  (let ((Rf     (car (list-ref specs 10)))
        (cri    (car specs))
        (crmin  (cadr specs))
        (cct    (caar (cdddr specs)))
        (Duv    (cadar (cdddr specs)))
        (lpm    (caddr specs))
        )
    (dis specs " Rf=" Rf dnl)
    (list (- Rf)                             ;; target: maximize Rf
          (- cri   *min-cri-ra*)             ;; CRI(Ra) >= min-cri-ra
          (- crmin (- *min-cri-ra* 10))      ;; worst Ri >= min-cri-ra - 10
          (- cct (- *target-cct* 50))        ;; cct >= target - 50
          (- (+ *target-cct* 50) cct)        ;; cct <= target + 50
          (* 1000 (- 0.012 Duv))             ;; Duv <= 0.012
          (- lpm *min-efficacy*)             ;; efficacy >= min-efficacy
          )
        )
  )

(define (specs->max-Rf-philips specs)
  (let ((Rf     (car (list-ref specs 10)))
        (cri    (car specs))
        (crmin  (cadr specs))
        (cct    (caar (cdddr specs)))
        (Duv    (cadar (cdddr specs)))
        (lpm-philips (if *use-grid*
                        (grid-philips-lumens-per-watt *current-sgrid*)
                        (philips-lumens-per-watt w)))
        )
    (dis specs " Philips-LER=" lpm-philips " Rf=" Rf dnl)
    (list (- Rf)                             ;; target: maximize Rf
          (- cri   *min-cri-ra*)             ;; CRI(Ra) >= min-cri-ra
          (- (+ *min-cri-ra* 2) cri)         ;; CRI(Ra) <= min-cri-ra + 2  (pin CRI)
          (- crmin (- *min-cri-ra* 10))      ;; worst Ri >= min-cri-ra - 10
          (- cct (- *target-cct* 50))        ;; cct >= target - 50
          (- (+ *target-cct* 50) cct)        ;; cct <= target + 50
          (* 1000 (- 0.012 Duv))             ;; Duv <= 0.012
          (- lpm-philips *min-efficacy*)     ;; Philips-corrected efficacy >= min
          )
        )
  )

(define (run-max-Rf! cct min-cri min-efficacy)
  (set! *min-efficacy* min-efficacy)
  (run-example-iters! cct min-cri -100 *default-iters* specs->max-Rf
                      (string-append "_maxRf_eff"
                                     (stringify (round min-efficacy))))
  )

(define (run-max-Rf-philips! cct min-cri min-efficacy)
  (set! *num-constraints* 7)  ;; one extra: CRI upper bound
  (set! *min-efficacy* min-efficacy)
  (run-example-iters! cct min-cri -100 *default-iters* specs->max-Rf-philips
                      (string-append "_maxRfP_eff"
                                     (stringify (round min-efficacy))))
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Maximize efficacy subject to ALL R_i >= threshold (R1-R14)
;;
;; Uses worst-14 (= min of all 14 Ri values) at specs position 6.
;; No CRI constraint needed since floor on worst Ri implies CRI floor.
;;

(define *min-worst-ri* 50)

(define (specs->max-eff-allri specs)
  (let ((lpm      (caddr specs))
        (worst-14 (list-ref specs 6))
        (cct      (caar (cdddr specs)))
        (Duv      (cadar (cdddr specs)))
        )
    (dis specs " worst-14=" worst-14 dnl)
    (list (- lpm)                            ;; target: maximize efficacy
          (- worst-14 *min-worst-ri*)        ;; all Ri >= threshold
          (- cct (- *target-cct* 50))        ;; cct >= target - 50
          (- (+ *target-cct* 50) cct)        ;; cct <= target + 50
          (* 1000 (- 0.012 Duv))             ;; Duv <= 0.012
          )
        )
  )

(define (specs->max-eff-allri-philips specs)
  (let ((worst-14 (list-ref specs 6))
        (cct      (caar (cdddr specs)))
        (Duv      (cadar (cdddr specs)))
        (lpm-philips (if *use-grid*
                        (grid-philips-lumens-per-watt *current-sgrid*)
                        (philips-lumens-per-watt w)))
        )
    (dis specs " worst-14=" worst-14 " Philips-LER=" lpm-philips dnl)
    (list (- lpm-philips)                    ;; target: maximize Philips efficacy
          (- worst-14 *min-worst-ri*)        ;; all Ri >= threshold
          (- cct (- *target-cct* 50))        ;; cct >= target - 50
          (- (+ *target-cct* 50) cct)        ;; cct <= target + 50
          (* 1000 (- 0.012 Duv))             ;; Duv <= 0.012
          )
        )
  )

(define (run-max-eff-allri! cct min-worst-ri)
  (set! *num-constraints* 4)
  (set! *min-worst-ri* min-worst-ri)
  (run-example-iters! cct 0 -100 *default-iters* specs->max-eff-allri
                      (string-append "_allRi"
                                     (stringify (round min-worst-ri))))
  )

(define (run-max-eff-allri-philips! cct min-worst-ri)
  (set! *num-constraints* 4)
  (set! *min-worst-ri* min-worst-ri)
  (run-example-iters! cct 0 -100 *default-iters* specs->max-eff-allri-philips
                      (string-append "_allRiP"
                                     (stringify (round min-worst-ri))))
  )

(define (m3-opt-r9 p)
  (ParametricSpectrum.Scheme2Vec
   (specs->target-r9 (specs-func p))))

(define (run-r9)
  (COBYLA_M3.Minimize *p* 6 (make-lrvectorfield-obj m3-opt-r9) 1 0.00001 10000 2)
  )

(define (plot-current-state pfx)
  (let* ((nm (string-append 
             (stringify *target-cct*)
             "_CRI"
             (stringify *min-cri-ra*)
             pfx
             "_"
             (stringify cur-dims)
             ))
         (wr (FileWr.Open (string-append nm ".res"))))

    (dis (stringify (if *use-grid*
                        (grid-calc-specs *current-sgrid*)
                        (calc-specs w))) dnl dnl wr)

    (dis (stringify (ParametricSpectrum.Vec2Scheme *p*)) dnl wr)
    
    (plot (normalize-spectrum w)
          l0 l1
          (string-append "w_" nm ".dat")
          391)))



(define (run-example-iters! cct min-cri min-r9 repcnt spec-eval pfx)
  (dis "*****  START RUN cct=" cct " CRI(ra)>=" min-cri " " pfx "  *****" dnl)
  (define *start-dims*   2)
  (define *start-rhobeg* 4)
  (define rhobeg *start-rhobeg*)

  ;;(set! *test-spectrum* (make-lrfunc-obj (trunc-spectrum (make-Bl cct) l0 l1)))
  (set! *test-spectrum* (ParametricSpectrum.MakeBlackbodyInWavelength cct l0 l1))
  (set! *target-cct* cct)
  (set! *min-cri-ra* min-cri)
  (set! *min-r9* min-r9)
  
  (define (repeat)

    (set! rhobeg (max (/ rhobeg 2) *rhobeg-min*))

    (subdivide-problem!)
    (dis "subdividing cur-dims = " cur-dims dnl)
    (run rhobeg spec-eval)
    (plot-current-state pfx)
    
    (dis "done at dims " cur-dims dnl)

    )
  
  (plot (normalize-spectrum (unwrap-lrfunc *test-spectrum*))
        l0 l1
        (string-append "base_" (stringify cct) ".dat")
        391)
    
  (dis "setting up dims = " *start-dims* dnl)
  (setup-problem! *test-spectrum* *start-dims*)
  (run rhobeg spec-eval) ;; big step
  (plot-current-state pfx)
  (dis "done at dims " cur-dims dnl)

  (let loop ((k repcnt))
    (if (<= k 0) 'ok
        (begin (repeat) (loop (- k 1)))))
  )

(define (plot-the-samples)
  (define *min-sample*  1)
  (define *max-sample* 14)
  (let loop ((i *min-sample*))
    (if (> i *max-sample*)
        'ok
        (begin
          (plot (R i) l0 l1 (string-append "R" (stringify i) ".dat") 391)
          (loop (+ i 1))
          )
        )
    )
  )

;; Default iteration count: 7 gives 2→129. Override with -iters N.
(define *default-iters* 7)

;; Override rhobeg halving: -rhobeg-min N keeps rhobeg >= N at all levels.
;; Default 0 means standard halving (4, 2, 1, 0.5, ...).
(define *rhobeg-min* 0)

(define (run-example! cct min-cri min-r9)
  (dis "run-example " min-cri " " min-r9 dnl)
  (run-example-iters! cct min-cri min-r9 *default-iters* specs->target
                      (string-append              "_R9="
                                                  (stringify min-r9))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Gaussian peak parameterization
;;
;; Instead of N-point piecewise-linear grid, represent the spectrum as
;; a sum of K Gaussian peaks:
;;   S(lambda) = sum_k A_k * exp(-(lambda - mu_k)^2 / (2 * sigma_k^2))
;;
;; Parameters: (mu_1 sigma_1 A_1  mu_2 sigma_2 A_2  ... mu_K sigma_K A_K)
;; All in nm (not meters) for COBYLA compatibility (similar scales).
;; Amplitudes are in arbitrary power units.
;;

(define *gauss-K* 3)          ;; number of Gaussian peaks
(define *gauss-sgrid* #f)     ;; current Gaussian spectrum grid (391 points)
(define *gauss-params* #f)    ;; current Gaussian parameter vector (LRVector)

;; Build a 391-point spectrum grid from K Gaussian peaks.
;; params is a Scheme list: (mu1_nm sigma1_nm A1 mu2_nm sigma2_nm A2 ...)
(define (gauss-params->grid params)
  (let ((v (make-vector *grid-n* 0.0)))
    (let peak-loop ((p params) (k 0))
      (if (or (null? p) (>= k *gauss-K*))
          v
          (let* ((mu-nm    (car p))
                 (sigma-nm (abs (cadr p)))   ;; force sigma positive
                 (amp      (abs (caddr p)))  ;; force amplitude non-negative
                 (mu-m     (* mu-nm 1e-9))
                 (sigma-m  (* (max sigma-nm 1.0) 1e-9)) ;; floor sigma at 1nm
                 (inv2s2   (/ 1.0 (* 2.0 sigma-m sigma-m))))
            (let grid-loop ((i 0) (lam *grid-lo*))
              (if (< i *grid-n*)
                  (begin
                    (let* ((dl  (- lam mu-m))
                           (g   (* amp (exp (* -1.0 dl dl inv2s2)))))
                      (vector-set! v i (+ (vector-ref v i) g)))
                    (grid-loop (+ i 1) (+ lam *grid-step*)))))
            (peak-loop (cdddr p) (+ k 1)))))))

;; Evaluate specs from Gaussian parameters (Scheme list).
;; This bypasses ParametricSpectrum entirely.
(define (gauss-specs-func param-list)
  (set! *gauss-sgrid* (gauss-params->grid param-list))
  (set! *current-sgrid* *gauss-sgrid*)
  (grid-calc-specs *gauss-sgrid*))

;; Version that takes an M3 LRVector (as COBYLA passes), converts to list
(define (gauss-specs-func-from-vec vec)
  (let ((param-list (ParametricSpectrum.Vec2Scheme vec)))
    (ParametricSpectrum.SetVec *gauss-params* vec) ;; keep state in sync
    (gauss-specs-func param-list)))

;; Objective for Gaussian mode: maximize efficacy subject to CRI/CCT/Duv.
;; Same constraint structure as specs->target.
(define (gauss-specs->target specs)
  (let ((lpm    (caddr specs))
        (r9     (nth (car (cddddr specs)) 8))
        (cri    (car specs))
        (crmin  (cadr specs))
        (cct    (caar (cdddr specs)))
        (Duv    (cadar (cdddr specs)))
        )
    (dis specs dnl)
    (list (- lpm)                         ;; target: maximize efficacy
          (- cri   *min-cri-ra*)          ;; CRI(Ra) >= min
          (- r9    *min-r9*)              ;; R9 >= min
          (- crmin (- *min-cri-ra* 10))   ;; worst Ri >= min-10
          (- cct (- *target-cct* 50))     ;; CCT >= target-50
          (- (+ *target-cct* 50) cct)     ;; CCT <= target+50
          (* 1000 (- 0.012 Duv))          ;; Duv <= 0.012
          )))

;; Write output files for Gaussian mode
(define (gauss-plot-state pfx)
  (let* ((nm (string-append
              (stringify *target-cct*)
              "_CRI"
              (stringify *min-cri-ra*)
              pfx
              "_gauss" (stringify *gauss-K*)))
         (wr (FileWr.Open (string-append nm ".res"))))

    (dis (stringify (grid-calc-specs *gauss-sgrid*)) dnl dnl wr)
    (dis (stringify (ParametricSpectrum.Vec2Scheme *gauss-params*)) dnl wr)
    (Wr.Close wr)

    ;; write spectrum data file for gnuplot
    (let ((dwr (FileWr.Open (string-append "w_" nm ".dat")))
          (norm-sgrid (grid-normalize *gauss-sgrid*)))
      (let loop ((i 0) (lam *grid-lo*))
        (if (< i *grid-n*)
            (begin
              (Wr.PutText dwr (string-append (stringify (* lam 1e9))
                                              " "
                                              (stringify (vector-ref norm-sgrid i))
                                              dnl))
              (loop (+ i 1) (+ lam *grid-step*)))
            (Wr.Close dwr)))))))

;; Default initial peaks for K=3: blue, green, red
(define (gauss-initial-params K)
  (cond ((= K 1) '(555.0  25.0 1.0))
        ((= K 2) '(480.0  20.0 1.0  600.0  20.0 1.0))
        ((= K 3) '(450.0  20.0 1.0  540.0  20.0 1.0  610.0  20.0 1.0))
        ((= K 4) '(430.0  15.0 1.0  490.0  15.0 1.0  560.0  15.0 1.0  620.0  15.0 1.0))
        ((= K 5) '(430.0  15.0 1.0  470.0  15.0 1.0  530.0  15.0 1.0
                   580.0  15.0 1.0  630.0  15.0 1.0))
        (else
         ;; spread K peaks evenly from 420 to 660 nm
         (let loop ((k 0) (result '()))
           (if (>= k K)
               (reverse result)
               (let ((center (+ 420.0 (* k (/ 240.0 (- K 1))))))
                 (loop (+ k 1)
                       (cons 1.0 (cons 20.0 (cons center result))))))))))

;; Main Gaussian optimization driver
(define (run-gauss! cct min-cri min-r9 K)
  (set! *gauss-K* K)
  (set! *target-cct* cct)
  (set! *min-cri-ra* min-cri)
  (set! *min-r9* min-r9)
  (set! *num-constraints* 6)

  (dis "***** GAUSSIAN MODE K=" K " cct=" cct " CRI>=" min-cri
       " R9>=" min-r9 " *****" dnl)

  ;; Create initial state vector from default peaks
  (let* ((init-params (gauss-initial-params K))
         (init-vec    (ParametricSpectrum.Scheme2Vec init-params))
         (n-params    (* 3 K)))

    (set! *gauss-params* init-vec)

    ;; Build the COBYLA callback.
    ;; COBYLA passes the state as an LRVector through the M3/Scheme bridge.
    ;; The lambda receives (*unused* vec) — the first arg is the surrogate.
    (let ((opt-func
           (lambda (p)
             (ParametricSpectrum.Scheme2Vec
              (gauss-specs->target (gauss-specs-func-from-vec p))))))

      ;; Run COBYLA: rhobeg=10 is ~10nm for centers, ~10nm for sigmas,
      ;; and ~10 for amplitudes — reasonable starting step.
      (dis "Starting COBYLA with " n-params " parameters (K=" K " peaks)" dnl)
      (COBYLA_M3.Minimize *gauss-params*
                          *num-constraints*
                          (make-lrvectorfield-obj opt-func)
                          10.0    ;; rhobeg
                          0.01    ;; rhoend
                          3000    ;; maxfun
                          2       ;; iprint
                          )
      (gauss-plot-state "")

      ;; Second pass with tighter convergence
      (dis "Refining (pass 2)..." dnl)
      (COBYLA_M3.Minimize *gauss-params*
                          *num-constraints*
                          (make-lrvectorfield-obj opt-func)
                          2.0     ;; rhobeg
                          0.001   ;; rhoend
                          3000    ;; maxfun
                          2       ;; iprint
                          )
      (gauss-plot-state "_refined")

      ;; Print final results
      (let* ((final-params (ParametricSpectrum.Vec2Scheme *gauss-params*))
             (final-specs  (gauss-specs-func final-params)))
        (dis dnl "===== GAUSSIAN OPTIMIZATION RESULTS =====" dnl)
        (dis "K = " K " peaks" dnl)
        (let print-peaks ((p final-params) (k 1))
          (if (not (null? p))
              (begin
                (dis "Peak " k ": center=" (car p) " nm, sigma=" (cadr p)
                     " nm, amplitude=" (caddr p) dnl)
                (print-peaks (cdddr p) (+ k 1)))))
        (dis "Efficacy = " (caddr final-specs) " lm/W" dnl)
        (dis "CRI(Ra)  = " (car final-specs) dnl)
        (dis "CCT      = " (caar (cdddr final-specs)) " K" dnl)
        (dis "R9       = " (nth (car (cddddr final-specs)) 8) dnl)
        (dis "=============================================" dnl)
        ))))

(define pp
  (obj-method-wrap (LibertyUtils.DoParseParams) 'ParseParams.T))

;; Grid-based integration toggle (use before any -run* flag)
(if (pp 'keywordPresent "-grid")
    (begin
      (set! *use-grid* #t)
      (init-grid!)))

;; TM-30 toggle: load CES data and initialize CES grid
;; Requires -grid to have been set first
;; Note: MScheme load resolves relative to CWD, not to the loaded file.
;; Sweep scripts should symlink or copy ces99.scm into CWD, or run from src/.
(if (pp 'keywordPresent "-tm30")
    (begin
      (set! *compute-tm30* #t)
      (load "ces99.scm")
      (init-ces-grid!)))

;; Override subdivision depth: -iters N (default 7 → 129 params)
;; 8 → 257, 9 → 513
(if (pp 'keywordPresent "-iters")
    (set! *default-iters* (pp 'getNextInt 1 20)))

;; Override minimum rhobeg: -rhobeg-min X (default 0 = standard halving)
;; Prevents rhobeg from shrinking below X at high subdivision levels.
(if (pp 'keywordPresent "-rhobeg-min")
    (set! *rhobeg-min* (pp 'getNextLongReal 0 100)))

(if (pp 'keywordPresent "-run")
    (begin
      (define run-cct (pp 'getNextLongReal      0 1e6))
      (define run-cri (pp 'getNextLongReal -10000 100))
      (define run-r9  (pp 'getNextLongReal -10000 100))
      (run-example! run-cct run-cri run-r9)
      (exit)
      )
    )
      
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;



(define (specs->cri-sel-target specs)
  (let ((lpm    (caddr specs))
        (r9     (nth (car (cddddr specs)) 8))
        (cri    (car specs))
        (crmin  (cadr specs))
        (cct    (caar (cdddr specs)))
        (Duv    (cadar (cdddr specs)))
        (sel-cri      (nth specs 7)) ;; cri over selected TCS
        (sel-wrst-cri (nth specs 8)) ;; worst cri over selected TCS
        )
    (dis specs dnl)
    (list (- (caddr specs))                    ;; target var : efficacy
          (- sel-cri   *min-cri-ra*)           ;; cri constraint
          (- sel-wrst-cri (- *min-cri-ra* 10)) ;; worst cri
          1
          (- cct (- *target-cct* 50))          ;; cct >= *target-cct* - 50
          (- (+ *target-cct* 50) cct)          ;; cct <= *target-cct* + 50
          (* 1000 (- 0.012 Duv))               ;; Duv <= 0.012 (weight 1000)
          )
        )
  )

(define (run-multi! cct cri)
  (set! *the-selection* *start-selection*)
  (let loop ((pfx "DROP"))
    (run-example-iters! cct cri -100 6 specs->cri-sel-target (string-append pfx "_X"))

    (if (not (= 0 (length (filter (lambda(x)x) *the-selection*))))
        (let ((worst-axis (nth (calc-specs w) 9)))
          (set! *the-selection* (filter-out worst-axis *the-selection*))
          (loop (string-append pfx "_" (stringify worst-axis)))
          )
        'ok
        )
    )
  )

(if (pp 'keywordPresent "-run-drop")
    (begin
      (define run-cct (pp 'getNextLongReal    0 1e6))
      (define run-cri (pp 'getNextLongReal -100 100))
      (run-multi! run-cct run-cri)
      (exit)
      )
    )

;; Inverse problem: maximize R9 at given efficacy constraint
;; Usage: photopic -run-maxr9 <cct> <min-cri> <min-efficacy>
;;   e.g., photopic -run-maxr9 2700 80 350
(if (pp 'keywordPresent "-run-maxr9")
    (begin
      (define run-cct     (pp 'getNextLongReal    0 1e6))
      (define run-cri     (pp 'getNextLongReal -100 100))
      (define run-eff     (pp 'getNextLongReal    0 700))
      (run-max-r9! run-cct run-cri run-eff)
      (exit)
      )
    )

;; Inverse problem with Philips phosphor-converted LED loss model
;; Efficacy constraint uses Philips-corrected LER (Stokes + QE losses)
;; Usage: photopic -run-maxr9-philips <cct> <min-cri> <min-efficacy>
;;   e.g., photopic -run-maxr9-philips 2700 80 300
(if (pp 'keywordPresent "-run-maxr9-philips")
    (begin
      (define run-cct     (pp 'getNextLongReal    0 1e6))
      (define run-cri     (pp 'getNextLongReal -100 100))
      (define run-eff     (pp 'getNextLongReal    0 700))
      (run-max-r9-philips! run-cct run-cri run-eff)
      (exit)
      )
    )

;; Maximize TM-30 Rf at given efficacy constraint (uncorrected LER)
;; Requires -grid -tm30 flags
;; Usage: photopic -grid -tm30 -run-maxRf <cct> <min-cri> <min-efficacy>
;;   e.g., photopic -grid -tm30 -run-maxRf 2700 80 350
(if (pp 'keywordPresent "-run-maxRf")
    (begin
      (define run-cct     (pp 'getNextLongReal    0 1e6))
      (define run-cri     (pp 'getNextLongReal -100 100))
      (define run-eff     (pp 'getNextLongReal    0 700))
      (run-max-Rf! run-cct run-cri run-eff)
      (exit)
      )
    )

;; Maximize TM-30 Rf with Philips phosphor-converted LED loss model
;; Requires -grid -tm30 flags
;; Usage: photopic -grid -tm30 -run-maxRf-philips <cct> <min-cri> <min-efficacy>
;;   e.g., photopic -grid -tm30 -run-maxRf-philips 2700 80 300
(if (pp 'keywordPresent "-run-maxRf-philips")
    (begin
      (define run-cct     (pp 'getNextLongReal    0 1e6))
      (define run-cri     (pp 'getNextLongReal -100 100))
      (define run-eff     (pp 'getNextLongReal    0 700))
      (run-max-Rf-philips! run-cct run-cri run-eff)
      (exit)
      )
    )

;; All-Ri constraint mode: maximize efficacy subject to ALL R1-R14 >= threshold
;; Usage: photopic -grid -run-allri <cct> <min-worst-ri>
;;   e.g., photopic -grid -run-allri 1800 50
(if (pp 'keywordPresent "-run-allri")
    (begin
      (define allri-cct  (pp 'getNextLongReal    0 1e6))
      (define allri-min  (pp 'getNextLongReal -100 100))
      (run-max-eff-allri! allri-cct allri-min)
      (exit)
      )
    )

;; Philips-corrected version
;; Usage: photopic -grid -run-allri-philips <cct> <min-worst-ri>
(if (pp 'keywordPresent "-run-allri-philips")
    (begin
      (define allri-cct  (pp 'getNextLongReal    0 1e6))
      (define allri-min  (pp 'getNextLongReal -100 100))
      (run-max-eff-allri-philips! allri-cct allri-min)
      (exit)
      )
    )

;; Gaussian peak parameterization mode
;; Spectrum as sum of K Gaussians: tests whether peak widths from grid
;; optimizer are intrinsic (CRI-driven) or artifacts of grid parameterization.
;; Requires -grid flag.
;; Usage: photopic -grid -run-gauss <cct> <min-cri> <min-r9> <K>
;;   e.g., photopic -grid -run-gauss 2700 60 -100 3
(if (pp 'keywordPresent "-run-gauss")
    (begin
      (define gauss-cct  (pp 'getNextLongReal      0 1e6))
      (define gauss-cri  (pp 'getNextLongReal -10000 100))
      (define gauss-r9   (pp 'getNextLongReal -10000 100))
      (define gauss-k    (truncate (pp 'getNextLongReal 1 20)))
      (run-gauss! gauss-cct gauss-cri gauss-r9 gauss-k)
      (exit)
      )
    )

