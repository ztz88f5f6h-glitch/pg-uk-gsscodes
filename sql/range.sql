-- basic bounds: country only
SELECT range_lower('E')::text;
SELECT range_upper('E')::text;   -- first value of the next country, F

-- basic bounds: country+type
SELECT range_lower('E01')::text;
SELECT range_upper('E01')::text; -- first value of the next type, E02

-- full 9-character code: range of exactly one value
SELECT range_lower('E01000001')::text;
SELECT range_upper('E01000001')::text;
SELECT range_lower('E01000001') = 'E01000001'::gsscode;
SELECT range_upper('E01000001') = 'E01000002'::gsscode;

-- invalid-length prefixes raise, unlike %/!% which just never match
SELECT range_lower('E0100');
SELECT range_lower('E0');
SELECT range_lower('');

-- the core soundness property: for every prefix length and every real
-- row, the range form and the %% boolean form must agree exactly
CREATE TEMP TABLE range_sample (code gsscode);
INSERT INTO range_sample
   SELECT ('E01' || lpad(i::text, 6, '0'))::gsscode FROM generate_series(1,50) i;
INSERT INTO range_sample
   SELECT ('E02' || lpad(i::text, 6, '0'))::gsscode FROM generate_series(1,20) i;
INSERT INTO range_sample VALUES ('W01000001'), ('S01000001'), ('K02000001');

SELECT count(*) AS disagreements FROM range_sample
WHERE (code % 'E01')
  IS DISTINCT FROM (code >= range_lower('E01') AND code < range_upper('E01'));

SELECT count(*) AS disagreements FROM range_sample
WHERE (code % 'E')
  IS DISTINCT FROM (code >= range_lower('E') AND code < range_upper('E'));

-- range form actually returns the right rows
SELECT count(*) FROM range_sample
WHERE code >= range_lower('E01') AND code < range_upper('E01');

CREATE INDEX ON range_sample USING btree (code);
ANALYZE range_sample;

-- range form drives a genuine index scan (ordinary </>= strategies,
-- no opfamily trickery) -- confirmed live via EXPLAIN separately, not
-- asserted here since plan cost/text isn't stable output for pg_regress
SELECT count(*) FROM range_sample
WHERE code >= range_lower('E01') AND code < range_upper('E01');
