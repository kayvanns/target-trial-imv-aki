# Decision log

Every rule in the pipeline, why it was chosen, the evidence behind it, and whether the PI has signed off. Decision numbers (D01…) are referenced in the SQL file headers.

**Status key**
- **Approved:** agreed with the PI (Neil)
- **Analyst:** analyst decision, reported to the PI, no objection yet
- **Proposed:** awaiting PI input
- **Open:** not yet decided

Evidence refers to `sql/checks/<file>` blocks and the matching `results/<name>.csv`.

---

## Population

### D01 · Sepsis definition
- **Rule:** a sepsis diagnosis (diagnosis text containing "sepsis" or ICD codes 038.x, 995.91/92, 785.52, A41.x, R65.2x) **or** an admission diagnosis containing "sepsis", recorded within 24 h of ICU admission.
- **Why:** eICU's antibiotic and culture data are too patchy across hospitals for Sepsis-3 suspected infection.
- **Not applied:** "septic shock" strings that don't contain the word "sepsis" were considered but not added. Check this if the count needs revisiting.
- **Evidence:** pipeline 01 (18,174 stays).
- **Status:** Analyst (reported Oct 12).

### D02 · Pneumonia exclusion
- **Rule:** exclude pneumonia (diagnosis text, ICD 480–486 / J12–J18) or "Sepsis, pulmonary" admission diagnosis recorded **within 24 h** of ICU admission.
- **Why:** pneumonia drives both respiratory failure (intubation) and sepsis severity (AKI), the largest source of confounding by indication.
  - A 24 h window, not 0, because diagnoses are often charted hours after arrival; a narrower window would miss patients who arrived with pneumonia.
  - Ventilator-associated pneumonia needs ~48 h of ventilation, so pneumonia charted in the first 24 h reflects the presenting illness, not the treatment.
  - Pneumonia after 24 h is not an exclusion (it can be caused by ventilation).
- **Evidence:** pipeline 01.
- **Status:** Approved (PI proposed excluding pneumonia).

### D03 · One ICU stay per patient
- **Rule:** keep each patient's **earliest sepsis hospitalization** (by discharge year), and only if the selected stay is the **first ICU stay of that hospitalization**.
  - Within a hospitalization, the first ICU stay has the largest `hospitaladmitoffset`.
  - Same-year hospitalizations can't be ordered in eICU, so `patienthealthsystemstayid` is an arbitrary, reproducible tie-break.
- **Why:** independent patients. ICU readmissions have an unknown earlier stay, which may have included ventilation, AKI or pneumonia.
- **Numbers:** 18,174 stays → 15,604 patients → **14,810** after excluding 794 ICU readmissions. 790 patients (5.1%) have >1 sepsis hospitalization in the same year → sensitivity analysis excluding them.
- **Evidence:** `checks/01` → `01a_one_stay_per_patient`.
- **Status:** Analyst (reported Oct 12).

### D04 · Adults
- **Rule:** age >= 18. Age is text in eICU; "> 89" is kept and coded 90.
- **Numbers:** 11 under 18 excluded, 0 missing → **14,799**.
- **Evidence:** `checks/02` → `02a_age`.
- **Status:** Analyst.

### D05 · Hospital data quality (treatment recording)
- **Rule:** keep hospitals where >= 80% of adult cohort patients have **any** treatment-table entry.
- **Why:** 14 hospitals never use the treatment table and 6 rarely do (0% and 2.5% ventilation rates), so "not ventilated" there means "not recorded".
- **Numbers:** 162 hospitals, **11,994** adults; 2,805 excluded. Sensitivity: >= 50% (183 hospitals, 13,784) and >= 95% (142 hospitals, 9,385). Stored as `hosp_tx_pct` so these are filters.
- **Evidence:** `checks/03` → `03c_imv_timing_treatment_only` (12,874 of 14,799 have any entry), `03d_hospital_treatment_usage`.
- **Status:** Analyst (reported Oct 12).

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
- **Status:** Analyst.

### D07 · Ventilator-setting markers (respiratory charting)
- **Rule:** **Tidal Volume (set)**, **Vent Rate** or **Plateau Pressure** charted with a value > 0.
- **Why:** the most ventilator-specific labels: charted for 74%, 74% and 43% of treatment-ventilated patients vs 3.5%, 4.3% and 2.3% of others. PEEP, FiO2, pressure support and CPAP are also used on non-invasive machines.
- **Evidence:** `checks/04` → `04a_respcharting_labels`.
- **Status:** Analyst.

