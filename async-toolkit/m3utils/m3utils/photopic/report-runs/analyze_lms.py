#!/usr/bin/env python3
"""
LMS Cone Excitation Analysis

Compare how different 2700K light sources stimulate the L, M, S cones
of the human eye. Quantifies the physiological basis for perceived
differences between incandescent and LED spectra, even when colorimetric
metrics (CRI, CCT, Duv) are matched.

Uses:
- CIE 1931 2-degree color matching functions
- Hunt-Pointer-Estevez (HPE) chromatic adaptation transform (XYZ -> LMS)
- Von Kries adaptation model
- Cone contrast metrics

Sources compared:
1. 2700K Planckian (blackbody) radiator — the reference
2. Waveform Lighting Centric Home A19 2700K LED — digitized from datasheet
3. Optimized spectra from our photopic tool at various CRI levels
"""

import os
import re
import sys
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.gridspec import GridSpec

RUNDIR = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------------------
# CIE 1931 2-degree color matching functions, 5nm spacing, 380-780nm
# Source: CIE 15:2004, Table 1
# ---------------------------------------------------------------------------
CMF_WL = np.arange(380, 785, 5, dtype=float)  # 81 points
CMF_X = np.array([
    0.001368, 0.002236, 0.004243, 0.007650, 0.014310,
    0.023190, 0.043510, 0.077630, 0.134380, 0.214770,
    0.283900, 0.328500, 0.348280, 0.348060, 0.336200,
    0.318700, 0.290800, 0.251100, 0.195360, 0.142100,
    0.095640, 0.058010, 0.032010, 0.014700, 0.004900,
    0.002400, 0.009300, 0.029100, 0.063270, 0.109600,
    0.165500, 0.225750, 0.290400, 0.359500, 0.433450,
    0.512050, 0.594500, 0.678400, 0.762100, 0.842500,
    0.916300, 0.978600, 1.026300, 1.056700, 1.062200,
    1.045600, 1.002600, 0.938400, 0.854450, 0.751400,
    0.642400, 0.541900, 0.447900, 0.360800, 0.283500,
    0.218700, 0.164900, 0.121200, 0.087400, 0.063600,
    0.046770, 0.032900, 0.022700, 0.015840, 0.011359,
    0.008111, 0.005790, 0.004109, 0.002899, 0.002049,
    0.001440, 0.001000, 0.000690, 0.000476, 0.000332,
    0.000235, 0.000166, 0.000117, 0.000083, 0.000059,
    0.000042,
])
CMF_Y = np.array([
    0.000039, 0.000064, 0.000120, 0.000217, 0.000396,
    0.000640, 0.001210, 0.002180, 0.004000, 0.007300,
    0.011600, 0.016840, 0.023000, 0.029800, 0.038000,
    0.048000, 0.060000, 0.073900, 0.090980, 0.112600,
    0.139020, 0.169300, 0.208020, 0.258600, 0.323000,
    0.407300, 0.503000, 0.608200, 0.710000, 0.793200,
    0.862000, 0.914850, 0.954000, 0.980300, 0.994950,
    1.000000, 0.995000, 0.978600, 0.952000, 0.915400,
    0.870000, 0.816300, 0.757000, 0.694900, 0.631000,
    0.566800, 0.503000, 0.441200, 0.381000, 0.321000,
    0.265000, 0.217000, 0.175000, 0.138200, 0.107000,
    0.081600, 0.061000, 0.044580, 0.032000, 0.023200,
    0.017000, 0.011920, 0.008210, 0.005723, 0.004102,
    0.002929, 0.002091, 0.001484, 0.001047, 0.000740,
    0.000520, 0.000361, 0.000249, 0.000172, 0.000120,
    0.000085, 0.000060, 0.000042, 0.000030, 0.000021,
    0.000015,
])
CMF_Z = np.array([
    0.006450, 0.010550, 0.020050, 0.036210, 0.067850,
    0.110200, 0.207400, 0.371300, 0.645600, 1.039050,
    1.385600, 1.622960, 1.747060, 1.782600, 1.772110,
    1.744100, 1.669200, 1.528100, 1.287640, 1.041900,
    0.812950, 0.616200, 0.465180, 0.353300, 0.272000,
    0.212300, 0.158200, 0.111700, 0.078250, 0.057250,
    0.042160, 0.029840, 0.020300, 0.013400, 0.008750,
    0.005750, 0.003900, 0.002750, 0.002100, 0.001800,
    0.001650, 0.001400, 0.001100, 0.001000, 0.000800,
    0.000600, 0.000340, 0.000240, 0.000190, 0.000100,
    0.000050, 0.000030, 0.000020, 0.000010, 0.000000,
    0.000000, 0.000000, 0.000000, 0.000000, 0.000000,
    0.000000, 0.000000, 0.000000, 0.000000, 0.000000,
    0.000000, 0.000000, 0.000000, 0.000000, 0.000000,
    0.000000, 0.000000, 0.000000, 0.000000, 0.000000,
    0.000000, 0.000000, 0.000000, 0.000000, 0.000000,
    0.000000,
])

# Hunt-Pointer-Estevez (HPE) normalized chromatic adaptation matrix
# XYZ -> LMS  (used in CIECAM97s, physiologically-based)
M_HPE = np.array([
    [ 0.38971,  0.68898, -0.07868],
    [-0.22981,  1.18340,  0.04641],
    [ 0.00000,  0.00000,  1.00000],
])

# ---------------------------------------------------------------------------
# CIE 1951 Scotopic luminosity function V'(λ), 5nm, 380-780nm
# Peaks at 507nm.  Rod photoreceptor sensitivity.
# Source: CIE 1951, ISO 23539:2005
# ---------------------------------------------------------------------------
SCOTOPIC_V = np.array([
    0.000589, 0.001108, 0.002209, 0.004530, 0.009290,
    0.018480, 0.034840, 0.060400, 0.096600, 0.143900,
    0.208100, 0.308600, 0.451800, 0.567000, 0.676000,
    0.793000, 0.904000, 0.982000, 0.997000, 1.000000,
    0.997000, 0.975000, 0.935000, 0.880000, 0.811000,
    0.733000, 0.650000, 0.564000, 0.481000, 0.402000,
    0.328100, 0.264600, 0.207600, 0.160200, 0.121200,
    0.089900, 0.065500, 0.046900, 0.033150, 0.022740,
    0.015640, 0.010900, 0.007650, 0.005400, 0.003830,
    0.002700, 0.001900, 0.001350, 0.000960, 0.000680,
    0.000478, 0.000340, 0.000240, 0.000170, 0.000120,
    0.000085, 0.000060, 0.000042, 0.000030, 0.000021,
    0.000015, 0.000010, 0.000007, 0.000005, 0.000004,
    0.000003, 0.000002, 0.000001, 0.000001, 0.000001,
    0.000000, 0.000000, 0.000000, 0.000000, 0.000000,
    0.000000, 0.000000, 0.000000, 0.000000, 0.000000,
    0.000000,
])

