-- Checks 05: creatinine and urine output. Primary cohort. Needs pipeline 02.


-- @query: 05a_creatinine_labs
-- Creatinine lab names, units and values (D13)
WITH cohort AS (
  SELECT patientunitstayid
  FROM `evocative-ethos-471602-r3.base.eicu_cohort`
  WHERE hosp_tx_pct >= 0.8
)
SELECT
  l.labname,
  l.labmeasurenamesystem                     AS unit,
  COUNT(DISTINCT l.patientunitstayid)        AS n_patients,
  COUNT(*)                                   AS n_results,
  COUNTIF(l.labresult IS NULL)               AS n_missing_value,
  COUNTIF(l.labresult <= 0)                  AS n_le_zero,
  COUNTIF(l.labresult > 20)                  AS n_gt_20,
  APPROX_QUANTILES(l.labresult, 4)           AS value_min_q1_median_q3_max
FROM `physionet-data.eicu_crd.lab` l
JOIN cohort USING (patientunitstayid)
WHERE LOWER(l.labname) LIKE '%creat%'
GROUP BY l.labname, l.labmeasurenamesystem
ORDER BY n_patients DESC;


-- @query: 05b_creatinine_timing
-- Creatinine timing and daily ICU coverage (D13, D18)
WITH cohort AS (
  SELECT patientunitstayid, unitdischargeoffset
  FROM `evocative-ethos-471602-r3.base.eicu_cohort`
  WHERE hosp_tx_pct >= 0.8
),
cr_raw AS (
  SELECT l.patientunitstayid, l.labresultoffset AS t, l.labresult AS v
  FROM `physionet-data.eicu_crd.lab` l
  JOIN cohort USING (patientunitstayid)
  WHERE l.labname = 'creatinine' AND l.labresult IS NOT NULL
),
range_check AS (
  SELECT
    COUNT(*)                         AS n_results_nonmissing,
    COUNTIF(v < 0.2)                 AS n_values_lt_0_2,
    COUNTIF(v > 15 AND v <= 20)      AS n_values_15_to_20,
    COUNTIF(v > 20)                  AS n_values_gt_20
  FROM cr_raw
),
cr AS (
  SELECT * FROM cr_raw WHERE v > 0 AND v <= 20
),
per_patient AS (
  SELECT
    c.patientunitstayid,
    COUNTIF(cr.t < 0)                                   AS n_pre_icu,
    COUNTIF(cr.t BETWEEN -1440 AND 360)                 AS n_around_admit,
    COUNTIF(cr.t BETWEEN 0 AND 1440)                    AS n_first_24h,
    COUNT(DISTINCT IF(cr.t BETWEEN 0 AND LEAST(10079, c.unitdischargeoffset),
                      DIV(cr.t, 1440), NULL))                AS n_days_with_cr_7d,
    LEAST(7, GREATEST(1, CAST(CEIL(c.unitdischargeoffset / 1440) AS INT64))) AS icu_days_7d,
    COUNTIF(cr.t > c.unitdischargeoffset AND cr.t <= 10080)   AS n_post_icu_cr_7d,
    COUNTIF(cr.t > c.unitdischargeoffset)                     AS n_post_icu_cr_any,
    c.unitdischargeoffset < 10080                             AS discharged_before_day7
  FROM cohort c
  LEFT JOIN cr USING (patientunitstayid)
  GROUP BY c.patientunitstayid, c.unitdischargeoffset
)
SELECT
  COUNT(*)                                                  AS n_patients,
  COUNTIF(n_pre_icu > 0)                                    AS n_with_pre_icu_cr,
  COUNTIF(n_around_admit > 0)                               AS n_with_cr_24h_before_to_6h_after,
  COUNTIF(n_first_24h > 0)                                  AS n_with_cr_first_24h,
  COUNTIF(n_days_with_cr_7d = 0)                            AS n_no_icu_cr_first_7d,
  ROUND(100 * SAFE_DIVIDE(SUM(n_days_with_cr_7d), SUM(icu_days_7d)), 1) AS pct_icu_days_with_cr_first_7d,
  APPROX_QUANTILES(icu_days_7d, 4)                          AS icu_days_first_7d_quartiles,
  COUNTIF(discharged_before_day7)                           AS n_icu_discharge_before_day7,
  COUNTIF(discharged_before_day7 AND n_post_icu_cr_7d > 0)  AS n_of_those_with_post_icu_cr_by_day7,
  COUNTIF(n_post_icu_cr_any > 0)                            AS n_with_any_post_icu_cr,
  ANY_VALUE(r.n_results_nonmissing)                         AS n_results_nonmissing,
  ANY_VALUE(r.n_values_lt_0_2)                              AS n_values_lt_0_2,
  ANY_VALUE(r.n_values_15_to_20)                            AS n_values_15_to_20,
  ANY_VALUE(r.n_values_gt_20)                               AS n_values_gt_20
