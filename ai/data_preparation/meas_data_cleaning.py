"""
Cleaning script for measurement dataset (TripA & TripB).
Merges all trips into a single clean CSV file.
"""

import pandas as pd
import numpy as np
import os
import glob

RAW_DIR = os.path.join(os.path.dirname(__file__), '..', '..', 'data', 'raw', 'measurement')
OUT_DIR = os.path.join(os.path.dirname(__file__), '..', '..', 'data', 'cleaned', 'measurement')

# columns to keep (original names) and their clean snake_case equivalents
COL_RENAME = {
    'Time [s]':                          'time_s',
    'Velocity [km/h]':                   'velocity_kmh',
    'Elevation [m]':                     'elevation_m',
    'Throttle [%]':                      'throttle_pct',
    'Motor Torque [Nm]':                 'motor_torque_nm',
    'Longitudinal Acceleration [m/s^2]': 'longitudinal_acceleration_ms2',
    'Regenerative Braking Signal':       'regen_braking_signal',
    'Battery Voltage [V]':               'battery_voltage_v',
    'Battery Current [A]':               'battery_current_a',
    'Battery Temperature [°C]':          'battery_temperature_c',
    'max. Battery Temperature [°C]':     'max_battery_temperature_c',
    'SoC [%]':                           'soc_pct',
    'displayed SoC [%]':                 'displayed_soc_pct',
    'Heating Power CAN [kW]':            'heating_power_can_kw',
    'Heating Power LIN [W]':             'heating_power_lin_w',
    'AirCon Power [kW]':                 'aircon_power_kw',
    'Heater Voltage [V]':                'heater_voltage_v',
    'Heater Current [A]':                'heater_current_a',
    'Ambient Temperature [°C]':          'ambient_temperature_c',
    'Coolant Temperature Heatercore [°C]': 'coolant_temp_heatercore_c',
    'Coolant Temperature Inlet [°C]':    'coolant_temp_inlet_c',
    'Heat Exchanger Temperature [°C]':   'heat_exchanger_temperature_c',
    'Cabin Temperature Sensor [°C]':     'cabin_temperature_c',
}

KEEP_COLS = list(COL_RENAME.keys())

# max acceptable jump between consecutive rows (per-signal spike thresholds)
SPIKE_LIMITS = {
    'SoC [%]': 3.0,
    'Battery Voltage [V]': 30.0,
    'Battery Temperature [°C]': 5.0,
    'Ambient Temperature [°C]': 5.0,
}

# Per-trip leading trim: remove initial seconds where BMS sensors are not yet settled.
# TripB02: BMS SoC lags ~4% behind coulomb counting during the first 200 s of
#          heavy discharge, then tracks correctly.  Trim that initial segment.
TRIP_TRIM_START_S = {
    'TripB02': 200.0,
}


def remove_spikes(df, trip_id):
    """Replace sensor spikes (isolated glitch) with NaN."""
    n_spikes = 0
    for col, limit in SPIKE_LIMITS.items():
        if col not in df.columns:
            continue
        diff = df[col].diff().abs()
        spike_mask = diff > limit
        if spike_mask.any():
            count = spike_mask.sum()
            n_spikes += count
            df.loc[spike_mask, col] = np.nan
    if n_spikes > 0:
        print(f"    {trip_id}: removed {n_spikes} spike(s)")
    return df


