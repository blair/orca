/****************************************************************************
 * RRDtool 1.0.46  Copyright Tobias Oetiker, 1997 - 2000
 ****************************************************************************
 * rrd_xport.c  export RRD data 
 ****************************************************************************/

#include "rrd_tool.h"
#include "rrd_graph.h"
#include "rrd_xport.h"
#include <sys/stat.h>
#ifdef WIN32
#include <io.h>
#include <fcntl.h>
#endif


int rrd_xport(int, char **, int *,
	      time_t *, time_t *,
	      unsigned long *, unsigned long *,
	      char ***, rrd_value_t **);

int rrd_xport_fn(image_desc_t *,
		 time_t *, time_t *,
		 unsigned long *, unsigned long *,
		 char ***, rrd_value_t **);



/* mostly rrd_graph(), just pushed a bit here and stretched a bit there */	
int 
rrd_xport(int argc, char **argv, int *xsize,
	  time_t         *start,
	  time_t         *end,        /* which time frame do you want ?
				       * will be changed to represent reality */
	  unsigned long  *step,       /* which stepsize do you want? 
				       * will be changed to represent reality */
	  unsigned long  *col_cnt,    /* number of data columns in the result */
	  char           ***legend_v, /* legend entries */
	  rrd_value_t    **data)      /* two dimensional array containing the data */

