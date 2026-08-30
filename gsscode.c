#include <postgres.h>
#include <varatt.h>
#include <utils/builtins.h>
#include <libpq/pqformat.h>

#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC;
#endif

#include "gsscode.h"
#include "binfmt.h"

#define PG_RETURN_GSSCODE(g) return UInt32GetDatum(g)
#define PG_GETARG_GSSCODE(n) DatumGetUInt32(PG_GETARG_DATUM(n))

Datum gsscode_in         (PG_FUNCTION_ARGS);
Datum gsscode_out        (PG_FUNCTION_ARGS);
Datum gsscode_recv       (PG_FUNCTION_ARGS);
Datum gsscode_send       (PG_FUNCTION_ARGS);
Datum gsscode_validate   (PG_FUNCTION_ARGS);
Datum gsscode_cmp        (PG_FUNCTION_ARGS);
Datum gsscode_eq         (PG_FUNCTION_ARGS);
Datum gsscode_ne         (PG_FUNCTION_ARGS);
Datum gsscode_lt         (PG_FUNCTION_ARGS);
Datum gsscode_gt         (PG_FUNCTION_ARGS);
Datum gsscode_lte        (PG_FUNCTION_ARGS);
Datum gsscode_gte        (PG_FUNCTION_ARGS);
Datum gsscode_country    (PG_FUNCTION_ARGS);
Datum gsscode_type       (PG_FUNCTION_ARGS);
Datum gsscode_area       (PG_FUNCTION_ARGS);
Datum gsscode_isnan      (PG_FUNCTION_ARGS);
Datum gsscode_cmp_partial (PG_FUNCTION_ARGS);
Datum gsscode_eq_partial  (PG_FUNCTION_ARGS);
Datum gsscode_ne_partial  (PG_FUNCTION_ARGS);
Datum gsscode_range_lower (PG_FUNCTION_ARGS);
Datum gsscode_range_upper (PG_FUNCTION_ARGS);

// prefix_mask(5)  -> top 5 bits  (country only)
// prefix_mask(12) -> top 12 bits (country+type)
// prefix_mask(32) -> all bits    (full code)
static inline uint32_t prefix_mask (unsigned bits) {
   return bits == 0 ? 0 : (uint32_t) (0xFFFFFFFFu << (32 - bits));
}


PG_FUNCTION_INFO_V1(gsscode_in);

Datum gsscode_in (PG_FUNCTION_ARGS) {
   gsscode g = gsscode_parse(PG_GETARG_CSTRING(0));

   if (g == 0)
      ereport(ERROR, (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
                      errmsg (_("cannot parse input for type gsscode")),
                      errhint(_("expected 9 characters: 1 letter followed by 8 digits, eg \"E01000001\""))));

   PG_RETURN_GSSCODE(g);
}


PG_FUNCTION_INFO_V1(gsscode_out);

Datum gsscode_out (PG_FUNCTION_ARGS) {
   char *str = palloc(10);

   if (gsscode_render(PG_GETARG_GSSCODE(0), str) == 0)
      ereport(ERROR, (errcode(ERRCODE_DATA_CORRUPTED),
                      errmsg (_("cannot render corrupted binary data to text"))));

   PG_RETURN_CSTRING(str);
}


PG_FUNCTION_INFO_V1(gsscode_recv);

Datum gsscode_recv (PG_FUNCTION_ARGS) {
   gsscode g = pq_getmsgint((StringInfo) PG_GETARG_POINTER(0), sizeof(gsscode));

   if (! gsscode_binchk(g))
      ereport(ERROR, (errcode(ERRCODE_INVALID_BINARY_REPRESENTATION),
                      errmsg (_("received binary data is invalid for type gsscode")),
                      errhint(_("server binary format version is %s"), STR(EXTVERSION))));

   PG_RETURN_GSSCODE(g);
}


PG_FUNCTION_INFO_V1(gsscode_send);

Datum gsscode_send (PG_FUNCTION_ARGS) {
   StringInfoData b;
   pq_begintypsend(&b);
   pq_sendint(&b, PG_GETARG_GSSCODE(0), sizeof(gsscode));
   PG_RETURN_BYTEA_P(pq_endtypsend(&b));
}


PG_FUNCTION_INFO_V1(gsscode_validate);

Datum gsscode_validate (PG_FUNCTION_ARGS) {
   gsscode g = gsscode_parse(text_to_cstring(PG_GETARG_TEXT_P(0)));
   PG_RETURN_BOOL(g ? TRUE : FALSE);
}


PG_FUNCTION_INFO_V1(gsscode_cmp);

Datum gsscode_cmp (PG_FUNCTION_ARGS) {
   gsscode a = PG_GETARG_GSSCODE(0),
           b = PG_GETARG_GSSCODE(1);

   if (a == b) PG_RETURN_INT32( 0);
   if (a >  b) PG_RETURN_INT32( 1);
   else        PG_RETURN_INT32(-1);
}


