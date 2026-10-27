-- Checks 01: one stay per patient. Needs pipeline 01.


-- @query: 01a_one_stay_per_patient
-- Stays, patients, ICU readmissions, same-year ambiguity (D03)
WITH first_year AS (
  SELECT uniquepid, MIN(hospitaldischargeyear) AS yr
  FROM `evocative-ethos-471602-r3.base.eicu_sepsis_stays`
  GROUP BY uniquepid
),
ambiguous AS (
  SELECT s.uniquepid
  FROM `evocative-ethos-471602-r3.base.eicu_sepsis_stays` s
  JOIN first_year f ON s.uniquepid = f.uniquepid AND s.hospitaldischargeyear = f.yr
  GROUP BY s.uniquepid
  HAVING COUNT(DISTINCT s.patienthealthsystemstayid) > 1
)
SELECT
  COUNT(*)                                                       AS n_stays,
  COUNT(DISTINCT uniquepid)                                      AS n_patients,
  COUNTIF(patient_stay_rank = 1)                                 AS n_selected_stays,
  COUNTIF(patient_stay_rank = 1 AND icu_order_in_hosp = 1)       AS n_selected_first_icu_of_hosp,
  COUNTIF(patient_stay_rank = 1 AND icu_order_in_hosp > 1)       AS n_selected_icu_readmission,
  COUNTIF(patient_stay_rank = 1 AND hospitaldischargeyear IS NULL) AS n_selected_missing_year,
  (SELECT COUNT(*) FROM ambiguous)                               AS n_patients_same_year_ambiguous
FROM `evocative-ethos-471602-r3.base.eicu_sepsis_stays`;
