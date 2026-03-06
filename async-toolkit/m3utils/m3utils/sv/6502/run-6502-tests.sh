#!/bin/sh
#
# run-6502-tests.sh -- Run all 6502 tests
#
# 1. Regenerate BDD-to-C ALU eval header
# 2. Run exhaustive ALU verification (BDD vs reference C)
# 3. Run Dormann functional test (fake6502 reference emulator)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

PASS=0
FAIL=0

echo "============================================="
echo "  6502 Test Suite"
echo "============================================="
echo ""

# --- Test 1: Generate BDD-to-C ALU eval ---
echo "=== Test 1: Generate BDD-to-C ALU eval ==="
if sh sv/6502/gen-c-eval.sh; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
echo ""

# --- Test 2: Exhaustive ALU verification ---
echo "=== Test 2: Exhaustive ALU verification (BDD vs reference) ==="
gcc -O2 -o /tmp/test_alu_$$ sv/6502/emu/test_alu.c -I sv/6502/emu
if /tmp/test_alu_$$; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
rm -f /tmp/test_alu_$$
echo ""

# --- Test 3: Dormann functional test (reference emulator) ---
echo "=== Test 3: Dormann 6502 functional test (fake6502) ==="
gcc -O2 -o /tmp/emu6502_$$ sv/6502/emu/emu6502.c sv/6502/emu/fake6502.c
if /tmp/emu6502_$$ --start 0x0000 --reset 0x0400 --success 0x3469 \
                    sv/6502/test/6502_functional_test.bin; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi
rm -f /tmp/emu6502_$$
echo ""

# --- Summary ---
echo "============================================="
echo "  SUMMARY: $PASS passed, $FAIL failed"
echo "============================================="

[ "$FAIL" -eq 0 ]
