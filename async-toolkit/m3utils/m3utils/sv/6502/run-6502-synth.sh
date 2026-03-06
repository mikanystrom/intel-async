#!/bin/sh
#
# run-6502-synth.sh -- Parse and synthesize 6502 RTL
#
# Usage: sv/6502/run-6502-synth.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

SVFE=sv/svparse/AMD64_LINUX/svfe
SVSYNTH=sv/svsynth/AMD64_LINUX/svsynth

if [ ! -x "$SVFE" ]; then
    echo "ERROR: svfe not found at $SVFE" >&2
    exit 1
fi

if [ ! -x "$SVSYNTH" ]; then
    echo "ERROR: svsynth not found at $SVSYNTH" >&2
    exit 1
fi

echo "=== Parsing 6502 RTL ==="
echo "  ALU.sv..."
"$SVFE" --scm sv/6502/rtl/ALU.sv > /tmp/6502_ALU.ast.scm
echo "  cpu.sv..."
"$SVFE" --scm sv/6502/rtl/cpu.sv > /tmp/6502_cpu.ast.scm
echo ""

echo "=== Synthesizing ALU ==="
"$SVSYNTH" sv/6502/synth_alu.scm
echo ""

echo "=== Analyzing CPU Combinational Cones ==="
"$SVSYNTH" sv/6502/synth_cpu_cones.scm
