#!/bin/sh
# Product LTS composition and deadlock checking acceptance test suite
#
# Tests:
#   Batch 1: Deadlock-free systems (prodcons, pipeline, multi_inst, bidir)
#   Batch 2: Expected-deadlock systems (deadlock_simple, deadlock_cycle)
#   Batch 3: Dining Philosophers (N=2 det fork, N=3 det fork, N=2 probe fork)
#
# Usage: sh run_deadlock_tests.sh
#
# Prerequisites:
#   - cspc binary built (M3UTILS/csp/$TARGET/cspc)
#   - cspfe binary built (M3UTILS/csp/cspparse/$TARGET/cspfe)

set -u

# --- Environment -----------------------------------------------------------

M3UTILS="${M3UTILS:-/Users/mika/cm3/intel-async/async-toolkit/m3utils/m3utils}"
CM3DIR="${CM3DIR:-/Users/mika/cm3/install/bin}"
TESTDIR="$(cd "$(dirname "$0")" && pwd)"
CSPDIR="$M3UTILS/csp"
SYSDIR="$TESTDIR/sys"

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
    _tag="$1"
    _expected="$2"
    _actual=$(echo "$_OUTPUT" | grep "^${_tag}=" | sed "s/^${_tag}=//")
    [ "$_actual" = "$_expected" ]
}

