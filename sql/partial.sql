-- scalar %% / !%%: country only
SELECT 'E01000001'::gsscode % 'E';
SELECT 'W01000001'::gsscode % 'E';
SELECT 'W01000001'::gsscode !% 'E';
SELECT 'E01000001'::gsscode !% 'E';

-- scalar %% / !%%: country+type
SELECT 'E01000001'::gsscode % 'E01';
SELECT 'E02000001'::gsscode % 'E01';

-- scalar %%: full code behaves like =
SELECT 'E01000001'::gsscode % 'E01000001';
SELECT 'E01000002'::gsscode % 'E01000001';

-- invalid-length prefixes never match, no error
SELECT 'E01000001'::gsscode % 'E0100';
SELECT 'E01000001'::gsscode % 'E0';
SELECT 'E01000001'::gsscode % '';

-- array form
SELECT 'E01000001'::gsscode % ARRAY['E01','E02'];
SELECT 'E02000001'::gsscode % ARRAY['E01','E02'];
SELECT 'W01000001'::gsscode % ARRAY['E01','E02'];
SELECT 'E01000001'::gsscode !% ARRAY['S01','S02'];
SELECT 'E01000001'::gsscode % ARRAY[]::text[];

-- %% correctness over a real table (not index-scan behaviour -- % is a
-- plain boolean filter; see sql/range.sql for the index-scan-eligible
-- range_lower()/range_upper() equivalent)
CREATE TEMP TABLE partial_sample (code gsscode);
INSERT INTO partial_sample
   SELECT ('E01' || lpad(i::text, 6, '0'))::gsscode FROM generate_series(1,50) i;
INSERT INTO partial_sample VALUES ('W01000001'), ('S01000001');
CREATE INDEX ON partial_sample USING btree (code);
ANALYZE partial_sample;
SELECT count(*) FROM partial_sample WHERE code % 'E01';
