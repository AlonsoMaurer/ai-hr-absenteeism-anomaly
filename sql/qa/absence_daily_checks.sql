-- QA checks for analytics.absence_daily

-- 1) Row count should be > 0
SELECT COUNT(*) AS row_count
FROM `ai-hr-absenteeism-anomaly.analytics.absence_daily`;

-- 2) absence_rate should be between 0 and 1
SELECT COUNT(*) AS out_of_range_rows
FROM `ai-hr-absenteeism-anomaly.analytics.absence_daily`
WHERE absence_rate < 0 OR absence_rate > 1 OR absence_rate IS NULL;

-- 3) Keys should not be null
SELECT COUNT(*) AS null_key_rows
FROM `ai-hr-absenteeism-anomaly.analytics.absence_daily`
WHERE date IS NULL OR department_id IS NULL OR shift_id IS NULL;
