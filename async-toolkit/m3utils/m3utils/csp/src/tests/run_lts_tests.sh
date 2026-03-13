#!/bin/sh
# LTS extraction acceptance test suite
#
# Tests both:
#   (A) The new LTS extraction from pre-compiled text9 files
#   (B) Regression: the existing cspc compiler pipeline still produces
#       correct text9 from .scm parse trees
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

# ============================================================================
#  PART A: LTS extraction from existing text9 files
# ============================================================================
#
# These tests load pre-compiled .text9.scm files and verify the extracted
# LTS has the expected states, transitions, and alphabet.

run_lts_text9_test() {
    name="$1"
    text9file="$2"
    expected_states="$3"
    expected_trans="$4"
    expected_actions="$5"  # space-separated action labels to check for

    tdir=$(mktemp -d)

    cat > "$tdir/driver.scm" <<ENDSCM
(load (string-append (Env.Get "M3UTILS") "/csp/src/setup.scm"))

(define lts (extract-lts-from-text9-file "$text9file"))
(print-lts lts)

;; Validate counts
(define nstates (length (lts-states lts)))
(define ntrans  (length (lts-transitions lts)))

(dis "TEST-STATES=" (number->string nstates) dnl)
(dis "TEST-TRANS="  (number->string ntrans) dnl)

;; Validate initial state
(dis "TEST-INITIAL=" (symbol->string (lts-initial lts)) dnl)

;; Write .aut file to verify it doesn't crash
(write-lts-aut lts "$tdir/test.aut")
(dis "TEST-AUT-OK" dnl)

(exit)
ENDSCM

    run_cspc "$tdir" driver.scm

    if [ $_RC -ne 0 ]; then
        fail "$name" "cspc exited with rc=$_RC"
        rm -rf "$tdir"
        return
    fi

    # Check state count
    actual_states=$(echo "$_OUTPUT" | grep "^TEST-STATES=" | sed 's/TEST-STATES=//')
    if [ "$actual_states" != "$expected_states" ]; then
        fail "$name" "expected $expected_states states, got $actual_states"
        rm -rf "$tdir"
        return
    fi

    # Check transition count
    actual_trans=$(echo "$_OUTPUT" | grep "^TEST-TRANS=" | sed 's/TEST-TRANS=//')
    if [ "$actual_trans" != "$expected_trans" ]; then
        fail "$name" "expected $expected_trans transitions, got $actual_trans"
        rm -rf "$tdir"
        return
    fi

    # Check initial state is START
    actual_init=$(echo "$_OUTPUT" | grep "^TEST-INITIAL=" | sed 's/TEST-INITIAL=//')
    if [ "$actual_init" != "START" ]; then
        fail "$name" "expected initial=START, got $actual_init"
        rm -rf "$tdir"
        return
    fi

    # Check .aut file was written
    if ! echo "$_OUTPUT" | grep -q "TEST-AUT-OK"; then
        fail "$name" ".aut export failed"
        rm -rf "$tdir"
        return
    fi

    # Check .aut file has correct header
    if [ -f "$tdir/test.aut" ]; then
        aut_header=$(head -1 "$tdir/test.aut")
        if ! echo "$aut_header" | grep -q "des (0,"; then
            fail "$name" "bad .aut header: $aut_header"
            rm -rf "$tdir"
            return
        fi
    else
        fail "$name" ".aut file not created"
        rm -rf "$tdir"
        return
    fi

    # Check expected actions appear in the output
    if [ -n "$expected_actions" ]; then
        for act in $expected_actions; do
            if ! echo "$_OUTPUT" | grep -q "$act"; then
                fail "$name" "expected action '$act' not found in output"
                rm -rf "$tdir"
                return
            fi
        done
    fi

    pass "$name"
    rm -rf "$tdir"
}

echo "=== LTS Extraction Acceptance Test Suite ==="
echo ""

echo "--- Part A: LTS from pre-compiled text9 files ---"

# simple.HELLOWORLD: (goto START) ... (goto END) ... (label END)
# States: START, END.  Transitions: START --tau--> END.
run_lts_text9_test \
    "helloworld" \
    "$CASTDIR/simple.HELLOWORLD.il/build/src/m3__simple_46_HELLOWORLD.text9.scm" \
    2 1 ""

