# Data Schema — AI HR Absenteeism Anomaly Detection

This document describes all tables in the `analytics` layer, derived from the SQL models in `sql/analytics/`.  
Tables are listed in execution order: each depends on the previous.

---

## Table 1: `analytics.attendance_clean`

**Purpose:** Curated, typed, and validated attendance records. Built from `raw.attendance_daily`, which was ingested with all columns as STRING to handle malformed CSV rows.

**Source:** `sql/analytics/attendance_clean.sql`  
**Source table:** `raw.attendance_daily`

| Column | Type | Description | Validation rules |
|---|---|---|---|
| `date` | DATE | Attendance record date | Parsed from YYYY-MM-DD or DD-MM-YYYY. Rows with NULL date are excluded. |
| `employee_id` | INT64 | Unique employee identifier | Cast via STRING → FLOAT64 → INT64. NULL rows excluded. |
| `department_id` | INT64 | Department the employee belongs to | Cast via STRING → FLOAT64 → INT64. NULL rows excluded. |
| `shift_id` | INT64 | Work shift identifier | Only values 1, 2, 3 are valid. Other values excluded. |
| `scheduled_minutes` | INT64 | Total minutes the employee was scheduled to work | Valid range: 60–720 min (1h to 12h). |
| `absence_minutes` | INT64 | Total minutes absent during scheduled shift | Valid range: 0–720 min. |
| `absence_reason` | STRING | Reason for absence, if provided | NULL if empty string. Optional field. |
| `is_absent` | INT64 | Binary flag: 1 = absent, 0 = present | Only values 0 and 1 accepted. |

**Row-level filters applied:**
- `date IS NOT NULL`
- `employee_id IS NOT NULL`
- `department_id IS NOT NULL`
- `shift_id IN (1, 2, 3)`
- `scheduled_minutes BETWEEN 60 AND 720`
- `absence_minutes BETWEEN 0 AND 720`
- `is_absent IN (0, 1)`

---

## Table 2: `analytics.absence_daily`

**Purpose:** Daily absenteeism aggregates by department + shift. Collapses individual attendance records into team-level metrics. Primary input for anomaly detection and Power BI reporting.

**Source:** `sql/analytics/absence_daily.sql`  
**Source table:** `analytics.attendance_clean`  
**Grain:** One row per `(date, department_id, shift_id)` combination.

| Column | Type | Description | Derivation |
|---|---|---|---|
| `date` | DATE | Reporting date | Grouped from `attendance_clean.date` |
| `department_id` | INT64 | Department identifier | Grouped from `attendance_clean.department_id` |
| `shift_id` | INT64 | Shift identifier (1, 2, or 3) | Grouped from `attendance_clean.shift_id` |
| `scheduled_headcount` | INT64 | Number of employees scheduled that day in this dept+shift | `COUNT(*)` |
| `absent_headcount` | INT64 | Number of employees absent that day in this dept+shift | `SUM(is_absent)` |
| `absence_rate` | FLOAT64 | Fraction of scheduled employees who were absent | `SAFE_DIVIDE(absent_headcount, scheduled_headcount)` — returns NULL if headcount = 0 |

**Note:** `SAFE_DIVIDE` is used to prevent division-by-zero errors on days with zero scheduled headcount.

---

## Table 3: `analytics.anomaly_alerts`

**Purpose:** Daily anomaly detection output. Compares each department + shift's absence rate against its own 28-day rolling baseline and flags statistically significant deviations. This is the table consumed by Power BI and by HRBPs.

**Source:** `sql/analytics/anomaly_alerts.sql`  
**Source table:** `analytics.absence_daily`  
**Grain:** One row per `(date, department_id, shift_id)` combination — same as `absence_daily`.

| Column | Type | Description | Derivation |
|---|---|---|---|
| `date` | DATE | Reporting date | From `absence_daily` |
| `department_id` | INT64 | Department identifier | From `absence_daily` |
| `shift_id` | INT64 | Shift identifier | From `absence_daily` |
| `scheduled_headcount` | INT64 | Scheduled employees that day | From `absence_daily` |
| `absent_headcount` | INT64 | Absent employees that day | From `absence_daily` |
| `absence_rate` | FLOAT64 | Observed absence rate | From `absence_daily` |
| `hist_days` | INT64 | Number of prior days available in the 28-day window | `COUNT(*) OVER (... ROWS BETWEEN 28 PRECEDING AND 1 PRECEDING)` — excludes current day to avoid data leakage |
| `mean_28d` | FLOAT64 | Average absence rate over the prior 28 days | `AVG(absence_rate) OVER (... 28 PRECEDING AND 1 PRECEDING)` |
| `std_28d` | FLOAT64 | Standard deviation of absence rate over the prior 28 days | `STDDEV_POP(absence_rate) OVER (... 28 PRECEDING AND 1 PRECEDING)` |
| `z_score` | FLOAT64 | Standardized deviation of today's rate from the 28-day baseline | `SAFE_DIVIDE(absence_rate - mean_28d, std_28d)` — NULL if std_28d = 0 |
| `is_anomaly` | INT64 | Binary flag: 1 = anomaly detected, 0 = normal | 1 when: `hist_days >= 14` AND `scheduled_headcount >= 20` AND `std_28d > 0` AND `z_score >= 3` |
| `alert_severity` | STRING | Severity classification of the anomaly | See severity logic below |

**Severity classification logic:**

| `alert_severity` value | Condition |
|---|---|
| `"Insufficient baseline"` | `hist_days < 14` OR `scheduled_headcount < 20` OR `std_28d IS NULL` OR `std_28d = 0` |
| `"High"` | `z_score >= 5` |
| `"Medium"` | `z_score >= 4` AND `z_score < 5` |
| `"Low"` | `z_score >= 3` AND `z_score < 4` |
| `"Normal"` | `z_score < 3` (no anomaly) |

**Detection thresholds and rationale:**

| Parameter | Value | Rationale |
|---|---|---|
| Rolling window | 28 days prior | Captures ~4 weeks of baseline; excludes current day to avoid leakage |
| Minimum history | `hist_days >= 14` | Requires at least 2 weeks of data before flagging — prevents false positives on new dept+shift combinations |
| Minimum headcount | `scheduled_headcount >= 20` | Small teams have high natural variance; filtering avoids noisy alerts on low-headcount units |
| Z-score threshold | `>= 3` (3σ) | Flags only statistically extreme deviations (~0.13% probability under a normal distribution) |

---

## Execution Order

```
raw.attendance_daily
       ↓
analytics.attendance_clean   (typing + validation)
       ↓
analytics.absence_daily      (daily aggregates by dept+shift)
       ↓
analytics.anomaly_alerts     (z-score detection + severity flags)
```

---

## Key Design Decisions

- **All columns loaded as STRING in raw layer** — avoids BigQuery type inference failures on malformed CSV. Typing is enforced downstream via `SAFE_CAST`.
- **Two-step numeric cast (STRING → FLOAT64 → INT64)** — handles values like `"1.0"` that fail direct integer casting.
- **`SAFE_DIVIDE` throughout** — prevents silent division-by-zero errors from propagating into downstream tables.
- **`STDDEV_POP` over `STDDEV_SAMP`** — population standard deviation is used since the window represents the full available history, not a sample.
- **Current day excluded from baseline window** — `ROWS BETWEEN 28 PRECEDING AND 1 PRECEDING` ensures today's value does not influence its own baseline (data leakage prevention).
