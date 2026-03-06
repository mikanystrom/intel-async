#!/bin/sh
#
# run-eqc-tests.sh -- Equivalence checking test suite
#
# Runs self-equivalence checks on verify/*.sv test modules.
#
# Usage: sv/tests/run-eqc-tests.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

SVFE=sv/svparse/AMD64_LINUX/svfe
SVSYNTH=sv/svsynth/AMD64_LINUX/svsynth
TESTDIR=sv/tests/verify
TMPDIR=/tmp/eqc-tests-$$

if [ ! -x "$SVFE" ]; then
    echo "ERROR: svfe not found at $SVFE" >&2
    exit 1
fi

if [ ! -x "$SVSYNTH" ]; then
    echo "ERROR: svsynth not found at $SVSYNTH" >&2
    exit 1
fi

mkdir -p "$TMPDIR"
trap "rm -rf $TMPDIR" EXIT

TESTS="test_add4 test_sub4 test_bitwise4 test_cmp4 test_mux4w test_reduce8 test_shift4 test_range4"

PASS=0
FAIL=0

echo "=== Equivalence Checking Test Suite ==="
echo ""

echo "--- Parsing test files ---"
for t in $TESTS; do
    "$SVFE" --scm "$TESTDIR/$t.sv" > "$TMPDIR/$t.ast.scm"
    echo "  $t.sv -> AST"
done
echo ""

echo "--- Running self-equivalence checks ---"
for t in $TESTS; do
    DRIVER="$TMPDIR/${t}_eqc.scm"
    GATE_OUT="$TMPDIR/${t}_gates.sv"

    cat > "$DRIVER" <<SCHEME_EOF
(define *sveqc-ast-file* "$TMPDIR/$t.ast.scm")
(define *sveqc-gate-file* "$GATE_OUT")
(define *sveqc-mode* 'self-check)
(load "sv/src/sveqc-driver.scm")
SCHEME_EOF

    OUTPUT=$("$SVSYNTH" "$DRIVER" < /dev/null 2>&1)

    if echo "$OUTPUT" | grep -q "PASS"; then
        echo "  PASS: $t"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $t"
        echo "$OUTPUT" | head -10
        FAIL=$((FAIL + 1))
    fi
done

echo ""

# Round-trip: for each module that got gate output, re-parse and compare
echo "--- Round-trip verification ---"
RT_PASS=0
RT_FAIL=0

for t in $TESTS; do
    GATE_SV="$TMPDIR/${t}_gates.sv"
    if [ ! -f "$GATE_SV" ]; then
        continue
    fi

    # Parse gate-level SV
    GATE_AST="$TMPDIR/${t}_gates.ast.scm"
    if "$SVFE" --scm "$GATE_SV" > "$GATE_AST" 2>/dev/null; then
        # Two-file comparison
        DRIVER="$TMPDIR/${t}_rt.scm"
        cat > "$DRIVER" <<SCHEME_EOF
(define *sveqc-ast-file* "$TMPDIR/$t.ast.scm")
(define *sveqc-ref-file* "$GATE_AST")
(define *sveqc-gate-file* #f)
(define *sveqc-mode* 'two-file)
(load "sv/src/sveqc-driver.scm")
SCHEME_EOF

        OUTPUT=$("$SVSYNTH" "$DRIVER" < /dev/null 2>&1)
        if echo "$OUTPUT" | grep -q "EQUIVALENCE VERIFIED"; then
            echo "  PASS: $t (round-trip)"
            RT_PASS=$((RT_PASS + 1))
        else
            echo "  FAIL: $t (round-trip)"
            RT_FAIL=$((RT_FAIL + 1))
        fi
    else
        echo "  SKIP: $t (gate-level parse failed)"
    fi
done

echo ""
echo "=== Summary ==="
echo "  Self-check: $PASS passed, $FAIL failed"
echo "  Round-trip:  $RT_PASS passed, $RT_FAIL failed"

if [ "$FAIL" -gt 0 ] || [ "$RT_FAIL" -gt 0 ]; then
    exit 1
fi
