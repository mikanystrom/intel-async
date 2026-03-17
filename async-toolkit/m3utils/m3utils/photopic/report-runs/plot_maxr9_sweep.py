#!/usr/bin/env python3
"""
Plot results of the max-R9 sweep: R9 vs efficacy frontier,
individual spectrum plots, and Philips-corrected efficacy.
"""

import os
import sys
import glob
import re
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

RUNDIR = os.path.dirname(os.path.abspath(__file__))

# CIE 1924 photopic luminous efficiency V(lambda), 10nm intervals
# from CieSpectrum.i3
V_LAMBDA_NM = np.arange(380, 780, 10, dtype=float)
V_VALUES = np.array([
    0.000039, 0.000120, 0.000396, 0.001210, 0.004000,
    0.011600, 0.023000, 0.038000, 0.060000, 0.090980,
    0.139020, 0.208020, 0.323000, 0.503000, 0.710000,
    0.862000, 0.954000, 0.994950, 0.995000, 0.952000,
    0.870000, 0.757000, 0.631000, 0.503000, 0.381000,
    0.265000, 0.175000, 0.107000, 0.061000, 0.032000,
    0.017000, 0.008210, 0.004102, 0.002091, 0.001047,
    0.000520, 0.000249, 0.000120, 0.000060, 0.000030,
])
K_M = 683.0  # lm/W

# Philips phosphor-converted LED loss model
PUMP_NM = 450.0  # blue LED pump wavelength
PUMP_QE = 0.90   # average phosphor quantum efficiency


def V_interp(wavelength_nm):
    """Interpolate photopic luminous efficiency at given wavelength(s)."""
    return np.interp(wavelength_nm, V_LAMBDA_NM, V_VALUES,
                     left=0.0, right=0.0)


def philips_cost(wavelength_nm):
    """
    Philips phosphor-converted LED cost function.

    Returns the watts of electrical (pump) power needed per watt of
    optical output at each wavelength.

    - At the pump wavelength (450nm): cost = 1 (direct emission)
    - At longer wavelengths: Stokes loss + quantum efficiency penalty
      cost = lambda / (lambda_pump * QE)
    - At shorter wavelengths (< pump): cost = 1 (assume direct)
    """
    wl = np.asarray(wavelength_nm, dtype=float)
    cost = np.ones_like(wl)
    mask = wl > PUMP_NM
    cost[mask] = wl[mask] / (PUMP_NM * PUMP_QE)
    return cost


def compute_efficacies(wavelength_nm, power):
    """
    Compute both uncorrected LER and Philips-corrected efficacy.

    Returns (ler_uncorrected, ler_philips) in lm/W.
    """
    v = V_interp(wavelength_nm)
    _trapz = np.trapezoid if hasattr(np, 'trapezoid') else np.trapz
    lumens_integral = _trapz(power * v, wavelength_nm)
    power_integral = _trapz(power, wavelength_nm)

    cost = philips_cost(wavelength_nm)
    philips_power_integral = _trapz(power * cost, wavelength_nm)

    ler = K_M * lumens_integral / power_integral if power_integral > 0 else 0
    ler_phil = K_M * lumens_integral / philips_power_integral if philips_power_integral > 0 else 0
    return ler, ler_phil


def load_dat(filename):
    """Load a .dat file: wavelength(m) power pairs."""
    data = np.loadtxt(filename)
    wavelength_nm = data[:, 0] * 1e9
    power = data[:, 1]
    return wavelength_nm, power


def load_res(filename):
    """Parse a .res file to extract key specs."""
    with open(filename) as f:
        line = f.readline().strip()
    nums = re.findall(r'[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?', line)
    if len(nums) >= 14:
        return {
            'cri_ra': float(nums[0]),
            'worst_ri': float(nums[1]),
            'efficacy': float(nums[2]),
            'cct': float(nums[3]),
            'duv': float(nums[4]),
            'r9': float(nums[13]),
        }
    return None


def wavelength_to_rgb(w):
    """Approximate visible spectrum color."""
    if w < 380 or w > 780:
        return (0, 0, 0)
    elif w < 440:
        r, g, b = -(w-440)/(440-380), 0.0, 1.0
    elif w < 490:
        r, g, b = 0.0, (w-440)/(490-440), 1.0
    elif w < 510:
        r, g, b = 0.0, 1.0, -(w-510)/(510-490)
    elif w < 580:
        r, g, b = (w-510)/(580-510), 1.0, 0.0
    elif w < 645:
        r, g, b = 1.0, -(w-645)/(645-580), 0.0
    else:
        r, g, b = 1.0, 0.0, 0.0
    if w < 420:
        f = 0.3 + 0.7*(w-380)/(420-380)
    elif w > 700:
        f = 0.3 + 0.7*(780-w)/(780-700)
    else:
        f = 1.0
    return (r*f, g*f, b*f)


