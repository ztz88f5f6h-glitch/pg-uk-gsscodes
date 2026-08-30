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
