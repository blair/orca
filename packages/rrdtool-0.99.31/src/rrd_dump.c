/*****************************************************************************
 * RRDTOOL 0.99.29 Copyright Tobias Oetiker, 1997, 1998, 1999
 *****************************************************************************
 * rrd_dump  Display a RRD
 *****************************************************************************
 * $Id: rrd_dump.c,v 1.5 1998/03/08 12:35:11 oetiker Exp oetiker $
 * $Log: rrd_dump.c,v $
 *****************************************************************************/

#include "rrd_tool.h"

int
rrd_dump(int argc, char **argv)    
{   
    int          i,ii,iii,full=0;
    time_t       now;
    char         somestring[255];
    rrd_value_t  my_cdp;

    FILE                  *in_file;
    rrd_t             rrd;


    while (1){
	static struct option long_options[] =
	{
	    {"full",      no_argument, 0, 'f'},
	    {0,0,0,0}
	};
	int option_index = 0;
	int opt;
	opt = getopt_long(argc, argv, "f", 
			  long_options, &option_index);
	if (opt == EOF)
	    break;

	switch(opt) {
	case 'f':
	    full=1;
	    break;
	case '?':
	    rrd_set_error("unknown option '%s'",argv[optind-1]);
	    return(-1);   	    
	}
    }
    
    if(optind >= argc){
	rrd_set_error("please specify an rrd");
	return(-1);   
    }
    if(rrd_open(argv[optind],&in_file,&rrd, RRD_READONLY)==-1){
	return(-1);
    }
    puts("RRD Header");
    puts("---------------------------");
    puts("");
    puts("* stat_head");
    printf("\tcookie:       '%s'\n",rrd.stat_head->cookie);
    printf("\tversion:      '%s'\n",rrd.stat_head->version);
    printf("\tfloat_cookie: %e\n",rrd.stat_head->float_cookie);
	
    printf("\tds_cnt:       %lu\n",rrd.stat_head->ds_cnt);
    printf("\trra_cnt:      %lu\n",rrd.stat_head->rra_cnt);
    printf("\tpdp_step:     %lu seconds\n",rrd.stat_head->pdp_step);

    for(i=0;i<rrd.stat_head->ds_cnt;i++){
	printf("\n* ds_def[%i]\n",i);
	printf("\tds-nam:       %s\n",rrd.ds_def[i].ds_nam);
	printf("\tdst:          %s\n",rrd.ds_def[i].dst);
	printf("\tds_mrhb:      %lu\n",rrd.ds_def[i].par[DS_mrhb_cnt].u_cnt);
	printf("\tmax_val:      %e\n",rrd.ds_def[i].par[DS_max_val].u_val);
	printf("\tmin_val:      %e\n",rrd.ds_def[i].par[DS_min_val].u_val);
    }

    for(i=0;i<rrd.stat_head->rra_cnt;i++){
	printf("\n* rra_def[%i]\n",i);
	printf("\tcf_name:      %s\n",rrd.rra_def[i].cf_nam);
	printf("\trow_cnt:      %lu\n",rrd.rra_def[i].row_cnt);
	printf("\tpdp_cnt:      %lu\n",rrd.rra_def[i].pdp_cnt);
    }
 
    printf("\n* live_head\n");
#if HAVE_STRFTIME
    strftime(somestring,200,"%Y-%m-%d %H:%M:%S",
	     localtime(&rrd.live_head->last_up));
#else
# error "Need strftime"
#endif
    printf("\tlast_up:       '%lu' %s\n",
	   rrd.live_head->last_up,somestring);

    printf("\n* pdp_prep\n");
    for(i=0;i<rrd.stat_head->ds_cnt;i++){
	printf("\n  (ds='%s')\n",rrd.ds_def[i].ds_nam);

	
	printf("\tlast_ds:      '%s'\n",rrd.pdp_prep[i].last_ds);
	printf("\tvalue:         %e\n",rrd.pdp_prep[i].scratch[PDP_val].u_val);
	printf("\tunkn_sec:      %lu seconds\n",
	       rrd.pdp_prep[i].scratch[PDP_unkn_sec_cnt].u_cnt);
    }
 
    printf("\n* cdp_prep");
    for(i=0;i<rrd.stat_head->rra_cnt;i++){
	printf("\n  (rra=%i)\n",i);
	for(ii=0;ii<rrd.stat_head->ds_cnt;ii++){
	    printf("\n    (ds=%s)\n",rrd.ds_def[ii].ds_nam);
	    printf("\tvalue:          %e\n",
		   rrd.cdp_prep[i*rrd.stat_head->ds_cnt+ii].scratch[CDP_val].u_val);
	    printf("\tunkn_pdp:       %lu pdp\n",
		   rrd.cdp_prep[i*rrd.stat_head->ds_cnt+ii].scratch[CDP_unkn_pdp_cnt].u_cnt);
	}
    } 

    for(i=0;i<rrd.stat_head->rra_cnt;i++){
	printf("\n* rra_ptr[%i]\n",i);
	printf("\tcur_row:        %lu\n",rrd.rra_ptr[i].cur_row);
    }

    if (full) {
	puts("");   
	puts("RRD Contents");
	puts("-----------------------");
	puts("");      
	for(i=0;i<rrd.stat_head->rra_cnt;i++){
	    printf("[%3i]:\n",i);
	    now = (rrd.live_head->last_up 
		   - rrd.live_head->last_up % (rrd.rra_def[i].pdp_cnt*rrd.stat_head->pdp_step)
		   - rrd.rra_ptr[i].cur_row * rrd.rra_def[i].pdp_cnt*rrd.stat_head->pdp_step);
	    for(ii=0;ii<rrd.rra_def[i].row_cnt;ii++){
		if (rrd.rra_ptr[i].cur_row==ii) {
		    printf("-> ");
		} else {
		    printf("   ");
		}
		printf("%10lu",now);
		now += rrd.rra_def[i].pdp_cnt*rrd.stat_head->pdp_step;
		if (rrd.rra_ptr[i].cur_row==ii) 
		    now -= rrd.rra_def[i].pdp_cnt*rrd.stat_head->pdp_step*rrd.rra_def[i].row_cnt;
		
		for(iii=0;iii<rrd.stat_head->ds_cnt;iii++){			 
		    fread(&my_cdp,sizeof(rrd_value_t),1,in_file);
		    
		    printf(" %12.3f",my_cdp);
		}
		printf("\n");
	    }
	}
    }
    rrd_free(&rrd);
    fclose(in_file);
    return(0);
}