# ---------------------------------------------------------------------------
# CIE S 026:2018 Melanopic sensitivity function smel(λ), 5nm, 380-780nm
# ipRGC (intrinsically photosensitive retinal ganglion cell) spectral
# sensitivity, corrected for pre-receptoral filtering (lens, macular pigment).
# In-vivo peak ~490nm.
# Source: CIE S 026/E:2018, Lucas et al. (2014)
# ---------------------------------------------------------------------------
MELANOPIC_S = np.array([
    0.00070, 0.00130, 0.00240, 0.00450, 0.00850,
    0.01590, 0.02920, 0.05100, 0.08430, 0.13300,
    0.20200, 0.29600, 0.41700, 0.53500, 0.66800,
    0.79400, 0.90400, 0.96700, 0.99300, 1.00000,
    0.98800, 0.95200, 0.89200, 0.81600, 0.72400,
    0.62600, 0.52400, 0.42600, 0.33600, 0.25800,
    0.19200, 0.13900, 0.09830, 0.06780, 0.04570,
    0.03020, 0.01960, 0.01250, 0.00790, 0.00490,
    0.00300, 0.00183, 0.00111, 0.00067, 0.00040,
    0.00024, 0.00014, 0.00009, 0.00005, 0.00003,
    0.00002, 0.00001, 0.00001, 0.00000, 0.00000,
    0.00000, 0.00000, 0.00000, 0.00000, 0.00000,
    0.00000, 0.00000, 0.00000, 0.00000, 0.00000,
    0.00000, 0.00000, 0.00000, 0.00000, 0.00000,
    0.00000, 0.00000, 0.00000, 0.00000, 0.00000,
    0.00000, 0.00000, 0.00000, 0.00000, 0.00000,
    0.00000,
])

# Physical constants
h = 6.62607015e-34  # Planck constant
c = 2.99792458e8    # speed of light
k = 1.380649e-23    # Boltzmann constant

# Photopic luminous efficacy
K_M = 683.0  # lm/W

# Philips cost model
PUMP_NM, PUMP_QE = 450.0, 0.90


def planck_spd(wl_nm, T):
    """Planckian (blackbody) spectral power distribution.
    Returns relative spectral radiance at given wavelengths and temperature."""
    wl_m = wl_nm * 1e-9
    num = 2 * h * c**2 / wl_m**5
    denom = np.exp(h * c / (wl_m * k * T)) - 1
    return num / denom


def spd_to_xyz(wl_nm, spd):
    """Compute CIE XYZ tristimulus values from SPD via CIE 1931 CMFs."""
    x_bar = np.interp(wl_nm, CMF_WL, CMF_X, left=0, right=0)
    y_bar = np.interp(wl_nm, CMF_WL, CMF_Y, left=0, right=0)
    z_bar = np.interp(wl_nm, CMF_WL, CMF_Z, left=0, right=0)
    _t = np.trapezoid if hasattr(np, 'trapezoid') else np.trapezoid
    X = _t(spd * x_bar, wl_nm)
    Y = _t(spd * y_bar, wl_nm)
    Z = _t(spd * z_bar, wl_nm)
    return np.array([X, Y, Z])


def xyz_to_lms(xyz):
    """Convert CIE XYZ to LMS cone excitations via HPE matrix."""
    return M_HPE @ xyz


def spd_to_lms(wl_nm, spd):
    """SPD -> LMS in one step."""
    return xyz_to_lms(spd_to_xyz(wl_nm, spd))


def von_kries_adapt(lms, lms_white):
    """Apply von Kries chromatic adaptation.
    Returns adapted LMS (normalized so that white -> [1,1,1])."""
    return lms / lms_white


def cone_contrast(lms1, lms2):
    """Root-mean-square cone contrast between two adapted LMS vectors."""
    dc = (lms1 - lms2) / lms2
    return np.sqrt(np.mean(dc**2))


def ler(wl_nm, spd):
    """Luminous efficacy of radiation (lm/W)."""
    y_bar = np.interp(wl_nm, CMF_WL, CMF_Y, left=0, right=0)
    _t = np.trapezoid if hasattr(np, 'trapezoid') else np.trapezoid
    return K_M * _t(spd * y_bar, wl_nm) / _t(spd, wl_nm)


def philips_ler(wl_nm, spd):
    """Philips-corrected LER (accounts for Stokes shift cost)."""
    y_bar = np.interp(wl_nm, CMF_WL, CMF_Y, left=0, right=0)
    _t = np.trapezoid if hasattr(np, 'trapezoid') else np.trapezoid
    lum = _t(spd * y_bar, wl_nm)
    cost = np.ones_like(wl_nm)
    mask = wl_nm > PUMP_NM
    cost[mask] = wl_nm[mask] / (PUMP_NM * PUMP_QE)
    return K_M * lum / _t(spd * cost, wl_nm)


def xy_from_xyz(xyz):
    """CIE xy chromaticity from XYZ."""
    s = xyz.sum()
    if s == 0:
        return 0, 0
    return xyz[0] / s, xyz[1] / s


def cct_approx(x, y):
    """Approximate CCT from CIE xy using McCamy's formula."""
    n = (x - 0.3320) / (0.1858 - y)
    return 449 * n**3 + 3525 * n**2 + 6823.3 * n + 5520.33


