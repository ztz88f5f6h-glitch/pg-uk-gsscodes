gsscode 1.1
===========
UK ONS/GSS geography code encoded in 32 bits and optimised for indexing
and prefix matches.


Fixed in 1.1.0
--------------
1.0.0 registered `%` under btree strategy 3 (the "equality" slot) to get
an index-assisted plan for prefix matches. That was a correctness bug,
not just an unusual choice: PostgreSQL requires strategy 3's operator to
be a genuine equivalence relation -- reflexive, symmetric, transitive --
for the planner's equivalence-class reasoning (join elimination,
`EquivalenceClass` merging) to stay sound. `%` isn't one: `a % 'SW1'`
and `b % 'SW1'` can both hold with `a <> b`, since many different codes
share a prefix. It never surfaced in 1.0.0's own tests because those
never exercised a plan shape that exploits equivalence-class deduction,
but the planner was entitled to assume a soundness property `%` didn't
actually have -- a self-join or similar plan on a `%`-filtered column
could in principle have produced silently wrong rows, not just a
sequential scan.

1.1.0 drops that opfamily registration entirely. `%`/`!%` are unchanged
otherwise -- still correct, ordinary boolean filters -- but are no
longer index-accelerated on their own. `gsscode_range_lower()`/`gsscode_range_upper()`
are the sound replacement, expressing a prefix as a genuine half-open
range usable with the ordinary (and ordinarily correct) `<`/`>=`
strategies. See "Partial matching" below.

