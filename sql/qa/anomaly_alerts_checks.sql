-- QA checks for analytics.anomaly_alerts (MVP)

-- 1) Row count should be > 0
SELECT COUNT(*) AS row_count
FROM `ai-hr-absenteeism-anomaly.analytics.anomaly_alerts`;

-- 2) is_anomaly should be only 0/1
SELECT COUNT(*) AS invalid_flag_rows
FROM `ai-hr-absenteeism-anomaly.analytics.anomaly_alerts`
WHERE is_anomaly NOT IN (0,1) OR is_anomaly IS NULL;

-- 3) z_score should be null only when baseline is insufficient (std_28d null/0 or hist_days < 14)
SELECT COUNT(*) AS unexpected_null_z
FROM `ai-hr-absenteeism-anomaly.analytics.anomaly_alerts`
WHERE z_score IS NULL AND hist_days >= 14 AND std_28d > 0;

-- 4) sanity: anomaly count should be > 0 (for this synthetic dataset)
SELECT is_anomaly, COUNT(*) AS n
FROM `ai-hr-absenteeism-anomaly.analytics.anomaly_alerts`
GROUP BY is_anomaly;
