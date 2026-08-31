-- gsscode 1.1.0 -> 1.1.1: rename the SQL-level range_lower/range_upper
-- functions to gsscode_range_lower/gsscode_range_upper.
--
-- Found via real live testing 2026-08-31: with both this extension and
-- the companion "postcode" extension installed in the same database
-- (the actual intended deployment, both extensions cover the same
-- AddressBase workflows), both declared a bare range_lower(text)/
-- range_upper(text) -- Postgres resolves functions by name+argument
-- types, so the two collided outright ("function already exists with
-- same argument types"). The underlying C symbols were already
-- correctly prefixed (gsscode_range_lower/gsscode_range_upper); this
-- just makes the SQL-level name match, removing any possibility of
-- colliding with another extension's identically-generic name again.
DROP FUNCTION range_lower(text);
DROP FUNCTION range_upper(text);

CREATE FUNCTION gsscode_range_lower(text)
   RETURNS gsscode
   AS 'MODULE_PATHNAME', 'gsscode_range_lower'
   LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gsscode_range_upper(text)
   RETURNS gsscode
   AS 'MODULE_PATHNAME', 'gsscode_range_upper'
   LANGUAGE C IMMUTABLE STRICT;