# first.PROC(true): 5 states, send R and recv L
# START --tau--> L17,  L17 --(send R)--> L22,  L22 --tau--> L19,
# L19 --(recv L)--> L21,  L21 --(send R)--> L22
run_lts_text9_test \
    "first_proc_true" \
    "$CASTDIR/first.SYSTEM.il/build/src/m3__first_46_PROC_40_true_41_.text9.scm" \
    5 5 "R! L?"

# first.PROC(false): 4 states, send R and recv L
# START --tau--> L43,  L43 --tau--> L40,  L40 --(recv L)--> L42,
# L42 --(send R)--> L43
run_lts_text9_test \
    "first_proc_false" \
    "$CASTDIR/first.SYSTEM.il/build/src/m3__first_46_PROC_40_false_41_.text9.scm" \
    4 4 "R! L?"

# collatz.WORKER: 6 states (START,L59,L66,L61,L65,L63), 9 transitions
# Has STRT (recv) and STATUS (send) channels, complex local-ifs
run_lts_text9_test \
    "collatz_worker" \
    "$CASTDIR/collatz.COLLATZ_20_44.il/build/src/m3__collatz_46_WORKER_40_20_44_44_41_.text9.scm" \
    6 9 "STRT? STATUS!"

# collatz.MANAGER: 4 states (START,L202,L207,L206), 5 transitions
# Has STRT (send) and STATUS (recv) channels
run_lts_text9_test \
    "collatz_manager" \
    "$CASTDIR/collatz.COLLATZ_20_44.il/build/src/m3__collatz_46_MANAGER_40_20_41_.text9.scm" \
    4 5 "STRT! STATUS?"

# collatz.SMERGE: 7 states, 12 transitions
# Has L (recv, array-accessed), R (send), and waitfor
run_lts_text9_test \
    "collatz_smerge" \
    "$CASTDIR/collatz.COLLATZ_20_44.il/build/src/m3__collatz_46_SMERGE.text9.scm" \
    7 12 "L? R!"

# collatz.STARTSPLIT(0): has L (recv) and R (send, array-accessed), fork/join
run_lts_text9_test \
    "collatz_startsplit" \
    "$CASTDIR/collatz.COLLATZ_20_44.il/build/src/m3__collatz_46_STARTSPLIT_40_0_41_.text9.scm" \
    6 7 "L? R!"

# ============================================================================
#  PART B: Compiler regression — recompile from .scm, compare text9
# ============================================================================
#
# These tests load the original .scm parse tree, run compile!, and verify
# that the resulting text9 matches the golden .text9.scm file.

