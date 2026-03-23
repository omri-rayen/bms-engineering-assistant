"""
OCV(SoC, T) extraction from measurement data.
------
Strategy: build the OCV LUT directly from per (SoC, T) bin medians.
------
Output:
- plant_model/data/ocv_lut.csv   (101 SoC x 7 T)
- plant_model/plots/ocv_*.png
"""

import os
import numpy as np
import pandas as pd
import matplotlib
import matplotlib.pyplot as plt
from scipy.interpolate import PchipInterpolator
from scipy.ndimage import gaussian_filter

matplotlib.use('Agg')

N_SERIES = 96
QS_CURRENT_MAX = 3.0      # |I| threshold for quasi-static [A]
SETTLE_TIME = 3.0         # min consecutive QS time [s]
DT = 0.1                  # sampling period [s]
MIN_PTS = 5               # min points per bin to use median

T_GRID  = np.array([0, 5, 10, 15, 20, 25, 30])
T_HALF  = 3.0
SOC_GRID = np.arange(0, 101, 1)

# NMC anchors (cell level)
V_EMPTY = 2.80
V_FULL  = 4.20

SMOOTH_SIGMA = [1.5, 0.8]   # Gaussian [SoC, T]

# paths
SCRIPT_DIR   = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, '..', '..'))
MEAS_CSV     = os.path.join(PROJECT_ROOT, 'data', 'cleaned', 'measurement',
                             'measurement_clean.csv')
OUT_DATA  = os.path.join(SCRIPT_DIR, '..', 'data')
OUT_PLOTS = os.path.join(SCRIPT_DIR, '..', 'plots')


# --- functions ---
def load_data():
    df = pd.read_csv(MEAS_CSV)
    df['campaign'] = df['trip_id'].apply(lambda t: 'A' if t.startswith('TripA') else 'B')
    na = (df['campaign'] == 'A').sum()
    nb = (df['campaign'] == 'B').sum()
    print(f"  {len(df):,} rows, {df['trip_id'].nunique()} trips  "
          f"(A: {na:,}  B: {nb:,})")
    return df


# --- extract quasi-static points ---
def extract_qs(df):
    settle_n = int(SETTLE_TIME / DT)    # min settle number
    records = []
    for tid, grp in df.groupby('trip_id'):
        grp = grp.sort_values('time_s').reset_index(drop=True)
        I = grp['battery_current_a'].values
        V = grp['battery_voltage_v'].values
        soc = grp['soc_pct'].values
        T = grp['battery_temperature_c'].values
        camp = grp['campaign'].iloc[0]

        is_qs = np.abs(I) < QS_CURRENT_MAX
        cnt = np.zeros(len(is_qs), dtype=int)
        for i in range(1, len(is_qs)):
            cnt[i] = (cnt[i-1] + 1) if is_qs[i] else 0
        mask = cnt >= settle_n

        for i in np.where(mask)[0]:
            records.append((soc[i], T[i], V[i] / N_SERIES, tid, camp))

    qs = pd.DataFrame(records, columns=['soc', 'temp', 'v_cell', 'trip_id', 'campaign'])

    for c in ['A', 'B']:
        sub = qs[qs['campaign'] == c]
        print(f"  Campaign {c}: {len(sub):,} qs pts, "
              f"T = [{sub['temp'].min():.0f}, {sub['temp'].max():.0f}] C")
    return qs


