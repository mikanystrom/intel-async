#!/bin/sh
# Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information.
# SPDX-License-Identifier: Apache-2.0
#
# Generate uncensored .scm files from .CENSORED versions.
# Censored constants are replaced with plausible dummy values
# so that the code can be loaded and tested.  The actual values
# are proprietary and not included in this repository.

DIR="$(cd "$(dirname "$0")" && pwd)"

# Use GNU sed if available (needed on macOS)
if command -v gsed >/dev/null 2>&1; then
  SED=gsed
else
  SED=sed
fi

######################################################################
# yield.scm
#
# The tsmc-d0-correction function has censored area thresholds and
# correction values.  We replace them with plausible dummy values.
# The function returns a negative D0 correction for large die areas.
######################################################################

$SED \
  -e '0,/XXX/{s/(> a XXX) -X.XXX)/(> a 400) -0.030)/}' \
  -e '0,/XXX/{s/(> a XXX) -X.XXX)/(> a 300) -0.025)/}' \
  -e '0,/XXX/{s/(> a XXX) -X.XXX)/(> a 200) -0.020)/}' \
  -e '0,/XXX/{s/(> a XXX) -X.XXX)/(> a 100) -0.010)/}' \
  "$DIR/yield.scm.CENSORED" > "$DIR/yield.scm"

echo "Generated yield.scm"

######################################################################
# defs-21ww07.scm
#
# *n5-saturation-D0* — the N5 saturation defect density.
# Comment says TOM thinks 0.070, "we split the difference"
# so the actual value is likely around 0.075.
######################################################################

$SED \
  -e 's/\*n5-saturation-D0\* X\.XXX/*n5-saturation-D0* 0.075/' \
  -e 's/is X\.XXX/is 0.080/' \
  "$DIR/defs-21ww07.scm.CENSORED" > "$DIR/defs-21ww07.scm"

echo "Generated defs-21ww07.scm"

######################################################################
# reports-21ww38.scm
#
# N3 layer counts and defect densities.
# N5 uses n=32 layers; N3 with more metal layers would be higher.
# D0 values decrease over time as the process matures.
######################################################################

$SED \
  -e 's/\*n3-17m-n\* XX\.XX/*n3-17m-n* 34.00/' \
  -e 's/\*n3-18m-n\* XX\.XX/*n3-18m-n* 36.00/' \
  -e 's/\*n3-d0-2023q3\*   X\.XXX/*n3-d0-2023q3*   0.100/' \
  -e 's/\*n3-d0-2024q3\*   X\.XXX/*n3-d0-2024q3*   0.080/' \
  -e 's/\*n3-d0-2025q4\*   X\.XXX/*n3-d0-2025q4*   0.065/' \
  "$DIR/reports-21ww38.scm.CENSORED" > "$DIR/reports-21ww38.scm"

echo "Generated reports-21ww38.scm"
