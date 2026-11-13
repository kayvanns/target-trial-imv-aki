# Decision log

Every rule in the pipeline, why it was chosen, and the evidence behind it. Decision numbers (D01…) are referenced in the SQL file headers.

Evidence refers to `sql/checks/<file>` blocks and the matching `results/<name>.csv`. Cohort-flow numbers are from `07b` (Option A) and `07c` (Option B); counts for each exclusion are after the earlier steps.

---

## Population

### D01 · Sepsis definition
- **Rule:** a sepsis diagnosis (diagnosis text containing "sepsis" or ICD codes 038.x, 995.91/92, 785.52, A41.x, R65.2x) **or** an admission diagnosis containing "sepsis", recorded within 24 h of ICU admission.
- **Why:** eICU's antibiotic and culture data are too patchy across hospitals for Sepsis-3 suspected infection.
- **Not applied:** "septic shock" strings that don't contain the word "sepsis" were considered but not added. Check this if the count needs revisiting.
- **Evidence:** pipeline 01 (18,174 stays).

### D02 · Pneumonia exclusion
- **Rule:** exclude pneumonia (diagnosis text, ICD 480–486 / J12–J18) or "Sepsis, pulmonary" admission diagnosis recorded **within 24 h** of ICU admission.
- **Why:** pneumonia drives both respiratory failure (intubation) and sepsis severity (AKI), the largest source of confounding by indication.
  - A 24 h window, not 0, because diagnoses are often charted hours after arrival; a narrower window would miss patients who arrived with pneumonia.
  - Ventilator-associated pneumonia needs ~48 h of ventilation, so pneumonia charted in the first 24 h reflects the presenting illness, not the treatment.
  - Pneumonia after 24 h is not an exclusion (it can be caused by ventilation).
- **Evidence:** pipeline 01.

### D03 · One ICU stay per patient
- **Rule:** keep each patient's **earliest sepsis hospitalization** (by discharge year), and only if the selected stay is the **first ICU stay of that hospitalization**.
  - Within a hospitalization, the first ICU stay has the largest `hospitaladmitoffset`.
  - Same-year hospitalizations can't be ordered in eICU, so `patienthealthsystemstayid` is an arbitrary, reproducible tie-break.
- **Why:** independent patients. ICU readmissions have an unknown earlier stay, which may have included ventilation, AKI or pneumonia.
- **Numbers:** 18,174 stays → 15,604 patients → **14,810** after excluding 794 ICU readmissions. 790 patients (5.1%) have >1 sepsis hospitalization in the same year → sensitivity analysis excluding them.
- **Evidence:** `checks/01` → `01a_one_stay_per_patient`.

### D04 · Adults
- **Rule:** age >= 18. Age is text in eICU; "> 89" is kept and coded 90.
- **Numbers:** 11 under 18 excluded, 0 missing → **14,799**.
- **Evidence:** `checks/02` → `02a_age`.

### D05 · Hospital data quality (treatment recording)
- **Rule:** keep hospitals where >= 80% of adult cohort patients have **any** treatment-table entry.
- **Why:** 14 hospitals never use the treatment table and 6 rarely do (0% and 2.5% ventilation rates), so "not ventilated" there means "not recorded".
- **Numbers:** 162 hospitals, **11,994** adults; 2,805 excluded. Sensitivity: >= 50% (183 hospitals, 13,784) and >= 95% (142 hospitals, 9,385). Stored as `hosp_tx_pct` so these are filters.
- **Evidence:** `checks/03` → `03c_imv_timing_treatment_only` (12,874 of 14,799 have any entry), `03d_hospital_treatment_usage`.

---

## Treatment: invasive mechanical ventilation (IMV)

### D06 · Treatment-table strings for IMV
- **Rule:** invasive = strings matching `mechanical ventilation | endotracheal tube | intubat`, **excluding** `non-invasive` and `endotracheal tube removal`.

| Class | Examples | Use |
| --- | --- | --- |
| Invasive | mechanical ventilation (± assist/volume/pressure controlled, SIMV, tidal volume 6-10 ml/kg, pressure support); surgery\|pulmonary therapies\|mechanical ventilation; endotracheal tube (insertion); reintubation | IMV and its start time |
| Supporting | ventilator weaning; endotracheal tube removal; lung recruitment; prone position | Implies IMV, not its start |
| NIV | non-invasive ventilation; mechanical ventilation\|non-invasive ventilation | **Not** IMV |
| Ambiguous | CPAP/PEEP therapy; tracheal suctioning | Not used (can be either) |
| Tracheostomy | tracheostomy (all variants); trach collar | Separate rule (D28) |
| Oxygen | oxygen therapy (all variants) | Not ventilation |
| Other | V/Q scan, chest physiotherapy | Ignored |

