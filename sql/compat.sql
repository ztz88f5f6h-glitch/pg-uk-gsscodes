SELECT 'E01000001'::gsscode ~* '^E01';
SELECT 'S01000001'::gsscode ~* '^E01';
SELECT 'e01000001'::gsscode ~* '^e01';
SELECT 'E01000001'::gsscode ~ '^E01';
SELECT 'E01000001'::gsscode ~ '^e01';  -- case sensitive: no match
SELECT 'E01000001'::gsscode !~ '^S01';
SELECT 'E01000001'::gsscode !~* '^s01';

SELECT LEFT('E01000001'::gsscode, 3);
SELECT LEFT('E01000001'::gsscode, 3) = 'E01';

-- LEFT(code,n) = literal can use a plain expression index
CREATE TEMP TABLE compat_sample (code gsscode);
INSERT INTO compat_sample
   SELECT ('E01' || lpad(i::text, 6, '0'))::gsscode FROM generate_series(1,20) i;
CREATE INDEX ON compat_sample (LEFT(code, 3));
ANALYZE compat_sample;
SELECT count(*) FROM compat_sample WHERE LEFT(code, 3) = 'E01';
