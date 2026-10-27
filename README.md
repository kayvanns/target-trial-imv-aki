# Invasive ventilation and AKI in non-pneumonia sepsis: target trial emulation (eICU-CRD)

**Question.** Among adults with new-onset non-pneumonia sepsis, does semi-elective invasive mechanical ventilation within 24 h of ICU admission increase the 7-day risk of moderate-to-severe AKI (KDIGO stage 2–3 or RRT), compared with no intubation within 24 h?

**Data.** eICU Collaborative Research Database v2.0 on BigQuery (`physionet-data.eicu_crd`). Project tables in `evocative-ethos-471602-r3.base`.

**Design.** Target trial emulation, time zero = ICU admission, clone-censor-weighting. See [`docs/target_trial_spec.md`](docs/target_trial_spec.md).

## Repository layout

```
sql/pipeline/   builds the tables, run in order (01 -> 04)
sql/checks/     read-only queries behind every decision; each "-- @query:" block
                saves its result to results/<name>.csv
results/        aggregated outputs only (counts) - never patient-level data
docs/           decisions log, cohort flow, data dictionary, protocol, references,
                VS Code / BigQuery setup
scripts/        run_sql.py (runner) and run_all.sh
```

## Pipeline

| Step | File | Builds | Expected rows |
| --- | --- | --- | --- |
| 01 | `01_sepsis_cohort.sql` | `eicu_sepsis_stays`, `eicu_sepsis_no_pneumonia` | 18,174 stays → 14,810 patients |
| 02 | `02_cohort_ventilation.sql` | `eicu_cohort` (adults, hospital quality, ventilation) | 14,799 (primary: 11,994) |
| 03 | `03_kidney_baseline.sql` | `eicu_kidney_v1`, `eicu_eligible_v1` | 11,994 / 4,690 |
| 04 | `04_exclusions.sql` | `eicu_tte_cohort` (`eligible_a`, `eligible_b`) | 11,994 (A: 3,086, B: 3,973) |
| 05 | *next:* analysis table (treatment timing, outcome, follow-up) | | |
| 06 | *next:* confounders at admission | | |

## Checks

| File | What it shows | Decisions |
| --- | --- | --- |
| `01_one_stay_per_patient` | stays, readmissions, same-year ambiguity | D03 |
| `02_age` | age format and exclusions | D04 |
| `03_ventilation_treatment` | treatment strings, their classes, timing, hospital usage, insertion vs ventilation entry | D05, D06, D08 |
| `04_ventilation_respcharting` | ventilator-setting labels, agreement with treatment, final ventilation definition | D07–D10 |
| `05_creatinine_urine` | creatinine labs, timing, hospital coverage; urine labels and charting frequency | D13–D16 |
| `06_kidney_history_baseline` | ESRD/CKD/transplant sources, RRT timing, baseline options, kidney flow | D16, D20–D26 |
| `07_exclusions` | DNR / chronic lung / tracheostomy entries; full cohort flow (Option A and B) | D26–D31 |
| `08_feasibility` | intubation counts, outcome events by design option, creatinine measurement by day | D12, D17–D19, D26 |

## Getting started

1. Set up BigQuery in VS Code: [`docs/setup_vscode_bigquery.md`](docs/setup_vscode_bigquery.md)
2. Test the connection: `python scripts/run_sql.py --test`
3. Build the tables: `bash scripts/run_all.sh pipeline`
4. **Check the counts** against the "Expected rows" column above and [`docs/cohort_flow.md`](docs/cohort_flow.md). Pipeline 01 rebuilds the starting tables from raw eICU data in one script, so any difference from 18,174 / 14,810 shows up here first.
5. Refresh all results: `bash scripts/run_all.sh checks`

## Where to look

- **Why is a rule the way it is?** → [`docs/decisions.md`](docs/decisions.md) (D01–D33), referenced in every SQL header
- **Current numbers** → [`docs/cohort_flow.md`](docs/cohort_flow.md)
- **What a column means** → [`docs/data_dictionary.md`](docs/data_dictionary.md)
- **Open questions for the PI** → decisions with status *Proposed* or *Open* (D12, D17, D18, D19, D26, D31)

## Data use

eICU is credentialed PhysioNet data. Never commit patient-level data (tables, row-level exports). Only aggregated counts go in `results/`, and the runner refuses to save results with more than 500 rows. Keep the repository private. Check small-cell rules before sharing results publicly.