PG_FUNCTION_INFO_V1(gsscode_eq);

Datum gsscode_eq (PG_FUNCTION_ARGS) {
   PG_RETURN_BOOL(PG_GETARG_GSSCODE(0) == PG_GETARG_GSSCODE(1));
}


PG_FUNCTION_INFO_V1(gsscode_ne);

Datum gsscode_ne (PG_FUNCTION_ARGS) {
   PG_RETURN_BOOL(PG_GETARG_GSSCODE(0) != PG_GETARG_GSSCODE(1));
}


PG_FUNCTION_INFO_V1(gsscode_lt);

Datum gsscode_lt (PG_FUNCTION_ARGS) {
   PG_RETURN_BOOL(PG_GETARG_GSSCODE(0) < PG_GETARG_GSSCODE(1));
}


PG_FUNCTION_INFO_V1(gsscode_gt);

Datum gsscode_gt (PG_FUNCTION_ARGS) {
   PG_RETURN_BOOL(PG_GETARG_GSSCODE(0) > PG_GETARG_GSSCODE(1));
}


PG_FUNCTION_INFO_V1(gsscode_lte);

Datum gsscode_lte (PG_FUNCTION_ARGS) {
   PG_RETURN_BOOL(PG_GETARG_GSSCODE(0) <= PG_GETARG_GSSCODE(1));
}


PG_FUNCTION_INFO_V1(gsscode_gte);

Datum gsscode_gte (PG_FUNCTION_ARGS) {
   PG_RETURN_BOOL(PG_GETARG_GSSCODE(0) >= PG_GETARG_GSSCODE(1));
}


// Partial/prefix matching -- eg 'E01' matches any gsscode whose country
// and type are E/01, regardless of area. Invalid or wrongly-sized
// prefixes never match anything rather than erroring, so these are safe
// to use in a WHERE clause driven by untrusted/user-supplied input.
//
// % and !% are plain boolean filters ONLY -- they are deliberately NOT
// registered as a btree operator family strategy. An earlier version of
// this extension registered % under strategy 3 (the "equality" slot) to
// get index-assisted prefix matching, but PostgreSQL requires strategy
// 3's operator to be a genuine equivalence relation for the planner's
// equivalence-class reasoning (join elimination, EquivalenceClass
// merging) to stay sound -- see
// https://www.postgresql.org/docs/current/xindex.html and the "Behavior
// of B-Tree Operator Classes" section of the btree docs. % isn't one:
// `a % 'SW1'` and `b % 'SW1'` can both hold with a <> b, since many
// different codes share a prefix. Registering it as strategy 3 anyway
// let the planner assume "both equal to the same prefix" implies "equal
// to each other", which is false in general -- a correctness bug, not
// just a missed optimization, even though it produced correct results
// in the simple cases this was tested against. range_lower()/
// range_upper() below are the sound replacement: they return real
// gsscode bounds, usable with the ordinary (and ordinarily correct) </>=
// strategies for full index support with no opfamily trickery.
//
// gsscode_cmp_partial itself is kept below, unused by anything in this
// (1.1.0) version's own SQL, purely because gsscode--1.0.0.sql still
// references it -- a fresh install chains through that script on its
// way to 1.1.0, and dropping the C symbol would break installing (or
// even just upgrading from) version 1.0.0. It can be removed only once
// 1.0.0 is no longer a supported install target.

PG_FUNCTION_INFO_V1(gsscode_cmp_partial);

Datum gsscode_cmp_partial (PG_FUNCTION_ARGS) {
   gsscode a = PG_GETARG_GSSCODE(0);
   char *str = text_to_cstring(PG_GETARG_TEXT_P(1));
   gsscode b; unsigned bits;
   bool ok = gsscode_parse_prefix(str, &b, &bits);
   pfree(str);

   if (! ok) PG_RETURN_INT32(-1); // invalid prefix fragment

   uint32_t mask = prefix_mask(bits), am = a & mask, bm = b & mask;
   if (am == bm) PG_RETURN_INT32( 0);
   if (am >  bm) PG_RETURN_INT32( 1);
   else          PG_RETURN_INT32(-1);
}


PG_FUNCTION_INFO_V1(gsscode_eq_partial);

Datum gsscode_eq_partial (PG_FUNCTION_ARGS) {
   gsscode a = PG_GETARG_GSSCODE(0);
   char *str = text_to_cstring(PG_GETARG_TEXT_P(1));
   gsscode b; unsigned bits;
   bool ok = gsscode_parse_prefix(str, &b, &bits);
   pfree(str);

   if (! ok) PG_RETURN_BOOL(false); // invalid prefix fragment

   uint32_t mask = prefix_mask(bits);
   PG_RETURN_BOOL((a & mask) == (b & mask));
}


