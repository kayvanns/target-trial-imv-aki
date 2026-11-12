-- Checks 10: moving time zero from ICU admission to admission + 2 h
-- Each window is computed side by side; no tables are changed.


-- @query: 10a_t0_window_eligibility
-- Missing creatinine at t0, stage at t0 and eligibility: current (labs to +6 h) vs t0 = +2 h
-- Same rules as pipelines 03-04; ESRD, severe CKD, CKD without range and other exclusions applied
WITH windows AS (
  SELECT 'a: current (labs to +6 h, IMV <= 60 min)' AS version, 0 AS t0, 360 AS lab_cut, 60 AS vent_cut
  UNION ALL
  SELECT 'b: t0 = +2 h (labs to +2 h, IMV <= 120 min)', 120, 120, 120
),
cohort AS (
  SELECT *
  FROM `evocative-ethos-471602-r3.base.eicu_tte_cohort`
  WHERE (kidney_exclusion_reason IS NULL
         OR REGEXP_CONTAINS(kidney_exclusion_reason, r'^[45]:'))
    AND NOT (ambiguous_ventilation OR kidney_transplant OR chronic_trach
             OR care_limited_at_t0 OR chronic_lung_disease)
),
cr AS (
  SELECT l.patientunitstayid, l.labresultoffset AS t, l.labresult AS value
  FROM `physionet-data.eicu_crd.lab` l
  JOIN cohort c USING (patientunitstayid)
  WHERE l.labname = 'creatinine'
    AND l.labresult BETWEEN 0.2 AND 20
    AND l.labresultoffset >= -10080
    AND (c.first_rrt_offset IS NULL OR l.labresultoffset < c.first_rrt_offset)
),
per_window AS (
  SELECT
    w.version, w.t0, w.vent_cut,
    c.patientunitstayid, c.imv_status, c.imv_start, c.is_ckd, c.baseline_creat AS ckd_baseline,
    c.expected_normal_creat,
    IFNULL(c.first_rrt_offset <= w.lab_cut, FALSE)                          AS rrt_by_t0,
    MIN(IF(cr.t <= w.lab_cut, cr.value, NULL))                              AS lowest_upto_t0,
    MIN(IF(cr.t BETWEEN -2880 AND w.lab_cut, cr.value, NULL))               AS lowest_48h_before_t0,
    ARRAY_AGG(IF(cr.t BETWEEN -1440 AND w.lab_cut, cr.value, NULL) IGNORE NULLS
              ORDER BY cr.t DESC, cr.value DESC LIMIT 1)[SAFE_OFFSET(0)]    AS t0_creat
  FROM cohort c
  CROSS JOIN windows w
  LEFT JOIN cr USING (patientunitstayid)
  GROUP BY w.version, w.t0, w.vent_cut, w.lab_cut,
           c.patientunitstayid, c.imv_status, c.imv_start, c.is_ckd, c.baseline_creat,
           c.expected_normal_creat, c.first_rrt_offset
),
with_baseline AS (
  SELECT
    *,
    CASE
      WHEN is_ckd               THEN ckd_baseline
      WHEN lowest_upto_t0 < 1.1 THEN lowest_upto_t0
      ELSE expected_normal_creat
    END AS baseline_creat
  FROM per_window
),
staged AS (
  SELECT
    *,
    IFNULL(imv_status = 'imv' AND imv_start <= vent_cut, FALSE)     AS ventilated_on_arrival,
    (imv_status = 'imv' AND imv_start <= t0 + 1440)                AS intubated_by_24h,
    CASE
      WHEN rrt_by_t0                                                THEN 3
      WHEN t0_creat IS NULL                                         THEN NULL
      WHEN t0_creat >= 3.0 * baseline_creat
        OR (t0_creat >= 4.0
            AND (t0_creat >= 1.5 * baseline_creat
                 OR t0_creat - lowest_48h_before_t0 >= 0.3))        THEN 3
      WHEN t0_creat >= 2.0 * baseline_creat                         THEN 2
      WHEN t0_creat >= 1.5 * baseline_creat
        OR t0_creat - lowest_48h_before_t0 >= 0.3                   THEN 1
      ELSE 0
    END AS t0_aki_stage
  FROM with_baseline
)
SELECT
  version,
  COUNT(*)                                                                AS n_start,
  COUNTIF(ventilated_on_arrival)                                          AS n_ventilated_on_arrival,
  COUNTIF(NOT ventilated_on_arrival)                                      AS n_not_ventilated,
  COUNTIF(NOT ventilated_on_arrival AND t0_aki_stage IS NULL)             AS n_no_t0_creatinine,
  COUNTIF(NOT ventilated_on_arrival AND t0_aki_stage = 0)                 AS n_stage0,
  COUNTIF(NOT ventilated_on_arrival AND t0_aki_stage = 1)                 AS n_stage1,
  COUNTIF(NOT ventilated_on_arrival AND t0_aki_stage = 2)                 AS n_stage2,
  COUNTIF(NOT ventilated_on_arrival AND t0_aki_stage = 3)                 AS n_stage3,
  COUNTIF(NOT ventilated_on_arrival AND t0_aki_stage <= 1)                AS n_eligible_b,
  COUNTIF(NOT ventilated_on_arrival AND t0_aki_stage <= 1
          AND intubated_by_24h)                                           AS n_eligible_b_intubated_by_24h,
  COUNTIF(NOT ventilated_on_arrival AND t0_aki_stage = 0)                 AS n_eligible_a,
  COUNTIF(NOT ventilated_on_arrival AND t0_aki_stage = 0
          AND intubated_by_24h)                                           AS n_eligible_a_intubated_by_24h
