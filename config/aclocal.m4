# config/aclocal.m4 generated automatically by aclocal 1.5

# Copyright 1996, 1997, 1998, 1999, 2000, 2001
# Free Software Foundation, Inc.
# This file is free software; the Free Software Foundation
# gives unlimited permission to copy and/or distribute it,
# with or without modifications, as long as this notice is preserved.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY, to the extent permitted by law; without
# even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE.

dnl Check if the requested modules are install in this perl module.
dnl Do not cache this result, since the user may easy install the
dnl modules and rerun configure.  We do not want to remember if
dnl the module is not installed.
dnl BORP_PERL_MODULE(DEFINE, PATH_TO_PERL, MODULE_NAME, MODULE_VERSION,
dnl    [ACTION_IF_FOUND, [ACTION_IF_NOT_FOUND]]
AC_DEFUN(BORP_PERL_MODULE, [
  AC_MSG_CHECKING([if Perl module $3 version $4 is installed])
  if $2 ./config/check_for_perl_mod $3 $4; then
    $1=yes
    ifelse([$5], , , [$5])
  else
    $1=no
    ifelse([$6], , , [$6])
  fi
  AC_MSG_RESULT([$]$1)
])

dnl Check if the whole path to Perl can be placed on the #! line
dnl of a shell script.  Some systems have length restrictions
dnl so some paths to programs may be too long.
dnl BORP_PERL_RUN(PATH_TO_SHELL [, ACTION-IF-WORKS [, ACTION-IF_NOT]])
AC_DEFUN(BORP_PERL_RUN, [
  AC_MSG_CHECKING([if '$1' will run Perl scripts])
  rm -f conftest.BZ
  cat > conftest.BZ <<EOF
#!$1

exit 0
EOF
  chmod +x conftest.BZ
  if ./conftest.BZ 2>/dev/null; then
    ifelse([$2], , , [$2])
    AC_MSG_RESULT(yes)
  else
    ifelse([$3], , , [$3])
    AC_MSG_RESULT(no)
  fi
  rm -f conftest.BZ
])

