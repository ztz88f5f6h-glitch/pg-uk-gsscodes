#ifndef GSSCODE_H__
#define GSSCODE_H__

#include <stdbool.h>

// Up to PG13, postgres.h transitively defined the uppercase TRUE/FALSE
// macros this file uses; PG14 removed them in favour of plain C99 bool.
// The Makefile also defines these via -DTRUE=true -DFALSE=false, but
// that only helps for builds that go through this exact Makefile --
// guarding it here too means the source still builds correctly under a
// different build wrapper (e.g. pgxn install) that doesn't pass those
// flags.
#ifndef TRUE
#define TRUE true
#endif
#ifndef FALSE
#define FALSE false
#endif

#define STR(macro) QUOTE(macro)
#define QUOTE(name) #name

#ifndef EXTVERSION
#error  EXTVERSION is not defined
#endif

#define GET_BITS(var,pos,len)     ((var) >> (pos) & ((1u<<(len))-1))
#define SET_BITS(var,pos,len,set) ((var) = ((var) &~ (((1u<<(len))-1)<<pos)) | ((set)<<(pos)))

// A GSS code is 9 characters: <country:1><type:2><area:6>, eg "E01000001".
// Every field here is a straight arithmetic passthrough of the source
// digits/letter -- there is no lookup table and nothing to keep in sync
// as ONS adds new country prefixes or type codes. That is deliberate:
// ONS adds new type codes (and occasionally new country-prefix letters,
// eg the existing E/W/S/N/J/K/L/M) on an ongoing basis, so the packed
// format must never hardcode the *set* of valid values, only the *width*
// of each field.
//
//   country: bits 27-31 (5 bits) -- letter 'A'-'Z' stored as (letter-'A'),
//            0-25. 5 bits gives room for 32 possible prefix letters;
//            only 8 (E,J,K,L,M,N,S,W) are in use as of 2026-08.
//   type:    bits 20-26 (7 bits) -- the 2-digit type code, 0-99 verbatim.
//   area:    bits  0-19 (20 bits) -- the 6-digit area code, 0-999999
//            verbatim (20 bits holds up to 1,048,575).
//
// Total 32 bits, using the full uint32_t. Because `gsscode` is unsigned
// (see binfmt.h) ordinary C `<`/`>` on the packed value already gives the
// correct natural sort order (country, then type, then area) -- there is
// no int4 sign-bit concern the way there would be if this were a signed
// type, since the comparison never goes through a signed representation.
#define GET_COUNTRY(g)     GET_BITS(g, 27, 5)
#define GET_TYPE(g)        GET_BITS(g, 20, 7)
#define GET_AREA(g)        GET_BITS(g,  0, 20)

#define SET_COUNTRY(g,v)   SET_BITS(g, 27, 5, v)
#define SET_TYPE(g,v)      SET_BITS(g, 20, 7, v)
#define SET_AREA(g,v)      SET_BITS(g,  0, 20, v)

#endif
