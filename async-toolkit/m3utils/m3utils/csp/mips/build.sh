#!/bin/bash
# build.sh — Build MiniMIPS simulator with crash capture
#
# Usage: ./build.sh [--max-retries N]
#
# If cspc crashes (SIGILL/rc=132), captures a crash report via lldb,
# then retries. Succeeds as soon as one attempt completes normally.

set -euo pipefail

MIPSDIR="$(cd "$(dirname "$0")" && pwd)"
M3UTILS="$(cd "$MIPSDIR/../.." && pwd)"

# Determine cm3 target (e.g., ARM64_DARWIN, AMD64_LINUX)
if [ -f "$M3UTILS/.bindir" ]; then
    TARGET="$(cat "$M3UTILS/.bindir")"
else
    TARGET="$("$M3UTILS/m3arch.sh")"
fi
CSPC="$M3UTILS/csp/$TARGET/cspc"
CM3_INSTALL="$(cd "$M3UTILS/../../../../install/bin" 2>/dev/null && pwd)" || true
MAX_RETRIES="${1:-5}"
CRASH_DIR="$MIPSDIR/crash-reports"

if [ ! -x "$CSPC" ]; then
    echo "error: cspc not found at $CSPC" >&2
    exit 1
fi

export M3UTILS
# Ensure cm3 and standard tools are on PATH
if [ -n "$CM3_INSTALL" ] && [ -x "$CM3_INSTALL/cm3" ]; then
    export PATH="$CM3_INSTALL:/usr/bin:/bin:$PATH"
fi

# Write Scheme build script to temp file (avoids stdin issues)
SCM_TMP=$(mktemp /tmp/build_minimips.XXXXXX)
cat > "$SCM_TMP" <<'SCHEME'
(load (string-append (Env.Get "M3UTILS") "/csp/src/setup.scm"))
(load (string-append (Env.Get "M3UTILS") "/csp/src/cspbuild.scm"))
(build-system! "minimips.sys")
(exit)
SCHEME
trap "rm -f $SCM_TMP" EXIT

attempt=0
while [ $attempt -lt $MAX_RETRIES ]; do
    attempt=$((attempt + 1))
    echo "=== Build attempt $attempt/$MAX_RETRIES ==="

    # Run cspc, capture output
    set +e
    output=$("$CSPC" -scm "$SCM_TMP" 2>&1)
    rc=$?
    set -e

    if [ $rc -eq 0 ]; then
        echo "=== Build succeeded on attempt $attempt ==="
        echo "$output" | tail -5
        exit 0
    fi

    echo "=== cspc exited with code $rc ==="

    # Capture crash report if it's a signal death (rc > 128)
    if [ $rc -gt 128 ]; then
        sig=$((rc - 128))
        signame="unknown"
        case $sig in
            4)  signame="SIGILL" ;;
            6)  signame="SIGABRT" ;;
            11) signame="SIGSEGV" ;;
            10) signame="SIGBUS" ;;
        esac

        mkdir -p "$CRASH_DIR"
        timestamp=$(date +%Y%m%d_%H%M%S)
        report="$CRASH_DIR/crash_${timestamp}_${signame}.txt"

        echo "=== Capturing crash report via lldb ($signame) ==="

        # Write lldb commands to a script file
        lldb_cmds=$(mktemp /tmp/lldb_cmds.XXXXXX)
        cat > "$lldb_cmds" <<EOF
target create $CSPC
breakpoint set --name RTSignalC__DefaultHandler
breakpoint set --name RTOS__Crash
process launch -- -scm $SCM_TMP
bt all
register read
frame variable
thread list
image list
quit
EOF

        {
            echo "MiniMIPS cspc crash report"
            echo "=========================="
            echo "Date:    $(date)"
            echo "Signal:  $signame (signal $sig, exit code $rc)"
            echo "Attempt: $attempt of $MAX_RETRIES"
            echo "cspc:    $CSPC"
            echo "uname:   $(uname -a)"
            echo ""
            echo "--- lldb session ---"
            lldb --batch --source "$lldb_cmds" 2>&1 || echo "(lldb capture failed with rc=$?)"
            echo ""
            echo "--- last 80 lines of cspc output ---"
            echo "$output" | tail -80
        } > "$report" 2>&1

        rm -f "$lldb_cmds"
        echo "=== Crash report saved to $report ==="
    else
        # Non-signal error — print last lines for context
        echo "$output" | tail -10
    fi

    if [ $attempt -lt $MAX_RETRIES ]; then
        echo "=== Retrying... ==="
    fi
done

echo "=== All $MAX_RETRIES attempts failed ===" >&2
exit 1
