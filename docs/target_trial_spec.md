# Target trial specification

Question: among adults with new-onset non-pneumonia sepsis, does semi-elective invasive mechanical ventilation (intubation for shock) within 24 h of ICU admission increase the 7-day risk of moderate-to-severe AKI, compared with no intubation within 24 h?

Decision numbers refer to `decisions.md`. Items marked *(proposed)* await PI input.

| Component | Target trial | Emulation in eICU-CRD |
| --- | --- | --- |
| **Eligibility** | Adults in the ICU with sepsis from a non-pulmonary source, not intubated, without AKI (or with mild AKI), without chronic kidney or lung disease that changes the decision or the outcome, without limits on care | Sepsis diagnosis within 24 h, pneumonia excluded (D01–D02); first ICU stay of the earliest sepsis hospitalization (D03); adults (D04); hospitals recording treatments for >= 80% (D05); no ESRD, severe CKD or CKD without a known baseline (D20–D21); creatinine available near admission (D25); stage 0 (Option A) or stage 0–1 (Option B) at admission *(proposed: B)* (D26); not ventilated on arrival (D09–D10); no kidney transplant, chronic tracheostomy, DNR/care limitation within 6 h, or chronic lung disease (D27–D30) |
| **Treatment strategies** | (1) Intubate within 24 h of ICU admission; (2) do not intubate within 24 h | IMV start = earliest of the treatment-table entry and ventilator settings (D06–D08); grace period 24 h *(proposed)* (D12) |
| **Assignment** | Randomized at ICU admission | Clone-censor-weighting: clones assigned to both strategies at time zero, censored at deviation, inverse-probability weights from baseline and time-varying confounders (D33) |
| **Time zero** | ICU admission | ICU admission; labs in the first 6 h count as "at time zero" (D11) |
| **Follow-up** | Time zero to AKI, death, hospital discharge or day 7 | Same; follow-up continues after ICU discharge (D18) |
| **Outcome** | KDIGO stage 2–3 AKI or RRT within 7 days | Serum creatinine against the baseline (D13, D22–D24), or RRT start (D16) *(proposed)* (D17). Urine output: sensitivity only (D15) |
| **Causal contrast** | Per-protocol effect | Risk difference and risk ratio at 7 days via clone-censor-weighting; death as a competing event |
| **Sensitivity analyses** | — | Option A; any-stage AKI; 72 h window; hospitals >= 50% / >= 95%; ESRD from >= 2 sources; keep CKD without a recorded baseline; MDRD constant 186; exclude same-year ambiguous patients; urine output in near-hourly hospitals |
