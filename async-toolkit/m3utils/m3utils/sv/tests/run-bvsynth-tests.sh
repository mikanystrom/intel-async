#!/bin/sh
#
# run-bvsynth-tests.sh -- Parse verify/*.sv to ASTs, then run
#                         exhaustive BDD equivalence verification.
#
# Usage: cd m3utils && sv/tests/run-bvsynth-tests.sh
#   or:  sv/tests/run-bvsynth-tests.sh  (from any dir under m3utils)
#

set -e

# Find repo root (directory containing sv/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

SVFE=sv/svparse/AMD64_LINUX/svfe
SVSYNTH=sv/svsynth/AMD64_LINUX/svsynth
TESTDIR=sv/tests/verify
ASTDIR=/tmp/bvsynth-ast

# Ensure binaries exist
if [ ! -x "$SVFE" ]; then
    echo "ERROR: svfe not found at $SVFE (run cm3 -override in svparse/)" >&2
    exit 1
fi

if [ ! -x "$SVSYNTH" ]; then
    echo "ERROR: svsynth not found at $SVSYNTH (run cm3 -override in svsynth/)" >&2
    exit 1
fi

mkdir -p "$ASTDIR"

# Parse all verify test files to AST
TESTS="test_add4 test_sub4 test_bitwise4 test_cmp4 test_mux4w test_reduce8 test_shift4 test_range4"

echo "=== Parsing test files ==="
for t in $TESTS; do
    echo "  $t.sv -> $t.ast.scm"
    "$SVFE" --scm "$TESTDIR/$t.sv" > "$ASTDIR/$t.ast.scm"
done
echo ""

# Run the verification
echo "=== Running BDD equivalence verification ==="
"$SVSYNTH" sv/tests/test_bvsynth.scm
