#!/bin/sh
#
# Test suite for the SystemVerilog preprocessor (svpp).
#
# Each test case is a .sv file with a corresponding .expected file.
# The test passes if svpp output matches .expected exactly
# and the output line count equals the input line count.
#
# Usage: ./run-pp-tests.sh

set -e

SVPP="$(dirname "$0")/../../svpp/AMD64_LINUX/svpp"
TDIR="$(dirname "$0")"

if [ ! -x "$SVPP" ]; then
    echo "svpp not found at $SVPP — build it first (cm3 -override from svpp/)"
    exit 1
fi

pass=0
fail=0
TMP="/tmp/_svpp_test_$$.out"
trap "rm -f $TMP" EXIT

for expected in "$TDIR"/t*.expected; do
    bn=$(basename "$expected" .expected)
    input="$TDIR/$bn.sv"
    if [ ! -f "$input" ]; then
        echo "  SKIP: $bn (no .sv file)"
        continue
    fi

    # Determine flags per test
    flags=""
    case "$bn" in
        t10_cmdline_D) flags="-D SYNTHESIS -D WIDTH=32" ;;
        t11_include)   flags="-I $TDIR" ;;
    esac

    # Run preprocessor
    "$SVPP" $flags "$input" > "$TMP" 2>/dev/null

    # Check output matches expected
    if ! diff -q "$expected" "$TMP" > /dev/null 2>&1; then
        fail=$((fail + 1))
        echo "  FAIL: $bn (output mismatch)"
        diff "$expected" "$TMP" | head -10
        continue
    fi

    # Check line count preservation
    src_lines=$(wc -l < "$input")
    out_lines=$(wc -l < "$TMP")
    if [ "$src_lines" != "$out_lines" ]; then
        fail=$((fail + 1))
        echo "  FAIL: $bn (line count: $src_lines in, $out_lines out)"
        continue
    fi

    pass=$((pass + 1))
done

echo "pp: $pass pass, $fail fail"
[ "$fail" -eq 0 ]
