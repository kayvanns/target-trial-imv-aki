-- Pipeline 02: adults, hospital treatment recording, invasive ventilation (D04-D08).
-- Builds base.eicu_cohort. Primary cohort: hosp_tx_pct >= 0.8.

CREATE OR REPLACE TABLE `evocative-ethos-471602-r3.base.eicu_cohort` AS
WITH

adults AS (
  SELECT
    b.*,
    CASE WHEN TRIM(b.age) = '> 89' THEN 90
         ELSE SAFE_CAST(b.age AS INT64) END AS age_num
  FROM `evocative-ethos-471602-r3.base.eicu_sepsis_no_pneumonia` b
  WHERE b.icu_order_in_hosp = 1
    AND (SAFE_CAST(b.age AS INT64) >= 18 OR TRIM(b.age) = '> 89')
),

tx_any AS (
  SELECT DISTINCT patientunitstayid
  FROM `physionet-data.eicu_crd.treatment`
),

hosp_usage AS (
  SELECT
    a.hospitalid,
    SAFE_DIVIDE(COUNTIF(t.patientunitstayid IS NOT NULL), COUNT(*)) AS hosp_tx_pct
  FROM adults a
  LEFT JOIN tx_any t USING (patientunitstayid)
  GROUP BY a.hospitalid
),

-- Treatment-table entries (D06)
tx_summary AS (
  SELECT
    t.patientunitstayid,
    MIN(IF(REGEXP_CONTAINS(LOWER(t.treatmentstring), r'mechanical ventilation|endotracheal tube|intubat')
           AND NOT REGEXP_CONTAINS(LOWER(t.treatmentstring), r'non-invasive|endotracheal tube removal'),
           t.treatmentoffset, NULL))                                        AS first_imv_tx,
    MIN(IF(REGEXP_CONTAINS(LOWER(t.treatmentstring), r'non-invasive|bipap'),
           t.treatmentoffset, NULL))                                        AS first_niv_tx,
    MIN(IF(REGEXP_CONTAINS(LOWER(t.treatmentstring), r'tracheostomy|trach collar'),
           t.treatmentoffset, NULL))                                        AS first_trach_tx
  FROM `physionet-data.eicu_crd.treatment` t
  JOIN adults USING (patientunitstayid)
  GROUP BY t.patientunitstayid
),

-- Ventilator settings in respiratory charting (D07)
vent_marker AS (
  SELECT rc.patientunitstayid, MIN(rc.respchartoffset) AS first_vent_marker
  FROM `physionet-data.eicu_crd.respiratorycharting` rc
  JOIN adults USING (patientunitstayid)
  WHERE rc.respchartvaluelabel IN ('Tidal Volume (set)', 'Vent Rate', 'Plateau Pressure')
    AND SAFE_CAST(rc.respchartvalue AS FLOAT64) > 0
  GROUP BY rc.patientunitstayid
)

SELECT
  a.*,
  h.hosp_tx_pct,
  ts.first_imv_tx,
  vm.first_vent_marker,
  ts.first_niv_tx,
  ts.first_trach_tx,

  -- Ventilation status; start = earliest of treatment entry and ventilator setting (D08)
  CASE
    WHEN ts.first_imv_tx IS NOT NULL                                   THEN 'imv'
    WHEN vm.first_vent_marker IS NOT NULL AND ts.first_niv_tx IS NULL  THEN 'imv'
    WHEN vm.first_vent_marker IS NOT NULL                              THEN 'ambiguous'
    ELSE 'none'
  END AS imv_status,

  CASE
    WHEN ts.first_imv_tx IS NOT NULL AND vm.first_vent_marker IS NOT NULL
      THEN LEAST(ts.first_imv_tx, vm.first_vent_marker)
    WHEN ts.first_imv_tx IS NOT NULL                                   THEN ts.first_imv_tx
    WHEN vm.first_vent_marker IS NOT NULL AND ts.first_niv_tx IS NULL  THEN vm.first_vent_marker
    ELSE NULL
  END AS imv_start,

  CASE
    WHEN ts.first_imv_tx IS NOT NULL AND vm.first_vent_marker IS NOT NULL THEN 'both'
    WHEN ts.first_imv_tx IS NOT NULL                                      THEN 'treatment_only'
    WHEN vm.first_vent_marker IS NOT NULL AND ts.first_niv_tx IS NULL     THEN 'charting_only'
    ELSE NULL
  END AS imv_source

FROM adults a
JOIN hosp_usage h USING (hospitalid)
LEFT JOIN tx_summary  ts USING (patientunitstayid)
LEFT JOIN vent_marker vm USING (patientunitstayid);