FROM per_patient
CROSS JOIN range_check r;


-- @query: 05c_creatinine_by_hospital
-- Hospitals by daily creatinine coverage (D14)
WITH cohort AS (
  SELECT patientunitstayid, hospitalid, unitdischargeoffset
  FROM `evocative-ethos-471602-r3.base.eicu_cohort`
  WHERE hosp_tx_pct >= 0.8
),
cr AS (
  SELECT l.patientunitstayid, l.labresultoffset AS t
  FROM `physionet-data.eicu_crd.lab` l
  JOIN cohort USING (patientunitstayid)
  WHERE l.labname = 'creatinine'
    AND l.labresult >= 0.2 AND l.labresult <= 20
),
per_patient AS (
  SELECT
    c.patientunitstayid,
    c.hospitalid,
    COUNTIF(cr.t BETWEEN -1440 AND 360) > 0             AS has_cr_around_admit,
    COUNTIF(cr.t BETWEEN 0 AND 1440) > 0                AS has_cr_first_24h,
    COUNT(DISTINCT IF(cr.t BETWEEN 0 AND LEAST(10079, c.unitdischargeoffset),
                      DIV(cr.t, 1440), NULL))           AS n_days_with_cr,
    LEAST(7, GREATEST(1, CAST(CEIL(c.unitdischargeoffset / 1440) AS INT64))) AS icu_days
  FROM cohort c
  LEFT JOIN cr USING (patientunitstayid)
  GROUP BY c.patientunitstayid, c.hospitalid, c.unitdischargeoffset
),
per_hosp AS (
  SELECT
    hospitalid,
    COUNT(*)                                AS n_patients,
    COUNTIF(has_cr_around_admit)            AS n_cr_around_admit,
    COUNTIF(has_cr_first_24h)               AS n_cr_first_24h,
    SUM(n_days_with_cr)                     AS cr_days,
    SUM(icu_days)                           AS icu_days,
    SAFE_DIVIDE(SUM(n_days_with_cr), SUM(icu_days)) AS daily_cov
  FROM per_patient
  GROUP BY hospitalid
)
SELECT
  CASE
    WHEN daily_cov < 0.50 THEN 'a: < 50%'
    WHEN daily_cov < 0.70 THEN 'b: 50-69%'
    WHEN daily_cov < 0.85 THEN 'c: 70-84%'
    WHEN daily_cov < 0.95 THEN 'd: 85-94%'
    ELSE                       'e: 95-100%'
  END                                                          AS daily_coverage_band,
  COUNT(*)                                                     AS n_hospitals,
  COUNTIF(n_patients < 20)                                     AS n_hosp_under_20_patients,
  SUM(n_patients)                                              AS n_patients,
  ROUND(100 * SAFE_DIVIDE(SUM(n_cr_around_admit), SUM(n_patients)), 1) AS pct_cr_24h_before_to_6h_after,
  ROUND(100 * SAFE_DIVIDE(SUM(n_cr_first_24h),    SUM(n_patients)), 1) AS pct_cr_first_24h,
  ROUND(100 * SAFE_DIVIDE(SUM(cr_days),           SUM(icu_days)),   1) AS pct_icu_days_with_cr
FROM per_hosp
GROUP BY daily_coverage_band
ORDER BY daily_coverage_band;


