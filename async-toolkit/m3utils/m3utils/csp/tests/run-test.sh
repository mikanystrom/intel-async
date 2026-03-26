#!/bin/sh
#
# Run cspc on a test example.
#
# Usage:
#   ./run-test.sh                          # compile HelloWorld (default)
#   ./run-test.sh <procs-file>             # compile a specific .procs file
#   ./run-test.sh --interpreted <procs>    # force interpreted mode
#   ./run-test.sh --compare <procs>        # run both and compare output
#
# Examples:
#   ./run-test.sh
#   ./run-test.sh ../mips/MiniMIPS.procs
#   ./run-test.sh --compare ../mips/MiniMIPS.procs
#   ./run-test.sh --interpreted ../mips/MiniMIPS.procs
#

# Increase stack size for deeply recursive interpreted mode
ulimit -s 65520 2>/dev/null || true

CSPC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CSPC="$CSPC_DIR/ARM64_DARWIN/cspc"
M3UTILS="$(cd "$CSPC_DIR/.." && pwd)"

if [ ! -x "$CSPC" ]; then
    echo "Error: cspc binary not found at $CSPC" >&2
    echo "Build it first: cd $CSPC_DIR && cm3 -build -override" >&2
    exit 1
fi

INTERPRETED=""
COMPARE=""
if [ "$1" = "--interpreted" ]; then
    INTERPRETED=1
    shift
elif [ "$1" = "--compare" ]; then
    COMPARE=1
    shift
fi

PROCS="${1:-simple_46_HELLOWORLD.procs}"

# Resolve relative to this directory
case "$PROCS" in
    /*) ;;
    *)  PROCS="$(cd "$(dirname "$0")" && pwd)/$PROCS" ;;
esac

if [ ! -f "$PROCS" ]; then
    echo "Error: .procs file not found: $PROCS" >&2
    exit 1
fi

# Work from the directory containing the .procs file so drive! can find the .scm files
WORKDIR="$(dirname "$PROCS")"
PROCS_BASE="$(basename "$PROCS")"

run_cspc() {
    # $1 = mode label, $2 = extra env
    MODE="$1"
    EXTRA_ENV="$2"

    cd "$WORKDIR"

    # Clean build directory completely
    rm -rf build/src
    mkdir -p build/src

    echo "=== Running $MODE ==="

    env NOM3READLINE=1 M3UTILS="$M3UTILS" $EXTRA_ENV "$CSPC" -scm <<EOF
(require-modules "time" "display")

(define t-start (Time.Now))

(define *m3utils-bench* (Env.Get "M3UTILS"))
(set! **scheme-load-path** (cons (string-append *m3utils-bench* "/csp/src")
                                  **scheme-load-path**))

(load "setup.scm")
(define t-loaded (Time.Now))

(set! debug #f)

(drive! "$PROCS_BASE" 'force)
(define t-done (Time.Now))

(dis dnl "=== TIMING ($MODE) ===" dnl)
(dis "  Setup:   " (number->string (- t-loaded t-start)) "s" dnl)
(dis "  Compile: " (number->string (- t-done t-loaded)) "s" dnl)
(dis "  Total:   " (number->string (- t-done t-start)) "s" dnl)

(exit 0)
EOF
}

checksum_build() {
    ( cd "$WORKDIR/build/src" && find . \( -name '*.m3' -o -name '*.i3' \) -print | sort | xargs cat ) \
        | shasum
}

if [ -n "$COMPARE" ]; then
    TMPDIR_BASE="${TMPDIR:-/tmp}/cspc-compare.$$"
    mkdir -p "$TMPDIR_BASE"

    # Run compiled
    run_cspc "COMPILED" "" > "$TMPDIR_BASE/compiled.out" 2>&1
    RC_C=$?
    if [ $RC_C -ne 0 ]; then
        echo "  COMPILED run FAILED (exit $RC_C)" >&2
        cat "$TMPDIR_BASE/compiled.out" >&2
    fi
    checksum_build > "$TMPDIR_BASE/compiled.sha"

    # Run interpreted
    run_cspc "INTERPRETED" "MSCHEME_INTERPRETED=1" > "$TMPDIR_BASE/interpreted.out" 2>&1
    RC_I=$?
    if [ $RC_I -ne 0 ]; then
        echo "  INTERPRETED run FAILED (exit $RC_I)" >&2
        tail -5 "$TMPDIR_BASE/interpreted.out" >&2
    fi
    checksum_build > "$TMPDIR_BASE/interpreted.sha"

    echo ""
    echo "========================================="
    if [ $RC_C -eq 0 ]; then
        echo "  COMPILED:"
        grep "TIMING\|Setup\|Compile:\|Total" "$TMPDIR_BASE/compiled.out" | grep -v "^>"
    else
        echo "  COMPILED: FAILED (exit $RC_C)"
    fi
    echo ""
    if [ $RC_I -eq 0 ]; then
        echo "  INTERPRETED:"
        grep "TIMING\|Setup\|Compile:\|Total" "$TMPDIR_BASE/interpreted.out" | grep -v "^>"
    else
        echo "  INTERPRETED: FAILED (exit $RC_I)"
    fi
    echo ""

    if [ $RC_C -eq 0 ] && [ $RC_I -eq 0 ]; then
        SHA_C="$(cat "$TMPDIR_BASE/compiled.sha")"
        SHA_I="$(cat "$TMPDIR_BASE/interpreted.sha")"
        if [ "$SHA_C" = "$SHA_I" ]; then
            echo "  Output checksum: MATCH ($SHA_C)"
        else
            echo "  Output checksum: MISMATCH!"
            echo "    Compiled:    $SHA_C"
            echo "    Interpreted: $SHA_I"
        fi
    fi
    echo "========================================="

    rm -rf "$TMPDIR_BASE"
elif [ -n "$INTERPRETED" ]; then
    run_cspc "INTERPRETED" "MSCHEME_INTERPRETED=1"
else
    run_cspc "COMPILED" ""
fi