{
    image_desc_t   im;
    int            i;
    long           long_tmp;
    time_t	   start_tmp=0,end_tmp=0;
    char           symname[100];
    long           scancount;
    struct rrd_time_value start_tv, end_tv;
    char           *parsetime_error = NULL;

    parsetime("end-24h", &start_tv);
    parsetime("now", &end_tv);

    /* use the default values from rrd_graph.c */
    im.xlab_user.minsec = -1;
    im.xgif=0;
    im.ygif=0;
    im.xsize = 400;
    im.ysize = 100;
    im.step = 0;
    im.ylegend[0] = '\0';
    im.title[0] = '\0';
    im.minval = DNAN;
    im.maxval = DNAN;    
    im.interlaced = 0;
    im.unitsexponent= 9999;
    im.unitslength= 9;
    im.extra_flags= 0;
    im.rigid = 0;
    im.imginfo = NULL;
    im.lazy = 0;
    im.logarithmic = 0;
    im.ygridstep = DNAN;
    im.draw_x_grid = 1;
    im.draw_y_grid = 1;
    im.base = 1000;
    im.prt_c = 0;
    im.gdes_c = 0;
    im.gdes = NULL;
    im.imgformat = IF_GIF; /* we default to GIF output */

    while (1){
	static struct option long_options[] =
	{
	    {"start",      required_argument, 0,  's'},
	    {"end",        required_argument, 0,  'e'},
	    {"maxrows",    required_argument, 0,  'm'},
	    {"step",       required_argument, 0,   261},
	    {0,0,0,0}
	};
	int option_index = 0;
	int opt;
	
	opt = getopt_long(argc, argv, "s:e:m:",
			  long_options, &option_index);

	if (opt == EOF)
	    break;
	
	switch(opt) {
	case 261:
	    im.step =  atoi(optarg);
	    break;
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
	case 'm':
	    long_tmp = atol(optarg);
	    if (long_tmp < 10) {
		rrd_set_error("maxrows below 10 rows");
		return -1;
	    }
	    im.xsize = long_tmp;
	    break;

	case '?':
            if (optopt != 0)
                rrd_set_error("unknown option '%c'", optopt);
            else
                rrd_set_error("unknown option '%s'",argv[optind-1]);
            return -1;
	}
    }

    /*    
    if (optind >= argc) {
       rrd_set_error("missing filename");
       return -1;
    }
    */

    if (proc_start_end(&start_tv,&end_tv,&start_tmp,&end_tmp) == -1){
	return -1;
    }  
    
    if (start_tmp < 3600*24*365*10){
	rrd_set_error("the first entry to fetch should be after 1980 (%ld)",start_tmp);
	return -1;
    }
    
    if (end_tmp < start_tmp) {
	rrd_set_error("start (%ld) should be less than end (%ld)", 
	       start_tmp, end_tmp);
	return -1;
    }
    
    im.start = start_tmp;
    im.end = end_tmp;

    
    for(i=optind;i<argc;i++){
	int   argstart=0;
	int   strstart=0;
	char  varname[30],*rpnex;
	gdes_alloc(&im);
	if(sscanf(argv[i],"%10[A-Z0-9]:%n",symname,&argstart)==1){
	    if((im.gdes[im.gdes_c-1].gf=gf_conv(symname))==-1){
		im_free(&im);
		rrd_set_error("unknown function '%s'",symname);
		return -1;
	    }
	} else {
	    rrd_set_error("can't parse '%s'",argv[i]);
	    im_free(&im);
	    return -1;
	}

	switch(im.gdes[im.gdes_c-1].gf){
	case GF_CDEF:
	    if((rpnex = malloc(strlen(&argv[i][argstart])*sizeof(char)))==NULL){
		rrd_set_error("malloc for CDEF");
		return -1;
	    }
	    if(sscanf(
		    &argv[i][argstart],
		    DEF_NAM_FMT "=%[^: ]",
		    im.gdes[im.gdes_c-1].vname,
		    rpnex) != 2){
		im_free(&im);
		free(rpnex);
		rrd_set_error("can't parse CDEF '%s'",&argv[i][argstart]);
		return -1;
	    }
	    /* checking for duplicate DEF CDEFS */
	    if(find_var(&im,im.gdes[im.gdes_c-1].vname) != -1){
		im_free(&im);
		rrd_set_error("duplicate variable '%s'",
			      im.gdes[im.gdes_c-1].vname);
		return -1; 
	    }	   
	    if((im.gdes[im.gdes_c-1].rpnp = str2rpn(&im,rpnex))== NULL){
		rrd_set_error("invalid rpn expression '%s'", rpnex);
		im_free(&im);		
		return -1;
	    }
	    free(rpnex);
	    break;
	case GF_DEF:
	    if (sscanf(
		&argv[i][argstart],
		DEF_NAM_FMT "=%n",
		im.gdes[im.gdes_c-1].vname,
		&strstart)== 1 && strstart){ /* is the = did not match %n returns 0 */ 
		if(sscanf(&argv[i][argstart
				  +strstart
				  +scan_for_col(&argv[i][argstart+strstart],
						MAXPATH,im.gdes[im.gdes_c-1].rrd)],
			  ":" DS_NAM_FMT ":" CF_NAM_FMT,
			  im.gdes[im.gdes_c-1].ds_nam,
			  symname) != 2){
		    im_free(&im);
		    rrd_set_error("can't parse DEF '%s' -2",&argv[i][argstart]);
		    return -1;
		}
	    } else {
		im_free(&im);
		rrd_set_error("can't parse DEF '%s'",&argv[i][argstart]);
		return -1;
	    }
	    
	    /* checking for duplicate DEF CDEFS */
	    if (find_var(&im,im.gdes[im.gdes_c-1].vname) != -1){
		im_free(&im);
		rrd_set_error("duplicate variable '%s'",
			  im.gdes[im.gdes_c-1].vname);
		return -1; 
	    }	   
	    if((im.gdes[im.gdes_c-1].cf=cf_conv(symname))==-1){
		im_free(&im);
		rrd_set_error("unknown cf '%s'",symname);
		return -1;
	    }
	    break;
	case GF_XPORT:
	    if((scancount=sscanf(
		&argv[i][argstart],
		"%29[^:]:%n",
		varname,
		&strstart))>=1){
		if(strstart <= 0){
		    im.gdes[im.gdes_c-1].legend[0] = '\0';
		} else { 
		    scan_for_col(&argv[i][argstart+strstart],FMT_LEG_LEN,im.gdes[im.gdes_c-1].legend);
		}
		if((im.gdes[im.gdes_c-1].vidx=find_var(&im,varname))==-1){
		    im_free(&im);
		    rrd_set_error("unknown variable '%s'",varname);
		    return -1;
		}		
	    } else {
		im_free(&im);
		rrd_set_error("can't parse '%s'",&argv[i][argstart]);
		return -1;
	    }
	    break;
	default:
	  break;
	}
	
    }

    if (im.gdes_c == 0){
	rrd_set_error("can't make a graph without contents");
	im_free(&im);
	return(-1); 
    }
    
    if (rrd_xport_fn(&im, start, end, step, col_cnt, legend_v, data) == -1){
	im_free(&im);
	return -1;
    }

    im_free(&im);
    return 0;
}


