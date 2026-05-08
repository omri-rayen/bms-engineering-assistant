# Requirements

This file mirrors `validator/requirements/requirements.json` for human reading.
The JSON is the authoritative source consumed by the test suites.

## Plant (MIL)

| ID                 | Statement                                                        |
| ------------------ | ---------------------------------------------------------------- |
| REQ-LL-PLT-V-01    | RMSE(V_pack) vs measurement ≤ 4.0 V over the trip set            |
| REQ-LL-PLT-SOC-01  | RMSE(SoC_pack × 100) ≤ 1.0 % over the trip set                   |
| REQ-LL-PLT-T-01    | RMSE(T_pack) ≤ 1.0 °C over the trip set                          |

## BMS (MIL)

| ID                  | Statement                                                                                  |
| ------------------- | ------------------------------------------------------------------------------------------ |
| REQ-LL-BMS-VMON-01  | OV warn/derate/shut after `bms.N_debounce_*` at the per-stage threshold                    |
| REQ-LL-BMS-VMON-02  | UV ladder, symmetric                                                                       |
| REQ-LL-BMS-TMON-01  | OT ladder on T_sensors_4(2)                                                                |
| REQ-LL-BMS-TMON-02  | UT ladder on T_sensors_4(1)                                                                |
| REQ-LL-BMS-IMON-01  | OC charge ladder via I_pack                                                                |
| REQ-LL-BMS-IMON-02  | OC discharge ladder                                                                        |
| REQ-LL-BMS-FSM-01   | Severity FSM escalates Nominal→Warn→Derate→Shut, recovers Warn→Nominal, latches at Shut    |
| REQ-LL-BMS-SOC-01   | EKF SoC error < 3 % at t=60 s with 2 % init offset, constant 30 A                          |
| REQ-LL-BMS-SOH-01   | SoH ∈ [0.5, 1.0] and non-increasing within a trip                                          |
| REQ-LL-BMS-BAL-01   | enable_bal gates I_bal_12; highest-V cell drains at `bms.bal_I_nom`                        |
| REQ-LL-BMS-BAL-02   | End-of-trip cell-voltage spread ≤ spread at 5 % of trip duration                           |
| REQ-LL-BMS-THM-01   | Heater on cold, chiller on hot, both off in band, mutual exclusion                         |
| REQ-LL-BMS-PWR-01   | P_limit derate ≥ 20 % drop, both 0 W under shutdown, always non-negative                   |
| REQ-LL-BMS-WDG-01   | Watchdog asserts severity ≥ Warn after `bms.N_watchdog_timeout` of frozen slave flags      |
| REQ-LL-BMS-HWP-01   | HW protection asserts shutdown_cmd within 1 step (no debounce) on \|I\| ≥ I_SC_thresh     |

## Predictor (MIL)

| ID                  | Statement                                                                          |
| ------------------- | ---------------------------------------------------------------------------------- |
| REQ-LL-PRD-LT-01    | alarm_3(OT) leads BMS warn by ≥ 30 s under worst-case OT injection                 |
| REQ-LL-PRD-LT-02    | alarm_3(OV) leads BMS warn by ≥ 10 s under worst-case OV injection                 |
| REQ-LL-PRD-LT-03    | alarm_3(UV) leads BMS warn by ≥ 10 s under worst-case UV injection                 |
| REQ-LL-PRD-DR-01    | Per-class detection rate ≥ 80 % across the injected-fault test set                 |
| REQ-LL-PRD-FAR-01   | False-alarm time fraction on nominal trips ≤ 10 %                                  |

## SIL

| ID                 | Statement                                                                |
| ------------------ | ------------------------------------------------------------------------ |
| REQ-LL-SIL-EQ-01   | Generated C of bms_master matches MIL on TripA02 (1 % rel or 1e-4 abs)   |

## PIL

| ID                  | Statement                                                                       |
| ------------------- | ------------------------------------------------------------------------------- |
| REQ-LL-RT-WCET-01   | bms_master mean PIL per-step latency on STM32 H7A3 (280 MHz) < req.RT_WCET_max_ms (host wall-clock incl. USART3 + DMA1 round-trip; HAL tick on TIM7, NVIC priorities prevent the PIL serial from being preempted) |
| REQ-LL-PIL-PRD-01   | LSTM `prob_3` on the target matches MIL reference within 1e-3 over a 30 s run   |
