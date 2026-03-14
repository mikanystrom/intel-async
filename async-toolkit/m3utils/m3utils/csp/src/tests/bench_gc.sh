#!/bin/sh
# Benchmark: N=8 dining philosophers symbolic deadlock check
# Compares memory usage with and without BDD garbage collection.
#
# Usage: sh bench_gc.sh

set -u

M3UTILS="${M3UTILS:-/Users/mika/cm3/intel-async/async-toolkit/m3utils/m3utils}"
CM3DIR="${CM3DIR:-/Users/mika/cm3/install/bin}"
TESTDIR="$(cd "$(dirname "$0")" && pwd)"
SYSDIR="$TESTDIR/sys"

TARGET="$("$M3UTILS/m3arch.sh")"
CSPC="${CSPC:-$M3UTILS/csp/$TARGET/cspc}"

export PATH="$CM3DIR:$M3UTILS/csp/cspparse/$TARGET:$PATH"

TDIR=$(mktemp -d)
cp "$SYSDIR"/*.csp "$TDIR/" 2>/dev/null || true
cp "$SYSDIR"/build_dining_eight_det.sys "$TDIR/"

# --- Without GC: override GC calls to be no-ops ---
cat > "$TDIR/bench_nogc.scm" <<'ENDSCM'
(load (string-append (Env.Get "M3UTILS") "/csp/src/setup.scm"))
(load (string-append (Env.Get "M3UTILS") "/csp/src/cspbuild.scm"))

;; Override GC calls to be no-ops
(define real-MarkRoot BDD.MarkRoot)
(define real-CollectGarbage BDD.CollectGarbage)
(set! BDD.MarkRoot (lambda (x) #t))
(set! BDD.CollectGarbage (lambda () #t))

(define result (check-deadlock-symbolic! "build_dining_eight_det.sys"))
(dis "result=" (if result "deadlock-free" "DEADLOCK") dnl)
(exit)
ENDSCM

# --- With GC (current code) ---
cat > "$TDIR/bench_gc.scm" <<'ENDSCM'
(load (string-append (Env.Get "M3UTILS") "/csp/src/setup.scm"))
(load (string-append (Env.Get "M3UTILS") "/csp/src/cspbuild.scm"))

(define result (check-deadlock-symbolic! "build_dining_eight_det.sys"))
(dis "result=" (if result "deadlock-free" "DEADLOCK") dnl)
(exit)
ENDSCM

echo "=== N=8 Dining Philosophers Symbolic Deadlock Check ==="
echo ""

echo "--- WITHOUT GC ---"
/usr/bin/time -l sh -c "cd '$TDIR' && M3UTILS='$M3UTILS' '$CSPC' -scm bench_nogc.scm 2>&1" 2>&1
echo ""

echo "--- WITH GC ---"
/usr/bin/time -l sh -c "cd '$TDIR' && M3UTILS='$M3UTILS' '$CSPC' -scm bench_gc.scm 2>&1" 2>&1

rm -rf "$TDIR"
