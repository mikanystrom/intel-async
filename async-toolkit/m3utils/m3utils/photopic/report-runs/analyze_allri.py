#!/usr/bin/env python3
"""
Analyze all-Ri sweep results: maximum Philips efficacy achievable
when ALL R_i (R1-R14) are constrained above a threshold.

Produces a summary table and compares with the unconstrained (CRI-only) results.
"""

import os
import re
import sys
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

RUNDIR = os.path.dirname(os.path.abspath(__file__))

# Production loss chain multipliers
TECH_PROD = 0.514
TECH_LAB  = 0.670
TECH_DOE  = 0.813

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
K_M = 683.0
PUMP_NM, PUMP_QE = 450.0, 0.90


def compute_phil(wl_nm, power):
    v = np.interp(wl_nm, V_LAMBDA_NM, V_VALUES, left=0, right=0)
    _t = np.trapezoid if hasattr(np, 'trapezoid') else np.trapz
    lum = _t(power * v, wl_nm)
    cost = np.ones_like(wl_nm)
    mask = wl_nm > PUMP_NM
    cost[mask] = wl_nm[mask] / (PUMP_NM * PUMP_QE)
    phil = K_M * lum / _t(power * cost, wl_nm)
    ler = K_M * lum / _t(power, wl_nm)
    return ler, phil


def load_res(fname):
    line = open(fname).readline().strip()
    nums = [float(x) for x in re.findall(r'[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?', line)]
    if len(nums) < 23:
        return None
    ri = nums[5:19]
    return {
        'cri_ra':   nums[0],
        'worst_r8': nums[1],
        'ler':      nums[2],
        'cct':      nums[3],
        'duv':      nums[4],
        'ri':       ri,
        'r9':       ri[8],
        'r12':      ri[11],
        'worst_14': min(ri),
        'cri_14':   sum(ri) / 14,
    }


def main():
    ccts = [1800, 2100, 2200, 2700]
    thresholds = [50, 60, 70, 80]

    print(f"\n{'='*100}")
    print("Maximum Philips Efficacy with All R_i >= Threshold")
    print(f"{'='*100}")
    print(f"{'CCT':>5} {'min Ri':>7} {'LER':>7} {'Phil':>7} "
          f"{'Sys_pr':>7} {'Sys_lb':>7} {'Sys_DOE':>7} "
          f"{'CRI':>6} {'R9':>6} {'R12':>6} {'worst':>6} {'CCT_act':>7}")
    print('-' * 100)

    results = {}
    for cct in ccts:
        for minri in thresholds:
            fname = os.path.join(RUNDIR,
                                 f'{cct}_CRI0_allRiP{minri}_129.res')
            dat_fname = os.path.join(RUNDIR,
                                     f'w_{cct}_CRI0_allRiP{minri}_129.dat')
            if not os.path.exists(fname):
                # Try lower dim count
                for d in [65, 33, 17, 9]:
                    alt = os.path.join(RUNDIR,
                                       f'{cct}_CRI0_allRiP{minri}_{d}.res')
                    if os.path.exists(alt):
                        fname = alt
                        dat_fname = os.path.join(RUNDIR,
                                                  f'w_{cct}_CRI0_allRiP{minri}_{d}.dat')
                        break

            if not os.path.exists(fname):
                print(f'{cct:5d} {minri:7d}    (no data)')
                continue

            specs = load_res(fname)
            if specs is None:
                continue

            phil = 0
            if os.path.exists(dat_fname):
                data = np.loadtxt(dat_fname)
                _, phil = compute_phil(data[:, 0] * 1e9, data[:, 1])

            sys_pr = phil * TECH_PROD
            sys_lb = phil * TECH_LAB
            sys_doe = phil * TECH_DOE

            print(f'{cct:5d} {minri:7d} {specs["ler"]:7.1f} {phil:7.1f} '
                  f'{sys_pr:7.1f} {sys_lb:7.1f} {sys_doe:7.1f} '
                  f'{specs["cri_ra"]:6.1f} {specs["r9"]:6.1f} '
                  f'{specs["r12"]:6.1f} {specs["worst_14"]:6.1f} '
                  f'{specs["cct"]:7.0f}')

            results[(cct, minri)] = {
                'phil': phil, 'sys_pr': sys_pr,
                'specs': specs,
            }
        print()

    # EU feasibility check
    print("\n--- EU 2019/2020 feasibility (98 lm/W system, best production) ---")
    for cct in ccts:
        for minri in thresholds:
            key = (cct, minri)
            if key not in results:
                continue
            r = results[key]
            status = "PASS" if r['sys_pr'] >= 98 else "FAIL"
            margin = r['sys_pr'] - 98
            print(f"  {cct}K all-Ri>={minri}: sys={r['sys_pr']:.1f} lm/W "
                  f"-> {status} (margin {margin:+.1f})")

    # Plot if we have enough data
    if len(results) >= 4:
        fig, ax = plt.subplots(figsize=(10, 6))
        for cct in ccts:
            xs, ys = [], []
            for minri in thresholds:
                if (cct, minri) in results:
                    xs.append(minri)
                    ys.append(results[(cct, minri)]['sys_pr'])
            if xs:
                ax.plot(xs, ys, 'o-', label=f'{cct}K', markersize=8,
                        linewidth=2)

        ax.axhline(y=98, color='red', linestyle='--', alpha=0.6,
                   label='EU 98 lm/W')
        ax.axhline(y=125, color='darkred', linestyle='-.', alpha=0.6,
                   label='DOE 125 lm/W')
        ax.set_xlabel('Minimum $R_i$ Threshold (all 14 test colors)',
                      fontsize=12)
        ax.set_ylabel('Maximum System Efficacy (lm/W, best production)',
                      fontsize=12)
        ax.set_title('Maximum Efficacy vs Color Quality Floor\n'
                     '(all $R_i \\geq$ threshold, Philips model, '
                     'best production ×0.514)',
                     fontsize=12)
        ax.legend(fontsize=10)
        ax.grid(True, alpha=0.3)
        plt.tight_layout()

        fname = 'fig_allri_frontier'
        plt.savefig(os.path.join(RUNDIR, fname + '.pdf'), dpi=150)
        plt.savefig(os.path.join(RUNDIR, fname + '.png'), dpi=150)
        print(f"\nSaved {fname}")


if __name__ == '__main__':
    main()
