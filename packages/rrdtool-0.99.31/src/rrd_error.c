/*****************************************************************************
 * RRDTOOL 0.99.31 Copyright Tobias Oetiker, 1997, 1998, 1999
 *****************************************************************************
 * rrd_error.c   Common Header File
 *****************************************************************************
 * $Id: rrd_tool.h,v 1.5 1998/03/08 12:35:11 oetiker Exp oetiker $
 * $Log: rrd_tool.h,v $
 *************************************************************************** */

#include "rrd_tool.h"
static char* rrd_error = NULL;
#include <stdarg.h>



void
rrd_set_error(char *fmt, ...)
{
    int maxlen = strlen(fmt)*4;
    va_list argp;
    rrd_clear_error();
    rrd_error = malloc(sizeof(char)*maxlen);
    va_start(argp, fmt);
    vsprintf(rrd_error, fmt, argp);
    va_end(argp);
}

int
rrd_test_error(void) {
    return rrd_error != NULL;
}

void
rrd_clear_error(void){
    free(rrd_error);
    rrd_error = NULL;
}

char *
rrd_get_error(void){
    return rrd_error;
}











