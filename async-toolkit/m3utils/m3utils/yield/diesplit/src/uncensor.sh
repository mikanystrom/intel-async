#!/bin/sh
# Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information.
# SPDX-License-Identifier: Apache-2.0
#
# Generate .scm files from .CENSORED versions.
# Censored constants are replaced with FICTITIOUS DUMMY values
# so that the code can be loaded and tested.
#
# WARNING: The replacement values are MADE UP.  They are NOT real
# proprietary data.  DO NOT USE FOR PRODUCTION YIELD ESTIMATES.
# The actual values are subject to NDA and are not in this repository.

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
  -e 's/;; CENSORED/\n;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;\n;; WARNING: ALL VALUES IN THIS FUNCTION ARE FICTITIOUS PLACEHOLDERS.\n;; They are MADE-UP numbers to stand in for proprietary data.\n;; DO NOT USE FOR PRODUCTION YIELD ESTIMATES.\n;; The real values are subject to NDA and are not in this repository.\n;; Contact your TSMC representative for further information.\n;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;/' \
  -e '0,/XXX/{s/(> a XXX) -X.XXX)/(> a 400) -0.030)  ;; FICTITIOUS - not a real TSMC value/}' \
  -e '0,/XXX/{s/(> a XXX) -X.XXX)/(> a 300) -0.025)  ;; FICTITIOUS - not a real TSMC value/}' \
  -e '0,/XXX/{s/(> a XXX) -X.XXX)/(> a 200) -0.020)  ;; FICTITIOUS - not a real TSMC value/}' \
  -e '0,/XXX/{s/(> a XXX) -X.XXX)/(> a 100) -0.010)  ;; FICTITIOUS - not a real TSMC value/}' \
  "$DIR/yield.scm.CENSORED" > "$DIR/yield.scm"

echo "Generated yield.scm (with FICTITIOUS placeholder values)"

######################################################################
# defs-21ww07.scm
#
# *n5-saturation-D0* — the N5 saturation defect density.
# Comment says TOM thinks 0.070, "we split the difference"
# so the actual value is likely around 0.075.
######################################################################

$SED \
  -e 's/\*n5-saturation-D0\* X\.XXX/*n5-saturation-D0* 0.075)  ;; FICTITIOUS - not a real TSMC value/' \
  -e 's/is X\.XXX ; CENSORED/is CENSORED\n;; the dummy value above is chosen to be plausible but is NOT real/' \
  -e '3a\;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;\n;; WARNING: Values in this file marked FICTITIOUS are MADE-UP\n;; placeholders for proprietary data.  DO NOT USE FOR PRODUCTION\n;; YIELD ESTIMATES.  Real values are subject to NDA.\n;; Contact your TSMC representative for further information.\n;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;' \
  "$DIR/defs-21ww07.scm.CENSORED" > "$DIR/defs-21ww07.scm"

echo "Generated defs-21ww07.scm (with FICTITIOUS placeholder values)"

######################################################################
# reports-21ww38.scm
#
# N3 layer counts and defect densities.
# N5 uses n=32 layers; N3 with more metal layers would be higher.
# D0 values decrease over time as the process matures.
######################################################################

$SED \
  -e 's/;; CENSORED$/;; FICTITIOUS - not a real value/' \
  -e 's/;; all below CENSORED/;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;\n;; WARNING: ALL VALUES BELOW ARE FICTITIOUS PLACEHOLDERS.\n;; They are MADE-UP numbers to stand in for proprietary data.\n;; DO NOT USE FOR PRODUCTION YIELD ESTIMATES.\n;; The real values are subject to NDA and are not in this repository.\n;; Contact your TSMC representative for further information.\n;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;/' \
  -e 's/\*n3-17m-n\* XX\.XX/*n3-17m-n* 34.00/' \
  -e 's/\*n3-18m-n\* XX\.XX/*n3-18m-n* 36.00/' \
  -e 's/\*n3-d0-2023q3\*   X\.XXX/*n3-d0-2023q3*   0.100)  ;; FICTITIOUS/' \
  -e 's/\*n3-d0-2024q3\*   X\.XXX/*n3-d0-2024q3*   0.080)  ;; FICTITIOUS/' \
  -e 's/\*n3-d0-2025q4\*   X\.XXX/*n3-d0-2025q4*   0.065)  ;; FICTITIOUS/' \
  "$DIR/reports-21ww38.scm.CENSORED" > "$DIR/reports-21ww38.scm"

echo "Generated reports-21ww38.scm (with FICTITIOUS placeholder values)"