def spd_to_5channel(wl_nm, spd):
    """Compute all 5 receptor channel responses: L, M, S, Rod, Melanopic."""
    lms = spd_to_lms(wl_nm, spd)
    _t = np.trapezoid if hasattr(np, 'trapezoid') else np.trapezoid
    rod_sens = np.interp(wl_nm, CMF_WL, SCOTOPIC_V, left=0, right=0)
    mel_sens = np.interp(wl_nm, CMF_WL, MELANOPIC_S, left=0, right=0)
    rod = _t(spd * rod_sens, wl_nm)
    mel = _t(spd * mel_sens, wl_nm)
    return np.array([lms[0], lms[1], lms[2], rod, mel])


def five_channel_contrast(ch1, ch2):
    """RMSCC across all 5 channels."""
    dc = (ch1 - ch2) / ch2
    return np.sqrt(np.mean(dc**2))


def sp_ratio(wl_nm, spd):
    """Scotopic/Photopic (S/P) ratio.
    Ratio of scotopic luminous flux to photopic luminous flux."""
    y_bar = np.interp(wl_nm, CMF_WL, CMF_Y, left=0, right=0)
    v_prime = np.interp(wl_nm, CMF_WL, SCOTOPIC_V, left=0, right=0)
    _t = np.trapezoid if hasattr(np, 'trapezoid') else np.trapezoid
    K_M_SCOT = 1700.0  # scotopic luminous efficacy, lm/W
    photopic = K_M * _t(spd * y_bar, wl_nm)
    scotopic = K_M_SCOT * _t(spd * v_prime, wl_nm)
    return scotopic / photopic


def mesopic_luminance(L_p, sp):
    """CIE 191:2010 mesopic luminance from photopic luminance and S/P ratio.
    L_p: photopic luminance (cd/m^2)
    sp: S/P ratio of the source
    Returns: mesopic luminance (cd/m^2), adaptation coefficient m."""
    # CIE 191:2010 iterative procedure
    # L_mes = m * L_p + (1 - m) * L_s, where L_s = sp * L_p * (683/1700)
    # The factor 683/1700 converts scotopic to photopic-equivalent cd/m^2
    L_s = L_p * sp * (K_M / 1700.0)

    # Iterative: m depends on L_mes
    m = 0.5  # initial guess
    for _ in range(20):
        L_mes = m * L_p + (1 - m) * L_s
        if L_mes <= 0.005:
            m = 0.0
        elif L_mes >= 5.0:
            m = 1.0
        else:
            # CIE formula: m = 0.767 + 0.3334 * log10(L_mes)
            m_new = 0.767 + 0.3334 * np.log10(L_mes)
            m_new = np.clip(m_new, 0, 1)
            if abs(m_new - m) < 1e-6:
                m = m_new
                break
            m = m_new
    L_mes = m * L_p + (1 - m) * L_s
    return L_mes, m


def melanopic_edi(wl_nm, spd):
    """Melanopic Equivalent Daylight Illuminance (M-EDI) per CIE S 026:2018.
    Returns M-EDI in melanopic lux, given SPD normalized to some illuminance."""
    mel_sens = np.interp(wl_nm, CMF_WL, MELANOPIC_S, left=0, right=0)
    y_bar = np.interp(wl_nm, CMF_WL, CMF_Y, left=0, right=0)
    _t = np.trapezoid if hasattr(np, 'trapezoid') else np.trapezoid
    # Melanopic irradiance (relative)
    mel_irr = _t(spd * mel_sens, wl_nm)
    # Photopic illuminance (relative)
    phot_ill = K_M * _t(spd * y_bar, wl_nm)
    # Melanopic action factor (ratio of melanopic sensitivity to D65 reference)
    # For D65, the melanopic/photopic ratio is approximately 1.0 by definition
    # M-EDI = melanopic_irr * K_mel_D65 where K_mel_D65 = 1.3262 (CIE S 026)
    # Simplified: M-EDI / E_v = melanopic_DLR (daylight response factor)
    # melanopic_DLR = (mel_irr / phot_ill) * K_M * 1.3262
    K_MEL_D65 = 1.3262  # melanopic efficacy ratio for D65
    mel_dlr = (mel_irr / (phot_ill / K_M)) * K_MEL_D65
    return mel_dlr  # This is the melanopic DLR (M-EDI / photopic lux)


def cone_excitation_by_band(wl_nm, spd, bands=None):
    """Break down LMS cone excitation by wavelength band.
    Returns dict: band_label -> (L_frac, M_frac, S_frac)."""
    if bands is None:
        bands = [
            ('380-420', 380, 420),
            ('420-460', 420, 460),
            ('460-500', 460, 500),
            ('500-560', 500, 560),
            ('560-620', 560, 620),
            ('620-680', 620, 680),
            ('680-780', 680, 780),
        ]

    total_lms = spd_to_lms(wl_nm, spd)
    result = {}
    for label, lo, hi in bands:
        mask = (wl_nm >= lo) & (wl_nm < hi)
        band_spd = np.where(mask, spd, 0)
        band_lms = spd_to_lms(wl_nm, band_spd)
        result[label] = band_lms / total_lms
    return result, total_lms


