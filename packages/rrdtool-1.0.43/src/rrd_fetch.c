/*****************************************************************************
 * RRDtool 1.0.43  Copyright Tobias Oetiker, 1997 - 2000
 *****************************************************************************
 * rrd_fetch.c  read date from an rrd to use for further processing
 *****************************************************************************
 * $Id: rrd_fetch.c,v 1.1.1.1 2002/02/26 10:21:37 oetiker Exp $
 * $Log: rrd_fetch.c,v $
 * Revision 1.1.1.1  2002/02/26 10:21:37  oetiker
 * Intial Import
 *
 *****************************************************************************/

#include "rrd_tool.h"
/*#define DEBUG*/

int
rrd_fetch(int argc, 
	  char **argv,
	  time_t         *start,
	  time_t         *end,       /* which time frame do you want ?
				      * will be changed to represent reality */
	  unsigned long  *step,      /* which stepsize do you want? 
				      * will be changed to represent reality */
	  unsigned long  *ds_cnt,    /* number of data sources in file */
	  char           ***ds_namv,   /* names of data sources */
	  rrd_value_t    **data)     /* two dimensional array containing the data */
{


    long     step_tmp =1;
    time_t   start_tmp=0, end_tmp=0;
    enum     cf_en cf_idx;

    struct time_value start_tv, end_tv;
    char     *parsetime_error = NULL;

    /* init start and end time */
    parsetime("end-24h", &start_tv);
    parsetime("now", &end_tv);

    while (1){
	static struct option long_options[] =
	{
	    {"resolution",      required_argument, 0, 'r'},
	    {"start",      required_argument, 0, 's'},
	    {"end",      required_argument, 0, 'e'},
	    {0,0,0,0}
	};
	int option_index = 0;
	int opt;
	opt = getopt_long(argc, argv, "r:s:e:", 
			  long_options, &option_index);

	if (opt == EOF)
	    break;

	switch(opt) {
	case 's':
            if ((parsetime_error = parsetime(optarg, &start_tv))) {
                rrd_set_error( "start time: %s", parsetime_error );
                return -1;
	    }
	    break;
	case 'e':
            if ((parsetime_error = parsetime(optarg, &end_tv))) {
                rrd_set_error( "end time: %s", parsetime_error );
                return -1;
	    }
	    break;
	case 'r':
	    step_tmp = atol(optarg);
	    break;
	case '?':
	    rrd_set_error("unknown option '-%c'",optopt);
	    return(-1);
	}
    }

    
    if (proc_start_end(&start_tv,&end_tv,&start_tmp,&end_tmp) == -1){
	return -1;
    }  

    
    if (start_tmp < 3600*24*365*10){
	rrd_set_error("the first entry to fetch should be after 1980");
	return(-1);
    }
    
    if (end_tmp < start_tmp) {
	rrd_set_error("start (%ld) should be less than end (%ld)", start_tmp, end_tmp);
	return(-1);
    }
    
    *start = start_tmp;
    *end = end_tmp;

    if (step_tmp < 1) {
	rrd_set_error("step must be >= 1 second");
	return -1;
    }
    *step = step_tmp;
    
    if (optind + 1 >= argc){
	rrd_set_error("not enough arguments");
	return -1;
    }
    
    if ((cf_idx=cf_conv(argv[optind+1])) == -1 ){
	return -1;
    }

    if (rrd_fetch_fn(argv[optind],cf_idx,start,end,step,ds_cnt,ds_namv,data) == -1)
	return(-1);
    return (0);
}

