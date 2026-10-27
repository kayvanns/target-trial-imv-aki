-- Pipeline 03: kidney exclusions, baseline creatinine, AKI stage at time zero
-- (D11, D13, D16, D20-D26). Builds base.eicu_kidney_v1 (primary cohort) and
-- base.eicu_eligible_v1 (no kidney exclusion, stage 0).

-- Labs up to 6 h after ICU admission count as time zero (D11)
DECLARE t0_grace_min INT64 DEFAULT 360;

CREATE OR REPLACE TABLE `evocative-ethos-471602-r3.base.eicu_kidney_v1` AS
WITH

cohort AS (
  SELECT *
  FROM `evocative-ethos-471602-r3.base.eicu_cohort`
  WHERE hosp_tx_pct >= 0.8
),

-- ESRD / chronic dialysis, any of 4 sources (D20)
esrd AS (
  SELECT patientunitstayid
  FROM `physionet-data.eicu_crd.pasthistory`
  WHERE REGEXP_CONTAINS(LOWER(pasthistorypath),
          r'renal failure - hemodialysis|renal failure - peritoneal dialysis')
  UNION DISTINCT
  SELECT patientunitstayid
  FROM `physionet-data.eicu_crd.apacheapsvar`
  WHERE dialysis = 1
  UNION DISTINCT
  SELECT patientunitstayid
  FROM `physionet-data.eicu_crd.diagnosis`
  WHERE REGEXP_CONTAINS(LOWER(diagnosisstring),
          r'esrd|end stage renal|stage 5|dialysis associated|dialysis access')
     OR REGEXP_CONTAINS(IFNULL(icd9code, ''),
          r'(^|,\s*)(585\.5|585\.6|N18\.5|N18\.6|V45\.1|Z99\.2)')
  UNION DISTINCT
  SELECT patientunitstayid
  FROM `physionet-data.eicu_crd.treatment`
  WHERE REGEXP_CONTAINS(LOWER(treatmentstring),
          r'for chronic renal failure|peritoneal dialysis')
),

-- range_code: 1 = creatinine 1-2, 2 = 2-3, 3 = 3-4, 4 = 4-5, 5 = > 5
ckd_pasthistory AS (
  SELECT
    patientunitstayid,
    MAX(CASE
          WHEN REGEXP_CONTAINS(LOWER(pasthistorypath), r'creatinine > 5') THEN 5
          WHEN REGEXP_CONTAINS(LOWER(pasthistorypath), r'creatinine 4-5') THEN 4
          WHEN REGEXP_CONTAINS(LOWER(pasthistorypath), r'creatinine 3-4') THEN 3
          WHEN REGEXP_CONTAINS(LOWER(pasthistorypath), r'creatinine 2-3') THEN 2
          WHEN REGEXP_CONTAINS(LOWER(pasthistorypath), r'creatinine 1-2') THEN 1
        END) AS range_code
  FROM `physionet-data.eicu_crd.pasthistory`
  WHERE REGEXP_CONTAINS(LOWER(pasthistorypath),
          r'renal insufficiency|renal failure- not currently dialyzed|renal failure - not currently dialyzed')
  GROUP BY patientunitstayid
),

ckd_diagnosis AS (
  SELECT DISTINCT patientunitstayid
  FROM `physionet-data.eicu_crd.diagnosis`
  WHERE REGEXP_CONTAINS(LOWER(diagnosisstring),
          r'chronic kidney disease|chronic renal insufficiency|anemia of renal disease')
),

kidney_transplant AS (
  SELECT patientunitstayid
  FROM `physionet-data.eicu_crd.pasthistory`
  WHERE REGEXP_CONTAINS(LOWER(pasthistorypath), r'renal transplant')
  UNION DISTINCT
  SELECT patientunitstayid
  FROM `physionet-data.eicu_crd.diagnosis`
  WHERE REGEXP_CONTAINS(LOWER(diagnosisstring), r'kidney transplant')
     OR REGEXP_CONTAINS(IFNULL(icd9code, ''), r'(^|,\s*)(V42\.0|Z94\.0|996\.81)')
),

-- RRT: treatments (not catheter insertion) and RRT fluid removal (D16)
rrt_events AS (
  SELECT patientunitstayid, treatmentoffset AS t
  FROM `physionet-data.eicu_crd.treatment`
  WHERE REGEXP_CONTAINS(LOWER(treatmentstring),
          r'dialys|crrt|cvvh|c v v h|hemofiltration|ultrafiltration|renal replacement')
    AND NOT REGEXP_CONTAINS(LOWER(treatmentstring), r'catheter')
  UNION ALL
  SELECT patientunitstayid, intakeoutputoffset AS t
  FROM `physionet-data.eicu_crd.intakeoutput`
  WHERE REGEXP_CONTAINS(LOWER(cellpath), r'output')
    AND REGEXP_CONTAINS(LOWER(celllabel),
          r'hemofiltration|dialys|fluid removal|ultrafiltrat|crrt|cvvh')
),

first_rrt AS (
  SELECT r.patientunitstayid, MIN(r.t) AS first_rrt_offset
  FROM rrt_events r
  JOIN cohort USING (patientunitstayid)
  GROUP BY r.patientunitstayid
),

