/*
 * php_rrdtool.h
 *
 * php4 rrdtool module.  
 *
 * Joe Miller, <joeym@inficad.com>,<joeym@ibizcorp.com>, 7/19/2000
 *
 * $Id: php_rrdtool.h,v 1.1.1.1 2002/02/26 10:21:20 oetiker Exp $
 *
 */

#ifndef _PHP4_RRDTOOL_H
#define _PHP4_RRDTOOL_H

#if COMPILE_DL_RRDTOOL
#undef HAVE_RRDTOOL
#define HAVE_RRDTOOL 1
#endif
#ifndef DLEXPORT
#define DLEXPORT
#endif

#if HAVE_RRDTOOL

PHP_MINFO_FUNCTION(rrdtool);

extern zend_module_entry rrdtool_module_entry;
#define rrdtool_module_ptr &rrdtool_module_entry
#define phpext_rrdtool_ptr rrdtool_module_ptr

PHP_FUNCTION(rrd_error);
PHP_FUNCTION(rrd_clear_error);
PHP_FUNCTION(rrd_update);
PHP_FUNCTION(rrd_last);
PHP_FUNCTION(rrd_create);
PHP_FUNCTION(rrd_graph);
PHP_FUNCTION(rrd_fetch);

#else

#define phpext_rrdtool_ptr NULL


#endif /* HAVE_RRDTOOL */

#endif  /* _PHP4_RRDTOOL_H */
