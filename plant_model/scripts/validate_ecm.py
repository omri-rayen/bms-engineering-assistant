"""
ECM validation: simulate every trip and compare with measured data.
Per-trip plots + summary stats split by campaign.
------
Output:
- plant_model/data/validation_results.csv
- plant_model/plots/trips/validation_<trip_id>.png
- plant_model/plots/validation_summary.png
- plant_model/plots/validation_rmse_vs_temp.png
"""

import os, glob, warnings
import numpy as np
import pandas as pd
from scipy.interpolate import RegularGridInterpolator
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

warnings.filterwarnings('ignore')

N_SERIES = 96
DT = 0.1

T_GRID      = np.array([0, 5, 10, 15, 20, 25, 30])
SOC_OCV_GRID = np.arange(0, 101, 1)
SOC_ECM_GRID = np.arange(0, 101, 5)

# --- paths ---
SCRIPT_DIR   = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, '..', '..'))
MEAS_CSV  = os.path.join(PROJECT_ROOT, 'data', 'cleaned', 'measurement',
                          'measurement_clean.csv')
DATA_DIR  = os.path.join(SCRIPT_DIR, '..', 'data')
OUT_PLOTS = os.path.join(SCRIPT_DIR, '..', 'plots')
TRIP_PLOTS = os.path.join(OUT_PLOTS, 'trips')


# --- LUT loading ---
def load_lut(name, soc_grid):
    path = os.path.join(DATA_DIR, f'{name}_lut.csv')
    df = pd.read_csv(path)
    t_cols = [c for c in df.columns if c.startswith('T')]
    t_bp = np.array([float(c.replace('T', '').replace('C', '')) for c in t_cols])
    interp = RegularGridInterpolator(
        (soc_grid.astype(float), t_bp.astype(float)), df[t_cols].values,
        method='linear', bounds_error=False, fill_value=None)
    return interp


def load_luts():
    return {
        'ocv': load_lut('ocv', SOC_OCV_GRID),
        'r0':  load_lut('r0',  SOC_ECM_GRID),
        'r1':  load_lut('r1',  SOC_ECM_GRID),
        'c1':  load_lut('c1',  SOC_ECM_GRID),
        'r2':  load_lut('r2',  SOC_ECM_GRID),
        'c2':  load_lut('c2',  SOC_ECM_GRID),
    }


def lookup(interp, soc, T):
    return interp(np.column_stack([np.atleast_1d(soc),
                                   np.atleast_1d(T)])).ravel()


# --- ECM simulation ---
def simulate(I, soc, T, luts):
    N   = len(I)
    ocv = lookup(luts['ocv'], soc, T)
    r0  = np.clip(lookup(luts['r0'], soc, T), 1e-5, None)
    r1  = np.clip(lookup(luts['r1'], soc, T), 1e-6, None)
    c1  = np.clip(lookup(luts['c1'], soc, T), 100., None)
    r2  = np.clip(lookup(luts['r2'], soc, T), 1e-6, None)
    c2  = np.clip(lookup(luts['c2'], soc, T), 100., None)
    tau1 = r1 * c1
    tau2 = r2 * c2

    V = np.empty(N)
    vrc1 = vrc2 = 0.0
    for k in range(N):
        V[k] = ocv[k] + I[k] * r0[k] + vrc1 + vrc2
        if k < N - 1:
            a1 = np.exp(-DT / tau1[k])
            a2 = np.exp(-DT / tau2[k])
            vrc1 = a1 * vrc1 + r1[k] * (1 - a1) * I[k]
            vrc2 = a2 * vrc2 + r2[k] * (1 - a2) * I[k]
    return V


# --- per-trip plot ---
def plot_trip(tid, t_s, V_meas, V_model, rmse, T_mean, campaign, plt):
    err = (V_model - V_meas) * 1e3   # mV

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 6),
                                    sharex=True,
                                    gridspec_kw={'height_ratios': [2, 1]})
    color = 'tab:blue' if campaign == 'A' else 'tab:orange'

    # Voltage comparison
    ax1.plot(t_s, V_meas * 1e3, lw=0.6, color='black', alpha=0.7,
             label='Measured')
    ax1.plot(t_s, V_model * 1e3, lw=0.6, color=color, alpha=0.8,
             label='ECM Model')
    ax1.set_ylabel('V_cell [mV]')
    ax1.set_title(f'{tid}  |  Campaign {campaign}  |  '
                  f'RMSE = {rmse:.1f} mV  |  T_mean = {T_mean:.0f} C')
    ax1.legend(fontsize=8, loc='upper right')
    ax1.grid(True, alpha=0.3)

    # Error
    ax2.plot(t_s, err, lw=0.5, color='tab:red', alpha=0.7)
    ax2.axhline(0, color='black', lw=0.4)
    ax2.set_ylabel('Error [mV]')
    ax2.set_xlabel('Time [s]')
    ax2.grid(True, alpha=0.3)

    fig.tight_layout()
    fig.savefig(os.path.join(TRIP_PLOTS, f'validation_{tid}.png'), dpi=120)
    plt.close(fig)


