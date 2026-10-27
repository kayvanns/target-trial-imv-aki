-- Checks 04: ventilator settings and the final ventilation definition.
-- Primary cohort (hosp_tx_pct >= 0.8). Needs pipeline 02.


-- @query: 04a_respcharting_labels
-- Charting labels in ventilated vs non-ventilated patients (D07)
WITH cohort AS (
  SELECT patientunitstayid, first_imv_tx IS NOT NULL AS vent_tx
  FROM `evocative-ethos-471602-r3.base.eicu_cohort`
  WHERE hosp_tx_pct >= 0.8
),
group_sizes AS (
  SELECT COUNTIF(vent_tx) AS n_vent_total, COUNTIF(NOT vent_tx) AS n_notvent_total
  FROM cohort
),
labels AS (
  SELECT
    rc.respcharttypecat,
    rc.respchartvaluelabel,
    COUNT(DISTINCT IF(c.vent_tx,     rc.patientunitstayid, NULL)) AS n_vent_patients,
    COUNT(DISTINCT IF(NOT c.vent_tx, rc.patientunitstayid, NULL)) AS n_notvent_patients
  FROM `physionet-data.eicu_crd.respiratorycharting` rc
  JOIN cohort c USING (patientunitstayid)
  GROUP BY rc.respcharttypecat, rc.respchartvaluelabel
)
SELECT
  l.respcharttypecat,
  l.respchartvaluelabel,
  l.n_vent_patients,
  l.n_notvent_patients,
  ROUND(100 * SAFE_DIVIDE(l.n_vent_patients,    g.n_vent_total),    1) AS pct_of_ventilated,
  ROUND(100 * SAFE_DIVIDE(l.n_notvent_patients, g.n_notvent_total), 1) AS pct_of_not_ventilated,
  g.n_vent_total,
  g.n_notvent_total
FROM labels l
CROSS JOIN group_sizes g
WHERE l.n_vent_patients + l.n_notvent_patients >= 100
ORDER BY l.n_vent_patients + l.n_notvent_patients DESC;


-- @query: 04b_vent_settings_vs_treatment
-- Ventilator settings vs treatment-table timing (D08)
WITH cohort AS (
  SELECT patientunitstayid, first_imv_tx, first_vent_marker,
         first_niv_tx IS NOT NULL AS has_niv_entry
  FROM `evocative-ethos-471602-r3.base.eicu_cohort`
  WHERE hosp_tx_pct >= 0.8
)
SELECT
  CASE
    WHEN first_imv_tx IS NULL   THEN 'e: no IMV in treatment table'
    WHEN first_imv_tx <= 60     THEN 'a: IMV entry <= 1 h'
    WHEN first_imv_tx <= 1440   THEN 'b: 1-24 h'
    WHEN first_imv_tx <= 4320   THEN 'c: 24-72 h'
    ELSE                             'd: > 72 h'
  END                                                         AS tx_group,
  COUNT(*)                                                    AS n_patients,
  COUNTIF(first_vent_marker IS NOT NULL)                      AS n_with_vent_marker,
  COUNTIF(first_vent_marker IS NOT NULL AND has_niv_entry)    AS n_marker_and_niv_entry,
  COUNTIF(first_vent_marker IS NOT NULL AND NOT has_niv_entry) AS n_marker_no_niv_entry,
  COUNTIF(first_vent_marker <= 0)                             AS n_marker_at_or_before_admit,
  COUNTIF(first_vent_marker > 0 AND first_vent_marker <= 60)  AS n_marker_0_1h,
  COUNTIF(ABS(first_vent_marker - first_imv_tx) <= 60)        AS n_marker_within_1h_of_tx,
  COUNTIF(first_vent_marker < first_imv_tx - 60)              AS n_marker_gt1h_before_tx,
  COUNTIF(first_vent_marker > first_imv_tx + 60)              AS n_marker_gt1h_after_tx,
  APPROX_QUANTILES(first_vent_marker - first_imv_tx, 4)       AS marker_minus_tx_quartiles
FROM cohort
GROUP BY tx_group
ORDER BY tx_group;


-- @query: 04c_combined_vent_definition
-- Final ventilation definition (D08-D10)
SELECT
  COUNT(*)                                                    AS n_adults_all_hospitals,
  COUNTIF(hosp_tx_pct >= 0.8)                                 AS n_primary_cohort,
  COUNT(DISTINCT IF(hosp_tx_pct >= 0.8, hospitalid, NULL))    AS n_primary_hospitals,
  COUNTIF(hosp_tx_pct >= 0.8 AND imv_status = 'imv')          AS n_imv,
  COUNTIF(hosp_tx_pct >= 0.8 AND imv_source = 'charting_only') AS n_imv_added_from_charting,
  COUNTIF(hosp_tx_pct >= 0.8 AND imv_status = 'ambiguous')    AS n_ambiguous,
  COUNTIF(hosp_tx_pct >= 0.8 AND imv_start <= 0)              AS n_start_at_or_before_admit,
  COUNTIF(hosp_tx_pct >= 0.8 AND imv_start > 0    AND imv_start <= 60)   AS n_start_0_1h,
  COUNTIF(hosp_tx_pct >= 0.8 AND imv_start > 60   AND imv_start <= 1440) AS n_start_1_24h,
  COUNTIF(hosp_tx_pct >= 0.8 AND imv_start > 1440 AND imv_start <= 4320) AS n_start_24_72h,
  COUNTIF(hosp_tx_pct >= 0.8 AND imv_start > 4320)            AS n_start_after_72h,
  COUNTIF(hosp_tx_pct >= 0.8 AND first_trach_tx <= 60)        AS n_trach_within_1h
FROM `evocative-ethos-471602-r3.base.eicu_cohort`;
