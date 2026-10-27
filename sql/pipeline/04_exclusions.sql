-- Pipeline 04: remaining exclusions and final eligibility (D09, D10, D26-D31).
-- Builds base.eicu_tte_cohort. Analysis cohort: eligible_a or eligible_b.

CREATE OR REPLACE TABLE `evocative-ethos-471602-r3.base.eicu_tte_cohort` AS
WITH

-- Within 6 h of ICU admission (D29)
care_limitation_at_t0 AS (
  SELECT DISTINCT patientunitstayid
  FROM `physionet-data.eicu_crd.careplangeneral`
  WHERE LOWER(cplgroup) = 'care limitation'
    AND LOWER(cplitemvalue) IN ('do not resuscitate', 'no cpr', 'no intubation',
                                'comfort measures only', 'no augmentation of care',
                                'no vasopressors/inotropes', 'no cardioversion')
    AND cplitemoffset <= 360
),

chronic_trach_careplan AS (
  SELECT DISTINCT patientunitstayid
  FROM `physionet-data.eicu_crd.careplangeneral`
  WHERE LOWER(cplgroup) = 'airway'
    AND LOWER(cplitemvalue) = 'intubated/trach-chronic'
),

-- Chronic: timing ignored (D30)
chronic_lung AS (
  SELECT patientunitstayid
  FROM `physionet-data.eicu_crd.pasthistory`
  WHERE REGEXP_CONTAINS(LOWER(pasthistorypath),
          r'/pulmonary/(copd|home oxygen|restrictive disease|respiratory failure|sarcoidosis)/')
  UNION DISTINCT
  SELECT patientunitstayid
  FROM `physionet-data.eicu_crd.diagnosis`
  WHERE REGEXP_CONTAINS(LOWER(diagnosisstring), r'copd|chronic respiratory failure')
),

asthma AS (
  SELECT patientunitstayid
  FROM `physionet-data.eicu_crd.pasthistory`
  WHERE REGEXP_CONTAINS(LOWER(pasthistorypath), r'/pulmonary/asthma/')
  UNION DISTINCT
  SELECT patientunitstayid
  FROM `physionet-data.eicu_crd.diagnosis`
  WHERE REGEXP_CONTAINS(LOWER(diagnosisstring), r'asthma')
),

flags AS (
  SELECT
    k.* EXCEPT (exclusion_reason),
    k.exclusion_reason                                                AS kidney_exclusion_reason,

    -- Option A: stage 0; Option B: stage 0-1 at time zero (D26)
    k.exclusion_reason IS NULL                                        AS kidney_ok_a,
    (k.exclusion_reason IS NULL
       OR (k.exclusion_reason LIKE '5:%' AND k.t0_aki_stage = 1))     AS kidney_ok_b,

    IFNULL(k.imv_status = 'imv' AND k.imv_start <= 60, FALSE)         AS ventilated_on_arrival,
    k.imv_status = 'ambiguous'                                        AS ambiguous_ventilation,
    (IFNULL(k.first_trach_tx <= 60, FALSE)
       OR ct.patientunitstayid IS NOT NULL)                           AS chronic_trach,
    cl.patientunitstayid IS NOT NULL                                  AS care_limited_at_t0,
    lung.patientunitstayid IS NOT NULL                                AS chronic_lung_disease,
    a.patientunitstayid IS NOT NULL                                   AS has_asthma
  FROM `evocative-ethos-471602-r3.base.eicu_kidney_v1` k
  LEFT JOIN care_limitation_at_t0  cl USING (patientunitstayid)
  LEFT JOIN chronic_trach_careplan ct USING (patientunitstayid)
  LEFT JOIN (SELECT DISTINCT patientunitstayid FROM chronic_lung) lung USING (patientunitstayid)
  LEFT JOIN (SELECT DISTINCT patientunitstayid FROM asthma)       a    USING (patientunitstayid)
)

SELECT
  *,
  (ventilated_on_arrival OR ambiguous_ventilation OR kidney_transplant
     OR chronic_trach OR care_limited_at_t0 OR chronic_lung_disease)   AS other_excluded,
  kidney_ok_a AND NOT (ventilated_on_arrival OR ambiguous_ventilation OR kidney_transplant
     OR chronic_trach OR care_limited_at_t0 OR chronic_lung_disease)   AS eligible_a,
  kidney_ok_b AND NOT (ventilated_on_arrival OR ambiguous_ventilation OR kidney_transplant
     OR chronic_trach OR care_limited_at_t0 OR chronic_lung_disease)   AS eligible_b
FROM flags;
