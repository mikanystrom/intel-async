#!/bin/sh
#
# run-svlint.sh -- RTL lint tool for SystemVerilog
#
# Usage: sv/svlint/run-svlint.sh [--pp-flags FLAGS] input.sv [input2.sv ...]
#
# Pipeline:
#   svpp.py [flags] input.sv > /tmp/svlint-$$.pp.sv
#   svfe --scm /tmp/svlint-$$.pp.sv > /tmp/svlint-$$.ast.scm
#   svsynth (load svlint-driver.scm with AST path)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

SVFE=sv/svparse/AMD64_LINUX/svfe
SVSYNTH=sv/svsynth/AMD64_LINUX/svsynth
SVPP=sv/src/svpp.py
TMPDIR=/tmp/svlint-$$

PP_FLAGS=""

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --pp-flags)
            shift
            PP_FLAGS="$1"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--pp-flags FLAGS] input.sv [input2.sv ...]"
            echo ""
            echo "RTL lint checker for SystemVerilog."
            echo ""
            echo "Options:"
            echo "  --pp-flags FLAGS   Preprocessor flags (e.g., '-D VERILATOR -I path')"
            echo ""
            echo "Checks:"
            echo "  - Undriven outputs"
            echo "  - Blocking assigns in always_ff"
            echo "  - Non-blocking assigns in always_comb"
            echo "  - Unused signals"
            echo "  - Multiple drivers"
            echo "  - Latch inference"
            echo "  - Width mismatches"
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

if [ $# -eq 0 ]; then
    echo "ERROR: no input files" >&2
    echo "Usage: $0 [--pp-flags FLAGS] input.sv [input2.sv ...]" >&2
    exit 1
fi

# Check tools
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

for INPUT in "$@"; do
    echo "=== Linting: $INPUT ==="
    BASENAME=$(basename "$INPUT" .sv)
    BASENAME=$(basename "$BASENAME" .v)

    # Preprocess
    PP_OUT="$TMPDIR/${BASENAME}.pp.sv"
    if [ -n "$PP_FLAGS" ]; then
        python3 "$SVPP" $PP_FLAGS "$INPUT" > "$PP_OUT"
    else
        python3 "$SVPP" "$INPUT" > "$PP_OUT"
    fi

    # Parse to AST
    AST_OUT="$TMPDIR/${BASENAME}.ast.scm"
    "$SVFE" --scm "$PP_OUT" > "$AST_OUT"

    # Run lint
    DRIVER="$TMPDIR/${BASENAME}_lint.scm"
    cat > "$DRIVER" <<SCHEME_EOF
(define *svlint-ast-file* "$AST_OUT")
(load "sv/src/svlint-driver.scm")
SCHEME_EOF

    "$SVSYNTH" "$DRIVER" < /dev/null
    echo ""
done
