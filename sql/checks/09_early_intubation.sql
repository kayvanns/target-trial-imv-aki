-- Checks 09: intubation timing near ICU admission

-- @query: 09a_imv_start_10min_bins
-- IMV start in 10-minute bins, first 4 h (is the 60-minute cutoff on a cliff?)
WITH cohort AS (
  SELECT *
  FROM `evocative-ethos-471602-r3.base.eicu_tte_cohort`
  WHERE kidney_ok_b
    AND NOT (ambiguous_ventilation OR kidney_transplant OR chronic_trach
             OR care_limited_at_t0 OR chronic_lung_disease)
    AND imv_status = 'imv'
    AND imv_start <= 240
)
SELECT
  IF(imv_start < 0, -10, CAST(FLOOR(imv_start / 10) * 10 AS INT64)) AS bin_start_min,
  COUNT(*)                                                          AS n
FROM cohort
GROUP BY bin_start_min
ORDER BY bin_start_min;


-- @query: 09b_early_imv_by_admit_source
-- Where patients came from, by IMV timing group
WITH cohort AS (
  SELECT
    *,
    CASE
      WHEN imv_status != 'imv' OR imv_start > 1440 THEN 'e: not intubated by 24 h'
      WHEN imv_start <= 60                         THEN 'a: 0-60 min (excluded)'
      WHEN imv_start <= 120                        THEN 'b: 61-120 min'
      WHEN imv_start <= 360                        THEN 'c: 2-6 h'
      ELSE                                              'd: 6-24 h'
    END AS imv_group
  FROM `evocative-ethos-471602-r3.base.eicu_tte_cohort`
  WHERE kidney_ok_b
    AND NOT (ambiguous_ventilation OR kidney_transplant OR chronic_trach
             OR care_limited_at_t0 OR chronic_lung_disease)
)
SELECT
  imv_group,
  unitadmitsource,
  COUNT(*)                                                         AS n,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY imv_group), 1) AS pct_of_group,
  APPROX_QUANTILES(-hospitaladmitoffset / 60, 2)[OFFSET(1)]        AS median_hours_in_hospital_before_icu
FROM cohort
GROUP BY imv_group, unitadmitsource
HAVING COUNT(*) >= 5
ORDER BY imv_group, n DESC;


-- @query: 09c_early_imv_by_source
-- How IMV was found, and how far apart the two sources are
WITH cohort AS (
  SELECT
    *,
    CASE
      WHEN imv_start <= 60  THEN 'a: 0-60 min (excluded)'
      WHEN imv_start <= 120 THEN 'b: 61-120 min'
      WHEN imv_start <= 360 THEN 'c: 2-6 h'
      ELSE                       'd: 6-24 h'
    END AS imv_group
  FROM `evocative-ethos-471602-r3.base.eicu_tte_cohort`
  WHERE kidney_ok_b
    AND NOT (ambiguous_ventilation OR kidney_transplant OR chronic_trach
             OR care_limited_at_t0 OR chronic_lung_disease)
    AND imv_status = 'imv'
    AND imv_start <= 1440
)
SELECT
  imv_group,
  COUNT(*)                                                             AS n,
  COUNTIF(imv_source = 'both')                                         AS n_both,
  COUNTIF(imv_source = 'treatment_only')                               AS n_treatment_only,
  COUNTIF(imv_source = 'charting_only')                                AS n_charting_only,
  COUNTIF(imv_source = 'both' AND first_vent_marker < first_imv_tx)    AS n_settings_before_tx_entry,
  APPROX_QUANTILES(IF(imv_source = 'both',
                      ABS(first_imv_tx - first_vent_marker), NULL), 2)[OFFSET(1)] AS median_min_between_sources
FROM cohort
GROUP BY imv_group
ORDER BY imv_group;