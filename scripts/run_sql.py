"""Run project SQL files on BigQuery.

Pipeline files (sql/pipeline/*.sql) run as one BigQuery script and build tables.
Check files (sql/checks/*.sql) are split into blocks that start with a line

    -- @query: <name>

Each block runs on its own, and its result is saved to results/<name>.csv.

Examples
    python scripts/run_sql.py --test                              # check the connection
    python scripts/run_sql.py sql/pipeline/01_sepsis_cohort.sql   # build tables
    python scripts/run_sql.py sql/checks/05_creatinine_urine.sql  # all blocks in a file
    python scripts/run_sql.py sql/checks/08_feasibility.sql --only 08b_outcome_scenarios
    python scripts/run_sql.py sql/checks/05_creatinine_urine.sql --dry-run   # cost only

Only aggregated results should ever be saved (PhysioNet data use agreement).
"""

import argparse
import re
import sys
import time
from pathlib import Path

from google.cloud import bigquery

# Billing project for queries. The eICU data itself lives in physionet-data.
PROJECT = "evocative-ethos-471602-r3"

ROOT = Path(__file__).resolve().parent.parent
RESULTS = ROOT / "results"
BLOCK_HEADER = re.compile(r"^-- @query:\s*(\S+)\s*$", re.MULTILINE)

# Refuse to save a result this large to results/ - a sign it is patient-level.
MAX_RESULT_ROWS = 500


def split_blocks(sql: str):
    """Return [(name, sql), ...] for each '-- @query: name' block."""
    parts = BLOCK_HEADER.split(sql)
    # parts = [preamble, name1, body1, name2, body2, ...]
    return [(parts[i].strip(), parts[i + 1].strip()) for i in range(1, len(parts), 2)]


def gigabytes(n_bytes):
    return (n_bytes or 0) / 1e9


def run_query(client, sql, dry_run=False):
    config = bigquery.QueryJobConfig(dry_run=dry_run, use_query_cache=not dry_run)
    return client.query(sql, job_config=config)


def run_check_file(client, path: Path, only=None, dry_run=False):
    blocks = split_blocks(path.read_text())
    if only:
        blocks = [b for b in blocks if b[0] in only]
        if not blocks:
            sys.exit(f"No block named {only} in {path}")
    RESULTS.mkdir(exist_ok=True)

    for name, sql in blocks:
        print(f"\n=== {name} ===")
        start = time.time()
        job = run_query(client, sql, dry_run)
        if dry_run:
            print(f"would process {gigabytes(job.total_bytes_processed):.2f} GB")
            continue

        df = job.result().to_dataframe()
        if len(df) > MAX_RESULT_ROWS:
            print(f"NOT SAVED: {len(df)} rows looks patient-level (limit {MAX_RESULT_ROWS}).")
            continue

        out = RESULTS / f"{name}.csv"
        df.to_csv(out, index=False)
        print(f"{len(df)} rows, {gigabytes(job.total_bytes_processed):.2f} GB, "
              f"{time.time() - start:.0f}s -> {out.relative_to(ROOT)}")
        print(df.head(15).to_string(index=False))


def run_pipeline_file(client, path: Path, dry_run=False):
    print(f"\n=== {path.name} ===")
    start = time.time()
    job = run_query(client, path.read_text(), dry_run)
    if dry_run:
        print(f"would process {gigabytes(job.total_bytes_processed):.2f} GB")
        return
    job.result()  # wait for the whole script to finish
    print(f"done in {time.time() - start:.0f}s, "
          f"{gigabytes(job.total_bytes_billed):.2f} GB billed")


def test_connection(client):
    sql = "SELECT COUNT(*) AS n_icu_stays FROM `physionet-data.eicu_crd.patient`"
    n = list(run_query(client, sql).result())[0].n_icu_stays
    print(f"Connected. eICU patient table has {n:,} ICU stays (expected 200,859).")


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("files", nargs="*", type=Path, help="SQL files to run")
    parser.add_argument("--only", nargs="+", help="run only these @query blocks")
    parser.add_argument("--dry-run", action="store_true",
                        help="estimate data scanned without running")
    parser.add_argument("--test", action="store_true", help="test the BigQuery connection")
    args = parser.parse_args()

    client = bigquery.Client(project=PROJECT)

    if args.test:
        test_connection(client)
        return
    if not args.files:
        parser.print_help()
        return

    for path in args.files:
        if not path.exists():
            sys.exit(f"File not found: {path}")
        try:
            if split_blocks(path.read_text()):
                run_check_file(client, path, args.only, args.dry_run)
            else:
                run_pipeline_file(client, path, args.dry_run)
        except Exception as err:  # show BigQuery's message without a long traceback
            sys.exit(f"\nFAILED in {path}:\n{err}")


if __name__ == "__main__":
    main()
