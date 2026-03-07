#!/bin/sh
# run-svsop.sh -- Generate minimized SOP equations from SystemVerilog
#
# Usage: run-svsop.sh [--cut N] [pp-flags...] input.sv
#
# Options:
#   --cut N    Set BDD cut threshold (default: no cuts).
#              Intermediate variables are introduced when BDDs exceed
#              N nodes, keeping all SOP equations bounded in size.
#              Recommended: 30 for arithmetic-heavy designs.
#
# Preprocesses, parses, synthesizes BDDs, then converts each output bit
# to a minimized sum-of-products equation using SopBDD.invariantSimplify.

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$SCRIPT_DIR/.." && pwd)

SVPP="$TOP/svpp/AMD64_LINUX/svpp"
SVFE="$TOP/svparse/AMD64_LINUX/svfe"
SVSYNTH="$TOP/svsynth/AMD64_LINUX/svsynth"

CUT_THRESHOLD=""

# Parse our flags (before pp flags)
while [ $# -gt 0 ]; do
    case "$1" in
        --cut)
            CUT_THRESHOLD="$2"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

if [ $# -lt 1 ]; then
    echo "Usage: $0 [--cut N] [pp-flags...] input.sv" >&2
    exit 1
fi

# Last argument is the input file; everything before is pp flags
ARGS=""
INPUT=""
for arg in "$@"; do
    if [ -n "$INPUT" ]; then
        ARGS="$ARGS $INPUT"
    fi
    INPUT="$arg"
done

TMPDIR="${TMPDIR:-/tmp}"
TMPPP="$TMPDIR/svsop-$$.pp.sv"
TMPAST="$TMPDIR/svsop-$$.ast.scm"
TMPRUN="$TMPDIR/svsop-$$.run.scm"

cleanup() { rm -f "$TMPPP" "$TMPAST" "$TMPRUN"; }
trap cleanup EXIT

$SVPP $ARGS "$INPUT" > "$TMPPP"
$SVFE --scm "$TMPPP" > "$TMPAST" 2>/dev/null

# Build the run script: define AST path, then svsop.scm with cut threshold injected
cat > "$TMPRUN" <<EOF
(define *cpu-ast-file* "$TMPAST")
EOF

if [ -n "$CUT_THRESHOLD" ]; then
    # Insert (set! *bv-cut-threshold* N) at the CUT-THRESHOLD-HOOK marker
    sed "s/;; CUT-THRESHOLD-HOOK/(set! *bv-cut-threshold* $CUT_THRESHOLD)/" \
        "$TOP/src/svsop.scm" >> "$TMPRUN"
else
    cat "$TOP/src/svsop.scm" >> "$TMPRUN"
fi

cd "$TOP/.."
$SVSYNTH "$TMPRUN"
