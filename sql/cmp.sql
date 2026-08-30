SELECT 'E01000001'::gsscode = 'E01000001'::gsscode;
SELECT 'E01000001'::gsscode <> 'E02000001'::gsscode;
SELECT 'E01000001'::gsscode < 'E01000002'::gsscode;
SELECT 'E01000001'::gsscode > 'E01000002'::gsscode;
SELECT 'E01000001'::gsscode <= 'E01000001'::gsscode;
SELECT 'E01000001'::gsscode >= 'E01000001'::gsscode;

-- country sorts before type sorts before area
SELECT 'E99000001'::gsscode < 'J01000001'::gsscode;  -- country order
SELECT 'E01999999'::gsscode < 'E02000001'::gsscode;  -- type order
SELECT 'E01000001'::gsscode < 'E01000002'::gsscode;  -- area order

-- ORDER BY matches expected country/type/area sequence
CREATE TEMP TABLE cmp_sample (code gsscode);
INSERT INTO cmp_sample VALUES
   ('W01000001'), ('E02000001'), ('E01000002'), ('K02000001'), ('E01000001');
SELECT code FROM cmp_sample ORDER BY code;

-- accessors
SELECT country('E01000001'::gsscode);
SELECT gss_type('E01000001'::gsscode);
SELECT area('E01000001'::gsscode);
SELECT gss_type('K99000003'::gsscode);
SELECT area('E01999999'::gsscode);
