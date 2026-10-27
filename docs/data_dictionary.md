# Data dictionary

All tables live in `evocative-ethos-471602-r3.base`. All offsets are **minutes from ICU admission** (eICU convention; ICU admission = 0). Each table carries every column of the table it's built from, plus the columns listed.

## eicu_sepsis_stays (pipeline 01)
Every ICU stay with sepsis and no pneumonia (18,174 rows).

| Column | Meaning |
| --- | --- |
| patientunitstayid | ICU stay ID (row key) |
| patienthealthsystemstayid | hospitalization ID |
| uniquepid | patient ID |
| age | text; "> 89" for patients over 89 |
| gender, ethnicity | from `patient` |
| hospitalid, unittype, unitadmitsource | hospital and unit |
| hospitaladmitoffset | hospital admission relative to ICU admission (negative) |
| hospitaldischargeoffset, unitdischargeoffset | discharge times |
| hospitaldischargeyear | used to order hospitalizations |
| unitdischargestatus, hospitaldischargestatus | "Alive" / "Expired" |
| admissionheight, admissionweight | at admission |
| apacheadmissiondx | APACHE admission diagnosis |
| sepsis_source | 'diagnosis', 'admissiondx' or 'both' |
| sepsis_dx_string, sepsis_dx_icd, sepsis_admitdx_path | matched sepsis entries |
| all_admitdx_paths | all admission diagnoses |
| icu_order_in_hosp | 1 = first ICU stay of the hospitalization |
| patient_stay_rank | 1 = the patient's selected (earliest) stay |

## eicu_sepsis_no_pneumonia (pipeline 01)
One row per patient: `patient_stay_rank = 1 AND icu_order_in_hosp = 1` (14,810 rows).

## eicu_cohort (pipeline 02)
Adults (14,799 rows). **Primary cohort = `hosp_tx_pct >= 0.8`** (11,994).

| Column | Meaning |
| --- | --- |
| age_num | age as a number ("> 89" = 90) |
| hosp_tx_pct | share of the hospital's adult cohort patients with any treatment entry |
| first_imv_tx | first invasive-ventilation treatment entry |
| first_vent_marker | first ventilator setting (set tidal volume, vent rate, plateau pressure) |
| first_niv_tx | first non-invasive ventilation entry |
| first_trach_tx | first tracheostomy / trach collar entry |
| imv_status | 'imv', 'ambiguous' or 'none' |
| imv_start | IMV start = earliest of first_imv_tx and first_vent_marker |
| imv_source | 'both', 'treatment_only' or 'charting_only' |

## eicu_kidney_v1 (pipeline 03)
Primary cohort (11,994 rows) with kidney results.

| Column | Meaning |
| --- | --- |
| is_esrd | ESRD / chronic dialysis (any of 4 sources) |
| is_ckd | CKD, not ESRD |
| ckd_range_code | recorded usual creatinine: 1 = 1–2, 2 = 2–3, 3 = 3–4, 4 = 4–5, 5 = > 5 |
| kidney_transplant | past history or diagnosis |
| first_rrt_offset | first RRT (dialysis, CRRT, hemofiltration, ultrafiltration) |
| lowest_upto_t0 | lowest creatinine from 7 days before ICU admission to time zero (+6 h) |
| lowest_48h_before_t0 | lowest creatinine in the 48 h before time zero |
| t0_creat | most recent creatinine from −24 h to +6 h |
| expected_normal_creat | MDRD-estimated normal creatinine for age and sex (eGFR 75) |
| baseline_creat | baseline creatinine, mg/dL (D22) |
| baseline_source | 'measured (lowest up to time zero)', 'expected normal (MDRD)' or 'CKD: recorded range midpoint' |
| t0_aki_stage | KDIGO stage at time zero (NULL = no creatinine) |
| t0_offset | time zero (always 0 = ICU admission) |
| exclusion_reason | first kidney exclusion (NULL = passes, stage 0) |

## eicu_eligible_v1 (pipeline 03)
Rows of `eicu_kidney_v1` with `exclusion_reason IS NULL` (4,690), minus the helper columns.

## eicu_tte_cohort (pipeline 04)
Primary cohort (11,994 rows) with every exclusion flag. **Analysis cohort = `eligible_a` or `eligible_b`.**

| Column | Meaning |
| --- | --- |
| kidney_exclusion_reason | = `exclusion_reason` from pipeline 03 |
| kidney_ok_a / kidney_ok_b | passes kidney rules (A: stage 0; B: stage 0–1) |
| ventilated_on_arrival | IMV start <= 60 min |
| ambiguous_ventilation | imv_status = 'ambiguous' |
| chronic_trach | trach entry <= 60 min or care plan "trach-chronic" |
| care_limited_at_t0 | DNR / limitation of care within 6 h |
| chronic_lung_disease | COPD / chronic lung disease |
| has_asthma | asthma (not an exclusion) |
| other_excluded | any non-kidney exclusion |
| eligible_a | Option A eligible (3,086) |
| eligible_b | Option B eligible (3,973) |
