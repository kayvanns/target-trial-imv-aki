-- Checks 07: non-kidney exclusions and cohort flow. Needs pipelines 03-04.


-- @query: 07a_exclusion_discovery
-- DNR, chronic lung disease and tracheostomy entries (D28-D31)
WITH elig AS (
  SELECT patientunitstayid
  FROM `evocative-ethos-471602-r3.base.eicu_eligible_v1`
  WHERE NOT IFNULL(imv_start <= 60, FALSE)
    AND imv_status != 'ambiguous'
),
care_plan AS (
  SELECT
    'care plan'                                        AS source,
    CONCAT(cp.cplgroup, ' | ', cp.cplitemvalue)        AS item,
    COUNT(DISTINCT cp.patientunitstayid)               AS n_patients,
    COUNT(DISTINCT IF(cp.cplitemoffset <= 360, cp.patientunitstayid, NULL)) AS n_by_6h
  FROM `physionet-data.eicu_crd.careplangeneral` cp
  JOIN elig USING (patientunitstayid)
  WHERE REGEXP_CONTAINS(LOWER(cp.cplgroup), r'care limitation|code status')
     OR REGEXP_CONTAINS(LOWER(cp.cplitemvalue), r'dnr|cpr|resusc|intubat|comfort|palliat|hospice')
  GROUP BY cp.cplgroup, cp.cplitemvalue
),
past_history AS (
  SELECT
    'past history'                                     AS source,
    p.pasthistorypath                                  AS item,
    COUNT(DISTINCT p.patientunitstayid)                AS n_patients,
    COUNT(DISTINCT IF(p.pasthistoryoffset <= 360, p.patientunitstayid, NULL)) AS n_by_6h
  FROM `physionet-data.eicu_crd.pasthistory` p
  JOIN elig USING (patientunitstayid)
  WHERE REGEXP_CONTAINS(LOWER(p.pasthistorypath),
          r'pulmonary|copd|asthma|lung|emphysema|bronch|oxygen|trach|ventilat|fibrosis|sarcoid')
  GROUP BY p.pasthistorypath
),
diagnoses AS (
  SELECT
    'diagnosis'                                        AS source,
    d.diagnosisstring                                  AS item,
    COUNT(DISTINCT d.patientunitstayid)                AS n_patients,
    COUNT(DISTINCT IF(d.diagnosisoffset <= 360, d.patientunitstayid, NULL)) AS n_by_6h
  FROM `physionet-data.eicu_crd.diagnosis` d
  JOIN elig USING (patientunitstayid)
  WHERE REGEXP_CONTAINS(LOWER(d.diagnosisstring),
          r'copd|chronic obstructive|emphysema|chronic bronchitis|asthma|interstitial|pulmonary fibrosis|chronic respiratory failure|tracheostomy|home oxygen|ventilator dependen|comfort|palliat|dnr|do not resus')
  GROUP BY d.diagnosisstring
)
SELECT * FROM (
  SELECT * FROM care_plan
  UNION ALL SELECT * FROM past_history
  UNION ALL SELECT * FROM diagnoses
)
WHERE n_patients >= 5
ORDER BY source, n_patients DESC;


-- @query: 07b_cohort_flow_option_a
-- Cohort flow, Option A (D20-D31)
SELECT
  CASE
    WHEN kidney_exclusion_reason IS NOT NULL   THEN CONCAT('0', kidney_exclusion_reason)
    WHEN ventilated_on_arrival                 THEN '06: ventilated on arrival'
    WHEN ambiguous_ventilation                 THEN '07: ambiguous ventilation status'
    WHEN kidney_transplant                     THEN '08: kidney transplant'
    WHEN chronic_trach                         THEN '09: chronic tracheostomy'
    WHEN care_limited_at_t0                    THEN '10: DNR / care limitation at time zero'
    WHEN chronic_lung_disease                  THEN '11: COPD / chronic lung disease'
    ELSE                                            '12: ELIGIBLE (Option A)'
  END                                          AS step,
  COUNT(*)                                     AS n_patients,
  COUNTIF(has_asthma)                          AS n_with_asthma
FROM `evocative-ethos-471602-r3.base.eicu_tte_cohort`
GROUP BY step
ORDER BY step;


-- @query: 07c_cohort_flow_option_b
-- Cohort flow, Option B (D26)
SELECT
  CASE
    WHEN NOT kidney_ok_b                       THEN CONCAT('0', REPLACE(kidney_exclusion_reason,
                                                    'AKI at time zero (stage >= 1)',
                                                    'AKI at time zero (stage >= 2)'))
    WHEN ventilated_on_arrival                 THEN '06: ventilated on arrival'
    WHEN ambiguous_ventilation                 THEN '07: ambiguous ventilation status'
    WHEN kidney_transplant                     THEN '08: kidney transplant'
    WHEN chronic_trach                         THEN '09: chronic tracheostomy'
    WHEN care_limited_at_t0                    THEN '10: DNR / care limitation at time zero'
    WHEN chronic_lung_disease                  THEN '11: COPD / chronic lung disease'
    ELSE                                            '12: ELIGIBLE (Option B)'
  END                                          AS step,
  COUNT(*)                                     AS n_patients,
  COUNTIF(t0_aki_stage = 1)                    AS n_stage1_at_t0,
  COUNTIF(has_asthma)                          AS n_with_asthma
FROM `evocative-ethos-471602-r3.base.eicu_tte_cohort`
GROUP BY step
ORDER BY step;
