-- Purpose: Build a curated attendance table from raw ingestion.
-- Notes:
-- - raw.attendance_daily was loaded with all columns as STRING for robust ingestion.
-- - Some numeric fields arrive as "1.0" (STRING), so we cast STRING -> FLOAT64 -> INT64.
-- - Dates may arrive in two formats: YYYY-MM-DD or DD-MM-YYYY.

CREATE OR REPLACE TABLE `ai-hr-absenteeism-anomaly.analytics.attendance_clean` AS
WITH base AS (
  SELECT
    COALESCE(
      SAFE.PARSE_DATE('%Y-%m-%d', date),
      SAFE.PARSE_DATE('%d-%m-%Y', date)
    ) AS date,

    SAFE_CAST(SAFE_CAST(employee_id AS FLOAT64) AS INT64) AS employee_id,
    SAFE_CAST(SAFE_CAST(department_id AS FLOAT64) AS INT64) AS department_id,
    SAFE_CAST(SAFE_CAST(shift_id AS FLOAT64) AS INT64) AS shift_id,

    SAFE_CAST(SAFE_CAST(scheduled_minutes AS FLOAT64) AS INT64) AS scheduled_minutes,
    SAFE_CAST(SAFE_CAST(absence_minutes AS FLOAT64) AS INT64) AS absence_minutes,

    NULLIF(absence_reason, '') AS absence_reason,
    SAFE_CAST(SAFE_CAST(is_absent AS FLOAT64) AS INT64) AS is_absent

  FROM `ai-hr-absenteeism-anomaly.raw.attendance_daily`
)
SELECT *
FROM base
WHERE
  date IS NOT NULL
  AND employee_id IS NOT NULL
  AND department_id IS NOT NULL
  AND shift_id IN (1, 2, 3)
  AND scheduled_minutes BETWEEN 60 AND 720
  AND absence_minutes BETWEEN 0 AND 720
  AND is_absent IN (0, 1);