# ---------------------------------------------------------------------------
# Waveform Lighting Centric Home A19 2700K — digitized from datasheet
# Specs: CRI 95+, R9=91, R12=91, Duv=0.0000, CIE xy=(0.4598, 0.4106)
# ---------------------------------------------------------------------------
def waveform_2700k_spd():
    """Return (wl_nm, relative_power) for the Waveform 2700K LED.
    Digitized from the datasheet spectrum chart (420-740nm range).
    Target: CIE xy = (0.4598, 0.4106), CCT = 2700K.
    Adjusted to match target chromaticity via iterative correction."""
    # Wavelength (nm) and relative spectral power
    # Blue pump at 450nm (~35% of peak), phosphor peak ~610nm,
    # extended red tail to match warm CCT
    data = np.array([
        [420, 0.005], [425, 0.015], [430, 0.04], [435, 0.08],
        [438, 0.12], [440, 0.17], [442, 0.22], [444, 0.27],
        [446, 0.31], [448, 0.34], [450, 0.36], [452, 0.34],
        [454, 0.30], [456, 0.25], [458, 0.20], [460, 0.16],
        [462, 0.13], [465, 0.10], [468, 0.085], [470, 0.08],
        [475, 0.08], [480, 0.10], [485, 0.14], [490, 0.19],
        [495, 0.26], [500, 0.33], [505, 0.40], [510, 0.47],
        [515, 0.54], [520, 0.60], [525, 0.66], [530, 0.71],
        [535, 0.76], [540, 0.80], [545, 0.84], [550, 0.87],
        [555, 0.90], [560, 0.92], [565, 0.94], [570, 0.96],
        [575, 0.97], [580, 0.98], [585, 0.99], [590, 0.995],
        [595, 1.00], [600, 1.00], [605, 1.00], [610, 1.00],
        [615, 0.99], [620, 0.97], [625, 0.94], [630, 0.90],
        [635, 0.85], [640, 0.80], [645, 0.74], [650, 0.67],
        [655, 0.60], [660, 0.53], [665, 0.46], [670, 0.39],
        [675, 0.33], [680, 0.27], [685, 0.22], [690, 0.17],
        [695, 0.13], [700, 0.10], [705, 0.07], [710, 0.05],
        [715, 0.035], [720, 0.025], [725, 0.015], [730, 0.008],
        [740, 0.003],
    ])
    wl, power = data[:, 0], data[:, 1]

    # Fine-tune: match target chromaticity xy=(0.4598, 0.4106)
    # Two parameters: spectral tilt alpha and blue-peak scale beta
    target_x, target_y = 0.4598, 0.4106
    best_alpha, best_beta, best_err = 0, 1, 1e9
    for alpha in np.linspace(-0.5, 3, 350):
        for beta in np.linspace(0.3, 3, 270):
            test_power = power * (wl / 550.0)**alpha
            # Scale the blue pump region (420-475nm)
            blue_mask = wl < 475
            test_power = np.where(blue_mask, test_power * beta, test_power)
            test_spd = np.interp(CMF_WL, wl, test_power, left=0, right=0)
            xyz = np.array([
                np.trapezoid(test_spd * CMF_X, CMF_WL),
                np.trapezoid(test_spd * CMF_Y, CMF_WL),
                np.trapezoid(test_spd * CMF_Z, CMF_WL),
            ])
            s = xyz.sum()
            if s > 0:
                err = (xyz[0]/s - target_x)**2 + (xyz[1]/s - target_y)**2
                if err < best_err:
                    best_err = err
                    best_alpha = alpha
                    best_beta = beta

    power = power * (wl / 550.0)**best_alpha
    blue_mask = wl < 475
    power = np.where(blue_mask, power * best_beta, power)
    return wl, power / np.max(power)


def load_dat(fname):
    """Load a photopic .dat file (wavelength_m, power)."""
    data = np.loadtxt(fname)
    wl_nm = data[:, 0] * 1e9
    power = data[:, 1]
    return wl_nm, power


def normalize_spd(spd):
    """Normalize SPD to unit area for fair comparison."""
    _t = np.trapezoid if hasattr(np, 'trapezoid') else np.trapezoid
    return spd / _t(spd, np.arange(len(spd)))


# ---------------------------------------------------------------------------
# CRI test color sample reflectances (TCS01-TCS14)
# Approximate reflectance curves at key wavelengths for a few samples
# We include TCS09 (saturated red) and TCS12 (strong blue)
# ---------------------------------------------------------------------------

# For simplicity, use flat-spectrum analysis on a neutral wall.
# The key insight is the cone excitation difference for the illuminant itself.


