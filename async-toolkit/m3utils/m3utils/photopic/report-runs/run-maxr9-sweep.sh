#!/bin/sh
#
# Sweep: maximize R9 as a function of required efficacy (EU scenario)
#
# For each efficacy threshold, find the spectrum that maximizes R9
# while maintaining CRI >= 80 (EU Ecodesign requirement) at 2700K.
#
# This produces the data for the "R9 achievable vs required efficacy"
# curve---the inverse problem.
#
# Usage:
#   cd report-runs
#   ./run-maxr9-sweep.sh
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

# Sweep efficacy from 300 to 430 lm/W in steps of 10
for eff in 300 310 320 330 340 350 360 370 380 390 400 410 420 430; do
    echo "=== Maximize R9 at CCT=${CCT} CRI>=${CRI} efficacy>=${eff} ==="
    $PHOTOPIC -run-maxr9 $CCT $CRI $eff -scm -scmfile $SCMFILE
    echo ""
done

echo "=== Sweep complete ==="
echo "Generate figures with: python3 plot_spectra.py"
