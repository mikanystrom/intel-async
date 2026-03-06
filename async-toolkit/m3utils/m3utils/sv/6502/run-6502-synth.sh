#!/bin/sh
#
# run-6502-synth.sh -- Parse and synthesize 6502 RTL
#
# 1. Parse ALU.sv and cpu.sv through svfe
# 2. Synthesize ALU to BDDs and generate C eval header
# 3. Synthesize CPU decode cones and generate C eval header
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

SVFE=sv/svparse/AMD64_LINUX/svfe
SVSYNTH=sv/svsynth/AMD64_LINUX/svsynth
SVPP=sv/svpp/AMD64_LINUX/svpp

if [ ! -x "$SVFE" ]; then
    echo "ERROR: svfe not found at $SVFE" >&2
    exit 1
fi
if [ ! -x "$SVSYNTH" ]; then
    echo "ERROR: svsynth not found at $SVSYNTH" >&2
    exit 1
fi

TMPDIR=/tmp/6502-synth-$$
mkdir -p "$TMPDIR"
trap "rm -rf $TMPDIR" EXIT

echo "============================================="
echo "  6502 RTL Synthesis"
echo "============================================="

# --- Parse ---
echo ""
echo "=== Parsing ALU.sv ==="
"$SVPP" sv/6502/rtl/ALU.sv > "$TMPDIR/ALU.pp.sv"
"$SVFE" --scm "$TMPDIR/ALU.pp.sv" > "$TMPDIR/ALU.ast.scm"
echo "  OK"

echo ""
echo "=== Parsing cpu.sv ==="
"$SVPP" sv/6502/rtl/cpu.sv > "$TMPDIR/cpu.pp.sv"
"$SVFE" --scm "$TMPDIR/cpu.pp.sv" > "$TMPDIR/cpu.ast.scm"
echo "  OK"

# --- ALU Synthesis ---
echo ""
echo "=== ALU BDD Synthesis + C Code Generation ==="
cat > "$TMPDIR/alu_driver.scm" <<EOF
(define *gen-c-ast-file* "$TMPDIR/ALU.ast.scm")
(define *gen-c-output-file* "sv/6502/emu/alu_bdd_eval.h")
(load "sv/6502/gen_c_eval.scm")
EOF
"$SVSYNTH" "$TMPDIR/alu_driver.scm" < /dev/null

# --- CPU Decode Synthesis ---
echo ""
echo "=== CPU Decode Cone Synthesis + C Code Generation ==="
cat > "$TMPDIR/cpu_driver.scm" <<EOF
(define *cpu-ast-file* "$TMPDIR/cpu.ast.scm")
(define *cpu-output-file* "sv/6502/emu/cpu_decode_eval.h")
(load "sv/6502/synth_cpu_cones.scm")
EOF
"$SVSYNTH" "$TMPDIR/cpu_driver.scm" < /dev/null

echo ""
echo "============================================="
echo "  Done"
echo "============================================="
