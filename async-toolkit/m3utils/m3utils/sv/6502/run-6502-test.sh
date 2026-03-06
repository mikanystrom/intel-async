#!/bin/sh
#
# run-6502-test.sh -- Build and run 6502 emulator on Dormann test suite
#
# Usage: sv/6502/run-6502-test.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

echo "=== Building 6502 Emulator ==="
cd sv/6502/emu
make clean
make
cd "$ROOT"
echo ""

echo "=== Running Klaus Dormann 6502 Functional Test ==="
echo "  (this takes ~2 seconds)"
sv/6502/emu/emu6502 --reset 0x0400 --success 0x3469 sv/6502/test/6502_functional_test.bin
echo ""

echo "=== Parsing 6502 SV Model ==="
SVFE=sv/svparse/AMD64_LINUX/svfe
if [ -x "$SVFE" ]; then
    "$SVFE" --scm sv/6502/rtl/ALU.sv > /dev/null 2>&1 && echo "  ALU.sv: PARSE OK" || echo "  ALU.sv: PARSE FAIL"
    "$SVFE" --scm sv/6502/rtl/cpu.sv > /dev/null 2>&1 && echo "  cpu.sv: PARSE OK" || echo "  cpu.sv: PARSE FAIL"
else
    echo "  (svfe not built, skipping parse test)"
fi
