# Data Cleaning Report

## 1. Measurement Data Cleaning

**Source**: 70 raw CSV files (32 TripA + 38 TripB)
**Out**: 1 file `measurement_clean.csv`

### Steps Applied

1. **Column name cleanup**
   - Stripped leading/trailing whitespace from all column names
   - Fixed bracket typo: `max. SoC [%)` to `max. SoC [%]`

2. **Column selection**
   - Kept 23 shared columns relevant to BMS analysis (time, velocity, elevation, throttle, motor torque, acceleration, regen braking, battery voltage/current/temperature, SoC, heating/cooling signals, ambient temperature, cabin/coolant sensors)
   - Dropped constant config columns (`min. SoC`, `max. SoC`, `Heater Signal`, `Requested Coolant Temperature`, `Requested Heating Power`)
   - Dropped TripB-only cabin sensor columns (defrost, footwell, head vent temperatures)

3. **Spike removal**
   - Detected and replaced isolated sensor glitches with NaN using per-signal thresholds:
     - SoC: > 3 % jump between consecutive rows
     - Battery Voltage: > 30 V jump
     - Battery / Ambient Temperature: > 5 C jump

4. **Missing value handling**
   - Linear interpolation for small gaps (≤ 10 consecutive NaN rows)
   - Backward fill for edge gaps (≤ 5 rows)
   - Heater-related columns (`Heating Power LIN`, `Heater Voltage/Current`, `Coolant Temperature`): remaining NaN filled with 0 (heater off)
   - Velocity: remaining NaN filled with 0 (vehicle stopped)
   - Dropped rows where critical columns (`Time`, `Battery Voltage`, `Battery Current`, `SoC`) are still NaN after interpolation
   - Remaining NaN in non-critical numeric columns: forward fill then backward fill

5. **Trip identification**
   - Added `trip_id` column with source filename (e.g., `TripA01`, `TripB15`)

6. **Column renaming**
   - All columns renamed to snake_case (e.g., `Battery Voltage [V]` to `battery_voltage_v`)

**Output**: `data/cleaned/measurement/measurement_clean.csv` - 24 columns

---

## 2. Simulation Data Cleaning

**Source**: 24 raw CSV files (12 CAN + 12 LIN, 3 temperatures x 4 scenarios)
**Out**: 1 file `simulation_clean.csv`

### Steps Applied

1. **Header fix for Neg10_Heating_CAN.csv**
   - This file has a corrupted/shifted header (3 header rows instead of 2)
   - Loaded with `skiprows=[0, 1]` to skip the extra row and category row

2. **Duplicate column disambiguation**
   - `Power [kW]` (Battery) to `Battery Power [kW]`
   - `Power [kW].1` (Consumption) to `Consumption Power [kW]`
   - `Energy [kWh]` to `Consumption Energy [kWh]`

3. **Column selection**
   - Kept 21 analysis-relevant columns (time, ambient temp, speed, acceleration, traction, drive torque, EM power, pack voltage, battery current/power, SOC, SOH, cell temperature, consumption, cabin temperature, heating power, auxiliaries)
   - Dropped constant simulation config columns (`Slope`, `Wind Speed`, `Mass Jred`, `Seat Heating`, `Rest Lights`, `Window Lifters`, `Infotainment`, `Wipers`, `Blower`, `CU Sensors`)

4. **Numeric conversion**
   - All kept columns coerced to numeric (`errors='coerce'`)

5. **Sentinel value removal**
   - Replaced 65535 values with NaN (489 rows per file in `[kWh/100km]` - division-by-zero placeholder at trip start)

6. **Missing value handling**
   - Linear interpolation for small gaps (≤ 10 consecutive NaN rows)
   - Dropped rows where critical columns (`Time`, `Pack Voltage`, `Battery Current`, `SOC`) are still NaN

7. **Metadata columns added**
   - `sim_id`: source filename (e.g., `0_Charging_CAN`)
   - `temperature`: numeric value extracted from filename (-10, 0, 10)
   - `scenario`: driving scenario (`Standard`, `Charging`, `Heating`, `Mixed`)
   - `bus_type`: heater bus model (`CAN` or `LIN`)

8. **Column renaming**
   - All columns renamed to snake_case (e.g., `Pack Voltage [V]` to `pack_voltage_v`)

**Output**: `data/cleaned/simulation/simulation_clean.csv` - 25 columns
