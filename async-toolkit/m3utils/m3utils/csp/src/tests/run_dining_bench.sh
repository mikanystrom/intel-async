#!/bin/sh
# Dining Philosophers benchmark: deadlock checking at various N.
#
# For each N, generates a .sys file, runs check-deadlock!, and reports
# product states explored and wall-clock time.
#
# Three variants:
#   det-naive: deterministic forks, all left-first (DEADLOCK)
#   det-asym:  deterministic forks, last one reversed (DEADLOCK-FREE)
#   probe:     probe-based nondeterministic forks (DEADLOCK)
#
# Usage: sh run_dining_bench.sh

set -u

M3UTILS="${M3UTILS:-/Users/mika/cm3/intel-async/async-toolkit/m3utils/m3utils}"
CM3DIR="${CM3DIR:-/Users/mika/cm3/install/bin}"
TESTDIR="$(cd "$(dirname "$0")" && pwd)"
CSPDIR="$M3UTILS/csp"
SYSDIR="$TESTDIR/sys"

if [ -f "$M3UTILS/.bindir" ]; then
    TARGET="$(cat "$M3UTILS/.bindir")"
else
    TARGET="$("$M3UTILS/m3arch.sh")"
fi
CSPC="${CSPC:-$CSPDIR/$TARGET/cspc}"

export PATH="$CM3DIR:$CSPDIR/cspparse/$TARGET:$PATH"

MAX_RETRIES=2

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

generate_sys() {
    _n="$1"
    _name="$2"
    _fork_csp="$3"
    _rev_fork_csp="$4"
    _file="$5"

    {
        echo "system ${_name};"
        _i=0
        while [ $_i -lt "$_n" ]; do
            echo "  var f${_i}lg : channel(32); var f${_i}la : channel(32); var f${_i}rg : channel(32); var f${_i}ra : channel(32);"
            _i=$((_i + 1))
        done
        echo "  process Fork = \"${_fork_csp}\""
        echo "    port out LG : channel(32) port in LA : channel(32) port out RG : channel(32) port in RA : channel(32);"
        if [ -n "$_rev_fork_csp" ] && [ "$_rev_fork_csp" != "$_fork_csp" ]; then
            echo "  process ForkRev = \"${_rev_fork_csp}\""
            echo "    port out LG : channel(32) port in LA : channel(32) port out RG : channel(32) port in RA : channel(32);"
        fi
        echo "  process Phil = \"phil_naive.csp\""
        echo "    port in LG : channel(32) port out LT : channel(32) port in RG : channel(32) port out RT : channel(32);"
        echo "begin"
        _i=0
        while [ $_i -lt "$_n" ]; do
            _last=$((_n - 1))
            if [ -n "$_rev_fork_csp" ] && [ "$_rev_fork_csp" != "$_fork_csp" ] && [ $_i -eq $_last ]; then
                _ftype="ForkRev"
            else
                _ftype="Fork"
            fi
            echo "  var fork${_i} : ${_ftype}(LG => f${_i}lg, LA => f${_i}la, RG => f${_i}rg, RA => f${_i}ra);"
            _i=$((_i + 1))
        done
        _i=0
        while [ $_i -lt "$_n" ]; do
            _left=$_i
            _right=$(( (_i + 1) % _n ))
            echo "  var phil${_i} : Phil(LG => f${_left}lg, LT => f${_left}la, RG => f${_right}rg, RT => f${_right}ra);"
            _i=$((_i + 1))
        done
        echo "end."
    } > "$_file"
}

run_one() {
    _label="$1"
    _n="$2"
    _fork="$3"
    _revfork="$4"
    _expect="$5"

    _variant=$(echo "$_label" | sed 's/  *N=.*//' | tr ' -' '__')
    _name="bench_${_variant}_${_n}"
    _sysfile="${_name}.sys"
    generate_sys "$_n" "$_name" "$_fork" "$_revfork" "$TDIR/$_sysfile"

    cat > "$TDIR/d.scm" <<ENDSCM
(load (string-append (Env.Get "M3UTILS") "/csp/src/setup.scm"))
(load (string-append (Env.Get "M3UTILS") "/csp/src/cspbuild.scm"))
(define result (check-deadlock! "$_sysfile"))
(dis "R=" (if (eq? result #t) "free" "dead") dnl)
(exit)
ENDSCM

    _t0=$(perl -MTime::HiRes -e 'printf "%.0f\n", Time::HiRes::time()*1000')
    run_cspc "$TDIR" d.scm
    _t1=$(perl -MTime::HiRes -e 'printf "%.0f\n", Time::HiRes::time()*1000')
    _dt=$(( _t1 - _t0 ))

    _actual=$(echo "$_OUTPUT" | grep "^R=" | sed "s/^R=//")
    _states=$(echo "$_OUTPUT" | grep "explored" | sed 's/.*explored \([0-9]*\).*/\1/')

    _ok="OK"
    case "$_expect" in
        dead) [ "$_actual" = "dead" ] || _ok="FAIL" ;;
        free) [ "$_actual" = "free" ] || _ok="FAIL" ;;
    esac

    _result_str="$_actual"
    [ "$_actual" = "free" ] && _result_str="deadlock-free"
    [ "$_actual" = "dead" ] && _result_str="deadlock"

    printf "%-28s  %-18s  %8s  %7d ms\n" "$_label" "$_result_str ($_ok)" "$_states" "$_dt"
}

# --- Main -------------------------------------------------------------------

TDIR=$(mktemp -d)
cp "$SYSDIR"/*.csp "$TDIR/"

echo ""
echo "=== Dining Philosophers Benchmark ==="
echo ""
printf "%-28s  %-18s  %8s  %9s\n" "System" "Result" "States" "Time"
printf "%-28s  %-18s  %8s  %9s\n" "----------------------------" "------------------" "--------" "---------"

for N in 2 3 4 5; do
    run_one "det-naive  N=$N"  "$N" "phil_fork_det.csp" "phil_fork_det.csp" "dead"
    run_one "det-asym   N=$N"  "$N" "phil_fork_det.csp" "phil_fork_rev.csp" "free"
    run_one "probe      N=$N"  "$N" "phil_fork.csp"     "phil_fork.csp"     "dead"
done

rm -rf "$TDIR"
echo ""
