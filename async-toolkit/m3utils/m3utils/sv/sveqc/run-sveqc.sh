#!/bin/sh
#
# run-sveqc.sh -- Equivalence checking tool for SystemVerilog
#
# Usage:
#   sv/sveqc/run-sveqc.sh [--pp-flags FLAGS] [--gate-out FILE] input.sv
#   sv/sveqc/run-sveqc.sh [--pp-flags FLAGS] input.sv reference.sv
#
# Single-file mode: synthesize BDDs, emit gate-level SV, report stats
# Two-file mode:    compare two designs for functional equivalence
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

SVFE=sv/svparse/AMD64_LINUX/svfe
SVSYNTH=sv/svsynth/AMD64_LINUX/svsynth
SVPP=sv/src/svpp.py
TMPDIR=/tmp/sveqc-$$

PP_FLAGS=""
GATE_OUT=""

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --pp-flags)
            shift
            PP_FLAGS="$1"
            shift
            ;;
        --gate-out)
            shift
            GATE_OUT="$1"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--pp-flags FLAGS] [--gate-out FILE] input.sv [reference.sv]"
            echo ""
            echo "Equivalence checking for SystemVerilog modules."
            echo ""
            echo "Single-file mode: synthesize to BDDs, optionally emit gate-level SV."
            echo "Two-file mode: compare two designs for functional equivalence."
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

if [ $# -eq 0 ]; then
    echo "ERROR: no input files" >&2
    exit 1
fi

INPUT1="$1"
INPUT2="${2:-}"

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

# Preprocess and parse a file
parse_file() {
    local INPUT="$1"
    local TAG="$2"
    local BASENAME=$(basename "$INPUT" .sv)
    BASENAME=$(basename "$BASENAME" .v)

    PP_OUT="$TMPDIR/${TAG}_${BASENAME}.pp.sv"
    if [ -n "$PP_FLAGS" ]; then
        python3 "$SVPP" $PP_FLAGS "$INPUT" > "$PP_OUT"
    else
        python3 "$SVPP" "$INPUT" > "$PP_OUT"
    fi

    AST_OUT="$TMPDIR/${TAG}_${BASENAME}.ast.scm"
    "$SVFE" --scm "$PP_OUT" > "$AST_OUT"
    echo "$AST_OUT"
}

AST1=$(parse_file "$INPUT1" "a")

if [ -n "$INPUT2" ]; then
    # Two-file mode
    AST2=$(parse_file "$INPUT2" "b")

    DRIVER="$TMPDIR/eqc_driver.scm"
    cat > "$DRIVER" <<SCHEME_EOF
(define *sveqc-ast-file* "$AST1")
(define *sveqc-ref-file* "$AST2")
(define *sveqc-gate-file* #f)
(define *sveqc-mode* 'two-file)
(load "sv/src/sveqc-driver.scm")
SCHEME_EOF

    "$SVSYNTH" "$DRIVER" < /dev/null
else
    # Single-file mode
    DRIVER="$TMPDIR/eqc_driver.scm"

    GATE_LINE="(define *sveqc-gate-file* #f)"
    if [ -n "$GATE_OUT" ]; then
        GATE_LINE="(define *sveqc-gate-file* \"$GATE_OUT\")"
    fi

    cat > "$DRIVER" <<SCHEME_EOF
(define *sveqc-ast-file* "$AST1")
$GATE_LINE
(define *sveqc-mode* 'self-check)
(load "sv/src/sveqc-driver.scm")
SCHEME_EOF

    "$SVSYNTH" "$DRIVER" < /dev/null
fi
