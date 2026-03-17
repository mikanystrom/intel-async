#!/bin/sh
#
# Sweep: maximize TM-30 Rf as a function of required efficacy (uncorrected LER)
#
# For each efficacy threshold, find the spectrum that maximizes TM-30 Rf
# (color fidelity over 99 CES samples) while maintaining CRI >= 80 at 2700K.
#
# This produces the data for the "Rf achievable vs required efficacy"
# curve, complementing the R9 sweep.
#
# Usage:
#   cd report-runs
#   ./run-maxRf-sweep.sh
#

PHOTOPIC=../ARM64_DARWIN/photopic
SCMFILE=../src/photopic.scm
CCT=2700
CRI=80

if [ ! -x "$PHOTOPIC" ]; then
    echo "Error: photopic binary not found at $PHOTOPIC" >&2
    echo "Build it first: cd ../src && cm3 -override" >&2
    exit 1
fi

echo "=== Max-Rf sweep (uncorrected LER): CCT=${CCT} CRI>=${CRI} ==="

# Sweep efficacy from 300 to 430 lm/W in steps of 10
for eff in 300 310 320 330 340 350 360 370 380 390 400 410 420 430; do
    echo "=== Maximize Rf at CCT=${CCT} CRI>=${CRI} efficacy>=${eff} ==="
    $PHOTOPIC -grid -tm30 -run-maxRf $CCT $CRI $eff -scm -scmfile $SCMFILE
    echo ""
done

echo "=== Sweep complete ==="
echo "Generate figures with: python3 plot_maxRf_sweep.py"
