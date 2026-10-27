-- Checks 03: ventilation in the treatment table. All adults. Needs pipeline 02.


-- @query: 03a_vent_treatment_strings
-- Ventilation-related treatment strings (D06)
SELECT
  t.treatmentstring,
  COUNT(DISTINCT t.patientunitstayid) AS n_patients
FROM `physionet-data.eicu_crd.treatment` t
JOIN `evocative-ethos-471602-r3.base.eicu_cohort` c USING (patientunitstayid)
WHERE REGEXP_CONTAINS(LOWER(t.treatmentstring),
        r'ventilat|intubat|endotracheal|cpap|bipap|high flow|tracheostomy')
GROUP BY t.treatmentstring
ORDER BY n_patients DESC;


-- @query: 03b_vent_string_classification
-- Treatment strings by class used in the pipeline (D06)
WITH s AS (
  SELECT
    t.treatmentstring,
    LOWER(t.treatmentstring)            AS ls,
    COUNT(DISTINCT t.patientunitstayid) AS n_patients
  FROM `physionet-data.eicu_crd.treatment` t
  JOIN `evocative-ethos-471602-r3.base.eicu_cohort` c USING (patientunitstayid)
  WHERE REGEXP_CONTAINS(LOWER(t.treatmentstring),
          r'ventilat|intubat|endotracheal|cpap|bipap|high flow|tracheostomy')
  GROUP BY t.treatmentstring
)
SELECT
  CASE
    WHEN REGEXP_CONTAINS(ls, r'non-invasive|bipap')                                  THEN '3_niv'
    WHEN REGEXP_CONTAINS(ls, r'cpap/peep|tracheal suctioning')                       THEN '4_ambiguous'
    WHEN REGEXP_CONTAINS(ls, r'tracheostomy|trach collar')                           THEN '5_trach'
    WHEN REGEXP_CONTAINS(ls, r'endotracheal tube removal|extubat')                   THEN '2_supporting'
    WHEN REGEXP_CONTAINS(ls, r'ventilator weaning|lung recruitment|prone position')  THEN '2_supporting'
    WHEN REGEXP_CONTAINS(ls, r'mechanical ventilation|endotracheal tube|intubat')    THEN '1_invasive'
    WHEN REGEXP_CONTAINS(ls, r'oxygen therapy|high flow')                            THEN '6_oxygen'
    ELSE '7_other'
  END AS vent_class,
  treatmentstring,
  n_patients
FROM s
ORDER BY vent_class, n_patients DESC;


-- @query: 03c_imv_timing_treatment_only
-- Ventilation timing from the treatment table alone (D06, D08)
WITH tx AS (
  SELECT t.patientunitstayid, t.treatmentoffset, LOWER(t.treatmentstring) AS ls
  FROM `physionet-data.eicu_crd.treatment` t
  JOIN `evocative-ethos-471602-r3.base.eicu_cohort` c USING (patientunitstayid)
),
cls AS (
  SELECT patientunitstayid, treatmentoffset,
    CASE
      WHEN REGEXP_CONTAINS(ls, r'non-invasive|bipap')                                 THEN '3_niv'
      WHEN REGEXP_CONTAINS(ls, r'cpap/peep|tracheal suctioning')                      THEN '4_ambiguous'
      WHEN REGEXP_CONTAINS(ls, r'tracheostomy|trach collar')                          THEN '5_trach'
      WHEN REGEXP_CONTAINS(ls, r'endotracheal tube removal|extubat')                  THEN '2_supporting'
      WHEN REGEXP_CONTAINS(ls, r'ventilator weaning|lung recruitment|prone position') THEN '2_supporting'
      WHEN REGEXP_CONTAINS(ls, r'mechanical ventilation|endotracheal tube|intubat')   THEN '1_invasive'
      ELSE NULL
    END AS vent_class
  FROM tx
),
per_patient AS (
  SELECT patientunitstayid,
    MIN(IF(vent_class = '1_invasive',   treatmentoffset, NULL)) AS first_invasive,
    MIN(IF(vent_class = '2_supporting', treatmentoffset, NULL)) AS first_supporting,
    MIN(IF(vent_class = '5_trach',      treatmentoffset, NULL)) AS first_trach,
    MIN(IF(vent_class = '3_niv',        treatmentoffset, NULL)) AS first_niv
  FROM cls
  WHERE vent_class IS NOT NULL
  GROUP BY patientunitstayid
)
SELECT
  (SELECT COUNT(*) FROM `evocative-ethos-471602-r3.base.eicu_cohort`) AS n_adults,
  (SELECT COUNT(DISTINCT patientunitstayid) FROM tx)              AS n_adults_with_any_treatment_entry,
  COUNTIF(first_invasive IS NOT NULL)                             AS n_any_invasive,
  COUNTIF(first_invasive <= 0)                                    AS n_inv_at_or_before_admit,
  COUNTIF(first_invasive > 0    AND first_invasive <= 60)         AS n_inv_0_1h,
  COUNTIF(first_invasive > 60   AND first_invasive <= 1440)       AS n_inv_1_24h,
  COUNTIF(first_invasive > 1440 AND first_invasive <= 4320)       AS n_inv_24_72h,
  COUNTIF(first_invasive > 4320)                                  AS n_inv_after_72h,
  COUNTIF(first_invasive IS NULL AND first_supporting IS NOT NULL) AS n_supporting_only_no_invasive,
  COUNTIF(first_trach IS NOT NULL)                                AS n_any_trach,
  COUNTIF(first_trach <= 60)                                      AS n_trach_within_1h_of_admit,
  COUNTIF(first_niv IS NOT NULL)                                  AS n_any_niv,
  COUNTIF(first_niv IS NOT NULL AND first_invasive IS NULL)       AS n_niv_never_invasive
