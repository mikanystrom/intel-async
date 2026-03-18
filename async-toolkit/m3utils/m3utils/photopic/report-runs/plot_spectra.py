#!/usr/bin/env python3
"""Plot photopic optimization results."""

import os
import sys
import glob
import matplotlib
matplotlib.use('Agg')  # non-interactive backend
import matplotlib.pyplot as plt
import numpy as np

RUNDIR = os.path.dirname(os.path.abspath(__file__))

def load_dat(filename):
    """Load a .dat file: wavelength(m) power pairs."""
    data = np.loadtxt(filename)
    wavelength_nm = data[:, 0] * 1e9  # convert m -> nm
    power = data[:, 1]
    return wavelength_nm, power

def load_res(filename):
    """Parse a .res file to extract key specs."""
    with open(filename) as f:
        line = f.readline().strip()
    # Parse the S-expression minimally
    # Format: (cri_ra worst_ri efficacy (cct Duv) (R1..R14) ...)
    # Indices: 0       1        2        3   4     5..18
    # R9 is at index 13 (5 + 8, since R1=5, R2=6, ..., R9=13)
    import re
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

def normalize_spectrum(wl, power):
    """Normalize power to max=1 for comparison."""
    return power / np.max(power)

def wavelength_to_rgb(wavelength_nm):
    """Approximate visible spectrum color for a given wavelength."""
    w = wavelength_nm
    if w < 380 or w > 780:
        return (0, 0, 0)
    elif w < 440:
        r = -(w - 440) / (440 - 380)
        g = 0.0
        b = 1.0
    elif w < 490:
        r = 0.0
        g = (w - 440) / (490 - 440)
        b = 1.0
    elif w < 510:
        r = 0.0
        g = 1.0
        b = -(w - 510) / (510 - 490)
    elif w < 580:
        r = (w - 510) / (580 - 510)
        g = 1.0
        b = 0.0
    elif w < 645:
        r = 1.0
        g = -(w - 645) / (645 - 580)
        b = 0.0
    else:
        r = 1.0
        g = 0.0
        b = 0.0

    # Intensity falloff at edges
    if w < 420:
        factor = 0.3 + 0.7 * (w - 380) / (420 - 380)
    elif w > 700:
        factor = 0.3 + 0.7 * (780 - w) / (780 - 700)
    else:
        factor = 1.0

    return (r * factor, g * factor, b * factor)


def plot_spectrum_with_rainbow(ax, wl, power, label=None, alpha=0.3):
    """Plot a spectrum with rainbow-colored fill."""
    ax.plot(wl, power, 'k-', linewidth=1.5, label=label)
    # Fill with approximate spectral colors
    for i in range(len(wl) - 1):
        color = wavelength_to_rgb(wl[i])
        ax.fill_between(wl[i:i+2], power[i:i+2], alpha=alpha, color=color)


def plot1_blackbody_vs_optimized():
    """Figure 1: Blackbody baseline vs CRI>=60 optimized spectrum."""
    base_file = os.path.join(RUNDIR, 'base_2700.dat')
    opt_file = os.path.join(RUNDIR, 'w_2700_CRI60_R9=-100_17.dat')
    res_file = os.path.join(RUNDIR, '2700_CRI60_R9=-100_17.res')

    if not os.path.exists(opt_file):
        print("Skipping plot1: missing data")
        return

    wl_base, pow_base = load_dat(base_file)
    wl_opt, pow_opt = load_dat(opt_file)
    specs = load_res(res_file)

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 8), sharex=True)

    # Normalize both to same scale
    pow_base_norm = normalize_spectrum(wl_base, pow_base)
    pow_opt_norm = normalize_spectrum(wl_opt, pow_opt)

    plot_spectrum_with_rainbow(ax1, wl_base, pow_base_norm, '2700K Blackbody')
    ax1.set_ylabel('Relative Power')
    ax1.set_title('2700K Blackbody Reference (CRI=100, ~88 lm/W visible)')
    ax1.legend()
    ax1.set_xlim(380, 770)
    ax1.grid(True, alpha=0.3)

    plot_spectrum_with_rainbow(ax2, wl_opt, pow_opt_norm,
                               f'Optimized (CRI$\\geq$60)')
    ax2.set_xlabel('Wavelength (nm)')
    ax2.set_ylabel('Relative Power')
    if specs:
        ax2.set_title(f'Max-Efficacy Spectrum: CRI={specs["cri_ra"]:.0f}, '
                      f'{specs["efficacy"]:.0f} lm/W, CCT={specs["cct"]:.0f}K')
    ax2.legend()
    ax2.set_xlim(380, 770)
    ax2.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(os.path.join(RUNDIR, 'fig1_blackbody_vs_optimized.pdf'), dpi=150)
    plt.savefig(os.path.join(RUNDIR, 'fig1_blackbody_vs_optimized.png'), dpi=150)
    print("Saved fig1_blackbody_vs_optimized")


