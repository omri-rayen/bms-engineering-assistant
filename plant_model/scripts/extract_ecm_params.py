"""
ECM parameter extraction: R0, R1, C1, R2, C2 as 2D LUTs over (SoC, T).
------
R0: instantaneous voltage steps when |dI| > threshold.
RC: windowed least-squares on 60s segments, OCV and R0 as fixed inputs.
All params at cell level (pack / 96). Negative current = discharge.
------
Output:
- plant_model/data/{r0,r1,c1,r2,c2}_lut.csv  (21 SoC x 7 T each)
- plant_model/data/ecm_params_all.csv
- plant_model/plots/ecm_*.png
"""

import os, glob, warnings
import numpy as np
import pandas as pd
from scipy.interpolate import RegularGridInterpolator
from scipy.optimize import least_squares
from scipy.ndimage import gaussian_filter

warnings.filterwarnings('ignore')

N_SERIES = 96
DT = 0.1

T_GRID = np.array([0, 5, 10, 15, 20, 25, 30])
T_HALF = 3.0
SOC_GRID = np.arange(0, 101, 5)   # 21 breakpoints
SOC_HALF = 2.5

# R0 extraction
STEP_THRESH   = 8.0    # min |dI| for a current step [A]
PRESTEP_THRESH = 4.0   # max |dI| before the step (stability)
R0_MIN = 1e-4           # 0.1 mOhm
R0_MAX = 5e-3           # 5 mOhm
R0_MIN_PTS = 3

# RC fitting
WIN_S     = 60.0        # window length [s]
STRIDE_S  = 30.0        # stride [s]
MIN_I_STD = 5.0         # min std(I) to attempt fit [A]
RC_RMSE_MAX = 0.015     # max window RMSE [V, cell]

# smoothing
SMOOTH_SIGMA = [0.8, 0.5]   # [SoC, T]

# --- paths ---
SCRIPT_DIR   = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, '..', '..'))
MEAS_CSV = os.path.join(PROJECT_ROOT, 'data', 'cleaned', 'measurement',
                         'measurement_clean.csv')
OCV_CSV  = os.path.join(SCRIPT_DIR, '..', 'data', 'ocv_lut.csv')
OUT_DATA  = os.path.join(SCRIPT_DIR, '..', 'data')
OUT_PLOTS = os.path.join(SCRIPT_DIR, '..', 'plots')


# --- OCV look-up ---
def load_ocv_lut():
    df = pd.read_csv(OCV_CSV)
    soc_bp = df['SoC_pct'].values.astype(float)
    t_cols = [c for c in df.columns if c.startswith('T')]
    t_bp = np.array([float(c.replace('T', '').replace('C', '')) for c in t_cols])
    interp = RegularGridInterpolator(
        (soc_bp, t_bp), df[t_cols].values,
        method='linear', bounds_error=False, fill_value=None)
    return interp


def lut_lookup(interp, soc, T):
    pts = np.column_stack([np.atleast_1d(soc), np.atleast_1d(T)])
    return interp(pts).ravel()


# --- R0 extraction ---
def extract_r0(df):
    records = []
    for tid, grp in df.groupby('trip_id'):
        grp = grp.sort_values('time_s').reset_index(drop=True)
        I   = grp['battery_current_a'].values
        V   = grp['battery_voltage_v'].values / N_SERIES
        soc = grp['soc_pct'].values
        T   = grp['battery_temperature_c'].values

        dI = np.diff(I)
        dV = np.diff(V)
        dI_pre = np.concatenate([[0], dI[:-1]])

        for k in range(1, len(dI)):
            if abs(dI[k]) < STEP_THRESH:
                continue
            if abs(dI_pre[k]) > PRESTEP_THRESH:
                continue
            r0 = abs(dV[k]) / abs(dI[k])
            if R0_MIN <= r0 <= R0_MAX:
                records.append({
                    'soc': soc[k+1], 'temperature': T[k+1],
                    'r0': r0, 'trip_id': tid,
                })

    r0_df = pd.DataFrame(records)
    print(f"  {len(r0_df):,} events from {r0_df['trip_id'].nunique()} trips")
    return r0_df


def build_r0_lut(r0_df):
    n_s, n_t = len(SOC_GRID), len(T_GRID)
    lut = np.full((n_s, n_t), np.nan)
    counts = np.zeros((n_s, n_t), dtype=int)

    for j, tc in enumerate(T_GRID):
        tm = (r0_df['temperature'] >= tc - T_HALF) & \
             (r0_df['temperature'] <= tc + T_HALF)
        for i, sc in enumerate(SOC_GRID):
            sm = (r0_df['soc'] >= sc - SOC_HALF) & \
                 (r0_df['soc'] < sc + SOC_HALF)
            sub = r0_df.loc[tm & sm, 'r0']
            counts[i, j] = len(sub)
            if len(sub) >= R0_MIN_PTS:
                lut[i, j] = sub.median()
    return lut, counts


