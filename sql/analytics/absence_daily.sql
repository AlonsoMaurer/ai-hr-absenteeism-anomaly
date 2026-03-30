-- Purpose: Daily absenteeism metrics by department + shift.
-- Output feeds Power BI and anomaly detection.

CREATE OR REPLACE TABLE `ai-hr-absenteeism-anomaly.analytics.absence_daily` AS
SELECT
  date,
  department_id,
  shift_id,
  COUNT(*) AS scheduled_headcount,
  SUM(is_absent) AS absent_headcount,
  SAFE_DIVIDE(SUM(is_absent), COUNT(*)) AS absence_rate
FROM `ai-hr-absenteeism-anomaly.analytics.attendance_clean`
GROUP BY 1, 2, 3;
