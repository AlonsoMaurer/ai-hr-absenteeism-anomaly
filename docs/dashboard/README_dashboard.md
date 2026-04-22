# HR Absenteeism Anomaly Monitor — Power BI Dashboard

**Part of:** `ai-hr-absenteeism-anomaly` portfolio project  
**Stack:** Power BI Desktop · DAX · Synthetic dataset (`anomaly_alerts`)  
**Status:** v1 complete

---

## Overview

Interactive Power BI dashboard for monitoring absenteeism anomalies across departments and shifts. Detects statistically significant deviations using z-score thresholds and classifies them by severity (High / Medium / Low).

The dashboard was designed following a dark analytics-app aesthetic, prioritizing signal-to-noise ratio and semantic color coding over decorative elements.

---

## Data Model

**Primary table:** `anomaly_alerts`

| Column | Type | Description |
|---|---|---|
| `date` | Date | Observation date |
| `department_id` | Integer | Department identifier |
| `shift_id` | Integer | Shift (1, 2, 3) |
| `scheduled_headcount` | Integer | Planned headcount for the day |
| `absent_headcount` | Integer | Employees absent |
| `absence_rate` | Decimal | `absent / scheduled` |
| `hist_days` | Integer | Days of historical baseline used |
| `mean_28d` | Decimal | 28-day rolling absence rate mean |
| `std_28d` | Decimal | 28-day rolling standard deviation |
| `z_score` | Decimal | `(absence_rate - mean_28d) / std_28d` |
| `is_anomaly` | Integer | 1 if `z_score > threshold`, else 0 |
| `alert_severity` | String | High / Medium / Low / Normal |

Source data is intentionally kept in raw form as evidence of the cleaning pipeline. Transformations are applied at the DAX layer.

---

## DAX Measures

Measures are organized into display folders:

### Core KPIs
| Measure | Description |
|---|---|
| `Total Anomalies` | Count of rows where `is_anomaly = 1` |
| `High Severity` | Count of High severity anomalies |
| `Avg Absence Rate Anomalies` | Average absence rate for anomalous rows |
| `Depts Affected` | Distinct department count with anomalies |
| `Daily Anomaly Count` | Count of anomalies per day |

### Filters (shift-aware versions)
| Measure | Description |
|---|---|
| `Total Anomalies (Filtered)` | Respects shift slicer context |
| `High Severity (Filtered)` | Respects shift slicer context |
| `Avg Absence Rate (Filtered)` | Respects shift slicer context |
| `Depts Affected (Filtered)` | Respects shift slicer context |
| `Selected Shift Label` | Returns "Shift 1/2/3" or "All Shifts" |

### Severity (conditional formatting)
| Measure | Description |
|---|---|
| `Severity Color` | Hex color by severity — font/fill binding |
| `Severity Font Color` | Light variant for pill text |
| `Severity Background Color` | Dark variant for pill background |
| `Severity Label` | `⬤ High / ⬤ Medium / ⬤ Low` with BLANK() on totals |
| `Absence Rate Color` | Semantic color for absence rate column |

### Detail (alert table)
| Measure | Description |
|---|---|
| `Max Z-Score` | Worst z-score per dept (for table aggregation) |
| `Max Absence Rate` | Highest absence rate per dept |
| `Max Absence Rate Color` | Semantic color bound to `Max Absence Rate` |
| `Max Headcount` | Headcount at worst anomaly |
| `Top Severity Label` | Severity pill for worst anomaly per dept |
| `Top Severity Font Color` | Font color for `Top Severity Label` |
| `Avg Baseline 28d` | Average 28-day baseline per dept |
| `Avg Z-Score` | Average z-score for anomalous rows |

### Heatmap
| Measure | Description |
|---|---|
| `Anomaly Heatmap Value` | Count per dept × shift cell |

---

## Visuals

| Visual | Type | Key config |
|---|---|---|
| KPI cards | Card | Semantic border color per metric; `(Filtered)` measures respond to shift slicer |
| Anomalies by dept | Bar chart | Horizontal; sorted descending by total |
| Dept × Shift heatmap | Matrix | Rows: `department_name`; Columns: `shift_id`; Values: `Anomaly Heatmap Value`; background gradient `#1F2535 → #F97316 → #EF4444` |
| Daily trend | Line chart | Eje X: `Día` (day number 1–30); filtered to `is_anomaly = 1` |
| Alert detail table | Table | Filtered to `is_anomaly = 1`; sorted by `Max Z-Score` desc; conditional formatting on `Max Absence Rate` and `Top Severity Label` |
| Shift slicer | Slicer (Tile) | Field: `shift_id`; filters all visuals on page |

---

## Theme

Applied via `HR_Anomaly_Dark_Theme.json`.

| Token | Hex | Usage |
|---|---|---|
| Canvas background | `#0F1117` | Page background (set manually) |
| Surface | `#181C27` | Visual backgrounds |
| Surface 2 | `#1F2535` | Alternate rows, heatmap zero cells |
| Border | `#2A3147` | Visual borders, grid lines |
| Text | `#FFFFFF` | Primary values |
| Muted | `#64748B` | Labels, subtitles, axis text |
| High | `#EF4444` | High severity |
| Medium | `#F97316` | Medium severity |
| Low | `#22C55E` | Low severity |
| Accent | `#3B82F6` | Default data color, active slicer |

---

## Design Decisions & Trade-offs

**Pill simulation via text measure** — Power BI table visuals apply background color to the entire row, not individual cells. `Severity Label` uses a `⬤` Unicode symbol with conditional font color to simulate severity pills without row-level background artifacts.

**Dept-level aggregation in alert table** — The table shows one row per department (worst anomaly) rather than one row per dept-shift-day. This reduces noise and matches the "top anomalies" intent. The trade-off is loss of shift-level detail in this view; the heatmap covers that angle.

**Day number on trend axis** — The synthetic dataset spans a fixed historical period (not rolling from today). Using `Día` (day number) instead of calendar dates keeps the "last 30 days" framing consistent regardless of when the file is opened.

**Import mode** — BigQuery connection uses Import mode (not DirectQuery) for performance. Refresh is manual; production deployment would use scheduled refresh via Power BI Service.

**Dirty source data preserved** — Raw source files are not cleaned at the file level. All transformations occur in DAX to maintain a visible audit trail of the cleaning pipeline.
