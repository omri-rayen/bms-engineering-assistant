"""
Cleaning script for simulation dataset (CAN & LIN files).
Merges all simulation scenarios into a single clean CSV file.
"""

import pandas as pd
import numpy as np
import os
import glob

RAW_DIR = os.path.join(os.path.dirname(__file__), '..', '..', 'data', 'raw', 'simulation')
OUT_DIR = os.path.join(os.path.dirname(__file__), '..', '..', 'data', 'cleaned', 'simulation')

# temperature mapping from filename prefix
TEMP_MAP = {'Neg10': -10, '0': 0, 'Pos10': 10}

# columns to keep (after renaming duplicates) and their snake_case equivalents
COL_RENAME = {
    'Time [s]':                          'time_s',
    'Ambient Temperature [C]':           'ambient_temperature_c',
    'Longitudinal Acceleration [m/s^2]': 'longitudinal_acceleration_ms2',
    'Speed [m/s]':                       'speed_ms',
    'Traction Force [N]':                'traction_force_n',
    'Drive Torque [Nm]':                 'drive_torque_nm',
    'EM Power [kW]':                     'em_power_kw',
    'Pack Voltage [V]':                  'pack_voltage_v',
    'Battery Current [A]':               'battery_current_a',
    'Battery Power [kW]':                'battery_power_kw',
    'SOC [%]':                           'soc_pct',
    'Ageing SOH [-]':                    'ageing_soh',
    'Mean Cell Temperature [C]':         'mean_cell_temperature_c',
    'Consumption Power [kW]':            'consumption_power_kw',
    'Consumption Energy [kWh]':          'consumption_energy_kwh',
    'Cabin Temperature [C]':             'cabin_temperature_c',
    'Heating Power [kW]':                'heating_power_kw',
    'Heating Power inclPeak [kW]':       'heating_power_incl_peak_kw',
    'Heatexchanger Inlet Coolant Temp [C]': 'heatexchanger_inlet_coolant_temp_c',
    'Heatexchanger Outlet Air Temp [C]': 'heatexchanger_outlet_air_temp_c',
    'Auxiliaries Total [W]':             'auxiliaries_total_w',
}

KEEP_COLS = list(COL_RENAME.keys())


def parse_filename(fname):
    """Get temperature, scenario, bus type from filename."""
    base = fname.replace('.csv', '')
    parts = base.split('_')
    bus_type = parts[-1]  # CAN or LIN
    temp_str = parts[0]
    scenario = '_'.join(parts[1:-1])
    return temp_str, scenario, bus_type


def load_sim_file(filepath):
    """Load a simulation CSV, handling the header format differences."""
    fname = os.path.basename(filepath)

    # Neg10_Heating_CAN.csv has an extra header row (3 rows before data)
    if fname == 'Neg10_Heating_CAN.csv':
        skip_rows = [0, 1]  # skip the extra row and category row
        df = pd.read_csv(filepath, sep=';', encoding='latin-1',
                         skiprows=skip_rows, low_memory=False)
    else:
        # normal files: row 0 = category, row 1 = column names
        df = pd.read_csv(filepath, sep=';', encoding='latin-1',
                         header=1, low_memory=False)

    # handle duplicate "Power [kW]" columns - pandas auto-renames to "Power [kW].1"
    rename_map = {}
    if 'Power [kW]' in df.columns:
        rename_map['Power [kW]'] = 'Battery Power [kW]'
    if 'Power [kW].1' in df.columns:
        rename_map['Power [kW].1'] = 'Consumption Power [kW]'
    if 'Energy [kWh]' in df.columns:
        rename_map['Energy [kWh]'] = 'Consumption Energy [kWh]'
    df.rename(columns=rename_map, inplace=True)

    return df


def clean_sim_file(filepath):
    """Load, clean, and add metadata to a simulation file."""
    fname = os.path.basename(filepath)
    temp_str, scenario, bus_type = parse_filename(fname)

    df = load_sim_file(filepath)

    # convert all kept columns to numeric
    for col in df.columns:
        if col in KEEP_COLS:
            df[col] = pd.to_numeric(df[col], errors='coerce')

    # select only the columns we want
    cols_available = [c for c in KEEP_COLS if c in df.columns]
    df = df[cols_available].copy()

    # replace sentinel 65535 with NaN
    df.replace(65535, np.nan, inplace=True)

    # interpolate small gaps
    df.interpolate(method='linear', limit=10, inplace=True)

    # add metadata columns
    sim_id = fname.replace('.csv', '')
    df.insert(0, 'sim_id', sim_id)
    df['temperature'] = TEMP_MAP.get(temp_str, np.nan)
    df['scenario'] = scenario
    df['bus_type'] = bus_type

    return df


def main():
    files = sorted(glob.glob(os.path.join(RAW_DIR, '*.csv')))
    print(f"Loading {len(files)} simulation files...")

    dfs = []
    for f in files:
        df = clean_sim_file(f)
        dfs.append(df)
        print(f"  {os.path.basename(f)}: {len(df)} rows")

    # merge all
    merged = pd.concat(dfs, ignore_index=True)
    print(f"\nMerged: {merged.shape[0]} rows x {merged.shape[1]} cols")

    # drop rows where critical columns are NaN
    critical = ['Time [s]', 'Pack Voltage [V]', 'Battery Current [A]', 'SOC [%]']
    before = len(merged)
    merged.dropna(subset=critical, inplace=True)
    dropped = before - len(merged)
    if dropped > 0:
        print(f"Dropped {dropped} rows with missing critical values")

    # rename columns to snake_case
    merged.rename(columns=COL_RENAME, inplace=True)

    print(f"\nFinal dataset: {merged.shape[0]} rows x {merged.shape[1]} cols")
    print(f"Missing values remaining: {merged.isnull().sum().sum()}")
    print(f"Columns: {list(merged.columns)}")

    # save
    os.makedirs(OUT_DIR, exist_ok=True)
    out_path = os.path.join(OUT_DIR, 'simulation_clean.csv')
    merged.to_csv(out_path, index=False)
    print(f"\nSaved to {out_path}")


if __name__ == '__main__':
    main()