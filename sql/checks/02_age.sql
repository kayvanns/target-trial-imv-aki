-- Checks 02: age. Needs pipeline 01.


-- @query: 02a_age
-- Age format and adults (D04)
SELECT
  COUNT(*)                                                     AS n_total,
  COUNTIF(age IS NULL OR TRIM(age) = '')                       AS n_age_missing,
  COUNTIF(TRIM(age) = '> 89')                                  AS n_age_over_89,
  COUNTIF(SAFE_CAST(age AS INT64) < 18)                        AS n_under_18,
  COUNTIF(SAFE_CAST(age AS INT64) >= 18 OR TRIM(age) = '> 89') AS n_adult,
  COUNTIF(TRIM(age) != '' AND TRIM(age) != '> 89'
          AND SAFE_CAST(age AS INT64) IS NULL)                 AS n_unexpected_format
FROM `evocative-ethos-471602-r3.base.eicu_sepsis_no_pneumonia`;