# --- build OCV LUT directly from bin medians ---
def build_lut(qs):
    lut = np.full((len(SOC_GRID), len(T_GRID)), np.nan)
    counts = np.zeros_like(lut, dtype=int)
    # medians[j] = {soc: median_v} for temperature column j, reused in plots
    medians = [{} for _ in T_GRID]

    for j, tc in enumerate(T_GRID):
        tmask = (qs['temp'] >= tc - T_HALF) & (qs['temp'] <= tc + T_HALF)
        for i, s in enumerate(SOC_GRID):
            smask = (qs['soc'] >= s - 0.5) & (qs['soc'] < s + 0.5)
            sub = qs.loc[tmask & smask, 'v_cell']
            counts[i, j] = len(sub)
            if len(sub) >= MIN_PTS:
                m = sub.median()
                lut[i, j] = m
                medians[j][s] = m

    # fill gaps along SoC axis with PCHIP + NMC anchors
    for j in range(len(T_GRID)):
        col = lut[:, j]
        valid = ~np.isnan(col)
        if valid.sum() < 3:     # need at least 3 points for interpolation
            continue
        sv = list(SOC_GRID[valid])
        vv = list(col[valid])
        if sv[0] > 2:
            sv.insert(0, 0);  vv.insert(0, V_EMPTY)
        if sv[-1] < 98:
            sv.append(100);   vv.append(V_FULL)
        lut[:, j] = PchipInterpolator(sv, vv)(SOC_GRID)

    # fill remaining NaN along T axis (linear)
    for i in range(len(SOC_GRID)):
        row = lut[i, :]
        valid = ~np.isnan(row)
        if valid.sum() >= 2 and not valid.all():
            lut[i, :] = np.interp(T_GRID, T_GRID[valid], row[valid])
        elif valid.sum() == 1:
            lut[i, :] = row[valid][0]

    remaining_nan = np.isnan(lut).sum()
    if remaining_nan:
        raise ValueError(
            f"{remaining_nan} NaN values remain in LUT after interpolation. "
            "Check data coverage — PCHIP and T-axis fill should handle all gaps."
        )

    print(f"  LUT: V = [{lut.min():.4f}, {lut.max():.4f}] V")
    return lut, counts, medians


def smooth_and_enforce(lut):
    """Gaussian smooth, then enforce monotonicity along SoC axis."""
    lut = gaussian_filter(lut, sigma=SMOOTH_SIGMA)
    for j in range(lut.shape[1]):
        for i in range(1, lut.shape[0]):
            if lut[i, j] < lut[i-1, j]:
                lut[i, j] = lut[i-1, j]
    return lut


# --- measure ageing offset ---
def measure_ageing(qs):
    """Median V offset (B - A) in the overlap zone T in [17, 22] C."""
    ov = qs[(qs['temp'] >= 17) & (qs['temp'] <= 22)]
    deltas = []
    for s in range(30, 85):
        sub = ov[(ov['soc'] >= s - 2) & (ov['soc'] < s + 2)]
        va = sub.loc[sub['campaign'] == 'A', 'v_cell']
        vb = sub.loc[sub['campaign'] == 'B', 'v_cell']
        if len(va) >= 20 and len(vb) >= 5:
            deltas.append(vb.median() - va.median())
    if deltas:
        med = np.median(deltas) * 1e3
        lo  = np.min(deltas) * 1e3
        hi  = np.max(deltas) * 1e3
        print(f"  Ageing offset (B - A): median {med:+.1f} mV  "
              f"[{lo:+.1f}, {hi:+.1f}] mV")
    else:
        print("  Ageing offset: no overlap data available")

# def ageing_correction(qs, AGEING_OFFSET):
#     T_AGE_MIN = 17.0
#     T_AGE_MAX = 22.0

#     mask_b_overlap = (
#         (qs['campaign'] == 'B') &
#         (qs['temp'] >= T_AGE_MIN) &
#         (qs['temp'] <= T_AGE_MAX)
#     )

#     qs.loc[mask_b_overlap, 'v_cell'] -= AGEING_OFFSET


# save LUT
def save_lut(lut):
    os.makedirs(OUT_DATA, exist_ok=True)
    df = pd.DataFrame(lut, columns=[f'T{t}C' for t in T_GRID])
    df.insert(0, 'SoC_pct', SOC_GRID)
    path = os.path.join(OUT_DATA, 'ocv_lut.csv')
    df.to_csv(path, index=False)
    print(f"  Saved: {path}")
    print(f"  Shape: {lut.shape[0]} SoC x {lut.shape[1]} T")
    print(f"  V range: {lut.min():.4f} - {lut.max():.4f} V")
    row50 = lut[50, :]
    print(f"  T spread at SoC=50%: {(row50.max()-row50.min())*1e3:.1f} mV")