run_recompile_test() {
    # Recompile from .scm and compare with golden text9.
    # Label names may differ (global counter state), so we compare:
    #   (a) block count is the same
    #   (b) LTS state/transition counts match
    name="$1"
    scm_file="$2"
    golden_text9="$3"
    expected_states="$4"
    expected_trans="$5"

    tdir=$(mktemp -d)

    cat > "$tdir/driver.scm" <<ENDSCM
(load (string-append (Env.Get "M3UTILS") "/csp/src/setup.scm"))

;; Load and compile the process
(loaddata0! "$scm_file")
(loaddata1!)
(compile!)

;; Load the golden text9
(define golden (load-text9 "$golden_text9"))

;; Compare block counts
(define actual-n (length text9))
(define golden-n (length golden))
(dis "RECOMPILE-BLOCKS-MATCH=" (if (= actual-n golden-n) "yes" "no") dnl)
(dis "RECOMPILE-ACTUAL-BLOCKS=" (number->string actual-n) dnl)
(dis "RECOMPILE-GOLDEN-BLOCKS=" (number->string golden-n) dnl)

;; Compare LTS structure: extract from both and compare counts
(define lts-actual (extract-lts text9 '()))
(define lts-golden (extract-lts golden '()))

(define as (length (lts-states lts-actual)))
(define at (length (lts-transitions lts-actual)))
(define gs (length (lts-states lts-golden)))
(define gt (length (lts-transitions lts-golden)))

(dis "RECOMPILE-LTS-MATCH=" (if (and (= as gs) (= at gt)) "yes" "no") dnl)
(dis "RECOMPILE-STATES=" (number->string as) dnl)
(dis "RECOMPILE-TRANS=" (number->string at) dnl)

(exit)
ENDSCM

    run_cspc "$tdir" driver.scm

    if [ $_RC -ne 0 ]; then
        fail "$name" "cspc exited with rc=$_RC"
        rm -rf "$tdir"
        return
    fi

    # Check block count match
    blocks_match=$(echo "$_OUTPUT" | grep "^RECOMPILE-BLOCKS-MATCH=" | sed 's/.*=//')
    if [ "$blocks_match" != "yes" ]; then
        actual_b=$(echo "$_OUTPUT" | grep "^RECOMPILE-ACTUAL-BLOCKS=" | sed 's/.*=//')
        golden_b=$(echo "$_OUTPUT" | grep "^RECOMPILE-GOLDEN-BLOCKS=" | sed 's/.*=//')
        fail "$name" "block count: actual=$actual_b golden=$golden_b"
        rm -rf "$tdir"
        return
    fi

    # Check LTS structure match
    lts_match=$(echo "$_OUTPUT" | grep "^RECOMPILE-LTS-MATCH=" | sed 's/.*=//')
    if [ "$lts_match" != "yes" ]; then
        fail "$name" "LTS structure mismatch after recompile"
        rm -rf "$tdir"
        return
    fi

    # Check against expected counts
    actual_states=$(echo "$_OUTPUT" | grep "^RECOMPILE-STATES=" | sed 's/.*=//')
    actual_trans=$(echo "$_OUTPUT" | grep "^RECOMPILE-TRANS=" | sed 's/.*=//')
    if [ "$actual_states" != "$expected_states" ] || [ "$actual_trans" != "$expected_trans" ]; then
        fail "$name" "expected ${expected_states}s/${expected_trans}t, got ${actual_states}s/${actual_trans}t"
        rm -rf "$tdir"
        return
    fi

    pass "$name"
    rm -rf "$tdir"
}

echo ""
echo "--- Part B: Compiler regression (recompile and compare text9) ---"

run_recompile_test \
    "recompile_helloworld" \
    "$CASTDIR/simple.HELLOWORLD.il/simple_46_HELLOWORLD.scm" \
    "$CASTDIR/simple.HELLOWORLD.il/build/src/m3__simple_46_HELLOWORLD.text9.scm" \
    2 1

run_recompile_test \
    "recompile_first_proc_true" \
    "$CASTDIR/first.SYSTEM.il/first_46_PROC_40_true_41_.scm" \
    "$CASTDIR/first.SYSTEM.il/build/src/m3__first_46_PROC_40_true_41_.text9.scm" \
    5 5

run_recompile_test \
    "recompile_first_proc_false" \
    "$CASTDIR/first.SYSTEM.il/first_46_PROC_40_false_41_.scm" \
    "$CASTDIR/first.SYSTEM.il/build/src/m3__first_46_PROC_40_false_41_.text9.scm" \
    4 4

# ============================================================================
#  PART C: LTS extraction via the full pipeline (extract-process-lts!)
# ============================================================================
#
# Tests the convenience function that loads .scm, compiles, and extracts
# the LTS in one call.

run_full_pipeline_test() {
    name="$1"
    scm_file="$2"
    expected_states="$3"
    expected_trans="$4"

    tdir=$(mktemp -d)

    cat > "$tdir/driver.scm" <<ENDSCM
(load (string-append (Env.Get "M3UTILS") "/csp/src/setup.scm"))

(define lts (extract-process-lts! "$scm_file"))

(define nstates (length (lts-states lts)))
(define ntrans  (length (lts-transitions lts)))

(dis "PIPELINE-STATES=" (number->string nstates) dnl)
(dis "PIPELINE-TRANS="  (number->string ntrans) dnl)

(exit)
ENDSCM

    run_cspc "$tdir" driver.scm

    if [ $_RC -ne 0 ]; then
        fail "$name" "cspc exited with rc=$_RC"
        rm -rf "$tdir"
        return
    fi

    actual_states=$(echo "$_OUTPUT" | grep "^PIPELINE-STATES=" | sed 's/PIPELINE-STATES=//')
    actual_trans=$(echo "$_OUTPUT" | grep "^PIPELINE-TRANS=" | sed 's/PIPELINE-TRANS=//')

    if [ "$actual_states" = "$expected_states" ] && [ "$actual_trans" = "$expected_trans" ]; then
        pass "$name"
    else
        fail "$name" "expected ${expected_states}s/${expected_trans}t, got ${actual_states}s/${actual_trans}t"
    fi

    rm -rf "$tdir"
}

echo ""
echo "--- Part C: Full pipeline (extract-process-lts!) ---"

run_full_pipeline_test \
    "pipeline_helloworld" \
    "$CASTDIR/simple.HELLOWORLD.il/simple_46_HELLOWORLD.scm" \
    2 1

run_full_pipeline_test \
    "pipeline_first_proc_true" \
    "$CASTDIR/first.SYSTEM.il/first_46_PROC_40_true_41_.scm" \
    5 5

run_full_pipeline_test \
    "pipeline_first_proc_false" \
    "$CASTDIR/first.SYSTEM.il/first_46_PROC_40_false_41_.scm" \
    4 4

# ============================================================================
#  PART D: LTS structural invariants
# ============================================================================
#
# Additional checks that verify LTS well-formedness properties.

run_invariant_test() {
    name="$1"
    text9file="$2"

    tdir=$(mktemp -d)

    cat > "$tdir/driver.scm" <<ENDSCM
(load (string-append (Env.Get "M3UTILS") "/csp/src/setup.scm"))

(define lts (extract-lts-from-text9-file "$text9file"))

;; Invariant 1: initial state is in the state set
(define ok1 (memq (lts-initial lts) (lts-states lts)))
(dis "INV-INIT-IN-STATES=" (if ok1 "yes" "no") dnl)

;; Invariant 2: all transition source states are in the state set
(define ok2 #t)
(for-each
 (lambda (t)
   (if (not (memq (car t) (lts-states lts)))
       (set! ok2 #f)))
 (lts-transitions lts))
(dis "INV-SRC-IN-STATES=" (if ok2 "yes" "no") dnl)

;; Invariant 3: all transition target states are in the state set
(define ok3 #t)
(for-each
 (lambda (t)
   (if (not (memq (caddr t) (lts-states lts)))
       (set! ok3 #f)))
 (lts-transitions lts))
(dis "INV-DST-IN-STATES=" (if ok3 "yes" "no") dnl)

;; Invariant 4: all non-tau actions in transitions appear in alphabet
(define ok4 #t)
(for-each
 (lambda (t)
   (let ((act (cadr t)))
     (if (and (not (eq? act 'tau))
              (not (member act (lts-alphabet lts))))
         (set! ok4 #f))))
 (lts-transitions lts))
(dis "INV-ACTS-IN-ALPHA=" (if ok4 "yes" "no") dnl)

;; Invariant 5: no duplicate transitions
(define ok5 #t)
(let check ((ts (lts-transitions lts)))
  (if (not (null? ts))
      (begin
        (if (member (car ts) (cdr ts))
            (set! ok5 #f))
        (check (cdr ts)))))
(dis "INV-NO-DUP-TRANS=" (if ok5 "yes" "no") dnl)

(exit)
ENDSCM

    run_cspc "$tdir" driver.scm

    if [ $_RC -ne 0 ]; then
        fail "$name" "cspc exited with rc=$_RC"
        rm -rf "$tdir"
        return
    fi

    all_ok=true
    for inv in INV-INIT-IN-STATES INV-SRC-IN-STATES INV-DST-IN-STATES \
               INV-ACTS-IN-ALPHA INV-NO-DUP-TRANS; do
        val=$(echo "$_OUTPUT" | grep "^${inv}=" | sed "s/${inv}=//")
        if [ "$val" != "yes" ]; then
            fail "$name" "$inv failed"
            all_ok=false
            break
        fi
    done

    if $all_ok; then
        pass "$name"
    fi

    rm -rf "$tdir"
}

echo ""
echo "--- Part D: LTS structural invariants ---"

run_invariant_test \
    "invariants_helloworld" \
    "$CASTDIR/simple.HELLOWORLD.il/build/src/m3__simple_46_HELLOWORLD.text9.scm"

run_invariant_test \
    "invariants_first_proc_true" \
    "$CASTDIR/first.SYSTEM.il/build/src/m3__first_46_PROC_40_true_41_.text9.scm"

run_invariant_test \
    "invariants_collatz_worker" \
    "$CASTDIR/collatz.COLLATZ_20_44.il/build/src/m3__collatz_46_WORKER_40_20_44_44_41_.text9.scm"

run_invariant_test \
    "invariants_collatz_smerge" \
    "$CASTDIR/collatz.COLLATZ_20_44.il/build/src/m3__collatz_46_SMERGE.text9.scm"

run_invariant_test \
    "invariants_startsplit" \
    "$CASTDIR/collatz.COLLATZ_20_44.il/build/src/m3__collatz_46_STARTSPLIT_40_0_41_.text9.scm"

# ============================================================================
#  PART E: Aldebaran .aut format validation
# ============================================================================

run_aut_format_test() {
    name="$1"
    text9file="$2"
    expected_states="$3"
    expected_trans="$4"

    tdir=$(mktemp -d)

    cat > "$tdir/driver.scm" <<ENDSCM
(load (string-append (Env.Get "M3UTILS") "/csp/src/setup.scm"))

(define lts (extract-lts-from-text9-file "$text9file"))
(write-lts-aut lts "$tdir/test.aut")
(dis "AUT-DONE" dnl)
(exit)
ENDSCM

    run_cspc "$tdir" driver.scm

    if [ $_RC -ne 0 ]; then
        fail "$name" "cspc exited with rc=$_RC"
        rm -rf "$tdir"
        return
    fi

    if [ ! -f "$tdir/test.aut" ]; then
        fail "$name" ".aut file not created"
        rm -rf "$tdir"
        return
    fi

    # Check header format: des (0, N, M)
    header=$(head -1 "$tdir/test.aut")
    expected_header="des (0, $expected_trans, $expected_states)"
    if [ "$header" != "$expected_header" ]; then
        fail "$name" "header mismatch: expected '$expected_header', got '$header'"
        rm -rf "$tdir"
        return
    fi

    # Check number of transition lines (all lines after header)
    ntrans_lines=$(tail -n +2 "$tdir/test.aut" | wc -l | tr -d ' ')
    if [ "$ntrans_lines" != "$expected_trans" ]; then
        fail "$name" "expected $expected_trans transition lines, got $ntrans_lines"
        rm -rf "$tdir"
        return
    fi

    # Check all transition lines match format: (N, "label", M)
    bad_lines=$(tail -n +2 "$tdir/test.aut" | grep -cv '^([0-9]*, ".*", [0-9]*)$' || true)
    if [ "$bad_lines" != "0" ]; then
        fail "$name" "$bad_lines lines don't match .aut format"
        rm -rf "$tdir"
        return
    fi

    # Check initial state (0) appears as source in at least one transition
    if ! tail -n +2 "$tdir/test.aut" | grep -q '^(0,'; then
        fail "$name" "initial state 0 has no outgoing transitions"
        rm -rf "$tdir"
        return
    fi

    pass "$name"
    rm -rf "$tdir"
}

echo ""
echo "--- Part E: Aldebaran .aut format validation ---"

run_aut_format_test \
    "aut_helloworld" \
    "$CASTDIR/simple.HELLOWORLD.il/build/src/m3__simple_46_HELLOWORLD.text9.scm" \
    2 1

run_aut_format_test \
    "aut_first_proc_true" \
    "$CASTDIR/first.SYSTEM.il/build/src/m3__first_46_PROC_40_true_41_.text9.scm" \
    5 5

run_aut_format_test \
    "aut_first_proc_false" \
    "$CASTDIR/first.SYSTEM.il/build/src/m3__first_46_PROC_40_false_41_.text9.scm" \
    4 4

# ============================================================================
#  Summary
# ============================================================================

echo ""
echo "=== Results: $PASS/$TOTAL passed ==="

if [ $FAIL -ne 0 ]; then
    echo "($FAIL FAILED)"
    exit 1
fi
