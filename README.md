# AI HR Absenteeism Anomaly Detection (MVP)
> 🌎 [Versión en español disponible aquí](README_es.md)

End-to-end AI Engineering portfolio project: **detect daily absenteeism anomalies** by **department + shift** for HRBPs, using **BigQuery (SQL)** + **Python** + **Power BI** + **GitHub**.

---

## TL;DR

**Problem:** HR Business Partners in mid-to-large organizations lack an early warning system for absenteeism spikes — unusual patterns are often detected days late, after operational impact has already occurred.

**Solution:** An end-to-end analytics pipeline (BigQuery + Python + Power BI) that computes daily z-score anomalies by department + shift, producing a prioritized alert table for HRBP action.

**Result:** On a synthetic dataset of 3,425 employees, the system surfaced **103 anomalous department-shift-day combinations** from 6 months of attendance data — signals that would have been invisible in raw headcount reports.

**Stack:** BigQuery · Python · Power BI · GitHub  
**Scope:** Team-level detection only — no individual monitoring. Synthetic data, no PII.

---

## 1) Business Context & Impact

### The problem
Absenteeism in Latin American organizations costs an estimated **3–6% of total payroll** annually (ILO, 2023). Beyond direct cost, undetected absenteeism spikes signal underlying issues — disengagement, health crises, management problems — that compound over time.

HR Business Partners typically work with weekly or monthly headcount summaries. By the time a pattern is visible in a report, the operational window to intervene has already closed.

### What this system enables
This pipeline gives HRBPs a **daily, team-level anomaly signal** they can act on the same day:

- **Detect early:** flag department + shift combinations with statistically unusual absence rates before they appear in aggregated reports
- **Prioritize investigation:** severity-ranked alerts focus HRBP time on the 5–10% of signals that warrant a conversation, not the full attendance log
- **Protect privacy:** all alerts are at team level — no individual is flagged or monitored

### Business question answered daily
> *Which department + shift combinations show anomalous absenteeism today compared to their own 28-day baseline — and how severe is the deviation?*

### Intended workflow
1. Pipeline runs overnight → `analytics.anomaly_alerts` refreshed
2. HRBP opens Power BI dashboard each morning
3. Reviews prioritized alerts (z-score ≥ 3, dept ≥ 20 headcount)
4. Decides whether to investigate, escalate, or monitor
5. Operational action taken within the same business day

---

## 2) Tech Stack
- **BigQuery**: ingestion + analytics tables + anomaly detection logic (SQL)
- **Python (Colab)**: synthetic data generation + ingestion helper for malformed CSV
- **Power BI**: dashboard on `analytics.anomaly_alerts` · dark theme · DAX anomaly measures · shift slicer
- **GitHub**: versioned SQL models, QA checks, and documentation

---

## 3) Data (Synthetic, "company-like")
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
- `analytics.departments_clean` (deduplicated + standardized department names)

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

#### Key Findings — MVP Run on Synthetic Data

The current pipeline run on 6 months of synthetic attendance data produced the following results:

| Metric | Value |
|---|---|
| Employees in dataset | 3,425 |
| Days analyzed | ~180 |
| Dept-shift combinations monitored | ~40 |
| Total anomaly-day combinations flagged | **103** |
| Flagging rate (anomalies / total dept-shift-days) | ~1.4% |
| Minimum z-score threshold | 3.0 (≥3σ above 28-day baseline) |
| Minimum headcount filter | 20 scheduled employees |

**What this means operationally:**
- On an average day, **0–3 department-shift combinations** would appear in the HRBP dashboard as requiring attention
- The 1.4% flagging rate is consistent with expected anomaly rates in a healthy organization — too low suggests the threshold is too strict; too high suggests noise
- The z-score ≥ 3 threshold was calibrated to minimize false positives for HRBPs: only statistically significant deviations surface

**Planned improvement:**  
The current baseline uses mean + standard deviation (z-score). A more robust alternative is median + MAD (Median Absolute Deviation), which is less sensitive to historical outliers. The MVP prioritizes an end-to-end working system over a perfect statistical model.

### E) Department ID deduplication and unmatched records

`raw.departments` contains duplicate entries for the same canonical department under different IDs and name variants:

| department_id | department_name | Issue |
|---|---|---|
| 2 | Finanze | Typo — duplicate of Finance (ID 3) |
| 3 | Finance | Canonical |
| 4 | HR | Canonical |
| 9 | H.R. | Duplicate of HR (ID 4) |

**Decision:** `analytics.departments_clean` standardizes names and keeps the lowest `department_id` for each canonical department via `ROW_NUMBER()`.

**Known consequence:** anomaly records associated with deduplicated IDs (2 and 9) produce unmatched rows in the Power BI join. These appear as blank `department_name` values and are filtered out at the visualization layer.

**Production fix:** a remapping step in SQL would reassign orphaned IDs to their canonical counterpart before the join. Documented as a future improvement.

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

4) **departments_clean**  
   Creates: `analytics.departments_clean`  
   File: `sql/analytics/departments_clean.sql`

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
- `data/raw/` → source CSV files (synthetic, no PII)
- `docs/` → data schema and project documentation
- `docs/dashboard/` → Power BI report, dark theme JSON, and visual layer documentation

---

## 8) Privacy & Ethics
- Synthetic data only (no real PII).
- Alerts are **team-level** (department + shift), not individual monitoring.
- Intended use: operational investigation and prevention, not punitive action.

---
