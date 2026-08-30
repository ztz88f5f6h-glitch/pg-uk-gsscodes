# gsscode_ons_refresh is bundled here rather than given its own build
# directory since it's pure SQL/plpython3u (no C, no MODULE_big entry of
# its own) -- PGXS installs a .control per name listed in EXTENSION.
EXTENSION    = gsscode gsscode_ons_refresh
EXTVERSION   = 1.0.0

MODULE_big   = gsscode
OBJS         = gsscode.o binfmt.o
DATA         = gsscode--1.0.0.sql gsscode_ons_refresh--1.0.0.sql
# gsscode_ons_refresh is deliberately excluded from the regression suite
# -- it does live, non-deterministic network I/O (fetching the current
# ONS release), which is unsafe/inappropriate for pg_regress's exact-text
# comparison. It's covered by manual live verification instead (see
# README).
REGRESS      = parser cmp partial compat nan types
REGRESS_OPTS = --load-extension=gsscode
PG_CPPFLAGS  = -std=c99 -Wall -Wpedantic -DEXTVERSION=$(EXTVERSION) -DTRUE=true -DFALSE=false

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

override CFLAGS := $(filter-out -Wdeclaration-after-statement, $(CFLAGS))