def plot_spectrum(ax, wl, power, label=None, alpha=0.3):
    """Plot a spectrum with rainbow fill."""
    pnorm = power / np.max(power)
    ax.plot(wl, pnorm, 'k-', linewidth=1.0, label=label)
    for i in range(len(wl)-1):
        color = wavelength_to_rgb(wl[i])
        ax.fill_between(wl[i:i+2], pnorm[i:i+2], alpha=alpha, color=color)


def find_sweep_results(cri_min, philips=False):
    """Find all maxR9 result files for a given CRI minimum.

    If philips=True, look for Philips-corrected results (maxR9P prefix).
    """
    tag = 'maxR9P' if philips else 'maxR9'
    pattern = os.path.join(RUNDIR,
                           f'2700_CRI{cri_min}_{tag}_eff*_129.res')
    files = glob.glob(pattern)
    results = []
    for f in files:
        # Extract efficacy threshold from filename
        m = re.search(r'_eff(\d+\.?\d*)_129\.res$', f)
        if not m:
            continue
        eff_threshold = float(m.group(1))
        specs = load_res(f)
        if specs is None:
            continue

        # Find corresponding .dat file
        dat_file = f.replace('2700_CRI', 'w_2700_CRI').replace('.res', '.dat')
        ler, ler_phil = 0, 0
        if os.path.exists(dat_file):
            wl, power = load_dat(dat_file)
            ler, ler_phil = compute_efficacies(wl, power)

        results.append({
            'eff_threshold': eff_threshold,
            'r9': specs['r9'],
            'cri_ra': specs['cri_ra'],
            'efficacy': specs['efficacy'],
            'cct': specs['cct'],
            'worst_ri': specs['worst_ri'],
            'ler_philips': ler_phil,
            'dat_file': dat_file,
            'res_file': f,
        })

    results.sort(key=lambda x: x['eff_threshold'])
    return results


def plot_individual_spectra(results, cri_min, philips=False):
    """Generate individual spectrum plots for each efficacy level."""
    n = len(results)
    if n == 0:
        return

    # Multi-panel figure: up to 4 columns
    ncols = min(4, n)
    nrows = (n + ncols - 1) // ncols
    fig, axes = plt.subplots(nrows, ncols, figsize=(4*ncols, 3.5*nrows),
                             sharex=True, sharey=True)
    if nrows == 1 and ncols == 1:
        axes = np.array([[axes]])
    elif nrows == 1:
        axes = axes[np.newaxis, :]
    elif ncols == 1:
        axes = axes[:, np.newaxis]

    for idx, r in enumerate(results):
        row, col = idx // ncols, idx % ncols
        ax = axes[row, col]

        if os.path.exists(r['dat_file']):
            wl, power = load_dat(r['dat_file'])
            plot_spectrum(ax, wl, power)

        ax.set_title(
            f'eff$\\geq${r["eff_threshold"]:.0f}\n'
            f'R$_9$={r["r9"]:.0f}  CRI={r["cri_ra"]:.0f}  '
            f'{r["efficacy"]:.0f} lm/W',
            fontsize=8)
        ax.set_xlim(380, 770)
        ax.grid(True, alpha=0.3)

    # Hide empty panels
    for idx in range(n, nrows*ncols):
        row, col = idx // ncols, idx % ncols
        axes[row, col].set_visible(False)

    for ax in axes[-1, :]:
        if ax.get_visible():
            ax.set_xlabel('Wavelength (nm)', fontsize=9)
    for ax in axes[:, 0]:
        ax.set_ylabel('Relative Power', fontsize=9)

    philips_label = ' (Philips-corrected)' if philips else ''
    fig.suptitle(f'Optimized Spectra: Max $R_9$ at CRI$\\geq${cri_min}, 2700K{philips_label}',
                 fontsize=13, fontweight='bold')
    plt.tight_layout()

    ptag = '_philips' if philips else ''
    fname = f'fig_maxr9_spectra_cri{cri_min}{ptag}'
    plt.savefig(os.path.join(RUNDIR, fname + '.pdf'), dpi=150)
    plt.savefig(os.path.join(RUNDIR, fname + '.png'), dpi=150)
    print(f"Saved {fname}")


