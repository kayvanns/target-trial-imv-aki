# Cohort flow

Latest run: Oct 27, 2026. Each step lists patients excluded for the **first** reason that applies. Decision numbers refer to `decisions.md`.

## Base cohort (pipelines 01–02)

| Step | Excluded | Remaining | Decision |
| --- | --- | --- | --- |
| ICU stays with sepsis, no pneumonia (within 24 h) | — | 18,174 stays | D01, D02 |
| One stay per patient (earliest sepsis hospitalization) | 2,570 stays | 15,604 patients | D03 |
| ICU readmissions (not the first ICU stay of the hospitalization) | 794 | 14,810 | D03 |
| Under 18 | 11 | 14,799 | D04 |
| Hospitals recording treatments for < 80% of patients (20 hospitals never/rarely) | 2,805 | **11,994** (162 hospitals) | D05 |

## Kidney rules (pipeline 03)

| Step | Excluded | Remaining | Decision |
| --- | --- | --- | --- |
| ESRD / chronic dialysis | 844 | 11,150 | D20 |
| Severe CKD (usual creatinine > 4) | 38 | 11,112 | D21 |
| CKD without recorded usual creatinine | 1,038 | 10,074 | D21 |
| No creatinine near time zero | 801 | 9,273 | D25 |
| AKI at time zero (stage 1: 1,508 · stage 2: 1,505 · stage 3: 1,570) | 4,583 | 4,690 | D26 |

## Other exclusions (pipeline 04)

| Step | Excluded | Remaining | Decision |
| --- | --- | --- | --- |
| Ventilated on arrival (<= 60 min) | 604 | 4,086 | D09 |
| Ambiguous ventilation status | 26 | 4,060 | D10 |
| Kidney transplant | 15 | 4,045 | D27 |
| Chronic tracheostomy | 69 | 3,976 | D28 |
| DNR / care limitation within 6 h | 409 | 3,567 | D29 |
| COPD / chronic lung disease | 481 | **3,086 (Option A)** | D30 |

**Option B** (stage 1 at time zero kept): **3,973** eligible (+887).

Asthma (not excluded): 181 of the Option A eligible.

## Feasibility (24 h grace period)

| Option | Eligible | Intubated by 24 h | Events by 72 h | Events by 7 days |
| --- | --- | --- | --- | --- |
| A, stage 2–3 or RRT | 3,086 | 242 | 107 | 149 |
| A, any stage 1–3 or RRT | 3,086 | 242 | 328 | 429 |
| **B, stage 2–3 or RRT (proposed)** | **3,973** | **375** | **262** | **327** |

Events are counted overall only, not by intubation (D32).
