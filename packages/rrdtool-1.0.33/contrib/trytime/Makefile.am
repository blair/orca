## Process this file with automake to produce Makefile.in
INCLUDES = -I../../src -I../../gd1.3
EXTRA_DIST = trytime.c
contribdir = $(prefix)/contrib/trytime
contrib_DATA = README trytime.c
bin_PROGRAMS    = trytime
trytime_SOURCES  = trytime.c
trytime_LDADD    = ../../src/librrd.la
