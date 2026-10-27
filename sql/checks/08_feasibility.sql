-- Checks 08: feasibility. Needs pipeline 04.
-- AKI events are counted overall only, never by intubation (D32).


-- @query: 08a_feasibility_option_a
-- Option A: intubation timing, ICU stay, deaths, AKI events (D12, D18, D19)
WITH careplan_ett_by_6h AS (
  SELECT DISTINCT patientunitstayid
  FROM `physionet-data.eicu_crd.careplangeneral`
  WHERE LOWER(cplgroup) = 'airway'
    AND REGEXP_CONTAINS(LOWER(cplitemvalue), r'^intubated/(oral|nasal) ett')
    AND cplitemoffset <= 360
),
elig AS (
  SELECT t.*, ett.patientunitstayid IS NOT NULL AS careplan_ett_by_6h
  FROM `evocative-ethos-471602-r3.base.eicu_tte_cohort` t
  LEFT JOIN careplan_ett_by_6h ett USING (patientunitstayid)
  WHERE t.eligible_a
),
creatinine_after_t0 AS (
  SELECT l.patientunitstayid, l.labresultoffset AS t, l.labresult AS value
  FROM `physionet-data.eicu_crd.lab` l
  JOIN elig e USING (patientunitstayid)
  WHERE l.labname = 'creatinine'
    AND l.labresult BETWEEN 0.2 AND 20
    AND l.labresultoffset > 360
    AND (e.first_rrt_offset IS NULL OR l.labresultoffset < e.first_rrt_offset)
),
per_patient AS (
  SELECT
    e.patientunitstayid, e.imv_status, e.imv_start, e.unitdischargeoffset,
    LOWER(e.unitdischargestatus) = 'expired'                         AS died_in_icu,
    e.first_rrt_offset, e.careplan_ett_by_6h,
    MIN(IF(c.value >= 2.0 * e.baseline_creat
           OR (c.value >= 4.0 AND c.value >= 1.5 * e.baseline_creat), c.t, NULL)) AS first_cr_stage23,
    COUNTIF(c.t <= 4320)                                             AS n_cr_by_72h,
    COUNTIF(c.t <= 10080)                                            AS n_cr_by_7d
  FROM elig e
  LEFT JOIN creatinine_after_t0 c USING (patientunitstayid)
  GROUP BY e.patientunitstayid, e.imv_status, e.imv_start, e.unitdischargeoffset,
           e.unitdischargestatus, e.first_rrt_offset, e.careplan_ett_by_6h
),
with_event AS (
  SELECT *, (SELECT MIN(x) FROM UNNEST([first_cr_stage23, first_rrt_offset]) x) AS aki_time
  FROM per_patient
)
SELECT
  COUNT(*)                                                                  AS n_patients,
  COUNTIF(imv_status = 'imv' AND imv_start <= 360)                          AS n_intubated_by_6h,
  COUNTIF(imv_status = 'imv' AND imv_start <= 720)                          AS n_intubated_by_12h,
  COUNTIF(imv_status = 'imv' AND imv_start <= 1440)                         AS n_intubated_by_24h,
  COUNTIF(imv_status = 'imv' AND imv_start <= 2880)                         AS n_intubated_by_48h,
  COUNTIF(imv_status = 'imv' AND imv_start <= 4320)                         AS n_intubated_by_72h,
  COUNTIF(imv_status = 'imv')                                               AS n_intubated_ever,
  APPROX_QUANTILES(unitdischargeoffset / 60, 4)                             AS icu_hours_quartiles,
  COUNTIF(unitdischargeoffset < 4320)                                       AS n_left_icu_before_72h,
  COUNTIF(unitdischargeoffset < 10080)                                      AS n_left_icu_before_7d,
  COUNTIF(died_in_icu AND unitdischargeoffset <= 4320)                      AS n_died_in_icu_by_72h,
  COUNTIF(died_in_icu AND unitdischargeoffset <= 10080)                     AS n_died_in_icu_by_7d,
  COUNTIF(n_cr_by_72h >= 1)                                                 AS n_any_creat_6h_to_72h,
  COUNTIF(n_cr_by_7d >= 1)                                                  AS n_any_creat_6h_to_7d,
  COUNTIF(aki_time <= 4320)                                                 AS n_aki_by_72h,
  COUNTIF(aki_time <= 4320  AND aki_time <= unitdischargeoffset)            AS n_aki_by_72h_in_icu,
  COUNTIF(aki_time <= 10080)                                                AS n_aki_by_7d,
  COUNTIF(aki_time <= 10080 AND aki_time <= unitdischargeoffset)            AS n_aki_by_7d_in_icu,
  COUNTIF(first_rrt_offset <= 10080)                                        AS n_rrt_by_7d,
  COUNTIF(careplan_ett_by_6h)                                               AS n_careplan_ett_by_6h,
  COUNTIF(careplan_ett_by_6h AND imv_status = 'imv' AND imv_start <= 360)   AS n_of_those_imv_by_6h,
  COUNTIF(careplan_ett_by_6h AND imv_status = 'imv' AND imv_start > 360)    AS n_of_those_imv_after_6h,
  COUNTIF(careplan_ett_by_6h AND imv_status = 'none')                       AS n_of_those_never_imv
FROM with_event;