def plot2_cri_comparison():
    """Figure 2: Spectra at different CRI constraints, all at 2700K."""
    cri_list = ['60', '70', '80', '82', '85', '90', '95', '98']
    ncols = 4
    nrows = 2
    fig, axes = plt.subplots(nrows, ncols, figsize=(16, 8), sharex=True, sharey=True)

    # Find available files for each CRI
    plotted = 0
    for idx, cri_str in enumerate(cri_list):
        row, col = idx // ncols, idx % ncols
        ax = axes[row, col]

        # Find the highest-dimension .dat file for this CRI
        pattern = os.path.join(RUNDIR, f'w_2700_CRI{cri_str}_R9=-100_*.dat')
        files = sorted(glob.glob(pattern),
                       key=lambda f: int(f.split('_')[-1].replace('.dat', '')))
        if not files:
            ax.text(0.5, 0.5, f'CRI$\\geq${cri_str}\n(no data yet)',
                   transform=ax.transAxes, ha='center', va='center', fontsize=14)
            ax.set_xlim(380, 770)
            continue

        # Use highest dimension file
        dat_file = files[-1]
        dims = dat_file.split('_')[-1].replace('.dat', '')
        res_file = dat_file.replace(f'w_', '').replace('.dat', '.res')

        wl, power = load_dat(dat_file)
        power_norm = normalize_spectrum(wl, power)
        specs = load_res(res_file) if os.path.exists(res_file) else None

        plot_spectrum_with_rainbow(ax, wl, power_norm)

        title = f'CRI $\\geq$ {cri_str}'
        if specs:
            title += f'\nCRI={specs["cri_ra"]:.0f}, {specs["efficacy"]:.0f} lm/W, $R_9$={specs["r9"]:.0f}'
        ax.set_title(title, fontsize=10)
        ax.set_xlim(380, 770)
        ax.grid(True, alpha=0.3)
        plotted += 1

    for ax in axes[-1,:]:
        ax.set_xlabel('Wavelength (nm)')
    for ax in axes[:,0]:
        ax.set_ylabel('Relative Power')

    fig.suptitle('Optimal Spectra at 2700K with Increasing CRI Constraints',
                 fontsize=14, fontweight='bold')
    plt.tight_layout()
    plt.savefig(os.path.join(RUNDIR, 'fig2_cri_comparison.pdf'), dpi=150)
    plt.savefig(os.path.join(RUNDIR, 'fig2_cri_comparison.png'), dpi=150)
    print(f"Saved fig2_cri_comparison ({plotted} panels with data)")


def plot3_convergence():
    """Figure 3: How the spectrum evolves with increasing resolution."""
    # Find all available dimension levels
    all_dims = [2, 3, 5, 9, 17, 33, 65, 129, 257, 513]
    dims_list = [d for d in all_dims
                 if os.path.exists(os.path.join(RUNDIR,
                     f'w_2700_CRI60_R9=-100_{d}.dat'))]
    if not dims_list:
        print("Skipping plot3: no CRI60 data")
        return

    n = len(dims_list)
    ncols = min(5, n)
    nrows = (n + ncols - 1) // ncols
    fig, axes = plt.subplots(nrows, ncols, figsize=(3.5*ncols, 3.5*nrows),
                             sharex=True, sharey=True)
    if nrows == 1 and ncols == 1:
        axes = np.array([[axes]])
    elif nrows == 1:
        axes = axes[np.newaxis, :]
    elif ncols == 1:
        axes = axes[:, np.newaxis]

    plotted = 0
    for i, dims in enumerate(dims_list):
        row, col = i // ncols, i % ncols
        ax = axes[row, col]
        dat_file = os.path.join(RUNDIR, f'w_2700_CRI60_R9=-100_{dims}.dat')
        res_file = os.path.join(RUNDIR, f'2700_CRI60_R9=-100_{dims}.res')

        wl, power = load_dat(dat_file)
        power_norm = normalize_spectrum(wl, power)

        plot_spectrum_with_rainbow(ax, wl, power_norm)

        specs = load_res(res_file) if os.path.exists(res_file) else None
        title = f'{dims} parameters'
        if specs:
            title += f'\n{specs["efficacy"]:.0f} lm/W, CRI={specs["cri_ra"]:.0f}'
        ax.set_title(title, fontsize=10)
        ax.set_xlim(380, 770)
        ax.grid(True, alpha=0.3)
        plotted += 1

    # Hide empty panels
    for idx in range(n, nrows*ncols):
        row, col = idx // ncols, idx % ncols
        axes[row, col].set_visible(False)

    for ax in axes[-1,:]:
        if ax.get_visible():
            ax.set_xlabel('Wavelength (nm)')
    for ax in axes[:,0]:
        ax.set_ylabel('Relative Power')

    fig.suptitle('Spectrum Evolution as Optimizer Resolution Increases (CRI$\\geq$60, 2700K)',
                 fontsize=13, fontweight='bold')
    plt.tight_layout()
    plt.savefig(os.path.join(RUNDIR, 'fig3_convergence.pdf'), dpi=150)
    plt.savefig(os.path.join(RUNDIR, 'fig3_convergence.png'), dpi=150)
    print(f"Saved fig3_convergence ({plotted} panels)")


