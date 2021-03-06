dnl RRDtool AutoConf script ... 
dnl ---------------------------
dnl
dnl Created by Jeff Allen, Tobi Oetiker, Blair Zajac
dnl
dnl
dnl Disable user's CDPATH, otherwise expressions of the form:
dnl   cd $var && pwd
dnl generate double output, ie. cd command reports the new
dnl directory location in addition to the pwd command. See
dnl missing_dir= below. This in turn generates an unterminated
dnl 's' command for sed when generating the Makefiles.
unset CDPATH

dnl make sure we are being executed in the right place
AC_INIT(rrdtool, 1.0.50)
AC_CONFIG_SRCDIR([src/rrd_tool.c])

dnl all our local stuff like install scripts and include files
dnl is in there
AC_CONFIG_AUX_DIR(config)

dnl determine the type of system we are running on
AC_CANONICAL_TARGET([])

dnl tell automake the this script is for rrdtool
AM_INIT_AUTOMAKE

dnl where we install our stuff ...
AC_PREFIX_DEFAULT( /usr/local/rrdtool-1.0.50 )

dnl tell automake which file to use as config header
AC_CONFIG_HEADERS([config.h])

dnl Minimum Autoconf version required.
AC_PREREQ(2.58)

dnl don't build a shared library ...
dnl this can be changed when running configure
AC_DISABLE_SHARED

dnl let automake know we use libtool
AC_PROG_LIBTOOL

dnl LWT 24July03, add config options for locally installed
dnl               libpng and zlib.  Use similar switch name 
dnl               as pkgconfig which ships w/glib code

