# Data Quality Report

## 1. Measurement Data

### Overview

| Group | Files | Total Rows | Columns |
|-------|-------|------------|---------|
| TripA | 32 | 467,701 | 22-28 |
| TripB | 38 | 627,092 | 48 |
| **Total** | **70** | **1,094,793** | 24 |

- Format: CSV, semicolon-separated, latin-1 encoding
- Time step: 0.1 s
- TripA: warm weather (ambient 14-33.5 C), TripB: cold weather (ambient -3.5-14 C)
- TripB has ~20 extra columns vs TripA (cabin/thermal sensors)

### Issues

| Issue | Scope | Details |
|-------|-------|---------|
| Column whitespace | All files | `Regenerative Braking Signal ` has trailing space; TripB also has `Temperature Vent right [°C] ` |
| Bracket typo | All files | `max. SoC [%)` should be `max. SoC [%]` |
| Column inconsistency | TripA | Files vary between 22-28 columns (TripA01 has 28, most have 23); TripA11 has an extra `Unnamed: 23` column |
| Duplicate column name | TripB | `Temperature Vent right [°C]` appears twice (with/without trailing space) |
| Missing values | TripB | TripB09: 36.6 % missing SoC; TripB07: 18.2 % missing across TripB-specific columns; TripB05/B06: `Coolant Volume Flow` 100 % missing; most others < 1 % |
| Missing values | TripA | `Battery Temperature` and `Ambient Temperature` missing in TripA01 (10,090 nulls); `Heating Power LIN` missing in 310,587 rows |
| Constant columns | All files | `min. SoC [%]`, `max. SoC [%)`, `Heater Signal`, `Requested Coolant Temperature [°C]` - reflect vehicle config, not bugs |
| Encoding artifacts | TripA01 | Some column names show `ï¿½` instead of `°` (encoding mismatch) |

### No Issues Found

- No duplicate timestamps or rows in any file
- Time is monotonically increasing everywhere
- Regular 0.1 s time steps throughout
- All core signals within expected physical bounds

### Key Statistics

| Signal | TripA (min / max / mean) | TripB (min / max / mean) |
|--------|--------------------------|--------------------------|
| Velocity [km/h] | 0 / 151.6 / 43.3 | 0 / 152.3 / 45.8 |
| Battery Voltage [V] | 349.4 / 394.8 / 382.9 | 301.8 / 394.2 / 371.6 |
| Battery Current [A] | -395.2 / 143.5 / -15.4 | -404.4 / 144.5 / -18.7 |
| Battery Temp [C] | 16 / 32 / 22.4 | -1 / 22 / 10.2 |
| SoC [%] | 34.2 / 88.5 / 72.9 | 0.0 / 86.1 / 59.0 |
| Ambient Temp [C] | 14.0 / 33.5 / 23.0 | -3.5 / 14.0 / 5.5 |

---

## 2. Simulation Data

### Overview

| Metric | Value |
|--------|-------|
| Total files | 24 (12 CAN + 12 LIN) |
| Rows per file | 38,220 (exception: Neg10_Heating_CAN has 38,221) |
| Columns | 43 |
| Temperature conditions | -10 C, 0 C, +10 C |
| Scenarios | Standard, Charging, Heating, Mixed |
| Total rows | 917,281 |

- Format: CSV, semicolon-separated, latin-1 encoding, 2-row header (row 0 = category, row 1 = column names)
- Time step: 0.1 s
- CAN and LIN files share the same column structure

### Issues

| Issue | Scope | Details |
|-------|-------|---------|
| Corrupted header | Neg10_Heating_CAN.csv | Column names appear as `Unnamed: X`; has 1 extra row (38,221 vs 38,220) |
| Sentinel values | All files | `[kWh/100km]` contains 489 rows with value 65535 + 1 NaN per file |
| Duplicate column name | All files | Two columns named `Power [kW]` (Battery vs Consumption) |
| Constant columns | All files | `Slope [rad]`, `Wind Speed [m/s]`, `Mass Jred [kg]`, `Seat Heating [W]`, `Rest Lights [W]`, `Window Lifters [W]`, `Infotainment [W]`, `Wipers [W]`, `Blower [W]`, `CU Sensors [W]` - simulation config parameters |
| Low voltage at -10 C | Neg10 files | Pack Voltage drops to ~220 V (expected: high internal resistance at -10 C) |

### No Issues Found

- No duplicate timestamps or rows
- Monotonic, regular 0.1 s time steps in all files
- Ambient temperature matches filename condition in all files

### Key Statistics

| Signal | Min | Max | Mean |
|--------|-----|-----|------|
| Speed [m/s] | 0.00 | 38.48 | 15.91 |
| Pack Voltage [V] | 219.22 | 407.05 | 361.15 |
| Battery Current [A] | -94.31 | 433.43 | 32.00 |
| SOC [%] | 18.50 | 86.80 | 59.52 |
| Mean Cell Temp [C] | -10.00 | 14.21 | 3.60 |
| Ambient Temp [C] | -10.00 | 10.00 | 0.43 |
