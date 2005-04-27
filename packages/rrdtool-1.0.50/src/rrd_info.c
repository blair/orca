/*****************************************************************************
 * RRDtool 1.0.50  Copyright Tobias Oetiker, 1997 - 2000
 *****************************************************************************
 * rrd_info  Get Information about the configuration of an RRD
 *****************************************************************************/

#include "rrd_tool.h"
#include <stdarg.h>

/* proto */
static char * sprintf_alloc(char *, ...);
static info_t *push(info_t *, char *, enum info_type, infoval);
info_t *rrd_info(int, char **);

/* allocate memory for string */
static char *
sprintf_alloc(char *fmt, ...) {
#ifdef HAVE_VSNPRINTF    
    int maxlen = 50;
#else
    int maxlen = 1000;
#endif
    char *str = NULL;
    va_list argp;
    str = malloc(sizeof(char)*(strlen(fmt)+maxlen));
    if (str != NULL) {
	va_start(argp, fmt);
#ifdef HAVE_VSNPRINTF
	vsnprintf(str, maxlen-1, fmt, argp);
#else
	vsprintf(str, fmt, argp);
#endif
    }
    va_end(argp);
    return str;
}

static info_t 
*push(info_t *info, char *key, enum info_type type, infoval value){
    info_t *next;
    next = malloc(sizeof(*next));
    next->next = (info_t *) 0;
    if( info )
	info->next = next;
    next->type = type;
    next->key  = key;
    switch (type) {
    case RD_I_VAL:
	next->value.u_val = value.u_val;
	break;
    case RD_I_CNT:
	next->value.u_cnt = value.u_cnt;
	break;
    case RD_I_STR:
	next->value.u_str = malloc(sizeof(char)*(strlen(value.u_str)+1));
	strcpy(next->value.u_str,value.u_str);
	break;
    }
    return(next);
}

  
info_t *
rrd_info(int argc, char **argv) {   
    int          i,ii=0;
    FILE         *in_file;
    rrd_t        rrd;
    info_t       *data,*cd;
    infoval      info;

    if(rrd_open(argv[1],&in_file,&rrd, RRD_READONLY)==-1){
	return(NULL);
    }
    fclose(in_file);

    info.u_str=argv[1];
    cd=push(NULL,sprintf_alloc("filename"),    RD_I_STR, info);
    data=cd;

    info.u_str=rrd.stat_head->version;
    cd=push(cd,sprintf_alloc("rrd_version"),    RD_I_STR, info);

    info.u_cnt=rrd.stat_head->pdp_step;
    cd=push(cd,sprintf_alloc("step"),       RD_I_CNT, info);

    info.u_cnt=rrd.live_head->last_up;
    cd=push(cd,sprintf_alloc("last_update"), RD_I_CNT, info);

    for(i=0;i<rrd.stat_head->ds_cnt;i++){

	info.u_str=rrd.ds_def[i].dst;
	cd=push(cd,sprintf_alloc("ds[%s].type",             rrd.ds_def[i].ds_nam), RD_I_STR, info);

	info.u_cnt=rrd.ds_def[i].par[DS_mrhb_cnt].u_cnt;
	cd=push(cd,sprintf_alloc("ds[%s].minimal_heartbeat",rrd.ds_def[i].ds_nam), RD_I_CNT, info);

	info.u_val=rrd.ds_def[i].par[DS_min_val].u_val;
	cd=push(cd,sprintf_alloc("ds[%s].min",              rrd.ds_def[i].ds_nam), RD_I_VAL, info);
	
	info.u_val=rrd.ds_def[i].par[DS_max_val].u_val;
	cd=push(cd,sprintf_alloc("ds[%s].max",              rrd.ds_def[i].ds_nam), RD_I_VAL, info);
	
	info.u_str=rrd.pdp_prep[i].last_ds;
	cd=push(cd,sprintf_alloc("ds[%s].last_ds",          rrd.ds_def[i].ds_nam), RD_I_STR, info);

	info.u_val=rrd.pdp_prep[i].scratch[PDP_val].u_val;
        cd=push(cd,sprintf_alloc("ds[%s].value",            rrd.ds_def[i].ds_nam), RD_I_VAL, info);

	info.u_cnt=rrd.pdp_prep[i].scratch[PDP_unkn_sec_cnt].u_cnt;
	cd=push(cd,sprintf_alloc("ds[%s].unknown_sec",      rrd.ds_def[i].ds_nam), RD_I_CNT, info);
    }

    for(i=0;i<rrd.stat_head->rra_cnt;i++){
	info.u_str=rrd.rra_def[i].cf_nam;
	cd=push(cd,sprintf_alloc("rra[%d].cf",         i),  RD_I_STR,   info);

	info.u_cnt=rrd.rra_def[i].row_cnt;
	cd=push(cd,sprintf_alloc("rra[%d].rows",i),  RD_I_CNT,   info);

	info.u_cnt=rrd.rra_def[i].pdp_cnt;
	cd=push(cd,sprintf_alloc("rra[%d].pdp_per_row",i),  RD_I_CNT,   info);

        info.u_val=rrd.rra_def[i].par[RRA_cdp_xff_val].u_val;
        cd=push(cd,sprintf_alloc("rra[%d].xff",i),  RD_I_VAL,   info);
        
	for(ii=0;ii<rrd.stat_head->ds_cnt;ii++){
	    info.u_val=rrd.cdp_prep[i*rrd.stat_head->ds_cnt+ii].scratch[CDP_val].u_val;
	    cd=push(cd,sprintf_alloc("rra[%d].cdp_prep[%d].value",i,ii), RD_I_VAL, info);

	    info.u_cnt=rrd.cdp_prep[i*rrd.stat_head->ds_cnt+ii].scratch[CDP_unkn_pdp_cnt].u_cnt;
	    cd=push(cd,sprintf_alloc("rra[%d].cdp_prep[%d].unknown_datapoints",i,ii), RD_I_CNT, info);
        }
    }
    rrd_free(&rrd);
    return(data);

}





