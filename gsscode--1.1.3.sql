CREATE TYPE gsscode;

CREATE FUNCTION gsscode_in(cstring)
   RETURNS gsscode
   AS 'MODULE_PATHNAME'
   LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gsscode_out(gsscode)
   RETURNS cstring
   AS 'MODULE_PATHNAME'
   LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gsscode_recv(internal)
   RETURNS gsscode
   AS 'MODULE_PATHNAME'
   LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gsscode_send(gsscode)
   RETURNS bytea
   AS 'MODULE_PATHNAME'
   LANGUAGE C IMMUTABLE STRICT;

CREATE TYPE gsscode (
   INPUT    = gsscode_in,
   OUTPUT   = gsscode_out,
   RECEIVE  = gsscode_recv,
   SEND     = gsscode_send,
   LIKE     = pg_catalog.int4,
   CATEGORY = 'S'
);

CREATE FUNCTION gsscode_validate(text)
   RETURNS boolean
   AS 'MODULE_PATHNAME'
   LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION is_valid_gss(text)
   RETURNS boolean
   AS 'MODULE_PATHNAME', 'gsscode_validate'
   LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gsscode_cmp(gsscode, gsscode)
   RETURNS integer
   AS 'MODULE_PATHNAME'
   LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gsscode_eq(gsscode, gsscode)
   RETURNS boolean
   AS 'MODULE_PATHNAME'
   LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gsscode_ne(gsscode, gsscode)
   RETURNS boolean
   AS 'MODULE_PATHNAME'
   LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gsscode_lt(gsscode, gsscode)
   RETURNS boolean
   AS 'MODULE_PATHNAME'
   LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gsscode_gt(gsscode, gsscode)
   RETURNS boolean
   AS 'MODULE_PATHNAME'
   LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gsscode_lte(gsscode, gsscode)
   RETURNS boolean
   AS 'MODULE_PATHNAME'
   LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gsscode_gte(gsscode, gsscode)
   RETURNS boolean
   AS 'MODULE_PATHNAME'
   LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
   PROCEDURE  = gsscode_eq,
   LEFTARG    = gsscode,
   RIGHTARG   = gsscode,
   COMMUTATOR = =,
   NEGATOR    = <>,
   RESTRICT   = eqsel,
   JOIN       = eqjoinsel);

CREATE OPERATOR <> (
   PROCEDURE  = gsscode_ne,
   LEFTARG    = gsscode,
   RIGHTARG   = gsscode,
   COMMUTATOR = <>,
   NEGATOR    = =,
   RESTRICT   = neqsel,
   JOIN       = neqjoinsel);

CREATE OPERATOR < (
   PROCEDURE  = gsscode_lt,
   LEFTARG    = gsscode,
   RIGHTARG   = gsscode,
   COMMUTATOR = >,
   NEGATOR    = >=);

CREATE OPERATOR > (
   PROCEDURE  = gsscode_gt,
   LEFTARG    = gsscode,
   RIGHTARG   = gsscode,
   COMMUTATOR = <,
   NEGATOR    = <=);

CREATE OPERATOR <= (
   PROCEDURE  = gsscode_lte,
   LEFTARG    = gsscode,
   RIGHTARG   = gsscode,
   COMMUTATOR = >=,
   NEGATOR    = >);

CREATE OPERATOR >= (
   PROCEDURE  = gsscode_gte,
   LEFTARG    = gsscode,
   RIGHTARG   = gsscode,
   COMMUTATOR = <=,
   NEGATOR    = <);

CREATE OPERATOR FAMILY gsscode_ops USING btree;

CREATE OPERATOR CLASS gsscode_ops
DEFAULT FOR TYPE gsscode USING btree FAMILY gsscode_ops AS
   OPERATOR 1 <,
   OPERATOR 2 <=,
   OPERATOR 3 =,
   OPERATOR 4 >=,
   OPERATOR 5 >,
   FUNCTION 1 gsscode_cmp(gsscode, gsscode);

-- Partial/prefix matching: `code % 'E01'` matches any code whose country
-- and type are E/01 regardless of area; `code % 'E'` matches country E
-- regardless of type/area. Only prefix lengths of 1 (country), 3
-- (country+type) or 9 (full code) are meaningful -- anything else never
-- matches. The array form lets you match against several prefixes at
-- once, eg `code % ARRAY['E01','E02']`.

