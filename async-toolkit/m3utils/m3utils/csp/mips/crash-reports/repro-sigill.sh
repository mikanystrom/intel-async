#!/bin/bash
# repro-sigill.sh -- Reproduce transient SIGILL in cspc on ARM64 Darwin
#
# Usage: ./repro-sigill.sh [iterations]
#
# Runs cspc N times (default 100) on the MiniMIPS build and counts
# SIGILL (exit code 132) vs success.

set -uo pipefail

M3UTILS="/Users/mika/cm3/intel-async/async-toolkit/m3utils/m3utils"
CSPC="$M3UTILS/csp/ARM64_DARWIN/cspc"
MIPSDIR="$M3UTILS/csp/mips"
export M3UTILS
export PATH="/Users/mika/cm3/install/bin:/usr/bin:/bin:$PATH"

if [ ! -x "$CSPC" ]; then
    echo "error: cspc not found at $CSPC" >&2
    exit 1
fi

SCM_TMP=$(mktemp /tmp/build_minimips_repro.XXXXXX)
cat > "$SCM_TMP" <<'SCHEME'
(load (string-append (Env.Get "M3UTILS") "/csp/src/setup.scm"))
(load (string-append (Env.Get "M3UTILS") "/csp/src/cspbuild.scm"))
(build-system! "minimips.sys")
(exit)
SCHEME
trap "rm -f $SCM_TMP" EXIT

TOTAL=${1:-100}
SUCCESS=0
SIGILL_COUNT=0
OTHER_FAIL=0

echo "Running $TOTAL iterations of cspc on MiniMIPS..."
echo "cspc: $CSPC"
echo "Working dir: $MIPSDIR"
echo ""

for i in $(seq 1 $TOTAL); do
    rc=0
    cd "$MIPSDIR"
    "$CSPC" -scm "$SCM_TMP" > /dev/null 2>&1 || rc=$?

    if [ $rc -eq 0 ]; then
        SUCCESS=$((SUCCESS + 1))
    elif [ $rc -eq 132 ]; then
        SIGILL_COUNT=$((SIGILL_COUNT + 1))
        echo "  [$i] SIGILL (rc=132)"
    elif [ $rc -gt 128 ]; then
        sig=$((rc - 128))
        OTHER_FAIL=$((OTHER_FAIL + 1))
        echo "  [$i] Signal $sig (rc=$rc)"
    else
        OTHER_FAIL=$((OTHER_FAIL + 1))
        echo "  [$i] Error rc=$rc"
    fi

    if [ $((i % 10)) -eq 0 ]; then
        echo "Progress: $i/$TOTAL (ok=$SUCCESS sigill=$SIGILL_COUNT other=$OTHER_FAIL)"
    fi
done

echo ""
echo "=== RESULTS ==="
echo "Total runs:    $TOTAL"
echo "Successes:     $SUCCESS"
echo "SIGILL (132):  $SIGILL_COUNT"
echo "Other errors:  $OTHER_FAIL"
if [ $TOTAL -gt 0 ]; then
    pct=$(echo "scale=1; $SIGILL_COUNT * 100 / $TOTAL" | bc 2>/dev/null || echo "?")
    echo "SIGILL rate:   ${pct}%"
fi
