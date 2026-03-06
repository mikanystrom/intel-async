#!/bin/sh
#
# run-roundtrip-test.sh -- Round-trip verification:
#   behavioral SV -> BDDs -> gate-level SV -> svfe parse -> BDDs -> compare
#
# Usage: sv/tests/run-roundtrip-test.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

SVFE=sv/svparse/AMD64_LINUX/svfe
SVSYNTH=sv/svsynth/AMD64_LINUX/svsynth
TESTDIR=sv/tests/verify
TMPDIR=/tmp/roundtrip

mkdir -p "$TMPDIR"

# Step 1: Parse behavioral SV to AST
echo "=== Parsing behavioral SV ==="
"$SVFE" --scm "$TESTDIR/test_add4.sv" > "$TMPDIR/test_add4.ast.scm"
echo "  test_add4.sv -> AST"

# Step 2+3: Run Scheme to build BDDs, emit gate-level SV
echo ""
echo "=== Building BDDs and emitting gate-level SV ==="
"$SVSYNTH" sv/tests/test_roundtrip_emit.scm

# Step 4: Parse gate-level SV through svfe
echo ""
echo "=== Parsing gate-level SV ==="
"$SVFE" --scm "$TMPDIR/roundtrip_gates.sv" > "$TMPDIR/roundtrip_gates.ast.scm"
echo "  roundtrip_gates.sv -> AST"

# Step 5: Compare BDDs
echo ""
echo "=== Comparing BDDs ==="
"$SVSYNTH" sv/tests/test_roundtrip_compare.scm
