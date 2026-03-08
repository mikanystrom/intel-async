#!/bin/sh
# cspbuild .sys test suite
# Usage: sh run_sys_tests.sh

set -u

# --- Environment -----------------------------------------------------------

M3UTILS="${M3UTILS:-/Users/mika/cm3/intel-async/async-toolkit/m3utils/m3utils}"
CM3DIR="${CM3DIR:-/Users/mika/cm3/install/bin}"
TESTDIR="$(cd "$(dirname "$0")" && pwd)"

# Determine cm3 target (e.g., ARM64_DARWIN, AMD64_LINUX)
if [ -f "$M3UTILS/.bindir" ]; then
    TARGET="$(cat "$M3UTILS/.bindir")"
else
    TARGET="$("$M3UTILS/m3arch.sh")"
fi
CSPC="${CSPC:-$M3UTILS/csp/$TARGET/cspc}"

# Ensure cm3, sstubgen, and cspfe are on PATH
export PATH="$CM3DIR:$M3UTILS/csp/cspparse/$TARGET:$PATH"

PASS=0
FAIL=0
TOTAL=0
MAX_RETRIES=2  # retry up to 2 times on transient crash (rc=133)

# --- Helpers ----------------------------------------------------------------

# Run cspc in a directory, with retries for transient crashes.
# Sets _RC and _OUTPUT for the caller.
run_cspc() {
    _dir="$1"
    _script="$2"
    _try=0
    while [ $_try -le $MAX_RETRIES ]; do
        _OUTPUT=$(cd "$_dir" && M3UTILS="$M3UTILS" "$CSPC" -scm "$_script" 2>&1)
        _RC=$?
        if [ $_RC -ne 133 ]; then
            return
        fi
        _try=$((_try + 1))
        sleep 1
    done
}