### D08 · IMV status and start time
- **Rule:**
  - **IMV** = a treatment IMV entry, **or** a ventilator marker with no NIV entry.
  - **Ambiguous** = ventilator marker + NIV entry, no treatment IMV entry.
  - **Start** = the **earliest** of the first treatment entry and the first marker.
- **Why:** treatment entries lag the ventilator settings. In the 1–24 h group, 67% had settings charted > 1 h earlier (median −114 min). "Endotracheal tube | insertion" and "mechanical ventilation" entries agree with each other (median lag 0), but were likely entered together, late.
- **Numbers (primary cohort):** 3,273 IMV (331 added from charting only), 82 ambiguous. Start: 864 at or before admission, 850 at 0–1 h, 1,176 at 1–24 h, 271 at 24–72 h, 112 later. About 600 patients moved from "1–24 h" to "on arrival".
- **Evidence:** `checks/03` → `03e`; `checks/04` → `04b`, `04c`.
- **Status:** Analyst (reported Oct 12; PI asked to review the treatment definition).

### D09 · Ventilated on arrival → excluded
- **Rule:** IMV start <= 60 min after ICU admission (includes starts before admission).
- **Why:** mostly intubated before the ICU (ED/OR); charting in the first hour reflects arrival, not an ICU decision. Not at risk of the treatment decision at time zero.
- **Numbers:** 604 excluded (after the kidney rules).
- **Evidence:** `04c`, `07b`.
- **Status:** Analyst.

### D10 · Ambiguous ventilation → excluded
- **Numbers:** 26 excluded (after the kidney rules).
- **Status:** Analyst.

### D11 · Time zero = ICU admission
- **Rule:** time zero is ICU admission (offset 0). Labs drawn in the first 6 h count as "at time zero" (creatinine changes slowly, so they reflect the state on arrival).
- **Why:** PI's decision. The question is new-onset sepsis and semi-elective intubation for shock, so time zero should be as close to sepsis onset as possible.
  - Considered and dropped: time zero at the first "candidate" moment (respiratory signs). The PI noted this would select patients intubated for respiratory failure, not shock.
  - Positivity is handled by strong adjustment plus overlap diagnostics and trimming.
- **Status:** Approved (PI).

### D12 · Grace period = 24 h
- **Rule:** Strategy A = intubate within 24 h of ICU admission; Strategy B = no intubation within 24 h.
- **Why:** nearly doubles the treated group vs 6 h (242 vs 129 under Option A), fits "semi-elective intubation in the first day", and captures most intubations that ever happen (241 of 314 by 24 h).
- **Evidence:** `checks/08` → `08a_feasibility_option_a`.
- **Status:** Proposed (asked PI Oct 27).

---

## Outcome: AKI

### D13 · Serum creatinine
- **Rule:** `lab.labname = 'creatinine'` (mg/dL), plausible range **0.2–20**. "Urinary creatinine" is a different test and is not used.
- **Numbers:** 99.2% of patients have >= 1 value; values are drawn on 83.9% of ICU days in the first week. 126 values < 0.2, 21 > 20 (of 106,782).
- **Evidence:** `checks/05` → `05a`, `05b`.
- **Status:** Analyst.

### D14 · No extra hospital restriction for creatinine
- **Why:** 97.7% of patients are at hospitals measuring creatinine on 82–88% of ICU days. Low-coverage hospitals are few and mostly small. Sensitivity analysis: exclude the < 50% coverage band (73 patients).
- **Evidence:** `05c_creatinine_by_hospital`.
- **Status:** Analyst.

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
- **Status:** Analyst (reported to PI).

### D16 · RRT (dialysis, CRRT, …)
- **Rule:** first RRT = earliest of:
  - treatment entries matching `dialys|crrt|cvvh|c v v h|hemofiltration|ultrafiltration|renal replacement` (catheter insertion alone excluded)
  - intake/output RRT fluid-removal labels (`hemofiltration|dialys|fluid removal|ultrafiltrat|crrt|cvvh`)
- **Uses:** RRT start = KDIGO stage 3; creatinine after RRT start is ignored (RRT removes creatinine); RRT by time zero = AKI at time zero.
- **Numbers:** among non-ESRD patients, none before ICU admission; 506 during the stay.
- **Evidence:** `06c_rrt_timing_by_esrd_group`.
- **Status:** Analyst.

### D17 · Primary outcome
- **Rule:** KDIGO **stage 2–3 by creatinine, or RRT initiation**.
- **Why stage 2–3, not any stage:**
  - Stage 1 by creatinine is noisy (lab variation, fluid shifts, baseline estimation error) and often transient.
  - Stage 1 is sensitive to how often blood is drawn, which differs by arm.
