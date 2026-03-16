#!/bin/sh
#
# Sweep: maximize R9 as a function of required efficacy
# using the Philips phosphor-converted LED loss model
#
# The Philips model accounts for Stokes shift and quantum efficiency
# losses in phosphor conversion from a 450nm blue pump LED.
# Cost C(lambda) = max(1, lambda / (lambda_pump * QE))
# where lambda_pump = 450nm, QE = 0.90
#
# Runs multiple efficacy thresholds in parallel (10 at a time).
# For each threshold, finds the spectrum maximizing R9 while
# maintaining CRI >= $CRI_MIN at 2700K with Philips-corrected efficacy.
#
# Usage:
#   ./run-maxr9-sweep-parallel.sh          # CRI >= 80 (default)
#   ./run-maxr9-sweep-parallel.sh 95       # CRI >= 95
#

PHOTOPIC=../ARM64_DARWIN/photopic
SCMFILE=../src/photopic.scm
CCT=2700
CRI=${1:-80}
PARALLEL=10

if [ ! -x "$PHOTOPIC" ]; then
    echo "Error: photopic binary not found at $PHOTOPIC" >&2
    exit 1
fi

echo "=== Max-R9 sweep (Philips-corrected): CCT=${CCT} CRI>=${CRI} ==="
echo "=== Running ${PARALLEL} jobs in parallel ==="
echo ""

# Efficacy thresholds to sweep (Philips-corrected lm/W)
# These are lower than uncorrected LER because of phosphor losses.
# Philips correction factor at 600nm (warm white peak): ~1.48
# So LER 400 -> Philips ~270, LER 350 -> Philips ~237
# We sweep from 200 to 320 in Philips-corrected lm/W
EFFS="200 210 220 230 240 250 255 260 265 270 275 280 285 290 295 300 305 310 315 320"

running=0
for eff in $EFFS; do
    echo "Starting: Philips-corrected efficacy >= ${eff} lm/W"
    $PHOTOPIC -run-maxr9-philips $CCT $CRI $eff -scm -scmfile $SCMFILE > /dev/null 2>&1 &
    running=$((running + 1))
    if [ $running -ge $PARALLEL ]; then
        wait -n 2>/dev/null || wait
        running=$((running - 1))
    fi
done

wait
echo ""
echo "=== Sweep complete: CRI>=${CRI} (Philips-corrected) ==="
echo "Generate figures with: python3 plot_maxr9_sweep.py ${CRI}"
