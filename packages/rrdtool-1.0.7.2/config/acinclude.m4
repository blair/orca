dnl Check if aclocal can the find libtool macros.
AC_DEFUN(RRD_ACLOCAL_FIND_LIBTOOL,
    [
	AC_CACHE_CHECK(
	    [whether aclocal can find libtool macros],
	    rrd_cv_libtool_macros,
	    [
		rm -rf .test-libtool
		mkdir .test-libtool
		cd .test-libtool
		cat >configure.in <<EOF
[AM_PROG_LIBTOOL]
EOF
		aclocal >/dev/null 2>/dev/null
		if grep LIBTOOL aclocal.m4 >/dev/null 2>&1; then
		    rrd_cv_libtool_macros=yes
		else
		    rrd_cv_libtool_macros=no
		fi
		cd ..
		rm -rf .test-libtool
	    ]
	)
	if test "$amanda_cv_libtool_macros" = yes; then
	    LIBTOOL_M4_MACRO_DIR=
	else
	    # We don't want top_srcdir here, because, when we run aclocal,
	    # we're already in top_srcdir.
	    LIBTOOL_M4_MACRO_DIR='-I config/libtool'
	fi
	AC_SUBST(LIBTOOL_M4_MACRO_DIR)
    ]
)
