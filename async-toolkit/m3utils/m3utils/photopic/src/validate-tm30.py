#!/usr/bin/env python3
"""
Compute TM-30 reference values for known illuminants using colour-science.
Used to validate the Scheme TM-30 implementation in photopic.

Usage:
    python3 validate-tm30.py
"""

import numpy as np

# Suppress scipy warning
import warnings
warnings.filterwarnings("ignore")

from colour.colorimetry import SDS_ILLUMINANTS, SpectralShape
from colour.temperature import CCT_to_uv_Ohno2013, uv_to_CCT_Ohno2013
from colour.quality import colour_fidelity_index
from colour.quality.cfi2017 import (
    colour_fidelity_index_CIE2017,
    CCT_reference_illuminant,
)

try:
    # Try to get full specification with additional_data
    from colour.quality.tm3018 import colour_fidelity_index_ANSIIESTM3018
    HAS_TM3018 = True
except ImportError:
    HAS_TM3018 = False


def compute_tm30_reference(name, sd):
    """Compute TM-30 metrics for a spectral distribution."""
    print(f"\n=== {name} ===")

    # CCT
    cct_duv = CCT_reference_illuminant(sd)
    print(f"CCT = {cct_duv[0]:.2f} K, Duv = {cct_duv[1]:.6f}")

    # CIE 2017 Rf
    try:
        spec = colour_fidelity_index_CIE2017(sd, additional_data=True)
        print(f"Rf (CIE 2017) = {spec.R_f:.4f}")
        print(f"R_s (first 5) = {spec.R_s[:5]}")
    except Exception as e:
        print(f"CIE 2017 error: {e}")
        # Fallback: just Rf
        Rf = colour_fidelity_index_CIE2017(sd)
        print(f"Rf (CIE 2017) = {Rf:.4f}")

    # IES TM-30-18 (if available)
    if HAS_TM3018:
        try:
            spec18 = colour_fidelity_index_ANSIIESTM3018(sd, additional_data=True)
            print(f"Rf (TM-30-18) = {spec18.R_f:.4f}")
            print(f"Rg (TM-30-18) = {spec18.R_g:.4f}")
            # Rcs per bin
            if hasattr(spec18, 'R_cs'):
                print(f"Rcs = {spec18.R_cs}")
        except Exception as e:
            print(f"TM-30-18 error: {e}")


# Illuminant A (2856K blackbody) — should give Rf ≈ 100
sd_A = SDS_ILLUMINANTS["A"]
compute_tm30_reference("Illuminant A (2856K)", sd_A)

# FL2 (cool white fluorescent) — known Rf ≈ 70
sd_FL2 = SDS_ILLUMINANTS["FL2"]
compute_tm30_reference("FL2 (Cool White Fluorescent)", sd_FL2)

# FL11 — another common test
if "FL11" in SDS_ILLUMINANTS:
    sd_FL11 = SDS_ILLUMINANTS["FL11"]
    compute_tm30_reference("FL11", sd_FL11)

# D65 — daylight reference
sd_D65 = SDS_ILLUMINANTS["D65"]
compute_tm30_reference("D65 (Daylight)", sd_D65)

# Also print Planckian 3000K for warm white validation
from colour.colorimetry import sd_blackbody
sd_3000 = sd_blackbody(3000, SpectralShape(380, 780, 1))
compute_tm30_reference("Planckian 3000K", sd_3000)

print("\n=== Summary for Scheme validation ===")
print("(Expected Rf values for comparison)")
print("Illuminant A:    Rf ≈ 100 (Planckian reference = itself)")
print("FL2:             Rf ≈ 70")
print("Planckian 3000K: Rf ≈ 100")
