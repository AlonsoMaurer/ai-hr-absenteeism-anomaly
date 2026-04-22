> 🌎 [Versión en español disponible aquí](README_es.md)

# Power BI Dashboard — HR Absenteeism Anomaly Monitor

> Part of [`ai-hr-absenteeism-anomaly`](https://github.com/AlonsoMaurer/ai-hr-absenteeism-anomaly) · Located in `docs/dashboard/`

Interactive Power BI dashboard built on `analytics.anomaly_alerts`. Designed for daily HRBP use: review prioritized anomaly alerts by department and shift, filtered by severity and z-score.

**Files in this folder:**
- `Dashboard3.pbix` — Power BI report file
- `HR_Anomaly_Dark_Theme.json` — custom dark theme (import via View → Themes)

---

## 1) What the Dashboard Shows

The dashboard answers the same business question as the pipeline:

> *Which department + shift combinations show anomalous absenteeism today compared to their own 28-day baseline — and how severe is the deviation?*

It surfaces this in four visuals:

| Visual | What it shows |
|---|---|
| KPI cards | Total anomalies, high severity count, avg absence rate, depts affected — all respond to shift filter |
| Anomalies by dept (bar) | Total anomaly count per department, sorted descending |
| Dept × Shift heatmap (matrix) | Anomaly count per dept-shift cell; color intensity = frequency |
| Daily trend (line) | Anomaly count per day over the last 30 days |
| Alert detail (table) | One row per department — worst anomaly, sorted by z-score desc; severity pills color-coded |

---

## 2) Data Source

**Table:** `analytics.anomaly_alerts` (BigQuery, imported via Power BI Import mode)

| Column | Type | Description |
|---|---|---|
| `date` | Date | Observation date |
| `department_id` | Integer | Department identifier |
| `shift_id` | Integer | Shift (1, 2, 3) |
| `scheduled_headcount` | Integer | Planned headcount for the day |
| `absent_headcount` | Integer | Employees absent |
| `absence_rate` | Decimal | `absent / scheduled` |
| `mean_28d` | Decimal | 28-day rolling absence rate mean |
| `std_28d` | Decimal | 28-day rolling standard deviation |
| `z_score` | Decimal | `(absence_rate - mean_28d) / std_28d` |
| `is_anomaly` | Integer | 1 if flagged, 0 otherwise |
| `alert_severity` | String | High / Medium / Low / Normal |

**Connection:** BigQuery → Power BI Desktop, Import mode. Refresh is manual in the MVP; scheduled refresh would require Power BI Service.

---

## 3) DAX Measures

Measures are organized into display folders in the model.

### Core KPIs
| Measure | Description |
|---|---|
| `Total Anomalies` | `COUNT` where `is_anomaly = 1` |
| `High Severity` | `COUNT` where `alert_severity = "High"` and `is_anomaly = 1` |
| `Avg Absence Rate Anomalies` | `AVERAGE(absence_rate)` for anomalous rows |
| `Depts Affected` | `DISTINCTCOUNT(department_id)` where `is_anomaly = 1` |
| `Daily Anomaly Count` | Anomaly count per day |

### Filters (shift-aware)
| Measure | Description |
|---|---|
| `Total Anomalies (Filtered)` | Respects shift slicer context |
| `High Severity (Filtered)` | Respects shift slicer context |
| `Avg Absence Rate (Filtered)` | Respects shift slicer context |
| `Depts Affected (Filtered)` | Respects shift slicer context |
| `Selected Shift Label` | Returns "Shift 1 / 2 / 3" or "All Shifts" |

### Severity (conditional formatting)
| Measure | Description |
|---|---|
| `Severity Color` | Hex color by severity level — used for font/fill binding |
| `Severity Font Color` | Light variant (`#FCA5A5 / #FDBA74 / #86EFAC`) for pill text |
| `Severity Background Color` | Dark variant (`#3B0F0F / #3B1F0A / #0A2E1A`) for pill fill |
| `Severity Label` | `⬤ High / ⬤ Medium / ⬤ Low` — returns `BLANK()` on totals row |
| `Absence Rate Color` | Semantic color bound to `absence_rate` column |

### Alert table (aggregated per dept)
| Measure | Description |
|---|---|
| `Max Z-Score` | Worst z-score per department |
| `Max Absence Rate` | Highest absence rate per department |
| `Max Absence Rate Color` | Semantic color for `Max Absence Rate` column |
| `Max Headcount` | Headcount at worst anomaly |
| `Top Severity Label` | Severity pill for worst anomaly per department |
| `Top Severity Font Color` | Font color for `Top Severity Label` |
| `Avg Baseline 28d` | Average 28-day baseline per department |

---

## 4) Engineering Decisions

### A) Pill simulation via text measure
Power BI table visuals apply conditional background color to the **entire row**, not individual cells. This made severity pills expand across all columns, breaking the visual hierarchy.

**Decision:** `Severity Label` uses a `⬤` Unicode symbol with conditional font color (`Severity Font Color`) to simulate pills without row-level background artifacts. The trade-off is that the pill is text-only — no filled background cell.

### B) Dept-level aggregation in alert table
The underlying table has one row per dept-shift-day. Displaying it raw produces dozens of rows with duplicates per department.

**Decision:** the alert table aggregates to one row per department using `Max Z-Score`, `Max Absence Rate`, and `Top Severity Label` — showing the worst anomaly per dept. The trade-off is loss of shift-level detail in this view; the heatmap covers that angle.

### C) Day number on trend axis
The synthetic dataset spans a fixed historical period (not rolling from today). Using calendar dates on the axis produced a confusing chart with months from 2024–2025.

**Decision:** use `Día` (day number 1–30) on the X axis with the title "Daily Anomaly Trend — Last 30 Days". This keeps the framing consistent regardless of when the file is opened. The trade-off is loss of specific date references.

### D) Import mode (not DirectQuery)
Power BI's DirectQuery mode against BigQuery introduces latency on every visual interaction.

**Decision:** Import mode with manual refresh for the MVP. Acceptable given the daily refresh cadence of `analytics.anomaly_alerts`. Production deployment would use scheduled refresh via Power BI Service.

### E) Blank department names
Records associated with deduplicated department IDs (2 and 9 — see main README, Section 5E) produce unmatched rows in the Power BI join.

**Decision:** filtered out at the visualization layer via `department_name is not blank`. This is consistent with the handling documented in the main pipeline README. The permanent fix (ID remapping in SQL) is a documented future improvement.

---

## 5) Theme

Applied via `HR_Anomaly_Dark_Theme.json` (View → Themes → Browse for themes).

| Token | Hex | Usage |
|---|---|---|
| Canvas background | `#0F1117` | Page background (set manually — not controllable via theme JSON) |
| Surface | `#181C27` | Visual backgrounds |
| Surface 2 | `#1F2535` | Alternate rows, heatmap zero cells |
| Border | `#2A3147` | Visual borders, grid lines |
| Text primary | `#FFFFFF` | KPI values |
| Text muted | `#64748B` | Labels, subtitles, axis text |
| High severity | `#EF4444` | High anomaly color |
| Medium severity | `#F97316` | Medium anomaly color |
| Low severity | `#22C55E` | Low anomaly color |
| Accent | `#3B82F6` | Default data color, active slicer tile |

**Known limitation:** Power BI theme JSON does not support `transparent` as a color value. Canvas background (`#0F1117`) must be set manually via View → Page background.
