dnl $Id: config.m4,v 1.1.1.1 2002/02/26 10:21:20 oetiker Exp $

PHP_ARG_WITH(rrdtool, for RRDTool support,
[  --with-rrdtool[=DIR]      Include RRDTool support.  DIR is the rrdtool
                          install directory.])

if test "$PHP_RRDTOOL" != "no"; then
  for i in /usr/local /usr /opt/rrdtool /usr/local/rrdtool $PHP_RRDTOOL; do
    if test -f $i/include/rrd.h; then
      RRDTOOL_DIR=$i
    fi
  done

  if test -z "$RRDTOOL_DIR"; then
    AC_MSG_ERROR(Please reinstall rrdtool, or specify a directory - I cannot find rrd.h)
  fi
  PHP_ADD_INCLUDE($RRDTOOL_DIR/include)
  PHP_ADD_LIBRARY_WITH_PATH(rrd, $RRDTOOL_DIR/lib, RRDTOOL_SHARED_LIBADD)
  PHP_SUBST(RRDTOOL_SHARED_LIBADD)

  AC_DEFINE(HAVE_RRDTOOL,1,[ ])

  PHP_EXTENSION(rrdtool, $ext_shared)
fi
