## Process this file with automake to produce Makefile.in
RSYNC = rsync --rsh=ssh

# build the following subdirectories
SUBDIRS = cgilib-0.4 config gd1.3 zlib-1.1.4 libpng-1.0.9 \
          src doc examples contrib tcl

# the following files are not mentioned in any other Makefile
EXTRA_DIST = COPYRIGHT CHANGES NT-BUILD-TIPS.txt TODO CONTRIBUTORS rrdtool.spec \
 perl-piped/MANIFEST perl-piped/README perl-piped/rrdpl.ds? \
 perl-piped/RRDp.pm perl-piped/Makefile.PL.in  perl-piped/t/base.t \
 perl-shared/MANIFEST perl-shared/README perl-shared/RRDs.xs \
 perl-shared/ntmake.pl perl-shared/Makefile.PL.in perl-shared/t/base.t \
 perl-shared/rrdpl.ds? perl-shared/RRDs.pm rrdtool.spec

CLEANFILES = config.cache

# lets schedule the perl stuff for installation
# the special call to install-sh is because the -d switch is not portable
# mac os X has its perl module in bundles so it seems
install-data-local:
	$(top_srcdir)/config/mkinstalldirs $(DESTDIR)$(prefix)/lib/perl/auto/RRDs
	$(INSTALL) -m 644 perl-piped/RRDp.pm $(DESTDIR)$(prefix)/lib/perl
	$(INSTALL) -m 644 perl-shared/RRDs.pm $(DESTDIR)$(prefix)/lib/perl
	$(INSTALL) -m 644 perl-shared/blib/arch/auto/RRDs/RRDs.bs $(DESTDIR)$(prefix)/lib/perl/auto/RRDs
	test -f perl-shared/blib/arch/auto/RRDs/RRDs.@SO_EXT@  && $(INSTALL) -m 755 perl-shared/blib/arch/auto/RRDs/RRDs.@SO_EXT@ $(DESTDIR)$(prefix)/lib/perl/auto/RRDs || true
	test -f perl-shared/blib/arch/auto/RRDs/RRDs.bundle  && $(INSTALL) -m 755 perl-shared/blib/arch/auto/RRDs/RRDs.bundle $(DESTDIR)$(prefix)/lib/perl/auto/RRDs || true


# use relaxed rules when building dists
AUTOMAKE_OPTIONS= foreign no-dependencies

# where we keep local rules for automake
ACLOCAL_M4= 	$(top_srcdir)/config/aclocal.m4
AUTOHEADER = @AUTOHEADER@ --localdir=$(top_srcdir)/config
AUTOCONF = @AUTOCONF@ --localdir=$(top_srcdir)/config

# rules for building the perl module

# This "CLONE" stuff is probably not as clean as it should be.
# But it is only used when the source and build trees are mutually separate.
PERL_CLONE = mkdir \$${P_DIR} \
		&& cd \$${P_DIR} \
		&& for _perlfile_ in \$${P_FILES} \
		   ; do \
			ln -s ../$(top_srcdir)/\$${P_DIR}/\$${_perlfile_} . \
		   ; done

perl_piped:: $(top_builddir)/perl-piped
	test -d perl-piped \
	  || sh -c "P_DIR='perl-piped'; P_FILES='Makefile.PL RRDp.pm' ; $(PERL_CLONE)"

perl_piped:: perl-piped/Makefile
	cd perl-piped && $(MAKE)

perl-piped/Makefile: perl-piped/Makefile.PL
	cd perl-piped && $(PERL) Makefile.PL $(PERL_MAKE_OPTIONS)


perl_shared:: $(top_builddir)/perl-shared
	test -d perl-shared \
	  || sh -c "P_DIR='perl-shared'; P_FILES='Makefile.PL RRDs.pm RRDs.xs' ; $(PERL_CLONE)"

perl_shared:: perl-shared/Makefile
	cd perl-shared && $(MAKE)

perl-shared/Makefile: perl-shared/Makefile.PL
	cd perl-shared && $(PERL) Makefile.PL $(PERLFLAGS) $(PERL_MAKE_OPTIONS)

# add the following to the all target
all-local:	@COMP_PERL@

to-docs: to-versync
	(cd doc && $(MAKE) clean && $(MAKE) && $(MAKE) pdf)
	(cd website && wmk-1.7.4 -f manual tutorial contributors.wml && ./site-sync )

to-versync: 
	perl -i -p -e '"$(VERSION)" =~ /(\d+)\.(\d+)\.(\d+)/; $$v=sprintf("%1d.%02d0%02d1" ,$${1},$${2},$${3}); s|VERSION\s*=\s*[\d.]+|VERSION = $$v|' perl-*/RRD?.pm
	perl -i -p -e 's|RRDtool\s+\d+\.\d+\.\d+ |RRDtool $(VERSION) |' src/*.[ch]
	perl -i -p -e 's|Version:.+|Version:\t$(VERSION)|' rrdtool.spec

to-dist: to-docs dist
	mv $(PACKAGE)-$(VERSION).tar.gz archive
	
to-scp: to-dist
	cp CHANGES  archive/$(PACKAGE)-$(VERSION).tar.gz /home/oetiker/public_html/webtools/rrdtool/pub/
	(cd /home/oetiker/public_html/webtools/rrdtool/pub; rm $(PACKAGE).tar.gz; ln -s $(PACKAGE)-$(VERSION).tar.gz $(PACKAGE).tar.gz;gmd5sum $(PACKAGE)-$(VERSION).tar.gz >$(PACKAGE)-$(VERSION).tar.gz.md5; pgps  $(PACKAGE)-$(VERSION).tar.gz.md5)

#	$(RSYNC) CHANGES archive/$(PACKAGE)-$(VERSION).tar.gz tobi@ipn.caida.org:/ipn/web/Tools/RRDtool/pub/

site-perl-inst: site-perl-install

site-perl-install: all perl-piped/Makefile perl-shared/Makefile
	cd perl-piped && $(MAKE) install
	cd perl-shared && $(MAKE) install

site-tcl-install: all
	cd tcl && $(MAKE) tcl-install

clean-local:
	cd perl-piped && test -f Makefile && $(MAKE) clean || true
	cd perl-shared && test -f Makefile && $(MAKE) clean || true

##END##
