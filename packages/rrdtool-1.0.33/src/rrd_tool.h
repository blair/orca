/*****************************************************************************
 * RRDtool 1.0.13  Copyright Tobias Oetiker, 1997,1998, 1999
 *****************************************************************************
 * rrd_tool.h   Common Header File
 *****************************************************************************
 * $Id: rrd_tool.h,v 1.5 1998/03/08 12:35:11 oetiker Exp oetiker $
 * $Log: rrd_tool.h,v $
 *****************************************************************************/
#ifdef  __cplusplus
extern "C" {
#endif


#ifndef _RRD_TOOL_H
#define _RRD_TOOL_H

#ifdef WIN32
# include "ntconfig.h"
#else
#ifdef HAVE_CONFIG_H
#include <config.h>
#endif
#endif

#ifdef MUST_DISABLE_SIGFPE
#include <signal.h>
#endif

#ifdef MUST_DISABLE_FPMASK
#include <floatingpoint.h>
#endif
    
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <time.h>
#include <ctype.h>

#if HAVE_SYS_PARAM_H
#  include <sys/param.h>
#endif

#ifndef MAXPATH
#  define MAXPATH 1024
#endif

#if HAVE_MATH_H
# include <math.h>
#endif
#if HAVE_UNISTD_H
# include <unistd.h>
#endif
#if HAVE_SYS_TIME_H
# include <sys/time.h>
#endif
#if HAVE_SYS_TIMES_H
# include <sys/times.h>
#endif
#if HAVE_SYS_RESOURCE_H
# include <sys/resource.h>
#if (defined(__svr4__) && defined(__sun__))
/* Solaris headers (pre 2.6) don't have a getrusage prototype.
   Use this instead. */
extern int getrusage(int, struct rusage *);
#endif /* __svr4__ && __sun__ */
#endif

#include "parsetime.h"
int proc_start_end (struct time_value *,  struct time_value *, time_t *, time_t *);

#ifndef WIN32

/* unix-only includes */
#ifndef isnan
int isnan(double value);
#endif

#else

/* Win32 only includes */

#include <float.h>        /* for _isnan  */
#define isnan _isnan
#define finite _finite
#define isinf(a) (_fpclass(a) == _FPCLASS_NINF || _fpclass(a) == _FPCLASS_PINF)
#endif

/* local include files -- need to be after the system ones */
#include "getopt.h"
#include "rrd_format.h"

#ifndef max
#define max(a,b) ((a) > (b) ? (a) : (b))
#endif

#ifndef min
#define min(a,b) ((a) < (b) ? (a) : (b))
#endif                                                   

#define DIM(x) (sizeof(x)/sizeof(x[0]))

/* main function blocks */
int    rrd_create(int argc, char **argv);
int    rrd_update(int argc, char **argv);
int    rrd_graph(int argc, char **argv, char ***prdata, int *xsize, int *ysize);
int    rrd_fetch(int argc, char **argv, 
		 time_t *start, time_t *end, unsigned long *step, 
		 unsigned long *ds_cnt, char ***ds_namv, rrd_value_t **data);
int    rrd_restore(int argc, char **argv);
int    rrd_dump(int argc, char **argv);
int    rrd_tune(int argc, char **argv);
time_t rrd_last(int argc, char **argv);
int    rrd_resize(int argc, char **argv);

/* HELPER FUNCTIONS */
void rrd_set_error(char *fmt,...);
void rrd_clear_error(void);
int  rrd_test_error(void);
char *rrd_get_error(void);
int  LockRRD(FILE *);
int GifSize(FILE *, long *, long *);
int PngSize(FILE *, long *, long *);
int PngSize(FILE *, long *, long *);
#include <gd.h>
void gdImagePng(gdImagePtr im, FILE *out);
int rrd_create_fn(char *file_name, rrd_t *rrd);
int rrd_fetch_fn(char *filename, enum cf_en cf_idx,
		 time_t *start,time_t *end,
		 unsigned long *step,
		 unsigned long *ds_cnt,
		 char        ***ds_namv,
		 rrd_value_t **data);
void rrd_free(rrd_t *rrd);
void rrd_init(rrd_t *rrd);

int  rrd_open(char *file_name, FILE **in_file, rrd_t *rrd, int rdwr);
int readfile(char *file, char **buffer, int skipfirst);


#define RRD_READONLY    0
#define RRD_READWRITE   1

enum cf_en cf_conv(char *string);
enum dst_en dst_conv(char *string);
long ds_match(rrd_t *rrd,char *ds_nam);
double rrd_diff(char *a, char *b);

#endif



#ifdef  __cplusplus
}
#endif