- **Numbers:** treatment table alone gives 3,264 ventilated adults. Only 18 have supporting entries without an invasive entry, so the invasive strings are internally consistent.
- **Evidence:** `checks/03` → `03a`, `03b`, `03c`.

### D07 · Ventilator-setting markers (respiratory charting)
- **Rule:** **Tidal Volume (set)**, **Vent Rate** or **Plateau Pressure** charted with a value > 0.
- **Why:** the most ventilator-specific labels: charted for 74%, 74% and 43% of treatment-ventilated patients vs 3.5%, 4.3% and 2.3% of others. PEEP, FiO2, pressure support and CPAP are also used on non-invasive machines.
- **Evidence:** `checks/04` → `04a_respcharting_labels`.

### D08 · IMV status and start time
- **Rule:**
  - **IMV** = a treatment IMV entry, **or** a ventilator marker with no NIV entry.
  - **Ambiguous** = ventilator marker + NIV entry, no treatment IMV entry.
  - **Start** = the **earliest** of the first treatment entry and the first marker.
- **Why:** treatment entries lag the ventilator settings. In the 1–24 h group, 67% had settings charted > 1 h earlier (median −114 min). "Endotracheal tube | insertion" and "mechanical ventilation" entries agree with each other (median lag 0), but were likely entered together, late.
- **Numbers (primary cohort):** 3,273 IMV (331 added from charting only), 82 ambiguous. Start: 864 at or before admission, 850 at 0–1 h, 1,176 at 1–24 h, 271 at 24–72 h, 112 later.
- **Evidence:** `checks/03` → `03e`; `checks/04` → `04b`, `04c`.

### D09 · Ventilated on arrival → excluded
- **Rule:** IMV start at or before time zero (<= 120 min after ICU admission; includes starts before admission). Uses `t0_offset` from pipeline 03.
- **Why:** mostly intubated before the ICU (ED/OR); charting in the first hours reflects arrival, not an ICU decision. Anyone intubated by time zero is not at risk of the treatment decision at time zero.
- **Numbers:** 679 (Option A flow), 939 (Option B flow).
- **Evidence:** `04c`, `10a_t0_window_eligibility`, `07b`, `07c`.

### D10 · Ambiguous ventilation → excluded
- **Numbers:** 26 (Option A flow), 42 (Option B flow).

### D11 · Time zero = ICU admission + 2 h
- **Rule:** time zero is **2 h after ICU admission** (`t0_min = 120`, stored as `t0_offset`). Baseline status uses data up to time zero, with a limited look-ahead to 6 h after ICU admission (`fallback_end_min = 360`) that stops at intubation, for:
  - creatinine at time zero when none was drawn by time zero (D23)
  - RRT (D16)
  - care limitations when no code status was charted by time zero (D29)
- **Why:**
  - The question is new-onset sepsis and semi-elective intubation for shock, so time zero should be close to sepsis onset.
  - Baseline status must come from before treatment. A fixed window running hours past time zero lets data after intubation define baseline (`10d`); stopping the look-ahead at intubation prevents this.
  - Positivity is handled by strong adjustment plus overlap diagnostics and trimming.
- **Evidence:** `10a_t0_window_eligibility`, `10d_baseline_values_after_imv`.

### D12 · Grace period = 24 h
- **Rule:** Strategy A = intubate within 24 h of time zero; Strategy B = no intubation within 24 h of time zero.
- **Why:** fits "semi-elective intubation in the first day" and captures most early intubations while keeping enough treated patients.
- **Numbers:** 292 of 3,878 intubated within 24 h (Option B); 195 of 3,010 (Option A).
- **Evidence:** `12a_analysis_summary`, `08a_feasibility_option_a`.

---

## Outcome: AKI

### D13 · Serum creatinine
- **Rule:** `lab.labname = 'creatinine'` (mg/dL), plausible range **0.2–20**. "Urinary creatinine" is a different test and is not used.
- **Numbers:** 99.2% of patients have >= 1 value; values are drawn on 83.9% of ICU days in the first week. 126 values < 0.2, 21 > 20 (of 106,782).
- **Evidence:** `checks/05` → `05a`, `05b`.

### D14 · No extra hospital restriction for creatinine
- **Why:** 97.7% of patients are at hospitals measuring creatinine on 82–88% of ICU days. Low-coverage hospitals are few and mostly small. Sensitivity analysis: exclude the < 50% coverage band (73 patients).
- **Evidence:** `05c_creatinine_by_hospital`.

