-- Purpose: Daily anomaly alerts for absenteeism by department + shift.
-- Method: Rolling 28-day baseline (prior days only) using robust statistics:
-- - median_28d of absence_rate
-- - mad_28d (median absolute deviation)
-- - robust_z = (absence_rate - median_28d) / (1.4826 * mad_28d)
--
-- Notes:
-- - Uses only past 28 days (excludes current day) to avoid leakage.
-- - Requires minimum history to reduce noise.

CREATE OR REPLACE TABLE `ai-hr-absenteeism-anomaly.analytics.anomaly_alerts` AS
WITH w AS (
  SELECT
    date,
    department_id,
    shift_id,
    scheduled_headcount,
    absent_headcount,
    absence_rate,

    -- count of prior observations in the rolling window
    COUNT(*) OVER (
      PARTITION BY department_id, shift_id
      ORDER BY date
      RANGE BETWEEN INTERVAL 28 DAY PRECEDING AND INTERVAL 1 DAY PRECEDING
    ) AS hist_days,

    -- rolling median of absence_rate (prior 28 days)
    PERCENTILE_CONT(absence_rate, 0.5) OVER (
      PARTITION BY department_id, shift_id
      ORDER BY date
      RANGE BETWEEN INTERVAL 28 DAY PRECEDING AND INTERVAL 1 DAY PRECEDING
    ) AS median_28d

  FROM `ai-hr-absenteeism-anomaly.analytics.absence_daily`
),
dev AS (
  SELECT
    *,
    ABS(absence_rate - median_28d) AS abs_dev
  FROM w
),
stats AS (
  SELECT
    *,
    -- rolling MAD = median(|x - median|)
    PERCENTILE_CONT(abs_dev, 0.5) OVER (
      PARTITION BY department_id, shift_id
      ORDER BY date
      RANGE BETWEEN INTERVAL 28 DAY PRECEDING AND INTERVAL 1 DAY PRECEDING
    ) AS mad_28d
  FROM dev
)
SELECT
  date,
  department_id,
  shift_id,
  scheduled_headcount,
  absent_headcount,
  absence_rate,

  hist_days,
  median_28d,
  mad_28d,

  -- robust z-score (MAD scaled to ~std dev for normal dist)
  SAFE_DIVIDE(absence_rate - median_28d, 1.4826 * mad_28d) AS robust_z,

  -- flag anomalies only when we have enough history and stable sample size
  CASE
    WHEN hist_days >= 14
     AND scheduled_headcount >= 20
     AND mad_28d IS NOT NULL
     AND mad_28d > 0
     AND SAFE_DIVIDE(absence_rate - median_28d, 1.4826 * mad_28d) >= 3
    THEN 1 ELSE 0
  END AS is_anomaly,

  CASE
    WHEN hist_days < 14 OR scheduled_headcount < 20 OR mad_28d IS NULL OR mad_28d = 0 THEN "Insufficient baseline"
    WHEN SAFE_DIVIDE(absence_rate - median_28d, 1.4826 * mad_28d) >= 5 THEN "High"
    WHEN SAFE_DIVIDE(absence_rate - median_28d, 1.4826 * mad_28d) >= 4 THEN "Medium"
    WHEN SAFE_DIVIDE(absence_rate - median_28d, 1.4826 * mad_28d) >= 3 THEN "Low"
    ELSE "Normal"
  END AS alert_severity

FROM stats;
