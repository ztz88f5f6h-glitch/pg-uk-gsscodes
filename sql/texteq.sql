-- gsscode/text cross-type equality: added 2026-08-31, found live while
-- checking whether a gsscode-typed column can join against a still-text
-- typed one (exactly what a loader migrating one table at a time needs).

-- assignment coercion (was already working via Postgres's own I/O
-- fallback before this version; the ASSIGNMENT cast formalizes it)
CREATE TEMP TABLE gsstest (gss gsscode PRIMARY KEY);
CREATE TEMP TABLE texttest (code text);
INSERT INTO texttest VALUES ('E01000001'), ('E02000001');
INSERT INTO gsstest (gss) SELECT code FROM texttest;
SELECT gss::text FROM gsstest ORDER BY gss;

-- the actual point of this version: direct comparison across the two
-- types, both argument orders
SELECT 'E01000001'::gsscode = 'E01000001'::text;
SELECT 'E01000001'::text = 'E01000001'::gsscode;
SELECT 'E01000001'::gsscode = 'E02000001'::text;
SELECT 'E01000001'::gsscode <> 'E02000001'::text;
SELECT 'E01000001'::text <> 'E02000001'::gsscode;

-- a join between a gsscode-typed table and a still-text-typed one --
-- this is the exact query shape that failed before this version
SELECT G.gss::text, T.code
FROM gsstest G JOIN texttest T ON G.gss = T.code
ORDER BY G.gss;
