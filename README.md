# AI HR Absenteeism Anomaly Detection (MVP)

End-to-end AI Engineering portfolio project: **detect daily absenteeism anomalies** by **department + shift** for HRBPs, using **BigQuery (SQL)** + **Python** + **Power BI** + **GitHub**.

---

## 1) Business Goal
HRBPs need an early signal to investigate unusual spikes in absenteeism across **areas/shifts** (not individual surveillance).  
This MVP produces a daily alert table that can be consumed in Power BI.

**Primary question:**  
> *Which department + shift combinations show anomalous absenteeism today compared to their recent baseline?*

---

## 2) Tech Stack
- **BigQuery**: ingestion + analytics tables + anomaly detection logic (SQL)
- **Python (Colab)**: synthetic data generation + ingestion helper for malformed CSV
- **Power BI**: dashboard on `analytics.anomaly_alerts`
- **GitHub**: versioned SQL models, QA checks, and documentation

---

## 3) Data (Synthetic, “company-like”)
This project uses a synthetic dataset (~3,425 employees) designed to look realistic and to include typical data quality issues.

**7 base CSV files (source layer):**
- `employees_dirty.csv`
- `departments.csv`
- `performance_reviews.csv`
- `engagement.csv`
- `exits.csv`
- `shifts.csv`
- `attendance_daily.csv` *(intentionally messy / malformed rows)*

---

## 4) BigQuery Architecture (Raw → Analytics)
We separate ingestion from curated analytics to keep the pipeline production-like.

### Datasets
- `raw`: ingestion/staging tables
- `analytics`: curated tables built from `raw`

### Canonical tables in `raw`
- `raw.attendance_daily`
- `raw.departments`
- `raw.employees_dirty`
- `raw.engagement`
- `raw.exits`
- `raw.performance_reviews`
- `raw.shifts`

### Curated tables in `analytics`
- `analytics.attendance_clean` (typed + validated)
- `analytics.absence_daily` (daily metrics by dept+shift)
- `analytics.anomaly_alerts` (daily anomaly flags + severity)

---

## 5) Engineering Decisions (what we fixed and why)

### A) CSV ingestion failures (attendance)
`attendance_daily.csv` failed to load into BigQuery due to malformed CSV rows (BigQuery reported ~25 errors).

**Decision:** keep the raw file as evidence and generate a deterministic ingestion-safe file.
- `attendance_daily.csv` remains the original raw source (messy on purpose)
- A helper script generates:
  - `attendance_daily_ingest.csv` (loadable)
  - `ingestion_log.json` (single structured log as evidence)

This demonstrates **reproducible ingestion** rather than manual fixes.

**Ingestion helper (versioned):**
- Script: `python/sanitize_attendance.py` → generates `attendance_daily_ingest.csv` + `ingestion_log.json`
- Evidence: `ingestion_log.json` is a single structured log capturing rows kept/dropped and reasons.

### B) Load raw attendance as STRING
To avoid BigQuery type inference issues during ingestion, `raw.attendance_daily` was loaded with **all columns as STRING**.

**Decision:** enforce typing and validation only downstream in `analytics` (SQL), using `SAFE_CAST`.

### C) Casting fix: STRING → FLOAT64 → INT64
Some numeric fields arrived as strings like `"1.0"` (e.g., `department_id`, `shift_id`), which makes direct casts return NULL:
- `SAFE_CAST('1.0' AS INT64)` → NULL

**Fix:** cast in two steps:
- `STRING → FLOAT64 → INT64`

This fix is implemented in `sql/analytics/attendance_clean.sql` and prevents empty curated tables.

### D) Anomaly detection method (MVP)
We use a simple, reliable baseline that runs natively in BigQuery:

- Source: `analytics.absence_daily`
- Rolling window: **prior 28 days** (excludes current day to avoid leakage)
- Baseline: `mean_28d`, `std_28d`
- Score: `z_score = (absence_rate - mean_28d) / std_28d`
- Flags: `hist_days >= 14`, `scheduled_headcount >= 20`, `z_score >= 3`

Current synthetic run produced **103 anomalies**.

> Note: A more robust baseline (median/MAD) is a planned improvement. BigQuery window limitations make MAD-based windows more complex; the MVP prioritizes an end-to-end working system.

---

## 6) SQL Execution Order (BigQuery)
Run the analytics layer in this exact order:

1) **attendance_clean**  
   Creates: `analytics.attendance_clean`  
   File: `sql/analytics/attendance_clean.sql`

2) **absence_daily**  
   Creates: `analytics.absence_daily`  
   File: `sql/analytics/absence_daily.sql`

3) **anomaly_alerts**  
   Creates: `analytics.anomaly_alerts`  
   File: `sql/analytics/anomaly_alerts.sql`

### QA (recommended)
After each step, run:
- `sql/qa/attendance_clean_checks.sql`
- `sql/qa/absence_daily_checks.sql`
- `sql/qa/anomaly_alerts_checks.sql`

---

## 7) Repository Structure
- `sql/analytics/` → BigQuery SQL models (curated tables)
- `sql/qa/` → reproducible QA checks
- `python/` → ingestion helper(s) and synthetic data generation
- `docs/` → optional documentation

---

## 8) Privacy & Ethics
- Synthetic data only (no real PII).
- Alerts are **team-level** (department + shift), not individual monitoring.
- Intended use: operational investigation and prevention, not punitive action.

---

## Next Steps (MVP completion)
- Add Power BI dashboard connected to `analytics.anomaly_alerts`
- Document dataset schema (tables + columns + value in the project)
- Optional: automate execution via dbt or GitHub Actions