FROM per_patient;


-- @query: 03d_hospital_treatment_usage
-- Hospitals by share of patients with any treatment entry (D05)
WITH tx_any AS (
  SELECT DISTINCT patientunitstayid FROM `physionet-data.eicu_crd.treatment`
),
tx_inv AS (
  SELECT DISTINCT patientunitstayid
  FROM `physionet-data.eicu_crd.treatment`
  WHERE REGEXP_CONTAINS(LOWER(treatmentstring), r'mechanical ventilation|endotracheal tube|intubat')
    AND NOT REGEXP_CONTAINS(LOWER(treatmentstring), r'non-invasive|endotracheal tube removal')
),
per_hosp AS (
  SELECT
    c.hospitalid,
    COUNT(*)                                  AS n_adults,
    COUNTIF(ta.patientunitstayid IS NOT NULL) AS n_with_tx,
    COUNTIF(ti.patientunitstayid IS NOT NULL) AS n_invasive
  FROM `evocative-ethos-471602-r3.base.eicu_cohort` c
  LEFT JOIN tx_any ta USING (patientunitstayid)
  LEFT JOIN tx_inv ti USING (patientunitstayid)
  GROUP BY c.hospitalid
)
SELECT
  CASE
    WHEN n_with_tx = 0              THEN 'a: 0% (never uses table)'
    WHEN n_with_tx / n_adults < 0.5 THEN 'b: 1-49%'
    WHEN n_with_tx / n_adults < 0.8 THEN 'c: 50-79%'
    WHEN n_with_tx / n_adults < 0.95 THEN 'd: 80-94%'
    ELSE                                 'e: 95-100%'
  END                                                         AS tx_usage_group,
  COUNT(*)                                                    AS n_hospitals,
  SUM(n_adults)                                               AS n_adults,
  SUM(n_with_tx)                                              AS n_adults_with_tx,
  SUM(n_invasive)                                             AS n_invasive,
  ROUND(SAFE_DIVIDE(SUM(n_invasive), SUM(n_adults)) * 100, 1) AS pct_invasive_of_adults
FROM per_hosp
GROUP BY tx_usage_group
ORDER BY tx_usage_group;


-- @query: 03e_insertion_vs_mech_vent_entry
-- First mechanical-ventilation entry vs tube insertion entry (D08)
WITH tx AS (
  SELECT t.patientunitstayid, t.treatmentoffset, LOWER(t.treatmentstring) AS ls
  FROM `physionet-data.eicu_crd.treatment` t
  JOIN `evocative-ethos-471602-r3.base.eicu_cohort` c USING (patientunitstayid)
),
per_patient AS (
  SELECT patientunitstayid,
    MIN(IF(REGEXP_CONTAINS(ls, r'mechanical ventilation|endotracheal tube|intubat')
           AND NOT REGEXP_CONTAINS(ls, r'non-invasive|endotracheal tube removal'),
           treatmentoffset, NULL))                                    AS first_invasive,
    MIN(IF(REGEXP_CONTAINS(ls, r'mechanical ventilation')
           AND NOT REGEXP_CONTAINS(ls, r'non-invasive'),
           treatmentoffset, NULL))                                    AS first_mv,
    MIN(IF(REGEXP_CONTAINS(ls, r'endotracheal tube\|insertion'),
           treatmentoffset, NULL))                                    AS first_ett_insertion
  FROM tx
  GROUP BY patientunitstayid
)
SELECT
  CASE
    WHEN first_invasive <= 60   THEN 'a: first invasive <= 1 h'
    WHEN first_invasive <= 1440 THEN 'b: 1-24 h'
    WHEN first_invasive <= 4320 THEN 'c: 24-72 h'
    ELSE                             'd: > 72 h'
  END                                                                AS first_invasive_group,
  COUNT(*)                                                           AS n_ventilated,
  COUNTIF(first_ett_insertion IS NOT NULL)                           AS n_with_insertion_entry,
  COUNTIF(first_ett_insertion <= 0)                                  AS n_insertion_at_or_before_admit,
  COUNTIF(first_ett_insertion IS NOT NULL AND first_mv IS NOT NULL)  AS n_with_both,
  COUNTIF(first_mv - first_ett_insertion BETWEEN -60 AND 60)         AS n_mv_within_1h_of_insertion,
  COUNTIF(first_mv - first_ett_insertion > 60)                       AS n_mv_charted_gt1h_after_insertion,
  COUNTIF(first_mv - first_ett_insertion < -60)                      AS n_mv_charted_gt1h_before_insertion,
  APPROX_QUANTILES(first_mv - first_ett_insertion, 4)                AS lag_minutes_quartiles
FROM per_patient
WHERE first_invasive IS NOT NULL
GROUP BY first_invasive_group
ORDER BY first_invasive_group;