AC_MSG_CHECKING([for local libpng use])
AC_ARG_ENABLE([local-libpng],
[  --enable-local-libpng   Use OS's libpng instead of v1.0.9 with rrdtool],
[local_libpng=$enableval],
[local_libpng=no])
AC_MSG_RESULT([$local_libpng])


AC_MSG_CHECKING([for local zlib use])
AC_ARG_ENABLE([local-zlib],
[  --enable-local-zlib     Use OS's zlib instead of v1.1.4 with rrdtool],
[local_zlib=$enableval],
[local_zlib=no])
AC_MSG_RESULT([$local_zlib])

AM_CONDITIONAL(USE_INSTALLED_LIBPNG, test x$local_libpng = xyes)
AM_CONDITIONAL(USE_INSTALLED_ZLIB,   test x$local_zlib = xyes)

if test x$local_libpng = xyes
then
  PNG_LINK=-lpng
  AC_SUBST(PNG_LINK)
else
  PNG_LIB_DIR=libpng-1.0.9
  AC_SUBST(PNG_LIB_DIR)
fi

if test x$local_zlib = xyes
then
  ZLIB_LINK=-lz
  AC_SUBST(ZLIB_LINK)
else
  ZLIB_LIB_DIR=zlib-1.1.4
  AC_SUBST(ZLIB_LIB_DIR)
fi

RRD_PRIVATE_LINK="-lrrd_private $PNG_LINK $ZLIB_LINK" 
AC_SUBST(RRD_PRIVATE_LINK)

dnl Define library subdirectory names here.
CGI_LIB_DIR=cgilib-0.4
GD_LIB_DIR=gd1.3

dnl substitute them in all the files listed in AC_OUTPUT
AC_SUBST(CGI_LIB_DIR)
AC_SUBST(GD_LIB_DIR)
AC_SUBST(PERLFLAGS)

dnl Check for Perl.
AC_PATH_PROG(PERL, perl, no)
if test "x$PERL" = "xno"; then
	COMP_PERL=
else
	COMP_PERL="perl_piped perl_shared"
	AC_MSG_CHECKING(for shared library extension)
	SO_EXT=`$PERL -e 'use Config; if (defined $Config{so} and $Config{so} ne 'a') {print "$Config{so}\n"} else {print "so\n"};'`
	AC_MSG_RESULT($SO_EXT)
        AC_MSG_CHECKING(for the C compiler perl wants to use to build its modules)
        PROBLEMCC=`$PERL -e 'use Config; ($cc = $Config{cc}) =~ s/\s.*//; exit 0 if -x $cc; map {if (-x "$_/$cc"){exit 0}} split /:/, $ENV{PATH};print $Config{cc}'`
        if test x$PROBLEMCC != x; then
                AC_MSG_RESULT(no)
                echo Could not find the Compiler: '"'$PROBLEMCC'"'
                echo which has been used to build perl. You may have to compile
                echo your own copy of perl to make this work. Binary perls often
                echo exhibit this problem
                exit 1
        else
                AC_MSG_RESULT(found)
        fi
fi
AC_SUBST(COMP_PERL)
AC_SUBST(SO_EXT)

dnl Check for Tcl.
withval=""
AC_ARG_WITH(tcllib,[  --with-tcllib=DIR       location of the tclConfig.sh])
found=0
AC_MSG_CHECKING(for tclConfig.sh in $withval)
if test -f "$withval/tclConfig.sh" ; then
    	tcl_config=$withval/tclConfig.sh
        found=1
        AC_MSG_RESULT(yes)
        break
else
        AC_MSG_RESULT(no)
fi

if test $found -eq 0 ; then
        AC_MSG_WARN([tclConfig.sh not found - Tcl interface won't be built])
else
	. $tcl_config
fi

dnl Pass additional perl options when generating Makefile from Makefile.PL
# Options to pass when configuring perl module
AC_ARG_WITH(perl-options,
[  --with-perl-options=[OPTIONS]  options to pass on command-line when
                          generating Makefile from Makefile.PL],
[PERL_MAKE_OPTIONS=$withval])
AC_SUBST(PERL_MAKE_OPTIONS)

dnl Enable ISO-8859-2 fonts rather than ISO-8859-2
AC_ARG_ENABLE(latin2,
[  --enable-latin2         use ISO-8859-2 fonts ],
[with_latin2=$enableval],
[with_latin2=no])
test "$with_latin2" = "yes" && AC_DEFINE(LATIN2_ENABLE,1,[Define to get LATIN2 encoding])

AM_CONDITIONAL(COMP_TCL, test x$found = x1 )

AC_SUBST(TCL_PREFIX)
AC_SUBST(TCL_SHLIB_CFLAGS)
AC_SUBST(TCL_SHLIB_LD)
AC_SUBST(TCL_SHLIB_SUFFIX)
AC_SUBST(TCL_PACKAGE_PATH)
AC_SUBST(TCL_LD_SEARCH_FLAGS)

dnl Check for the compiler and static/shared library creation.
AC_PROG_CC
AC_PROG_CPP
dnl RRD_ACLOCAL_FIND_LIBTOOL


dnl Checks for header files.
AC_HEADER_STDC
AC_CHECK_HEADERS(sys/stat.h sys/types.h fcntl.h locale.h fp_class.h malloc.h unistd.h ieeefp.h math.h time.h sys/time.h sys/times.h sys/param.h sys/resource.h float.h)

dnl Checks for typedefs, structures, and compiler characteristics.
AC_C_CONST
AC_HEADER_TIME
AC_STRUCT_TM

dnl Checks for libraries.
AC_CHECK_FUNC(acos, , AC_CHECK_LIB(m, acos))

dnl Check for nroff
AC_PATH_PROGS(NROFF, gnroff nroff)
AC_PATH_PROGS(TROFF, groff troff)

dnl Does the compiler like -Wall and -pedantic?
if test "x$GCC" = "xyes"; then
  oCFLAGS=$CFLAGS
  CFLAGS="$CFLAGS -Wall -pedantic -Wshadow -Wpointer-arith -Wcast-align -Wmissing-prototypes -Wmissing-declarations -Wnested-externs -Winline"
  AC_CACHE_CHECK(if we can use GCC-specific compiler options, rd_cv_gcc_opt,
                [AC_COMPILE_IFELSE([AC_LANG_PROGRAM([[]], [[return 0 ]])],[rd_cv_gcc_opt=yes],[rd_cv_gcc_opt=no ])
               ]
        )
  if test $rd_cv_gcc_opt = no; then
         CFLAGS=$oCFLAGS
  fi
fi

dnl add pic flag in any case this makes sure all our code is relocatable
CFLAGS="$CFLAGS "`$SHELL libtool --config | grep pic_flag= | sed -e 's/.*pic_flag=//' -e 's/"//g'`

dnl it seems that hpux chockes on -fPIC for some reason
ZLIB_CFLAGS="$CFLAGS"
case $target_os in
*hpux*)
 	ZLIB_CFLAGS=`echo $CFLAGS|sed -e 's/-fPIC/-fpic/g'`
;;
esac
AC_SUBST(ZLIB_CFLAGS)

dnl Checks for library functions.
AC_FUNC_STRFTIME
AC_FUNC_VPRINTF

dnl for each function found we get a definition in config.h 
dnl of the form HAVE_FUNCTION

AC_CHECK_FUNCS(opendir readdir chdir chroot getuid strerror tzset setlocale snprintf vsnprintf fpclass class fp_class isnan memmove strchr mktime getrusage gettimeofday)

dnl HP-UX 11.00 does not have finite but does have isfinite as a macro
AC_CHECK_FUNCS(fpclassify, ,
  [AC_MSG_CHECKING(for fpclassify with <math.h>)
    AC_LINK_IFELSE([AC_LANG_PROGRAM([[#include <math.h>]], [[float f = 0.0; fpclassify(f)]])],[AC_MSG_RESULT(yes)
      AC_DEFINE(HAVE_FPCLASSIFY,1,We have the fpclassify function)],[AC_MSG_RESULT(no)])])
AC_CHECK_FUNCS(finite, ,
  [AC_CHECK_FUNCS(isfinite, ,
    [AC_MSG_CHECKING(for isfinite with <math.h>)
    AC_LINK_IFELSE([AC_LANG_PROGRAM([[#include <math.h>]], [[float f = 0.0; isfinite(f)]])],[AC_MSG_RESULT(yes)
      AC_DEFINE(HAVE_ISFINITE,1,we have the isinfinite function)],[AC_MSG_RESULT(no)])])])
AC_CHECK_FUNCS(isinf, ,
  [AC_MSG_CHECKING(for isinf with <math.h>)
    AC_LINK_IFELSE([AC_LANG_PROGRAM([[#include <math.h>]], [[float f = 0.0; isinf(f)]])],[AC_MSG_RESULT(yes)
      AC_DEFINE(HAVE_ISINF,1,we have the isinf function)],[AC_MSG_RESULT(no)])])

dnl what does realloc do if it gets called with a NULL pointer

AC_CACHE_CHECK([if realloc can deal with NULL], rd_cv_null_realloc,
[AC_RUN_IFELSE([AC_LANG_SOURCE([[#include <stdlib.h>
	      int main(void){
              char *x = NULL;
	      x = realloc (x,10);
	      if (x==NULL) return 1;
	      return 0;
             }]])],[rd_cv_null_realloc=yes],[rd_cv_null_realloc=nope],[:])])

if test x"$rd_cv_null_realloc" = xnope; then
AC_DEFINE(NO_NULL_REALLOC,1,[no null realloc])
fi

dnl determine how to get IEEE math working
dnl AC_IEEE(MESSAGE, set rd_cv_ieee_[var] variable, INCLUDES,
dnl   FUNCTION-BODY, [ACTION-IF-FOUND [,ACTION-IF-NOT-FOUND]])

AC_DEFUN(AC_IEEE, 
AC_MSG_CHECKING([if IEEE math works $1])
AC_CACHE_VAL([rd_cv_ieee_$2],
[AC_RUN_IFELSE([AC_LANG_SOURCE([[$3

#if HAVE_MATH_H
#  include <math.h>
#endif

#if HAVE_FLOAT_H
#  include <float.h>  
#endif

#if HAVE_IEEEFP_H
#  include <ieeefp.h>
#endif

#if HAVE_FP_CLASS_H
#  include <fp_class.h>
#endif

/* Solaris */
#if (! defined(HAVE_ISINF) && defined(HAVE_FPCLASS))
#  define HAVE_ISINF 1
#  define isinf(a) (fpclass(a) == FP_NINF || fpclass(a) == FP_PINF)
#endif

/* Digital UNIX */
#if (! defined(HAVE_ISINF) && defined(HAVE_FP_CLASS) && defined(HAVE_FP_CLASS_H))
#  define HAVE_ISINF 1
#  define isinf(a) (fp_class(a) == FP_NEG_INF || fp_class(a) == FP_POS_INF)
#endif 

/* AIX */
#if (! defined(HAVE_ISINF) && defined(HAVE_CLASS))
#  define HAVE_ISINF 1
#  define isinf(a) (class(a) == FP_MINUS_INF || class(a) == FP_PLUS_INF)
#endif

#if (! defined(HAVE_ISINF) && defined(HAVE_FPCLASSIFY) && defined(FP_PLUS_INF) && defined(FP_MINUS_INF))
#  define HAVE_ISINF 1
#  define isinf(a) (fpclassify(a) == FP_MINUS_INF || fpclassify(a) == FP_PLUS_INF)
#endif

#if (! defined(HAVE_ISINF) && defined(HAVE_FPCLASSIFY) && defined(FP_INFINITE))
#  define HAVE_ISINF 1
#  define isinf(a) (fpclassify(a) == FP_INFINITE)
#endif

#include <stdio.h>
int main(void){
    double nan,inf,c,zero;
    $4;
    /* some math to see if we get a floating point exception */
    zero=sin(0.0); /* don't let the compiler optimize us away */
    nan=0.0/zero; /* especially here */
    inf=1.0/zero; /* and here. I want to know if it can do the magic */
		  /* at run time without sig fpe */
    c = inf + nan;
    c = inf / nan;
    if (! isnan(nan)) {printf ("not isnan(NaN) ... "); return 1;}
    if (nan == nan) {printf ("nan == nan ... "); return 1;}
    if (! isinf(inf)) {printf ("not isinf(oo) ... "); return 1;}
    if (! isinf(-inf)) {printf ("not isinf(-oo) ... "); return 1;}
    if (! inf > 0) {printf ("not inf > 0 ... "); return 1;}
    if (! -inf < 0) {printf ("not -inf < 0 ... "); return 1;}
    return 0;
 }]])],[rd_cv_ieee_$2=yes],[rd_cv_ieee_$2=no],[:])])
dnl these we run regardles is cached or not
if test x${rd_cv_ieee_$2} = "xyes"; then
 AC_MSG_RESULT(yes)
 $5
else
 AC_MSG_RESULT(no)
 $6
fi

)

_cflags=${CFLAGS}
AC_IEEE([out of the box], works, , , ,
  [CFLAGS="$_cflags -ieee"
  AC_IEEE([with the -ieee switch], switch, , , ,
    [CFLAGS="$_cflags -qfloat=nofold"
    AC_IEEE([with the -qfloat=nofold switch], nofold, , , ,
      [CFLAGS="$_cflags -w -qflttrap=enable:zerodivide"
      AC_IEEE([with the -w -qflttrap=enable:zerodivide], flttrap, , , ,
       [CFLAGS="$_cflags -mieee"
       AC_IEEE([with the -mieee switch], mswitch, , , ,
         [CFLAGS="$_cflags -q float=rndsngl"
         AC_IEEE([with the -q float=rndsngl switch], qswitch, , , ,
           [CFLAGS="$_cflags -OPT:IEEE_NaN_inf=ON"
           AC_IEEE([with the -OPT:IEEE_NaN_inf=ON switch], ieeenaninfswitch, , , ,
             [CFLAGS="$_cflags -OPT:IEEE_comparisons=ON"
             AC_IEEE([with the -OPT:IEEE_comparisons=ON switch], ieeecmpswitch, , , ,
               [CFLAGS=$_cflags
               AC_IEEE([with fpsetmask(0)], mask,
                 [#include <floatingpoint.h>], [fpsetmask(0)],
                 [AC_DEFINE(MUST_DISABLE_FPMASK,1,[UNKNOWN only works with FPMASK disabled])
    	           PERLFLAGS="CCFLAGS=-DMUST_DISABLE_FPMASK"],
                   [AC_IEEE([with signal(SIGFPE,SIG_IGN)], sigfpe,
                   [#include <signal.h>], [signal(SIGFPE,SIG_IGN)],
                   [AC_DEFINE(MUST_DISABLE_SIGFPE,1,[UNKNOWN only works with disabled SIGFPE])
                   PERLFLAGS="CCFLAGS=-DMUST_DISABLE_SIGFPE"],		
                   AC_MSG_ERROR([
Your Compiler does not do propper IEEE math ... Please find out how to
make IEEE math work with your compiler and let me know (oetiker@ee.ethz.ch).
Check config.log to see what went wrong ...
]))])])])])])])])])])


AC_CONFIG_FILES([cgilib-0.4/Makefile				\
          examples/shared-demo.pl			\
          examples/piped-demo.pl			\
          examples/stripes.pl				\
          examples/bigtops.pl				\
          examples/minmax.pl				\
          examples/cgi-demo.cgi				\
          examples/Makefile				\
          contrib/Makefile				\
          contrib/trytime/Makefile			\
          contrib/log2rrd/log2rrd.pl			\
          contrib/killspike/killspike.pl		\
          contrib/rrdlastds/rrdlastds.pl		\
          contrib/rrdfetchnames/rrdfetchnames.pl	\
          contrib/add_ds/add_ds.pl			\
	  contrib/add_ds/batch.pl			\
          doc/Makefile					\
          gd1.3/Makefile				\
          libpng-1.0.9/Makefile				\
          zlib-1.1.4/Makefile				\
          src/Makefile					\
          tcl/Makefile					\
          perl-shared/Makefile.PL			\
          perl-piped/Makefile.PL                       \
          Makefile])
AC_CONFIG_COMMANDS([default],[[\
          chmod +x examples/*.cgi examples/*.pl contrib/*/*.pl]],[[]])
AC_OUTPUT

AC_MSG_CHECKING(in)
AC_MSG_RESULT(and out again)

echo $ECHO_N "ordering CD from http://people.ee.ethz.ch/~oetiker/wish $ac_c" 1>&6
sleep 1
echo $ECHO_N ".$ac_c" 1>&6
sleep 2
echo $ECHO_N ".$ac_c" 1>&6
sleep 1
echo $ECHO_N ".$ac_c" 1>&6
sleep 3
echo $ECHO_N ".$ac_c" 1>&6
echo $ECHO_N ".$ac_c" 1>&6
echo $ECHO_N ".$ac_c" 1>&6
sleep 2
AC_MSG_RESULT([ just kidding ;-)])
echo
echo "----------------------------------------------------------------"
echo "Config is DONE!"
echo
echo "Type 'make' to compile the software and use 'make install' to "
echo "install everything to: $prefix."
echo
echo "If you want to install the perl"
echo "modules in site-perl, try 'make site-perl-install'."
echo 
echo "       ... that wishlist is NO JOKE. If you find RRDtool useful"
echo "make me happy. Go to http://people.ee.ethz.ch/oetiker/wish and"
echo "place an order."
echo 
echo "                               -- Tobi Oetiker <tobi@oetiker.ch>"
echo "----------------------------------------------------------------"
