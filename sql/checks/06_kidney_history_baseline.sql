-- Checks 06: kidney history, RRT, baseline creatinine. Primary cohort.
-- Needs pipelines 02-03.


-- @query: 06a_kidney_history_sources
-- Kidney history entries by source (D20, D21, D27)
WITH cohort AS (
  SELECT patientunitstayid
  FROM `evocative-ethos-471602-r3.base.eicu_cohort`
  WHERE hosp_tx_pct >= 0.8
),
ph AS (
  SELECT
    'pasthistory'                                              AS source,
    p.pasthistorypath                                          AS item,
    COUNT(DISTINCT p.patientunitstayid)                        AS n_patients,
    COUNT(DISTINCT IF(p.pasthistoryoffset <= 0, p.patientunitstayid, NULL)) AS n_entry_at_or_before_admit,
    APPROX_QUANTILES(p.pasthistoryoffset, 2)[OFFSET(1)]        AS median_offset_min
  FROM `physionet-data.eicu_crd.pasthistory` p
  JOIN cohort USING (patientunitstayid)
  WHERE REGEXP_CONTAINS(LOWER(p.pasthistorypath), r'renal|kidney|dialys|nephr|transplant')
  GROUP BY p.pasthistorypath
),
dx AS (
  SELECT
    'diagnosis'                                                AS source,
    CONCAT(d.diagnosisstring, '  [', IFNULL(ANY_VALUE(d.icd9code), ''), ']') AS item,
    COUNT(DISTINCT d.patientunitstayid)                        AS n_patients,
    COUNT(DISTINCT IF(d.diagnosisoffset <= 0, d.patientunitstayid, NULL)) AS n_entry_at_or_before_admit,
    APPROX_QUANTILES(d.diagnosisoffset, 2)[OFFSET(1)]          AS median_offset_min
  FROM `physionet-data.eicu_crd.diagnosis` d
  JOIN cohort USING (patientunitstayid)
  WHERE REGEXP_CONTAINS(LOWER(d.diagnosisstring), r'renal|kidney|dialys|nephr|esrd|transplant')
     OR REGEXP_CONTAINS(IFNULL(d.icd9code, ''), r'(^|,\s*)(585|N18|V45\.1|Z99\.2|V42\.0|Z94\.0)')
  GROUP BY d.diagnosisstring
),
tx AS (
  SELECT
    'treatment'                                                AS source,
    t.treatmentstring                                          AS item,
    COUNT(DISTINCT t.patientunitstayid)                        AS n_patients,
    COUNT(DISTINCT IF(t.treatmentoffset <= 0, t.patientunitstayid, NULL)) AS n_entry_at_or_before_admit,
    APPROX_QUANTILES(t.treatmentoffset, 2)[OFFSET(1)]          AS median_offset_min
  FROM `physionet-data.eicu_crd.treatment` t
  JOIN cohort USING (patientunitstayid)
  WHERE REGEXP_CONTAINS(LOWER(t.treatmentstring), r'dialys|crrt|cvvh|hemofiltration|ultrafiltration|renal replacement')
  GROUP BY t.treatmentstring
),
apache AS (
  SELECT
    'apacheapsvar'                                             AS source,
    CONCAT('dialysis = ', CAST(a.dialysis AS STRING))          AS item,
    COUNT(DISTINCT a.patientunitstayid)                        AS n_patients,
    CAST(NULL AS INT64)                                        AS n_entry_at_or_before_admit,
    CAST(NULL AS INT64)                                        AS median_offset_min
  FROM `physionet-data.eicu_crd.apacheapsvar` a
  JOIN cohort USING (patientunitstayid)
  GROUP BY a.dialysis
)
SELECT * FROM (
  SELECT * FROM ph
  UNION ALL SELECT * FROM dx
  UNION ALL SELECT * FROM tx
  UNION ALL SELECT * FROM apache
)
WHERE n_patients >= 5
ORDER BY source, n_patients DESC;