int
rrd_xport_fn(image_desc_t *im,
	     time_t         *start,
	     time_t         *end,        /* which time frame do you want ?
					  * will be changed to represent reality */
	     unsigned long  *step,       /* which stepsize do you want? 
					  * will be changed to represent reality */
	     unsigned long  *col_cnt,    /* number of data columns in the result */
	     char           ***legend_v, /* legend entries */
	     rrd_value_t    **data)      /* two dimensional array containing the data */
{

    int            i = 0, j = 0;
    unsigned long  *ds_cnt;    /* number of data sources in file */
    unsigned long  col, dst_row, row_cnt;
    rrd_value_t    *srcptr, *dstptr;

    unsigned long nof_xports = 0;
    unsigned long xport_counter = 0;
    unsigned long *ref_list;
    rrd_value_t **srcptr_list;
    char **legend_list;
    int ii = 0;

    time_t start_tmp = 0;
    time_t end_tmp = 0;
    unsigned long step_tmp = 1;

    /* pull the data from the rrd files ... */
    if(data_fetch(im)==-1)
	return -1;

    /* evaluate CDEF  operations ... */
    if(data_calc(im)==-1)
	return -1;

    /* how many xports? */
    for(i = 0; i < im->gdes_c; i++) {	
	switch(im->gdes[i].gf) {
	case GF_XPORT:
	  nof_xports++;
	  break;
	default:
	  break;
	}
    }

    if(nof_xports == 0) {
      rrd_set_error("no XPORT found, nothing to do");
      return -1;
    }

    /* a list of referenced gdes */
    ref_list = malloc(sizeof(int) * nof_xports);
    if(ref_list == NULL)
      return -1;

    /* a list to save pointers into each gdes data */
    srcptr_list = malloc(sizeof(srcptr) * nof_xports);
    if(srcptr_list == NULL) {
      free(ref_list);
      return -1;
    }

    /* a list to save pointers to the column's legend entry */
    /* this is a return value! */
    legend_list = malloc(sizeof(char *) * nof_xports);
    if(legend_list == NULL) {
      free(srcptr_list);
      free(ref_list);
      return -1;
    }

    /* find referenced gdes and save their index and */
    /* a pointer into their data */
    for(i = 0; i < im->gdes_c; i++) {	
	switch(im->gdes[i].gf) {
	case GF_XPORT:
	  ii = im->gdes[i].vidx;
	  if(xport_counter > nof_xports) {
	    rrd_set_error( "too many xports: should not happen. Hmmm");
	    free(srcptr_list);
	    free(ref_list);
	    free(legend_list);
	    return -1;
	  } 
	  srcptr_list[xport_counter] = im->gdes[ii].data;
	  ref_list[xport_counter++] = i;
	  break;
	default:
	  break;
	}
    }

    start_tmp = im->gdes[0].start;
    end_tmp = im->gdes[0].end;
    step_tmp = im->gdes[0].step;

    *col_cnt = nof_xports;
    *start = start_tmp;
    *end = end_tmp;
    *step = step_tmp;

    row_cnt = ((*end)-(*start))/(*step) + 1;

    /* room for rearranged data */
    /* this is a return value! */
    if (((*data) = malloc((*col_cnt) * row_cnt * sizeof(rrd_value_t)))==NULL){
        free(srcptr_list);
        free(ref_list);
	free(legend_list);
	rrd_set_error("malloc xport data area");
	return(-1);
    }
    dstptr = (*data);

    j = 0;
    for(i = 0; i < im->gdes_c; i++) {	
	switch(im->gdes[i].gf) {
	case GF_XPORT:
	  /* reserve room for one legend entry */
	  /* is FMT_LEG_LEN + 5 the correct size? */
	  if ((legend_list[j] = malloc(sizeof(char) * (FMT_LEG_LEN+5)))==NULL) {
	    free(srcptr_list);
	    free(ref_list);
	    free(legend_list);
	    rrd_set_error("malloc xprint legend entry");
	    return(-1);
	  }

	  if (im->gdes[i].legend)
	    /* omit bounds check, should have the same size */
	    strcpy (legend_list[j++], im->gdes[i].legend);
	  else
	    legend_list[j++][0] = '\0';

	  break;
	default:
	  break;
	}
    }

    /* fill data structure */
    for(dst_row = 0; dst_row < row_cnt; dst_row++) {
      for(i = 0; i < nof_xports; i++) {
        j = ref_list[i];
	ii = im->gdes[j].vidx;
	ds_cnt = &im->gdes[ii].ds_cnt;
	col = *ds_cnt;

	srcptr = srcptr_list[i];
	for(col = 0; col < (*ds_cnt); col++) {
	  rrd_value_t newval = DNAN;
	  newval = srcptr[col];

	  if (im->gdes[ii].ds_namv && im->gdes[ii].ds_nam) {
	    if(strcmp(im->gdes[ii].ds_namv[col],im->gdes[ii].ds_nam) == 0)
	      (*dstptr++) = newval;
	  } else {
	    (*dstptr++) = newval;
	  }

	}
	srcptr_list[i] += (*ds_cnt);
      }
    }

    *legend_v = legend_list;
    free(srcptr_list);
    free(ref_list);
    return 0;

}
