-- Correctness fix: % was registered under btree strategy 3 (the
-- "equality" slot) purely to get an index-assisted plan for prefix
-- matches. PostgreSQL requires strategy 3's operator to be a genuine
-- equivalence relation for the planner's equivalence-class reasoning to
-- stay sound (see xindex.html / "Behavior of B-Tree Operator Classes").
-- % isn't one -- `a % 'SW1'` and `b % 'SW1'` can both hold with a <> b --
-- so this was a real correctness bug, not just an odd choice. It never
-- surfaced in the testing this extension shipped with because those
-- tests never exercised a plan shape that exploits equivalence-class
-- deduction (eg a self-join on a %-filtered column), but the planner was
-- entitled to assume soundness it didn't have.
--
-- Fix: drop the opfamily registration entirely -- % and !% remain
-- correct, ordinary boolean filters, just no longer wired into the
-- btree strategy that requires equivalence semantics. In its place,
-- range_lower()/range_upper() expose the actual prefix as a genuine
-- half-open range, usable with the already-correct </>= strategies for
-- full, sound index support:
--
--    WHERE code >= range_lower('E01') AND code < range_upper('E01')

ALTER OPERATOR FAMILY gsscode_ops USING btree DROP
   OPERATOR 3 (gsscode, text),
   FUNCTION 1 (gsscode, text);

DROP FUNCTION gsscode_cmp_partial(gsscode, text);

CREATE FUNCTION range_lower(text)
   RETURNS gsscode
   AS 'MODULE_PATHNAME', 'gsscode_range_lower'
   LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION range_upper(text)
   RETURNS gsscode
   AS 'MODULE_PATHNAME', 'gsscode_range_upper'
   LANGUAGE C IMMUTABLE STRICT;
