## Process this file with automake to produce Makefile.in

#AUTOMAKE_OPTIONS        = foreign

# where we keep local rules for automake
#ACLOCAL_M4 = $(top_srcdir)/config/aclocal.m4
#AUTOHEADER = @AUTOHEADER@ --localdir=$(top_srcdir)/config

ZLIB_LIB_DIR = @ZLIB_LIB_DIR@

INCLUDES = -I$(top_srcdir)/$(ZLIB_LIB_DIR)

EXTRA_DIST= ANNOUNCE CHANGES INSTALL KNOWNBUG README README.rrdtool TODO Y2KINFO example.c libpng.3\
		libpng.txt libpngpf.3 png.5 png.dsp png.dsw 

noinst_LTLIBRARIES = librrd_png.la

librrd_png_la_SOURCES =	\
	png.c		\
	pngerror.c	\
	pngget.c	\
	pngmem.c	\
	pngpread.c	\
	pngread.c	\
	pngrio.c	\
	pngrtran.c	\
	pngrutil.c	\
	pngset.c	\
	pngtrans.c	\
	pngwio.c	\
	pngwrite.c	\
	pngwtran.c	\
	pngwutil.c	\
	png.h      pngconf.h
