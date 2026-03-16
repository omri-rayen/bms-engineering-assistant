# EDA Report

## 1. Dataset Overview

| | Measurement | Simulation |
|---|---|---|
| Rows | 1,064,082 | 917,280 |
| Columns | 24 | 25 |
| Trips / Runs | 70 (32 TripA + 38 TripB) | 24 (3 temps × 4 scenarios × 2 bus) |
| NaN remaining | 0 | 0 |

**Column naming**: All columns renamed to snake_case (e.g. `time_s`, `battery_current_a`, `soc_pct`). Identifiers (`trip_id`, `sim_id`) placed first.

## 2. Signal Ranges

### Measurement

| Signal | Min | Max | Unit |
|---|---|---|---|
| Voltage | 301.8 | 394.8 | V |
| Current | -404.4 | 144.5 | A |
| SoC | 15.4 | 88.5 | % |
| Battery Temp | -1.0 | 32.0 | °C |
| Ambient Temp | -3.5 | 33.5 | °C |

### Simulation

| Signal | Min | Max | Unit |
|---|---|---|---|
| Pack Voltage | 219.2 | 407.1 | V |
| Current | -94.3 | 433.4 | A |
| SOC | 18.5 | 86.8 | % |
| Cell Temp | -10.0 | 14.2 | °C |

## 3. Key Findings

### 3.1 TripA vs TripB Differences
- **TripA** (warm weather, 14-33°C ambient): higher battery temperatures, lower heating power usage, smoother voltage profiles.
- **TripB** (cold weather, -3.5-14°C ambient): higher current draw, more voltage variability, significant heating power usage across all trips.

### 3.2 Correlation Analysis
- **Strong positive**: Voltage - SoC (0.80), Motor Torque - Acceleration (0.96).
- **Strong negative**: Current - Torque (-0.75), Current - Acceleration (-0.69).
- **Moderate**: Current - Voltage (0.54), Temperature - Voltage (0.44).
- Velocity has weak correlation with most signals (battery operates across all speeds).

### 3.3 SoC Range Analysis
- Most trips operate in the 60-85% SoC range.
- Highest SoC consumption: TripB14 (50+%), TripB10, TripA07, TripB01 (long trips with deep discharge).
- TripB04 includes a charging session (SoC rise from ~30% to ~70%).
- Negative delta SoC in TripB04: trip ended at higher SoC than it started (charging occurred mid-trip).

### 3.4 Driving Phases (TripB04 example)
| Phase | Duration [s] | Share |
|---|---|---|
| Charging | 1419 | 48% |
| Cruise | 743 | 25% |
| Acceleration | 294 | 10% |
| Rest | 197 | 7% |
| Regen Braking | 182 | 6% |
| Heating | 120 | 4% |

### 3.5 Sensor Noise
- Max SoC jump per timestep: 0.30% (TripA06) - within normal bounds after spike removal.
- Max voltage jump per timestep: 17.2 V (TripB02) - large but within physical limits during rapid load changes.
- TripB trips generally show higher current noise (σ=3-5 A/step) vs TripA (σ=2-3 A/step) due to cold-weather conditions.
- Outlier spike in TripB14 (SoC: 34% to 0%) was detected and removed during cleaning.

### 3.6 Simulation Insights
- At -10°C: SOC depletes much faster (drops to ~20%) compared to 0°C (~35%) and 10°C (~65%).
- Cell temperature rises from initial condition during operation (self-heating effect).
- Heating scenario uses consistently high heating power; Mixed scenario has the most variable heating demand.
- Standard and Charging scenarios show similar SOC profiles; Heating scenario slightly lower due to auxiliary power draw.

### 3.7 Real vs Simulation Comparison
- Current: measurement has more negative current values (discharge); simulation has positive-skewed current (different sign convention for some scenarios).
- SoC: measurement concentrates in 60-85%; simulation has wider spread (18-87%) covering more extreme conditions.
- Voltage: measurement clusters at 360-395V; simulation spans wider range down to ~220V at -10°C deep discharge.
- Real trips have more variability (urban driving, stops), simulations follow smoother drive cycles.

## 4. Data Quality After Cleaning

- **Spikes removed**: 1 spike in TripB14 (SoC jumped from 34% to 0% at end of trip).
- **Sentinel values**: 65535 values in simulation `[kWh/100km]` column replaced and interpolated.
- **Missing values**: All NaN resolved via interpolation, zero-fill (heater columns), or row dropping (critical columns).
- **Column consistency**: All files harmonized to common column sets with snake_case naming.
