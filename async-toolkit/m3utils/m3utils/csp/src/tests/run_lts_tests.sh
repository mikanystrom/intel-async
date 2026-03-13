#!/bin/sh
# LTS extraction acceptance test suite
#
# Tests both:
#   (A) The new LTS extraction from pre-compiled text9 files
#   (B) Regression: the existing cspc compiler pipeline still produces
#       correct text9 from .scm parse trees
#
# Tests are batched into 3 cspc invocations to minimize startup overhead:
#   Batch 1: Parts A + D + E (text9-based: extraction, invariants, .aut)
#   Batch 2: Part B (compiler regression: recompile and compare)
#   Batch 3: Part C (full pipeline: extract-process-lts!)
#
# Usage: sh run_lts_tests.sh
#
# Prerequisites:
#   - cspc binary built (M3UTILS/csp/$TARGET/cspc)
#   - Existing text9 files in simplecsp/cast/ (golden references)

set -u

# --- Environment -----------------------------------------------------------

M3UTILS="${M3UTILS:-/Users/mika/cm3/intel-async/async-toolkit/m3utils/m3utils}"
CM3DIR="${CM3DIR:-/Users/mika/cm3/install/bin}"
TESTDIR="$(cd "$(dirname "$0")" && pwd)"
CSPDIR="$M3UTILS/csp"
CASTDIR="$CSPDIR/simplecsp/cast"

# Determine cm3 target
if [ -f "$M3UTILS/.bindir" ]; then
    TARGET="$(cat "$M3UTILS/.bindir")"
else
    TARGET="$("$M3UTILS/m3arch.sh")"
fi
CSPC="${CSPC:-$CSPDIR/$TARGET/cspc}"

export PATH="$CM3DIR:$CSPDIR/cspparse/$TARGET:$PATH"

PASS=0
FAIL=0
TOTAL=0
MAX_RETRIES=2

# --- Helpers ----------------------------------------------------------------

run_cspc() {
    _dir="$1"
    _script="$2"
    _try=0
    while [ $_try -le $MAX_RETRIES ]; do
        _OUTPUT=$(cd "$_dir" && M3UTILS="$M3UTILS" "$CSPC" -scm "$_script" 2>&1)
        _RC=$?
        if [ $_RC -ne 133 ]; then
            return
        fi
        _try=$((_try + 1))
        sleep 1
    done
}

check_result() {
    # check_result TAG EXPECTED_VALUE
    # Looks up "TAG=VALUE" in $_OUTPUT
    _tag="$1"
    _expected="$2"
    _actual=$(echo "$_OUTPUT" | grep "^${_tag}=" | sed "s/^${_tag}=//")
    [ "$_actual" = "$_expected" ]
}

