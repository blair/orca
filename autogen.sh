#!/bin/sh

echo "$0: checking installation..."

# Check for autoconf 2.53 or newer.
ac_version=`${AUTOCONF:-autoconf} --version 2>/dev/null|head -1|sed -e 's/^[^0-9]*//' -e 's/[a-z]* *$//'`
if test -z "$ac_version"; then
  echo "$0: autoconf not found."
  echo "           You need autoconf version 2.53 or newer installed"
  echo "           to build Orca from Subversion."
  exit 1
fi
IFS=.; set $ac_version; IFS=' '
if test "$1" = "2" -a "$2" -lt "53" || test "$1" -lt "2"; then
  echo "$0: autoconf version $ac_version found."
  echo "           You need autoconf version 2.53 or newer installed"
  echo "           to build Orca from Subversion."
  exit 1
else
  echo "$0: autoconf version $ac_version (ok)"
fi

# The Orca Subversion repository contains RRDtool, which has its own
# automake, autoconf and libtool setup.  When checking out Orca from
# Subversion, it does not preserve the relative timestamps of the
# build environment, which can cause `make' to rebuild RRDtool's build
# environment.
#
# To work around this, touch the build files in chronological order.
echo "$0: touching RRDtool build files to preserve relative timestamps"
find packages -name configure.in -o -name Makefile.am | xargs touch
sleep 2
find packages -name configure -o -name Makefile.in -o -name stamp-h\* | xargs touch

echo "$0: building configuration files"

aclocal -I config --output=config/aclocal.m4
autoconf --include=config
rm -fr autom4te*.cache