- **Alternatives (sensitivity):** any-stage AKI (429 events vs 149 under Option A).
- **Evidence:** `08b_outcome_scenarios`.
- **Status:** Proposed (asked PI Oct 27).

### D18 · Outcome window and follow-up
- **Rule:** **7 days** from ICU admission. Follow-up ends at day 7, death, or **hospital** discharge. ICU discharge does **not** end follow-up; ward creatinine counts.
- **Why:**
  - With a 24 h grace period, a 72 h window leaves late-intubated patients only ~2 days for creatinine to rise (it takes 24–48 h).
  - Matches the ADQI definition of sepsis-associated AKI (within 7 days).
  - +25–40% more events than 72 h (B: 327 vs 262).
  - 78% leave the ICU within 72 h, so censoring at ICU discharge is not viable.
- **Sensitivity:** 72 h window.
- **Open:** whether patients discharged home before day 7 count as "no AKI" (standard) or are censored.
- **Evidence:** `05b`, `08a`, `08b`.
- **Status:** Proposed (asked PI Oct 27).

### D19 · Limitation: creatinine measurement on the ward
- **Finding:** creatinine is drawn on 84–97% of ICU days but only 47–58% of ward days. Non-intubated patients move to the ward sooner (day 3: 1,933 on the ward vs 1,329 in the ICU, compared with 32 vs 283 for intubated), so ward AKI is missed more often in that group, which could bias toward harm.
- **Plan:** 72 h sensitivity analysis; a measurement-aware approach (e.g. treat long gaps without creatinine as loss of follow-up, with weights); report lab frequency by group.
- **Evidence:** `08c_creatinine_by_day`.
- **Status:** Open (asked PI Oct 27).

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
- **Status:** Approved (PI: "all of these are reasonable").

### D21 · CKD
- **Rule:** CKD = past history "renal insufficiency…" / "renal failure – not currently dialyzed", or diagnoses (CKD, chronic renal insufficiency, anemia of renal disease).

| CKD group | n | Decision |
| --- | --- | --- |
| Recorded usual creatinine 1–2, 2–3, 3–4 | 487 | **Keep**, baseline = range midpoint |
| Usual creatinine 4–5 or > 5 (severe) | 38 | **Exclude** |
| "Baseline creatinine unknown" | 487 | **Exclude** |
| "Not currently dialyzed", no range | 235 | **Exclude** |
| Diagnosis only | 316 | **Exclude** |

- **Why:** without a recorded usual level there is no valid baseline. Among the 525 with a range, the lowest measured value finds AKI at time zero in only 16% vs 38% with the recorded range.
- **Sensitivity:** keep the 1,038 without a range, using their lowest measured value.
- **Possible rescue (not applied):** some diagnosis-only CKD has a stage (GFR range) that could be back-calculated.
- **Evidence:** `06d3_ckd_range_baseline`.
- **Status:** Analyst (reported Oct 27).

### D22 · Baseline creatinine
- **Rule** (MIMIC `creatinine_baseline` rule, adapted to use only data **up to time zero**):
  - **No CKD:** lowest creatinine from 7 days before ICU admission to time zero if < 1.1 mg/dL; otherwise the **expected normal** for age and sex, i.e. MDRD solved at eGFR 75: `Scr = (75 / (175 × age^-0.203 × 0.742[female]))^(-1/1.154)`
  - **CKD:** midpoint of the recorded range (1.5 / 2.5 / 3.5)
- **Why:**
  - eICU has no pre-hospital creatinine; "pre-ICU" values are ED labs ~6 h before ICU (median 5.7 h), already raised (~45% of non-CKD patients have a first value >= 1.5× expected normal).
  - MIMIC as written uses the whole stay, which includes post-treatment data.
  - Constant **175** (IDMS-standardized assays, used by US labs in 2014–15) vs MIMIC's 186; 186 gives baselines ~5% higher (sensitivity).
  - No race term.
- **Evidence:** `06d`, `06d2`, `06f`.
- **Status:** Analyst (reported Oct 27).

### D23 · Creatinine at time zero
- **Rule:** the most recent value from 24 h before to 6 h after ICU admission. Ties at the same minute → the higher value (reproducible).
- **Status:** Analyst.

### D24 · KDIGO staging (creatinine)
- **Rule:**
  - **Stage 3:** >= 3.0× baseline; or >= 4.0 mg/dL **when also an acute rise** (>= 1.5× baseline or >= 0.3 in 48 h); or RRT
  - **Stage 2:** >= 2.0× baseline
  - **Stage 1:** >= 1.5× baseline, or >= 0.3 mg/dL above the lowest value in the prior 48 h
