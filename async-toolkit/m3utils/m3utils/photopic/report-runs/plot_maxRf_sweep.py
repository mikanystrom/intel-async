#!/usr/bin/env python3
"""
Plot results of the max-Rf sweep: TM-30 Rf vs system efficacy frontier,
individual spectrum plots, and CSV summary.

The x-axis shows system (wall-plug) efficacy at three technology levels,
computed from Philips-corrected LER via production loss chain multipliers.

Technology scenarios (from report Table 5):
  - Best production: x0.514 (current top-bin parts)
  - Best lab:        x0.670 (demonstrated lab results)
  - DOE limit:       x0.813 (theoretical ceiling)

Regulatory thresholds (from report Table 3):
  - EU 2019/2020: 98 lm/W system
  - US DOE 2028:  125 lm/W system
"""

import os
import sys
import glob
import re
import ast
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

RUNDIR = os.path.dirname(os.path.abspath(__file__))

# Production loss chain multipliers (Philips LER -> system efficacy)
TECH_PROD = 0.514   # best production
TECH_LAB  = 0.670   # best lab
TECH_DOE  = 0.813   # DOE theoretical limit

TECH_LEVELS = [
    (TECH_PROD, 'Best production ($\\times$0.514)', 'o', '-',  'C0'),
    (TECH_LAB,  'Best lab ($\\times$0.670)',         's', '--', 'C1'),
    (TECH_DOE,  'DOE limit ($\\times$0.813)',        '^', ':',  'C2'),
]

# Regulatory system efficacy thresholds
REG_EU  = 98.0    # EU 2019/2020
REG_DOE = 125.0   # US DOE 2028

# CIE 1924 photopic luminous efficiency V(lambda), 10nm intervals
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
PUMP_NM = 450.0
PUMP_QE = 0.90


def V_interp(wavelength_nm):
    """Interpolate photopic luminous efficiency at given wavelength(s)."""
    return np.interp(wavelength_nm, V_LAMBDA_NM, V_VALUES,
                     left=0.0, right=0.0)


def philips_cost(wavelength_nm):
    """Philips phosphor-converted LED cost per watt at each wavelength."""
    wl = np.asarray(wavelength_nm, dtype=float)
    cost = np.ones_like(wl)
    mask = wl > PUMP_NM
    cost[mask] = wl[mask] / (PUMP_NM * PUMP_QE)
    return cost


def compute_efficacies(wavelength_nm, power):
    """Compute both uncorrected LER and Philips-corrected efficacy."""
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


def parse_scheme_list(s):
    """Parse a Scheme S-expression list into a Python nested structure.

    Handles nested lists, vectors (#(...)), and numeric atoms.
    """
    # Convert Scheme syntax to Python:
    #   #( -> [   (vector open)
    #   (  -> [   (list open)
    #   )  -> ]   (close)
    s = s.strip()
    s = s.replace('#(', '[').replace('(', '[').replace(')', ']')
    try:
        return ast.literal_eval(s)
    except (ValueError, SyntaxError):
        return None


def load_res(filename):
    """Parse a .res file to extract key specs including TM-30 data.

    The specs S-expression (from grid-calc-specs with -tm30) has structure:
      (cri-ra worst-ri efficacy (cct Duv) (ri1..ri14)
       cri-14 worst-14 sel-avg sel-worst sel-idx
       (Rf Rg #(Rcs...) (ref-temp-res)))
    """
    with open(filename) as f:
        line = f.readline().strip()

    parsed = parse_scheme_list(line)
    if parsed is None or len(parsed) < 10:
        # Fallback: regex-based extraction for non-TM30 files
        nums = re.findall(r'[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?', line)
        if len(nums) >= 14:
            return {
                'cri_ra': float(nums[0]),
                'worst_ri': float(nums[1]),
                'efficacy': float(nums[2]),
                'cct': float(nums[3]),
                'duv': float(nums[4]),
                'r9': float(nums[13]),
                'Rf': None,
                'Rg': None,
            }
        return None

    result = {
        'cri_ra': float(parsed[0]),
        'worst_ri': float(parsed[1]),
        'efficacy': float(parsed[2]),
        'cct': float(parsed[3][0]) if isinstance(parsed[3], list) else 0,
        'duv': float(parsed[3][1]) if isinstance(parsed[3], list) else 0,
        'Rf': None,
        'Rg': None,
        'r9': None,
    }

    # Extract R9 from ri-list (index 4, element 8 = R9)
    if isinstance(parsed[4], list) and len(parsed[4]) >= 9:
        result['r9'] = float(parsed[4][8])

    # Extract TM-30 data if present (index 10)
    if len(parsed) > 10 and isinstance(parsed[10], list) and len(parsed[10]) >= 2:
        result['Rf'] = float(parsed[10][0])
        result['Rg'] = float(parsed[10][1])

    return result


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
    """Find all maxRf result files for a given CRI minimum."""
    tag = 'maxRfP' if philips else 'maxRf'
    pattern = os.path.join(RUNDIR,
                           f'2700_CRI{cri_min}_{tag}_eff*_129.res')
    files = glob.glob(pattern)
    results = []
    for f in files:
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
            'Rf': specs['Rf'],
            'Rg': specs['Rg'],
            'r9': specs['r9'],
            'cri_ra': specs['cri_ra'],
            'efficacy': specs['efficacy'],  # uncorrected LER
            'cct': specs['cct'],
            'worst_ri': specs['worst_ri'],
            'ler_philips': ler_phil,
            'dat_file': dat_file,
            'res_file': f,
        })

    results.sort(key=lambda x: x['eff_threshold'])
    return results