# --- fill + smooth ---
def fill_and_smooth(lut, label=''):
    # T-axis interpolation (log-space for resistances captures Arrhenius-like behaviour)
    use_log = label.upper() in ('R0', 'R1', 'R2')
    for i in range(lut.shape[0]):
        row = lut[i, :]
        v = ~np.isnan(row)
        if v.sum() >= 2 and not v.all():
            if use_log:
                log_row = np.log(row)
                lut[i, :] = np.exp(np.interp(T_GRID, T_GRID[v], log_row[v]))
            else:
                lut[i, :] = np.interp(T_GRID, T_GRID[v], row[v])
        elif v.sum() == 1:
            lut[i, :] = row[v][0]

    # SoC-axis interpolation
    for j in range(lut.shape[1]):
        col = lut[:, j]
        v = ~np.isnan(col)
        if v.sum() >= 2:
            lut[:, j] = np.interp(SOC_GRID, SOC_GRID[v], col[v])

    if np.isnan(lut).any():
        med = np.nanmedian(lut)
        lut[np.isnan(lut)] = med

    return gaussian_filter(lut, sigma=SMOOTH_SIGMA)


# --- 2-RC simulation ---
def sim_2rc(I, ocv, r0, R1, tau1, R2, tau2, vrc1_0, vrc2_0):
    N = len(I)
    a1 = np.exp(-DT / tau1)
    a2 = np.exp(-DT / tau2)
    b1 = R1 * (1 - a1)
    b2 = R2 * (1 - a2)

    vrc1 = np.empty(N)
    vrc2 = np.empty(N)
    vrc1[0] = vrc1_0
    vrc2[0] = vrc2_0
    for k in range(1, N):
        vrc1[k] = a1 * vrc1[k-1] + b1 * I[k-1]
        vrc2[k] = a2 * vrc2[k-1] + b2 * I[k-1]
    return ocv + I * r0 + vrc1 + vrc2


def residual(p, I, ocv, r0, V):
    R1, tau1, R2, tau2, v10, v20 = p
    return sim_2rc(I, ocv, r0, R1, tau1, R2, tau2, v10, v20) - V


# bounds and starting points (cell level)
LB = np.array([1e-5,  0.5,  1e-5,   5.0, -0.05, -0.05])
UB = np.array([5e-3, 20.0,  5e-3, 200.0,  0.05,  0.05])
X0S = [
    np.array([5e-4,  3.0, 5e-4,  30.0, 0, 0]),
    np.array([3e-4,  8.0, 3e-4,  60.0, 0, 0]),
    np.array([8e-4,  1.5, 2e-4, 100.0, 0, 0]),
]


def fit_rc(df, ocv_interp, r0_interp):
    win_n    = int(WIN_S / DT)
    stride_n = int(STRIDE_S / DT)
    records  = []
    n_tot = n_good = 0

    trip_ids = sorted(df['trip_id'].unique())
    for ti, tid in enumerate(trip_ids):
        grp = df[df['trip_id'] == tid].sort_values('time_s').reset_index(drop=True)
        I    = grp['battery_current_a'].values
        V    = grp['battery_voltage_v'].values / N_SERIES
        soc  = grp['soc_pct'].values
        T    = grp['battery_temperature_c'].values

        if len(I) < win_n:
            continue

        ocv_trip = lut_lookup(ocv_interp, soc, T)
        r0_trip  = np.clip(lut_lookup(r0_interp, soc, T), R0_MIN, R0_MAX)

        for start in range(0, len(I) - win_n + 1, stride_n):
            end = start + win_n
            Iw, Vw = I[start:end], V[start:end]
            ow, rw = ocv_trip[start:end], r0_trip[start:end]
            sw, Tw = soc[start:end], T[start:end]

            if np.std(Iw) < MIN_I_STD:
                continue
            n_tot += 1

            best_cost, best_p = np.inf, None
            for x0 in X0S:
                try:
                    res = least_squares(residual, x0,
                                        args=(Iw, ow, rw, Vw),
                                        bounds=(LB, UB),
                                        method='trf', max_nfev=200)
                    if res.cost < best_cost:
                        best_cost = res.cost
                        best_p = res.x
                except Exception:
                    continue

            if best_p is None:
                continue
            rmse = np.sqrt(2 * best_cost / win_n)
            if rmse > RC_RMSE_MAX:
                continue
            if np.any(best_p[:4] <= LB[:4] * 1.01) or \
               np.any(best_p[:4] >= UB[:4] * 0.99):
                continue

            R1, tau1, R2, tau2 = best_p[:4]
            if tau1 > tau2:
                R1, R2 = R2, R1
                tau1, tau2 = tau2, tau1

            records.append({
                'soc': np.mean(sw), 'temperature': np.mean(Tw),
                'R1': R1, 'tau1': tau1, 'C1': tau1 / R1,
                'R2': R2, 'tau2': tau2, 'C2': tau2 / R2,
                'rmse': rmse, 'trip_id': tid,
            })
            n_good += 1

        if (ti + 1) % 10 == 0 or ti + 1 == len(trip_ids):
            print(f"  [{ti+1}/{len(trip_ids)}] {n_good}/{n_tot} good windows")

    rc_df = pd.DataFrame(records)
    print(f"  RC fits: {len(rc_df)} good / {n_tot} attempted")
    return rc_df


