-- QA checks for analytics.attendance_clean
-- Goal: confirm table is non-empty and only valid shifts exist (1,2,3).

-- 1) Row count should be > 0
SELECT COUNT(*) AS row_count
FROM `ai-hr-absenteeism-anomaly.analytics.attendance_clean`;

-- 2) Shift distribution should only include 1,2,3
SELECT shift_id, COUNT(*) AS n
FROM `ai-hr-absenteeism-anomaly.analytics.attendance_clean`
GROUP BY shift_id
ORDER BY shift_id;

-- 3) If this returns rows, it's a problem (should be 0 rows)
SELECT *
FROM `ai-hr-absenteeism-anomaly.analytics.attendance_clean`
WHERE shift_id NOT IN (1,2,3)
LIMIT 10;