def plot_r9_vs_efficacy_curve(results, cri_min, philips=False):
    """Plot R9 vs efficacy (both uncorrected and Philips-corrected)."""
    if len(results) < 2:
        print(f"Skipping R9-vs-efficacy curve for CRI>={cri_min}: < 2 data points")
        return

    fig, ax1 = plt.subplots(figsize=(10, 7))

    effs = [r['efficacy'] for r in results]
    r9s = [r['r9'] for r in results]
    cris = [r['cri_ra'] for r in results]
    philips = [r['ler_philips'] for r in results]

    # Main curve: R9 vs uncorrected efficacy
    ax1.plot(effs, r9s, 'bo-', markersize=8, linewidth=2,
             label='Uncorrected LER', zorder=3)

    # Philips-corrected curve
    if any(p > 0 for p in philips):
        ax1.plot(philips, r9s, 'rs--', markersize=7, linewidth=1.5,
                 label='Philips-corrected', zorder=3)

    # Annotate CRI values
    for i, r in enumerate(results):
        ax1.annotate(f'CRI={r["cri_ra"]:.0f}',
                     (r['efficacy'], r['r9']),
                     textcoords="offset points", xytext=(8, -5),
                     fontsize=7, color='blue')

    # Reference lines
    ax1.axhline(y=0, color='gray', linestyle='-', alpha=0.3)
    ax1.axhline(y=50, color='orange', linestyle='--', alpha=0.4,
                label='California JA8: $R_9 \\geq 50$')
    ax1.axhline(y=90, color='green', linestyle='--', alpha=0.4,
                label='Excellent red rendering')

    ax1.axhspan(-100, 0, alpha=0.04, color='red')

    ax1.set_xlabel('Luminous Efficacy of Radiation (lm/W)', fontsize=12)
    ax1.set_ylabel('Best Achievable $R_9$', fontsize=12)
    ax1.set_title(
        f'Maximum $R_9$ vs Required Efficacy at CRI$\\geq${cri_min}, 2700K\n'
        f'(Blue: theoretical LER; Red: Philips phosphor-corrected)',
        fontsize=12)
    ax1.legend(fontsize=9, loc='upper right')
    ax1.grid(True, alpha=0.3)

    plt.tight_layout()

    ptag = '_philips' if philips else ''
    fname = f'fig_r9_frontier_cri{cri_min}{ptag}'
    plt.savefig(os.path.join(RUNDIR, fname + '.pdf'), dpi=150)
    plt.savefig(os.path.join(RUNDIR, fname + '.png'), dpi=150)
    print(f"Saved {fname}")


def print_summary_table(results, cri_min, philips=False):
    """Print a summary table to stdout and a .csv file."""
    plabel = ' (Philips-corrected)' if philips else ''
    print(f"\n{'='*80}")
    print(f"Max-R9 Sweep Results: CRI >= {cri_min}, 2700K{plabel}")
    print(f"{'='*80}")
    print(f"{'Eff Floor':>10} {'LER':>8} {'Philips':>8} {'CRI(Ra)':>8} "
          f"{'R9':>8} {'Worst Ri':>9} {'CCT':>7}")
    print(f"{'(lm/W)':>10} {'(lm/W)':>8} {'(lm/W)':>8} {'':>8} "
          f"{'':>8} {'':>9} {'(K)':>7}")
    print('-'*80)

    ptag = '_philips' if philips else ''
    csv_path = os.path.join(RUNDIR, f'maxr9_sweep_cri{cri_min}{ptag}.csv')
    with open(csv_path, 'w') as csvf:
        csvf.write('eff_floor,ler,ler_philips,cri_ra,r9,worst_ri,cct\n')
        for r in results:
            print(f'{r["eff_threshold"]:10.0f} {r["efficacy"]:8.1f} '
                  f'{r["ler_philips"]:8.1f} {r["cri_ra"]:8.1f} '
                  f'{r["r9"]:8.1f} {r["worst_ri"]:9.1f} {r["cct"]:7.0f}')
            csvf.write(f'{r["eff_threshold"]:.0f},{r["efficacy"]:.1f},'
                       f'{r["ler_philips"]:.1f},{r["cri_ra"]:.1f},'
                       f'{r["r9"]:.1f},{r["worst_ri"]:.1f},{r["cct"]:.0f}\n')

    print(f"\nCSV saved to {csv_path}")


if __name__ == '__main__':
    philips = '--philips' in sys.argv
    args = [a for a in sys.argv[1:] if a != '--philips']
    cri_min = int(args[0]) if args else 80

    mode = 'Philips-corrected' if philips else 'uncorrected'
    print(f"Processing max-R9 sweep results for CRI >= {cri_min} ({mode})")
    results = find_sweep_results(cri_min, philips=philips)
    print(f"Found {len(results)} result files")

    if not results:
        print("No results found. Run the sweep first:")
        print(f"  ./run-maxr9-sweep-parallel.sh {cri_min}")
        sys.exit(1)

    print_summary_table(results, cri_min, philips=philips)
    plot_r9_vs_efficacy_curve(results, cri_min, philips=philips)
    plot_individual_spectra(results, cri_min, philips=philips)

    print("\nDone.")
