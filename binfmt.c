#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "binfmt.h"
#include "gsscode.h"

#define IS_AZ(c) (c >= 'A' && c <= 'Z')
#define IS_09(c) (c >= '0' && c <= '9')


const char * gsscode_version() { return STR(EXTVERSION); }


gsscode gsscode_parse (const char *str) {
   gsscode res = 0;
   if (! str) return 0;

   // exactly 9 characters: 1 letter + 8 digits, no separators, no
   // truncation/partial-match support (unlike postcode -- GSS codes
   // aren't typed by hand character-by-character the way postcodes are)
   char c = str[0];
   if (c >= 'a' && c <= 'z') c -= 32; // tr/[a-z]/[A-Z]/
   if (! IS_AZ(c)) return 0;

   unsigned type = 0, area = 0;
   for (int i = 1; i <= 2; i++) {
      if (! IS_09(str[i])) return 0;
      type = type*10 + (str[i] - '0');
   }
   for (int i = 3; i <= 8; i++) {
      if (! IS_09(str[i])) return 0;
      area = area*10 + (str[i] - '0');
   }
   if (str[9] != '\0') return 0; // trailing garbage

   SET_COUNTRY(res, c - 'A');
   SET_TYPE(res, type);
   SET_AREA(res, area);

   return res;
}


int gsscode_render (gsscode g, char buf[10]) {
   if (! gsscode_binchk(g)) return 0;

   char *b = buf;
   *(b++) = 'A' + GET_COUNTRY(g);
   b += snprintf(b, 3, "%02u", GET_TYPE(g));
   b += snprintf(b, 7, "%06u", GET_AREA(g));

   return b - buf; // number of chars written
}


bool gsscode_binchk (gsscode g) {
   if (GET_COUNTRY(g) > 25)   return false; // must map to A-Z
   if (GET_TYPE(g) > 99)      return false; // 2-digit field
   if (GET_AREA(g) > 999999)  return false; // 6-digit field

   return true;
}


bool gsscode_parse_prefix (const char *str, gsscode *out, unsigned *mask_bits) {
   size_t len = strlen(str);

   char c = str[0];
   if (c >= 'a' && c <= 'z') c -= 32; // tr/[a-z]/[A-Z]/
   if (! IS_AZ(c)) return false;

   gsscode res = 0;
   SET_COUNTRY(res, c - 'A');

   if (len == 1) { *out = res; *mask_bits = 5; return true; }
   if (len < 3)  return false;

   unsigned type = 0;
   for (int i = 1; i <= 2; i++) {
      if (! IS_09(str[i])) return false;
      type = type*10 + (str[i] - '0');
   }
   SET_TYPE(res, type);

   if (len == 3) { *out = res; *mask_bits = 12; return true; }
   if (len != 9) return false;

   unsigned area = 0;
   for (int i = 3; i <= 8; i++) {
      if (! IS_09(str[i])) return false;
      area = area*10 + (str[i] - '0');
   }
   SET_AREA(res, area);

   *out = res;
   *mask_bits = 32;
   return true;
}