CREATE FUNCTION gsscode_eq_partial(gsscode, text)
   RETURNS boolean
   AS 'MODULE_PATHNAME'
   LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gsscode_ne_partial(gsscode, text)
   RETURNS boolean
   AS 'MODULE_PATHNAME'
   LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR % (
   PROCEDURE  = gsscode_eq_partial,
   LEFTARG    = gsscode,
   RIGHTARG   = text,
   NEGATOR    = !%,
   RESTRICT   = eqsel,
   JOIN       = eqjoinsel
);

CREATE OPERATOR !% (
   PROCEDURE  = gsscode_ne_partial,
   LEFTARG    = gsscode,
   RIGHTARG   = text,
   NEGATOR    = %,
   RESTRICT   = neqsel,
   JOIN       = neqjoinsel
);

CREATE FUNCTION gsscode_range_lower(text)
   RETURNS gsscode
   AS 'MODULE_PATHNAME', 'gsscode_range_lower'
   LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gsscode_range_upper(text)
   RETURNS gsscode
   AS 'MODULE_PATHNAME', 'gsscode_range_upper'
   LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gsscode_eq_partial_any(gsscode, text[])
   RETURNS boolean
   LANGUAGE sql IMMUTABLE STRICT AS $$
      SELECT EXISTS (SELECT 1 FROM unnest($2) p WHERE gsscode_eq_partial($1, p))
   $$;

CREATE FUNCTION gsscode_ne_partial_any(gsscode, text[])
   RETURNS boolean
   LANGUAGE sql IMMUTABLE STRICT AS $$
      SELECT NOT EXISTS (SELECT 1 FROM unnest($2) p WHERE gsscode_eq_partial($1, p))
   $$;

CREATE OPERATOR % (
   PROCEDURE  = gsscode_eq_partial_any,
   LEFTARG    = gsscode,
   RIGHTARG   = text[],
   NEGATOR    = !%,
   RESTRICT   = eqsel,
   JOIN       = eqjoinsel
);

CREATE OPERATOR !% (
   PROCEDURE  = gsscode_ne_partial_any,
   LEFTARG    = gsscode,
   RIGHTARG   = text[],
   NEGATOR    = %,
   RESTRICT   = neqsel,
   JOIN       = neqjoinsel
);