PG_FUNCTION_INFO_V1(gsscode_ne_partial);

Datum gsscode_ne_partial (PG_FUNCTION_ARGS) {
   gsscode a = PG_GETARG_GSSCODE(0);
   char *str = text_to_cstring(PG_GETARG_TEXT_P(1));
   gsscode b; unsigned bits;
   bool ok = gsscode_parse_prefix(str, &b, &bits);
   pfree(str);

   if (! ok) PG_RETURN_BOOL(true); // invalid prefix fragment

   uint32_t mask = prefix_mask(bits);
   PG_RETURN_BOOL((a & mask) != (b & mask));
}


// range_lower()/range_upper() -- the sound, index-friendly replacement
// for indexed prefix matching (see the long comment above % / !%).
// Together they express "matches prefix" as the genuinely correct
// half-open range [range_lower(p), range_upper(p)):
//
//    WHERE code >= range_lower('E01') AND code < range_upper('E01')
//
// range_lower() is just the prefix's value with every unspecified
// trailing field zeroed -- gsscode_parse_prefix() already returns
// exactly that. range_upper() is the smallest value strictly greater
// than every value matching the prefix: add one at the bit position
// immediately above the masked region. Both raise an error for a
// malformed prefix rather than silently returning a value, unlike %/!%
// -- these are meant to be called with a literal, known-good prefix
// when constructing a query, not with arbitrary/untrusted input the way
// %/!% are designed to tolerate.
//
// Overflow note: range_upper()'s addition could in principle wrap a
// uint32_t if the masked field were already at its maximum representable
// bit pattern, but no value gsscode_parse_prefix() can actually produce
// reaches that: country tops out at 25 ('Z') against a 5-bit field
// (max 31), and type tops out at 99 against a 7-bit field (max 127) --
// there's headroom in both, so no prefix reachable via real parsed text
// can trigger it.

PG_FUNCTION_INFO_V1(gsscode_range_lower);

Datum gsscode_range_lower (PG_FUNCTION_ARGS) {
   char *str = text_to_cstring(PG_GETARG_TEXT_P(0));
   gsscode val; unsigned bits;
   bool ok = gsscode_parse_prefix(str, &val, &bits);
   pfree(str);

   if (! ok)
      ereport(ERROR, (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
                      errmsg (_("invalid gsscode prefix")),
                      errhint(_("expected a country letter, a country+type (eg \"E01\"), or a full 9-character code"))));

   PG_RETURN_GSSCODE(val);
}


PG_FUNCTION_INFO_V1(gsscode_range_upper);

Datum gsscode_range_upper (PG_FUNCTION_ARGS) {
   char *str = text_to_cstring(PG_GETARG_TEXT_P(0));
   gsscode val; unsigned bits;
   bool ok = gsscode_parse_prefix(str, &val, &bits);
   pfree(str);

   if (! ok)
      ereport(ERROR, (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
                      errmsg (_("invalid gsscode prefix")),
                      errhint(_("expected a country letter, a country+type (eg \"E01\"), or a full 9-character code"))));

   PG_RETURN_GSSCODE(val + (1u << (32 - bits)));
}


// Convenience accessors -- letting callers filter/group by country or
// type without unpacking the code back to text first.

PG_FUNCTION_INFO_V1(gsscode_country);

Datum gsscode_country (PG_FUNCTION_ARGS) {
   gsscode g = PG_GETARG_GSSCODE(0);
   char buf[2] = { (char) ('A' + GET_COUNTRY(g)), '\0' };
   PG_RETURN_TEXT_P(cstring_to_text(buf));
}


PG_FUNCTION_INFO_V1(gsscode_type);

Datum gsscode_type (PG_FUNCTION_ARGS) {
   PG_RETURN_INT32(GET_TYPE(PG_GETARG_GSSCODE(0)));
}


PG_FUNCTION_INFO_V1(gsscode_area);

Datum gsscode_area (PG_FUNCTION_ARGS) {
   PG_RETURN_INT32(GET_AREA(PG_GETARG_GSSCODE(0)));
}


// ONS reserves area=999999 within every type as a placeholder/"no code
// assigned" marker for CHD use -- eg E00999999, E01999999, E02999999 --
// confirmed against the live Register of Geographic Codes "Reserved code
// (for CHD use)" column, which follows this pattern for all 206 current
// entity types with no exception. It is NOT tied to any specific type
// value (eg type 99) -- area=999999 alone is what marks it.
PG_FUNCTION_INFO_V1(gsscode_isnan);

Datum gsscode_isnan (PG_FUNCTION_ARGS) {
   PG_RETURN_BOOL(GET_AREA(PG_GETARG_GSSCODE(0)) == 999999);
}
