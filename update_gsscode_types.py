#!/usr/bin/env python3
"""Refresh the gsscode extension's gsscode_types table from the current
ONS Register of Geographic Codes (RGC) release on the Open Geography
Portal (geoportal.statistics.gov.uk, ArcGIS-hosted).

ONS republishes the RGC periodically under a new dated item each time
(eg "Register of Geographic Codes (June 2025) for the UK", then a
"(June 2026)" successor with a different item id) and tags exactly one
of them with the ArcGIS category "/Categories/LATEST". This script
queries for that tag+category combination rather than hardcoding an
item id or a release date, so it keeps working as ONS publishes new
releases without needing code changes here.

Usage:
    python3 update_gsscode_types.py --dsn "host=... port=... dbname=... user=..."

Requires only psycopg2 -- the RGC is published as a plain CSV inside the
release zip, so no XLSX-parsing dependency (eg openpyxl) is needed.
"""
import argparse
import csv
import io
import json
import sys
import urllib.parse
import urllib.request
import zipfile

import psycopg2
from psycopg2.extras import execute_values

SEARCH_BASE = "https://www.arcgis.com/sharing/rest/search"
SEARCH_QUERY = 'tags:PRD_RGC AND categories:"/Categories/LATEST"'


def find_latest_item():
    url = SEARCH_BASE + "?" + urllib.parse.urlencode({"q": SEARCH_QUERY, "f": "json"})
    with urllib.request.urlopen(url, timeout=30) as resp:
        data = json.load(resp)
    results = data.get("results", [])
    if len(results) != 1:
        raise RuntimeError(
            f"expected exactly one RGC item tagged /Categories/LATEST, got {len(results)} "
            "-- ONS's tagging scheme may have changed, check search results manually"
        )
    item = results[0]
    return item["id"], item["title"]


def download_csv(item_id):
    url = f"https://www.arcgis.com/sharing/rest/content/items/{item_id}/data"
    with urllib.request.urlopen(url, timeout=120) as resp:
        blob = resp.read()
    zf = zipfile.ZipFile(io.BytesIO(blob))
    csv_names = [n for n in zf.namelist() if n.lower().endswith(".csv")]
    if len(csv_names) != 1:
        raise RuntimeError(
            f"expected exactly one CSV in the RGC release zip, found {csv_names} "
            "-- ONS's release packaging may have changed"
        )
    return zf.read(csv_names[0]).decode("utf-8-sig")


def parse_rows(csv_text):
    reader = csv.DictReader(io.StringIO(csv_text))
    rows = []
    for r in reader:
        gss = (r.get("Entity code") or "").strip()
        if not gss:
            continue
        rows.append((
            gss,
            (r.get("Entity name") or "").strip(),
            (r.get("Entity abbreviation") or "").strip() or None,
            (r.get("Entity theme") or "").strip() or None,
            (r.get("Entity coverage") or "").strip() or None,
            (r.get("Status") or "").strip() or None,
        ))
    return rows


def upsert(dsn, rows):
    conn = psycopg2.connect(dsn)
    try:
        conn.autocommit = False
        with conn.cursor() as cur:
            execute_values(
                cur,
                """
                INSERT INTO gsscode_types (gss, name, abbreviation, theme, coverage, status)
                VALUES %s
                ON CONFLICT (gss) DO UPDATE SET
                    name = EXCLUDED.name,
                    abbreviation = EXCLUDED.abbreviation,
                    theme = EXCLUDED.theme,
                    coverage = EXCLUDED.coverage,
                    status = EXCLUDED.status
                """,
                rows,
            )
            cur.execute("SELECT count(*) FROM gsscode_types")
            total = cur.fetchone()[0]
        conn.commit()
        return total
    finally:
        conn.close()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dsn", required=True, help='libpq connection string, eg "host=... port=... dbname=... user=..."')
    ap.add_argument("--dry-run", action="store_true", help="fetch and parse only, don't write to the database")
    args = ap.parse_args()

    item_id, title = find_latest_item()
    print(f"latest RGC release: {title} ({item_id})", file=sys.stderr)

    csv_text = download_csv(item_id)
    rows = parse_rows(csv_text)
    print(f"parsed {len(rows)} entity type rows", file=sys.stderr)

    if args.dry_run:
        for r in rows[:5]:
            print(r)
        print("... (dry run, no database changes made)", file=sys.stderr)
        return

    total = upsert(args.dsn, rows)
    print(f"upserted {len(rows)} rows, gsscode_types now has {total} rows total", file=sys.stderr)


if __name__ == "__main__":
    main()
