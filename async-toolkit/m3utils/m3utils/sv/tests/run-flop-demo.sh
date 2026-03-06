#!/bin/sh
#
# run-flop-demo.sh -- Round-trip demo with a flop-to-flop path.
#
# Synthesizes the combinational cone inside an always_ff block,
# emits gate-level SV, parses it back, and verifies BDD equality.
#
# Usage: sv/tests/run-flop-demo.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

SVFE=sv/svparse/AMD64_LINUX/svfe
SVSYNTH=sv/svsynth/AMD64_LINUX/svsynth
TMPDIR=/tmp/flop-demo

mkdir -p "$TMPDIR"

echo "=============================================="
echo "  Flop-to-Flop Round-Trip Demo"
echo "=============================================="
echo ""

# Step 1: Show the source
echo "=== Source: test_alu_pipe.sv ==="
cat sv/tests/verify/test_alu_pipe.sv
echo ""

# Step 2: Parse to AST
echo "=== Step 1: Parse behavioral SV ==="
"$SVFE" --scm sv/tests/verify/test_alu_pipe.sv > "$TMPDIR/alu_pipe.ast.scm"
echo "  Parsed OK"

# Step 3: Synthesize BDDs and emit gate-level SV
echo ""
echo "=== Step 2: Synthesize BDDs, emit gate-level SV ==="
"$SVSYNTH" sv/tests/test_flop_emit.scm

# Step 4: Parse gate-level SV
echo ""
echo "=== Step 3: Parse gate-level SV ==="
"$SVFE" --scm "$TMPDIR/alu_pipe_gates.sv" > "$TMPDIR/alu_pipe_gates.ast.scm"
echo "  Parsed OK"

# Step 5: Compare BDDs
echo ""
echo "=== Step 4: Compare BDDs ==="
"$SVSYNTH" sv/tests/test_flop_compare.scm