- **Why the ">= 4.0" condition:** KDIGO's "increase to >= 4.0" only applies once AKI is present. Without it, CKD patients with high baselines were over-called as stage 3 (fix moved 2 patients to eligible).
- **Status:** Analyst.

### D25 · No creatinine near time zero → excluded
- **Numbers:** **801**. AKI status at time zero can't be determined.
- **Status:** Analyst.

### D26 · Eligibility: AKI at time zero
- **Option A:** stage 0 at time zero → 3,086 eligible, 242 intubated by 24 h, 149 events (stage 2–3/RRT, 7 days).
- **Option B:** stage 0–1 at time zero, outcome = progression to stage 2–3/RRT → 3,973 eligible, 375 intubated, 327 events.
- **Why B is proposed:**
  - More than doubles events and raises treated by 55% while keeping the stage 2–3 outcome.
  - Rough minimum detectable RR after weighting: ~1.75 (B) vs ~2.3 (A).
  - Adjust for stage and creatinine at time zero; report effect by starting stage.
- **Precedent:** Option A matches the ProCESS AKI analysis (Kellum 2016).
- **Sensitivity:** Option A (stage 2–3 and any-stage).
- **Evidence:** `08b_outcome_scenarios`, `07b`, `07c`.
- **Status:** Proposed (asked PI Oct 27). Both stored (`eligible_a`, `eligible_b`).

---

## Other baseline exclusions

### D27 · Kidney transplant → excluded
- **Rule:** past history "renal transplant" or diagnoses (kidney transplant, ICD V42.0/Z94.0/996.81).
- **Numbers:** 15 excluded (after earlier steps).
- **Status:** Approved (PI).

### D28 · Chronic tracheostomy → excluded
- **Rule:** tracheostomy treatment entry within 60 min **or** care plan "Airway | Intubated/trach-chronic". "Trach-acute" (new) is not an exclusion.
- **Numbers:** 69.
- **Evidence:** `03c` (19 within 1 h), `07a` (69 care-plan chronic).
- **Status:** Approved (PI).

### D29 · DNR / limitation of care at time zero → excluded
- **Rule:** care plan "Care Limitation" **within 6 h**: Do not resuscitate, No CPR, **No intubation**, Comfort measures only, No augmentation of care, No vasopressors/inotropes, No cardioversion. "No blood draws/products" are not included.
- **Why:** "No intubation" makes positivity impossible; limitations set after 6 h happen after time zero and are not exclusions.
- **Numbers:** 409.
- **Evidence:** `07a_exclusion_discovery`.
- **Status:** Approved (PI).

### D30 · COPD / chronic lung disease → excluded
- **Rule** (chronic, so timing is ignored):
  - past history Pulmonary/COPD (any severity), Home Oxygen, Restrictive Disease, Respiratory Failure (prior), Sarcoidosis
  - diagnoses containing COPD (incl. exacerbations) or chronic respiratory failure
- **Not included:** lung cancer / metastases, pulmonary embolism (not chronic lung disease).
- **Why:** intubation in these patients is driven by respiratory reasons, not shock; intubation decisions depend on unmeasured lung function; ventilation affects them differently (air trapping).
- **Numbers:** 481.
- **Evidence:** `07a_exclusion_discovery`.
- **Status:** Approved (PI suggested).

### D31 · Asthma → flagged, not excluded
- **Numbers:** 181 among the Option A eligible.
- **Status:** Proposed (asked PI Oct 27).

---

## Analysis principles

### D32 · Outcome-blind feasibility
- Outcome events are counted **overall only, never split by intubation**, until the protocol (eligibility, outcome, window, grace period) is fixed. This prevents design choices being steered by the result. Measurement frequency (not results) may be split by group.

### D33 · Clone-censor-weighting (planned)
- Single time zero (ICU admission), clones assigned to both strategies, censored at deviation from the assigned strategy, inverse-probability-of-censoring weights from baseline and time-varying covariates; overlap diagnostics and weight truncation. Reference: Maringe et al., *Int J Epidemiol* 2020.
- **Status:** Approved approach (PI); details pending.

---

## Designs considered and set aside

| Design | Why set aside |
| --- | --- |
| "Ever ventilated vs never" | Confounding by indication, no clear time zero |
| Time zero at first "candidate" moment (respiratory signs) | Selects respiratory-failure intubations, not shock-driven ones (PI) |
| Sequential trials (new trial every 4 h) | Not needed with a single time zero; more complex |
| PEEP strategies among ventilated patients ("Version 1") | Kept as a possible secondary project; PEEP charted for ~81% of treatment-ventilated patients (`04a`) |