-- @query: 05d_urine_output_labels
-- Output labels in intake/output (D15)
WITH cohort AS (
  SELECT patientunitstayid
  FROM `evocative-ethos-471602-r3.base.eicu_cohort`
  WHERE hosp_tx_pct >= 0.8
)
SELECT
  io.celllabel,
  COUNT(DISTINCT io.patientunitstayid)                         AS n_patients,
  COUNT(*)                                                     AS n_rows,
  COUNT(DISTINCT io.cellpath)                                  AS n_distinct_paths,
  ANY_VALUE(io.cellpath)                                       AS example_path,
  LOGICAL_OR(REGEXP_CONTAINS(LOWER(io.cellpath), r'urine'))    AS path_mentions_urine,
  COUNTIF(io.cellvaluenumeric < 0)                             AS n_negative,
  COUNTIF(io.cellvaluenumeric > 2000)                          AS n_gt_2000ml,
  APPROX_QUANTILES(io.cellvaluenumeric, 4)                     AS ml_min_q1_median_q3_max
FROM `physionet-data.eicu_crd.intakeoutput` io
JOIN cohort USING (patientunitstayid)
WHERE REGEXP_CONTAINS(LOWER(io.cellpath), r'output')
GROUP BY io.celllabel
HAVING COUNT(DISTINCT io.patientunitstayid) >= 20
ORDER BY n_patients DESC
LIMIT 80;


-- @query: 05d2_urine_label_classification
-- Output labels by class (D15, D16)
WITH cohort AS (
  SELECT patientunitstayid
  FROM `evocative-ethos-471602-r3.base.eicu_cohort`
  WHERE hosp_tx_pct >= 0.8
),
labels AS (
  SELECT
    io.celllabel,
    LOWER(io.celllabel)                       AS l,
    COUNT(DISTINCT io.patientunitstayid)      AS n_patients,
    COUNT(*)                                  AS n_rows,
    APPROX_QUANTILES(io.cellvaluenumeric, 4)  AS ml_min_q1_median_q3_max
  FROM `physionet-data.eicu_crd.intakeoutput` io
  JOIN cohort USING (patientunitstayid)
  WHERE REGEXP_CONTAINS(LOWER(io.cellpath), r'output')
  GROUP BY io.celllabel
),
classified AS (
  SELECT *,
    CASE
      WHEN REGEXP_CONTAINS(l, r'hemofiltration|dialys|fluid removal|ultrafiltrat|crrt|cvvh')
        THEN '5_rrt_fluid_removal'
      WHEN REGEXP_CONTAINS(l, r'total')
        THEN '4_total'
      WHEN REGEXP_CONTAINS(l, r'mixed')
        THEN '3_mixed'
      WHEN REGEXP_CONTAINS(l, r'urin|void|foley') AND REGEXP_CONTAINS(l, r'count|occurrence|number')
        THEN '2_urine_count_not_volume'
      WHEN REGEXP_CONTAINS(l, r'nephrostomy|urostomy|ileal conduit|ureter')
        THEN '1b_urine_review'
      WHEN REGEXP_CONTAINS(l, r'urin|void|foley|urethral|indwelling|suprapubic')
        THEN '1_urine_volume'
      ELSE '6_other'
    END AS uo_class
  FROM labels
)
SELECT uo_class, celllabel, n_patients, n_rows, ml_min_q1_median_q3_max
FROM classified
WHERE uo_class != '6_other'
   OR REGEXP_CONTAINS(l, r'cath|bladder|renal|kidney|\bgu\b|genito')
ORDER BY uo_class, n_patients DESC;


