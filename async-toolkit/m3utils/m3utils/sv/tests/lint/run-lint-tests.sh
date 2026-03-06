#!/bin/sh
#
# run-lint-tests.sh -- Run lint checks on test files and verify expected warnings
#
# Usage: sv/tests/lint/run-lint-tests.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$ROOT"

SVFE=sv/svparse/AMD64_LINUX/svfe
SVSYNTH=sv/svsynth/AMD64_LINUX/svsynth
SVPP=sv/src/svpp.py
TESTDIR=sv/tests/lint
TMPDIR=/tmp/lint-tests-$$

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

PASS=0
FAIL=0

run_lint() {
    local INPUT="$1"
    local EXPECTED_PATTERN="$2"
    local TEST_NAME="$3"

    BASENAME=$(basename "$INPUT" .sv)
    PP_OUT="$TMPDIR/${BASENAME}.pp.sv"
    AST_OUT="$TMPDIR/${BASENAME}.ast.scm"

    python3 "$SVPP" "$INPUT" > "$PP_OUT"
    "$SVFE" --scm "$PP_OUT" > "$AST_OUT"

    DRIVER="$TMPDIR/${BASENAME}_lint.scm"
    cat > "$DRIVER" <<SCHEME_EOF
(define *svlint-ast-file* "$AST_OUT")
(load "sv/src/svlint-driver.scm")
SCHEME_EOF

    OUTPUT=$("$SVSYNTH" "$DRIVER" < /dev/null 2>&1)

    if echo "$OUTPUT" | grep -q "$EXPECTED_PATTERN"; then
        echo "  PASS: $TEST_NAME (found: $EXPECTED_PATTERN)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $TEST_NAME (expected: $EXPECTED_PATTERN)"
        echo "  Output was:"
        echo "$OUTPUT" | head -20
        FAIL=$((FAIL + 1))
    fi
}

# Test for no-warning case
run_lint_clean() {
    local INPUT="$1"
    local TEST_NAME="$2"

    BASENAME=$(basename "$INPUT" .sv)
    PP_OUT="$TMPDIR/${BASENAME}.pp.sv"
    AST_OUT="$TMPDIR/${BASENAME}.ast.scm"

    python3 "$SVPP" "$INPUT" > "$PP_OUT"
    "$SVFE" --scm "$PP_OUT" > "$AST_OUT"

    DRIVER="$TMPDIR/${BASENAME}_lint.scm"
    cat > "$DRIVER" <<SCHEME_EOF
(define *svlint-ast-file* "$AST_OUT")
(load "sv/src/svlint-driver.scm")
SCHEME_EOF

    OUTPUT=$("$SVSYNTH" "$DRIVER" < /dev/null 2>&1)

    if echo "$OUTPUT" | grep -q "Total warnings: 0"; then
        echo "  PASS: $TEST_NAME (zero warnings)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $TEST_NAME (expected zero warnings)"
        echo "$OUTPUT"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Lint Test Suite ==="
echo ""

run_lint "$TESTDIR/test_undriven.sv"    "output.*diff.*never driven"   "Undriven output"
run_lint "$TESTDIR/test_unused.sv"      "never"                        "Unused signal"
run_lint "$TESTDIR/test_multidriver.sv" "multiple drivers"             "Multiple drivers"
run_lint "$TESTDIR/test_latch.sv"       "possible latch"               "Latch inference"
run_lint "$TESTDIR/test_blocking_ff.sv" "blocking assign"              "Blocking in FF"
run_lint "$TESTDIR/test_width.sv"       "width mismatch"               "Width mismatch"
run_lint_clean "$TESTDIR/test_clean.sv"                                "Clean module"

echo ""
echo "=== Summary ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "  Total:  $((PASS + FAIL))"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
