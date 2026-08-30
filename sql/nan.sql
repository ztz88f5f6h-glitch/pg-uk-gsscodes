-- reserved/"NaN" codes: area = 999999 within any type
SELECT isnan('E00999999'::gsscode);
SELECT isnan('E01999999'::gsscode);
SELECT isnan('K99999999'::gsscode);
SELECT isnan('E01000001'::gsscode);   -- ordinary code: not NaN
SELECT isnan('K99000003'::gsscode);   -- real Extra-Regio entry: not NaN

-- deliberately NOT IEEE-754 NaN semantics: reserved codes are ordinary,
-- fully self-equal, normally-ordered values under every operator except
-- isnan() itself -- this keeps the type usable in a plain btree index.
SELECT 'E01999999'::gsscode = 'E01999999'::gsscode;
SELECT 'E01999999'::gsscode <> 'E01999999'::gsscode;
SELECT 'E01999999'::gsscode < 'E02000001'::gsscode;
SELECT 'E01999999'::gsscode > 'E01000001'::gsscode;
SELECT 'E01999999'::gsscode <= 'E01999999'::gsscode;
SELECT 'E01999999'::gsscode >= 'E01999999'::gsscode;
