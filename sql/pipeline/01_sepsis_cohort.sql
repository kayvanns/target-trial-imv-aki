-- Pipeline 01: sepsis without pneumonia, one ICU stay per patient (D01-D03).
-- Builds base.eicu_sepsis_stays and base.eicu_sepsis_no_pneumonia.

-- Diagnoses recorded within 24 h of ICU admission (D01, D02)
DECLARE window_min INT64 DEFAULT 1440;

CREATE OR REPLACE TABLE `evocative-ethos-471602-r3.base.eicu_sepsis_stays` AS
WITH

sepsis_dx AS (
  SELECT
    patientunitstayid,
    STRING_AGG(DISTINCT diagnosisstring, ' ; ') AS sepsis_dx_string,
    STRING_AGG(DISTINCT icd9code, ' ; ')        AS sepsis_dx_icd
  FROM `physionet-data.eicu_crd.diagnosis`
  WHERE diagnosisoffset <= window_min
    AND (
      LOWER(diagnosisstring) LIKE '%sepsis%'
      OR REGEXP_CONTAINS(icd9code, r'(^|,\s*)(038\.\d+|995\.91|995\.92|785\.52|A41\.\d+|R65\.2\d?)')
    )
  GROUP BY patientunitstayid
),

sepsis_admitdx AS (
  SELECT
    patientunitstayid,
    STRING_AGG(DISTINCT admitdxpath, ' ; ') AS sepsis_admitdx_path
  FROM `physionet-data.eicu_crd.admissiondx`
  WHERE admitdxenteredoffset <= window_min
    AND LOWER(admitdxpath) LIKE '%sepsis%'
  GROUP BY patientunitstayid
),

sepsis_cohort AS (
  SELECT
    COALESCE(d.patientunitstayid, a.patientunitstayid) AS patientunitstayid,
    d.sepsis_dx_string,
    d.sepsis_dx_icd,
    a.sepsis_admitdx_path,
    CASE
      WHEN d.patientunitstayid IS NOT NULL AND a.patientunitstayid IS NOT NULL THEN 'both'
      WHEN d.patientunitstayid IS NOT NULL THEN 'diagnosis'
      ELSE 'admissiondx'
    END AS sepsis_source
  FROM sepsis_dx d
  FULL OUTER JOIN sepsis_admitdx a ON d.patientunitstayid = a.patientunitstayid
),

pneumonia_dx AS (
  SELECT DISTINCT patientunitstayid
  FROM `physionet-data.eicu_crd.diagnosis`
  WHERE diagnosisoffset <= window_min
    AND (
      LOWER(diagnosisstring) LIKE '%pneumonia%'
      OR REGEXP_CONTAINS(icd9code, r'(^|,\s*)(48[0-6]\.?\d*|J1[2-8]\.?\d*)')
    )
),

-- 'Sepsis, pulmonary' counts as pneumonia
pneumonia_admitdx AS (
  SELECT DISTINCT patientunitstayid
  FROM `physionet-data.eicu_crd.admissiondx`
  WHERE admitdxenteredoffset <= window_min
    AND (
      LOWER(admitdxpath) LIKE '%pneumonia%'
      OR LOWER(admitdxpath) LIKE '%sepsis, pulmonary%'
    )
),

pneumonia_cohort AS (
  SELECT patientunitstayid FROM pneumonia_dx
  UNION DISTINCT
  SELECT patientunitstayid FROM pneumonia_admitdx
),

all_admitdx AS (
  SELECT patientunitstayid, STRING_AGG(DISTINCT admitdxpath, ' ; ') AS all_admitdx_paths
  FROM `physionet-data.eicu_crd.admissiondx`
  GROUP BY patientunitstayid
),

stays AS (
  SELECT
    p.patientunitstayid,
    p.patienthealthsystemstayid,
    p.uniquepid,
    p.age,
    p.gender,
    p.ethnicity,
    p.hospitalid,
    p.unittype,
    p.unitadmitsource,
    p.hospitaladmitoffset,
    p.hospitaldischargeoffset,
    p.hospitaldischargeyear,
    p.unitdischargeoffset,
    p.unitdischargestatus,
    p.hospitaldischargestatus,
    p.admissionheight,
    p.admissionweight,
    p.apacheadmissiondx,
    s.sepsis_source,
    s.sepsis_dx_string,
    s.sepsis_dx_icd,
    s.sepsis_admitdx_path,
    ad.all_admitdx_paths
  FROM `physionet-data.eicu_crd.patient` p
  JOIN sepsis_cohort s USING (patientunitstayid)
  LEFT JOIN pneumonia_cohort pn USING (patientunitstayid)
  LEFT JOIN all_admitdx ad USING (patientunitstayid)
  WHERE pn.patientunitstayid IS NULL
),

-- First ICU stay of a hospitalization = largest hospitaladmitoffset
icu_order AS (
  SELECT
    patientunitstayid,
    ROW_NUMBER() OVER (PARTITION BY patienthealthsystemstayid
                       ORDER BY hospitaladmitoffset DESC, patientunitstayid) AS icu_order_in_hosp
  FROM `physionet-data.eicu_crd.patient`
)

SELECT
  s.*,
  o.icu_order_in_hosp,
  -- Earliest hospitalization first; same-year order is arbitrary (D03)
  ROW_NUMBER() OVER (PARTITION BY s.uniquepid
                     ORDER BY s.hospitaldischargeyear ASC NULLS LAST,
                              s.patienthealthsystemstayid,
                              s.hospitaladmitoffset DESC,
                              s.patientunitstayid) AS patient_stay_rank
FROM stays s
JOIN icu_order o USING (patientunitstayid);

CREATE OR REPLACE TABLE `evocative-ethos-471602-r3.base.eicu_sepsis_no_pneumonia` AS
SELECT * EXCEPT (patient_stay_rank)
FROM `evocative-ethos-471602-r3.base.eicu_sepsis_stays`
WHERE patient_stay_rank = 1
  AND icu_order_in_hosp = 1;
