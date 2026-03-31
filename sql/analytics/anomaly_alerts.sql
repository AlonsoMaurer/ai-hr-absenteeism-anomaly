CREATE OR REPLACE TABLE `ai-hr-absenteeism-anomaly.analytics.anomaly_alerts` AS
WITH w AS (
  SELECT
    date,
    department_id,
    shift_id,
    scheduled_headcount,
    absent_headcount,
    absence_rate,

    COUNT(*) OVER (
      PARTITION BY department_id, shift_id
      ORDER BY date
      ROWS BETWEEN 28 PRECEDING AND 1 PRECEDING
    ) AS hist_days,

    AVG(absence_rate) OVER (
      PARTITION BY department_id, shift_id
      ORDER BY date
      ROWS BETWEEN 28 PRECEDING AND 1 PRECEDING
    ) AS mean_28d,

    STDDEV_POP(absence_rate) OVER (
      PARTITION BY department_id, shift_id
      ORDER BY date
      ROWS BETWEEN 28 PRECEDING AND 1 PRECEDING
    ) AS std_28d

  FROM `ai-hr-absenteeism-anomaly.analytics.absence_daily`
)
SELECT
  date,
  department_id,
  shift_id,
  scheduled_headcount,
  absent_headcount,
  absence_rate,

  hist_days,
  mean_28d,
  std_28d,

  SAFE_DIVIDE(absence_rate - mean_28d, std_28d) AS z_score,

  CASE
    WHEN hist_days >= 14
     AND scheduled_headcount >= 20
     AND std_28d IS NOT NULL
     AND std_28d > 0
     AND SAFE_DIVIDE(absence_rate - mean_28d, std_28d) >= 3
    THEN 1 ELSE 0
  END AS is_anomaly,

  CASE
    WHEN hist_days < 14 OR scheduled_headcount < 20 OR std_28d IS NULL OR std_28d = 0 THEN "Insufficient baseline"
    WHEN SAFE_DIVIDE(absence_rate - mean_28d, std_28d) >= 5 THEN "High"
    WHEN SAFE_DIVIDE(absence_rate - mean_28d, std_28d) >= 4 THEN "Medium"
    WHEN SAFE_DIVIDE(absence_rate - mean_28d, std_28d) >= 3 THEN "Low"
    ELSE "Normal"
  END AS alert_severity

FROM w;
