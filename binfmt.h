#ifndef GSSCODE_BINFMT_H__
#define GSSCODE_BINFMT_H__

#include <stdint.h>
#include <stdbool.h>

typedef uint32_t gsscode;

const char * gsscode_version (void);

__attribute__((nonnull (1)))
__attribute__((warn_unused_result))
gsscode gsscode_parse (const char *str);

__attribute__((nonnull (2)))
// buf must be at least 10 bytes: 9 visible characters (e.g. "E01000001")
// plus a null terminator.
int gsscode_render (gsscode g, char buf[10]);

__attribute__((warn_unused_result))
bool gsscode_binchk (gsscode g);

// Parses a partial/prefix GSS code for the % and !% operators: a bare
// country letter ("E"), a country+type ("E01"), or a full 9-character
// code ("E01000001") -- any other length is rejected. On success, *out
// holds the parsed value (unset trailing fields zeroed) and *mask_bits
// holds how many leading (most-significant) bits of the packed value are
// significant for the comparison: 5, 12, or 32.
__attribute__((nonnull (1,2,3)))
__attribute__((warn_unused_result))
bool gsscode_parse_prefix (const char *str, gsscode *out, unsigned *mask_bits);

#endif
