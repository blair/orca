
EXTRA_DIST = README ifOctets.tcl tclrrd.c
CLEANFILES = tclrrd.o tclrrd.so

VERSION = @VERSION@

CFLAGS = @CFLAGS@ -I$(top_srcdir)/src
TCL_PREFIX = @TCL_PREFIX@
TCL_SHLIB_LD = @TCL_SHLIB_LD@
TCL_SHLIB_CFLAGS = @TCL_SHLIB_CFLAGS@
TCL_SHLIB_SUFFIX = @TCL_SHLIB_SUFFIX@
TCL_PACKAGE_PATH = $(DESTDIR)@TCL_PACKAGE_PATH@
TCL_LIB_FILE = tclrrd.$(VERSION)$(TCL_SHLIB_SUFFIX)
TCL_LD_SEARCH_FLAGS = @TCL_LD_SEARCH_FLAGS@
GD_LIB_DIR       = $(top_srcdir)/@GD_LIB_DIR@

SRC_DIR            = $(top_srcdir)/src
AM_CPPFLAGS        = -I$(TCL_PREFIX)/include -I$(SRC_DIR)  -I$(GD_LIB_DIR)
LIBDIRS            = -L$(libdir) -L$(SRC_DIR)  -L../src/.libs
LIB_RUNTIME_DIR    = $(libdir)

if COMP_TCL

$(TCL_LIB_FILE): tclrrd.o
	$(TCL_SHLIB_LD) $(LIBDIRS) $< -o $@ @RRD_PRIVATE_LINK@ -lm $(TCL_LIB_SPEC)

tclrrd.o: tclrrd.c
	$(CC) $(CFLAGS) $(TCL_SHLIB_CFLAGS) $(INCLUDES) $(AM_CPPFLAGS) -c $< -DVERSION=\"$(VERSION)\"

all-local: $(TCL_LIB_FILE)

tcl-install: $(TCL_LIB_FILE)
	cp $(TCL_LIB_FILE) $(TCL_PACKAGE_PATH)/$(TCL_LIB_FILE)
	if [ ! -d $(TCL_PACKAGE_PATH)/tclrrd.$(VERSION) ] ; then \
		mkdir $(TCL_PACKAGE_PATH)/tclrrd.$(VERSION) ; \
	fi
	echo "package ifneeded Rrd $(VERSION) [list load [file join \$$dir .. $(TCL_LIB_FILE)]]" > $(TCL_PACKAGE_PATH)/tclrrd.$(VERSION)/pkgIndex.tcl

else

all-local:

endif

diff:
	cd .. ; diff -c -u -r -N --exclude Makefile --exclude html --exclude doc --exclude Makefile.in --exclude Makefile.old --exclude perl --exclude aclocal.m4 --exclude configure rrdtool-1.0.13 rrdtool-1.0.13-ibr > rrdtool-1.0.13-ibr.patch
	