def build_param_lut(raw, col, min_n=2):
    n_s, n_t = len(SOC_GRID), len(T_GRID)
    lut = np.full((n_s, n_t), np.nan)
    for j, tc in enumerate(T_GRID):
        tm = (raw['temperature'] >= tc - T_HALF) & \
             (raw['temperature'] <= tc + T_HALF)
        for i, sc in enumerate(SOC_GRID):
            sm = (raw['soc'] >= sc - SOC_HALF) & \
                 (raw['soc'] < sc + SOC_HALF)
            sub = raw.loc[tm & sm, col]
            if len(sub) >= min_n:
                lut[i, j] = sub.median()
    return lut


def save_lut(lut, name):
    df = pd.DataFrame(lut, columns=[f'T{t}C' for t in T_GRID])
    df.insert(0, 'SoC_pct', SOC_GRID)
    path = os.path.join(OUT_DATA, f'{name}_lut.csv')
    df.to_csv(path, index=False)
    return path


# --- plotting ---
def make_plots(luts):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt

    os.makedirs(OUT_PLOTS, exist_ok=True)
    for f in glob.glob(os.path.join(OUT_PLOTS, 'ecm_*.png')):
        os.remove(f)

    names  = ['r0',   'r1',   'c1', 'r2',   'c2']
    labels = ['R0 [mOhm]', 'R1 [mOhm]', 'C1 [F]', 'R2 [mOhm]', 'C2 [F]']
    scales = [1e3,    1e3,    1,    1e3,    1]

    fig, axes = plt.subplots(2, 3, figsize=(16, 9))
    for idx, (n, lab, sc) in enumerate(zip(names, labels, scales)):
        ax = axes.flat[idx]
        for j, t in enumerate(T_GRID):
            ax.plot(SOC_GRID, luts[n][:, j] * sc, lw=1.2, label=f'{t} C')
        ax.set_xlabel('SoC [%]')
        ax.set_ylabel(lab)
        ax.set_title(n.upper())
        ax.legend(fontsize=7)
        ax.grid(True, alpha=0.3)
    axes.flat[5].set_visible(False)
    fig.suptitle('ECM Parameter LUTs (smoothed)', fontsize=13)
    fig.tight_layout()
    fig.savefig(os.path.join(OUT_PLOTS, 'ecm_luts.png'), dpi=150)
    plt.close(fig)

    print(f"  Plots saved: {OUT_PLOTS}/ecm_*.png")


def main():
    print('--- ECM Parameter Extraction (R0, R1, C1, R2, C2) ---')

    ocv_interp = load_ocv_lut()
    print("OCV LUT loaded.")

    df = pd.read_csv(MEAS_CSV)
    print(f"Measurement data: {len(df):,} rows, {df['trip_id'].nunique()} trips")
    os.makedirs(OUT_DATA, exist_ok=True)

    print('\nR0 Extraction')
    r0_df = extract_r0(df)
    r0_lut, r0_counts = build_r0_lut(r0_df)
    r0_lut = fill_and_smooth(r0_lut, 'R0')
    save_lut(r0_lut, 'r0')
    print(f"  R0 range: {r0_lut.min()*1e3:.3f} - {r0_lut.max()*1e3:.3f} mOhm")

    # R0 interpolator for RC fitting
    r0_interp = RegularGridInterpolator(
        (SOC_GRID.astype(float), T_GRID.astype(float)), r0_lut,
        method='linear', bounds_error=False, fill_value=None)

    print('\nRC Parameter Extraction')
    rc_df = fit_rc(df, ocv_interp, r0_interp)

    if not rc_df.empty:
        rc_df.to_csv(os.path.join(OUT_DATA, 'ecm_params_all.csv'), index=False)

    print('\nBuilding LUTs')
    luts = {'r0': r0_lut}
    if rc_df.empty:
        print("  WARNING: no RC fits - using defaults")
        for n, val in [('r1', 5e-4), ('c1', 5000), ('r2', 5e-4), ('c2', 50000)]:
            luts[n] = np.full((len(SOC_GRID), len(T_GRID)), val)
    else:
        for n in ['R1', 'C1', 'R2', 'C2']:
            raw = build_param_lut(rc_df, n)
            raw = fill_and_smooth(raw, n)
            luts[n.lower()] = raw
            p = save_lut(raw, n.lower())
            print(f"  {n}: [{raw.min():.6f}, {raw.max():.6f}] -> {p}")

    print('\nPlotting')
    make_plots(luts)


if __name__ == '__main__':
    main()