def main():
    # ===================================================================
    # 1. Build spectra on a common wavelength grid
    # ===================================================================
    wl = np.arange(380, 781, 2, dtype=float)  # 2nm spacing

    # Blackbody at 2700K
    bb = planck_spd(wl, 2700)

    # Waveform LED
    wf_wl, wf_pow = waveform_2700k_spd()
    wf = np.interp(wl, wf_wl, wf_pow, left=0, right=0)

    # Optimized spectra from photopic tool
    spectra = {}
    spec_files = {
        'CRI 80 (unconstrained)': 'w_2700_CRI80_R9=-100_129.dat',
        'CRI 95 (unconstrained)': 'w_2700_CRI95_R9=-100_129.dat',
        'CRI 80, Phil 250':      'w_2700_CRI80_maxR9P_eff250_129.dat',
        'CRI 95, Phil 250':      'w_2700_CRI95_maxR9P_eff250_129.dat',
    }
    for label, fn in spec_files.items():
        fpath = os.path.join(RUNDIR, fn)
        if os.path.exists(fpath):
            s_wl, s_pow = load_dat(fpath)
            spectra[label] = np.interp(wl, s_wl, s_pow, left=0, right=0)

    # Normalize all SPDs to equal luminous flux (Y = 1000)
    def norm_to_lum(spd, target=1000):
        xyz = spd_to_xyz(wl, spd)
        return spd * target / xyz[1]

    bb_n = norm_to_lum(bb)
    wf_n = norm_to_lum(wf)
    spec_n = {k: norm_to_lum(v) for k, v in spectra.items()}

    # ===================================================================
    # 2. Colorimetric properties
    # ===================================================================
    print("=" * 90)
    print("LMS Cone Excitation Analysis — 2700K Illuminants")
    print("=" * 90)

    all_sources = {'2700K Blackbody': bb_n, 'Waveform A19': wf_n}
    all_sources.update(spec_n)

    print(f"\n{'Source':<28} {'x':>7} {'y':>7} {'CCT':>6} "
          f"{'L':>10} {'M':>10} {'S':>10} {'LER':>6}")
    print("-" * 90)

    ref_lms = spd_to_lms(wl, bb_n)  # blackbody as reference

    source_lms = {}
    for name, spd in all_sources.items():
        xyz = spd_to_xyz(wl, spd)
        x, y = xy_from_xyz(xyz)
        cct = cct_approx(x, y)
        lms = spd_to_lms(wl, spd)
        lr = ler(wl, spd)
        source_lms[name] = lms
        print(f"{name:<28} {x:7.4f} {y:7.4f} {cct:6.0f} "
              f"{lms[0]:10.2f} {lms[1]:10.2f} {lms[2]:10.2f} {lr:6.1f}")

    # ===================================================================
    # 3. Von Kries adapted cone responses & cone contrast
    # ===================================================================
    print(f"\n{'='*90}")
    print("Von Kries Adapted Cone Responses (reference: 2700K blackbody)")
    print(f"{'='*90}")
    print(f"\n{'Source':<28} {'L_a':>8} {'M_a':>8} {'S_a':>8} "
          f"{'dL/L%':>7} {'dM/M%':>7} {'dS/S%':>7} {'RMSCC%':>7}")
    print("-" * 90)

    for name, lms in source_lms.items():
        adapted = von_kries_adapt(lms, ref_lms)
        dl = (adapted[0] - 1) * 100
        dm = (adapted[1] - 1) * 100
        ds = (adapted[2] - 1) * 100
        rmscc = cone_contrast(lms, ref_lms) * 100
        print(f"{name:<28} {adapted[0]:8.5f} {adapted[1]:8.5f} "
              f"{adapted[2]:8.5f} {dl:+7.2f} {dm:+7.2f} {ds:+7.2f} "
              f"{rmscc:7.3f}")

    # ===================================================================
    # 4. Cone excitation breakdown by wavelength band
    # ===================================================================
    print(f"\n{'='*90}")
    print("Cone Excitation by Wavelength Band (fraction of total)")
    print(f"{'='*90}")

    bands = [
        ('UV-V  380-420', 380, 420),
        ('Violet 420-460', 420, 460),
        ('Blue  460-500', 460, 500),
        ('Green 500-560', 500, 560),
        ('Yel-Or 560-620', 560, 620),
        ('Red   620-680', 620, 680),
        ('DeepR 680-780', 680, 780),
    ]

    key_sources = ['2700K Blackbody', 'Waveform A19']
    for sn in spec_n:
        key_sources.append(sn)

    for cone_idx, cone_name in enumerate(['L cone', 'M cone', 'S cone']):
        print(f"\n  {cone_name}:")
        header = f"    {'Band':<16}"
        for name in key_sources:
            short = name[:16]
            header += f" {short:>16}"
        print(header)
        print("    " + "-" * (16 + 17 * len(key_sources)))

        for band_label, lo, hi in bands:
            row = f"    {band_label:<16}"
            for name in key_sources:
                spd = all_sources[name]
                breakdown, _ = cone_excitation_by_band(wl, spd, bands)
                frac = breakdown[band_label][cone_idx]
                row += f" {frac*100:15.2f}%"
            print(row)

    # Deep red contribution (>650nm, >700nm)
    print(f"\n{'='*90}")
    print("Deep Red Contribution to Cone Excitation")
    print(f"{'='*90}")
    deep_bands = [
        ('>650nm', 650, 780),
        ('>700nm', 700, 780),
    ]
    print(f"\n{'Source':<28} {'L >650':>8} {'L >700':>8} "
          f"{'M >650':>8} {'M >700':>8}")
    print("-" * 70)
    for name in key_sources:
        spd = all_sources[name]
        total_lms = spd_to_lms(wl, spd)
        vals = []
        for _, lo, hi in deep_bands:
            mask = (wl >= lo) & (wl < hi)
            band_spd = np.where(mask, spd, 0)
            band_lms = spd_to_lms(wl, band_spd)
            vals.append(band_lms / total_lms)
        print(f"{name:<28} {vals[0][0]*100:7.2f}% {vals[1][0]*100:7.2f}% "
              f"{vals[0][1]*100:7.2f}% {vals[1][1]*100:7.2f}%")

    # ===================================================================
    # 5. Five-channel receptor analysis (L, M, S, Rod, Melanopic)
    # ===================================================================
    print(f"\n{'='*90}")
    print("FIVE-CHANNEL RECEPTOR ANALYSIS (L, M, S, Rod, Melanopic)")
    print(f"{'='*90}")

    ref_5ch = spd_to_5channel(wl, bb_n)
    ch_names = ['L', 'M', 'S', 'Rod', 'Mel']

    print(f"\n{'Source':<28}", end='')
    for cn in ch_names:
        print(f" {cn:>10}", end='')
    print()
    print("-" * 82)

    source_5ch = {}
    for name, spd in all_sources.items():
        ch = spd_to_5channel(wl, spd)
        source_5ch[name] = ch
        print(f"{name:<28}", end='')
        for v in ch:
            print(f" {v:10.2f}", end='')
        print()

    # Adapted (normalized to blackbody)
    print(f"\n{'Source':<28}", end='')
    for cn in ch_names:
        print(f" {'d'+cn+'%':>8}", end='')
    print(f" {'3ch%':>8} {'5ch%':>8}")
    print("-" * 90)

    for name, ch in source_5ch.items():
        adapted = ch / ref_5ch
        deltas = (adapted - 1) * 100
        rmscc3 = cone_contrast(ch[:3], ref_5ch[:3]) * 100
        rmscc5 = five_channel_contrast(ch, ref_5ch) * 100
        print(f"{name:<28}", end='')
        for d in deltas:
            print(f" {d:+8.2f}", end='')
        print(f" {rmscc3:8.3f} {rmscc5:8.3f}")

    # ===================================================================
    # 5c. S/P ratio and mesopic luminance analysis
    # ===================================================================
    print(f"\n{'='*90}")
    print("MESOPIC LUMINANCE ANALYSIS")
    print(f"{'='*90}")

    # S/P ratios
    print(f"\n{'Source':<28} {'S/P':>6} {'M-DLR':>7}")
    print("-" * 45)
    source_sp = {}
    source_mdlr = {}
    for name, spd in all_sources.items():
        s_p = sp_ratio(wl, spd)
        mdlr = melanopic_edi(wl, spd)
        source_sp[name] = s_p
        source_mdlr[name] = mdlr
        print(f"{name:<28} {s_p:6.3f} {mdlr:7.4f}")

    # Mesopic luminance at various photopic levels
    # Convert typical residential illuminances to luminance
    # Assume diffuse wall at 30% reflectance: L = E * rho / pi
    wall_rho = 0.30
    lux_levels = [10, 30, 50, 100, 200, 300, 500]

    print(f"\nMesopic luminance at residential light levels")
    print(f"(wall luminance at {wall_rho*100:.0f}% reflectance)")
    header = f"{'Source':<28} {'S/P':>5}"
    for lx in lux_levels:
        header += f" {lx:>5}lx"
    print(header)
    print("-" * (34 + 7 * len(lux_levels)))

    bb_sp = source_sp['2700K Blackbody']
    mesopic_data = {}  # name -> list of (lux, L_mes, deficit_pct)
    for name, spd in all_sources.items():
        s_p = source_sp[name]
        row = f"{name:<28} {s_p:5.3f}"
        data = []
        for lx in lux_levels:
            L_p = lx * wall_rho / np.pi
            L_mes, m_coeff = mesopic_luminance(L_p, s_p)
            data.append((lx, L_mes, m_coeff))
            row += f" {L_mes:6.2f}"
        mesopic_data[name] = data
        print(row)

    # Deficit relative to blackbody
    print(f"\nMesopic brightness deficit vs blackbody (%)")
    header = f"{'Source':<28}"
    for lx in lux_levels:
        header += f" {lx:>5}lx"
    print(header)
    print("-" * (28 + 7 * len(lux_levels)))

    bb_data = mesopic_data['2700K Blackbody']
    mesopic_deficits = {}  # name -> list of deficit %
    for name in all_sources:
        src_data = mesopic_data[name]
        row = f"{name:<28}"
        deficits = []
        for i, (lx, L_mes, _) in enumerate(src_data):
            bb_mes = bb_data[i][1]
            deficit = (L_mes - bb_mes) / bb_mes * 100
            deficits.append(deficit)
            row += f" {deficit:+6.1f}"
        mesopic_deficits[name] = deficits
        print(row)

    # Adaptation coefficient m at each level
    print(f"\nCIE adaptation coefficient m (blackbody, S/P={bb_sp:.3f})")
    header = f"{'':28}"
    for lx in lux_levels:
        header += f" {lx:>5}lx"
    print(header)
    row = f"{'m':>28}"
    for _, _, m_coeff in bb_data:
        row += f" {m_coeff:6.3f}"
    print(row)

    # S/P and M-DLR summary: what a lux meter misses
    print(f"\n{'='*90}")
    print("WHAT A LUX METER MISSES: Scotopic & Melanopic at Same Photopic Illuminance")
    print(f"{'='*90}")
    print(f"\nAt 200 photopic lux (typical residential evening):")
    print(f"{'Source':<28} {'Phot':>7} {'Scot':>7} {'Mel':>7} "
          f"{'dScot':>7} {'dMel':>7}")
    print(f"{'':28} {'lux':>7} {'lux':>7} {'M-EDI':>7} {'%':>7} {'%':>7}")
    print("-" * 70)
    bb_sp_val = source_sp['2700K Blackbody']
    bb_mdlr_val = source_mdlr['2700K Blackbody']
    for name in all_sources:
        phot = 200
        scot = phot * source_sp[name]
        mel = phot * source_mdlr[name]
        bb_scot = phot * bb_sp_val
        bb_mel = phot * bb_mdlr_val
        d_scot = (scot - bb_scot) / bb_scot * 100
        d_mel = (mel - bb_mel) / bb_mel * 100
        print(f"{name:<28} {phot:7.0f} {scot:7.1f} {mel:7.1f} "
              f"{d_scot:+7.1f} {d_mel:+7.1f}")

    # ===================================================================
    # 5b. Spectral overlap with cone fundamentals
    # ===================================================================
    # Compute the effective cone sensitivity weighted by each illuminant
    # This shows WHERE in the spectrum each cone gets its signal from
    x_bar = np.interp(wl, CMF_WL, CMF_X, left=0, right=0)
    y_bar = np.interp(wl, CMF_WL, CMF_Y, left=0, right=0)
    z_bar = np.interp(wl, CMF_WL, CMF_Z, left=0, right=0)

    # LMS sensitivities via HPE transform of CMFs
    l_bar = M_HPE[0, 0] * x_bar + M_HPE[0, 1] * y_bar + M_HPE[0, 2] * z_bar
    m_bar = M_HPE[1, 0] * x_bar + M_HPE[1, 1] * y_bar + M_HPE[1, 2] * z_bar
    s_bar = M_HPE[2, 0] * x_bar + M_HPE[2, 1] * y_bar + M_HPE[2, 2] * z_bar

    # ===================================================================
    # 6. Plots
    # ===================================================================

    # --- Figure 1: Spectral comparison ---
    fig, axes = plt.subplots(2, 1, figsize=(12, 8), sharex=True)

    # Normalize for plotting (peak = 1)
    def plot_norm(spd):
        return spd / np.max(spd)

    ax = axes[0]
    ax.plot(wl, plot_norm(bb_n), 'k-', linewidth=2, label='2700K Blackbody')
    ax.plot(wl, plot_norm(wf_n), 'b-', linewidth=2, label='Waveform A19 LED')
    ax.fill_between(wl, 0, plot_norm(bb_n), alpha=0.1, color='orange')
    ax.fill_between(wl, 0, plot_norm(wf_n), alpha=0.1, color='blue')
    ax.set_ylabel('Relative SPD (peak = 1)', fontsize=11)
    ax.set_title('2700K Illuminant Spectra: Blackbody vs Waveform LED',
                 fontsize=13)
    ax.legend(fontsize=10)
    ax.set_xlim(380, 780)
    ax.grid(True, alpha=0.3)

    # Annotate key differences
    ax.annotate('450nm\npump', xy=(450, 0.48), fontsize=8,
                ha='center', color='blue')
    ax.annotate('Deep red\ndeficit', xy=(700, 0.15), fontsize=8,
                ha='center', color='red')
    ax.annotate('470nm\ngap', xy=(473, 0.08), fontsize=8,
                ha='center', color='blue')

    ax = axes[1]
    ax.plot(wl, plot_norm(bb_n), 'k-', linewidth=1.5,
            label='2700K Blackbody', alpha=0.7)
    colors = ['#2196F3', '#4CAF50', '#FF9800', '#F44336']
    for i, (label, spd) in enumerate(spec_n.items()):
        c = colors[i % len(colors)]
        ax.plot(wl, plot_norm(spd), '-', color=c, linewidth=1.5, label=label)
    ax.set_xlabel('Wavelength (nm)', fontsize=11)
    ax.set_ylabel('Relative SPD (peak = 1)', fontsize=11)
    ax.set_title('Optimized Spectra vs Blackbody', fontsize=13)
    ax.legend(fontsize=9, loc='upper right')
    ax.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(os.path.join(RUNDIR, 'fig_lms_spectra.pdf'), dpi=150)
    plt.savefig(os.path.join(RUNDIR, 'fig_lms_spectra.png'), dpi=150)
    print("\nSaved fig_lms_spectra")

    # --- Figure 2: Cone excitation breakdown (stacked bar) ---
    fig, axes = plt.subplots(1, 3, figsize=(16, 6))
    band_labels = [b[0] for b in bands]
    band_colors = ['#4a148c', '#7b1fa2', '#1565c0', '#2e7d32',
                   '#f9a825', '#d84315', '#b71c1c']

    for cone_idx, (ax, cone_name) in enumerate(
            zip(axes, ['L cone', 'M cone', 'S cone'])):
        bottom = np.zeros(len(key_sources))
        for bi, (blabel, lo, hi) in enumerate(bands):
            vals = []
            for name in key_sources:
                spd = all_sources[name]
                bd, _ = cone_excitation_by_band(wl, spd, bands)
                vals.append(bd[blabel][cone_idx] * 100)
            vals = np.array(vals)
            ax.bar(range(len(key_sources)), vals, bottom=bottom,
                   color=band_colors[bi], label=blabel if cone_idx == 0 else '',
                   edgecolor='white', linewidth=0.5)
            bottom += vals

        ax.set_title(cone_name, fontsize=13, fontweight='bold')
        ax.set_xticks(range(len(key_sources)))
        short_names = []
        for n in key_sources:
            if 'Blackbody' in n:
                short_names.append('BB 2700K')
            elif 'Waveform' in n:
                short_names.append('Waveform')
            elif 'CRI 80' in n and 'uncon' in n:
                short_names.append('CRI80\nmax-eff')
            elif 'CRI 95' in n and 'uncon' in n:
                short_names.append('CRI95\nmax-eff')
            elif 'CRI 80' in n and 'Phil' in n:
                short_names.append('CRI80\nPh250')
            elif 'CRI 95' in n and 'Phil' in n:
                short_names.append('CRI95\nPh250')
            else:
                short_names.append(n[:10])
        ax.set_xticklabels(short_names, fontsize=8)
        ax.set_ylabel('Fraction of cone excitation (%)', fontsize=10)
        ax.set_ylim(0, 105)
        ax.grid(True, alpha=0.2, axis='y')

    axes[0].legend(fontsize=8, loc='upper left', bbox_to_anchor=(0, 1))
    fig.suptitle('Cone Excitation by Wavelength Band', fontsize=14,
                 fontweight='bold', y=1.02)
    plt.tight_layout()
    plt.savefig(os.path.join(RUNDIR, 'fig_lms_bands.pdf'), dpi=150,
                bbox_inches='tight')
    plt.savefig(os.path.join(RUNDIR, 'fig_lms_bands.png'), dpi=150,
                bbox_inches='tight')
    print("Saved fig_lms_bands")

    # --- Figure 3: Cone-weighted spectral distribution ---
    # Shows WHERE each cone gets its signal for each illuminant
    fig, axes = plt.subplots(3, 1, figsize=(12, 10), sharex=True)
    cone_colors = ['#d32f2f', '#388e3c', '#1565c0']  # L=red, M=green, S=blue
    cone_bars = [l_bar, m_bar, s_bar]
    cone_names = ['L cone', 'M cone', 'S cone']

    for i, (ax, cbar, cname, ccol) in enumerate(
            zip(axes, cone_bars, cone_names, cone_colors)):
        # Blackbody
        sig_bb = bb_n * cbar
        sig_bb_n = sig_bb / np.max(sig_bb)
        ax.fill_between(wl, 0, sig_bb_n, alpha=0.25, color='orange',
                        label='BB 2700K')
        ax.plot(wl, sig_bb_n, '-', color='darkorange', linewidth=1)

        # Waveform
        sig_wf = wf_n * cbar
        sig_wf_n = sig_wf / np.max(sig_bb)  # normalize to BB peak
        ax.fill_between(wl, 0, sig_wf_n, alpha=0.2, color=ccol,
                        label='Waveform')
        ax.plot(wl, sig_wf_n, '-', color=ccol, linewidth=1.5)

        ax.set_ylabel(f'{cname} signal', fontsize=11)
        ax.legend(fontsize=9)
        ax.grid(True, alpha=0.3)
        ax.set_xlim(380, 780)

        # Mark deep red region
        ax.axvspan(650, 780, alpha=0.05, color='red')
        if i == 0:
            ax.annotate('Deep red (>650nm)\nBB only', xy=(710, 0.3),
                        fontsize=8, color='darkred', ha='center')

    axes[-1].set_xlabel('Wavelength (nm)', fontsize=11)
    axes[0].set_title(
        'Cone-Weighted Spectral Signal: Blackbody vs Waveform LED\n'
        '(each panel shows illuminant SPD × cone sensitivity)',
        fontsize=12)
    plt.tight_layout()
    plt.savefig(os.path.join(RUNDIR, 'fig_lms_cone_signal.pdf'), dpi=150)
    plt.savefig(os.path.join(RUNDIR, 'fig_lms_cone_signal.png'), dpi=150)
    print("Saved fig_lms_cone_signal")

    # --- Figure 4: Five-channel contrast bar chart ---
    fig, ax = plt.subplots(figsize=(12, 5.5))
    names = []
    contrasts = {cn: [] for cn in ch_names}
    for name in key_sources:
        if 'Blackbody' in name:
            continue
        ch = source_5ch[name]
        adapted = ch / ref_5ch
        names.append(name.replace('(unconstrained)', '').strip())
        for i, cn in enumerate(ch_names):
            contrasts[cn].append((adapted[i] - 1) * 100)

    x = np.arange(len(names))
    n_bars = 5
    w = 0.15
    bar_colors = ['#d32f2f', '#388e3c', '#1565c0', '#7b1fa2', '#ff6f00']
    bar_labels = ['L cone', 'M cone', 'S cone', 'Rod (V\')', 'Melanopic']
    for i, (cn, col, lbl) in enumerate(zip(ch_names, bar_colors, bar_labels)):
        offset = (i - n_bars/2 + 0.5) * w
        ax.bar(x + offset, contrasts[cn], w, color=col, label=lbl, alpha=0.8)

    ax.axhline(y=0, color='black', linewidth=0.5)
    ax.set_ylabel('Channel contrast vs blackbody (%)', fontsize=11)
    ax.set_title('Five-Channel Receptor Contrast\n'
                 '(deviation from 2700K blackbody, all 5 receptor types)',
                 fontsize=12)
    ax.set_xticks(x)
    ax.set_xticklabels(names, fontsize=8, rotation=15, ha='right')
    ax.legend(fontsize=9, ncol=5, loc='lower left')
    ax.grid(True, alpha=0.3, axis='y')
    plt.tight_layout()
    plt.savefig(os.path.join(RUNDIR, 'fig_5ch_contrast.pdf'), dpi=150)
    plt.savefig(os.path.join(RUNDIR, 'fig_5ch_contrast.png'), dpi=150)
    print("Saved fig_5ch_contrast")

    # --- Figure 5: What a lux meter misses ---
    fig, axes = plt.subplots(1, 2, figsize=(14, 5.5))

    # Left panel: S/P ratio and M-DLR as grouped bars
    plot_names = []
    sp_vals = []
    mdlr_vals = []
    for name in key_sources:
        sp_vals.append(source_sp[name])
        mdlr_vals.append(source_mdlr[name])
        if 'Blackbody' in name:
            plot_names.append('BB 2700K')
        elif 'Waveform' in name:
            plot_names.append('Waveform')
        elif 'CRI 80' in name and 'uncon' in name:
            plot_names.append('CRI80\nmax-eff')
        elif 'CRI 95' in name and 'uncon' in name:
            plot_names.append('CRI95\nmax-eff')
        elif 'CRI 80' in name and 'Phil' in name:
            plot_names.append('CRI80\nPh250')
        elif 'CRI 95' in name and 'Phil' in name:
            plot_names.append('CRI95\nPh250')
        else:
            plot_names.append(name[:10])

    ax = axes[0]
    x = np.arange(len(plot_names))
    w = 0.35
    bars1 = ax.bar(x - w/2, sp_vals, w, color='#7b1fa2', alpha=0.8,
                   label='S/P ratio (scotopic/photopic)')
    bars2 = ax.bar(x + w/2, mdlr_vals, w, color='#ff6f00', alpha=0.8,
                   label='M-DLR (melanopic/photopic)')
    ax.set_xticks(x)
    ax.set_xticklabels(plot_names, fontsize=8)
    ax.set_ylabel('Ratio', fontsize=11)
    ax.set_title('Scotopic & Melanopic Efficiency\nper Photopic Lumen',
                 fontsize=12)
    ax.legend(fontsize=8, loc='upper right')
    ax.grid(True, alpha=0.3, axis='y')
    # Add value labels
    for bar in bars1:
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.01,
                f'{bar.get_height():.2f}', ha='center', va='bottom', fontsize=7)
    for bar in bars2:
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.01,
                f'{bar.get_height():.2f}', ha='center', va='bottom', fontsize=7)

    # Right panel: absolute scotopic & melanopic lux at 200 phot lux
    ax = axes[1]
    phot_lx = 200
    scot_vals = [phot_lx * sp for sp in sp_vals]
    mel_vals = [phot_lx * m for m in mdlr_vals]
    bars1 = ax.bar(x - w/2, scot_vals, w, color='#7b1fa2', alpha=0.8,
                   label='Scotopic lux')
    bars2 = ax.bar(x + w/2, mel_vals, w, color='#ff6f00', alpha=0.8,
                   label='Melanopic lux (M-EDI)')
    ax.set_xticks(x)
    ax.set_xticklabels(plot_names, fontsize=8)
    ax.set_ylabel('Illuminance (lux)', fontsize=11)
    ax.set_title(f'At {phot_lx} Photopic Lux (Same Meter Reading)\n'
                 'Rod & Melanopic Stimulation Received',
                 fontsize=12)
    ax.legend(fontsize=8, loc='upper right')
    ax.grid(True, alpha=0.3, axis='y')
    # Add value labels
    for bar in bars1:
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 1,
                f'{bar.get_height():.0f}', ha='center', va='bottom', fontsize=7)
    for bar in bars2:
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 1,
                f'{bar.get_height():.0f}', ha='center', va='bottom', fontsize=7)

    fig.suptitle('What a Lux Meter Misses', fontsize=14, fontweight='bold',
                 y=1.02)
    plt.tight_layout()
    plt.savefig(os.path.join(RUNDIR, 'fig_mesopic_deficit.pdf'), dpi=150,
                bbox_inches='tight')
    plt.savefig(os.path.join(RUNDIR, 'fig_mesopic_deficit.png'), dpi=150,
                bbox_inches='tight')
    print("Saved fig_mesopic_deficit")

    # Also save the old 3-channel version for backwards compatibility
    fig, ax = plt.subplots(figsize=(10, 5))
    x = np.arange(len(names))
    w = 0.25
    ax.bar(x - w, contrasts['L'], w, color='#d32f2f', label='L cone', alpha=0.8)
    ax.bar(x,     contrasts['M'], w, color='#388e3c', label='M cone', alpha=0.8)
    ax.bar(x + w, contrasts['S'], w, color='#1565c0', label='S cone', alpha=0.8)
    ax.axhline(y=0, color='black', linewidth=0.5)
    ax.set_ylabel('Cone contrast vs blackbody (%)', fontsize=11)
    ax.set_title('Von Kries Adapted Cone Contrast\n'
                 '(deviation from 2700K blackbody reference)', fontsize=12)
    ax.set_xticks(x)
    ax.set_xticklabels(names, fontsize=8, rotation=15, ha='right')
    ax.legend(fontsize=10)
    ax.grid(True, alpha=0.3, axis='y')
    plt.tight_layout()
    plt.savefig(os.path.join(RUNDIR, 'fig_lms_contrast.pdf'), dpi=150)
    plt.savefig(os.path.join(RUNDIR, 'fig_lms_contrast.png'), dpi=150)
    print("Saved fig_lms_contrast")

    plt.close('all')
    print("\nDone.")


if __name__ == '__main__':
    main()
