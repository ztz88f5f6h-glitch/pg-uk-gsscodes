-- gsscode 1.1.1 -> 1.1.2: add gsscode/text cross-type equality operators
-- and an ASSIGNMENT cast from text to gsscode.
--
-- Found live 2026-08-31 testing whether gss-os-fetch's loader could
-- adopt gsscode for its "gss" columns: assignment (INSERT/UPDATE INTO a
-- gsscode column FROM a text expression) already worked via Postgres's
-- own undocumented I/O-function fallback even with zero pg_cast entries
-- -- but a direct comparison (`gsscode_col = text_col`, exactly what a
-- join between a gsscode-typed table and a still-text-typed one needs)
-- failed outright with "operator does not exist: gsscode = text".
--
-- Deliberately NOT an IMPLICIT cast: an implicit cast participates in
-- essentially all operator/function resolution and type unification
-- everywhere gsscode and text values meet, not just this one comparison
-- -- given gsscode_in is strict (raises on anything that isn't a valid
-- 9-character code), that would silently widen where a bad text value
-- can raise an error throughout the whole database, not just at
-- deliberate comparison points. A targeted pair of cross-type operators
-- fixes exactly the comparison case, matching this extension's own
-- existing precedent (~/~*/LEFT() are the same kind of narrow
-- text-compatibility shim, not a blanket cast). The ASSIGNMENT cast
-- below formalizes the INSERT-coercion behavior that was already
-- happening, undocumented, before this version.
CREATE FUNCTION gsscode_eq_text(gsscode, text)
   RETURNS boolean
   LANGUAGE sql IMMUTABLE STRICT AS $$
      SELECT $1 = $2::gsscode
   $$;

CREATE FUNCTION text_eq_gsscode(text, gsscode)
   RETURNS boolean
   LANGUAGE sql IMMUTABLE STRICT AS $$
      SELECT $1::gsscode = $2
   $$;

CREATE FUNCTION gsscode_ne_text(gsscode, text)
   RETURNS boolean
   LANGUAGE sql IMMUTABLE STRICT AS $$
      SELECT $1 != $2::gsscode
   $$;

CREATE FUNCTION text_ne_gsscode(text, gsscode)
   RETURNS boolean
   LANGUAGE sql IMMUTABLE STRICT AS $$
      SELECT $1::gsscode != $2
   $$;

CREATE OPERATOR = (
   PROCEDURE  = gsscode_eq_text,
   LEFTARG    = gsscode,
   RIGHTARG   = text,
   COMMUTATOR = =,
   NEGATOR    = <>,
   RESTRICT   = eqsel,
   JOIN       = eqjoinsel
);

CREATE OPERATOR = (
   PROCEDURE  = text_eq_gsscode,
   LEFTARG    = text,
   RIGHTARG   = gsscode,
   COMMUTATOR = =,
   NEGATOR    = <>,
   RESTRICT   = eqsel,
   JOIN       = eqjoinsel
);

CREATE OPERATOR <> (
   PROCEDURE  = gsscode_ne_text,
   LEFTARG    = gsscode,
   RIGHTARG   = text,
   COMMUTATOR = <>,
   NEGATOR    = =,
   RESTRICT   = neqsel,
   JOIN       = neqjoinsel
);

CREATE OPERATOR <> (
   PROCEDURE  = text_ne_gsscode,
   LEFTARG    = text,
   RIGHTARG   = gsscode,
   COMMUTATOR = <>,
   NEGATOR    = =,
   RESTRICT   = neqsel,
   JOIN       = neqjoinsel
);

-- ASSIGNMENT only, deliberately -- NOT IMPLICIT (see comment above).
-- Formalizes the coercion Postgres was already doing via I/O-function
-- fallback for INSERT/UPDATE ... SELECT text_expr INTO a gsscode column.
--
-- The cast function's argument must be declared as text itself, not
-- cstring, even though gsscode_in takes cstring -- confirmed live
-- 2026-08-31 ("argument of cast function must match or be
-- binary-coercible from source data type" when this used
-- gsscode_in(cstring) directly). Small wrapper needed.
CREATE FUNCTION gsscode_from_text(text)
   RETURNS gsscode
   LANGUAGE sql IMMUTABLE STRICT AS $$
      SELECT gsscode_in($1::cstring)
   $$;

CREATE CAST (text AS gsscode) WITH FUNCTION gsscode_from_text(text) AS ASSIGNMENT;