run_parse_test() {
    name="$1"
    sysfile="$2"
    TOTAL=$((TOTAL + 1))

    tdir=$(mktemp -d)

    # Copy .csp files the .sys might reference
    cp "$TESTDIR"/*.csp "$tdir/" 2>/dev/null || true
    cp "$TESTDIR/$sysfile" "$tdir/"

    # Generate a small Scheme driver that parses the .sys file
    cat > "$tdir/driver.scm" <<EOF
(load (string-append (Env.Get "M3UTILS") "/csp/src/setup.scm"))
(load (string-append (Env.Get "M3UTILS") "/csp/src/cspbuild.scm"))
(let ((sys (parse-sys-file "$sysfile")))
  (dis "parse-ok" dnl))
(exit)
EOF

    run_cspc "$tdir" driver.scm

    if [ $_RC -eq 0 ] && echo "$_OUTPUT" | grep -q "parse-ok"; then
        printf "  PASS  %s\n" "$name"
        PASS=$((PASS + 1))
    else
        printf "  FAIL  %s  (rc=%d, output: %s)\n" "$name" "$_RC" "$(echo "$_OUTPUT" | tail -3)"
        FAIL=$((FAIL + 1))
    fi

    rm -rf "$tdir"
}

run_build_test() {
    name="$1"
    sysfile="$2"
    TOTAL=$((TOTAL + 1))

    tdir=$(mktemp -d)

    # Copy .csp files the .sys might reference
    cp "$TESTDIR"/*.csp "$tdir/" 2>/dev/null || true
    cp "$TESTDIR/$sysfile" "$tdir/"

    # Generate a Scheme driver that runs the full build pipeline
    cat > "$tdir/driver.scm" <<EOF
(load (string-append (Env.Get "M3UTILS") "/csp/src/setup.scm"))
(load (string-append (Env.Get "M3UTILS") "/csp/src/cspbuild.scm"))
(build-system! "$sysfile")
(exit)
EOF

    run_cspc "$tdir" driver.scm

    # Check exit code and presence of simulator binary
    sim=""
    if [ -f "$tdir/build/$TARGET/sim" ]; then
        sim="$tdir/build/$TARGET/sim"
    fi

    if [ $_RC -eq 0 ] && [ -n "$sim" ]; then
        printf "  PASS  %s\n" "$name"
        PASS=$((PASS + 1))
    else
        printf "  FAIL  %s  (rc=%d, sim=%s)\n" "$name" "$_RC" "${sim:-not found}"
        if [ $_RC -ne 0 ]; then
            printf "        output: %s\n" "$(echo "$_OUTPUT" | tail -5)"
        fi
        FAIL=$((FAIL + 1))
    fi

    rm -rf "$tdir"
}

run_error_test() {
    name="$1"
    sysfile="$2"
    expected="$3"
    TOTAL=$((TOTAL + 1))

    tdir=$(mktemp -d)

    # Copy .csp files the .sys might reference
    cp "$TESTDIR"/*.csp "$tdir/" 2>/dev/null || true
    cp "$TESTDIR/$sysfile" "$tdir/"

    # Generate a Scheme driver that tries to parse (and validate) the .sys file.
    # On error, cspc exits non-zero automatically.
    cat > "$tdir/driver.scm" <<EOF
(load (string-append (Env.Get "M3UTILS") "/csp/src/setup.scm"))
(load (string-append (Env.Get "M3UTILS") "/csp/src/cspbuild.scm"))
(let ((sys (parse-sys-file "$sysfile")))
  (validate-system! sys))
(exit)
EOF

    run_cspc "$tdir" driver.scm

    if [ $_RC -ne 0 ] && echo "$_OUTPUT" | grep -qi "$expected"; then
        printf "  PASS  %-28s (got: \"%s\")\n" "$name" "$expected"
        PASS=$((PASS + 1))
    else
        printf "  FAIL  %s  (rc=%d, expected \"%s\")\n" "$name" "$_RC" "$expected"
        printf "        output: %s\n" "$(echo "$_OUTPUT" | tail -3)"
        FAIL=$((FAIL + 1))
    fi

    rm -rf "$tdir"
}

# --- Main -------------------------------------------------------------------

echo "=== cspbuild .sys test suite ==="
echo ""

echo "--- Parse tests ---"
run_parse_test  parse_minimal        parse_minimal.sys
run_parse_test  parse_external       parse_external.sys
run_parse_test  parse_channels       parse_channels.sys
run_parse_test  parse_slack          parse_slack.sys
run_parse_test  parse_line_comments  parse_line_comments.sys
run_parse_test  parse_block_comments parse_block_comments.sys
run_parse_test  parse_multi_instance parse_multi_instance.sys
run_parse_test  parse_multi_process  parse_multi_process.sys
run_parse_test  parse_multi_binding  parse_multi_binding.sys

echo ""
echo "--- Build tests ---"
run_build_test  build_hello_inline   build_hello_inline.sys
run_build_test  build_hello_external build_hello_external.sys
run_build_test  build_prodcons       build_prodcons.sys
run_build_test  build_pipeline       build_pipeline.sys
run_build_test  build_bidir          build_bidir.sys
run_build_test  build_wide           build_wide.sys
run_build_test  build_slack          build_slack.sys
run_build_test  build_multi_inst     build_multi_inst.sys
run_build_test  build_collatz        build_collatz.sys

echo ""
echo "--- Error tests ---"
run_error_test  err_unknown_proc     err_unknown_proc.sys     "unknown process"
run_error_test  err_unknown_chan      err_unknown_chan.sys      "unknown channel"
run_error_test  err_unknown_port     err_unknown_port.sys     "unknown port"
run_error_test  err_width_mismatch   err_width_mismatch.sys   "width mismatch"
run_error_test  err_unbound_port     err_unbound_port.sys     "unbound"
run_error_test  err_missing_semi     err_missing_semi.sys     "expected"
run_error_test  err_unterminated_comment err_unterminated_comment.sys "unterminated"
run_error_test  err_unterminated_string  err_unterminated_string.sys  "unterminated"

echo ""
echo "=== Results: $PASS/$TOTAL passed ==="

if [ $FAIL -ne 0 ]; then
    echo "($FAIL FAILED)"
    exit 1
fi
