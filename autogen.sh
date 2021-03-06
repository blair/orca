#!/bin/sh

# Check for autoconf 2.53 or newer.
echo "$0: checking for autoconf 2.53 or newer..."
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

# Check for aclocal.
${ACLOCAL:-aclocal} --version >/dev/null 2>&1
if test $? -ne 0; then
  echo "$0: aclocal not found."
  echo "           You need aclocal installed to build Orca from Subversion."
  exit 1
else
  echo "$0: aclocal found"
fi

# The Orca Subversion repository contains RRDtool, which has its own
# automake, autoconf and libtool setup.  When checking out Orca from
# Subversion, it does not preserve the relative timestamps of the
# build environment, which can cause 'make' to rebuild RRDtool's build
# environment.
#
# To work around this, touch the build files in chronological order.
# These files are touched in the same order that the files appear in
# the offical RRDtool tarball.
echo "$0: touching RRDtool build files to preserve relative timestamps..."
for f in \
  Makefile.am \
  configure.ac \
  aclocal.m4 \
  Makefile.in \
  configure \
  config.h.in;
  do
    path=packages/rrdtool-1.0.50/$f
    echo Touching $path
    touch $path
    sleep 2
done

# Now create configure and it's associated build files.
echo "$0: creating configure and associated build files..."
${ACLOCAL:-aclocal} -I config --output=config/aclocal.m4
${AUTOCONF:-autoconf} --include=config
rm -fr autom4te*.cache
