SELECT count(*) FROM gsscode_types;

SELECT description('E01000001'::gsscode);
SELECT description('E01');
SELECT description('e01');           -- case insensitive
SELECT description('E01000001');     -- longer text truncates to 3 chars
SELECT description('K02'::text);
SELECT description('K03'::text);
SELECT description('K04'::text);
SELECT description('S01'::text);
SELECT description('W01'::text);
SELECT description('ZZ'::text) IS NULL;  -- unknown prefix
