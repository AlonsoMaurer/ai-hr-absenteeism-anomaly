## SQL Execution Order (BigQuery)

Run the analytics layer in this exact order:

1) **attendance_clean**  
   Creates: `analytics.attendance_clean`  
   Source: `raw.attendance_daily` (loaded as STRING)  
   File: `sql/analytics/attendance_clean.sql`

2) **absence_daily**  
   Creates: `analytics.absence_daily` (daily absence rate by department + shift)  
   Source: `analytics.attendance_clean`  
   File: `sql/analytics/absence_daily.sql`

3) **anomaly_alerts**  
   Creates: `analytics.anomaly_alerts` (daily anomaly flags + severity)  
   Source: `analytics.absence_daily`  
   File: `sql/analytics/anomaly_alerts.sql`

### QA (optional but recommended)
After each step, run the checks:
- `sql/qa/attendance_clean_checks.sql`
- `sql/qa/absence_daily_checks.sql`
- `sql/qa/anomaly_alerts_checks.sql`
