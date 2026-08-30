-- Optional in-database refresh of gsscode_types, for installations that
-- accept the untrusted-language trust cost and want a single SQL call
-- instead of running update_gsscode_types.py externally. This is a
-- SEPARATE extension precisely so the core gsscode extension stays
-- dependency-free -- most users should never need to enable
-- plpython3u just to get the packed type and its %/!% operators.
--
-- This function reuses the exact same logic as update_gsscode_types.py
-- (same ArcGIS search query, same "/Categories/LATEST" tag lookup, same
-- CSV parsing, same upsert), just embedded as one PL/Python3u function
-- body instead of an external script. See that script's docstring for
-- why the search is done this way rather than a hardcoded item id/URL.
--
-- Requires the Postgres server process itself to have outbound internet
-- access to arcgis.com -- many production database hosts deliberately
-- firewall that off, in which case this will simply time out; the
-- external script has no such requirement since it can run from
-- wherever you have egress.
CREATE FUNCTION update_gsscode_types()
   RETURNS integer
   LANGUAGE plpython3u
   AS $$
import csv
import io
import json
import urllib.parse
import urllib.request
import zipfile

search_url = "https://www.arcgis.com/sharing/rest/search?" + urllib.parse.urlencode({
    "q": 'tags:PRD_RGC AND categories:"/Categories/LATEST"',
    "f": "json",
})
with urllib.request.urlopen(search_url, timeout=30) as resp:
    data = json.load(resp)
results = data.get("results", [])
if len(results) != 1:
    plpy.error(
        "expected exactly one RGC item tagged /Categories/LATEST, got %d "
        "-- ONS's tagging scheme may have changed, check search results manually"
        % len(results)
    )
item_id = results[0]["id"]

data_url = "https://www.arcgis.com/sharing/rest/content/items/%s/data" % item_id
with urllib.request.urlopen(data_url, timeout=120) as resp:
    blob = resp.read()

zf = zipfile.ZipFile(io.BytesIO(blob))
csv_names = [n for n in zf.namelist() if n.lower().endswith(".csv")]
if len(csv_names) != 1:
    plpy.error(
        "expected exactly one CSV in the RGC release zip, found %r "
        "-- ONS's release packaging may have changed" % csv_names
    )
csv_text = zf.read(csv_names[0]).decode("utf-8-sig")

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

plan = plpy.prepare("""
    INSERT INTO gsscode_types (gss, name, abbreviation, theme, coverage, status)
    VALUES ($1, $2, $3, $4, $5, $6)
    ON CONFLICT (gss) DO UPDATE SET
        name = EXCLUDED.name,
        abbreviation = EXCLUDED.abbreviation,
        theme = EXCLUDED.theme,
        coverage = EXCLUDED.coverage,
        status = EXCLUDED.status
""", ["text", "text", "text", "text", "text", "text"])

for row in rows:
    plpy.execute(plan, list(row))

return len(rows)
$$;

COMMENT ON FUNCTION update_gsscode_types() IS
   'Refreshes gsscode_types from the current ONS Register of Geographic Codes release. Returns the number of rows upserted. Requires the database server to have outbound internet access.';