def plot_Rf_vs_system_efficacy(results, cri_min, philips=False):
    """Plot Rf vs system efficacy at three technology levels."""
    if len(results) < 2:
        print(f"Skipping Rf-vs-efficacy curve for CRI>={cri_min}: < 2 data points")
        return

    phil_lers = np.array([r['ler_philips'] for r in results])
    Rfs = np.array([r['Rf'] if r['Rf'] is not None else 0 for r in results])
    Rgs = np.array([r['Rg'] if r['Rg'] is not None else 0 for r in results])

    if all(rf == 0 for rf in Rfs):
        print(f"No TM-30 data found in results for CRI>={cri_min}")
        return

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(11, 12),
                                    height_ratios=[3, 1], sharex=True)

    # --- Main plot: Rf vs system efficacy ---
    for mult, label, marker, ls, color in TECH_LEVELS:
        sys_effs = phil_lers * mult
        ax1.plot(sys_effs, Rfs, marker=marker, linestyle=ls,
                 color=color, markersize=7, linewidth=1.8,
                 label=label, zorder=3)

    # Regulatory threshold lines
    ax1.axvline(x=REG_EU, color='red', linestyle='--', alpha=0.6, linewidth=1.5,
                label=f'EU 2019/2020: {REG_EU:.0f} lm/W')
    ax1.axvline(x=REG_DOE, color='darkred', linestyle='-.', alpha=0.6, linewidth=1.5,
                label=f'US DOE 2028: {REG_DOE:.0f} lm/W')

    ax1.set_ylabel('Best Achievable TM-30 $R_f$', fontsize=12)
    ax1.set_title(
        f'Maximum TM-30 $R_f$ vs System Efficacy at CRI$\\geq${cri_min}, 2700K\n'
        f'(Philips LER $\\times$ production loss chain)',
        fontsize=12)
    ax1.legend(fontsize=9, loc='lower left')
    ax1.grid(True, alpha=0.3)
    ax1.set_ylim(bottom=max(0, min(Rfs) - 5))

    # --- Sub-plot: Rg vs system efficacy ---
    for mult, label, marker, ls, color in TECH_LEVELS:
        sys_effs = phil_lers * mult
        ax2.plot(sys_effs, Rgs, marker=marker, linestyle=ls,
                 color=color, markersize=5, linewidth=1.2, zorder=3)

    ax2.axvline(x=REG_EU, color='red', linestyle='--', alpha=0.6, linewidth=1.5)
    ax2.axvline(x=REG_DOE, color='darkred', linestyle='-.', alpha=0.6, linewidth=1.5)
    ax2.axhline(y=100, color='gray', linestyle='-', alpha=0.3)

    ax2.set_xlabel('System (Wall-Plug) Efficacy (lm/W)', fontsize=12)
    ax2.set_ylabel('$R_g$ (Gamut)', fontsize=11)
    ax2.grid(True, alpha=0.3)

    plt.tight_layout()

    ptag = '_philips' if philips else ''
    fname = f'fig_maxRf_frontier_cri{cri_min}{ptag}'
    plt.savefig(os.path.join(RUNDIR, fname + '.pdf'), dpi=150)
    plt.savefig(os.path.join(RUNDIR, fname + '.png'), dpi=150)
    print(f"Saved {fname}")


