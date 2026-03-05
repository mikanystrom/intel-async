#!/bin/bash
# run_tests.sh - Compile and run all equivalence-checking tests with iverilog
#
# Usage: ./run_tests.sh
#
# Each test compiles an RTL module, its gate-level netlist, the cell library,
# and a testbench, then runs the simulation to check equivalence.

set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

CELLS="cells.v"
PASS=0
FAIL=0
TOTAL=0

# List of tests: testbench rtl gates
TESTS=(
  "tb_and2.v       test_and2.sv       test_and2_gates.v"
  "tb_mux4.v       test_mux4.sv       test_mux4_gates.v"
  "tb_xor_chain.v  test_xor_chain.sv  test_xor_chain_gates.v"
  "tb_mixed.v      test_mixed.sv      test_mixed_gates.v"
  "tb_adder.v      test_adder.sv      test_adder_gates.v"
  "tb_alu1.v       test_alu1.sv       test_alu1_gates.v"
  "tb_compare.v    test_compare.sv    test_compare_gates.v"
  "tb_decoder.v    test_decoder.sv    test_decoder_gates.v"
  "tb_parity8.v    test_parity8.sv    test_parity8_gates.v"
)

echo "========================================="
echo " Equivalence Verification Test Suite"
echo "========================================="
echo ""

for entry in "${TESTS[@]}"; do
  read -r tb rtl gates <<< "$entry"
  name="${tb%.v}"
  TOTAL=$((TOTAL + 1))

  echo "--- $name ---"

  # Compile
  if ! iverilog -g2012 -o "${name}.vvp" "$CELLS" "$rtl" "$gates" "$tb" 2>&1; then
    echo "  COMPILE FAILED"
    FAIL=$((FAIL + 1))
    echo ""
    continue
  fi

  # Run
  output=$(vvp "${name}.vvp" 2>&1)
  echo "$output"

  if echo "$output" | grep -q "PASS"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
  fi
  echo ""
done

echo "========================================="
echo " Results: $PASS passed, $FAIL failed (out of $TOTAL)"
echo "========================================="

# Clean up build artifacts
rm -f *.vvp *.vcd

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
