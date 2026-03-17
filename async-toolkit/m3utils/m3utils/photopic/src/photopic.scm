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
         (sel-data (compute-on-selection (cadr full-cri))))
    (append (list cri-ra worst-ri efficacy)
            full-cri
            (append (list cri-14 worst-14) sel-data))))

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
  (run-example-iters! cct min-cri -100 7 specs->max-r9
                      (string-append "_maxR9_eff"
                                     (stringify (round min-efficacy))))
  )

(define (run-max-r9-philips! cct min-cri min-efficacy)
  (set! *num-constraints* 7)  ;; one extra: CRI upper bound
  (set! *min-efficacy* min-efficacy)
  (run-example-iters! cct min-cri -100 7 specs->max-r9-philips
                      (string-append "_maxR9P_eff"
                                     (stringify (round min-efficacy))))
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

    (dis (stringify (calc-specs w)) dnl dnl wr)

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

    (set! rhobeg (/ rhobeg 2))
    
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

(define (run-example! cct min-cri min-r9)
  (dis "run-example " min-cri " " min-r9 dnl)
  (run-example-iters! cct min-cri min-r9 7 specs->target
                      (string-append              "_R9="
                                                  (stringify min-r9))))

(define pp
  (obj-method-wrap (LibertyUtils.DoParseParams) 'ParseParams.T))

;; Grid-based integration toggle (use before any -run* flag)
(if (pp 'keywordPresent "-grid")
    (begin
      (set! *use-grid* #t)
      (init-grid!)))

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

