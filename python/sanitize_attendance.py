import csv
import json
import hashlib
import os
from datetime import datetime, timezone

# Inputs/outputs (keep simple)
RAW = "attendance_daily.csv"
OUT = "attendance_daily_ingest.csv"
LOG = "ingestion_log.json"

EXPECTED_HEADER = [
    "date", "employee_id", "department_id", "shift_id",
    "scheduled_minutes", "absence_minutes", "absence_reason", "is_absent"
]
EXPECTED_COLS = len(EXPECTED_HEADER)

def sha256_file(path: str, chunk_size: int = 1024 * 1024) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(chunk_size), b""):
            h.update(chunk)
    return h.hexdigest()

def main():
    if not os.path.exists(RAW):
        raise FileNotFoundError(f"Missing input file: {RAW}")

    raw_sha = sha256_file(RAW)

    good_rows = 0
    bad_rows = 0
    bad_reason_counts = {}

    # Deterministic rule: keep only rows with exactly 8 columns
    with open(RAW, "r", encoding="utf-8", errors="replace", newline="") as f_in, \
         open(OUT, "w", encoding="utf-8", newline="") as f_out:

        reader = csv.reader(f_in)
        writer = csv.writer(f_out)

        _ = next(reader, None)  # skip original header
        writer.writerow(EXPECTED_HEADER)

        for row in reader:
            if not row or all((c.strip() == "" for c in row)):
                bad_rows += 1
                bad_reason_counts["empty_row"] = bad_reason_counts.get("empty_row", 0) + 1
                continue

            if len(row) != EXPECTED_COLS:
                bad_rows += 1
                key = f"wrong_num_cols_{len(row)}"
                bad_reason_counts[key] = bad_reason_counts.get(key, 0) + 1
                continue

            writer.writerow(row)
            good_rows += 1

    log = {
        "run_ts_utc": datetime.now(timezone.utc).isoformat(),
        "raw_file": RAW,
        "ingest_file": OUT,
        "raw_sha256": raw_sha,
        "good_rows_written": good_rows,
        "bad_rows_dropped": bad_rows,
        "bad_reason_counts": bad_reason_counts,
        "rule": "kept rows with exactly 8 columns; dropped malformed CSV rows to guarantee BigQuery load"
    }

    with open(LOG, "w", encoding="utf-8") as f:
        json.dump(log, f, indent=2)

    print("✅ Done")
    print("Created:", OUT)
    print("Created:", LOG)
    print("good_rows:", good_rows, "| bad_rows:", bad_rows)

if __name__ == "__main__":
    main()
