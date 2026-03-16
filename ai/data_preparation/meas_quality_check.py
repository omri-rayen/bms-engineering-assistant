"""
Quality check for measurement dataset (TripA and TripB files).
Inspects structure, missing values, duplicates, outliers, and data consistency.
"""

import pandas as pd
import os
import glob

DATA_DIR = os.path.join(os.path.dirname(__file__), '..', '..', 'data', 'raw', 'measurement')

# essential signals
KEY_COLS = [
    'Time [s]', 'Velocity [km/h]', 'Battery Voltage [V]', 'Battery Current [A]',
    'Battery Temperature [°C]', 'SoC [%]', 'Ambient Temperature [°C]',
    'Heating Power CAN [kW]', 'Heating Power LIN [W]'
]

# expected physical ranges (reasonable bounds for a 96s1p EV battery pack)
EXPECTED_RANGES = {
    'Velocity [km/h]':           (-5, 200),
    'Battery Voltage [V]':       (250, 450),
    'Battery Current [A]':       (-500, 500),
    'Battery Temperature [°C]':  (-30, 60),
    'SoC [%]':                   (10, 90),
    'Ambient Temperature [°C]':  (-30, 50),
}


def load_trip(filepath):
    """Load a single trip CSV."""
    return pd.read_csv(filepath, sep=';', encoding='latin-1')


def check_file(filepath):
    """Run quality checks on a single trip file. Returns a dict of findings."""
    fname = os.path.basename(filepath)
    df = load_trip(filepath)
    
    findings = {
        'file': fname,
        'rows': len(df),
        'cols': len(df.columns),
        'issues': []
    }

    # --- column name issues ---
    for col in df.columns:
        if col.strip() != col:
            findings['issues'].append(f"Column '{col}' has leading/trailing whitespace")

    # duplicate column names
    stripped_cols = df.columns.str.strip()
    dup_cols = stripped_cols[stripped_cols.duplicated()]
    if not dup_cols.empty:
        findings['issues'].append(f"Duplicate column names: {', '.join(dup_cols)}")

    # known typo: "max. SoC [%)" should be "max. SoC [%]"
    if 'max. SoC [%)' in df.columns:
        findings['issues'].append("Column 'max. SoC [%)' has bracket typo (should be ']')")

    # --- missing values ---
    missing = df.isnull().sum()
    missing = missing[missing > 0]
    if len(missing) > 0:
        for col, count in missing.items():
            pct = 100 * count / len(df)
            findings['issues'].append(f"Missing values in '{col}': {count} ({pct:.1f}%)")

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
        below = (df[col] < lo).sum()
        above = (df[col] > hi).sum()
        if below > 0:
            findings['issues'].append(f"'{col}' below {lo}: {below} rows (min={df[col].min():.2f})")
        if above > 0:
            findings['issues'].append(f"'{col}' above {hi}: {above} rows (max={df[col].max():.2f})")

    # --- constant columns ---
    for col in df.columns:
        if df[col].dtype in ['float64', 'int64'] and df[col].nunique() <= 1:
            findings['issues'].append(f"Column '{col}' is constant (value={df[col].iloc[0]})")

    # --- duplicate rows ---
    dup_rows = df.duplicated().sum()
    if dup_rows > 0:
        findings['issues'].append(f"Fully duplicate rows: {dup_rows}")

    if not findings['issues']:
        findings['issues'].append("No issues found")

    return findings


def main():
    files = sorted(glob.glob(os.path.join(DATA_DIR, 'Trip*.csv')))
    print(f"Found {len(files)} measurement files\n")

    tripA_files = [f for f in files if 'TripA' in os.path.basename(f)]
    tripB_files = [f for f in files if 'TripB' in os.path.basename(f)]
    print(f"  TripA: {len(tripA_files)} files")
    print(f"  TripB: {len(tripB_files)} files")

    # check column consistency within each group
    print("\n--- Column consistency ---")
    colsA = set()
    colsB = set()
    for f in tripA_files:
        df = load_trip(f)
        if not colsA:
            colsA = set(df.columns)
        elif set(df.columns) != colsA:
            print(f"  WARNING: {os.path.basename(f)} has different columns than TripA01")
    for f in tripB_files:
        df = load_trip(f)
        if not colsB:
            colsB = set(df.columns)
        elif set(df.columns) != colsB:
            print(f"  WARNING: {os.path.basename(f)} has different columns than TripB01")

    print(f"  TripA columns: {len(colsA)}")
    print(f"  TripB columns: {len(colsB)}")
    extra_in_B = colsB - colsA
    if extra_in_B:
        print(f"  Extra columns in TripB (not in TripA): {sorted(extra_in_B)}")

    # run quality checks on every file
    print("\n--- Per-file quality checks ---")
    all_findings = []
    for f in files:
        findings = check_file(f)
        all_findings.append(findings)
        has_problems = findings['issues'] != ["No issues found"]
        if has_problems:
            print(f"\n  {findings['file']} ({findings['rows']} rows, {findings['cols']} cols):")
            for issue in findings['issues']:
                print(f"    - {issue}")

    # summary
    clean_count = sum(1 for f in all_findings if f['issues'] == ["No issues found"])
    problem_count = len(all_findings) - clean_count
    print(f"\n--- Summary ---")
    print(f"  Total files: {len(all_findings)}")
    print(f"  Clean files: {clean_count}")
    print(f"  Files with issues: {problem_count}")

    # overall stats across all files
    print("\n--- Overall statistics (all trips combined) ---")
    all_dfs = []
    for f in files:
        df = load_trip(f)
        df['_source'] = os.path.basename(f)
        all_dfs.append(df)

    # separate stats for A and B (since they have different columns)
    for prefix, group_files in [('TripA', tripA_files), ('TripB', tripB_files)]:
        dfs = [load_trip(f) for f in group_files]
        combined = pd.concat(dfs, ignore_index=True)
        print(f"\n  {prefix} ({len(dfs)} files, {len(combined)} total rows):")
        for col in KEY_COLS:
            if col in combined.columns:
                vals = combined[col].dropna()
                print(f"    {col}: min={vals.min():.2f}, max={vals.max():.2f}, mean={vals.mean():.2f}, nulls={combined[col].isnull().sum()}")


if __name__ == '__main__':
    main()