-- Text-compatibility shims: `code ~ 'pattern'`, `code ~* 'pattern'` and
-- `left(code, n)` on a gsscode column, for existing queries/reports
-- written against the old plain-text gss column (eg "WHERE gsscode ~*
-- '^E03'", "WHERE LEFT(gsscode,3) = 'E03'") to keep working unmodified
-- once the column's type changes from text to gsscode.
--
-- IMPORTANT: these are compatibility shims, not a fast path. Each one
-- renders the packed value back to its 9-character text form and then
-- runs the ordinary text operator/function, so a btree index on the
-- gsscode column gives them no help -- they cost the same as running the
-- equivalent query against the original text column would have. The %
-- and !% operators above are the ones that get the indexed, bitmask
-- comparison this type exists for; prefer them (eg `code % 'E03'`
-- instead of `code ~* '^E03'`, `code % 'E01'` instead of
-- `LEFT(code,3) = 'E01'`) wherever performance matters.

CREATE FUNCTION left(gsscode, integer)
   RETURNS text
   LANGUAGE sql IMMUTABLE STRICT AS $$ SELECT left($1::text, $2) $$;

CREATE FUNCTION gsscode_regexeq(gsscode, text)
   RETURNS boolean
   LANGUAGE sql IMMUTABLE STRICT AS $$ SELECT $1::text ~ $2 $$;

CREATE FUNCTION gsscode_regexne(gsscode, text)
   RETURNS boolean
   LANGUAGE sql IMMUTABLE STRICT AS $$ SELECT $1::text !~ $2 $$;

CREATE FUNCTION gsscode_iregexeq(gsscode, text)
   RETURNS boolean
   LANGUAGE sql IMMUTABLE STRICT AS $$ SELECT $1::text ~* $2 $$;

CREATE FUNCTION gsscode_iregexne(gsscode, text)
   RETURNS boolean
   LANGUAGE sql IMMUTABLE STRICT AS $$ SELECT $1::text !~* $2 $$;

CREATE OPERATOR ~ (
   PROCEDURE  = gsscode_regexeq,
   LEFTARG    = gsscode,
   RIGHTARG   = text,
   NEGATOR    = !~,
   RESTRICT   = regexeqsel,
   JOIN       = regexeqjoinsel
);

CREATE OPERATOR !~ (
   PROCEDURE  = gsscode_regexne,
   LEFTARG    = gsscode,
   RIGHTARG   = text,
   NEGATOR    = ~,
   RESTRICT   = regexnesel,
   JOIN       = regexnejoinsel
);

CREATE OPERATOR ~* (
   PROCEDURE  = gsscode_iregexeq,
   LEFTARG    = gsscode,
   RIGHTARG   = text,
   NEGATOR    = !~*,
   RESTRICT   = icregexeqsel,
   JOIN       = icregexeqjoinsel
);

CREATE OPERATOR !~* (
   PROCEDURE  = gsscode_iregexne,
   LEFTARG    = gsscode,
   RIGHTARG   = text,
   NEGATOR    = ~*,
   RESTRICT   = icregexnesel,
   JOIN       = icregexnejoinsel
);

-- Component accessors -- avoid unpacking to text and re-parsing just to
-- filter or group by country/type.

CREATE FUNCTION country(gsscode)
   RETURNS text
   AS 'MODULE_PATHNAME', 'gsscode_country'
   LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gss_type(gsscode)
   RETURNS integer
   AS 'MODULE_PATHNAME', 'gsscode_type'
   LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION area(gsscode)
   RETURNS integer
   AS 'MODULE_PATHNAME', 'gsscode_area'
   LANGUAGE C IMMUTABLE STRICT;

-- ONS reserves area=999999 within every type as a "no code assigned"
-- placeholder (eg E00999999, E01999999, K99999999) -- see the live
-- Register of Geographic Codes "Reserved code (for CHD use)" column,
-- which follows this pattern for all 206 current entity types. isnan()
-- lets callers filter these out (or find them) explicitly, the same way
-- float8's isnan() does for IEEE NaN -- these values are ordinary,
-- fully-comparable gsscode values otherwise; nothing about ordering or
-- equality treats them specially.
CREATE FUNCTION isnan(gsscode)
   RETURNS boolean
   AS 'MODULE_PATHNAME', 'gsscode_isnan'
   LANGUAGE C IMMUTABLE STRICT;

-- Private reference table of ONS entity types (what a 3-character
-- country+type prefix actually means, eg 'E01' -> 'Lower layer Super
-- Output Areas'), seeded from the ONS Register of Geographic Codes
-- (June 2025 release, geoportal.statistics.gov.uk) -- 206 rows, small
-- and stable enough to ship with the extension. It does NOT hold
-- individual area names (eg what "E01000001" itself is called) -- that's
-- a much larger, per-installation dataset (500,000+ rows, changing as
-- boundaries are redrawn) that stays external rather than being baked
-- into a general-purpose extension. See update_gsscode_types.py for how
-- to refresh this table from the current ONS release.
CREATE TABLE gsscode_types (
   gss           char(3) PRIMARY KEY,
   name          text NOT NULL,
   abbreviation  text,
   theme         text,
   coverage      text,
   status        text
);

INSERT INTO gsscode_types (gss, name, abbreviation, theme, coverage, status) VALUES
('E00', 'Output Areas', 'OA', 'Statistical Building Block', 'England', 'Current'),
('E01', 'Lower layer Super Output Areas', 'LSOA', 'Statistical Building Block', 'England', 'Current'),
('E02', 'Middle layer Super Output Areas', 'MSOA', 'Statistical Building Block', 'England', 'Current'),
('E04', 'Civil Parishes', 'PAR', 'Administrative', 'England', 'Current'),
('E05', 'Electoral Wards/Divisions', 'WD', 'Administrative/Electoral', 'England', 'Current'),
('E06', 'Unitary Authorities', 'UA', 'Administrative', 'England', 'Current'),
('E07', 'Non-metropolitan Districts', 'NMD', 'Administrative', 'England', 'Current'),
('E08', 'Metropolitan Districts', 'MD', 'Administrative', 'England', 'Current'),
('E09', 'London Boroughs', 'LONB', 'Administrative', 'England', 'Current'),
('E10', 'Counties', 'CTY', 'Administrative', 'England', 'Current'),
('E11', 'Metropolitan Counties', 'MCTY', 'Administrative', 'England', 'Current'),
('E12', 'Regions', 'RGN', 'Administrative', 'England', 'Current'),
('E13', 'Inner and Outer London', 'IOL', 'Statistical Building Block', 'England', 'Current'),
('E14', 'Westminster Parliamentary Constituencies', 'PCON', 'Electoral', 'England', 'Current'),
('E15', 'European Electoral Regions', 'EER', 'Electoral', 'England', 'Archived'),
('E16', 'Primary Care Trusts', 'PCT', 'Health', 'England', 'Archived'),
('E17', 'Care Trusts', 'CT', 'Health', 'England', 'Archived'),
('E18', 'Strategic Health Authorities', 'SHA', 'Health', 'England', 'Archived'),
('E19', 'Pan Strategic Health Authorities', 'PSHA', 'Health', 'England', 'Archived'),
('E20', 'Cancer Registries', 'CANREG', 'Health', 'England', 'Current'),
('E21', 'Cancer Networks', 'CANNET', 'Health', 'England', 'Archived'),
('E22', 'Community Safety Partnerships', 'CSP', 'Other', 'England', 'Current'),
('E23', 'Police Force Areas', 'PFA', 'Other', 'England', 'Current'),
('E24', 'Local Learning and Skills Council areas', 'LLSC', 'Other', 'England', 'Archived'),
('E25', 'Primary Urban Areas', 'PUA', 'Other', 'England', 'Current'),
('E26', 'National Parks', 'NPARK', 'Other', 'England', 'Current'),
('E27', 'New Deal for Communities', 'NDC', 'Other', 'England', 'Archived'),
('E28', 'Registration Districts', 'REGD', 'Other', 'England', 'Current'),
('E29', 'Registration Sub-district', 'REGSD', 'Other', 'England', 'Current'),
('E30', 'Travel to Work Areas', 'TTWA', 'Other', 'England', 'Current'),
('E31', 'Fire and Rescue Authorities', 'FRA', 'Other', 'England', 'Current'),
('E32', 'London Assembly Constituencies', 'LAC', 'Electoral', 'England', 'Current'),
('E33', 'Workplace Zones', 'WZ', 'Census', 'England', 'Current'),
('E34', 'Built Up Areas (2011 Version)', 'BUA', 'Census', 'England', 'Archived'),
('E35', 'Built Up Area sub-divisions (2011 Version)', 'BUASD', 'Census', 'England', 'Archived'),
('E36', 'Census Merged Wards ', 'CMWD', 'Census', 'England', 'Current'),
('E37', 'Local Enterprise Partnerships', 'LEP', 'Other', 'England', 'Archived'),
('E38', 'Sub Integrated Care Board Locations', 'SICBL', 'Health', 'England', 'Current'),
('E39', 'NHS England (Region, Local Office)', 'NHSRLO', 'Health', 'England', 'Archived'),
('E40', 'NHS England Regions', 'NHSER', 'Health', 'England', 'Current'),
('E41', 'Census Merged Local Authority Districts', 'CMLAD', 'Census', 'England', 'Current'),
('E42', 'Census Merged Counties', 'CMCTY', 'Census', 'England', 'Current'),
('E43', 'Non-Civil Parished Areas', 'NCP', 'Census', 'England', 'Current'),
('E45', 'Public Health England Centres', 'PHEC', 'Health', 'England', 'Archived'),
('E46', 'Public Health England Regions', 'PHEREG', 'Health', 'England', 'Archived'),
('E47', 'Combined Authorities', 'CAUTH', 'Administrative', 'England', 'Current'),
('E48', 'Local Resilience Forums', 'LRF', 'Other', 'England', 'Current'),
('E49', 'Enterprise Zones', 'EZ', 'Other', 'England', 'Current'),
('E50', 'Waste Authorities', 'WA', 'Other', 'England', 'Current'),
('E51', 'Development Corporations', 'DC', 'Other', 'England', 'Current'),
('E52', 'LEP - overlapping part', 'LEPOP', 'Other', 'England', 'Archived'),
('E53', 'LEP - non overlapping part ', 'LEPNOP', 'Other', 'England', 'Archived'),
('E54', 'Integrated Care Boards', 'ICB', 'Health', 'England', 'Current'),
('E55', 'Strategic Clinical Networks', 'SCN', 'Health', 'England', 'Current'),
('E56', 'Cancer Alliances', 'CAL', 'Health', 'England', 'Current'),
('E57', 'National Cancer Vanguards', 'NCV', 'Health', 'England', 'Archived'),
('E58', 'County Electoral Divisions', 'CED', 'Electoral', 'England', 'Current'),
('E59', 'Integrated Care Systems', 'ICS', 'Health', 'England', 'Archived'),
('E60', 'Local Planning Authorities', 'LPA', 'Administrative', 'England', 'Current'),
('E61', 'Greater London Authority', 'GLA', 'Administrative', 'England', 'Current'),
('E62', 'National Landscapes (formerly AONB)', 'NL', 'Other', 'England', 'Current'),
('E63', 'Built Up Areas', 'BUA', 'Census', 'England', 'Current'),
('E65', 'England Non-National Park Area', 'NonNPARK', 'Census', 'England', 'Current'),
('E66', 'Grouped Local Authority Districts (Parishes)', 'GLAD', 'Census', 'England', 'Current'),
('E67', 'Census Merged Local Authority Districts 2021', 'CMLAD21', 'Census', 'England', 'Current'),
('E68', 'Grouped Lower Tier Local Authorities 2022', 'GLTLA', 'Census', 'England', 'Current'),
('E69', 'Local Skills Improvement Plan areas', 'LSIP', 'Other', 'England', 'Current'),
('E92', 'Country', 'CTRY', 'Administrative', 'England', 'Current'),
('J01', 'Major Towns and Cities', 'TCITY', 'Experimental', 'England and Wales', 'Current'),
('J02', '1961 Census Parishes', 'PAR', 'Census', 'England and Wales', 'Current'),
('J03', '1961 Census Wards', 'WD', 'Census', 'England and Wales', 'Current'),
('J04', '1961 Census Districts', 'LAD', 'Census', 'England and Wales', 'Current'),
('J05', '1961 Census Counties', 'CTY', 'Census', 'England and Wales', 'Current'),
('J06', 'Covid Infection Survey', 'CIS', 'Health', 'United Kingdom', 'Current'),
('K01', 'Travel to Work Areas', 'TTWA', 'Other', 'United Kingdom', 'Current'),
('K02', 'United Kingdom', 'UK', 'Administrative', 'United Kingdom', 'Current'),
('K03', 'Great Britain', 'GB', 'Administrative', 'Great Britain', 'Current'),
('K04', 'England and Wales', 'E&W', 'Administrative', 'England and Wales', 'Current'),
('K05', 'Built Up Areas (2011 Version)', 'BUA', 'Census', 'England and Wales', 'Archived'),
('K06', 'Built Up Area sub divisions (2011 Version)', 'BUASD', 'Census', 'England and Wales', 'Archived'),
('K07', 'National Landscapes (formerly AONB)', 'NL', 'Other', 'England and Wales', 'Current'),
('K08', 'Built Up Areas', 'BUA', 'Census', 'England and Wales', 'Current'),
('K99', 'Non-Standard Geography Categories', 'NSGC', 'Other', 'United Kingdom', 'Current'),
('L00', 'Strategic Health Authorities', 'SHA', 'Health', 'Channel Islands', 'Current'),
('L93', 'British Crown Dependencies', 'BCD', 'Administrative', 'Channel Islands', 'Current'),
('M00', 'Strategic Health Authorities', 'SHA', 'Health', 'Isle of Man', 'Current'),
('M01', 'Primary Healthcare Directorate', 'PHD', 'Health', 'Isle of Man', 'Current'),
('M83', 'British Crown Dependency', 'BCD', 'Administrative', 'Isle of Man', 'Current'),
('N00', 'Small Areas', 'SA', 'Statistical Building Block', 'Northern Ireland', 'Archived'),
('N05', 'Westminster Parliamentary Constituencies', 'PCON', 'Electoral', 'Northern Ireland', 'Current'),
('N06', 'Westminster Parliamentary Constituencies', 'PCON', 'Electoral', 'Northern Ireland', 'Archived'),
('N07', 'European Electoral Regions', 'EER', 'Electoral', 'Northern Ireland', 'Archived'),
('N08', 'Electoral Wards', 'WD', 'Administrative/Electoral', 'Northern Ireland', 'Current'),
('N09', 'Local Government Districts', 'LGD', 'Administrative', 'Northern Ireland', 'Current'),
('N10', 'District Electoral Areas', 'DEA', 'Electoral', 'Northern Ireland', 'Current'),
('N11', 'Settlement 2015', 'SETT2015', 'Census', 'Northern Ireland', 'Current'),
('N12', 'Travel to Work Areas', 'TTWA', 'Other', 'Northern Ireland', 'Current'),
('N13', 'Local Planning Authorities', 'LPA', 'Administrative', 'Northern Ireland', 'Current'),
('N19', 'Workplace Zones', 'WZ', 'Census', 'Northern Ireland', 'Current'),
('N20', 'Data Zones', 'DZ', 'Census', 'Northern Ireland', 'Current'),
('N21', 'Super Data Zones', 'SDZ', 'Census', 'Northern Ireland', 'Current'),
('N23', 'Police Force Areas', 'PFA', 'Other', 'Northern Ireland', 'Current'),
('N24', 'Police Force Districts', 'PFD', 'Other', 'Northern Ireland', 'Current'),
('N31', 'Northern Ireland Fire and Rescue Service', 'NIFRS', 'Other', 'Northern Ireland', 'Current'),
('N32', 'Northern Ireland Fire and Rescue Service Areas', 'NIFRSA', 'Other', 'Northern Ireland', 'Current'),
('N33', 'Northern Ireland Fire and Rescue Service Districts', 'NIFRSD', 'Other', 'Northern Ireland', 'Current'),
('N34', 'City Regions', 'CREG', 'Other', 'Northern Ireland', 'Current'),
('N92', 'Country', 'CTRY', 'Administrative', 'Northern Ireland', 'Current'),
('S00', 'Output Areas', 'OA', 'Statistical Building Block', 'Scotland', 'Current'),
('S01', 'Data Zones', 'DZ', 'Statistical Building Block', 'Scotland', 'Current'),
('S02', 'Intermediate Zones', 'IZ', 'Statistical Building Block', 'Scotland', 'Current'),
('S03', 'Community Health Partnerships', 'CHP', 'Health', 'Scotland', 'Archived'),
('S04', 'Regeneration Outcome Agreement Areas - Scotland', 'ROAS', 'Housing and Regeneration', 'Scotland', 'Current'),
('S05', 'Regeneration Outcome Areas - Community Planning Partnerships', 'ROAC', 'Housing and Regeneration', 'Scotland', 'Current'),
('S06', 'Regeneration Outcome Areas - Local Areas', 'ROAL', 'Housing and Regeneration', 'Scotland', 'Current'),
('S07', 'Regional Transport Partnerships', 'RTP', 'Transport', 'Scotland', 'Current'),
('S08', 'Health Board areas', 'HB', 'Health', 'Scotland', 'Current'),
('S09', 'Enterprise Regions', 'ER', 'Economic', 'Scotland', 'Current'),
('S10', 'Urban Regeneration Companies', 'URC', 'Economic', 'Scotland', 'Current'),
('S11', 'Strategic Development Plan Areas', 'SDPA', 'Administrative', 'Scotland', 'Current'),
('S12', 'Council Areas', 'CA', 'Administrative', 'Scotland', 'Current'),
('S13', 'Electoral Wards', 'WD', 'Administrative/Electoral', 'Scotland', 'Current'),
('S14', 'Westminster Parliamentary Constituencies', 'PCON', 'Electoral', 'Scotland', 'Current'),
('S15', 'European Electoral Regions', 'EER', 'Electoral', 'Scotland', 'Archived'),
('S16', 'Scottish Parliamentary Constituencies ', 'SPC', 'Electoral', 'Scotland', 'Current'),
('S17', 'Scottish Parliamentary Regions', 'SPR', 'Electoral', 'Scotland', 'Current'),
('S19', 'Localities', 'LOCS', 'Other', 'Scotland', 'Current'),
('S20', 'Settlements', 'SETT', 'Other', 'Scotland', 'Current'),
('S21', 'National Parks', 'NPARK', 'Other', 'Scotland', 'Current'),
('S22', 'Travel to Work Areas', 'TTWA', 'Other', 'Scotland', 'Current'),
('S23', 'Police Force Areas', 'PFA', 'Other', 'Scotland', 'Current'),
('S24', 'Highlands and Islands Enterprise', 'HIE', 'Economic', 'Scotland', 'Current'),
('S25', 'Community Justice Authorities', 'CJA', 'Other', 'Scotland', 'Current'),
('S26', 'Community Health Partnerships sub-areas', 'CHCP', 'Health', 'Scotland', 'Archived'),
('S27', 'ISD Health Board of Treatment', 'ISDT', 'Health', 'Scotland', 'Current'),
('S28', 'Census Detailed Characteristics', 'CDC', 'Census', 'Scotland', 'Current'),
('S29', 'Census Local Characteristics', 'CLC', 'Census', 'Scotland', 'Current'),
('S30', 'Local Administrative Units 1', 'LAU1', 'Administrative', 'Scotland', 'Current'),
('S31', 'Local Administrative Units 2', 'LAU2', 'Administrative', 'Scotland', 'Current'),
('S32', 'Scottish Police Divisions', 'SPD', 'Other', 'Scotland', 'Current'),
('S33', 'Broad Rental Market Areas', 'BRMA', 'Housing and Regeneration', 'Scotland', 'Current'),
('S34', 'Workplace Zones', 'WZ', 'Census', 'Scotland', 'Current'),
('S35', 'Civil Parish', 'CVP', 'Administrative', 'Scotland', 'Archived'),
('S36', 'Island Groups', 'ISLG', 'Other', 'Scotland', 'Current'),
('S37', 'Integration Authorities', 'HIA', 'Health', 'Scotland', 'Current'),
('S38', 'Scottish Fire and Rescue Service', 'SFRS', 'Other', 'Scotland', 'Current'),
('S39', 'Scottish Fire and Rescue Local Senior Officer Areas', 'SFRLSO', 'Other', 'Scotland', 'Current'),
('S40', 'Scottish Fire and Rescue Service Delivery Areas', 'SFRSDA', 'Other', 'Scotland', 'Current'),
('S41', 'Scottish Marine Regions', 'SMR', 'Other', 'Scotland', 'Current'),
('S42', 'Scottish Local Resilience Partnerships', 'SLRP', 'Other', 'Scotland', 'Current'),
('S43', 'Scottish Regional Resilience Partnerships', 'SRRP', 'Other', 'Scotland', 'Current'),
('S44', 'Local Planning Authorities', 'LPA', 'Administrative', 'Scotland', 'Current'),
('S45', 'Built Up Areas', 'BUA', 'Census', 'Scotland', 'Current'),
('S47', 'Non-Standard Geography Categories', 'NSGC', 'Other', 'Scotland', 'Current'),
('S48', 'Scotttish Island Regions', 'SIR', 'Other', 'Scotland', 'Current'),
('S52', 'Census Locality', 'CLOC', 'Other', 'Scotland', 'Current'),
('S53', 'Census Settlement', 'CSETT', 'Other', 'Scotland', 'Current'),
('S92', 'Country', 'CTRY', 'Administrative', 'Scotland', 'Current'),
('W00', 'Output Areas', 'OA', 'Statistical Building Block', 'Wales', 'Current'),
('W01', 'Lower layer Super Output Areas', 'LSOA', 'Statistical Building Block', 'Wales', 'Current'),
('W02', 'Middle layer Super Output Areas', 'MSOA', 'Statistical Building Block', 'Wales', 'Current'),
('W03', 'Upper layer Super Output Areas', 'USOA', 'Statistical Building Block', 'Wales', 'Archived'),
('W04', 'Communities', 'COM', 'Administrative', 'Wales', 'Current'),
('W05', 'Electoral Wards', 'WD', 'Administrative/Electoral', 'Wales', 'Current'),
('W06', 'Unitary Authorities', 'UA', 'Administrative', 'Wales', 'Current'),
('W07', 'Westminster Parliamentary Constituencies', 'PCON', 'Electoral', 'Wales', 'Current'),
('W08', 'European Electoral Regions', 'EER', 'Electoral', 'Wales', 'Archived'),
('W09', 'Senedd Constituencies', 'SENC', 'Electoral', 'Wales', 'Current'),
('W10', 'Senedd Electoral Regions', 'SENER', 'Electoral', 'Wales', 'Current'),
('W11', 'Local Health Boards', 'LHB', 'Health', 'Wales', 'Current'),
('W12', 'Cancer Registries', 'CANREG', 'Health', 'Wales', 'Current'),
('W13', 'Cancer Networks', 'CANNET', 'Health', 'Wales', 'Current'),
('W14', 'Community Safety Partnerships', 'CSP', 'Other', 'Wales', 'Current'),
('W15', 'Police Force Areas', 'PFA', 'Other', 'Wales', 'Current'),
('W16', 'Department for Children, Education, Lifelong Learning and Skills, WG', 'DCELLS', 'Other', 'Wales', 'Current'),
('W18', 'National Parks', 'NPARK', 'Other', 'Wales', 'Current'),
('W19', 'Senedd Cymru Economic Regions', 'SCER', 'Other', 'Wales', 'Current'),
('W20', 'Registration Districts', 'REGD', 'Other', 'Wales', 'Current'),
('W21', 'Registration Sub-district', 'REGSD', 'Other', 'Wales', 'Current'),
('W22', 'Travel to Work Areas', 'TTWA', 'Other', 'Wales', 'Current'),
('W23', 'Spatial Plan Areas', 'SPA', 'Other', 'Wales', 'Current'),
('W24', 'Spatial Plan Sub-areas', 'SPSA', 'Other', 'Wales', 'Current'),
('W25', 'Fire and Rescue Authorities', 'FRA', 'Other', 'Wales', 'Current'),
('W26', 'Strategic Regeneration Areas', 'SRA', 'Other', 'Wales', 'Current'),
('W27', 'Strategic Regeneration Sub-areas', 'SRASub', 'Other', 'Wales', 'Current'),
('W28', 'Transport Consortia Areas', 'TCA', 'Other', 'Wales', 'Current'),
('W29', 'Agricultural Regions', 'AgricReg', 'Other', 'Wales', 'Current'),
('W30', 'Agricultural Small Areas', 'AgricSmall', 'Other', 'Wales', 'Current'),
('W31', 'Wales Non-National Park Area', 'NonNPARK', 'Other', 'Wales', 'Current'),
('W32', 'Non-Strategic Regeneration Area', 'NonSRA', 'Other', 'Wales', 'Current'),
('W33', 'Communities First Areas', 'CFA', 'Other', 'Wales', 'Current'),
('W34', 'Non-Communities First Areas', 'NonCFA', 'Other', 'Wales', 'Current'),
('W35', 'Workplace Zones', 'WZ', 'Census', 'Wales', 'Current'),
('W36', 'Footprint Regions for Public Service Collaboration', 'PSCReg', 'Administrative', 'Wales', 'Current'),
('W37', 'Built Up Areas (2011 Version)', 'BUA', 'Census', 'Wales', 'Archived'),
('W38', 'Built Up Area sub-divisions (2011 Version)', 'BUASD', 'Census', 'Wales', 'Archived'),
('W39', 'Census Merged Wards', 'CMWD', 'Census', 'Wales', 'Current'),
('W40', 'Census Merged Local Authority Districts', 'CMLAD', 'Census', 'Wales', 'Current'),
('W41', 'Local Resilience Forums', 'LRF', 'Other', 'Wales', 'Current'),
('W42', 'City Regions', 'CREG', 'Other', 'Wales', 'Current'),
('W43', 'Local Planning Authorities', 'LPA', 'Administrative', 'Wales', 'Current'),
('W44', 'National Landscapes (formerly AONB)', 'NL', 'Other', 'Wales', 'Current'),
('W45', 'Built Up Areas', 'BUA', 'Census', 'Wales', 'Current'),
('W46', 'Grouped Local Authority Districts (Parishes)', 'GLAD', 'Census', 'Wales', 'Current'),
('W47', 'Grouped Lower Tier Local Authorities 2022', 'GLTLA', 'Census', 'Wales', 'Current'),
('W92', 'Country', 'CTRY', 'Administrative', 'Wales', 'Current');

-- Without this, a pg_dump would silently skip gsscode_types' contents
-- (Postgres assumes extension-owned table data is reconstructible from
-- CREATE EXTENSION alone) and any refresh from update_gsscode_types.py
-- would be lost on the next restore. Same mechanism PostGIS uses for
-- spatial_ref_sys.
SELECT pg_catalog.pg_extension_config_dump('gsscode_types', '');

CREATE FUNCTION description(gsscode)
   RETURNS text
   LANGUAGE sql IMMUTABLE STRICT AS $$
      SELECT name FROM gsscode_types WHERE gss = country($1) || to_char(gss_type($1), 'FM00')
   $$;

CREATE FUNCTION description(text)
   RETURNS text
   LANGUAGE sql IMMUTABLE STRICT AS $$
      SELECT name FROM gsscode_types WHERE gss = upper(left($1, 3))
   $$;

-- Whole-row form of description() -- returns every gsscode_types column
-- (abbreviation, theme, coverage, status, as well as name) in one call
-- instead of one hand-written join per field you want.
CREATE FUNCTION type_info(gsscode)
   RETURNS gsscode_types
   LANGUAGE sql IMMUTABLE STRICT AS $$
      SELECT * FROM gsscode_types WHERE gss = country($1) || to_char(gss_type($1), 'FM00')
   $$;

CREATE FUNCTION type_info(text)
   RETURNS gsscode_types
   LANGUAGE sql IMMUTABLE STRICT AS $$
      SELECT * FROM gsscode_types WHERE gss = upper(left($1, 3))
   $$;

-- Added in 1.1.2: gsscode/text cross-type operators + assignment cast
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