### D15 · Urine output → sensitivity analysis only
- **Why:**
  - ~25% of patients have none charted.
  - It's mostly charted per shift: median 2–4 distinct hours with an entry in the first 24 h; only ~1 in 5 patients near-hourly.
  - It's charted **more often in ventilated patients** (near-hourly 29% vs 16%), which would bias the comparison.
- **Rule for the sensitivity analysis:**
  - restrict to **hospitals** (not patients) with >= 50% near-hourly charting: 18 hospitals, 1,814 patients
  - urine = all bladder-catheter, void, external, straight-cath, condom-cath, nephrostomy, urostomy, ileal conduit and ureteral-stent labels
  - excluded: counts/occurrences, mixed urine/stool, totals, RRT fluid
  - drop values < 0 or > 5,000 mL
- **Evidence:** `05d`, `05d2`, `05e`, `05e2`.

### D16 · RRT (dialysis, CRRT, …)
- **Rule:** first RRT = earliest of:
  - treatment entries matching `dialys|crrt|cvvh|c v v h|hemofiltration|ultrafiltration|renal replacement` (catheter insertion alone excluded)
  - intake/output RRT fluid-removal labels (`hemofiltration|dialys|fluid removal|ultrafiltrat|crrt|cvvh`)
- **Uses:**
  - RRT start = KDIGO stage 3.
  - Creatinine after RRT start is ignored (RRT removes creatinine).
  - RRT started **by 6 h after ICU admission and before intubation** = AKI (stage 3) at time zero (same look-ahead window as the fallback creatinine, D23). RRT after intubation is not AKI at time zero; it can count as the outcome.
- **Numbers:** among non-ESRD patients, none before ICU admission; 506 during the stay. 8 RRT outcome events within 7 days (Option B).
- **Evidence:** `06c_rrt_timing_by_esrd_group`, `12a_analysis_summary`.

### D17 · Primary outcome
- **Rule:** KDIGO **stage 2–3 by creatinine, or RRT initiation**. Outcome creatinine counts only after 6 h from ICU admission (360 min, the end of the time-zero look-ahead window, D23).
- **Why stage 2–3, not any stage:**
  - Stage 1 by creatinine is noisy (lab variation, fluid shifts, baseline estimation error) and often transient.
  - Stage 1 is sensitive to how often blood is drawn, which differs by arm.
- **Alternatives (sensitivity):** any-stage AKI (Option A: 433 events vs 148 for stage 2–3/RRT).
- **Evidence:** `08b_outcome_scenarios`, `12a_analysis_summary`.

### D18 · Outcome window and follow-up
- **Rule:** **7 days** from time zero. Follow-up ends at AKI, day 7, death, or **hospital** discharge. ICU discharge does **not** end follow-up; ward creatinine counts.
- **Why:**
  - With a 24 h grace period, a 72 h window leaves late-intubated patients only ~2 days for creatinine to rise (it takes 24–48 h).
  - Matches the ADQI definition of sepsis-associated AKI (within 7 days).
  - More events than 72 h (Option B: 313 vs 252).
  - 78% leave the ICU within 72 h, so censoring at ICU discharge is not viable.
- **Numbers (Option B, end of follow-up):** 313 AKI, 107 death, 2,236 hospital discharge, 1,222 day 7.
- **Sensitivity:** 72 h window.
- **Open:** whether patients discharged home before day 7 count as "no AKI" (standard) or are censored.
- **Evidence:** `05b`, `08a`, `08b`, `12a_analysis_summary`.

### D19 · Limitation: creatinine measurement on the ward
- **Finding:** creatinine is drawn on 84–97% of ICU days but only 47–58% of ward days. Non-intubated patients move to the ward sooner (day 3: 1,933 on the ward vs 1,329 in the ICU, compared with 32 vs 283 for intubated), so ward AKI is missed more often in that group, which could bias toward harm.
- **Plan:** 72 h sensitivity analysis; a measurement-aware approach (e.g. treat long gaps without creatinine as loss of follow-up, with weights); report lab frequency by group.
- **Evidence:** `08c_creatinine_by_day`, `08d_followup_gaps`.

---

## Kidney history and baseline

### D20 · ESRD / chronic dialysis → excluded
- **Rule:** any of 4 sources:
  - past history "renal failure – hemodialysis / peritoneal dialysis"
  - APACHE `dialysis = 1`
  - diagnoses (ESRD, CKD stage 5, dialysis-associated peritonitis, dialysis access surgery, ICD 585.5/585.6/N18.5/N18.6/V45.1x/Z99.2)
  - treatments "for chronic renal failure" or peritoneal dialysis