If you're upgrading an existing 1.0.0 install: `ALTER EXTENSION gsscode
UPDATE;` handles it -- verified live, including confirming the unsound
opfamily entry is actually gone from `pg_amop` afterward and that a
fresh install of 1.1.0 (which still chains through the original 1.0.0
script) ends up in the same corrected state.


Format
------
A GSS code is 9 characters: `<country:1><type:2><area:6>`, eg
`E01000001` (an LSOA in England). Validated against the full live
`code_history` table (511,305 real codes, 2026-08): every code currently
in use is a single letter followed by 8 digits.


Coverage
--------
Every field is a raw arithmetic passthrough of the source characters --
there is no lookup table of valid country letters or type codes, and
nothing to keep in sync as ONS adds new ones over time:

  - country: 5 bits, `letter - 'A'` (0-25). 8 letters are in use as of
    2026-08 (E, J, K, L, M, N, S, W); up to 32 are representable.
  - type:    7 bits, the 2-digit type code verbatim (0-99).
  - area:    20 bits, the 6-digit area code verbatim (0-999999).

Because nothing is enumerated, a new country prefix or type code ONS
introduces tomorrow packs and unpacks correctly today, with no extension
changes required.

Composite/cross-border entities (eg K02 "United Kingdom", K03 "Great
Britain", K04 "England and Wales") are ordinary type codes within their
own country prefix, exactly like any other GSS code -- not a derived
union of the constituent countries' codes. There isn't a bitwise
relationship between eg `E`+`W`+`S` and `K03`; ONS encodes composites as
their own distinct type-coded entries.


Parsing
-------
Text input must be exactly 9 characters: one letter (case-insensitive)
followed by 8 digits. No partial/fragmentary input, no separators --
GSS codes are generated and consumed programmatically, not typed in by
hand a character at a time.


Comparison and ordering
------------------------
`gsscode` is stored as an unsigned 32-bit integer, so `<`/`>`/etc. sort
in country, then type, then area order -- the same order as sorting the
original text. Verified against a random 5,000-row sample of real codes:
zero order mismatches between text sort and packed-integer sort.


Partial matching
-----------------
The `%` and `!%` operators match a prefix: a bare country letter ('E'),
a country+type ('E01'), or a full 9-character code. Any other length
never matches -- rather than raising an error, which would make these
operators unsafe to use directly against untrusted/user-supplied input.
An array form matches against several prefixes in one call:

    SELECT * FROM areas WHERE gss % 'E01';                 -- all English LSOAs
    SELECT * FROM areas WHERE gss % ARRAY['E01','E02'];

`%`/`!%` are plain boolean filters, not index-accelerated on their own
-- an earlier version registered `%` in the type's btree operator family
(as the "equality" strategy) specifically to get an index-assisted plan,
but that was a real correctness bug, not just an unusual choice:
PostgreSQL requires that strategy's operator to be a genuine equivalence
relation for the planner's equivalence-class reasoning to stay sound,
and `%` isn't one -- `a % 'SW1'` and `b % 'SW1'` can both hold with
`a <> b`. Fixed in 1.1.0; see the "Fixed in 1.1.0" section below.

For an indexed prefix search, use `gsscode_range_lower()`/`gsscode_range_upper()`
instead -- they express the prefix as a genuine half-open range, using
the ordinary (and ordinarily correct) `<`/`>=` strategies for full,
sound index support:

    SELECT * FROM areas
    WHERE gss >= gsscode_range_lower('E01') AND gss < gsscode_range_upper('E01');
    -- Index Only Scan using areas_gss_idx ...
    --   Index Cond: ((gss >= 'E01000000'::gsscode) AND (gss < 'E02000000'::gsscode))

Unlike `%`/`!%`, `gsscode_range_lower()`/`gsscode_range_upper()` raise an error on an
invalid-length prefix rather than silently returning a value -- they're
meant to be called with a literal, known-good prefix when constructing a
query, not with arbitrary/untrusted input.

Component accessors -- `country(gss)`, `gss_type(gss)`, `area(gss)` --
are also available when you need to filter or group by a field directly
rather than by prefix.


Text-compatibility shims
-------------------------
`~`, `~*`, `!~`, `!~*` and `left(gsscode, n)` are overloaded so that
queries and reports written against the original plain-text column keep
working unmodified once its type changes to `gsscode`:

    WHERE gss ~* '^E03'
    WHERE LEFT(gss, 3) = 'E03'

These render the packed value back to text and run the ordinary text
operator/function -- correct for any pattern, but a btree index on the
`gsscode` column gives them no help; they cost the same as running the
same query against the original text column would have. This is a hard
limit of how PostgreSQL's planner picks index scans (by the operator's
static registration in an opfamily, never by what a function does with a
particular argument at runtime) -- there's no way to make a general
regex operator index-eligible, since most patterns (character classes,
alternation, anything unanchored) aren't reducible to a single mask
comparison the way a literal prefix is.

Two ways to get indexed speed back:

  - Prefer `gsscode_range_lower()`/`gsscode_range_upper()` when the pattern really is
    just an anchored literal prefix: `gss >= gsscode_range_lower('E03') AND
    gss < gsscode_range_upper('E03')` instead of `gss ~* '^E03'`. `%` alone is
    cheaper per-row than a full regex match even without an index (a
    plain integer-mask compare vs. running a compiled pattern), but it
    won't get you an index scan -- see "Partial matching" above for why.
  - For `LEFT(gss, n) = 'literal'` queries specifically, a plain
    PostgreSQL expression index gets full index-scan speed with no
    extension code involved, since `left(gsscode, integer)` is
    `IMMUTABLE`:

        CREATE INDEX ON areas (LEFT(gss, 3));

    Verified live against the real dataset: this produces the same
    `Index Scan` plan and cost as the `gsscode_range_lower()`/`gsscode_range_upper()`
    form.


Rendering
---------
Output is always the canonical 9-character upper-case form, eg
`E01000001`. `gsscode::text` works without an explicit cast declaration
(PostgreSQL derives it automatically from the type's I/O functions).


Validity and reserved/NaN codes
--------------------------------
`is_valid(text)` checks whether a string parses as a gsscode without
actually raising -- useful for filtering untrusted input before casting.

ONS reserves area=999999 within every type as a "no code assigned"
placeholder -- eg `E00999999`, `E01999999`, `K99999999` -- confirmed
against the live Register of Geographic Codes' own "Reserved code (for
CHD use)" column, which follows this pattern for all 206 current entity
types with no exception. These parse and store as perfectly ordinary,
fully-comparable gsscode values (nothing about `=`/`<`/`>` treats them
specially) -- `isnan(gsscode)` is how you detect and filter them
explicitly, the same role `isnan()` plays for `float8`.


Type names and descriptions
-----------------------------
`description(gsscode)` and `description(text)` look up what a 3-character
country+type prefix actually means, eg `description('E01')` ->
`'Lower layer Super Output Areas'`. Both overloads truncate to the first
3 characters, so a full 9-character code works too.

`type_info(gsscode)` and `type_info(text)` return the whole
`gsscode_types` row instead of just `name` -- `abbreviation`, `theme`,
`coverage` and `status` as well -- for when you want more than one field
without hand-writing the join yourself:

    SELECT (type_info('E01000001'::gsscode)).*;
    --  gss | name                            | abbreviation | theme                       | coverage | status
    -- -----+---------------------------------+--------------+------------------------------+----------+---------
    --  E01 | Lower layer Super Output Areas  | LSOA         | Statistical Building Block  | England  | Current

The data comes from a private `gsscode_types` table shipped with the
extension (206 rows: gss, name, abbreviation, theme, coverage, status),
seeded from the ONS Register of Geographic Codes -- a small, stable type
registry that's safe to ship as part of the extension itself. It does
NOT hold individual area names (eg what `E01000001` itself is called, as
opposed to what "E01" as a type means) -- that's a much larger,
per-installation dataset (500,000+ rows, changing as boundaries are
redrawn) that stays external rather than being baked into a general-
purpose extension.

The individual-code names live in ONS's Code History Database (CHD), not
the Register of Geographic Codes this extension ships:

  - [Code History Database (CHD)](https://www.ons.gov.uk/methodology/geography/geographicalproducts/namescodesandlookups/codehistorydatabasechd)
    -- ONS's own overview/methodology page for the CHD.
  - [Open Geography Portal](https://geoportal.statistics.gov.uk) -- where
    the actual CHD download (CSV or MS Access) is hosted, alongside the
    RGC and everything else ONS publishes geographically. Search for
    "Code History Database" to find the current dated release.
  - [Names, codes and lookups](https://www.ons.gov.uk/methodology/geography/geographicalproducts/namescodesandlookups)
    -- ONS's top-level index of everything in this space, including
    theme-specific names-and-codes listings (eg [administrative
    geographies](https://www.ons.gov.uk/methodology/geography/geographicalproducts/namescodesandlookups/namesandcodeslistings/namesandcodesforadministrativegeography))
    if you only need one geography type rather than the full CHD.

If you have your own copy loaded into a table, wiring up individual-code
names is a one-line function:

    CREATE FUNCTION name(gsscode) RETURNS text LANGUAGE sql STABLE AS $$
       SELECT name FROM your_code_history_table WHERE gss = $1::text
    $$;

`gsscode_types` survives `pg_dump`/restore even after a refresh (see
below) -- it's registered via `pg_extension_config_dump()`, the same
mechanism PostGIS uses for `spatial_ref_sys`, so restoring doesn't
silently revert it to the shipped snapshot.


Refreshing gsscode_types from ONS
-----------------------------------
ONS republishes the Register of Geographic Codes periodically under a
new dated release (eg "(June 2025)" then "(June 2026)", each a different
underlying file). Two ways to refresh:

**`update_gsscode_types.py`** (recommended default) -- an external
script, stdlib + `psycopg2` only, no extra Postgres privileges needed
anywhere:

    python3 update_gsscode_types.py --dsn "host=... port=... dbname=... user=..."

It finds the current release by querying ArcGIS's search API for the
item tagged `PRD_RGC` and category `/Categories/LATEST`, rather than a
hardcoded item id or date, so it keeps working as ONS publishes new
releases. Verified live: correctly found the "(June 2026)" release
ahead of the "(June 2025)" one used to seed this table, parsed all 206
rows, and upserted them.

**`gsscode_ons_refresh` extension** (optional) -- a separate extension
(`requires = 'gsscode, http'`) adding one function,
`update_gsscode_types()`, that refreshes the table via a single
`SELECT`. It's deliberately a separate extension, not bundled into
`gsscode` itself: most installations should never need to enable
anything extra just to get the packed type and its operators.

The real obstacle to doing this in-database at all is that ONS only
publishes the RGC as a ZIP (confirmed -- no bare-CSV endpoint, no
queryable feature-service), and PostgreSQL has no trusted, built-in way
to decompress one -- an HTTP-only path can fetch the file but can't
finish the job on its own. Rather than reaching for an untrusted
language (`plpython3u`) to do that decompression inside the database,
the decompression happens outside it entirely: this repo's own GitHub
Actions workflow (`.github/workflows/refresh-gsscode-types.yml`) fetches
and unzips the current ONS release on a schedule, the same way
`update_gsscode_types.py` does, and commits the parsed result as
`data/gsscode_types.json`. `update_gsscode_types()` then only ever needs
to do a plain HTTP GET of that file plus `jsonb_populate_recordset()` --
both fully within PostgreSQL's trusted core. The whole function is
`plpgsql` (a trusted language); the only non-default piece is `http`
itself, which -- unlike `plpython3u` -- can only make HTTP requests,
nothing more.

Two things worth knowing before reaching for this:

  - `http` still needs superuser to enable, same as any non-default
    extension, and is unavailable on some managed Postgres services --
    just a much narrower thing to grant than a general-purpose scripting
    language.
  - This shifts part of what you're trusting: instead of only ONS, you're
    also trusting this repo's GitHub Actions pipeline and whoever has
    write access to it. For most uses that's a reasonable trade, but it's
    a real, new dependency, not just a strict improvement -- name it if
    you're evaluating this for something that matters.
  - The Postgres server process itself needs outbound internet access to
    raw.githubusercontent.com. Many production database hosts
    deliberately firewall that off, in which case this will simply time
    out -- the external script has no such requirement since it can run
    from wherever you have egress.

Verified live: truncated `gsscode_types` to 0 rows, called
`SELECT update_gsscode_types();`, got `206` back via a real HTTP fetch
of the live file on GitHub and a real `jsonb_populate_recordset()`
upsert -- no `plpython3u`, no untrusted language, anywhere in the path.