def plot_individual_spectra(results, cri_min, philips=False):
    """Generate individual spectrum plots for each efficacy level."""
    n = len(results)
    if n == 0:
        return

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

        Rf_str = f'Rf={r["Rf"]:.0f}' if r['Rf'] is not None else 'Rf=?'
        Rg_str = f'Rg={r["Rg"]:.0f}' if r['Rg'] is not None else ''
        sys_eff = r['ler_philips'] * TECH_PROD
        ax.set_title(
            f'Phil$\\geq${r["eff_threshold"]:.0f} (sys={sys_eff:.0f})\n'
            f'{Rf_str}  {Rg_str}  CRI={r["cri_ra"]:.0f}  '
            f'{r["efficacy"]:.0f} lm/W',
            fontsize=8)
        ax.set_xlim(380, 770)
        ax.grid(True, alpha=0.3)

    for idx in range(n, nrows*ncols):
        row, col = idx // ncols, idx % ncols
        axes[row, col].set_visible(False)

    for ax in axes[-1, :]:
        if ax.get_visible():
            ax.set_xlabel('Wavelength (nm)', fontsize=9)
    for ax in axes[:, 0]:
        ax.set_ylabel('Relative Power', fontsize=9)

    philips_label = ' (Philips-corrected)' if philips else ''
    fig.suptitle(f'Optimized Spectra: Max TM-30 $R_f$ at CRI$\\geq${cri_min}, 2700K{philips_label}',
                 fontsize=13, fontweight='bold')
    plt.tight_layout()

    ptag = '_philips' if philips else ''
    fname = f'fig_maxRf_spectra_cri{cri_min}{ptag}'
    plt.savefig(os.path.join(RUNDIR, fname + '.pdf'), dpi=150)
    plt.savefig(os.path.join(RUNDIR, fname + '.png'), dpi=150)
    print(f"Saved {fname}")


def print_summary_table(results, cri_min, philips=False):
    """Print a summary table to stdout and a .csv file."""
    plabel = ' (Philips-corrected)' if philips else ''
    print(f"\n{'='*110}")
    print(f"Max-Rf Sweep Results: CRI >= {cri_min}, 2700K{plabel}")
    print(f"{'='*110}")
    print(f"{'Eff Floor':>10} {'LER':>8} {'Phil':>8} "
          f"{'Sys Prod':>9} {'Sys Lab':>8} {'Sys DOE':>8} "
          f"{'CRI(Ra)':>8} {'Rf':>6} {'Rg':>6} {'R9':>7} {'Worst Ri':>9} {'CCT':>7}")
    print(f"{'(lm/W)':>10} {'(lm/W)':>8} {'(lm/W)':>8} "
          f"{'(lm/W)':>9} {'(lm/W)':>8} {'(lm/W)':>8} "
          f"{'':>8} {'':>6} {'':>6} {'':>7} {'':>9} {'(K)':>7}")
    print('-'*110)

    ptag = '_philips' if philips else ''
    csv_path = os.path.join(RUNDIR, f'maxRf_sweep_cri{cri_min}{ptag}.csv')
    with open(csv_path, 'w') as csvf:
        csvf.write('eff_floor,ler,ler_philips,sys_prod,sys_lab,sys_doe,'
                   'cri_ra,Rf,Rg,r9,worst_ri,cct\n')
        for r in results:
            sys_prod = r['ler_philips'] * TECH_PROD
            sys_lab  = r['ler_philips'] * TECH_LAB
            sys_doe  = r['ler_philips'] * TECH_DOE
            Rf_s = f'{r["Rf"]:.1f}' if r['Rf'] is not None else '—'
            Rg_s = f'{r["Rg"]:.1f}' if r['Rg'] is not None else '—'
            r9_s = f'{r["r9"]:.1f}' if r['r9'] is not None else '—'
            print(f'{r["eff_threshold"]:10.0f} {r["efficacy"]:8.1f} '
                  f'{r["ler_philips"]:8.1f} '
                  f'{sys_prod:9.1f} {sys_lab:8.1f} {sys_doe:8.1f} '
                  f'{r["cri_ra"]:8.1f} {Rf_s:>6} {Rg_s:>6} {r9_s:>7} '
                  f'{r["worst_ri"]:9.1f} {r["cct"]:7.0f}')
            csvf.write(
                f'{r["eff_threshold"]:.0f},{r["efficacy"]:.1f},'
                f'{r["ler_philips"]:.1f},{sys_prod:.1f},{sys_lab:.1f},{sys_doe:.1f},'
                f'{r["cri_ra"]:.1f},'
                f'{r["Rf"] if r["Rf"] is not None else ""},'
                f'{r["Rg"] if r["Rg"] is not None else ""},'
                f'{r["r9"] if r["r9"] is not None else ""},'
                f'{r["worst_ri"]:.1f},{r["cct"]:.0f}\n')

    print(f"\nCSV saved to {csv_path}")


if __name__ == '__main__':
    philips = '--philips' in sys.argv
    args = [a for a in sys.argv[1:] if a != '--philips']
    cri_min = int(args[0]) if args else 80

    mode = 'Philips-corrected' if philips else 'uncorrected'
    print(f"Processing max-Rf sweep results for CRI >= {cri_min} ({mode})")
    results = find_sweep_results(cri_min, philips=philips)
    print(f"Found {len(results)} result files")

    if not results:
        print("No results found. Run the sweep first:")
        if philips:
            print(f"  ./run-maxRf-sweep-parallel.sh {cri_min}")
        else:
            print(f"  ./run-maxRf-sweep.sh")
        sys.exit(1)

    print_summary_table(results, cri_min, philips=philips)
    plot_Rf_vs_system_efficacy(results, cri_min, philips=philips)
    plot_individual_spectra(results, cri_min, philips=philips)

    print("\nDone.")