FROM staged
GROUP BY version
ORDER BY version;

-- @query: 10d_baseline_values_after_imv
-- Current design, Option B, intubated at 1-6 h: baseline creatinine values recorded after IMV start,
-- and the stage at t0 if only values before IMV start were used
WITH cohort AS (
  SELECT
    *,
    IF(imv_start <= 120, 'a: 61-120 min', 'b: 2-6 h') AS imv_group
  FROM `evocative-ethos-471602-r3.base.eicu_tte_cohort`
  WHERE eligible_b
    AND imv_status = 'imv'
    AND imv_start <= 360
),
cr AS (
  SELECT l.patientunitstayid, l.labresultoffset AS t, l.labresult AS value
  FROM `physionet-data.eicu_crd.lab` l
  JOIN cohort c USING (patientunitstayid)
  WHERE l.labname = 'creatinine'
    AND l.labresult BETWEEN 0.2 AND 20
    AND l.labresultoffset BETWEEN -10080 AND 360
    AND (c.first_rrt_offset IS NULL OR l.labresultoffset < c.first_rrt_offset)
),
per_patient AS (
  SELECT
    c.patientunitstayid, c.imv_group, c.imv_start, c.is_ckd, c.baseline_creat,
    c.baseline_source, c.expected_normal_creat, c.t0_aki_stage,
    -- Current values and when they were measured
    ARRAY_AGG(IF(cr.t >= -1440, STRUCT(cr.t, cr.value), NULL) IGNORE NULLS
              ORDER BY cr.t DESC, cr.value DESC LIMIT 1)[SAFE_OFFSET(0)].t        AS t0_creat_time,
    ARRAY_AGG(STRUCT(cr.t, cr.value) ORDER BY cr.value, cr.t LIMIT 1)[SAFE_OFFSET(0)].t AS lowest_time,
    -- Same values using only creatinine before IMV start
    MIN(IF(cr.t < c.imv_start, cr.value, NULL))                                  AS pre_lowest,
    MIN(IF(cr.t BETWEEN -2880 AND c.imv_start - 1, cr.value, NULL))              AS pre_lowest_48h,
    ARRAY_AGG(IF(cr.t >= -1440 AND cr.t < c.imv_start, cr.value, NULL) IGNORE NULLS
              ORDER BY cr.t DESC, cr.value DESC LIMIT 1)[SAFE_OFFSET(0)]          AS pre_t0_creat
  FROM cohort c
  LEFT JOIN cr USING (patientunitstayid)
  GROUP BY c.patientunitstayid, c.imv_group, c.imv_start, c.is_ckd, c.baseline_creat,
           c.baseline_source, c.expected_normal_creat, c.t0_aki_stage
),
restaged AS (
  SELECT
    *,
    CASE
      WHEN is_ckd           THEN baseline_creat
      WHEN pre_lowest < 1.1 THEN pre_lowest
      ELSE expected_normal_creat
    END AS pre_baseline
  FROM per_patient
),
final AS (
  SELECT
    *,
    CASE
      WHEN pre_t0_creat IS NULL                                     THEN NULL
      WHEN pre_t0_creat >= 3.0 * pre_baseline
        OR (pre_t0_creat >= 4.0
            AND (pre_t0_creat >= 1.5 * pre_baseline
                 OR pre_t0_creat - pre_lowest_48h >= 0.3))          THEN 3
      WHEN pre_t0_creat >= 2.0 * pre_baseline                       THEN 2
      WHEN pre_t0_creat >= 1.5 * pre_baseline
        OR pre_t0_creat - pre_lowest_48h >= 0.3                     THEN 1
      ELSE 0
    END AS pre_t0_aki_stage
  FROM restaged
)
SELECT
  imv_group,
  COUNT(*)                                                                  AS n_patients,
  COUNTIF(t0_creat_time >= imv_start)                                       AS n_t0_creat_after_imv,
  APPROX_QUANTILES(IF(t0_creat_time >= imv_start,
                      t0_creat_time - imv_start, NULL), 2)[OFFSET(1)]      AS median_min_imv_to_t0_creat,
  COUNTIF(baseline_source LIKE 'measured%' AND lowest_time >= imv_start)    AS n_measured_baseline_after_imv,
  COUNTIF(t0_creat_time >= imv_start
          OR (baseline_source LIKE 'measured%' AND lowest_time >= imv_start)) AS n_any_baseline_value_after_imv,
  COUNTIF(pre_t0_creat IS NULL)                                             AS n_no_creat_before_imv,
  COUNTIF(pre_t0_aki_stage IS NOT NULL
          AND pre_t0_aki_stage != t0_aki_stage)                             AS n_stage_changes_pre_imv_only,
  COUNTIF(pre_t0_aki_stage >= 2)                                            AS n_stage2plus_pre_imv_only
FROM final
GROUP BY imv_group
ORDER BY imv_group;