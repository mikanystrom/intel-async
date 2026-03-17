;;
;; Compute system efficacy for a blackbody-spectrum LED at various CCTs.
;;
;; Uses the existing photopic infrastructure:
;;   visible-lumens-per-watt  -- LER over visible range only
;;   philips-lumens-per-watt  -- Philips-corrected (Stokes + QE)
;;
;; Then multiplies by the remaining loss chain:
;;   blue LED WPE, phosphor backscatter, thermal droop, driver, optical
;;

;; Loss chain scenarios (beyond Stokes/QE already in Philips model)
;;
;; Best production today:
(define *wpe-prod*         0.75)  ;; blue LED wall-plug efficiency
(define *backscatter-prod* 0.92)  ;; phosphor backscatter/reabsorption
(define *thermal-prod*     0.90)  ;; thermal droop at junction temp
(define *driver-prod*      0.92)  ;; AC-DC driver efficiency
(define *optical-prod*     0.90)  ;; diffuser/lens/fixture losses

;; Best lab / near-future:
(define *wpe-lab*          0.84)
(define *backscatter-lab*  0.95)
(define *thermal-lab*      0.93)
(define *driver-lab*       0.95)
(define *optical-lab*      0.95)

;; Theoretical limit (DOE roadmap):
(define *wpe-limit*        0.90)
(define *backscatter-limit* 0.98)
(define *thermal-limit*    0.97)
(define *driver-limit*     0.98)
(define *optical-limit*    0.97)

(define (chain-prod)
  (* *wpe-prod* *backscatter-prod* *thermal-prod*
     *driver-prod* *optical-prod*))

(define (chain-lab)
  (* *wpe-lab* *backscatter-lab* *thermal-lab*
     *driver-lab* *optical-lab*))

(define (chain-limit)
  (* *wpe-limit* *backscatter-limit* *thermal-limit*
     *driver-limit* *optical-limit*))

(define (fmt x w d)
  ;; format a number to width w with d decimal places
  (Fmt.LongReal x 'Fix d #f w 'Right #\space))

(define (compute-row T)
  (let* ((bb  (make-Bl T))
         (ler (visible-lumens-per-watt bb))
         (plr (philips-lumens-per-watt bb))
         (sys-prod  (* plr (chain-prod)))
         (sys-lab   (* plr (chain-lab)))
         (sys-limit (* plr (chain-limit))))
    (dis (fmt T 6 0) " "
         (fmt ler 8 1) " "
         (fmt plr 9 1) "  "
         (fmt sys-prod 8 1) " "
         (fmt sys-lab 9 1) " "
         (fmt sys-limit 9 1)
         dnl)))

(dis dnl)
(dis "Blackbody-Spectrum LED: System Efficacy at Various CCTs" dnl)
(dis "=======================================================" dnl)
(dis dnl)
(dis "  CCT   Vis LER  Phil LER    Prod.   Best Lab   Theor." dnl)
(dis "  (K)   (lm/W)    (lm/W)   (lm/W)    (lm/W)    (lm/W)" dnl)
(dis "------  -------  --------  -------  ---------  --------" dnl)

(for-each compute-row '(2100 2400 2700 3000 3500 4000 5000 5500 6500))

(dis dnl)
(dis "Loss chain multipliers:" dnl)
(dis "  Best production:  " (fmt (chain-prod) 6 4)
     " (" (fmt (* 100 (- 1 (chain-prod))) 4 1) "% total loss)" dnl)
(dis "  Best lab:         " (fmt (chain-lab) 6 4)
     " (" (fmt (* 100 (- 1 (chain-lab))) 4 1) "% total loss)" dnl)
(dis "  Theoretical limit:" (fmt (chain-limit) 6 4)
     " (" (fmt (* 100 (- 1 (chain-limit))) 4 1) "% total loss)" dnl)

(dis dnl)
(dis "Government standards (minimum system lm/W):" dnl)
(dis "  EU Ecodesign 2021 Class F (min):   70 lm/W" dnl)
(dis "  EU Ecodesign 2021 Class E:         85 lm/W" dnl)
(dis "  EU Ecodesign 2021 Class D:        110 lm/W" dnl)
(dis "  EU new Class C (~2025):           120 lm/W" dnl)
(dis "  US DOE general service (2028):    120 lm/W" dnl)
(dis "  California Title 24 JA8:           68 lm/W (also CRI>=90, R9>=50)" dnl)

(dis dnl)
(dis "Philips model parameters: pump=" (fmt (* *pump-nm* 1e9) 3 0)
     "nm, QE=" (fmt *pump-qe* 4 2) dnl)

(exit)