-- @query: 06b_esrd_ckd_counts
-- ESRD by source; CKD and transplant counts (D20, D21, D27)
WITH cohort AS (
  SELECT patientunitstayid
  FROM `evocative-ethos-471602-r3.base.eicu_cohort`
  WHERE hosp_tx_pct >= 0.8
),
ph_f AS (
  SELECT p.patientunitstayid,
    LOGICAL_OR(REGEXP_CONTAINS(LOWER(p.pasthistorypath),
      r'renal failure - hemodialysis|renal failure - peritoneal dialysis'))            AS esrd_ph,
    LOGICAL_OR(REGEXP_CONTAINS(LOWER(p.pasthistorypath),
      r'renal insufficiency|renal failure- not currently dialyzed|renal failure - not currently dialyzed')) AS ckd_ph,
    LOGICAL_OR(REGEXP_CONTAINS(LOWER(p.pasthistorypath),
      r'creatinine 4-5|creatinine > 5'))                                               AS ckd_ph_severe,
    LOGICAL_OR(REGEXP_CONTAINS(LOWER(p.pasthistorypath), r'renal transplant'))        AS kt_ph
  FROM `physionet-data.eicu_crd.pasthistory` p
  JOIN cohort USING (patientunitstayid)
  GROUP BY p.patientunitstayid
),
dx_f AS (
  SELECT d.patientunitstayid,
    LOGICAL_OR(REGEXP_CONTAINS(LOWER(d.diagnosisstring),
                 r'esrd|end stage renal|stage 5|dialysis associated|dialysis access')
            OR REGEXP_CONTAINS(IFNULL(d.icd9code, ''),
                 r'(^|,\s*)(585\.5|585\.6|N18\.5|N18\.6|V45\.1|Z99\.2)'))             AS esrd_dx,
    LOGICAL_OR(REGEXP_CONTAINS(LOWER(d.diagnosisstring),
                 r'chronic kidney disease|chronic renal insufficiency|anemia of renal disease')) AS ckd_dx,
    LOGICAL_OR(REGEXP_CONTAINS(LOWER(d.diagnosisstring), r'kidney transplant')
            OR REGEXP_CONTAINS(IFNULL(d.icd9code, ''),
                 r'(^|,\s*)(V42\.0|Z94\.0|996\.81)'))                                  AS kt_dx
  FROM `physionet-data.eicu_crd.diagnosis` d
  JOIN cohort USING (patientunitstayid)
  GROUP BY d.patientunitstayid
),
tx_f AS (
  SELECT t.patientunitstayid,
    LOGICAL_OR(REGEXP_CONTAINS(LOWER(t.treatmentstring),
      r'for chronic renal failure|peritoneal dialysis'))                               AS esrd_tx
  FROM `physionet-data.eicu_crd.treatment` t
  JOIN cohort USING (patientunitstayid)
  GROUP BY t.patientunitstayid
),
ap_f AS (
  SELECT a.patientunitstayid, LOGICAL_OR(a.dialysis = 1) AS esrd_apache
  FROM `physionet-data.eicu_crd.apacheapsvar` a
  JOIN cohort USING (patientunitstayid)
  GROUP BY a.patientunitstayid
),
flags AS (
  SELECT
    c.patientunitstayid,
    ap.patientunitstayid IS NOT NULL       AS has_apache,
    IFNULL(ph.esrd_ph, FALSE)              AS esrd_ph,
    IFNULL(ap.esrd_apache, FALSE)          AS esrd_apache,
    IFNULL(dx.esrd_dx, FALSE)              AS esrd_dx,
    IFNULL(tx.esrd_tx, FALSE)              AS esrd_tx,
    IFNULL(ph.ckd_ph, FALSE) OR IFNULL(dx.ckd_dx, FALSE) AS ckd_any,
    IFNULL(ph.ckd_ph_severe, FALSE)        AS ckd_severe,
    IFNULL(ph.kt_ph, FALSE) OR IFNULL(dx.kt_dx, FALSE)   AS kt_any
  FROM cohort c
  LEFT JOIN ph_f ph USING (patientunitstayid)
  LEFT JOIN dx_f dx USING (patientunitstayid)
  LEFT JOIN tx_f tx USING (patientunitstayid)
  LEFT JOIN ap_f ap USING (patientunitstayid)
),
f2 AS (
  SELECT *,
    CAST(esrd_ph AS INT64) + CAST(esrd_apache AS INT64)
      + CAST(esrd_dx AS INT64) + CAST(esrd_tx AS INT64)  AS n_esrd_sources
  FROM flags
)
SELECT
  COUNT(*)                                                   AS n_patients,
  COUNTIF(NOT has_apache)                                    AS n_no_apache_record,
  COUNTIF(esrd_ph)                                           AS n_esrd_pasthistory,
  COUNTIF(esrd_apache)                                       AS n_esrd_apache,
  COUNTIF(esrd_dx)                                           AS n_esrd_diagnosis,
  COUNTIF(esrd_tx)                                           AS n_esrd_treatment,
  COUNTIF(n_esrd_sources >= 1)                               AS n_esrd_any,
  COUNTIF(n_esrd_sources = 1)                                AS n_esrd_1_source,
  COUNTIF(n_esrd_sources = 2)                                AS n_esrd_2_sources,
  COUNTIF(n_esrd_sources >= 3)                               AS n_esrd_3plus_sources,
  COUNTIF(n_esrd_sources = 1 AND esrd_ph)                    AS n_esrd_only_pasthistory,
  COUNTIF(n_esrd_sources = 1 AND esrd_apache)                AS n_esrd_only_apache,
  COUNTIF(n_esrd_sources = 1 AND esrd_dx)                    AS n_esrd_only_diagnosis,
  COUNTIF(n_esrd_sources = 1 AND esrd_tx)                    AS n_esrd_only_treatment,
  COUNTIF(n_esrd_sources = 0 AND ckd_any)                    AS n_ckd_not_esrd,
  COUNTIF(n_esrd_sources = 0 AND ckd_severe)                 AS n_ckd_severe_not_esrd,
  COUNTIF(kt_any)                                            AS n_kidney_transplant_any,
  COUNTIF(kt_any AND n_esrd_sources >= 1)                    AS n_transplant_and_esrd,
  COUNTIF(kt_any AND n_esrd_sources = 0)                     AS n_transplant_not_esrd,
  COUNTIF(n_esrd_sources = 0)                                AS n_after_esrd_exclusion,
  COUNTIF(n_esrd_sources = 0 AND NOT kt_any)                 AS n_after_esrd_and_transplant,
  COUNTIF(n_esrd_sources = 0 AND NOT kt_any AND NOT ckd_severe) AS n_after_esrd_transplant_severe_ckd
FROM f2;


