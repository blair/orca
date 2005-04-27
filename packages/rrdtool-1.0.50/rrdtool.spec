%define DISTRO %([ -f /etc/redhat-release ] && sed -e "s/\\(.\\+\\)\\( Linux release \\)\\(.\\+\\)\\( .\\+\\)/\\1 \\3/" /etc/redhat-release)
%define DISTRO_REL %([ -f /etc/redhat-release ] && sed -e "s/\\(.\\+ release \\)\\(.\\+\\)\\( .\\+\\)/\\2/" /etc/redhat-release)
%define REQ_RPM_REL %(rpm -q --queryformat "%{VERSION}" rpm)
%define GLIBC_REL %(rpm -q --queryformat "%{VERSION}" glibc)

Summary: 	RRDtool - round robin database
Name: 		rrdtool
Version:	1.0.50
Release:	1.%{DISTRO_REL}
Copyright: 	GPL
Group: 		Applications/Databases
Source: 	http://people.ee.ethz.ch/oetiker/webtools/rrdtool/pub/%{name}-%{version}.tar.gz
Buildroot: 	/var/tmp/rrdtool-root
Prefix:	 	%{_prefix}
BuildRequires:	tcl-develop
Url: 		http://people.ee.ethz.ch/oetiker/webtools/rrdtool/
Vendor: 	Tobi Oetiker <oetiker@ee.ethz.ch>
Packager:	Chris Wilson <chris@aidworld.org>

%description
RRD is the Acronym for Round Robin Database. RRD is a system to store and 
display time-series data (i.e. network bandwidth, machine-room temperature, 
server load average). It stores the data in a very compact way that will not 
expand over time, and it presents useful graphs by processing the data to 
enforce a certain data density. It can be used either via simple wrapper 
scripts (from shell or Perl) or via frontends that poll network devices and 
put a friendly user interface on it.

%package devel
Summary: RRDtool - round robin database static libraries and headers
Group: Development/Libraries
Requires: rrdtool
%description devel
RRD is the Acronym for Round Robin Database. RRD is a system to store and
display time-series data (i.e. network bandwidth, machine-room temperature,
server load average). This package allow you to use directly this library.


%prep
%setup -q

%build
CFLAGS="$RPM_OPT_FLAGS" ./configure --with-tcllib=%{_libdir} --prefix=%{_prefix} --enable-shared
make
# @perl@ and @PERL@ correction
cd examples
find . -type f -exec /usr/bin/perl -e 's/^#! \@perl\@/#!\/usr\/bin\/perl/gi' -p -i \{\} \;
find . -name "*.pl" -exec perl -e 's;\015;;gi' -p -i \{\} \;
# clean-up pod2man

%install
rm -rf ${RPM_BUILD_ROOT}
make install prefix=${RPM_BUILD_ROOT}/usr imandir=${RPM_BUILD_ROOT}%{_mandir}/man1 mandir=${RPM_BUILD_ROOT}%{_mandir}

# reduce executables len
strip ${RPM_BUILD_ROOT}/%{_bindir}/rrd*
# reduce libraries len
strip ${RPM_BUILD_ROOT}/%{_libdir}/librrd*.so
strip ${RPM_BUILD_ROOT}/%{_libdir}/librrd*.a
strip ${RPM_BUILD_ROOT}/%{_libdir}/perl/auto/RRDs/RRDs.so
eval `perl '-V:installarchlib'`
install -d ${RPM_BUILD_ROOT}/$installarchlib
mv -f ${RPM_BUILD_ROOT}/%{_libdir}/perl/* ${RPM_BUILD_ROOT}/$installarchlib
# now create include and files
install -d ${RPM_BUILD_ROOT}/%{_includedir}
install -m644 src/rrd*.h ${RPM_BUILD_ROOT}/%{_includedir}
install -m755 contrib/log2rrd/log2rrd.pl ${RPM_BUILD_ROOT}/%{_bindir}
# remove .in/.am files
find  . -type f -name "*.in" -exec rm -f \{\} \;
find  . -type f -name "*.am" -exec rm -f \{\} \;
find ${RPM_BUILD_ROOT}/$installarchlib -type f -print | sed "s@^${RPM_BUILD_ROOT}@@g" > %{name}-%{version}-file
rm -rf ${RPM_BUILD_ROOT}/usr/{contrib,doc,examples,html}

%clean
rm -rf ${RPM_BUILD_ROOT}
 
%files -f %{name}-%{version}-file
%defattr(-,root,root)
%{_bindir}/*
%{_libdir}/librrd.*
%{_mandir}/man1/*
%doc C* README TODO doc/*.txt doc/*.html contrib

%files devel
%defattr(-,root,root)
%{_libdir}/lib*.a
%{_includedir}/*.h
%doc examples/*


%changelog
* Fri Jan 07 2004 Chris Wilson <chris@aidworld.org>
- 1.0.49
- Delete extraneous files which cause RPM build to fail on paranoid Fedora

* Wed Mar 26 2003 Tom Scanlan <tscanlan-web@they.gotdns.org>
- 1.0.41

* Mon Oct 28 2002 Andrew Pam <xanni@sericyb.com.au>
- 1.0.40

* Fri Jul 05 2002 Henri Gomez <hgomez@users.sourceforge.net>
- 1.0.39

* Mon Jun 03 2002 Henri Gomez <hgomez@users.sourceforge.net>
- 1.0.38

* Fri Apr 19 2002 Henri Gomez <hgomez@users.sourceforge.net>
- 1.0.37

* Tue Mar 12 2002 Henri Gomez <hgomez@users.sourceforge.net>
- 1.0.34
- rrdtools include zlib 1.1.4 which fix vulnerabilities in 1.1.3

