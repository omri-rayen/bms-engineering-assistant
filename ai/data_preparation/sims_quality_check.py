"""
Quality check for simulation dataset (CAN & LIN files at different temperatures).
Inspects structure, missing values, duplicates, anomalies, and data consistency.
"""

import pandas as pd
import os
import glob

DATA_DIR = os.path.join(os.path.dirname(__file__), '..', '..', 'data', 'raw', 'simulation')

# expected physical ranges for simulation data
EXPECTED_RANGES = {
    'Speed [m/s]':                (-5, 80),
    'Pack Voltage [V]':           (250, 450),
    'Battery Current [A]':        (-500, 500),
    'SOC [%]':                    (0, 100),
    'Ageing SOH [-]':             (0, 1.1),
    'Mean Cell Temperature [C]':  (-30, 60),
    'Ambient Temperature [C]':    (-30, 50),
    'Heating Power [kW]':         (-1, 20),
}

# temperature conditions encoded in filenames
TEMP_MAP = {
    'Neg10': -10,
    'Pos10': 10,
    '0': 0,
}


def parse_filename(fname):
    """Extract temperature, scenario, and bus type from filename ex: 'Neg10_Charging_CAN.csv'."""
    base = fname.replace('.csv', '')
    parts = base.split('_')
    bus_type = parts[-1]  # CAN or LIN
    temp_str = parts[0]   # temperature
    scenario = '_'.join(parts[1:-1])
    return temp_str, scenario, bus_type


def load_sim(filepath):
    """Load a simulation CSV (skip the category header row, use row 1 as columns)."""
    df = pd.read_csv(filepath, sep=';', encoding='latin-1', header=1, low_memory=False)
    return df


def check_file(filepath):
    """Run quality checks on a single simulation file."""
    fname = os.path.basename(filepath)
    temp_str, scenario, bus_type = parse_filename(fname)
    df = load_sim(filepath)

    findings = {
        'file': fname,
        'temp': temp_str,
        'scenario': scenario,
        'bus': bus_type,
        'rows': len(df),
        'cols': len(df.columns),
        'issues': []
    }

    # --- missing values ---
    missing = df.isnull().sum()
    missing = missing[missing > 0]
    if len(missing) > 0:
        for col, count in missing.items():
            pct = 100 * count / len(df)
            findings['issues'].append(f"Missing values in '{col}': {count} ({pct:.1f}%)")

    # --- column name issues ---
    for col in df.columns:
        if col.strip() != col:
            findings['issues'].append(f"Column '{col}' has leading/trailing whitespace")

    # duplicate column names
    stripped_cols = df.columns.str.strip()
    dup_cols = stripped_cols[stripped_cols.duplicated()]
    if not dup_cols.empty:
        findings['issues'].append(f"Duplicate column names: {', '.join(dup_cols)}")

    # --- time checks ---
    # duplicate timestamps
    if 'Time [s]' in df.columns:
        dup_times = df['Time [s]'].duplicated().sum()
        if dup_times > 0:
            findings['issues'].append(f"Duplicate timestamps: {dup_times}")

        # check time monotonicity
        diffs = df['Time [s]'].diff().dropna()
        non_mono = (diffs <= 0).sum()
        if non_mono > 0:
            findings['issues'].append(f"Non-monotonic time steps: {non_mono}")

        # check time step regularity
        expected_dt = 0.1
        tolerance = 0.005
        dt_vals = diffs[diffs > 0]
        if len(dt_vals) > 0:
            irregular = ((dt_vals - expected_dt).abs() > tolerance).sum()
            if irregular > 0:
                findings['issues'].append(f"Irregular time steps: {irregular} (expected dt = {expected_dt}s)")

    # --- out-of-range values ---
    for col, (lo, hi) in EXPECTED_RANGES.items():
        if col not in df.columns:
            continue
        series = pd.to_numeric(df[col], errors='coerce')
        below = (series < lo).sum()
        above = (series > hi).sum()
        if below > 0:
            findings['issues'].append(f"'{col}' below {lo}: {below} rows (min={series.min():.2f})")
        if above > 0:
            findings['issues'].append(f"'{col}' above {hi}: {above} rows (max={series.max():.2f})")

    # --- check ambient temperature matches filename ---
    if 'Ambient Temperature [C]' in df.columns and temp_str in TEMP_MAP:
        expected_temp = TEMP_MAP[temp_str]
        actual_temps = pd.to_numeric(df['Ambient Temperature [C]'], errors='coerce').dropna()
        if len(actual_temps) > 0:
            mean_temp = actual_temps.mean()
            if abs(mean_temp - expected_temp) > 5:
                findings['issues'].append(
                    f"Ambient temp mismatch: expected temp {expected_temp}°C, mean temp {mean_temp:.1f}°C"
                )

    # --- check for sentinel/placeholder values (65535 is common) ---
    for col in df.columns:
        series = pd.to_numeric(df[col], errors='coerce')
        n_sentinel = (series == 65535).sum()
        if n_sentinel > 0:
            findings['issues'].append(f"Sentinel value 65535 in '{col}': {n_sentinel} rows")

    # --- constant columns ---
    for col in df.columns:
        series = pd.to_numeric(df[col], errors='coerce')
        if series.notna().sum() > 0 and series.nunique() <= 1:
            findings['issues'].append(f"Column '{col}' is constant (value={series.iloc[0]})")

    # --- duplicate rows ---
    dup_rows = df.duplicated().sum()
    if dup_rows > 0:
        findings['issues'].append(f"Fully duplicate rows: {dup_rows}")

    if not findings['issues']:
        findings['issues'].append("No issues found")

    return findings