int
rrd_fetch_fn(
    char           *filename,  /* name of the rrd */
    enum cf_en     cf_idx,         /* which consolidation function ?*/
    time_t         *start,
    time_t         *end,       /* which time frame do you want ?
			        * will be changed to represent reality */
    unsigned long  *step,      /* which stepsize do you want? 
				* will be changed to represent reality */
    unsigned long  *ds_cnt,    /* number of data sources in file */
    char           ***ds_namv,   /* names of data_sources */
    rrd_value_t    **data)     /* two dimensional array containing the data */
{
    long           i,ii;
    FILE           *in_file;
    time_t         cal_start,cal_end, rra_start_time,rra_end_time;
    long  best_full_rra=0, best_part_rra=0, chosen_rra=0, rra_pointer=0;
    long  best_step_diff=0, tmp_step_diff=0, tmp_match=0, best_match=0;
    long  full_match, rra_base;
    long           start_offset, end_offset;
    int            first_full = 1;
    int            first_part = 1;
    rrd_t     rrd;
    rrd_value_t    *data_ptr;
    unsigned long  rows;

    if(rrd_open(filename,&in_file,&rrd, RRD_READONLY)==-1)
	return(-1);
    
    /* when was the realy last update of this file ? */

    if (((*ds_namv) = (char **) malloc(rrd.stat_head->ds_cnt * sizeof(char*)))==NULL){
	rrd_set_error("malloc fetch ds_namv array");
	rrd_free(&rrd);
	fclose(in_file);
	return(-1);
    }
    
    for(i=0;i<rrd.stat_head->ds_cnt;i++){
	if ((((*ds_namv)[i]) = malloc(sizeof(char) * DS_NAM_SIZE))==NULL){
	    rrd_set_error("malloc fetch ds_namv entry");
	    rrd_free(&rrd);
	    free(*ds_namv);
	    fclose(in_file);
	    return(-1);
	}
	strncpy((*ds_namv)[i],rrd.ds_def[i].ds_nam,DS_NAM_SIZE-1);
	(*ds_namv)[i][DS_NAM_SIZE-1]='\0';

    }
    
    /* find the rra which best matches the requirements */
    for(i=0;i<rrd.stat_head->rra_cnt;i++){
	if(cf_conv(rrd.rra_def[i].cf_nam) == cf_idx){
	    
	       
	    cal_end = (rrd.live_head->last_up - (rrd.live_head->last_up 
			  % (rrd.rra_def[i].pdp_cnt 
			     * rrd.stat_head->pdp_step)));
	    cal_start = (cal_end 
			 - (rrd.rra_def[i].pdp_cnt 
			    * rrd.rra_def[i].row_cnt
			    * rrd.stat_head->pdp_step));

            /* we need step difference in either full or partial case */
   	    tmp_step_diff = labs(*step - (rrd.stat_head->pdp_step
					 * rrd.rra_def[i].pdp_cnt));
	    full_match = *end -*start;
	    /* best full match */
	    if(cal_end >= *end 
	       && cal_start <= *start){
		if (first_full || (tmp_step_diff < best_step_diff)){
		    first_full=0;
		    best_step_diff = tmp_step_diff;
		    best_full_rra=i;
		} 
		
	    } else {
		/* best partial match */
		tmp_match = full_match;
		if (cal_start>*start)
		    tmp_match -= (cal_start-*start);
		if (cal_end<*end)
		    tmp_match -= (*end-cal_end);		
                if (first_part ||
                    (best_match < tmp_match) ||
                    (best_match == tmp_match && 
                     tmp_step_diff < best_step_diff)){ 
		    first_part=0;
		    best_match = tmp_match;
		    best_step_diff = tmp_step_diff;
		    best_part_rra =i;
		} 
	    }
	}
    }

    /* lets see how the matching went. */
    
    if (first_full==0)
	chosen_rra = best_full_rra;
    else if (first_part==0)
	chosen_rra = best_part_rra;
    else {
	rrd_set_error("the RRD does not contain an RRA matching the chosen CF");
	rrd_free(&rrd);
	fclose(in_file);
	return(-1);
    }
	
    /* set the wish parameters to their real values */
    
    *step = rrd.stat_head->pdp_step * rrd.rra_def[chosen_rra].pdp_cnt;
    *start -= (*start % *step);
    if (*end % *step) *end += (*step - *end % *step);
    rows = (*end - *start) / *step +1;

#ifdef DEBUG
    fprintf(stderr,"start %lu end %lu step %lu rows  %lu\n",
	    *start,*end,*step,rows);
#endif

    *ds_cnt =   rrd.stat_head->ds_cnt; 
    if (((*data) = malloc(*ds_cnt * rows * sizeof(rrd_value_t)))==NULL){
	rrd_set_error("malloc fetch data area");
	for (i=0;i<*ds_cnt;i++)
	      free((*ds_namv)[i]);
	free(*ds_namv);
	rrd_free(&rrd);
	fclose(in_file);
	return(-1);
    }
    
    data_ptr=(*data);
    
    /* find base address of rra */
    rra_base=ftell(in_file);
    for(i=0;i<chosen_rra;i++)
	rra_base += ( *ds_cnt
		      * rrd.rra_def[i].row_cnt
		      * sizeof(rrd_value_t));

    /* find start and end offset */
    rra_end_time = (rrd.live_head->last_up 
		    - (rrd.live_head->last_up % *step));
    rra_start_time = (rra_end_time
		 - ( *step * (rrd.rra_def[chosen_rra].row_cnt-1)));
    start_offset = (long)(*start - rra_start_time) / (long)*step;
    end_offset = (long)(rra_end_time - *end ) / (long)*step; 
#ifdef DEBUG
    fprintf(stderr,"rra_start %lu, rra_end %lu, start_off %li, end_off %li\n",
	    rra_start_time,rra_end_time,start_offset,end_offset);
#endif

    /* fill the gap at the start if needs be */

    if (start_offset <= 0)
	rra_pointer = rrd.rra_ptr[chosen_rra].cur_row+1;
    else 
	rra_pointer = rrd.rra_ptr[chosen_rra].cur_row+1+start_offset;
    
    if(fseek(in_file,(rra_base 
		   + (rra_pointer
		      * *ds_cnt
		      * sizeof(rrd_value_t))),SEEK_SET) != 0){
	rrd_set_error("seek error in RRA");
	for (i=0;i<*ds_cnt;i++)
	      free((*ds_namv)[i]);
	free(*ds_namv);
	rrd_free(&rrd);
	free(*data);
	*data = NULL;
	fclose(in_file);
	return(-1);

    }
#ifdef DEBUG
    fprintf(stderr,"First Seek: rra_base %lu rra_pointer %lu\n",
	    rra_base, rra_pointer);
#endif
    /* step trough the array */

    for (i=start_offset;
	 i<(long)(rrd.rra_def[chosen_rra].row_cnt-end_offset);
	 i++){
	/* no valid data yet */
	if (i<0) {
#ifdef DEBUG
	    fprintf(stderr,"pre fetch %li -- ",i);
#endif
	    for(ii=0;ii<*ds_cnt;ii++){
		*(data_ptr++) = DNAN;
#ifdef DEBUG
		fprintf(stderr,"%10.2f ",*(data_ptr-1));
#endif
	    }
	} 
	/* past the valid data area */
	else if (i>=rrd.rra_def[chosen_rra].row_cnt) {
#ifdef DEBUG
	    fprintf(stderr,"post fetch %li -- ",i);
#endif
	    for(ii=0;ii<*ds_cnt;ii++){
		*(data_ptr++) = DNAN;
#ifdef DEBUG
		fprintf(stderr,"%10.2f ",*(data_ptr-1));
#endif
	    }
	} else {
	    /* OK we are inside the valid area but the pointer has to 
	     * be wrapped*/
	    if (rra_pointer >= rrd.rra_def[chosen_rra].row_cnt) {
		rra_pointer -= rrd.rra_def[chosen_rra].row_cnt;
		if(fseek(in_file,(rra_base+rra_pointer
			       * *ds_cnt
			       * sizeof(rrd_value_t)),SEEK_SET) != 0){
		    rrd_set_error("wrap seek in RRA did fail");
		    for (ii=0;ii<*ds_cnt;ii++)
			free((*ds_namv)[ii]);
		    free(*ds_namv);
		    rrd_free(&rrd);
		    free(*data);
		    *data = NULL;
		    fclose(in_file);
		    return(-1);
		}
#ifdef DEBUG
		fprintf(stderr,"wrap seek ...\n");
#endif	    
	    }
	    
	    if(fread(data_ptr,
		     sizeof(rrd_value_t),
		     *ds_cnt,in_file) != rrd.stat_head->ds_cnt){
		rrd_set_error("fetching cdp from rra");
		for (ii=0;ii<*ds_cnt;ii++)
		    free((*ds_namv)[ii]);
		free(*ds_namv);
		rrd_free(&rrd);
		free(*data);
		*data = NULL;
		fclose(in_file);
		return(-1);
	    }
#ifdef DEBUG
	    fprintf(stderr,"post fetch %li -- ",i);
	    for(ii=0;ii<*ds_cnt;ii++)
		fprintf(stderr,"%10.2f ",*(data_ptr+ii));
#endif
	    data_ptr += *ds_cnt;
	    rra_pointer ++;
	}
#ifdef DEBUG
	    fprintf(stderr,"\n");
#endif	    
	
    }
    rrd_free(&rrd);
    fclose(in_file);
    return(0);
}
