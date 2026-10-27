# Results

Aggregated outputs only (counts and summary statistics). **No patient-level rows ever go in this folder** (PhysioNet data use agreement).

Each file is named after the `-- @query:` block in `sql/checks/` that produces it. Running `python scripts/run_sql.py sql/checks/<file>.sql` overwrites the matching CSVs with fresh results.

## Where the current files came from

The files below are the outputs of the original exploratory runs, Oct 12–27, 2026. Some were run before the final rule fixes, so a fresh run can differ slightly. Those differences are listed under Notes.

| File | Run | Notes |
| --- | --- | --- |
| 01a_one_stay_per_patient | Oct 12 | Transcribed from screenshot |
| 02a_age | Oct 12 | Transcribed |
| 03a_vent_treatment_strings | Oct 12 | Top 43 of 88 strings only (all others < 20 patients) |
| 03b_vent_string_classification | — | Not saved; run `checks/03` to generate |
| 03c_imv_timing_treatment_only | Oct 12 | |
| 03d_hospital_treatment_usage | Oct 12 | |
| 03e_insertion_vs_mech_vent_entry | Oct 12 | |
| 04a_respcharting_labels | Oct 12 | Labels with >= 100 patients |
| 04b_vent_settings_vs_treatment | Oct 12 | |
| 04c_combined_vent_definition | Oct 12 | |
| 05a–05e2 | Oct 13 | 05b is the corrected version (daily coverage capped at ICU discharge) |
| 06a–06c | Oct 13 | |
| 06d_baseline_options | Oct 16 | |
| 06d2_t0_staging_by_baseline_version | Oct 16 | Run with the earlier ">= 4.0 mg/dL" rule; the check now uses the final rule (D24) |
| 06d3_ckd_range_baseline | Oct 16 | Same as above |
| 06e_kidney_flow | Oct 27 | Transcribed; final rules. `n_kidney_transplant` column not captured |
| 06f_baseline_sources | — | Not yet run |
| 07a_exclusion_discovery | Oct 26 | |
| 07b_cohort_flow_option_a | Oct 27 | Transcribed from the Step 7 + Step 8b outputs |
| 07c_cohort_flow_option_b | — | Not yet run |
| 08a_feasibility_option_a | Oct 26 | Run before the final staging fixes (3,085 eligible; now 3,086) |
| 08b_outcome_scenarios | Oct 27 | Transcribed; final rules |
| 08c_creatinine_by_day | Oct 27 | |

**Before publishing:** many groups suppress counts below 10 in shared results. Check the data use agreement before making this repo or these files public.