-- @query: 06c_rrt_timing_by_esrd_group
-- RRT timing and first creatinine by ESRD group (D16, D20)
WITH cohort AS (
  SELECT patientunitstayid
  FROM `evocative-ethos-471602-r3.base.eicu_cohort`
  WHERE hosp_tx_pct >= 0.8
),
ph_f AS (
  SELECT p.patientunitstayid,
    LOGICAL_OR(REGEXP_CONTAINS(LOWER(p.pasthistorypath),
      r'renal failure - hemodialysis|renal failure - peritoneal dialysis')) AS esrd_ph
  FROM `physionet-data.eicu_crd.pasthistory` p
  JOIN cohort USING (patientunitstayid)
  GROUP BY p.patientunitstayid
),
dx_f AS (
  SELECT d.patientunitstayid,
    LOGICAL_OR(REGEXP_CONTAINS(LOWER(d.diagnosisstring),
                 r'esrd|end stage renal|stage 5|dialysis associated|dialysis access')
            OR REGEXP_CONTAINS(IFNULL(d.icd9code, ''),
                 r'(^|,\s*)(585\.5|585\.6|N18\.5|N18\.6|V45\.1|Z99\.2)')) AS esrd_dx
  FROM `physionet-data.eicu_crd.diagnosis` d
  JOIN cohort USING (patientunitstayid)
  GROUP BY d.patientunitstayid
),
tx_f AS (
  SELECT t.patientunitstayid,
    LOGICAL_OR(REGEXP_CONTAINS(LOWER(t.treatmentstring),
      r'for chronic renal failure|peritoneal dialysis')) AS esrd_tx
  FROM `physionet-data.eicu_crd.treatment` t
  JOIN cohort USING (patientunitstayid)
  GROUP BY t.patientunitstayid
),
ap_f AS (
  SELECT a.patientunitstayid, LOGICAL_OR(a.dialysis = 1) AS esrd_apache
  FROM `physionet-data.eicu_crd.apacheapsvar` a
  JOIN cohort USING (patientunitstayid)
  GROUP BY a.patientunitstayid
),
esrd AS (
  SELECT c.patientunitstayid,
    IFNULL(ph.esrd_ph, FALSE)     AS esrd_ph,
    IFNULL(dx.esrd_dx, FALSE)     AS esrd_dx,
    IFNULL(tx.esrd_tx, FALSE)     AS esrd_tx,
    IFNULL(ap.esrd_apache, FALSE) AS esrd_apache
  FROM cohort c
  LEFT JOIN ph_f ph USING (patientunitstayid)
  LEFT JOIN dx_f dx USING (patientunitstayid)
  LEFT JOIN tx_f tx USING (patientunitstayid)
  LEFT JOIN ap_f ap USING (patientunitstayid)
),
esrd_grp AS (
  SELECT patientunitstayid,
    CASE
      WHEN n_src >= 2                                  THEN 'a: ESRD, 2+ sources'
      WHEN n_src = 1 AND esrd_dx                       THEN 'b: ESRD, diagnosis only'
      WHEN n_src = 1                                   THEN 'c: ESRD, other single source'
      ELSE                                                  'd: not ESRD'
    END AS esrd_group
  FROM (
    SELECT *,
      CAST(esrd_ph AS INT64) + CAST(esrd_dx AS INT64)
        + CAST(esrd_tx AS INT64) + CAST(esrd_apache AS INT64) AS n_src
    FROM esrd
  )
),
dialysis_events AS (
  SELECT t.patientunitstayid, t.treatmentoffset AS t
  FROM `physionet-data.eicu_crd.treatment` t
  JOIN cohort USING (patientunitstayid)
  WHERE REGEXP_CONTAINS(LOWER(t.treatmentstring),
          r'dialys|crrt|cvvh|c v v h|hemofiltration|ultrafiltration|renal replacement')
    AND NOT REGEXP_CONTAINS(LOWER(t.treatmentstring), r'catheter')
  UNION ALL
  SELECT io.patientunitstayid, io.intakeoutputoffset AS t
  FROM `physionet-data.eicu_crd.intakeoutput` io
  JOIN cohort USING (patientunitstayid)
  WHERE REGEXP_CONTAINS(LOWER(io.cellpath), r'output')
    AND REGEXP_CONTAINS(LOWER(io.celllabel),
          r'hemofiltration|dialys|fluid removal|ultrafiltrat|crrt|cvvh')
),
first_dialysis AS (
  SELECT patientunitstayid, MIN(t) AS first_dialysis
  FROM dialysis_events GROUP BY patientunitstayid
),
catheter AS (
  SELECT t.patientunitstayid, MIN(t.treatmentoffset) AS first_dialysis_catheter
  FROM `physionet-data.eicu_crd.treatment` t
  JOIN cohort USING (patientunitstayid)
  WHERE REGEXP_CONTAINS(LOWER(t.treatmentstring), r'catheter for hemodialysis')
  GROUP BY t.patientunitstayid
),
first_cr AS (
  SELECT l.patientunitstayid,
         ARRAY_AGG(l.labresult ORDER BY l.labresultoffset LIMIT 1)[OFFSET(0)] AS first_creat
  FROM `physionet-data.eicu_crd.lab` l
  JOIN cohort USING (patientunitstayid)
  WHERE l.labname = 'creatinine' AND l.labresult BETWEEN 0.2 AND 20
    AND l.labresultoffset >= -1440
  GROUP BY l.patientunitstayid
)
SELECT
  g.esrd_group,
  COUNT(*)                                                         AS n_patients,
  COUNTIF(f.first_dialysis IS NOT NULL)                            AS n_any_dialysis,
  COUNTIF(f.first_dialysis <= 0)                                   AS n_dialysis_at_or_before_admit,
  COUNTIF(f.first_dialysis > 0    AND f.first_dialysis <= 1440)    AS n_dialysis_0_24h,
  COUNTIF(f.first_dialysis > 1440 AND f.first_dialysis <= 4320)    AS n_dialysis_24_72h,
  COUNTIF(f.first_dialysis > 4320 AND f.first_dialysis <= 10080)   AS n_dialysis_72h_7d,
  COUNTIF(f.first_dialysis > 10080)                                AS n_dialysis_after_7d,
  COUNTIF(k.first_dialysis_catheter IS NOT NULL)                   AS n_dialysis_catheter,
  COUNTIF(k.first_dialysis_catheter IS NOT NULL AND f.first_dialysis IS NULL) AS n_catheter_no_dialysis_signal,
  APPROX_QUANTILES(cr.first_creat, 4)                              AS first_creat_quartiles,
  COUNTIF(cr.first_creat >= 4)                                     AS n_first_creat_ge_4
