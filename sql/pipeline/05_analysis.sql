-- Pipeline 05: analysis table, one row per eligible patient
CREATE OR REPLACE TABLE `evocative-ethos-471602-r3.base.analysis` AS
WITH
 
cohort AS (
  SELECT
    patientunitstayid, hospitalid, eligible_a, eligible_b,
    t0_aki_stage, t0_creat, baseline_creat, baseline_source,
    imv_status, imv_start,
    first_rrt_offset,
    unitdischargeoffset, hospitaldischargeoffset,
    unitdischargestatus, hospitaldischargestatus
  FROM `evocative-ethos-471602-r3.base.eicu_tte_cohort`
  WHERE eligible_b
),
 
-- Creatinine before RRT start; one week back for the 48 h comparison
cr AS (
  SELECT l.patientunitstayid, l.labresultoffset AS t, l.labresult AS value
  FROM `physionet-data.eicu_crd.lab` l
  JOIN cohort c USING (patientunitstayid)
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
                    OR x.value - x.lowest_prior_48h >= 0.3)), x.t, NULL))  AS first_cr_stage23_time,
    MIN(IF(x.value >= 1.5 * c.baseline_creat
           OR x.value - x.lowest_prior_48h >= 0.3, x.t, NULL))            AS first_cr_stage1plus_time
  FROM cohort c
  LEFT JOIN cr_after_t0 x USING (patientunitstayid)
  GROUP BY c.patientunitstayid
),
 
events AS (
  SELECT
    c.*,
    (c.imv_status = 'imv' AND c.imv_start <= 1440)                                      AS intubated_by_24h,
    f.first_cr_stage23_time,
    (SELECT MIN(x) FROM UNNEST([f.first_cr_stage23_time, c.first_rrt_offset]) x)        AS aki_time,
    (SELECT MIN(x) FROM UNNEST([f.first_cr_stage1plus_time, c.first_rrt_offset]) x)     AS aki_time_any_stage,
    CASE
      WHEN c.first_rrt_offset IS NOT NULL
       AND c.first_rrt_offset <= IFNULL(f.first_cr_stage23_time, c.first_rrt_offset)   THEN 'rrt'
      WHEN f.first_cr_stage23_time IS NOT NULL                                          THEN 'creatinine'
    END                                                                                 AS aki_type,
    CASE
      WHEN LOWER(c.unitdischargestatus)     = 'expired' THEN c.unitdischargeoffset
      WHEN LOWER(c.hospitaldischargestatus) = 'expired' THEN c.hospitaldischargeoffset
    END                                                                                 AS death_time
  FROM cohort c
  JOIN first_events f USING (patientunitstayid)
),
 
follow_up AS (
  SELECT
    *,
    (SELECT MIN(x) FROM UNNEST([aki_time, death_time, hospitaldischargeoffset, 10080]) x) AS end_time
  FROM events
)
 
-- Ties go to AKI, then death, then discharge
SELECT
  *,
  CASE
    WHEN aki_time                = end_time THEN 'aki'
    WHEN death_time              = end_time THEN 'death'
    WHEN hospitaldischargeoffset = end_time THEN 'discharged'
    ELSE                                         'day7'
  END AS end_reason
FROM follow_up;