get_result() {
    _tag="$1"
    echo "$_OUTPUT" | grep "^${_tag}=" | sed "s/^${_tag}=//"
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

check_deadlock_test() {
    # check_deadlock_test NAME
    # Checks that NAME.deadlock=yes and NAME.trace-len > 0
    _name="$1"
    if check_result "${_name}.deadlock" "yes"; then
        _trace_len=$(get_result "${_name}.trace-len")
        if [ -n "$_trace_len" ] && [ "$_trace_len" -gt 0 ] 2>/dev/null; then
            pass "deadlock:$_name (trace=$_trace_len steps)"
        else
            fail "deadlock:$_name" "deadlock found but no trace"
        fi
    else
        _actual=$(get_result "${_name}.deadlock")
        fail "deadlock:$_name" "expected deadlock=yes, got '$_actual'"
    fi
}

echo "=== Product LTS Deadlock Checking Acceptance Test Suite ==="

# ============================================================================
#  BATCH 1: Deadlock-free systems (1 cspc invocation)
# ============================================================================

echo ""
echo "--- Batch 1: deadlock-free systems ---"

TDIR1=$(mktemp -d)

cp "$SYSDIR"/*.csp "$TDIR1/" 2>/dev/null || true
cp "$SYSDIR"/build_prodcons.sys "$TDIR1/"
cp "$SYSDIR"/build_pipeline.sys "$TDIR1/"
cp "$SYSDIR"/build_multi_inst.sys "$TDIR1/"
cp "$SYSDIR"/build_bidir.sys "$TDIR1/"

cat > "$TDIR1/driver.scm" <<'ENDSCM'
(load (string-append (Env.Get "M3UTILS") "/csp/src/setup.scm"))
(load (string-append (Env.Get "M3UTILS") "/csp/src/cspbuild.scm"))

(define (deadlock-test name sys-file expect-deadlock)
  (define result (check-deadlock! sys-file))
  (if expect-deadlock
      (begin
        (dis name ".deadlock="
             (if (not (eq? result #t)) "yes" "no") dnl)
        (if (and (not (eq? result #t)) (pair? result))
            (dis name ".trace-len="
                 (number->string (length result)) dnl)))
      (begin
        (dis name ".deadlock-free="
             (if (eq? result #t) "yes" "no") dnl))))

(deadlock-test "prodcons"   "build_prodcons.sys"   #f)
(deadlock-test "pipeline"   "build_pipeline.sys"   #f)
(deadlock-test "multi_inst" "build_multi_inst.sys"  #f)
(deadlock-test "bidir"      "build_bidir.sys"       #f)

(dis "BATCH1-DONE" dnl)
(exit)
ENDSCM

run_cspc "$TDIR1" driver.scm

if [ $_RC -ne 0 ]; then
    echo "  FAIL  batch 1 cspc exited with rc=$_RC"
    echo "$_OUTPUT" | tail -20
    FAIL=$((FAIL + 4))
    TOTAL=$((TOTAL + 4))
else
    if ! echo "$_OUTPUT" | grep -q "BATCH1-DONE"; then
        echo "  FAIL  batch 1 did not complete"
        echo "$_OUTPUT" | tail -20
        FAIL=$((FAIL + 4))
        TOTAL=$((TOTAL + 4))
    else
        for name in prodcons pipeline multi_inst bidir; do
            if check_result "${name}.deadlock-free" "yes"; then
                pass "deadlock-free:$name"
            else
                actual=$(get_result "${name}.deadlock-free")
                fail "deadlock-free:$name" "expected deadlock-free=yes, got '$actual'"
            fi
        done
    fi
fi

rm -rf "$TDIR1"

# ============================================================================
#  BATCH 2: Expected-deadlock systems (1 cspc invocation)
# ============================================================================

echo ""
echo "--- Batch 2: expected-deadlock systems ---"

TDIR2=$(mktemp -d)

cp "$SYSDIR"/*.csp "$TDIR2/" 2>/dev/null || true
cp "$SYSDIR"/build_deadlock_simple.sys "$TDIR2/"
cp "$SYSDIR"/build_deadlock_cycle.sys "$TDIR2/"

cat > "$TDIR2/driver.scm" <<'ENDSCM'
(load (string-append (Env.Get "M3UTILS") "/csp/src/setup.scm"))
(load (string-append (Env.Get "M3UTILS") "/csp/src/cspbuild.scm"))

(define (deadlock-test name sys-file expect-deadlock)
  (define result (check-deadlock! sys-file))
  (if expect-deadlock
      (begin
        (dis name ".deadlock="
             (if (not (eq? result #t)) "yes" "no") dnl)
        (if (and (not (eq? result #t)) (pair? result))
            (dis name ".trace-len="
                 (number->string (length result)) dnl)))
      (begin
        (dis name ".deadlock-free="
             (if (eq? result #t) "yes" "no") dnl))))

(deadlock-test "deadlock_simple" "build_deadlock_simple.sys" #t)
(deadlock-test "deadlock_cycle"  "build_deadlock_cycle.sys"  #t)

(dis "BATCH2-DONE" dnl)
(exit)
ENDSCM

run_cspc "$TDIR2" driver.scm

if [ $_RC -ne 0 ]; then
    echo "  FAIL  batch 2 cspc exited with rc=$_RC"
    echo "$_OUTPUT" | tail -20
    FAIL=$((FAIL + 2))
    TOTAL=$((TOTAL + 2))
else
    if ! echo "$_OUTPUT" | grep -q "BATCH2-DONE"; then
        echo "  FAIL  batch 2 did not complete"
        echo "$_OUTPUT" | tail -20
        FAIL=$((FAIL + 2))
        TOTAL=$((TOTAL + 2))
    else
        check_deadlock_test "deadlock_simple"
        check_deadlock_test "deadlock_cycle"
    fi
fi

rm -rf "$TDIR2"

# ============================================================================
#  BATCH 3: Dining Philosophers (1 cspc invocation)
# ============================================================================
#
# Three dining philosopher configurations, all expected to deadlock:
#
#   dining_det_2:     N=2, deterministic fork (left-then-right), naive philosopher
#                     Classic circular wait: both hold left fork, wait for right.
#
#   dining_det_3:     N=3, same topology, validates scaling.
#
#   dining_probe_2:   N=2, probe-based fork (*[ #LG -> ... [] #RG -> ... ]),
#                     naive philosopher.  Fork uses channel probes for
#                     nondeterministic selection.  Deadlock found via guarded-
#                     repetition termination (probe abstracted as tau in LTS).

echo ""
echo "--- Batch 3: dining philosophers ---"

TDIR3=$(mktemp -d)

cp "$SYSDIR"/*.csp "$TDIR3/" 2>/dev/null || true
cp "$SYSDIR"/build_dining_det.sys "$TDIR3/"
cp "$SYSDIR"/build_dining_three_det.sys "$TDIR3/"
cp "$SYSDIR"/build_dining_naive.sys "$TDIR3/"

cat > "$TDIR3/driver.scm" <<'ENDSCM'
(load (string-append (Env.Get "M3UTILS") "/csp/src/setup.scm"))
(load (string-append (Env.Get "M3UTILS") "/csp/src/cspbuild.scm"))

(define (deadlock-test name sys-file expect-deadlock)
  (define result (check-deadlock! sys-file))
  (if expect-deadlock
      (begin
        (dis name ".deadlock="
             (if (not (eq? result #t)) "yes" "no") dnl)
        (if (and (not (eq? result #t)) (pair? result))
            (dis name ".trace-len="
                 (number->string (length result)) dnl)))
      (begin
        (dis name ".deadlock-free="
             (if (eq? result #t) "yes" "no") dnl))))

;; N=2 deterministic fork — classic circular wait
(deadlock-test "dining_det_2" "build_dining_det.sys" #t)

;; N=3 deterministic fork — larger circular wait
(deadlock-test "dining_det_3" "build_dining_three_det.sys" #t)

;; N=2 probe-based fork — nondeterministic selection with probes
(deadlock-test "dining_probe_2" "build_dining_naive.sys" #t)

(dis "BATCH3-DONE" dnl)
(exit)
ENDSCM

run_cspc "$TDIR3" driver.scm

if [ $_RC -ne 0 ]; then
    echo "  FAIL  batch 3 cspc exited with rc=$_RC"
    echo "$_OUTPUT" | tail -20
    FAIL=$((FAIL + 3))
    TOTAL=$((TOTAL + 3))
else
    if ! echo "$_OUTPUT" | grep -q "BATCH3-DONE"; then
        echo "  FAIL  batch 3 did not complete"
        echo "$_OUTPUT" | tail -20
        FAIL=$((FAIL + 3))
        TOTAL=$((TOTAL + 3))
    else
        check_deadlock_test "dining_det_2"
        check_deadlock_test "dining_det_3"
        check_deadlock_test "dining_probe_2"
    fi
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