- **Why:** creatinine reflects the dialysis schedule, not kidney function, so KDIGO can't be applied.
- **Numbers:** **844** (7.0%); 88% confirmed by >= 2 sources. The 62 diagnosis-only patients behave like ESRD (63% RRT, median first creatinine 3.9). Sensitivity: >= 2 sources.
- **Evidence:** `06a`, `06b`, `06c`.

### D21 · CKD
- **Rule:** CKD = past history "renal insufficiency…" / "renal failure – not currently dialyzed", or diagnoses (CKD, chronic renal insufficiency, anemia of renal disease).

| CKD group | n | Decision |
| --- | --- | --- |
| Recorded usual creatinine 1–2, 2–3, 3–4 | 487 | **Keep**, baseline = range midpoint |
| Usual creatinine 4–5 or > 5 (severe) | 38 | **Exclude** |
| "Baseline creatinine unknown" | 487 | **Exclude** |
| "Not currently dialyzed", no range | 235 | **Exclude** |
| Diagnosis only | 316 | **Exclude** |

- **Why:** without a recorded usual level there is no valid baseline. Among patients with a range, the lowest measured value under-calls AKI at time zero compared with the recorded range.
- **Sensitivity:** keep the 1,038 without a range, using their lowest measured value.
- **Possible rescue (not applied):** some diagnosis-only CKD has a stage (GFR range) that could be back-calculated.
- **Evidence:** `06d3_ckd_range_baseline`.

### D22 · Baseline creatinine
- **Rule** (MIMIC `creatinine_baseline` rule, adapted to use only data **up to the time-zero creatinine**, D23):
  - **No CKD:** lowest creatinine from 7 days before ICU admission to `t0_creat_time` if < 1.1 mg/dL; otherwise the **expected normal** for age and sex, i.e. MDRD solved at eGFR 75: `Scr = (75 / (175 × age^-0.203 × 0.742[female]))^(-1/1.154)`
  - **CKD:** midpoint of the recorded range (1.5 / 2.5 / 3.5)
- **Why:**
  - eICU has no pre-hospital creatinine; "pre-ICU" values are ED labs ~6 h before ICU (median 5.7 h), already raised (~45% of non-CKD patients have a first value >= 1.5× expected normal).
  - MIMIC as written uses the whole stay, which includes post-treatment data.
  - Constant **175** (IDMS-standardized assays, used by US labs in 2014–15) vs MIMIC's 186; 186 gives baselines ~5% higher (sensitivity).
  - No race term.
- **Evidence:** `06d`, `06d2`, `06f`.

### D23 · Creatinine at time zero
- **Rule** (two steps, `t0_creat_source`):
  1. **`pre_t0`:** the most recent value from 24 h before ICU admission to time zero (+2 h).
  2. **`fallback`:** if none, the **earliest** value after time zero, up to 6 h after ICU admission and before intubation (never-intubated patients: up to 6 h).
  - Ties at the same minute → the higher value (reproducible).
  - The time of the chosen value (`t0_creat_time`) anchors the baseline: lowest value from 7 days before ICU admission to `t0_creat_time` (D22), and lowest in the 48 h before `t0_creat_time` (D24).
- **Why the fallback:** creatinine is often first drawn a few hours after arrival; without it, many more patients would have no time-zero value (`10a`: 856 vs 515 missing with labs to +2 h vs +6 h). Stopping at intubation keeps the value before treatment.
- **Numbers:** **232** of 3,878 Option B eligible patients have a fallback time-zero creatinine; 23 of them are intubated within 24 h.
- **Evidence:** `10a`, `10d`, `12a_analysis_summary`.

### D24 · KDIGO staging (creatinine)
- **Rule:**
  - **Stage 3:** >= 3.0× baseline; or >= 4.0 mg/dL **when also an acute rise** (>= 1.5× baseline or >= 0.3 in 48 h); or RRT
  - **Stage 2:** >= 2.0× baseline
  - **Stage 1:** >= 1.5× baseline, or >= 0.3 mg/dL above the lowest value in the prior 48 h
- **Why the ">= 4.0" condition:** KDIGO's "increase to >= 4.0" only applies once AKI is present. Without it, CKD patients with high baselines are over-called as stage 3.

### D25 · No creatinine near time zero → excluded
- **Numbers:** **896**. AKI status at time zero can't be determined.