-- @query: 08b_outcome_scenarios
-- AKI events by design option (D17, D18, D26)
WITH candidates AS (
  SELECT * FROM `evocative-ethos-471602-r3.base.eicu_tte_cohort`
  WHERE eligible_b
),
cr AS (
  SELECT l.patientunitstayid, l.labresultoffset AS t, l.labresult AS value
  FROM `physionet-data.eicu_crd.lab` l
  JOIN candidates c USING (patientunitstayid)
  WHERE l.labname = 'creatinine'
    AND l.labresult BETWEEN 0.2 AND 20
    AND l.labresultoffset >= -10080
    AND (c.first_rrt_offset IS NULL OR l.labresultoffset < c.first_rrt_offset)
),
cr_after_t0 AS (
  SELECT a.patientunitstayid, a.t, a.value, MIN(b.value) AS lowest_prior_48h
  FROM cr a
  LEFT JOIN cr b
    ON  b.patientunitstayid = a.patientunitstayid
    AND b.t >= a.t - 2880
    AND b.t <  a.t
  WHERE a.t > 360
  GROUP BY a.patientunitstayid, a.t, a.value
),
first_events AS (
  SELECT
    c.patientunitstayid,
    MIN(IF(x.value >= 2.0 * c.baseline_creat
           OR (x.value >= 4.0
               AND (x.value >= 1.5 * c.baseline_creat
                    OR x.value - x.lowest_prior_48h >= 0.3)), x.t, NULL))  AS first_cr_stage2plus,
    MIN(IF(x.value >= 1.5 * c.baseline_creat
           OR x.value - x.lowest_prior_48h >= 0.3, x.t, NULL))            AS first_cr_stage1plus
  FROM candidates c
  LEFT JOIN cr_after_t0 x USING (patientunitstayid)
  GROUP BY c.patientunitstayid
),
outcomes AS (
  SELECT
    c.patientunitstayid,
    c.t0_aki_stage,
    (c.imv_status = 'imv' AND c.imv_start <= 1440)                              AS intubated_by_24h,
    (SELECT MIN(x) FROM UNNEST([f.first_cr_stage2plus, c.first_rrt_offset]) x)   AS t_stage2plus,
    (SELECT MIN(x) FROM UNNEST([f.first_cr_stage1plus, c.first_rrt_offset]) x)   AS t_stage1plus
  FROM candidates c
  JOIN first_events f USING (patientunitstayid)
),
designs AS (
  SELECT 'A: stage 0 at t0' AS eligibility, 0 AS max_t0_stage, 'stage 2-3' AS outcome UNION ALL
  SELECT 'A: stage 0 at t0',                0,                 'any stage 1-3'          UNION ALL
  SELECT 'B: stage 0-1 at t0',              1,                 'stage 2-3'
)
SELECT
  d.eligibility,
  d.outcome,
  COUNT(*)                                                     AS n_eligible,
  COUNTIF(o.intubated_by_24h)                                  AS n_intubated_by_24h,
  COUNTIF(IF(d.outcome = 'stage 2-3', o.t_stage2plus, o.t_stage1plus) <= 4320)  AS n_events_by_72h,
  COUNTIF(IF(d.outcome = 'stage 2-3', o.t_stage2plus, o.t_stage1plus) <= 10080) AS n_events_by_7d
FROM outcomes o
CROSS JOIN designs d
WHERE o.t0_aki_stage <= d.max_t0_stage
GROUP BY d.eligibility, d.outcome
ORDER BY d.eligibility, d.outcome DESC;


-- @query: 08c_creatinine_by_day
-- Daily creatinine measurement by location and intubation group (D18, D19)
WITH candidates AS (
  SELECT
    patientunitstayid,
    unitdischargeoffset,
    hospitaldischargeoffset,
    (imv_status = 'imv' AND imv_start <= 1440) AS intubated_by_24h
  FROM `evocative-ethos-471602-r3.base.eicu_tte_cohort`
  WHERE eligible_b
),
patient_days AS (
  SELECT
    c.*,
    d AS day,
    CASE
      WHEN c.unitdischargeoffset     > (d - 1) * 1440 THEN 'ICU'
      WHEN c.hospitaldischargeoffset > (d - 1) * 1440 THEN 'ward'
      ELSE 'gone'
    END AS location
  FROM candidates c,
  UNNEST(GENERATE_ARRAY(1, 7)) AS d
),
creat_days AS (
  SELECT DISTINCT l.patientunitstayid, DIV(l.labresultoffset, 1440) + 1 AS day
  FROM `physionet-data.eicu_crd.lab` l
  JOIN candidates c USING (patientunitstayid)
  WHERE l.labname = 'creatinine'
    AND l.labresult BETWEEN 0.2 AND 20
    AND l.labresultoffset BETWEEN 0 AND 10079
)
SELECT
  pd.day,
  pd.location,
  IF(pd.intubated_by_24h, 'intubated by 24 h', 'not intubated by 24 h') AS group_24h,
  COUNT(*)                                                    AS n_patient_days,
  COUNTIF(cd.patientunitstayid IS NOT NULL)                   AS n_days_with_creat,
  ROUND(100 * COUNTIF(cd.patientunitstayid IS NOT NULL) / COUNT(*), 1) AS pct_days_with_creat
FROM patient_days pd
LEFT JOIN creat_days cd
  ON cd.patientunitstayid = pd.patientunitstayid AND cd.day = pd.day
WHERE pd.location != 'gone'
GROUP BY pd.day, pd.location, group_24h
ORDER BY pd.day, pd.location, group_24h;
