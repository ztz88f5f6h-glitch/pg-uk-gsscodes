-- Optional in-database refresh of gsscode_types, for installations that
-- want a single SQL call instead of running update_gsscode_types.py
-- externally. This is a SEPARATE extension precisely so the core
-- gsscode extension stays dependency-free -- most users should never
-- need to enable anything extra just to get the packed type and its
-- %/!% operators.
--
-- ONS only publishes the Register of Geographic Codes as a ZIP (no
-- bare-CSV endpoint, no queryable feature-service -- confirmed), and
-- PostgreSQL has no trusted, built-in way to decompress one. Rather than
-- reaching for an untrusted language (plpython3u) to do that
-- decompression inside the database, the decompression happens outside
-- it: scripts/publish_gsscode_types_json.py runs in this repo's GitHub
-- Actions CI (roughly monthly, matching ONS's own release cadence),
-- fetches and unzips the current ONS release the same way
-- update_gsscode_types.py does, and commits the parsed result as
-- data/gsscode_types.json. This function then only ever needs to do a
-- plain HTTP GET of that JSON file plus jsonb_populate_recordset() --
-- both fully within PostgreSQL's trusted core via the `http` extension,
-- which (unlike plpython3u) can only make HTTP requests, nothing more.
-- `http` still needs superuser to enable, same as any non-default
-- extension, but it's a much narrower thing to trust than a general-
-- purpose scripting language.
--
-- This does mean trusting this repo's own GitHub Actions pipeline and
-- write access to it, in addition to ONS -- a real, if narrow, new
-- dependency worth being aware of, not just a strict improvement.
CREATE FUNCTION update_gsscode_types()
   RETURNS integer
   LANGUAGE plpgsql
   AS $$
DECLARE
   resp http_response;
   payload jsonb;
   n integer;
BEGIN
   resp := http_get('https://raw.githubusercontent.com/ztz88f5f6h-glitch/pg-uk-gsscodes/main/data/gsscode_types.json');

   IF resp.status <> 200 THEN
      RAISE EXCEPTION 'fetching gsscode_types.json failed: HTTP %', resp.status;
   END IF;

   payload := resp.content::jsonb;

   WITH incoming AS (
      SELECT * FROM jsonb_populate_recordset(NULL::gsscode_types, payload)
   ),
   upserted AS (
      INSERT INTO gsscode_types (gss, name, abbreviation, theme, coverage, status)
      SELECT gss, name, abbreviation, theme, coverage, status FROM incoming
      ON CONFLICT (gss) DO UPDATE SET
         name         = EXCLUDED.name,
         abbreviation = EXCLUDED.abbreviation,
         theme        = EXCLUDED.theme,
         coverage     = EXCLUDED.coverage,
         status       = EXCLUDED.status
      RETURNING 1
   )
   SELECT count(*) INTO n FROM upserted;

   RETURN n;
END;
$$;

COMMENT ON FUNCTION update_gsscode_types() IS
   'Refreshes gsscode_types from data/gsscode_types.json in the gsscode GitHub repo, which is itself refreshed from ONS by CI. Returns the number of rows upserted. Requires the database server to have outbound internet access to raw.githubusercontent.com.';