FROM esrd_grp g
LEFT JOIN first_dialysis f USING (patientunitstayid)
LEFT JOIN catheter k       USING (patientunitstayid)
LEFT JOIN first_cr cr      USING (patientunitstayid)
GROUP BY g.esrd_group
ORDER BY g.esrd_group;


-- @query: 06d_baseline_options
-- Baseline creatinine options (D22)
WITH cohort AS (
  SELECT c.patientunitstayid, c.age_num, c.gender, p.ethnicity
  FROM `evocative-ethos-471602-r3.base.eicu_cohort` c
  JOIN `physionet-data.eicu_crd.patient` p USING (patientunitstayid)
  WHERE c.hosp_tx_pct >= 0.8
),
ph_f AS (
  SELECT p.patientunitstayid,
    LOGICAL_OR(REGEXP_CONTAINS(LOWER(p.pasthistorypath),
      r'renal failure - hemodialysis|renal failure - peritoneal dialysis')) AS esrd_ph,
    LOGICAL_OR(REGEXP_CONTAINS(LOWER(p.pasthistorypath),
      r'renal insufficiency|renal failure- not currently dialyzed|renal failure - not currently dialyzed')) AS ckd_ph
  FROM `physionet-data.eicu_crd.pasthistory` p
  JOIN cohort USING (patientunitstayid)
  GROUP BY p.patientunitstayid
),
dx_f AS (
  SELECT d.patientunitstayid,
    LOGICAL_OR(REGEXP_CONTAINS(LOWER(d.diagnosisstring),
                 r'esrd|end stage renal|stage 5|dialysis associated|dialysis access')
            OR REGEXP_CONTAINS(IFNULL(d.icd9code, ''),
                 r'(^|,\s*)(585\.5|585\.6|N18\.5|N18\.6|V45\.1|Z99\.2)')) AS esrd_dx,
    LOGICAL_OR(REGEXP_CONTAINS(LOWER(d.diagnosisstring),
                 r'chronic kidney disease|chronic renal insufficiency|anemia of renal disease')) AS ckd_dx
  FROM `physionet-data.eicu_crd.diagnosis` d
  JOIN cohort USING (patientunitstayid)
  GROUP BY d.patientunitstayid
),
tx_f AS (
  SELECT t.patientunitstayid,
    LOGICAL_OR(REGEXP_CONTAINS(LOWER(t.treatmentstring),
      r'for chronic renal failure|peritoneal dialysis')) AS esrd_tx
  FROM `physionet-data.eicu_crd.treatment` t
  JOIN cohort USING (patientunitstayid)
  GROUP BY t.patientunitstayid
),
ap_f AS (
  SELECT a.patientunitstayid, LOGICAL_OR(a.dialysis = 1) AS esrd_apache
  FROM `physionet-data.eicu_crd.apacheapsvar` a
  JOIN cohort USING (patientunitstayid)
  GROUP BY a.patientunitstayid
),
kidney AS (
  SELECT c.*,
    IFNULL(ph.esrd_ph, FALSE) OR IFNULL(dx.esrd_dx, FALSE)
      OR IFNULL(tx.esrd_tx, FALSE) OR IFNULL(ap.esrd_apache, FALSE) AS esrd_any,
    IFNULL(ph.ckd_ph, FALSE) OR IFNULL(dx.ckd_dx, FALSE)            AS ckd_any
  FROM cohort c
  LEFT JOIN ph_f ph USING (patientunitstayid)
  LEFT JOIN dx_f dx USING (patientunitstayid)
  LEFT JOIN tx_f tx USING (patientunitstayid)
  LEFT JOIN ap_f ap USING (patientunitstayid)
),
cr AS (
  SELECT l.patientunitstayid, l.labresultoffset AS t, l.labresult AS v
  FROM `physionet-data.eicu_crd.lab` l
  JOIN cohort USING (patientunitstayid)
  WHERE l.labname = 'creatinine'
    AND l.labresult BETWEEN 0.2 AND 20
    AND l.labresultoffset >= -10080
),
per_patient AS (
  SELECT
    k.patientunitstayid,
    k.ckd_any,
    MIN(IF(cr.t <= 0, cr.v, NULL))                                    AS cr_pre_min,
    COUNTIF(cr.t <= 0)                                                AS n_cr_pre,
    MIN(cr.t)                                                         AS first_cr_offset,
    ARRAY_AGG(cr.v IGNORE NULLS ORDER BY cr.t LIMIT 1)[SAFE_OFFSET(0)] AS cr_first,
    POW(75 / (175 * POW(k.age_num, -0.203)
                  * IF(k.gender = 'Female', 0.742, 1)
                  * IF(k.ethnicity = 'African American', 1.212, 1)), -1 / 1.154) AS cr_mdrd,
    POW(75 / (175 * POW(k.age_num, -0.203)
                  * IF(k.gender = 'Female', 0.742, 1)), -1 / 1.154)              AS cr_mdrd_racefree
  FROM kidney k
  LEFT JOIN cr USING (patientunitstayid)
  WHERE NOT k.esrd_any
  GROUP BY k.patientunitstayid, k.ckd_any, k.age_num, k.gender, k.ethnicity
)
SELECT
  IF(ckd_any, 'b: CKD (not ESRD)', 'a: no CKD')                       AS ckd_group,
  COUNT(*)                                                            AS n_patients,
  COUNTIF(cr_first IS NULL)                                           AS n_no_creatinine,
  COUNTIF(n_cr_pre >= 1)                                              AS n_with_pre_icu_cr,
  COUNTIF(n_cr_pre >= 2)                                              AS n_with_2plus_pre_icu_cr,
  APPROX_QUANTILES(IF(n_cr_pre >= 1, -first_cr_offset / 60, NULL), 4)  AS hours_first_cr_before_icu_quartiles,
  APPROX_QUANTILES(cr_pre_min, 4)                                     AS optA_pre_icu_min_quartiles,
  APPROX_QUANTILES(cr_first, 4)                                       AS optB_first_quartiles,
  APPROX_QUANTILES(cr_mdrd, 4)                                        AS optC_mdrd_quartiles,
  APPROX_QUANTILES(cr_mdrd_racefree, 4)                               AS optC_mdrd_racefree_quartiles,
  COUNTIF(cr_first >= 1.5 * cr_mdrd)                                  AS n_first_ge_1_5x_mdrd,
  COUNTIF(cr_first >= 1.5 * cr_mdrd_racefree)                         AS n_first_ge_1_5x_mdrd_racefree,
  COUNTIF(cr_first >= 2.0 * cr_mdrd)                                  AS n_first_ge_2x_mdrd,
  COUNTIF(cr_pre_min >= 1.5 * cr_mdrd)                                AS n_pre_icu_min_ge_1_5x_mdrd
