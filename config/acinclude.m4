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