### D26 · Eligibility: AKI at time zero
- **Option B (primary):** stage 0–1 at time zero, outcome = progression to stage 2–3/RRT → **3,878** eligible (868 at stage 1), 292 intubated within 24 h, 313 events (stage 2–3/RRT, 7 days).
- **Option A (sensitivity):** stage 0 at time zero → 3,010 eligible, 195 intubated within 24 h, 148 events.
- **Why B:**
  - More than doubles events (313 vs 148) and raises the treated group by half (292 vs 195) while keeping the stage 2–3 outcome.
  - Adjust for stage and creatinine at time zero; report effect by starting stage.
- **Precedent:** Option A matches the ProCESS AKI analysis (Kellum 2016).
- **Sensitivity:** Option A (stage 2–3 and any-stage).
- **Evidence:** `07b`, `07c`, `12a_analysis_summary`. Both stored (`eligible_a`, `eligible_b`).

---

## Other baseline exclusions

### D27 · Kidney transplant → excluded
- **Rule:** past history "renal transplant" or diagnoses (kidney transplant, ICD V42.0/Z94.0/996.81).
- **Numbers:** 14 (Option A flow), 22 (Option B flow).

### D28 · Chronic tracheostomy → excluded
- **Rule:** tracheostomy treatment entry at or before time zero (<= 120 min, `t0_offset`) **or** care plan "Airway | Intubated/trach-chronic". "Trach-acute" (new) is not an exclusion.
- **Numbers:** 55 (Option A flow), 65 (Option B flow).
- **Evidence:** `03c`, `07a`.

### D29 · DNR / limitation of care at time zero → excluded
- **Items:** care plan "Care Limitation": Do not resuscitate, No CPR, **No intubation**, Comfort measures only, No augmentation of care, No vasopressors/inotropes, No cardioversion. "No blood draws/products" are not included. "Full therapy" counts as a code-status entry (not limited).
- **Rule: status at time zero.** Limited if either:
  1. **`status_at_t0`:** the latest code-status entry (limitation or Full therapy) charted by time zero is a limitation. Same-minute tie → limitation. A limitation reversed to Full therapy before time zero is not limited.
  2. **`fallback`:** only if no code status was charted by time zero, the first entry after time zero, up to 6 h and before intubation, is a limitation. Same-minute tie → limitation.
  - Not limited: no entries; entries only after 6 h or after intubation; Full therapy at time zero that changes to a limitation later.
- **Why:**
  - "No intubation" makes positivity impossible.
  - Care-plan offsets are charting times. Code status is usually charted early (first care-limitation entry: median 34 min, 83% by 2 h), so a first status charted 2–6 h is most likely the status on arrival, charted late.
  - A change from Full therapy to a limitation after time zero is a new decision, often triggered by deterioration; excluding on it would use post-time-zero information. In the 2–6 h window, 53 of 107 limitations were such changes; after 6 h, 326 of 349.
- **Sensitivity:** `care_limited_strict_2h` (rule 1 only) and `care_limited_any_6h` (any limitation charted within 6 h).
- **Numbers:** 332 (Option A flow), 509 (Option B flow).
- **Evidence:** `07a_exclusion_discovery`, `11a_care_limitation_timing`, `11b_care_limitation_late_entries`.

### D30 · COPD / chronic lung disease → excluded
- **Rule** (chronic, so timing is ignored):
  - past history Pulmonary/COPD (any severity), Home Oxygen, Restrictive Disease, Respiratory Failure (prior), Sarcoidosis
  - diagnoses containing COPD (incl. exacerbations) or chronic respiratory failure
- **Not included:** lung cancer / metastases, pulmonary embolism (not chronic lung disease).
- **Why:** intubation in these patients is driven by respiratory reasons, not shock; intubation decisions depend on unmeasured lung function; ventilation affects them differently (air trapping).
- **Numbers:** 465 (Option A flow), 623 (Option B flow).
- **Evidence:** `07a_exclusion_discovery`.

### D31 · Asthma → flagged, not excluded
- **Numbers:** 217 among the Option B eligible, 174 among the Option A eligible.

---

## Analysis principles

### D32 · Outcome-blind feasibility
- Outcome events are counted **overall only, never split by intubation**, until the protocol (eligibility, outcome, window, grace period) is fixed. This prevents design choices being steered by the result. Measurement frequency (not results) may be split by group.

### D33 · Clone-censor-weighting (planned)
- Single time zero (ICU admission + 2 h, D11), clones assigned to both strategies, censored at deviation from the assigned strategy, inverse-probability-of-censoring weights from baseline and time-varying covariates; overlap diagnostics and weight truncation.