def main():
    files = sorted(glob.glob(os.path.join(DATA_DIR, '*.csv')))
    print(f"Found {len(files)} simulation files\n")

    can_files = [f for f in files if '_CAN.csv' in f]
    lin_files = [f for f in files if '_LIN.csv' in f]
    print(f"  CAN files: {len(can_files)}")
    print(f"  LIN files: {len(lin_files)}")

    # check column consistency
    print("\n--- Column consistency ---")
    ref_cols = None
    for f in files:
        df = load_sim(f)
        cols = list(df.columns)
        if ref_cols is None:
            ref_cols = cols
        elif cols != ref_cols:
            print(f"  WARNING: {os.path.basename(f)} has different columns")
    if ref_cols:
        print(f"  All files have {len(ref_cols)} columns (consistent)" if all(
            list(load_sim(f).columns) == ref_cols for f in files
        ) else "")

    # run quality checks
    print("\n--- Per-file quality checks ---")
    all_findings = []
    for f in files:
        findings = check_file(f)
        all_findings.append(findings)
        has_problems = findings['issues'] != ["No issues found"]
        if has_problems:
            print(f"\n  {findings['file']} ({findings['rows']} rows):")
            for issue in findings['issues']:
                print(f"    - {issue}")

    # summary
    clean_count = sum(1 for f in all_findings if f['issues'] == ["No issues found"])
    problem_count = len(all_findings) - clean_count
    print(f"\n--- Summary ---")
    print(f"  Total files: {len(all_findings)}")
    print(f"  Clean files: {clean_count}")
    print(f"  Files with issues: {problem_count}")

    # overall stats for key columns
    print("\n--- Overall statistics (all simulation files combined) ---")
    all_dfs = []
    for f in files:
        df = load_sim(f)
        df['_source'] = os.path.basename(f)
        all_dfs.append(df)
    combined = pd.concat(all_dfs, ignore_index=True)

    key_cols = ['Speed [m/s]', 'Pack Voltage [V]', 'Battery Current [A]',
                'SOC [%]', 'Mean Cell Temperature [C]', 'Ambient Temperature [C]']
    for col in key_cols:
        if col in combined.columns:
            vals = pd.to_numeric(combined[col], errors='coerce').dropna()
            print(f"  {col}: min={vals.min():.2f}, max={vals.max():.2f}, mean={vals.mean():.2f}")


if __name__ == '__main__':
    main()