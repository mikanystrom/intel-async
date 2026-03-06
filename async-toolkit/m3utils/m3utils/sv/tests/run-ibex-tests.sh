#!/bin/sh
#
# Test the SV parser against the lowRISC ibex RISC-V core.
#
# Prerequisites:
#   git clone --depth 1 https://github.com/lowRISC/ibex.git /tmp/ibex
#
# Usage:
#   ./run-ibex-tests.sh [/path/to/ibex]
#

set -e

IBEX="${1:-/tmp/ibex}"
SVFE="$(dirname "$0")/../svparse/AMD64_LINUX/svfe"
PP="$(dirname "$0")/../src/svpp.py"

if [ ! -d "$IBEX/rtl" ]; then
    echo "ibex not found at $IBEX"
    echo "Clone it first: git clone --depth 1 https://github.com/lowRISC/ibex.git $IBEX"
    exit 1
fi

if [ ! -x "$SVFE" ]; then
    echo "svfe not found at $SVFE — build it first (cm3 -override from svparse/src)"
    exit 1
fi

PRIM="$IBEX/vendor/lowrisc_ip/ip/prim/rtl"
DV="$IBEX/vendor/lowrisc_ip/dv/sv/dv_utils"
PP_FLAGS="-D VERILATOR -D RVFI -I $PRIM -I $DV"
TMP="/tmp/_svfe_test_$$.sv"

trap "rm -f $TMP" EXIT

run_suite() {
    suite="$1"
    shift
    pass=0
    fail=0
    for f in "$@"; do
        python3 "$PP" $PP_FLAGS "$f" > "$TMP" 2>/dev/null
        if "$SVFE" "$TMP" > /dev/null 2>&1; then
            pass=$((pass + 1))
        else
            fail=$((fail + 1))
            echo "  FAIL: $(basename "$f")"
        fi
    done
    echo "$suite: $pass pass, $fail fail"
}

echo "=== ibex/rtl ==="
run_suite "ibex/rtl" "$IBEX"/rtl/*.sv

echo ""
echo "=== ibex prim/rtl ==="
TMP2="/tmp/_svfe_preamble_$$.sv"
trap "rm -f $TMP $TMP2" EXIT
run_suite_with_preamble() {
    suite="$1"
    preamble="$2"
    shift 2
    pass=0
    fail=0
    for f in "$@"; do
        { echo "$preamble"; cat "$f"; } > "$TMP2"
        python3 "$PP" $PP_FLAGS "$TMP2" > "$TMP" 2>/dev/null
        if "$SVFE" "$TMP" > /dev/null 2>&1; then
            pass=$((pass + 1))
        else
            fail=$((fail + 1))
            echo "  FAIL: $(basename "$f")"
        fi
    done
    echo "$suite: $pass pass, $fail fail"
}
run_suite_with_preamble "prim/rtl" '`include "prim_assert.sv"' "$PRIM"/*.sv

echo ""
echo "=== verify ==="
pass=0
fail=0
for f in "$(dirname "$0")"/verify/*.sv; do
    if "$SVFE" "$f" > /dev/null 2>&1; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "  FAIL: $(basename "$f")"
    fi
done
echo "verify: $pass pass, $fail fail"