# --- plots ---
def make_plots(lut, qs, counts, medians):
    os.makedirs(OUT_PLOTS, exist_ok=True)

    cmap = plt.cm.coolwarm
    colors = cmap(np.linspace(0.05, 0.95, len(T_GRID)))

    # OCV curves only
    fig, ax = plt.subplots(figsize=(10, 6))
    for j, t in enumerate(T_GRID):
        ax.plot(SOC_GRID, lut[:, j], lw=1.8, color=colors[j], label=f'{t} C')
    ax.set_xlabel('SoC [%]')
    ax.set_ylabel('OCV [V] (cell)')
    ax.set_title('OCV(SoC, T) - All Temperatures')
    ax.legend(title='Temperature', loc='lower right')
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(os.path.join(OUT_PLOTS, 'ocv_curves.png'), dpi=150)
    plt.close(fig)

    # OCV curves + pre-computed medians + anchors
    fig, ax = plt.subplots(figsize=(10, 6))
    for j, t in enumerate(T_GRID):
        ax.plot(SOC_GRID, lut[:, j], lw=1.8, color=colors[j], label=f'{t} C')
        soc_med = list(medians[j].keys())
        v_med   = list(medians[j].values())
        if soc_med:
            ax.scatter(soc_med, v_med, s=25, color=colors[j], alpha=1.0,
                       edgecolors='white', linewidths=0.5, zorder=3)
    ax.scatter([0, 100], [V_EMPTY, V_FULL], marker='^', s=150, c='red',
               zorder=5, edgecolors='black', label='NMC anchors')
    ax.set_xlabel('SoC [%]')
    ax.set_ylabel('OCV [V] (cell)')
    ax.set_title('OCV(SoC, T) - Curves with Extracted Medians')
    ax.legend(title='Temperature', loc='lower right')
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(os.path.join(OUT_PLOTS, 'ocv_curves_with_data.png'), dpi=150)
    plt.close(fig)

    # source points by campaign
    fig, axes = plt.subplots(1, 2, figsize=(14, 5))
    cfg = [('A', 'Campaign A - Summer 2019\n(Jun-Jul, T = 17-30 C)', 'tab:blue'),
           ('B', 'Campaign B - Winter 2019/20\n(Dec-Feb, T = -1-22 C)', 'tab:orange')]
    for ax, (c, title, color) in zip(axes, cfg):
        sub = qs[qs['campaign'] == c]
        ax.scatter(sub['soc'], sub['temp'], s=3, alpha=0.3,marker='.', color=color)
        ax.set_xlabel('SoC [%]')
        ax.set_ylabel('Battery Temperature [C]')
        ax.set_title(f'{title}\n{len(sub):,} QS points')
        ax.set_xlim(0, 100)
        ax.set_ylim(-5, 35)
        ax.grid(True, alpha=0.3)
    fig.suptitle('Quasi-Static Data Source', fontsize=13, y=1.02)
    fig.tight_layout()
    fig.savefig(os.path.join(OUT_PLOTS, 'ocv_source_points.png'), dpi=150)
    plt.close(fig)

    # data coverage heatmap
    fig, ax = plt.subplots(figsize=(8, 8))
    im = ax.imshow(counts, aspect='auto', origin='lower',
                   extent=[T_GRID[0] - T_HALF, T_GRID[-1] + T_HALF,
                           SOC_GRID[0] - 0.5, SOC_GRID[-1] + 0.5],
                   cmap='YlOrRd', interpolation='nearest')
    ax.set_xlabel('Temperature [C]')
    ax.set_ylabel('SoC [%]')
    ax.set_title('QS Data Coverage per (SoC, T) Bin')
    fig.colorbar(im, ax=ax, label='Count')
    fig.tight_layout()
    fig.savefig(os.path.join(OUT_PLOTS, 'ocv_coverage.png'), dpi=150)
    plt.close(fig)

    print(f"  Plots saved: {OUT_PLOTS}/ocv_*.png")


def main():
    print('--- OCV(SoC, T) Extraction ---')
    print('\n1. Loading data ...')
    df = load_data()

    print('\n2. Extracting quasi-static points ...')
    qs = extract_qs(df)

    # print('\n3a. Applying ageing correction ...')
    # ageing_correction(qs, 0.0151)

    print('\n3. Measuring ageing offset ...')
    measure_ageing(qs)

    print('\n4. Building OCV LUT ...')
    lut, counts, medians = build_lut(qs)
    lut = smooth_and_enforce(lut)

    print('\n5. Saving ...')
    save_lut(lut)

    print('\n6. Plotting ...')
    make_plots(lut, qs, counts, medians)


if __name__ == '__main__':
    main()