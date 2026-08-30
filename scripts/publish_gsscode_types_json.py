#!/usr/bin/env python3
"""Fetch the current ONS Register of Geographic Codes and write it out as
data/gsscode_types.json, in the shape gsscode_ons_refresh's
update_gsscode_types() expects.

This is the CI-side half of the http-extension refresh path: Postgres's
http extension can make a plain HTTP GET but has no trusted way to
decompress a ZIP (ONS only publishes the RGC zipped -- confirmed, no
bare-CSV endpoint, no queryable feature-service). Rather than requiring
an untrusted language (plpython3u) inside the database to do the
unzip+parse step, this script does it here -- in CI, which has no such
trust restriction -- and commits the already-decompressed, already-
parsed result to the repo. The database side then only ever needs to do
a plain HTTP GET of a JSON file plus jsonb_populate_recordset(), both
fully within PostgreSQL's trusted core.

Reuses the exact same ArcGIS search/download/parse logic as
update_gsscode_types.py (the external, direct-to-Postgres refresh
script) -- see that file's docstring for why the search is done via the
"/Categories/LATEST" tag rather than a hardcoded item id or date.

Run by .github/workflows/refresh-gsscode-types.yml on a schedule; can
also be run manually with no arguments.
"""
import csv
import io
import json
import os
import sys
import urllib.parse
import urllib.request
import zipfile

SEARCH_BASE = "https://www.arcgis.com/sharing/rest/search"
SEARCH_QUERY = 'tags:PRD_RGC AND categories:"/Categories/LATEST"'
OUTPUT_PATH = os.path.join(os.path.dirname(__file__), "..", "data", "gsscode_types.json")


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
        rows.append({
            "gss": gss,
            "name": (r.get("Entity name") or "").strip(),
            "abbreviation": (r.get("Entity abbreviation") or "").strip() or None,
            "theme": (r.get("Entity theme") or "").strip() or None,
            "coverage": (r.get("Entity coverage") or "").strip() or None,
            "status": (r.get("Status") or "").strip() or None,
        })
    return rows


def main():
    item_id, title = find_latest_item()
    print(f"latest RGC release: {title} ({item_id})", file=sys.stderr)

    csv_text = download_csv(item_id)
    rows = parse_rows(csv_text)
    print(f"parsed {len(rows)} entity type rows", file=sys.stderr)

    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    with open(OUTPUT_PATH, "w") as f:
        json.dump(rows, f, indent=2, sort_keys=True)
        f.write("\n")
    print(f"wrote {OUTPUT_PATH}", file=sys.stderr)


if __name__ == "__main__":
    main()