def plot4_overlay():
    """Figure 4: Overlay all CRI spectra on one plot."""
    fig, ax = plt.subplots(figsize=(10, 6))

    # Plot blackbody baseline
    base_file = os.path.join(RUNDIR, 'base_2700.dat')
    if os.path.exists(base_file):
        wl, power = load_dat(base_file)
        ax.plot(wl, normalize_spectrum(wl, power),
                'k--', linewidth=2, alpha=0.5, label='2700K Blackbody')

    colors = {'60': 'red', '82': 'blue', '90': 'green',
              '95': 'purple', '98': 'orange'}

    for cri_str, color in colors.items():
        pattern = os.path.join(RUNDIR, f'w_2700_CRI{cri_str}_R9=-100_*.dat')
        files = sorted(glob.glob(pattern),
                       key=lambda f: int(f.split('_')[-1].replace('.dat', '')))
        if not files:
            continue

        dat_file = files[-1]
        res_file = dat_file.replace('w_', '').replace('.dat', '.res')

        wl, power = load_dat(dat_file)
        specs = load_res(res_file) if os.path.exists(res_file) else None

        label = f'CRI$\\geq${cri_str}'
        if specs:
            label += f' ({specs["efficacy"]:.0f} lm/W)'

        ax.plot(wl, normalize_spectrum(wl, power),
                color=color, linewidth=1.5, label=label)

    ax.set_xlabel('Wavelength (nm)', fontsize=12)
    ax.set_ylabel('Relative Spectral Power', fontsize=12)
    ax.set_title('Effect of CRI Constraint on Optimal Spectrum Shape (2700K)',
                fontsize=13, fontweight='bold')
    ax.set_xlim(380, 770)
    ax.legend(fontsize=10)
    ax.grid(True, alpha=0.3)

    # Add wavelength region annotations
    ax.axvspan(440, 460, alpha=0.05, color='blue')
    ax.axvspan(530, 550, alpha=0.05, color='green')
    ax.axvspan(600, 620, alpha=0.05, color='red')

    plt.tight_layout()
    plt.savefig(os.path.join(RUNDIR, 'fig4_overlay.pdf'), dpi=150)
    plt.savefig(os.path.join(RUNDIR, 'fig4_overlay.png'), dpi=150)
    print("Saved fig4_overlay")


def plot5_efficacy_vs_cri():
    """Figure 5: Efficacy vs CRI trade-off curve."""
    fig, ax = plt.subplots(figsize=(8, 6))

    cri_vals = []
    eff_vals = []
    r9_vals = []

    for cri_str in ['60', '70', '80', '82', '85', '90', '92', '95', '98']:
        pattern = os.path.join(RUNDIR, f'2700_CRI{cri_str}_R9=-100_*.res')
        files = sorted(glob.glob(pattern),
                       key=lambda f: int(f.split('_')[-1].replace('.res', '')))
        if not files:
            continue

        specs = load_res(files[-1])
        if specs:
            cri_vals.append(specs['cri_ra'])
            eff_vals.append(specs['efficacy'])

    if len(cri_vals) < 2:
        print("Skipping plot5: not enough data points")
        return

    ax.plot(cri_vals, eff_vals, 'bo-', markersize=8, linewidth=2)

    for cri, eff in zip(cri_vals, eff_vals):
        ax.annotate(f'{eff:.0f}', (cri, eff),
                   textcoords="offset points", xytext=(5, 10),
                   fontsize=9)

    # Add horizontal lines for regulatory thresholds
    ax.axhline(y=683, color='gray', linestyle=':', alpha=0.5,
               label='Theoretical max (683 lm/W at 555nm)')
    ax.axvline(x=80, color='red', linestyle='--', alpha=0.5,
               label='Energy Star CRI $\\geq$ 80')
    ax.axvline(x=90, color='orange', linestyle='--', alpha=0.5,
               label='California Title 24 CRI $\\geq$ 90')

    ax.set_xlabel('CRI (Ra)', fontsize=12)
    ax.set_ylabel('Maximum Luminous Efficacy (lm/W)', fontsize=12)
    ax.set_title('Efficacy-CRI Trade-off at 2700K\n'
                '(Maximum achievable efficacy for a given CRI floor)',
                fontsize=13)
    ax.legend(fontsize=9)
    ax.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(os.path.join(RUNDIR, 'fig5_tradeoff.pdf'), dpi=150)
    plt.savefig(os.path.join(RUNDIR, 'fig5_tradeoff.png'), dpi=150)
    print("Saved fig5_tradeoff")


