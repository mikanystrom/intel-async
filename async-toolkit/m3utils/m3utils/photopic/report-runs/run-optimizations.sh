#!/bin/sh
#
# Run photopic luminous efficacy optimizations at various CRI constraints.
#
# Each invocation maximizes luminous efficacy of radiation (LER) for a
# 2700K CCT spectrum, subject to a minimum CRI (Ra) constraint.
# R9 is unconstrained (min R9 = -100, effectively no constraint).
#
# The optimizer uses hierarchical subdivision: starting at 2 spectral
# parameters and doubling 7 times to reach 129 parameters (3.05 nm
# spacing across 380-770 nm).  Output spectra are sampled at 1 nm
# (391 points).
#
# Results are written to the current directory:
#   <cct>_CRI<cri>_R9=-100_<dims>.res  — optimization metrics at each level
#   w_<cct>_CRI<cri>_R9=-100_<dims>.dat — spectral data at each level
#   base_<cct>.dat                       — unmodified blackbody reference
#
# Usage:
#   cd report-runs
#   ./run-optimizations.sh            # run all CRI levels
#   ./run-optimizations.sh 90         # run only CRI >= 90
#   ./run-optimizations.sh 80 85 90   # run specific levels
#
# Prerequisites:
#   - photopic binary built in ../ARM64_DARWIN/ (or appropriate target)
#   - photopic.scm in ../src/
#

PHOTOPIC=../ARM64_DARWIN/photopic
SCMFILE=../src/photopic.scm
CCT=2700

if [ ! -x "$PHOTOPIC" ]; then
    echo "Error: photopic binary not found at $PHOTOPIC" >&2
    echo "Build it first: cd ../src && cm3 -override" >&2
    exit 1
fi

if [ ! -f "$SCMFILE" ]; then
    echo "Error: photopic.scm not found at $SCMFILE" >&2
    exit 1
fi

# Default: all CRI levels used in the report
if [ $# -eq 0 ]; then
    set -- 60 70 80 82 85 90 95 98
fi

for cri in "$@"; do
    echo "=== Running CCT=${CCT} CRI>=${cri} R9>=-100 ==="
    $PHOTOPIC -run $CCT $cri -100 -scm -scmfile $SCMFILE
    echo ""
done

echo "=== All runs complete ==="
echo "Generate figures with: python3 plot_spectra.py"