pass() {
    printf "  PASS  %s\n" "$1"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

fail() {
    printf "  FAIL  %s\n" "$1"
    if [ $# -gt 1 ]; then
        printf "        %s\n" "$2"
    fi
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
}

echo "=== LTS Extraction Acceptance Test Suite ==="

# ============================================================================
#  BATCH 1: Parts A + D + E — all text9-based tests in one cspc invocation
# ============================================================================
#
# Single Scheme script that loads all text9 files, extracts LTSs, checks
# state/transition counts, invariants, and writes .aut files.

echo ""
echo "--- Batch 1: text9 extraction + invariants + .aut format ---"

TDIR1=$(mktemp -d)

cat > "$TDIR1/driver.scm" <<ENDSCM
(load (string-append (Env.Get "M3UTILS") "/csp/src/setup.scm"))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Test framework
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (check-lts name lts expected-states expected-trans expected-actions)
  ;; Part A: state/transition counts and actions
  (let ((ns (length (lts-states lts)))
        (nt (length (lts-transitions lts)))
        (init (lts-initial lts)))
    (dis "A." name ".states=" (number->string ns) dnl)
    (dis "A." name ".trans=" (number->string nt) dnl)
    (dis "A." name ".initial=" (symbol->string init) dnl)
    (dis "A." name ".ok="
         (if (and (= ns expected-states)
                  (= nt expected-trans)
                  (eq? init 'START))
             "yes" "no") dnl))

  ;; Part D: structural invariants
  (let ((ok-init (if (memq (lts-initial lts) (lts-states lts)) #t #f))
        (ok-src  #t)
        (ok-dst  #t)
        (ok-act  #t)
        (ok-dup  #t))
    (for-each
     (lambda (t)
       (if (not (memq (car t) (lts-states lts))) (set! ok-src #f))
       (if (not (memq (caddr t) (lts-states lts))) (set! ok-dst #f))
       (let ((act (cadr t)))
         (if (and (not (eq? act 'tau))
                  (not (member act (lts-alphabet lts))))
             (set! ok-act #f))))
     (lts-transitions lts))
    (let check ((ts (lts-transitions lts)))
      (if (not (null? ts))
          (begin
            (if (member (car ts) (cdr ts)) (set! ok-dup #f))
            (check (cdr ts)))))
    (dis "D." name ".ok="
         (if (and ok-init ok-src ok-dst ok-act ok-dup) "yes" "no") dnl)))

(define (check-aut name lts aut-file expected-states expected-trans)
  ;; Part E: write .aut and report
  (write-lts-aut lts aut-file)
  (dis "E." name ".ok=yes" dnl)
  (dis "E." name ".file=" aut-file dnl)
  (dis "E." name ".states=" (number->string expected-states) dnl)
  (dis "E." name ".trans=" (number->string expected-trans) dnl))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Load all text9 files and run checks
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define castdir "$CASTDIR")

;; 1. simple.HELLOWORLD
(define lts-hw (extract-lts-from-text9-file
  (string-append castdir "/simple.HELLOWORLD.il/build/src/m3__simple_46_HELLOWORLD.text9.scm")))
(check-lts "helloworld" lts-hw 2 1 '())
(check-aut "helloworld" lts-hw "$TDIR1/hw.aut" 2 1)

;; 2. first.PROC(true)
(define lts-ft (extract-lts-from-text9-file
  (string-append castdir "/first.SYSTEM.il/build/src/m3__first_46_PROC_40_true_41_.text9.scm")))
(check-lts "first_proc_true" lts-ft 5 5 '((send R) (recv L)))
(check-aut "first_proc_true" lts-ft "$TDIR1/ft.aut" 5 5)

;; 3. first.PROC(false)
(define lts-ff (extract-lts-from-text9-file
  (string-append castdir "/first.SYSTEM.il/build/src/m3__first_46_PROC_40_false_41_.text9.scm")))
(check-lts "first_proc_false" lts-ff 4 4 '((send R) (recv L)))
(check-aut "first_proc_false" lts-ff "$TDIR1/ff.aut" 4 4)

;; 4. collatz.WORKER
(define lts-cw (extract-lts-from-text9-file
  (string-append castdir "/collatz.COLLATZ_20_44.il/build/src/m3__collatz_46_WORKER_40_20_44_44_41_.text9.scm")))
(check-lts "collatz_worker" lts-cw 6 9 '((recv STRT) (send STATUS)))

;; 5. collatz.MANAGER
(define lts-cm (extract-lts-from-text9-file
  (string-append castdir "/collatz.COLLATZ_20_44.il/build/src/m3__collatz_46_MANAGER_40_20_41_.text9.scm")))
(check-lts "collatz_manager" lts-cm 4 5 '((send STRT) (recv STATUS)))

;; 6. collatz.SMERGE
(define lts-cs (extract-lts-from-text9-file
  (string-append castdir "/collatz.COLLATZ_20_44.il/build/src/m3__collatz_46_SMERGE.text9.scm")))
(check-lts "collatz_smerge" lts-cs 7 12 '((recv L) (send R)))

;; 7. collatz.STARTSPLIT
(define lts-ss (extract-lts-from-text9-file
  (string-append castdir "/collatz.COLLATZ_20_44.il/build/src/m3__collatz_46_STARTSPLIT_40_0_41_.text9.scm")))
(check-lts "collatz_startsplit" lts-ss 6 7 '((recv L) (send R)))

(dis "BATCH1-DONE" dnl)
(exit)
ENDSCM

run_cspc "$TDIR1" driver.scm

if [ $_RC -ne 0 ]; then
    echo "  FAIL  batch 1 cspc exited with rc=$_RC"
    FAIL=$((FAIL + 15))
    TOTAL=$((TOTAL + 15))
else
    # Part A: extraction tests (7 tests)
    for name in helloworld first_proc_true first_proc_false \
                collatz_worker collatz_manager collatz_smerge collatz_startsplit; do
        if check_result "A.${name}.ok" "yes"; then
            pass "A:$name"
        else
            states=$(echo "$_OUTPUT" | grep "^A.${name}.states=" | sed "s/^A.${name}.states=//")
            trans=$(echo "$_OUTPUT" | grep "^A.${name}.trans=" | sed "s/^A.${name}.trans=//")
            fail "A:$name" "states=$states trans=$trans"
        fi
    done

    # Part D: invariant tests (5 tests — subset of the text9 files)
    for name in helloworld first_proc_true collatz_worker collatz_smerge collatz_startsplit; do
        if check_result "D.${name}.ok" "yes"; then
            pass "D:$name"
        else
            fail "D:$name" "structural invariant failed"
        fi
    done

    # Part E: .aut format tests (3 tests)
    for name in helloworld first_proc_true first_proc_false; do
        if ! check_result "E.${name}.ok" "yes"; then
            fail "E:$name" ".aut export failed"
            continue
        fi

        aut_file=$(echo "$_OUTPUT" | grep "^E.${name}.file=" | sed "s/^E.${name}.file=//")
        exp_states=$(echo "$_OUTPUT" | grep "^E.${name}.states=" | sed "s/^E.${name}.states=//")
        exp_trans=$(echo "$_OUTPUT" | grep "^E.${name}.trans=" | sed "s/^E.${name}.trans=//")

        if [ ! -f "$aut_file" ]; then
            fail "E:$name" ".aut file not created"
            continue
        fi

        # Check header
        header=$(head -1 "$aut_file")
        expected_header="des (0, $exp_trans, $exp_states)"
        if [ "$header" != "$expected_header" ]; then
            fail "E:$name" "header: expected '$expected_header', got '$header'"
            continue
        fi

        # Check transition line count
        ntrans_lines=$(tail -n +2 "$aut_file" | wc -l | tr -d ' ')
        if [ "$ntrans_lines" != "$exp_trans" ]; then
            fail "E:$name" "expected $exp_trans transition lines, got $ntrans_lines"
            continue
        fi

        # Check format of transition lines
        bad_lines=$(tail -n +2 "$aut_file" | grep -cv '^([0-9]*, ".*", [0-9]*)$' || true)
        if [ "$bad_lines" != "0" ]; then
            fail "E:$name" "$bad_lines lines don't match .aut format"
            continue
        fi

        # Check initial state has outgoing transitions
        if ! tail -n +2 "$aut_file" | grep -q '^(0,'; then
            fail "E:$name" "initial state 0 has no outgoing transitions"
            continue
        fi

        pass "E:$name"
    done
fi

rm -rf "$TDIR1"

# ============================================================================
#  BATCH 2: Part B — compiler regression (3 recompile tests, 1 cspc invocation)
# ============================================================================

echo ""
echo "--- Batch 2: compiler regression (recompile and compare text9) ---"

TDIR2=$(mktemp -d)

cat > "$TDIR2/driver.scm" <<ENDSCM
(load (string-append (Env.Get "M3UTILS") "/csp/src/setup.scm"))

(define castdir "$CASTDIR")

(define (recompile-check name scm-file golden-file expected-states expected-trans)
  (loaddata0! scm-file)
  (loaddata1!)
  (compile!)

  (define golden (load-text9 golden-file))

  (define blocks-match (= (length text9) (length golden)))

  (define lts-actual (extract-lts text9 '()))
  (define lts-golden (extract-lts golden '()))

  (define as (length (lts-states lts-actual)))
  (define at (length (lts-transitions lts-actual)))
  (define gs (length (lts-states lts-golden)))
  (define gt (length (lts-transitions lts-golden)))

  (dis "B." name ".ok="
       (if (and blocks-match (= as gs) (= at gt)
                (= as expected-states) (= at expected-trans))
           "yes" "no") dnl)
  (dis "B." name ".states=" (number->string as) dnl)
  (dis "B." name ".trans=" (number->string at) dnl))

(recompile-check "helloworld"
  (string-append castdir "/simple.HELLOWORLD.il/simple_46_HELLOWORLD.scm")
  (string-append castdir "/simple.HELLOWORLD.il/build/src/m3__simple_46_HELLOWORLD.text9.scm")
  2 1)

(recompile-check "first_proc_true"
  (string-append castdir "/first.SYSTEM.il/first_46_PROC_40_true_41_.scm")
  (string-append castdir "/first.SYSTEM.il/build/src/m3__first_46_PROC_40_true_41_.text9.scm")
  5 5)

(recompile-check "first_proc_false"
  (string-append castdir "/first.SYSTEM.il/first_46_PROC_40_false_41_.scm")
  (string-append castdir "/first.SYSTEM.il/build/src/m3__first_46_PROC_40_false_41_.text9.scm")
  4 4)

(dis "BATCH2-DONE" dnl)
(exit)
ENDSCM

run_cspc "$TDIR2" driver.scm

if [ $_RC -ne 0 ]; then
    echo "  FAIL  batch 2 cspc exited with rc=$_RC"
    FAIL=$((FAIL + 3))
    TOTAL=$((TOTAL + 3))
else
    for name in helloworld first_proc_true first_proc_false; do
        if check_result "B.${name}.ok" "yes"; then
            pass "B:$name"
        else
            states=$(echo "$_OUTPUT" | grep "^B.${name}.states=" | sed "s/^B.${name}.states=//")
            trans=$(echo "$_OUTPUT" | grep "^B.${name}.trans=" | sed "s/^B.${name}.trans=//")
            fail "B:$name" "states=$states trans=$trans"
        fi
    done
fi

rm -rf "$TDIR2"

# ============================================================================
#  BATCH 3: Part C — full pipeline (3 tests, 1 cspc invocation)
# ============================================================================

echo ""
echo "--- Batch 3: full pipeline (extract-process-lts!) ---"

TDIR3=$(mktemp -d)

cat > "$TDIR3/driver.scm" <<ENDSCM
(load (string-append (Env.Get "M3UTILS") "/csp/src/setup.scm"))

(define castdir "$CASTDIR")

(define (pipeline-check name scm-file expected-states expected-trans)
  (define lts (extract-process-lts! scm-file))
  (define ns (length (lts-states lts)))
  (define nt (length (lts-transitions lts)))
  (dis "C." name ".ok="
       (if (and (= ns expected-states) (= nt expected-trans)) "yes" "no") dnl)
  (dis "C." name ".states=" (number->string ns) dnl)
  (dis "C." name ".trans=" (number->string nt) dnl))

(pipeline-check "helloworld"
  (string-append castdir "/simple.HELLOWORLD.il/simple_46_HELLOWORLD.scm")
  2 1)

(pipeline-check "first_proc_true"
  (string-append castdir "/first.SYSTEM.il/first_46_PROC_40_true_41_.scm")
  5 5)

(pipeline-check "first_proc_false"
  (string-append castdir "/first.SYSTEM.il/first_46_PROC_40_false_41_.scm")
  4 4)

(dis "BATCH3-DONE" dnl)
(exit)
ENDSCM

run_cspc "$TDIR3" driver.scm

if [ $_RC -ne 0 ]; then
    echo "  FAIL  batch 3 cspc exited with rc=$_RC"
    FAIL=$((FAIL + 3))
    TOTAL=$((TOTAL + 3))
else
    for name in helloworld first_proc_true first_proc_false; do
        if check_result "C.${name}.ok" "yes"; then
            pass "C:$name"
        else
            states=$(echo "$_OUTPUT" | grep "^C.${name}.states=" | sed "s/^C.${name}.states=//")
            trans=$(echo "$_OUTPUT" | grep "^C.${name}.trans=" | sed "s/^C.${name}.trans=//")
            fail "C:$name" "states=$states trans=$trans"
        fi
    done
fi

rm -rf "$TDIR3"

# ============================================================================
#  Summary
# ============================================================================

echo ""
echo "=== Results: $PASS/$TOTAL passed ==="

if [ $FAIL -ne 0 ]; then
    echo "($FAIL FAILED)"
    exit 1
fi
