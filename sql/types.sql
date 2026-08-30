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

-- whole-row form
SELECT (type_info('E01000001'::gsscode)).name;
SELECT (type_info('E01000001'::gsscode)).abbreviation;
SELECT (type_info('K02'::text)).name;
SELECT (type_info('K02'::text)).theme;
SELECT type_info('ZZ'::text) IS NULL;  -- unknown prefix
