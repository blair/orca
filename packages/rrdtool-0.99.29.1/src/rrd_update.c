/*****************************************************************************
 * RRDTOOL 0.99.29 Copyright Tobias Oetiker, 1997, 1998, 1999
 *****************************************************************************
 * rrd_update.c  RRD Update Function
 *****************************************************************************
 * $Id: rrd_update.c,v 1.7 1998/03/08 12:35:11 oetiker Exp oetiker $
 * $Log: rrd_update.c,v $
 *****************************************************************************/

#include "rrd_tool.h"
#include <sys/types.h>
#include <fcntl.h>

#ifdef WIN32
 #include <sys/locking.h>
 #include <sys/stat.h>
 #include <io.h>
#else
 #include <unistd.h>
#endif


/* Prototypes */
int LockRRD(FILE *rrd_file);

/*#define DEBUG */

int 
rrd_update(int argc, char **argv)
{

    int              arg_i = 2;
    long             i,ii,iii;

    unsigned long    rra_begin;          /* byte pointer to the rra
					  * area in the rrd file.  this
					  * pointer never changes value */
    unsigned long    rra_start;          /* byte pointer to the rra
					  * area in the rrd file.  this
					  * pointer changes as each rrd is
					  * processed. */
    unsigned long    interval,
	pre_int,post_int;                /* interval between this and
					  * the last run */
    unsigned long    proc_pdp_st;        /* which pdp_st was the last
					  * to be processed */
    unsigned long    occu_pdp_st;        /* when was the pdp_st
					  * before the last update
					  * time */
    unsigned long    proc_pdp_age;       /* how old was the data in
					  * the pdp prep area when it
					  * was last updated */
    unsigned long    occu_pdp_age;       /* how long ago was the last
					  * pdp_step time */
    unsigned long    pdp_st;             /* helper for cdp_prep 
					  * processing */
    rrd_value_t      *pdp_new;           /* prepare the incoming data
					  * to be added the the
					  * existing entry */
    rrd_value_t      *pdp_temp;          /* prepare the pdp values 
					  * to be added the the
					  * cdp values */

    long             *tmpl_idx;          /* index representing the settings
					    transported by the template index */
    long             tmpl_max = 0;

    FILE             *rrd_file;
    rrd_t            rrd;
    time_t           current_time = time(NULL);
    char             **updvals;
    int              wrote_to_file = 0;
    char             *template = NULL;          

    rrd_init(&rrd);
    while (1) {
	static struct option long_options[] =
	{
	    {"template",      required_argument, 0, 't'},
	    {0,0,0,0}
	};
	int option_index = 0;
	int opt;
	opt = getopt_long(argc, argv, "t:", 
			  long_options, &option_index);
	
	if (opt == EOF)
	  break;
	
	switch(opt) {
	case 't':
	    template = optarg;
	    break;

	case '?':
	    rrd_set_error("unknown option '%s'",argv[optind-1]);
            rrd_free(&rrd);
	    return(-1);
	}
    }

    /* need at least 2 arguments: filename, data. */
    if (argc-optind < 2) {
	rrd_set_error("not enough arguments");
	return -1;
    }

    if(rrd_open(argv[optind],&rrd_file,&rrd, RRD_READWRITE)==-1){
	return -1;
    }
    rra_begin=ftell(rrd_file);
    rra_start=rra_begin;

    /* get exclusive lock to whole file.
     * lock gets removed when we close the file.
     */
    if (LockRRD(rrd_file) != 0) {
      rrd_set_error("could not lock RRD");
      rrd_free(&rrd);
      fclose(rrd_file);
      return(-1);   
    }

    if((updvals = malloc( sizeof(char*) * (rrd.stat_head->ds_cnt+1)))==NULL){
	rrd_set_error("allocating updvals pointer array");
	rrd_free(&rrd);
        fclose(rrd_file);
	return(-1);
    }

    if ((pdp_temp = malloc(sizeof(rrd_value_t)
			   *rrd.stat_head->ds_cnt))==NULL){
	rrd_set_error("allocating pdp_temp ...");
	free(updvals);
	rrd_free(&rrd);
        fclose(rrd_file);
	return(-1);
    }

    if ((tmpl_idx = malloc(sizeof(unsigned long)
			   *(rrd.stat_head->ds_cnt+1)))==NULL){
	rrd_set_error("allocating template_idx ...");
	free(pdp_temp);
	free(updvals);
	rrd_free(&rrd);
        fclose(rrd_file);
	return(-1);
    }
    /* initialize template redirector */
    for (i=0;i<=rrd.stat_head->ds_cnt;i++) tmpl_idx[i]=i;
    tmpl_max=rrd.stat_head->ds_cnt;
    if (template) {
	char *dsname;
	long temp_len;
	dsname = template;
	temp_len = strlen(template);
	tmpl_max = 0;
	for (i=0;i<=temp_len;i++) {
	    if (template[i] == ':' || template[i] =='\0') {
		template[i] = '\0';
		if ((tmpl_idx[++tmpl_max] = ds_match(&rrd,dsname)) == -1){			    free(updvals);
		    free(pdp_temp);
		    free(tmpl_idx);
		    rrd_free(&rrd);
		    fclose(rrd_file);
		    return(-1);
		}
		/* the first element is always the time */
		tmpl_idx[tmpl_max]++; 
	    }	    
	}
    }
    if ((pdp_new = malloc(sizeof(rrd_value_t)
			  *rrd.stat_head->ds_cnt))==NULL){
	rrd_set_error("allocating pdp_new ...");
	free(updvals);
	free(pdp_temp);
	free(tmpl_idx);
	rrd_free(&rrd);
        fclose(rrd_file);
	return(-1);
    }

    /* loop through the arguments. */
    for(arg_i=optind+1; arg_i<argc;arg_i++) {
	unsigned long count_colons = 0;

/* fprintf(stderr, "Handling %s\t%s\n", argv[arg_i]); */
	/* parse the update line ... the first value is the time, the
	   remaining ones are the datasources */
	/* skip any initial :'s */
	i=0;
	while (argv[arg_i][i] && argv[arg_i][i] == ':')
	    ++i;
	
	/* initialize all ds input to unknown except the first one
           which has always got to be set */
	for(ii=1;ii<=rrd.stat_head->ds_cnt;ii++)
	    updvals[ii] = "U";
	ii=0;
	updvals[ii++] = &argv[arg_i][i];
	for (;argv[arg_i][i] != '\0';++i) {
	    if (argv[arg_i][i] == ':') {
		count_colons++;
		argv[arg_i][i] = '\0';
		if (ii<=tmpl_max) {
		    updvals[tmpl_idx[ii++]] = &argv[arg_i][i+1];
		}
	    }
	}

	if (ii-1 != count_colons || ii-1 != tmpl_max) {
	    rrd_set_error("expected %lu data source readings (got %lu) from %s...",
			  tmpl_max, count_colons, argv[arg_i]);
	    break;
	}
	
        /* get the time from the reading ... handle N */
	if (strcmp(updvals[0],"N")==0){
	    current_time = time(NULL);
	} else {
	    current_time = atol(updvals[0]);
	}
	
	if(current_time <= rrd.live_head->last_up){
	    rrd_set_error("illegal attempt to update using time %ld when "
			  "last update time is %ld (minimum one second step ",
			  current_time, rrd.live_head->last_up);
	    break;
	}
	
	
	/* seek to the beginning of the rrd's */
	if(fseek(rrd_file, rra_begin, SEEK_SET) != 0) {
	    rrd_set_error("seek error in rrd");
	    break;
	}
	
	rra_start = rra_begin;

	/* when was the current pdp started */
	proc_pdp_age = rrd.live_head->last_up % rrd.stat_head->pdp_step;
	proc_pdp_st = rrd.live_head->last_up - proc_pdp_age;

	/* when did the last pdp_st occur */
	occu_pdp_age = current_time % rrd.stat_head->pdp_step;
	occu_pdp_st = current_time - occu_pdp_age;
	interval = current_time - rrd.live_head->last_up;
    
	if (occu_pdp_st > proc_pdp_st){
	    /* OK we passed the pdp_st moment*/
	    pre_int =  occu_pdp_st - rrd.live_head->last_up; /* how much of the input data
							      * occurred before the latest
							      * pdp_st moment*/
	    post_int = occu_pdp_age;			     /* how much after it */
	} else {
	    pre_int = interval;
	    post_int = 0;
	}

#ifdef DEBUG
	printf(
	       "proc_pdp_age %lu\t"
	       "proc_pdp_st %lu\t" 
	       "occu_pfp_age %lu\t" 
	       "occu_pdp_st %lu\t"
	       "int %lu\t"
	       "pre_int %lu\t"
	       "post_int %lu\n", proc_pdp_age, proc_pdp_st, 
		occu_pdp_age, occu_pdp_st,
	       interval, pre_int, post_int);
#endif
    
	/* process the data sources and update the pdp_prep 
	 * area accordingly */
	for(i=0;i<rrd.stat_head->ds_cnt;i++){
	    enum dst_en dst_idx;
	    dst_idx= dst_conv(rrd.ds_def[i].dst);
	    if((updvals[i+1][0] != 'U') &&
	       rrd.ds_def[i].par[DS_mrhb_cnt].u_cnt >= interval) {
		/* the data source type defines how to process the data */
		/* pdp_temp contains rate * time ... eg the bytes
		 * transferred during the interval. Doing it this way saves
		 * a lot of math operations */
		

		switch(dst_idx){
		case DST_COUNTER:
		case DST_DERIVE:
		    if(rrd.pdp_prep[i].last_ds[0] != 'U'){
			pdp_new[i]= rrd_diff(updvals[i+1],rrd.pdp_prep[i].last_ds);
			if(dst_idx == DST_COUNTER) {
				/* simple overflow catcher sugestet by andres kroonmaa */
				/* this will fail terribly for non 32 or 64 bit counters ... */
				/* are there any others in SNMP land ? */
			    if (pdp_new[i] < (double)0.0 ) 
				pdp_new[i] += (double)4294967296.0 ;  /* 2^32 */
			    if (pdp_new[i] < (double)0.0 ) 
				pdp_new[i] += (double)18446744069414584320.0; /* 2^64-2^32 */;
			}
		    }
			else
			    pdp_new[i]= DNAN;		
		    break;
		case DST_ABSOLUTE:
		    pdp_new[i]= atof(updvals[i+1]);		
		    break;
		case DST_GAUGE:
		    pdp_new[i] = atof(updvals[i+1]) * interval;
		    break;
		default:
		    rrd_set_error("rrd contains and DS type : '%s'",
				  rrd.ds_def[i].dst);
		    break;
		}
		/* break out of this for loop if the error string is set */
		if (rrd_test_error())
		    break;
	    } else {
		/* no news is news all the same */
		pdp_new[i] = DNAN;
	    }
	    
	    /* make a copy of the command line argument for the next run */
#ifdef DEBUG
	    fprintf(stderr,
		    "prep ds[%lu]\t"
		    "last_arg '%s'\t"
		    "this_arg '%s'\t"
		    "pdp_new %10.2f\n",
		    i,
		    rrd.pdp_prep[i].last_ds,
		    updvals[i+1], pdp_new[i]);
#endif
	    if(dst_idx == DST_COUNTER || dst_idx == DST_DERIVE){
		strncpy(rrd.pdp_prep[i].last_ds,
			updvals[i+1],LAST_DS_LEN-1);
		rrd.pdp_prep[i].last_ds[LAST_DS_LEN]=0;
	    }
	}
	/* break out of the argument parsing loop if the error_string is set */
	if (rrd_test_error())
	    break;

	/* has a pdp_st moment occurred since the last run ? */

	if (proc_pdp_st == occu_pdp_st){
	    /* no we have not passed a pdp_st moment. therefore update is simple */

	    for(i=0;i<rrd.stat_head->ds_cnt;i++){
		if(isnan(pdp_new[i]))
		    rrd.pdp_prep[i].scratch[PDP_unkn_sec_cnt].u_cnt += interval;
		else
		    rrd.pdp_prep[i].scratch[PDP_val].u_val+= pdp_new[i];
#ifdef DEBUG
		fprintf(stderr,
			"NO PDP  ds[%lu]\t"
			"value %10.2f\t"
			"unkn_sec %5lu\n",
			i,
			rrd.pdp_prep[i].scratch[PDP_val].u_val,
			rrd.pdp_prep[i].scratch[PDP_unkn_sec_cnt].u_cnt);
#endif
	    }	
	} else {
	    /* an pdp_st has occurred. */

	    /* in pdp_prep[].scratch[PDP_val].u_val we have collected rate*seconds which 
	     * occurred up to the last run. 	   
	    pdp_new[] contains rate*seconds from the latest run.
	    pdp_temp[] will contain the rate for cdp */


	    for(i=0;i<rrd.stat_head->ds_cnt;i++){
		/* update pdp_prep to the current pdp_st */
		if(isnan(pdp_new[i]))
		    rrd.pdp_prep[i].scratch[PDP_unkn_sec_cnt].u_cnt += pre_int;
		else
		    rrd.pdp_prep[i].scratch[PDP_val].u_val += 
			pdp_new[i]/(double)interval*(double)pre_int;

		/* if too much of the pdp_prep is unknown we dump it */
		if ((rrd.pdp_prep[i].scratch[PDP_unkn_sec_cnt].u_cnt 
		     > rrd.ds_def[i].par[DS_mrhb_cnt].u_cnt) ||
		    (occu_pdp_st-proc_pdp_st <= 
		     rrd.pdp_prep[i].scratch[PDP_unkn_sec_cnt].u_cnt)) {
		    pdp_temp[i] = DNAN;
		} else {
		    pdp_temp[i] = rrd.pdp_prep[i].scratch[PDP_val].u_val
			/ (double)( occu_pdp_st
				   - proc_pdp_st
				   - rrd.pdp_prep[i].scratch[PDP_unkn_sec_cnt].u_cnt);
		}
		/* make pdp_prep ready for the next run */
		if(isnan(pdp_new[i])){
		    rrd.pdp_prep[i].scratch[PDP_unkn_sec_cnt].u_cnt = post_int;
		    rrd.pdp_prep[i].scratch[PDP_val].u_val = 0.0;
		} else {
		    rrd.pdp_prep[i].scratch[PDP_unkn_sec_cnt].u_cnt = 0;
		    rrd.pdp_prep[i].scratch[PDP_val].u_val = 
			pdp_new[i]/(double)interval*(double)post_int;
		}
		/* make sure pdp_temp is neither too large or too small
		 * if any of these occur it becomes unknown ...
		 * sorry folks ... */
		if (! isnan(pdp_temp[i]) && 
		   	((! isnan(rrd.ds_def[i].par[DS_max_val].u_val) &&
		           pdp_temp[i] > rrd.ds_def[i].par[DS_max_val].u_val) ||
		         (! isnan(rrd.ds_def[i].par[DS_min_val].u_val) &&
		           pdp_temp[i] < rrd.ds_def[i].par[DS_min_val].u_val))) {
		    pdp_temp[i] = DNAN;
		}
#ifdef DEBUG
		fprintf(stderr,
			"PDP UPD ds[%lu]\t"
			"pdp_temp %10.2f\t"
			"new_prep %10.2f\t"
			"new_unkn_sec %5lu\n",
			i, pdp_temp[i],
			rrd.pdp_prep[i].scratch[PDP_val].u_val,
			rrd.pdp_prep[i].scratch[PDP_unkn_sec_cnt].u_cnt);
#endif
	    }


	    /* now we have to integrate this data into the cdp_prep areas */
	    /* going through the round robin archives */
	    for(i = 0;
		i < rrd.stat_head->rra_cnt;
		i++){
		enum cf_en current_cf = cf_conv(rrd.rra_def[i].cf_nam);
		/* going through all pdp_st moments which have occurred 
		 * since the last run */
		for(pdp_st  = proc_pdp_st+rrd.stat_head->pdp_step; 
		    pdp_st <= occu_pdp_st; 
		    pdp_st += rrd.stat_head->pdp_step){

#ifdef DEBUG
		    fprintf(stderr,"RRA %lu STEP %lu\n",i,pdp_st);
#endif

		    if((pdp_st %
			(rrd.rra_def[i].pdp_cnt*rrd.stat_head->pdp_step)) == 0){

			/* later on the cdp_prep values will be transferred to
			 * the rra.  we want to be in the right place. */
			rrd.rra_ptr[i].cur_row++;
			if (rrd.rra_ptr[i].cur_row >= rrd.rra_def[i].row_cnt)
			    /* oops ... we have to wrap the beast ... */
			    rrd.rra_ptr[i].cur_row=0;			
#ifdef DEBUG
			fprintf(stderr,"  -- RRA Preseek %ld\n",ftell(rrd_file));
#endif

			if(fseek(rrd_file, 
				 (rra_start + (rrd.stat_head->ds_cnt
					       *rrd.rra_ptr[i].cur_row
					       * sizeof(rrd_value_t))), SEEK_SET) != 0){
			    rrd_set_error("seek error in rrd");
			    break;
			}
#ifdef DEBUG
			fprintf(stderr,"  -- RRA Postseek %ld\n",ftell(rrd_file));
#endif
		    }

		    for(ii = 0;
			ii < rrd.stat_head->ds_cnt;
			ii++){
			iii=i*rrd.stat_head->ds_cnt+ii;
		    
			/* the contents of cdp_prep[].scratch[CDP_val].u_val depends
			 * on the consolidation function ! */
		    
			if (isnan(pdp_temp[ii])){    /* pdp is unknown */
			    rrd.cdp_prep[iii].scratch[CDP_unkn_pdp_cnt].u_cnt++;
#ifdef DEBUG
			    fprintf(stderr,"  ** UNKNOWN ADD %lu\n",
				    rrd.cdp_prep[iii].scratch[CDP_unkn_pdp_cnt].u_cnt);
#endif
			} else {
			    if (isnan(rrd.cdp_prep[iii].scratch[CDP_val].u_val)){
				/* cdp_prep is unknown when it does not
				 * yet contain data. It can not be zero for
				 * things like mim and max consolidation
				 * functions */
#ifdef DEBUG
				fprintf(stderr,"  ** INIT CDP %e\n", pdp_temp[ii]);
#endif
				rrd.cdp_prep[iii].scratch[CDP_val].u_val = pdp_temp[ii];
			    }
			    else {
				switch (current_cf){
				    case CF_AVERAGE:				
					rrd.cdp_prep[iii].scratch[CDP_val].u_val+=pdp_temp[ii];
#ifdef DEBUG
					fprintf(stderr,"  ** AVERAGE %e\n", 
						rrd.cdp_prep[iii].scratch[CDP_val].u_val);
#endif
					break;    
				    case CF_MINIMUM:
					if (pdp_temp[ii] < rrd.cdp_prep[iii].scratch[CDP_val].u_val)
					    rrd.cdp_prep[iii].scratch[CDP_val].u_val = pdp_temp[ii];
#ifdef DEBUG
					fprintf(stderr,"  ** MINIMUM %e\n", 
						rrd.cdp_prep[iii].scratch[CDP_val].u_val);
#endif
					break;
				    case CF_MAXIMUM:
					if (pdp_temp[ii] > rrd.cdp_prep[iii].scratch[CDP_val].u_val)
					    rrd.cdp_prep[iii].scratch[CDP_val].u_val = pdp_temp[ii];
#ifdef DEBUG
					fprintf(stderr,"  ** MAXIMUM %e\n", 
						rrd.cdp_prep[iii].scratch[CDP_val].u_val);
#endif
					break;
				    case CF_LAST:
					rrd.cdp_prep[iii].scratch[CDP_val].u_val=pdp_temp[ii];
#ifdef DEBUG
					fprintf(stderr,"  ** LAST %e\n", 
						rrd.cdp_prep[iii].scratch[CDP_val].u_val);
#endif
					break;    
				    default:
					rrd_set_error("Unknown cf %s",
						      rrd.rra_def[i].cf_nam);
					break;
				}
			    }
			}


			/* is the data in the cdp_prep ready to go into
			 * its rra ? */
			if((pdp_st % 
			    (rrd.rra_def[i].pdp_cnt*rrd.stat_head->pdp_step)) == 0){

			    /* prepare cdp_pref for its transition to the rra. */
			    if (rrd.cdp_prep[iii].scratch[CDP_unkn_pdp_cnt].u_cnt 
				> rrd.rra_def[i].pdp_cnt*
				rrd.rra_def[i].par[RRA_cdp_xff_val].u_val)
				/* to much of the cdp_prep is unknown ... */
				rrd.cdp_prep[iii].scratch[CDP_val].u_val = DNAN;
			    else if (current_cf == CF_AVERAGE){
				/* for a real average we have to divide
				 * the sum we built earlier on. While ignoring
				 * the unknown pdps */
				rrd.cdp_prep[iii].scratch[CDP_val].u_val 
					/= (rrd.rra_def[i].pdp_cnt
					    -rrd.cdp_prep[iii].scratch[CDP_unkn_pdp_cnt].u_cnt);
			    }
			    /* we can write straight away, because we are
			     * already in the right place ... */

#ifdef DEBUG
			    fprintf(stderr,"  -- RRA WRITE VALUE %e, at %ld\n",
				    rrd.cdp_prep[iii].scratch[CDP_val].u_val,ftell(rrd_file));
#endif

			    if(fwrite(&(rrd.cdp_prep[iii].scratch[CDP_val].u_val),
				      sizeof(rrd_value_t),1,rrd_file) != 1){
				rrd_set_error("writing rrd");
				break;
			    }
			    wrote_to_file = 1;

#ifdef DEBUG
			    fprintf(stderr,"  -- RRA WROTE new at %ld\n",ftell(rrd_file));
#endif

			    /* make cdp_prep ready for the next run */
			    rrd.cdp_prep[iii].scratch[CDP_val].u_val = DNAN;
			    rrd.cdp_prep[iii].scratch[CDP_unkn_pdp_cnt].u_cnt = 0;
			}
		    }
		    /* break out of this loop if error_string has been set */
		    if (rrd_test_error())
			break;
		}
		/* break out of this loop if error_string has been set */
		if (rrd_test_error())
		    break;
		/* to be able to position correctly in the next rra w move
		 * the rra_start pointer on to the next rra */
		rra_start += rrd.rra_def[i].row_cnt
			*rrd.stat_head->ds_cnt*sizeof(rrd_value_t);

	    }
	    /* break out of the argument parsing loop if error_string is set */
	    if (rrd_test_error())
		break;
	}
	rrd.live_head->last_up = current_time;
    }

    /* if we got here and if there is an error and if the file has not been
     * written to, then close things up and return. */
    if (rrd_test_error()) {
	free(updvals);
	free(tmpl_idx);
	rrd_free(&rrd);
	free(pdp_temp);
	free(pdp_new);
        fclose(rrd_file);
	return(-1);
    }

    /* aargh ... that was tough ... so many loops ... anyway, its done.
     * we just need to write back the live header portion now*/

    if (fseek(rrd_file, (sizeof(stat_head_t)
			 + sizeof(ds_def_t)*rrd.stat_head->ds_cnt 
			 + sizeof(rra_def_t)*rrd.stat_head->rra_cnt),
	      SEEK_SET) != 0) {
	rrd_set_error("seek rrd for live header writeback");
	free(updvals);
	free(tmpl_idx);
	rrd_free(&rrd);
	free(pdp_temp);
	free(pdp_new);
        fclose(rrd_file);
	return(-1);
    }

    if(fwrite( rrd.live_head,
	       sizeof(live_head_t), 1, rrd_file) != 1){
	rrd_set_error("fwrite live_head to rrd");
	free(updvals);
	rrd_free(&rrd);
	free(tmpl_idx);
	free(pdp_temp);
	free(pdp_new);
        fclose(rrd_file);
	return(-1);
    }

    if(fwrite( rrd.pdp_prep,
	       sizeof(pdp_prep_t),
	       rrd.stat_head->ds_cnt, rrd_file) != rrd.stat_head->ds_cnt){
	rrd_set_error("ftwrite pdp_prep to rrd");
	free(updvals);
	rrd_free(&rrd);
	free(tmpl_idx);
	free(pdp_temp);
	free(pdp_new);
        fclose(rrd_file);
	return(-1);
    }

    if(fwrite( rrd.cdp_prep,
	       sizeof(cdp_prep_t),
	       rrd.stat_head->rra_cnt *rrd.stat_head->ds_cnt, rrd_file) 
       != rrd.stat_head->rra_cnt *rrd.stat_head->ds_cnt){

	rrd_set_error("ftwrite cdp_prep to rrd");
	free(updvals);
	free(tmpl_idx);
	rrd_free(&rrd);
	free(pdp_temp);
	free(pdp_new);
        fclose(rrd_file);
	return(-1);
    }

    if(fwrite( rrd.rra_ptr,
	       sizeof(rra_ptr_t), 
	       rrd.stat_head->rra_cnt,rrd_file) != rrd.stat_head->rra_cnt){
	rrd_set_error("fwrite rra_ptr to rrd");
	free(updvals);
	free(tmpl_idx);
	rrd_free(&rrd);
	free(pdp_temp);
	free(pdp_new);
        fclose(rrd_file);
	return(-1);
    }

    /* OK now close the files and free the memory */
    if(fclose(rrd_file) != 0){
	rrd_set_error("closing rrd");
	free(updvals);
	free(tmpl_idx);
	rrd_free(&rrd);
	free(pdp_temp);
	free(pdp_new);
	return(-1);
    }

    rrd_free(&rrd);
    free(updvals);
    free(tmpl_idx);
    free(pdp_new);
    free(pdp_temp);
    return(0);
}

/*
 * get exclusive lock to whole file.
 * lock gets removed when we close the file
 *
 * returns 0 on success
 */
int
LockRRD(FILE *rrdfile)
{
    int	rrd_fd;		/* File descriptor for RRD */
    int			stat;

    rrd_fd = fileno(rrdfile);

	{
#ifndef WIN32    
		struct flock	lock;
    lock.l_type = F_WRLCK;    /* exclusive write lock */
    lock.l_len = 0;	      /* whole file */
    lock.l_start = 0;	      /* start of file */
    lock.l_whence = SEEK_SET;   /* end of file */

    stat = fcntl(rrd_fd, F_SETLK, &lock);
#else
		struct _stat st;

		if ( _fstat( rrd_fd, &st ) == 0 ) {
			stat = _locking ( rrd_fd, _LK_NBLCK, st.st_size );
		} else {
			stat = -1;
		}
#endif
	}

    return(stat);
}
