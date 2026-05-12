"""BMS analyzer — small symbolic expert system.

Reads the static facts collected by `ana.collect` (MATLAB) plus the
COV / MIL / SIL / PIL JSON reports written by the validator, applies a
forward-chaining rule base loaded from YAML, and writes an interpretation
report (analyzer/reports/ANALYSIS_<ts>.json).

Run: `python -m analyzer` from anywhere; sensible defaults look in the
canonical repo layout.
"""

__version__ = "0.1.0"