-- @query: 05e_urine_coverage_by_vent
-- Urine output charting by ventilation status (D15)
WITH cohort AS (
  SELECT patientunitstayid, unitdischargeoffset, imv_status
  FROM `evocative-ethos-471602-r3.base.eicu_cohort`
  WHERE hosp_tx_pct >= 0.8
),
io AS (
  SELECT io.patientunitstayid,
         io.intakeoutputoffset AS t,
         io.cellvaluenumeric   AS v,
         LOWER(io.celllabel)   AS l
  FROM `physionet-data.eicu_crd.intakeoutput` io
  JOIN cohort USING (patientunitstayid)
  WHERE REGEXP_CONTAINS(LOWER(io.cellpath), r'output')
),
uo AS (
  SELECT * FROM io
  WHERE REGEXP_CONTAINS(l, r'urin|void|foley|urethral|indwelling|suprapubic|nephrostomy|urostomy|ileal conduit|ureter|straight cath|condom cath')
    AND NOT REGEXP_CONTAINS(l, r'count|occurrence|number|incontinen|mixed|total|hemofiltration|dialys|fluid removal|ultrafiltrat|crrt|cvvh')
),
unmeasured AS (
  SELECT DISTINCT patientunitstayid FROM io
  WHERE (REGEXP_CONTAINS(l, r'urin|void|foley')
         AND REGEXP_CONTAINS(l, r'count|occurrence|number|incontinen'))
     OR REGEXP_CONTAINS(l, r'mixed')
),
per_patient AS (
  SELECT
    c.patientunitstayid,
    c.imv_status,
    c.unitdischargeoffset,
    COUNTIF(uo.t BETWEEN 0 AND c.unitdischargeoffset)               AS n_uo_icu,
    COUNTIF(uo.t BETWEEN 0 AND 1440)                                AS n_uo_24h,
    COUNT(DISTINCT IF(uo.t BETWEEN 0 AND 1439, DIV(uo.t, 60), NULL)) AS n_hours_uo_24h,
    COUNTIF(uo.v < 0)                                               AS n_neg,
    COUNTIF(uo.v > 2000)                                            AS n_gt_2000,
    COUNTIF(uo.v > 5000)                                            AS n_gt_5000,
    COUNTIF(uo.v IS NOT NULL)                                       AS n_values
  FROM cohort c
  LEFT JOIN uo USING (patientunitstayid)
  GROUP BY c.patientunitstayid, c.imv_status, c.unitdischargeoffset
)
SELECT
  p.imv_status,
  COUNT(*)                                                         AS n_patients,
  COUNTIF(p.n_uo_icu > 0)                                          AS n_any_uo_in_icu,
  COUNTIF(p.n_uo_24h > 0)                                          AS n_any_uo_first_24h,
  COUNTIF(p.unitdischargeoffset >= 1440)                           AS n_stay_ge_24h,
  APPROX_QUANTILES(IF(p.unitdischargeoffset >= 1440, p.n_hours_uo_24h, NULL), 4)
                                                                   AS hours_with_uo_first_24h_quartiles,
  COUNTIF(p.unitdischargeoffset >= 1440 AND p.n_hours_uo_24h >= 12) AS n_ge_12_hours_charted,
  COUNTIF(p.unitdischargeoffset >= 1440 AND p.n_hours_uo_24h BETWEEN 1 AND 4)
                                                                   AS n_1_to_4_hours_charted,
  COUNTIF(m.patientunitstayid IS NOT NULL)                         AS n_with_unmeasured_voids,
  SUM(p.n_values)                                                  AS n_uo_values,
  SUM(p.n_neg)                                                     AS n_negative,
  SUM(p.n_gt_2000)                                                 AS n_gt_2000ml,
  SUM(p.n_gt_5000)                                                 AS n_gt_5000ml
FROM per_patient p
LEFT JOIN unmeasured m USING (patientunitstayid)
GROUP BY p.imv_status
ORDER BY p.imv_status;


