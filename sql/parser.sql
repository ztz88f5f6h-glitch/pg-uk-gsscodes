-- round trip
SELECT 'E01000001'::gsscode::text;
SELECT 'K02000001'::gsscode::text;
SELECT 'w00000001'::gsscode::text;  -- lowercase normalised to upper

-- is_valid_gss
SELECT is_valid_gss('E01000001');
SELECT is_valid_gss('E0100000');    -- too short
SELECT is_valid_gss('E010000011');  -- too long
SELECT is_valid_gss('101000001');   -- no leading letter
SELECT is_valid_gss('EA1000001');   -- non-digit in type
SELECT is_valid_gss('E01999999');   -- reserved code: still valid syntax

-- invalid input raises
SELECT 'E0100000'::gsscode;