# --- summary plots ---
def plot_summary(res, plt):
    # RMSE histogram by campaign
    fig, ax = plt.subplots(figsize=(9, 5))
    for camp, color, label in [('A', 'tab:blue', 'Campaign A (summer)'),
                                ('B', 'tab:orange', 'Campaign B (winter)')]:
        sub = res[res['campaign'] == camp]
        if sub.empty:
            continue
        ax.hist(sub['rmse_mV'], bins=20, alpha=0.6, color=color,
                edgecolor='black', label=f'{label} (n={len(sub)})')
    med = res['rmse_mV'].median()
    ax.axvline(med, color='red', ls='--', lw=1.5,
               label=f'Overall median = {med:.1f} mV')
    ax.set_xlabel('RMSE [mV] (cell)')
    ax.set_ylabel('Trip count')
    ax.set_title(f'ECM Validation - RMSE Distribution ({len(res)} trips)')
    ax.legend()
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(os.path.join(OUT_PLOTS, 'validation_summary.png'), dpi=150)
    plt.close(fig)

    # RMSE vs temperature
    fig, ax = plt.subplots(figsize=(9, 5))
    for camp, color, marker in [('A', 'tab:blue', 'o'),
                                 ('B', 'tab:orange', 's')]:
        sub = res[res['campaign'] == camp]
        if sub.empty:
            continue
        ax.scatter(sub['T_mean'], sub['rmse_mV'], c=color, marker=marker,
                   s=40, alpha=0.7, edgecolors='white', linewidths=0.3,
                   label=f'Campaign {camp}')
    ax.set_xlabel('Mean Battery Temperature [C]')
    ax.set_ylabel('RMSE [mV]')
    ax.set_title('Per-Trip RMSE vs Temperature')
    ax.legend()
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(os.path.join(OUT_PLOTS, 'validation_rmse_vs_temp.png'), dpi=150)
    plt.close(fig)

    print(f"  Summary plots saved: {OUT_PLOTS}/validation_*.png")


def main():
    print('--- ECM Validation ---')

    luts = load_luts()
    print("LUTs loaded.")

    df = pd.read_csv(MEAS_CSV)
    print(f"Data: {len(df):,} rows, {df['trip_id'].nunique()} trips\n")

    # prepare output dirs, clean old plots
    os.makedirs(TRIP_PLOTS, exist_ok=True)
    for f in glob.glob(os.path.join(TRIP_PLOTS, 'validation_*.png')):
        os.remove(f)
    for f in glob.glob(os.path.join(OUT_PLOTS, 'validation_*.png')):
        os.remove(f)

    results = []
    trip_ids = sorted(df['trip_id'].unique())

    for ti, tid in enumerate(trip_ids):
        grp = df[df['trip_id'] == tid].sort_values('time_s').reset_index(drop=True)
        I     = grp['battery_current_a'].values
        V_meas = grp['battery_voltage_v'].values / N_SERIES
        soc   = grp['soc_pct'].values
        T     = grp['battery_temperature_c'].values
        t_s   = grp['time_s'].values
        camp  = 'A' if tid.startswith('TripA') else 'B'

        V_model = simulate(I, soc, T, luts)
        err = V_model - V_meas

        rmse = np.sqrt(np.mean(err**2)) * 1e3
        mae  = np.mean(np.abs(err)) * 1e3
        maxe = np.max(np.abs(err)) * 1e3
        bias = np.mean(err) * 1e3

        results.append({
            'trip_id': tid, 'campaign': camp,
            'n_samples': len(I),
            'duration_s': t_s[-1] - t_s[0],
            'T_mean': T.mean(), 'T_min': T.min(), 'T_max': T.max(),
            'soc_start': soc[0], 'soc_end': soc[-1],
            'rmse_mV': rmse, 'mae_mV': mae,
            'max_err_mV': maxe, 'bias_mV': bias,
        })

        # per-trip plot
        plot_trip(tid, t_s, V_meas, V_model, rmse, T.mean(), camp, plt)

        if (ti + 1) % 10 == 0 or ti + 1 == len(trip_ids):
            print(f"  [{ti+1}/{len(trip_ids)}] {tid}: "
                  f"RMSE={rmse:.1f} mV, bias={bias:+.1f} mV")

    res = pd.DataFrame(results)

    # summary
    print('\nValidation Summary')
    print(f"  Trips: {len(res)}")
    print(f"  RMSE : median={res['rmse_mV'].median():.1f} mV, "
          f"mean={res['rmse_mV'].mean():.1f} mV, "
          f"max={res['rmse_mV'].max():.1f} mV")
    print(f"  < 15 mV: {(res['rmse_mV'] < 15).sum()}/{len(res)}  "
          f"< 20 mV: {(res['rmse_mV'] < 20).sum()}/{len(res)}  "
          f"> 30 mV: {(res['rmse_mV'] > 30).sum()}/{len(res)}")

    for camp in ['A', 'B']:
        sub = res[res['campaign'] == camp]
        if sub.empty:
            continue
        print(f"\n  Campaign {camp} ({len(sub)} trips):")
        print(f"    RMSE : median={sub['rmse_mV'].median():.1f} mV, "
              f"mean={sub['rmse_mV'].mean():.1f} mV")
        print(f"    Bias : mean={sub['bias_mV'].mean():.1f} mV")
        print(f"    T range: [{sub['T_mean'].min():.0f}, {sub['T_mean'].max():.0f}] C")

    # save
    os.makedirs(DATA_DIR, exist_ok=True)
    csv_path = os.path.join(DATA_DIR, 'validation_results.csv')
    res.to_csv(csv_path, index=False)
    print(f"\n  Results saved: {csv_path}")

    # summary plots
    plot_summary(res, plt)


if __name__ == '__main__':
    main()