-- @query: 05e2_urine_hourly_by_hospital
-- Hospitals by near-hourly urine charting (D15)
WITH cohort AS (
  SELECT patientunitstayid, hospitalid, unitdischargeoffset, imv_status
  FROM `evocative-ethos-471602-r3.base.eicu_cohort`
  WHERE hosp_tx_pct >= 0.8
),
uo AS (
  SELECT io.patientunitstayid, io.intakeoutputoffset AS t
  FROM `physionet-data.eicu_crd.intakeoutput` io
  JOIN cohort USING (patientunitstayid)
  WHERE REGEXP_CONTAINS(LOWER(io.cellpath), r'output')
    AND REGEXP_CONTAINS(LOWER(io.celllabel), r'urin|void|foley|urethral|indwelling|suprapubic|nephrostomy|urostomy|ileal conduit|ureter|straight cath|condom cath')
    AND NOT REGEXP_CONTAINS(LOWER(io.celllabel), r'count|occurrence|number|incontinen|mixed|total|hemofiltration|dialys|fluid removal|ultrafiltrat|crrt|cvvh')
    AND io.cellvaluenumeric >= 0 AND io.cellvaluenumeric <= 5000
),
per_patient AS (
  SELECT
    c.patientunitstayid, c.hospitalid, c.imv_status,
    c.unitdischargeoffset >= 1440                                    AS stay_ge_24h,
    COUNTIF(uo.t BETWEEN 0 AND c.unitdischargeoffset) > 0            AS any_uo_icu,
    COUNT(DISTINCT IF(uo.t BETWEEN 0 AND 1439, DIV(uo.t, 60), NULL)) AS n_hours_uo_24h
  FROM cohort c
  LEFT JOIN uo USING (patientunitstayid)
  GROUP BY c.patientunitstayid, c.hospitalid, c.imv_status, c.unitdischargeoffset
),
per_hosp AS (
  SELECT
    hospitalid,
    COUNT(*)                                                         AS n_patients,
    COUNTIF(any_uo_icu)                                              AS n_any_uo,
    COUNTIF(stay_ge_24h)                                             AS n_ge24,
    COUNTIF(stay_ge_24h AND n_hours_uo_24h >= 12)                    AS n_hourly,
    COUNTIF(stay_ge_24h AND imv_status = 'imv')                      AS n_imv_ge24,
    COUNTIF(stay_ge_24h AND imv_status = 'imv'  AND n_hours_uo_24h >= 12) AS n_imv_hourly,
    COUNTIF(stay_ge_24h AND imv_status = 'none')                     AS n_none_ge24,
    COUNTIF(stay_ge_24h AND imv_status = 'none' AND n_hours_uo_24h >= 12) AS n_none_hourly,
    SAFE_DIVIDE(COUNTIF(stay_ge_24h AND n_hours_uo_24h >= 12), COUNTIF(stay_ge_24h)) AS hourly_share
  FROM per_patient
  GROUP BY hospitalid
)
SELECT
  CASE
    WHEN hourly_share IS NULL THEN 'f: no stays >= 24 h'
    WHEN hourly_share < 0.10  THEN 'a: < 10%'
    WHEN hourly_share < 0.30  THEN 'b: 10-29%'
    WHEN hourly_share < 0.50  THEN 'c: 30-49%'
    WHEN hourly_share < 0.80  THEN 'd: 50-79%'
    ELSE                           'e: >= 80%'
  END                                                                AS hourly_charting_band,
  COUNT(*)                                                           AS n_hospitals,
  COUNTIF(n_patients < 20)                                           AS n_hosp_under_20_patients,
  SUM(n_patients)                                                    AS n_patients,
  ROUND(100 * SAFE_DIVIDE(SUM(n_any_uo), SUM(n_patients)), 1)        AS pct_any_uo_in_icu,
  SUM(n_ge24)                                                        AS n_stay_ge_24h,
  ROUND(100 * SAFE_DIVIDE(SUM(n_hourly), SUM(n_ge24)), 1)            AS pct_near_hourly,
  SUM(n_imv_ge24)                                                    AS n_imv_ge_24h,
  ROUND(100 * SAFE_DIVIDE(SUM(n_imv_hourly), SUM(n_imv_ge24)), 1)    AS pct_near_hourly_imv,
  SUM(n_none_ge24)                                                   AS n_none_ge_24h,
  ROUND(100 * SAFE_DIVIDE(SUM(n_none_hourly), SUM(n_none_ge24)), 1)  AS pct_near_hourly_none
FROM per_hosp
GROUP BY hourly_charting_band
ORDER BY hourly_charting_band;