FROM per_patient
GROUP BY ckd_group
ORDER BY ckd_group;


-- @query: 06d2_t0_staging_by_baseline_version
-- Stage at time zero under three baseline versions (D22, D24, D26)
WITH cohort AS (
  SELECT c.patientunitstayid, c.age_num, c.gender
  FROM `evocative-ethos-471602-r3.base.eicu_cohort` c
  WHERE c.hosp_tx_pct >= 0.8
),
ph_f AS (
  SELECT p.patientunitstayid,
    LOGICAL_OR(REGEXP_CONTAINS(LOWER(p.pasthistorypath),
      r'renal failure - hemodialysis|renal failure - peritoneal dialysis')) AS esrd_ph,
    LOGICAL_OR(REGEXP_CONTAINS(LOWER(p.pasthistorypath),
      r'renal insufficiency|renal failure- not currently dialyzed|renal failure - not currently dialyzed')) AS ckd_ph
  FROM `physionet-data.eicu_crd.pasthistory` p
  JOIN cohort USING (patientunitstayid)
  GROUP BY p.patientunitstayid
),
dx_f AS (
  SELECT d.patientunitstayid,
    LOGICAL_OR(REGEXP_CONTAINS(LOWER(d.diagnosisstring),
                 r'esrd|end stage renal|stage 5|dialysis associated|dialysis access')
            OR REGEXP_CONTAINS(IFNULL(d.icd9code, ''),
                 r'(^|,\s*)(585\.5|585\.6|N18\.5|N18\.6|V45\.1|Z99\.2)')) AS esrd_dx,
    LOGICAL_OR(REGEXP_CONTAINS(LOWER(d.diagnosisstring),
                 r'chronic kidney disease|chronic renal insufficiency|anemia of renal disease')) AS ckd_dx
  FROM `physionet-data.eicu_crd.diagnosis` d
  JOIN cohort USING (patientunitstayid)
  GROUP BY d.patientunitstayid
),
tx_f AS (
  SELECT t.patientunitstayid,
    LOGICAL_OR(REGEXP_CONTAINS(LOWER(t.treatmentstring),
      r'for chronic renal failure|peritoneal dialysis')) AS esrd_tx
  FROM `physionet-data.eicu_crd.treatment` t
  JOIN cohort USING (patientunitstayid)
  GROUP BY t.patientunitstayid
),
ap_f AS (
  SELECT a.patientunitstayid, LOGICAL_OR(a.dialysis = 1) AS esrd_apache
  FROM `physionet-data.eicu_crd.apacheapsvar` a
  JOIN cohort USING (patientunitstayid)
  GROUP BY a.patientunitstayid
),
kidney AS (
  SELECT c.*,
    IFNULL(ph.esrd_ph, FALSE) OR IFNULL(dx.esrd_dx, FALSE)
      OR IFNULL(tx.esrd_tx, FALSE) OR IFNULL(ap.esrd_apache, FALSE) AS esrd_any,
    IFNULL(ph.ckd_ph, FALSE) OR IFNULL(dx.ckd_dx, FALSE)            AS ckd_any
  FROM cohort c
  LEFT JOIN ph_f ph USING (patientunitstayid)
  LEFT JOIN dx_f dx USING (patientunitstayid)
  LEFT JOIN tx_f tx USING (patientunitstayid)
  LEFT JOIN ap_f ap USING (patientunitstayid)
),
rrt_events AS (
  SELECT t.patientunitstayid, t.treatmentoffset AS t
  FROM `physionet-data.eicu_crd.treatment` t
  JOIN cohort USING (patientunitstayid)
  WHERE REGEXP_CONTAINS(LOWER(t.treatmentstring),
          r'dialys|crrt|cvvh|c v v h|hemofiltration|ultrafiltration|renal replacement')
    AND NOT REGEXP_CONTAINS(LOWER(t.treatmentstring), r'catheter')
  UNION ALL
  SELECT io.patientunitstayid, io.intakeoutputoffset AS t
  FROM `physionet-data.eicu_crd.intakeoutput` io
  JOIN cohort USING (patientunitstayid)
  WHERE REGEXP_CONTAINS(LOWER(io.cellpath), r'output')
    AND REGEXP_CONTAINS(LOWER(io.celllabel),
          r'hemofiltration|dialys|fluid removal|ultrafiltrat|crrt|cvvh')
),
first_rrt AS (
  SELECT patientunitstayid, MIN(t) AS first_rrt FROM rrt_events GROUP BY patientunitstayid
),
cr AS (
  SELECT l.patientunitstayid, l.labresultoffset AS t, l.labresult AS v
  FROM `physionet-data.eicu_crd.lab` l
  JOIN cohort USING (patientunitstayid)
  LEFT JOIN first_rrt r USING (patientunitstayid)
  WHERE l.labname = 'creatinine'
    AND l.labresult BETWEEN 0.2 AND 20
    AND l.labresultoffset >= -10080
    AND (r.first_rrt IS NULL OR l.labresultoffset < r.first_rrt)
),
per_patient AS (
  SELECT
    k.patientunitstayid,
    k.ckd_any,
    IFNULL(ANY_VALUE(r.first_rrt) <= 360, FALSE)                               AS rrt_by_t0,
    MIN(cr.v)                                                                  AS min_all,
    MIN(IF(cr.t <= 360, cr.v, NULL))                                           AS min_pre,
    MIN(IF(cr.t BETWEEN -2880 AND 360, cr.v, NULL))                            AS min_48h,
    ARRAY_AGG(IF(cr.t BETWEEN -1440 AND 360, cr.v, NULL) IGNORE NULLS
              ORDER BY cr.t DESC, cr.v DESC LIMIT 1)[SAFE_OFFSET(0)]                      AS tz_cr,
    POW(75 / (175 * POW(k.age_num, -0.203) * IF(k.gender = 'Female', 0.742, 1)), -1 / 1.154) AS mdrd175,
    POW(75 / (186 * POW(k.age_num, -0.203) * IF(k.gender = 'Female', 0.742, 1)), -1 / 1.154) AS mdrd186
  FROM kidney k
  LEFT JOIN cr USING (patientunitstayid)
  LEFT JOIN first_rrt r USING (patientunitstayid)
  WHERE NOT k.esrd_any
  GROUP BY k.patientunitstayid, k.ckd_any, k.age_num, k.gender
),
methods AS (
  SELECT p.patientunitstayid, p.ckd_any, p.rrt_by_t0, p.tz_cr, p.min_48h, m.method, m.baseline, m.src
  FROM per_patient p,
  UNNEST([
    STRUCT('1: MIMIC as written (whole stay, 186)' AS method,
           IF(p.ckd_any, p.min_all, IF(p.min_all < 1.1, p.min_all, p.mdrd186)) AS baseline,
           IF(p.ckd_any, IF(p.min_all IS NULL, 'missing', 'measured'),
              IF(p.min_all < 1.1, 'measured', 'mdrd')) AS src),
    STRUCT('2: adapted, up to time zero (175)',
           IF(p.ckd_any, p.min_pre, IF(p.min_pre < 1.1, p.min_pre, p.mdrd175)),
           IF(p.ckd_any, IF(p.min_pre IS NULL, 'missing', 'measured'),
              IF(p.min_pre < 1.1, 'measured', 'mdrd'))),
    STRUCT('3: adapted, up to time zero (186)',
           IF(p.ckd_any, p.min_pre, IF(p.min_pre < 1.1, p.min_pre, p.mdrd186)),
           IF(p.ckd_any, IF(p.min_pre IS NULL, 'missing', 'measured'),
              IF(p.min_pre < 1.1, 'measured', 'mdrd')))
  ]) m
),
staged AS (
  SELECT *,
    CASE
      WHEN rrt_by_t0                                                   THEN 3
      WHEN tz_cr IS NULL OR baseline IS NULL                           THEN NULL
      WHEN tz_cr >= 3.0 * baseline
        OR (tz_cr >= 4.0 AND (tz_cr >= 1.5 * baseline
                              OR tz_cr - min_48h >= 0.3))              THEN 3
      WHEN tz_cr >= 2.0 * baseline                                     THEN 2
      WHEN tz_cr >= 1.5 * baseline OR tz_cr - min_48h >= 0.3           THEN 1
      ELSE 0
    END AS stage_t0
  FROM methods
)
SELECT
  method,
  IF(ckd_any, 'b: CKD (not ESRD)', 'a: no CKD')                 AS ckd_group,
  COUNT(*)                                                      AS n_patients,
  COUNTIF(src = 'measured')                                     AS n_baseline_measured,
  COUNTIF(src = 'mdrd')                                         AS n_baseline_mdrd,
  COUNTIF(src = 'missing')                                      AS n_baseline_missing,
  APPROX_QUANTILES(baseline, 4)                                 AS baseline_quartiles,
  COUNTIF(tz_cr IS NULL AND NOT rrt_by_t0)                      AS n_no_t0_creatinine,
  COUNTIF(stage_t0 = 0)                                         AS n_stage0_at_t0,
  COUNTIF(stage_t0 = 1)                                         AS n_stage1_at_t0,
  COUNTIF(stage_t0 = 2)                                         AS n_stage2_at_t0,
  COUNTIF(stage_t0 = 3)                                         AS n_stage3_at_t0,
  COUNTIF(stage_t0 IS NULL)                                     AS n_stage_unknown