-- Before any RRT, from 7 days before ICU admission (D13, D16)
creatinine AS (
  SELECT l.patientunitstayid, l.labresultoffset AS t, l.labresult AS value
  FROM `physionet-data.eicu_crd.lab` l
  JOIN cohort USING (patientunitstayid)
  LEFT JOIN first_rrt r USING (patientunitstayid)
  WHERE l.labname = 'creatinine'
    AND l.labresult BETWEEN 0.2 AND 20
    AND l.labresultoffset >= -10080
    AND (r.first_rrt_offset IS NULL OR l.labresultoffset < r.first_rrt_offset)
),

creatinine_summary AS (
  SELECT
    patientunitstayid,
    MIN(IF(t <= t0_grace_min, value, NULL))                       AS lowest_upto_t0,
    MIN(IF(t BETWEEN -2880 AND t0_grace_min, value, NULL))
                                                                  AS lowest_48h_before_t0,
    -- Time-zero creatinine; ties at the same minute -> higher value (D23)
    ARRAY_AGG(IF(t BETWEEN -1440 AND t0_grace_min, value, NULL) IGNORE NULLS
              ORDER BY t DESC, value DESC LIMIT 1)[SAFE_OFFSET(0)] AS t0_creat
  FROM creatinine
  GROUP BY patientunitstayid
),

patients AS (
  SELECT
    c.*,
    e.patientunitstayid IS NOT NULL                                   AS is_esrd,
    (cp.patientunitstayid IS NOT NULL OR cd.patientunitstayid IS NOT NULL) AS is_ckd,
    cp.range_code                                                     AS ckd_range_code,
    kt.patientunitstayid IS NOT NULL                                  AS kidney_transplant,
    r.first_rrt_offset,
    s.lowest_upto_t0,
    s.lowest_48h_before_t0,
    s.t0_creat,
    -- Expected normal creatinine: MDRD (IDMS, no race term) at eGFR 75
    POW(75 / (175 * POW(c.age_num, -0.203)
                  * IF(c.gender = 'Female', 0.742, 1)), -1 / 1.154)   AS expected_normal_creat
  FROM cohort c
  LEFT JOIN (SELECT DISTINCT patientunitstayid FROM esrd)              e  USING (patientunitstayid)
  LEFT JOIN ckd_pasthistory                                            cp USING (patientunitstayid)
  LEFT JOIN ckd_diagnosis                                              cd USING (patientunitstayid)
  LEFT JOIN (SELECT DISTINCT patientunitstayid FROM kidney_transplant) kt USING (patientunitstayid)
  LEFT JOIN first_rrt                                                  r  USING (patientunitstayid)
  LEFT JOIN creatinine_summary                                         s  USING (patientunitstayid)
),

-- Baseline creatinine (D22)
with_baseline AS (
  SELECT
    *,
    CASE
      WHEN is_ckd AND ckd_range_code = 1 THEN 1.5
      WHEN is_ckd AND ckd_range_code = 2 THEN 2.5
      WHEN is_ckd AND ckd_range_code = 3 THEN 3.5
      WHEN is_ckd                        THEN NULL
      WHEN lowest_upto_t0 < 1.1          THEN lowest_upto_t0
      ELSE expected_normal_creat
    END AS baseline_creat,
    CASE
      WHEN is_ckd AND ckd_range_code BETWEEN 1 AND 3 THEN 'CKD: recorded range midpoint'
      WHEN is_ckd                                    THEN NULL
      WHEN lowest_upto_t0 < 1.1                      THEN 'measured (lowest up to time zero)'
      ELSE                                                'expected normal (MDRD)'
    END AS baseline_source
  FROM patients
),

-- KDIGO stage at time zero (D24)
with_stage AS (
  SELECT
    *,
    CASE
      WHEN first_rrt_offset <= t0_grace_min                           THEN 3
      WHEN t0_creat IS NULL OR baseline_creat IS NULL                 THEN NULL
      WHEN t0_creat >= 3.0 * baseline_creat
        OR (t0_creat >= 4.0
            AND (t0_creat >= 1.5 * baseline_creat
                 OR t0_creat - lowest_48h_before_t0 >= 0.3))          THEN 3
      WHEN t0_creat >= 2.0 * baseline_creat                           THEN 2
      WHEN t0_creat >= 1.5 * baseline_creat
        OR t0_creat - lowest_48h_before_t0 >= 0.3                     THEN 1
      ELSE 0
    END AS t0_aki_stage
  FROM with_baseline
)

SELECT
  *,
  0 AS t0_offset,
  CASE
    WHEN is_esrd                                          THEN '1: ESRD / chronic dialysis'
    WHEN is_ckd AND ckd_range_code >= 4                   THEN '2: severe CKD (usual creatinine > 4)'
    WHEN is_ckd AND ckd_range_code IS NULL                THEN '3: CKD without recorded usual creatinine'
    WHEN t0_aki_stage IS NULL                             THEN '4: no creatinine near time zero'
    WHEN t0_aki_stage >= 1                                THEN '5: AKI at time zero (stage >= 1)'
    ELSE NULL
  END AS exclusion_reason
FROM with_stage;

CREATE OR REPLACE TABLE `evocative-ethos-471602-r3.base.eicu_eligible_v1` AS
SELECT
  * EXCEPT (is_esrd, lowest_upto_t0, lowest_48h_before_t0,
            expected_normal_creat, exclusion_reason)
FROM `evocative-ethos-471602-r3.base.eicu_kidney_v1`
WHERE exclusion_reason IS NULL;
