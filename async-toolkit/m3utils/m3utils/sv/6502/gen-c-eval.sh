#!/bin/sh
#
# gen-c-eval.sh -- Generate C evaluation functions for 6502 ALU
#
# Usage: sv/6502/gen-c-eval.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

SVFE=sv/svparse/AMD64_LINUX/svfe
SVSYNTH=sv/svsynth/AMD64_LINUX/svsynth
SVPP=sv/src/svpp.py

if [ ! -x "$SVFE" ]; then
    echo "ERROR: svfe not found at $SVFE" >&2
    exit 1
fi

if [ ! -x "$SVSYNTH" ]; then
    echo "ERROR: svsynth not found at $SVSYNTH" >&2
    exit 1
fi

TMPDIR=/tmp/gen-c-eval-$$
mkdir -p "$TMPDIR"
trap "rm -rf $TMPDIR" EXIT

echo "=== Parsing ALU.sv ==="
python3 "$SVPP" sv/6502/rtl/ALU.sv > "$TMPDIR/ALU.pp.sv"
"$SVFE" --scm "$TMPDIR/ALU.pp.sv" > "$TMPDIR/ALU.ast.scm"
echo "  Parse OK"

echo ""
echo "=== Generating C evaluation functions ==="

OUTPUT_FILE="sv/6502/emu/alu_bdd_eval.h"

cat > "$TMPDIR/gen_driver.scm" <<EOF
(define *gen-c-ast-file* "$TMPDIR/ALU.ast.scm")
(define *gen-c-output-file* "$OUTPUT_FILE")
(load "sv/6502/gen_c_eval.scm")
EOF

"$SVSYNTH" "$TMPDIR/gen_driver.scm" < /dev/null

echo ""
echo "=== Done ==="
echo "  Output: $OUTPUT_FILE"