def load_and_clean(filepath):
    """Load one trip file, fix column names, select columns, handle missing values."""
    df = pd.read_csv(filepath, sep=';', encoding='latin-1')

    # strip whitespace
    df.columns = df.columns.str.strip()

    # fix the bracket typo
    df.rename(columns={'max. SoC [%)': 'max. SoC [%]'}, inplace=True)

    # keep only shared columns that exist in this file
    cols_to_keep = [c for c in KEEP_COLS if c in df.columns]
    df = df[cols_to_keep].copy()

    # add trip identifier
    fname = os.path.basename(filepath).replace('.csv', '')
    df.insert(0, 'trip_id', fname)

    # per-trip leading trim (sensor warm-up / BMS glitch removal)
    if fname in TRIP_TRIM_START_S:
        t_cut = TRIP_TRIM_START_S[fname]
        before_len = len(df)
        df = df[df['Time [s]'] >= t_cut].copy()
        df['Time [s]'] -= t_cut          # reset time to start at 0
        print(f"    {fname}: trimmed first {t_cut:.0f}s ({before_len - len(df)} rows)")

    # remove sensor spikes before interpolation
    df = remove_spikes(df, fname)

    # interpolate small gaps (forward then backward for edges)
    numeric_cols = df.select_dtypes(include=[np.number]).columns
    df[numeric_cols] = df[numeric_cols].interpolate(method='linear', limit=10)
    df[numeric_cols] = df[numeric_cols].bfill(limit=5)

    # heater-related columns: fill remaining NaN with 0 (heater off / not recorded)
    heater_cols = ['Heating Power LIN [W]', 'Heater Voltage [V]', 'Heater Current [A]',
                   'Coolant Temperature Heatercore [°C]', 'Coolant Temperature Inlet [°C]']
    for col in heater_cols:
        if col in df.columns:
            df[col] = df[col].fillna(0)

    # velocity: fill remaining NaN with 0 (vehicle stopped)
    if 'Velocity [km/h]' in df.columns:
        df['Velocity [km/h]'] = df['Velocity [km/h]'].fillna(0)

    return df


def main():
    files = sorted(glob.glob(os.path.join(RAW_DIR, 'Trip*.csv')))
    print(f"Loading {len(files)} measurement files...")

    dfs = []
    for f in files:
        df = load_and_clean(f)
        dfs.append(df)
        print(f"  {os.path.basename(f)}: {len(df)} rows")

    # merge all trips
    merged = pd.concat(dfs, ignore_index=True)
    print(f"\nMerged: {merged.shape[0]} rows x {merged.shape[1]} cols")

    # drop rows where critical columns are still NaN after interpolation
    critical_cols = ['Time [s]', 'Battery Voltage [V]', 'Battery Current [A]', 'SoC [%]']
    before = len(merged)
    merged.dropna(subset=critical_cols, inplace=True)
    dropped = before - len(merged)
    if dropped > 0:
        print(f"Dropped {dropped} rows with missing critical values")

    # fill remaining NaN in non-critical columns
    fill_zero_cols = ['Heating Power LIN [W]', 'Heater Voltage [V]', 'Heater Current [A]',
                      'Coolant Temperature Heatercore [°C]', 'Coolant Temperature Inlet [°C]',
                      'Heating Power CAN [kW]', 'AirCon Power [kW]',
                      'Heat Exchanger Temperature [°C]', 'Cabin Temperature Sensor [°C]',
                      'Velocity [km/h]', 'displayed SoC [%]']
    for col in fill_zero_cols:
        if col in merged.columns and merged[col].isnull().any():
            merged[col] = merged[col].fillna(0)

    # any leftover NaN in numeric cols: forward fill then backward fill
    numeric_cols = merged.select_dtypes(include=[np.number]).columns
    merged[numeric_cols] = merged[numeric_cols].ffill().bfill()

    # rename columns to snake_case
    merged.rename(columns=COL_RENAME, inplace=True)

    # final check
    print(f"\nFinal dataset: {merged.shape[0]} rows x {merged.shape[1]} cols")
    print(f"Missing values remaining: {merged.isnull().sum().sum()}")
    print(f"Columns: {list(merged.columns)}")

    # save
    os.makedirs(OUT_DIR, exist_ok=True)
    out_path = os.path.join(OUT_DIR, 'measurement_clean.csv')
    merged.to_csv(out_path, index=False)
    print(f"\nSaved to {out_path}")


if __name__ == '__main__':
    main()