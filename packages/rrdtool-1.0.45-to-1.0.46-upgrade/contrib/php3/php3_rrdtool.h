#ifndef _PHP3_RRDTOOL_H
#define _PHP3_RRDTOOL_H

#if COMPILE_DL
#undef HAVE_RRDTOOL
#define HAVE_RRDTOOL 1
#endif
#ifndef DLEXPORT
#define DLEXPORT
#endif

#if HAVE_RRDTOOL

extern php3_module_entry rrdtool_module_entry;
#define snmp_module_ptr &rrdtool_module_entry

extern DLEXPORT void php3_rrd_error(INTERNAL_FUNCTION_PARAMETERS);
extern DLEXPORT void php3_rrd_clear_error(INTERNAL_FUNCTION_PARAMETERS);
extern DLEXPORT void php3_rrd_update(INTERNAL_FUNCTION_PARAMETERS);
extern DLEXPORT void php3_rrd_last(INTERNAL_FUNCTION_PARAMETERS);
extern DLEXPORT void php3_rrd_create(INTERNAL_FUNCTION_PARAMETERS);
extern DLEXPORT void php3_rrd_graph(INTERNAL_FUNCTION_PARAMETERS);
extern DLEXPORT void php3_rrd_fetch(INTERNAL_FUNCTION_PARAMETERS);

#else

#define rrdtool_module_ptr NULL

#endif /* HAVE_RRDTOOL */

#endif  /* _PHP3_RRDTOOL_H */