def plot6_r9_vs_efficacy():
    """Figure 6: R9 (saturated red rendering) vs maximum efficacy."""
    fig, ax = plt.subplots(figsize=(9, 6))

    eff_vals = []
    r9_vals = []
    cri_labels = []

    for cri_str in ['60', '70', '80', '82', '85', '90', '95', '98']:
        pattern = os.path.join(RUNDIR, f'2700_CRI{cri_str}_R9=-100_*.res')
        files = sorted(glob.glob(pattern),
                       key=lambda f: int(f.split('_')[-1].replace('.res', '')))
        if not files:
            continue

        specs = load_res(files[-1])
        if specs and 'r9' in specs:
            eff_vals.append(specs['efficacy'])
            r9_vals.append(specs['r9'])
            cri_labels.append(cri_str)

    if len(eff_vals) < 2:
        print("Skipping plot6: not enough data points")
        return

    ax.plot(eff_vals, r9_vals, 'ro-', markersize=8, linewidth=2)

    for eff, r9, label in zip(eff_vals, r9_vals, cri_labels):
        ax.annotate(f'CRI$\\geq${label}', (eff, r9),
                   textcoords="offset points", xytext=(-10, 12),
                   fontsize=8, ha='center')

    # EU effective minimum efficacy for 800 lm lamp: ~98 lm/W
    # But our numbers are radiation-only LER, not system efficacy
    # Mark some reference efficacies
    ax.axhline(y=0, color='gray', linestyle='-', alpha=0.3)
    ax.axhline(y=50, color='orange', linestyle='--', alpha=0.5,
               label='California JA8 min $R_9$ = 50')
    ax.axhline(y=80, color='green', linestyle='--', alpha=0.5,
               label='Good red rendering ($R_9 \\geq 80$)')

    # Shade the "bad R9" region
    ax.axhspan(-50, 0, alpha=0.05, color='red')
    ax.text(420, -15, 'Reds look wrong', fontsize=9, color='red',
            ha='center', style='italic')

    ax.set_xlabel('Maximum Luminous Efficacy of Radiation (lm/W)', fontsize=12)
    ax.set_ylabel('$R_9$ (Saturated Red Rendering)', fontsize=12)
    ax.set_title('The Red Rendering Penalty of High Efficacy (2700K)\n'
                'Unconstrained $R_9$ — how badly the optimizer sacrifices reds',
                fontsize=12)
    ax.legend(fontsize=9, loc='lower left')
    ax.grid(True, alpha=0.3)
    ax.set_xlim(340, 450)

    plt.tight_layout()
    plt.savefig(os.path.join(RUNDIR, 'fig6_r9_vs_efficacy.pdf'), dpi=150)
    plt.savefig(os.path.join(RUNDIR, 'fig6_r9_vs_efficacy.png'), dpi=150)
    print("Saved fig6_r9_vs_efficacy")


if __name__ == '__main__':
    print(f"Data directory: {RUNDIR}")
    print(f"Available .dat files: {len(glob.glob(os.path.join(RUNDIR, '*.dat')))}")
    print(f"Available .res files: {len(glob.glob(os.path.join(RUNDIR, '*.res')))}")
    print()

    plot1_blackbody_vs_optimized()
    plot3_convergence()
    plot4_overlay()
    plot2_cri_comparison()
    plot5_efficacy_vs_cri()
    plot6_r9_vs_efficacy()

    print("\nDone. All figures saved.")