FROM staged
GROUP BY method, ckd_group
ORDER BY method, ckd_group;


-- @query: 06d3_ckd_range_baseline
-- CKD staging with the recorded creatinine range as baseline (D21, D22)
WITH cohort AS (
  SELECT c.patientunitstayid
  FROM `evocative-ethos-471602-r3.base.eicu_cohort` c
  WHERE c.hosp_tx_pct >= 0.8
),
ph AS (
  SELECT p.patientunitstayid, LOWER(p.pasthistorypath) AS l
  FROM `physionet-data.eicu_crd.pasthistory` p
  JOIN cohort USING (patientunitstayid)
),
ph_f AS (
  SELECT patientunitstayid,
    LOGICAL_OR(REGEXP_CONTAINS(l, r'renal failure - hemodialysis|renal failure - peritoneal dialysis')) AS esrd_ph,
    LOGICAL_OR(REGEXP_CONTAINS(l, r'renal insufficiency|renal failure- not currently dialyzed|renal failure - not currently dialyzed')) AS ckd_ph,
    LOGICAL_OR(REGEXP_CONTAINS(l, r'renal failure- not currently dialyzed|renal failure - not currently dialyzed')) AS ph_not_dialyzed,
    LOGICAL_OR(REGEXP_CONTAINS(l, r'baseline creatinine unknown'))                                   AS ph_range_unknown,
    MAX(CASE
          WHEN REGEXP_CONTAINS(l, r'creatinine > 5')  THEN 5
          WHEN REGEXP_CONTAINS(l, r'creatinine 4-5')  THEN 4
          WHEN REGEXP_CONTAINS(l, r'creatinine 3-4')  THEN 3
          WHEN REGEXP_CONTAINS(l, r'creatinine 2-3')  THEN 2
          WHEN REGEXP_CONTAINS(l, r'creatinine 1-2')  THEN 1
        END)                                                                                           AS ph_range,
    COUNT(DISTINCT CASE
          WHEN REGEXP_CONTAINS(l, r'creatinine (> 5|4-5|3-4|2-3|1-2)') THEN l END)                     AS n_ranges
  FROM ph
  GROUP BY patientunitstayid
),
dx_f AS (
  SELECT d.patientunitstayid,
    LOGICAL_OR(REGEXP_CONTAINS(LOWER(d.diagnosisstring),
                 r'esrd|end stage renal|stage 5|dialysis associated|dialysis access')
            OR REGEXP_CONTAINS(IFNULL(d.icd9code, ''),
                 r'(^|,\s*)(585\.5|585\.6|N18\.5|N18\.6|V45\.1|Z99\.2)')) AS esrd_dx,
    LOGICAL_OR(REGEXP_CONTAINS(LOWER(d.diagnosisstring),
                 r'chronic kidney disease|chronic renal insufficiency|anemia of renal disease')) AS ckd_dx
  FROM `physionet-data.eicu_crd.diagnosis` d
  JOIN cohort USING (patientunitstayid)
  GROUP BY d.patientunitstayid
),
tx_f AS (
  SELECT t.patientunitstayid,
    LOGICAL_OR(REGEXP_CONTAINS(LOWER(t.treatmentstring),
      r'for chronic renal failure|peritoneal dialysis')) AS esrd_tx
  FROM `physionet-data.eicu_crd.treatment` t
  JOIN cohort USING (patientunitstayid)
  GROUP BY t.patientunitstayid
),
ap_f AS (
  SELECT a.patientunitstayid, LOGICAL_OR(a.dialysis = 1) AS esrd_apache
  FROM `physionet-data.eicu_crd.apacheapsvar` a
  JOIN cohort USING (patientunitstayid)
  GROUP BY a.patientunitstayid
),
ckd AS (
  SELECT c.patientunitstayid,
    ph.ph_range, IFNULL(ph.n_ranges, 0) AS n_ranges,
    CASE
      WHEN ph.ph_range IS NOT NULL                 THEN CONCAT('range ', CASE ph.ph_range
                                                       WHEN 1 THEN '1-2' WHEN 2 THEN '2-3' WHEN 3 THEN '3-4'
                                                       WHEN 4 THEN '4-5' ELSE '> 5' END)
      WHEN IFNULL(ph.ph_range_unknown, FALSE)      THEN 'range unknown'
      WHEN IFNULL(ph.ph_not_dialyzed, FALSE)       THEN 'not currently dialyzed (no range)'
      ELSE                                              'diagnosis only'
    END AS range_group
  FROM cohort c
  LEFT JOIN ph_f ph USING (patientunitstayid)
  LEFT JOIN dx_f dx USING (patientunitstayid)
  LEFT JOIN tx_f tx USING (patientunitstayid)
  LEFT JOIN ap_f ap USING (patientunitstayid)
  WHERE NOT (IFNULL(ph.esrd_ph, FALSE) OR IFNULL(dx.esrd_dx, FALSE)
             OR IFNULL(tx.esrd_tx, FALSE) OR IFNULL(ap.esrd_apache, FALSE))
    AND (IFNULL(ph.ckd_ph, FALSE) OR IFNULL(dx.ckd_dx, FALSE))
),
rrt_events AS (
  SELECT t.patientunitstayid, t.treatmentoffset AS t
  FROM `physionet-data.eicu_crd.treatment` t
  JOIN ckd USING (patientunitstayid)
  WHERE REGEXP_CONTAINS(LOWER(t.treatmentstring),
          r'dialys|crrt|cvvh|c v v h|hemofiltration|ultrafiltration|renal replacement')
    AND NOT REGEXP_CONTAINS(LOWER(t.treatmentstring), r'catheter')
  UNION ALL
  SELECT io.patientunitstayid, io.intakeoutputoffset AS t
  FROM `physionet-data.eicu_crd.intakeoutput` io
  JOIN ckd USING (patientunitstayid)
  WHERE REGEXP_CONTAINS(LOWER(io.cellpath), r'output')
    AND REGEXP_CONTAINS(LOWER(io.celllabel),
          r'hemofiltration|dialys|fluid removal|ultrafiltrat|crrt|cvvh')
),
first_rrt AS (
  SELECT patientunitstayid, MIN(t) AS first_rrt FROM rrt_events GROUP BY patientunitstayid
),
cr AS (
  SELECT l.patientunitstayid, l.labresultoffset AS t, l.labresult AS v
  FROM `physionet-data.eicu_crd.lab` l
  JOIN ckd USING (patientunitstayid)
  LEFT JOIN first_rrt r USING (patientunitstayid)
  WHERE l.labname = 'creatinine'
    AND l.labresult BETWEEN 0.2 AND 20
    AND l.labresultoffset >= -10080
    AND (r.first_rrt IS NULL OR l.labresultoffset < r.first_rrt)
),
per_patient AS (
  SELECT
    k.patientunitstayid, k.range_group, k.ph_range, k.n_ranges,
    IFNULL(ANY_VALUE(r.first_rrt) <= 360, FALSE)                               AS rrt_by_t0,
    MIN(IF(cr.t <= 360, cr.v, NULL))                                           AS min_pre,
    MIN(IF(cr.t BETWEEN -2880 AND 360, cr.v, NULL))                            AS min_48h,
    ARRAY_AGG(IF(cr.t BETWEEN -1440 AND 360, cr.v, NULL) IGNORE NULLS
              ORDER BY cr.t DESC, cr.v DESC LIMIT 1)[SAFE_OFFSET(0)]                      AS tz_cr
  FROM ckd k
  LEFT JOIN cr USING (patientunitstayid)
  LEFT JOIN first_rrt r USING (patientunitstayid)
  GROUP BY k.patientunitstayid, k.range_group, k.ph_range, k.n_ranges
),
methods AS (
  SELECT p.*, m.method, m.baseline
  FROM per_patient p,
  UNNEST([
    STRUCT('a: v2 (lowest measured up to time zero)' AS method, p.min_pre AS baseline),
    STRUCT('b: range midpoint',
           IFNULL(CASE p.ph_range WHEN 1 THEN 1.5 WHEN 2 THEN 2.5 WHEN 3 THEN 3.5
                                  WHEN 4 THEN 4.5 WHEN 5 THEN 5.5 END, p.min_pre)),
    STRUCT('c: range lower bound',
           IFNULL(CAST(p.ph_range AS FLOAT64), p.min_pre))
  ]) m
),
staged AS (
  SELECT *,
    CASE
      WHEN rrt_by_t0                                                   THEN 3
      WHEN tz_cr IS NULL OR baseline IS NULL                           THEN NULL
      WHEN tz_cr >= 3.0 * baseline
        OR (tz_cr >= 4.0 AND (tz_cr >= 1.5 * baseline
                              OR tz_cr - min_48h >= 0.3))              THEN 3
      WHEN tz_cr >= 2.0 * baseline                                     THEN 2
      WHEN tz_cr >= 1.5 * baseline OR tz_cr - min_48h >= 0.3           THEN 1
      ELSE 0
    END AS stage_t0
  FROM methods
)
SELECT
  range_group,
  method,
  COUNT(*)                                                       AS n_patients,
  COUNTIF(n_ranges > 1)                                          AS n_more_than_one_range,
  COUNTIF(min_pre IS NULL)                                       AS n_no_measured_value,
  APPROX_QUANTILES(min_pre, 4)                                   AS min_measured_quartiles,
  COUNTIF(ph_range BETWEEN 1 AND 4 AND min_pre > ph_range + 1)   AS n_measured_above_range,
  COUNTIF(stage_t0 = 0)                                          AS n_stage0_at_t0,
  COUNTIF(stage_t0 = 1)                                          AS n_stage1_at_t0,
  COUNTIF(stage_t0 = 2)                                          AS n_stage2_at_t0,
  COUNTIF(stage_t0 = 3)                                          AS n_stage3_at_t0,
  COUNTIF(stage_t0 IS NULL)                                      AS n_stage_unknown
FROM staged
GROUP BY range_group, method
ORDER BY range_group, method;


-- @query: 06e_kidney_flow
-- Kidney exclusion flow (D20-D26)
SELECT
  IFNULL(exclusion_reason, '6: passes kidney rules (stage 0)') AS step,
  COUNT(*)                                              AS n_patients,
  COUNTIF(is_ckd)                                       AS n_with_ckd,
  COUNTIF(t0_aki_stage = 1)                             AS n_stage1,
  COUNTIF(t0_aki_stage = 2)                             AS n_stage2,
  COUNTIF(t0_aki_stage = 3)                             AS n_stage3,
  COUNTIF(kidney_transplant)                            AS n_kidney_transplant
FROM `evocative-ethos-471602-r3.base.eicu_kidney_v1`
GROUP BY step
ORDER BY step;


-- @query: 06f_baseline_sources
-- Baseline source among patients passing the kidney rules (D22)
SELECT
  baseline_source,
  COUNT(*)                              AS n_patients,
  APPROX_QUANTILES(baseline_creat, 4)   AS baseline_quartiles
FROM `evocative-ethos-471602-r3.base.eicu_kidney_v1`
WHERE exclusion_reason IS NULL
GROUP BY baseline_source
ORDER BY n_patients DESC;
