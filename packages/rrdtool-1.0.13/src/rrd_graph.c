/****************************************************************************
 * RRDtool  Copyright Tobias Oetiker, 1997,1998, 1999
 ****************************************************************************
 * rrd__graph.c  make creates ne rrds
 ****************************************************************************/

#include "rrd_tool.h"
#include <gd.h>
#include <gdlucidan10.h>
#include <gdlucidab12.h>
#include <sys/stat.h>

#define SmallFont gdLucidaNormal10
#define LargeFont gdLucidaBold12

/* #define DEBUG */

#ifdef DEBUG
# define DPRINT(x)    (void)(printf x, printf("\n"))
#else
# define DPRINT(x)
#endif

enum tmt_en {TMT_SECOND=0,TMT_MINUTE,TMT_HOUR,TMT_DAY,
	     TMT_WEEK,TMT_MONTH,TMT_YEAR};

enum grc_en {GRC_CANVAS=0,GRC_BACK,GRC_SHADEA,GRC_SHADEB,
	     GRC_GRID,GRC_MGRID,GRC_FONT,GRC_FRAME,GRC_ARROW,__GRC_END__};

enum gf_en {GF_PRINT=0,GF_GPRINT,GF_COMMENT,GF_HRULE,GF_VRULE,GF_LINE1,
	    GF_LINE2,GF_LINE3,GF_AREA,GF_STACK, GF_DEF, GF_CDEF };

enum op_en {OP_NUMBER=0,OP_VARIABLE,OP_INF,OP_NEGINF,
	    OP_UNKN,OP_NOW,OP_TIME,OP_ADD,OP_MOD,
            OP_SUB,OP_MUL,
	    OP_DIV,OP_SIN, OP_DUP, OP_EXC, OP_POP,
	    OP_COS,OP_LOG,OP_EXP,OP_LT,OP_LE,OP_GT,OP_GE,OP_EQ,OP_IF,
	    OP_UN,OP_END};

enum if_en {IF_GIF=0,IF_PNG=1};

typedef struct rpnp_t {
    enum op_en   op;
    double val; /* value for a OP_NUMBER */
    long ptr; /* pointer into the gdes array for OP_VAR */
    double *data; /* pointer to the current value from OP_VAR DAS*/
    long ds_cnt;   /* data source count for data pointer */
    long step; /* time step for OP_VAR das */
} rpnp_t;
 

typedef struct col_trip_t {
    int red; /* red = -1 is no color */
    int green;
    int blue;
    int i; /* color index assigned in gif image i=-1 is unasigned*/
} col_trip_t;


typedef struct xlab_t {
    long         minsec;       /* minimum sec per pix */
    enum tmt_en  gridtm;       /* grid interval in what ?*/
    long         gridst;       /* how many whats per grid*/
    enum tmt_en  mgridtm;      /* label interval in what ?*/
    long         mgridst;      /* how many whats per label*/
    enum tmt_en  labtm;        /* label interval in what ?*/
    long         labst;        /* how many whats per label*/
    long         precis;       /* label precision -> label placement*/
    char         *stst;        /* strftime string*/
} xlab_t;

xlab_t xlab[] = {
    {0,        TMT_SECOND,30, TMT_MINUTE,5,  TMT_MINUTE,5,         0,"%H:%M"},
    {2,        TMT_MINUTE,1,  TMT_MINUTE,5,  TMT_MINUTE,5,         0,"%H:%M"},
    {5,        TMT_MINUTE,2,  TMT_MINUTE,10, TMT_MINUTE,10,        0,"%H:%M"},
    {10,       TMT_MINUTE,5,  TMT_MINUTE,20, TMT_MINUTE,20,        0,"%H:%M"},
    {30,       TMT_MINUTE,10, TMT_HOUR,1,    TMT_HOUR,1,           0,"%H:%M"},
    {60,       TMT_MINUTE,30, TMT_HOUR,2,    TMT_HOUR,2,           0,"%H:%M"},
    {180,      TMT_HOUR,1,    TMT_HOUR,6,    TMT_HOUR,6,           0,"%H:%M"},
    /*{300,      TMT_HOUR,3,    TMT_HOUR,12,   TMT_HOUR,12,    12*3600,"%a %p"},  this looks silly*/
    {600,      TMT_HOUR,6,    TMT_DAY,1,     TMT_DAY,1,      24*3600,"%a"},
    {1800,     TMT_HOUR,12,   TMT_DAY,1,     TMT_DAY,2,      24*3600,"%a"},
    {3600,     TMT_DAY,1,     TMT_WEEK,1,     TMT_WEEK,1,    7*24*3600,"Week %W"},
    {3*3600,   TMT_WEEK,1,      TMT_MONTH,1,     TMT_WEEK,2,    7*24*3600,"Week %W"},
    {6*3600,   TMT_MONTH,1,   TMT_MONTH,1,   TMT_MONTH,1, 30*24*3600,"%b"},
    {48*3600,  TMT_MONTH,1,   TMT_MONTH,3,   TMT_MONTH,3, 30*24*3600,"%b"},
    {10*24*3600, TMT_YEAR,1,  TMT_YEAR,1,    TMT_YEAR,1, 365*24*3600,"%y"},
    {-1,TMT_MONTH,0,TMT_MONTH,0,TMT_MONTH,0,0,""}
};

/* sensible logarithmic y label intervals ...
   the first element of each row defines the possible starting points on the
   y axis ... the other specify the */

double yloglab[][12]= {{ 1e9, 1,  0,  0,  0,   0,  0,  0,  0,  0,  0,  0 },
		       {  1e3, 1,  0,  0,  0,   0,  0,  0,  0,  0,  0,  0 },
		       {  1e1, 1,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 },
		       /* {  1e1, 1,  5,  0,  0,  0,  0,  0,  0,  0,  0,  0 }, */
		       {  1e1, 1,  2.5,  5,  7.5,  0,  0,  0,  0,  0,  0,  0 },
		       {  1e1, 1,  2,  4,  6,  8,  0,  0,  0,  0,  0,  0 },
		       {  1e1, 1,  2,  3,  4,  5,  6,  7,  8,  9,  0,  0 },
		       {  0,   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0 }};

/* sensible y label intervals ...*/

typedef struct ylab_t {
    double   grid;    /* grid spacing */
    int      lfac[4]; /* associated label spacing*/
} ylab_t;

ylab_t ylab[]= {
    {0.1, {1,2, 5,10}},
    {0.2, {1,5,10,20}},
    {0.5, {1,2, 4,10}},
    {1.0,   {1,2, 5,10}},
    {2.0,   {1,5,10,20}},
    {5.0,   {1,2, 4,10}},
    {10.0,  {1,2, 5,10}},
    {20.0,  {1,5,10,20}},
    {50.0,  {1,2, 4,10}},
    {100.0, {1,2, 5,10}},
    {200.0, {1,5,10,20}},
    {500.0, {1,2, 4,10}},
    {0.0,   {0,0,0,0}}};



col_trip_t graph_col[] = { /* default colors */
    {255,255,255,-1},   /* canvas */
    {245,245,245,-1},   /* background */
    {200,200,200,-1},   /* shade A    */
    {150,150,150,-1},   /* shade B    */
    {140,140,140,-1},      /* grid */
    {130,30,30,-1},      /* major grid */
    {0,0,0,-1},         /* font */ 	
    {0,0,0,-1},         /* frame */
    {255,0,0,-1}	/*arrow*/
};

/* this structure describes the elements which can make up a graph.
   because they are quite diverse, not all elements will use all the
   possible parts of the structure. */
#ifdef HAVE_SNPRINTF
#define FMT_LEG_LEN 200
#else
#define FMT_LEG_LEN 2000
#endif

typedef  struct graph_desc_t {
    enum gf_en     gf;         /* graphing function */
    char           vname[30];  /* name of the variable */
    long           vidx;       /* gdes reference */
    char           rrd[255];   /* name of the rrd_file containing data */
    char           ds_nam[DS_NAM_SIZE]; /* data source name */
    long           ds;         /* data source number */
    enum cf_en     cf;         /* consolidation function */
    col_trip_t     col;        /* graph color */
    char           format[FMT_LEG_LEN+5]; /* format for PRINT AND GPRINT */
    char           legend[FMT_LEG_LEN+5]; /* legend*/
    gdPoint        legloc;     /* location of legend */   
    double         yrule;      /* value for y rule line */
    time_t         xrule;      /* value for x rule line */
    rpnp_t         *rpnp;     /* instructions for CDEF function */

    /* description of data fetched for the graph element */
    time_t         start,end; /* timestaps for first and last data element */
    unsigned long  step;      /* time between samples */
    unsigned long  ds_cnt; /* how many data sources are there in the fetch */
    long           data_first; /* first pointer to this data */
    char           **ds_namv; /* name of datasources  in the fetch. */
    rrd_value_t    *data; /* the raw data drawn from the rrd */
    rrd_value_t    *p_data; /* processed data, xsize elments */

} graph_desc_t;

#define ALTYGRID      0x01  /* use alternative y grid algorithm */
#define ALTAUTOSCALE  0x02  /* use alternative algorithm to find lower and upper bounds */

typedef struct image_desc_t {

    /* configuration of graph */

    char           graphfile[1024]; /* filename for graphic */
    long           xsize,ysize;    /* graph area size in pixels */
    col_trip_t     graph_col[__GRC_END__]; /* real colors for the graph */   
    char           ylegend[200];   /* legend along the yaxis */
    char           title[200];     /* title for graph */
    xlab_t         xlab_user;      /* user defined labeling for xaxis */
    char           xlab_form[200]; /* format for the label on the xaxis */

    double         ygridstep;      /* user defined step for y grid */
    int            ylabfact;       /* every how many y grid shall a label be written ? */

    time_t         start,end;      /* what time does the graph cover */
    rrd_value_t    minval,maxval;  /* extreme values in the data */
    int            rigid;          /* do not expand range even with 
				      values outside */
    char*          imginfo;         /* construct an <IMG ... tag and return 
				      as first retval */
    int            lazy;           /* only update the gif if there is reasonable
				      probablility that the existing one is out of date */
    int            logarithmic;    /* scale the yaxis logarithmic */
    enum if_en     imgformat;         /* image format */
    
    /* status information */
    	    
    long           xorigin,yorigin;/* where is (0,0) of the graph */
    long           xgif,ygif;      /* total size of the gif */
    int            interlaced;     /* will the graph be interlaced? */
    double         magfact;        /* numerical magnitude*/
    long         base;            /* 1000 or 1024 depending on what we graph */
    char           symbol;         /* magnitude symbol for y-axis */
    int            extra_flags;    /* flags for boolean options */
    /* data elements */

    long  prt_c;                  /* number of print elements */
    long  gdes_c;                  /* number of graphics elements */
    graph_desc_t   *gdes;          /* points to an array of graph elements */

} image_desc_t;




/* translate time values into x coordinates */   
/*#define xtr(x) (int)((double)im->xorigin \
		+ ((double) im->xsize / (double)(im->end - im->start) ) \
		* ((double)(x) - im->start)+0.5) */
/* initialize with xtr(im,0); */
int
xtr(image_desc_t *im,time_t time){
    static double pixie;
    if (time==0){
	pixie = (double) im->xsize / (double)(im->end - im->start);
	return im->xorigin;
    }
    return (int)((double)im->xorigin 
		 + pixie * ( time - im->start ) );
}

/* translate data values into y coordinates */

/* #define ytr(x) (int)((double)im->yorigin \
		- ((double) im->ysize / (im->maxval - im->minval) ) \
		* ((double)(x) - im->minval)+0.5) */
int
ytr(image_desc_t *im, double value){
    static double pixie;
    double yval;
    if (isnan(value)){
      if(!im->logarithmic)
	pixie = (double) im->ysize / (im->maxval - im->minval);
      else 
	pixie = (double) im->ysize / (log10(im->maxval) - log10(im->minval));
      yval = im->yorigin;
    } else if(!im->logarithmic) {
      yval = im->yorigin - pixie * (value - im->minval) + 0.5;
    } else {
      if (value < im->minval) {
	yval = im->yorigin;
      } else {
	yval = im->yorigin - pixie * (log10(value) - log10(im->minval)) + 0.5;
      }
    }
    /* make sure we don't return anything too unreasonable. GD lib can
       get terribly slow when drawing lines outside its scope. This is 
       especially problematic in connection with the rigid option */
    if (! im->rigid) {
      return (int)yval;
    } else if ((int)yval > im->yorigin) {
      return im->yorigin+2;
    } else if ((int) yval < im->yorigin - im->ysize){
      return im->yorigin - im->ysize - 2;
    } else {
      return (int)yval;
    } 
}

   
    


/* conversion function for symbolic entry names */

#define conv_if(VV,VVV) \
   if (strcmp(#VV, string) == 0) return VVV ;

enum gf_en gf_conv(char *string){
    
    conv_if(PRINT,GF_PRINT)
    conv_if(GPRINT,GF_GPRINT)
    conv_if(COMMENT,GF_COMMENT)
    conv_if(HRULE,GF_HRULE)
    conv_if(VRULE,GF_VRULE)
    conv_if(LINE1,GF_LINE1)
    conv_if(LINE2,GF_LINE2)
    conv_if(LINE3,GF_LINE3)
    conv_if(AREA,GF_AREA)
    conv_if(STACK,GF_STACK)
    conv_if(DEF,GF_DEF)
    conv_if(CDEF,GF_CDEF)
    
    return (-1);
}

enum if_en if_conv(char *string){
    
    conv_if(GIF,IF_GIF)
    conv_if(PNG,IF_PNG)

    return (-1);
}

enum tmt_en tmt_conv(char *string){

    conv_if(SECOND,TMT_SECOND)
    conv_if(MINUTE,TMT_MINUTE)
    conv_if(HOUR,TMT_HOUR)
    conv_if(DAY,TMT_DAY)
    conv_if(WEEK,TMT_WEEK)
    conv_if(MONTH,TMT_MONTH)
    conv_if(YEAR,TMT_YEAR)
    return (-1);
}

enum grc_en grc_conv(char *string){

    conv_if(BACK,GRC_BACK)
    conv_if(CANVAS,GRC_CANVAS)
    conv_if(SHADEA,GRC_SHADEA)
    conv_if(SHADEB,GRC_SHADEB)
    conv_if(GRID,GRC_GRID)
    conv_if(MGRID,GRC_MGRID)
    conv_if(FONT,GRC_FONT)
    conv_if(FRAME,GRC_FRAME)
    conv_if(ARROW,GRC_ARROW)

    return -1;	
}

#undef conv_if



int
im_free(image_desc_t *im)
{
    long i,ii;
    if (im == NULL) return 0;
    for(i=0;i<im->gdes_c;i++){
      if (im->gdes[i].data_first){
	/* careful here, because a single pointer can occur several times */
	  free (im->gdes[i].data);
	  if (im->gdes[i].ds_namv){
	      for (ii=0;ii<im->gdes[i].ds_cnt;ii++)
		  free(im->gdes[i].ds_namv[ii]);
	      free(im->gdes[i].ds_namv);
	  }
      }
      free (im->gdes[i].p_data);
      free (im->gdes[i].rpnp);
    }
    free(im->gdes);
    return 0;
}

/* find SI magnitude symbol for the given number*/
void
auto_scale(
	   image_desc_t *im,   /* image description */
	   double *value,
	   char **symb_ptr,
	   double *magfact
	   )
{
	
    char *symbol[] = {"a", /* 10e-18 Ato */
		      "f", /* 10e-15 Femto */
		      "p", /* 10e-12 Pico */
		      "n", /* 10e-9  Nano */
		      "u", /* 10e-6  Micro */
		      "m", /* 10e-3  Milli */
		      " ", /* Base */
		      "k", /* 10e3   Kilo */
		      "M", /* 10e6   Mega */
		      "G", /* 10e9   Giga */
		      "T", /* 10e12  Terra */
		      "P", /* 10e15  Peta */
		      "E"};/* 10e18  Exa */

    int symbcenter = 6;
    int index;  

    if (*value == 0.0 || isnan(*value) ) {
	index = 0;
	*magfact = 1.0;
    } else {
	index = floor(log(fabs(*value))/log(im->base)); 
	*magfact = pow(im->base, index);
	(*value) /= (*magfact);
    }
    if ( index <= symbcenter && index >= -symbcenter) {
	(*symb_ptr) = symbol[index+symbcenter];
    }
    else {
	(*symb_ptr) = "?";
    }
}


/* find SI magnitude symbol for the numbers on the y-axis*/
void 
si_unit(
    image_desc_t *im   /* image description */
)
{

    char symbol[] = {'a', /* 10e-18 Ato */ 
		     'f', /* 10e-15 Femto */
		     'p', /* 10e-12 Pico */
		     'n', /* 10e-9  Nano */
		     'u', /* 10e-6  Micro */
		     'm', /* 10e-3  Milli */
		     ' ', /* Base */
		     'k', /* 10e3   Kilo */
		     'M', /* 10e6   Mega */
		     'G', /* 10e9   Giga */
		     'T', /* 10e12  Terra */
		     'P', /* 10e15  Peta */
		     'E'};/* 10e18  Exa */

    int   symbcenter = 6;
    double digits;  
    
    digits = floor( log( max( fabs(im->minval),fabs(im->maxval)))/log(im->base)); 
    im->magfact = pow(im->base , digits);
#ifdef DEBUG
    printf("digits %6.3f  im->magfact %6.3f\n",digits,im->magfact);
#endif
    if ( ((digits+symbcenter) < sizeof(symbol)) &&
		    ((digits+symbcenter) >= 0) )
        im->symbol = symbol[(int)digits+symbcenter];
    else
	im->symbol = ' ';
 }

/*  move min and max values around to become sensible */

void 
expand_range(image_desc_t *im)
{
    double sensiblevalues[] ={1000.0,900.0,800.0,750.0,700.0,
			      600.0,500.0,400.0,300.0,250.0,
			      200.0,125.0,100.0,90.0,80.0,
			      75.0,70.0,60.0,50.0,40.0,30.0,
			      25.0,20.0,10.0,9.0,8.0,
			      7.0,6.0,5.0,4.0,3.5,3.0,
			      2.5,2.0,1.8,1.5,1.2,1.0,
			      0.8,0.7,0.6,0.5,0.4,0.3,0.2,0.1,0.0,-1};
    
    double scaled_min,scaled_max;  
    double adj;
    int i;
    

    
    #ifdef DEBUG
    printf("Min: %6.2f Max: %6.2f MagFactor: %6.2f\n",
	   im->minval,im->maxval,im->magfact);
    #endif

    if (isnan(im->ygridstep)){
	if(im->extra_flags & ALTAUTOSCALE) {
	    /* measure the amplitude of the function. Make sure that
	       graph boundaries are slightly higher then max/min vals
	       so we can see amplitude on the graph */
	      adj = (im->maxval - im->minval) * 0.1;
	      im->minval -= adj;
	      im->maxval += adj;
	}
	else {
	    scaled_min = im->minval / im->magfact;
	    scaled_max = im->maxval / im->magfact;
	    
	    for (i=1; sensiblevalues[i] > 0; i++){
		if (sensiblevalues[i-1]>=scaled_min &&
		    sensiblevalues[i]<=scaled_min)	
		    im->minval = sensiblevalues[i]*(im->magfact);
		
		if (-sensiblevalues[i-1]<=scaled_min &&
		-sensiblevalues[i]>=scaled_min)
		    im->minval = -sensiblevalues[i-1]*(im->magfact);
		
		if (sensiblevalues[i-1] >= scaled_max &&
		    sensiblevalues[i] <= scaled_max)
		    im->maxval = sensiblevalues[i-1]*(im->magfact);
		
		if (-sensiblevalues[i-1]<=scaled_max &&
		    -sensiblevalues[i] >=scaled_max)
		    im->maxval = -sensiblevalues[i]*(im->magfact);
	    }
	}
    } else {
	/* adjust min and max to the grid definition if there is one */
	im->minval = (double)im->ylabfact * im->ygridstep * 
	    floor(im->minval / ((double)im->ylabfact * im->ygridstep));
	im->maxval = (double)im->ylabfact * im->ygridstep * 
	    ceil(im->maxval /( (double)im->ylabfact * im->ygridstep));
    }
    
#ifdef DEBUG
    fprintf(stderr,"SCALED Min: %6.2f Max: %6.2f Factor: %6.2f\n",
	   im->minval,im->maxval,im->magfact);
#endif
}

    

void
reduce_data(
    enum cf_en     cf,         /* which consolidation function ?*/
    unsigned long  cur_step,   /* step the data currently is in */
    time_t         *start,
    time_t         *end,       /* which time frame do you want ?
				* will be changed to represent reality */
    unsigned long  *step,      /* desired step size. Will be adjusted to new increassed step size */
    unsigned long  *ds_cnt,    /* number of data sources in file */
    rrd_value_t    **data)     /* two dimensional array containing the data */
{
    int i,reduce_factor = ceil((double)(*step) / (double)cur_step);
    unsigned long src_row,trg_row,col,row_cnt,start_offset,skiprows=0;

    (*step) = cur_step*reduce_factor; /* set new step size for reduced data */
    /* adjust the start time so that it is a multiple of the new steptime */

    row_cnt = ((*end)-(*start))/cur_step+1; /* +1 because start and end are pointers to first and last entry */
    
    start_offset = (*start) % (*step);
    /* move the start pointer into the past so that the reduced data set
       fully covers the timespan of the new dataset */
    (*start) -= start_offset;

    trg_row=0;
    /* skip the first <skiprows> of original data because we already covered
       by the row of *unknown* data added to the reduced dataset */
    
    skiprows = ((*step) - start_offset) / cur_step;

    if (start_offset > 0) {
      /* we don't have full data for the first row, so we'll ditch 
         what is there and fill it with *UNKNOWN* */
      for (col=0;col<(*ds_cnt);col++) {
	(*data)[col] = DNAN;
      }
      trg_row++; /* one row of target filled already */

    };
 
        
    for (src_row = skiprows; src_row < row_cnt; src_row+=reduce_factor) {
	for (col=0;col<(*ds_cnt);col++){
	    double newval=0;
	    unsigned long validval=0;
	    for (i=0;i<reduce_factor && src_row+i<row_cnt;i++) {		
		unsigned long ptr = (src_row+i)* (*ds_cnt)+col;
		if (isnan((*data)[ptr])) continue; /* we can't help with NAN */
		validval++;
		switch (cf) {
		case CF_AVERAGE:
		    newval += (*data)[ptr];
		    break;
		case CF_MINIMUM:
		    newval = min (newval,(*data)[ptr]);
		    break;
		case CF_MAXIMUM:
		    newval = max (newval,(*data)[ptr]);
		    break;
		case CF_LAST:
		    newval = (*data)[ptr];
		    break;
		}
	    }
	    if (validval == 0){newval = DNAN;} else{
		switch (cf) {
		case CF_AVERAGE:		
		    newval /= validval;
		    break;
		case CF_MINIMUM:
		case CF_MAXIMUM:
		case CF_LAST:
		    break;
		}
	    }
	    (*data)[(trg_row)* (*ds_cnt)+col] = newval;
	}
	trg_row++;
    }
    *end = (*start) + (*step) * (trg_row);
    /* make sure there is some NAN at the end of the graph */
    for (col=0;col<(*ds_cnt);col++){
      (*data)[(trg_row)* *ds_cnt+col] = DNAN;
    }
}


/* get the data required for the graphs from the 
   relevant rrds ... */

int
data_fetch( image_desc_t *im )
{
    int       i,ii;
    int skip;
    /* pull the data from the log files ... */
    for (i=0;i<im->gdes_c;i++){
	/* only GF_DEF elements fetch data */
	if (im->gdes[i].gf != GF_DEF) 
	    continue;

	skip=0;
	/* do we have it already ?*/
	for (ii=0;ii<i;ii++){
	    if (im->gdes[ii].gf != GF_DEF) 
		continue;
	    if((strcmp(im->gdes[i].rrd,im->gdes[ii].rrd) == 0)
		&& (im->gdes[i].cf == im->gdes[ii].cf)){
		/* OK the data it is here already ... 
		 * we just copy the header portion */
		im->gdes[i].start = im->gdes[ii].start;
		im->gdes[i].end = im->gdes[ii].end;
		im->gdes[i].step = im->gdes[ii].step;
		im->gdes[i].ds_cnt = im->gdes[ii].ds_cnt;
		im->gdes[i].ds_namv = im->gdes[ii].ds_namv;		
		im->gdes[i].data = im->gdes[ii].data;
		im->gdes[i].data_first = 0;
		skip=1;
	    }
	    if (skip) 
		break;
	}
	if (! skip) {
	    unsigned long  ft_step = im->gdes[i].step ;
	    
	    if((rrd_fetch_fn(im->gdes[i].rrd,
			     im->gdes[i].cf,
			     &im->gdes[i].start,
			     &im->gdes[i].end,
			     &ft_step,
			     &im->gdes[i].ds_cnt,
			     &im->gdes[i].ds_namv,
			     &im->gdes[i].data)) == -1){		
		return -1;
	    }
	    im->gdes[i].data_first = 1;	    
	
	    if (ft_step < im->gdes[i].step) {
		reduce_data(im->gdes[i].cf,
			    ft_step,
			    &im->gdes[i].start,
			    &im->gdes[i].end,
			    &im->gdes[i].step,
			    &im->gdes[i].ds_cnt,
			    &im->gdes[i].data);
	    } else {
		im->gdes[i].step = ft_step;
	    }
	}
	
        /* lets see if the required data source is realy there */
	for(ii=0;ii<im->gdes[i].ds_cnt;ii++){
	    if(strcmp(im->gdes[i].ds_namv[ii],im->gdes[i].ds_nam) == 0){
		im->gdes[i].ds=ii; }
	}
	if (im->gdes[i].ds== -1){
	    rrd_set_error("No DS called '%s' in '%s'",
			  im->gdes[i].ds_nam,im->gdes[i].rrd);
	    return -1; 
	}
	
    }
    return 0;
}

/* evaluate the expressions in the CDEF functions */

/*************************************************************
 * CDEF stuff 
 *************************************************************/

/* find gdes containing var*/
long
find_var(image_desc_t *im, char *key){
    long ii;
    for(ii=0;ii<im->gdes_c-1;ii++){
	if((im->gdes[ii].gf == GF_DEF 
	    || im->gdes[ii].gf == GF_CDEF) 
	   && (strcmp(im->gdes[ii].vname,key) == 0)){
	    return ii; 
	}	   
    }	    	    
    return -1;
}

/* find the largest common denominator for all the numbers
   in the 0 terminated num array */
long
lcd(long *num){
    long rest;
    int i;
    for (i=0;num[i+1]!=0;i++){
	do { 
	    rest=num[i] % num[i+1];
	    num[i]=num[i+1]; num[i+1]=rest;
	} while (rest!=0);
	num[i+1] = num[i];
    }
/*    return i==0?num[i]:num[i-1]; */
      return num[i];
}


/* convert string to rpnp */
rpnp_t * 
str2rpn(image_desc_t *im,char *expr){
    int pos=0;
    long steps=-1;    
    rpnp_t  *rpnp;
    char vname[30];

    rpnp=NULL;

    while(*expr){
	if ((rpnp = (rpnp_t *) rrd_realloc(rpnp, (++steps + 2)* 
				       sizeof(rpnp_t)))==NULL){
	    return NULL;
	}

	else if(sscanf(expr,"%lf%n",&rpnp[steps].val,&pos) == 1){
	    rpnp[steps].op = OP_NUMBER;
	    expr+=pos;
	} 
	
#define match_op(VV,VVV) \
        else if (strncmp(expr, #VVV, strlen(#VVV))==0){ \
	    rpnp[steps].op = VV; \
	    expr+=strlen(#VVV); \
	}

	match_op(OP_ADD,+)
	match_op(OP_SUB,-)
	match_op(OP_MUL,*)
	match_op(OP_DIV,/)
	match_op(OP_MOD,%)
	match_op(OP_SIN,SIN)
	match_op(OP_COS,COS)
	match_op(OP_LOG,LOG)
	match_op(OP_EXP,EXP)
	match_op(OP_DUP,DUP)
	match_op(OP_EXC,EXC)
	match_op(OP_POP,POP)
	match_op(OP_LT,LT)
	match_op(OP_LE,LE)
	match_op(OP_GT,GT)
	match_op(OP_GE,GE)
	match_op(OP_EQ,EQ)
	match_op(OP_IF,IF)
	  /* order is important here ! .. match longest first */
	match_op(OP_UNKN,UNKN)
	match_op(OP_UN,UN)
	match_op(OP_NEGINF,NEGINF)
	match_op(OP_INF,INF)
	match_op(OP_NOW,NOW)
	match_op(OP_TIME,TIME)

#undef match_op


	else if ((sscanf(expr,"%29[_A-Za-z0-9]%n",
			 vname,&pos) == 1) 
		 && ((rpnp[steps].ptr = find_var(im,vname)) != -1)){
	    rpnp[steps].op = OP_VARIABLE;
	    expr+=pos;
	}	   

	else {
	    free(rpnp);
	    return NULL;
	}
	if (*expr == 0)
	  break;
	if (*expr == ',')
	    expr++;
	else {
	    free(rpnp);
	    return NULL;
	}  
    }
    rpnp[steps+1].op = OP_END;
    return rpnp;
}


#define dc_stackblock 100

/* run the rpn calculator on all the CDEF arguments */

int
data_calc( image_desc_t *im){

    int       gdi,rpi;
    int       dataidx;
    long      *steparray;
    int       stepcnt;
    time_t    now;
    double    *stack = NULL;
    long      dc_stacksize = 0;

    for (gdi=0;gdi<im->gdes_c;gdi++){
	/* only GF_CDEF elements are of interest */
	if (im->gdes[gdi].gf != GF_CDEF) 
	    continue;
	im->gdes[gdi].ds_cnt = 1;
	im->gdes[gdi].ds = 0;
	im->gdes[gdi].data_first = 1;
	im->gdes[gdi].start = 0;
	im->gdes[gdi].end = 0;
	steparray=NULL;
	stepcnt = 0;
	dataidx=-1;

	/* find the variables in the expression. And calc the lowest
           common denominator of all step sizes of the data sources involved.
	   this will be the step size for the cdef created data source*/

	for(rpi=0;im->gdes[gdi].rpnp[rpi].op != OP_END;rpi++){
	    if(im->gdes[gdi].rpnp[rpi].op == OP_VARIABLE){
		long ptr = im->gdes[gdi].rpnp[rpi].ptr;
		if ((steparray = rrd_realloc(steparray, (++stepcnt+1)*sizeof(double)))==NULL){
		  rrd_set_error("realloc steparray");
		  free(stack);
		  return -1;
		};
	

		steparray[stepcnt-1] = im->gdes[ptr].step;

		/* adjust start and end of cdef (gdi) so that it runs from
		   the latest start point to the earliest endpoint of any of the
		   rras involved (ptr) */

		if(im->gdes[gdi].start < im->gdes[ptr].start)
		    im->gdes[gdi].start = im->gdes[ptr].start;

		if(im->gdes[gdi].end == 0 
		   || im->gdes[gdi].end > im->gdes[ptr].end)
		    im->gdes[gdi].end = im->gdes[ptr].end;
		
		/* store pointer to the first element of the rra providing
		   data for variable, further save step size and data source count
		   of this rra*/ 
		im->gdes[gdi].rpnp[rpi].data = 
		    im->gdes[ptr].data + im->gdes[ptr].ds;
		im->gdes[gdi].rpnp[rpi].step = im->gdes[ptr].step;
		im->gdes[gdi].rpnp[rpi].ds_cnt = im->gdes[ptr].ds_cnt;
	    }

	}
	if(steparray == NULL){
	    rrd_set_error("rpn expressions without variables are not supported");
	    free(stack);
	    return -1;    
	}
	steparray[stepcnt]=0;
	/* now find the step for the result of the cdef. so that we land on
	   each step in all of the variables rras */

	im->gdes[gdi].step = lcd(steparray);
	
	
	free(steparray);

	if((im->gdes[gdi].data = malloc(((im->gdes[gdi].end
				     -im->gdes[gdi].start) 
				    / im->gdes[gdi].step +1)
				    * sizeof(double)))==NULL){
	    rrd_set_error("malloc im->gdes[gdi].data");
	    free(stack);
	    return -1;
	}
	
	/* step through the new cdef results array and calculate the values */
	for (now = im->gdes[gdi].start;
	     now<=im->gdes[gdi].end;
	     now += im->gdes[gdi].step){
	    long       stptr=-1;
	    /* process each op from the rpn in turn */
	    for (rpi=0;im->gdes[gdi].rpnp[rpi].op != OP_END;rpi++){
		if (stptr +5 > dc_stacksize){
		    dc_stacksize += dc_stackblock;		
		    stack = rrd_realloc(stack,dc_stacksize*sizeof(long));
		    if (stack==NULL){
			rrd_set_error("RPN stack overflow");
			return -1;
		    }
		}
		switch (im->gdes[gdi].rpnp[rpi].op){
		case OP_NUMBER:
		    stack[++stptr] = im->gdes[gdi].rpnp[rpi].val;
		    break;
		case OP_VARIABLE:
                    /* make sure we pull the correct value from the *.data array */
		    /* adjust the pointer into the array acordingly. */
		    if(now >  im->gdes[gdi].start &&
		       now % im->gdes[gdi].rpnp[rpi].step == 0){
			im->gdes[gdi].rpnp[rpi].data +=
			    im->gdes[gdi].rpnp[rpi].ds_cnt;
		    }
		    stack[++stptr] =  *im->gdes[gdi].rpnp[rpi].data;
		    break;
		case OP_UNKN:
		    stack[++stptr] = DNAN; 
		    break;
		case OP_INF:
		    stack[++stptr] = DINF; 
		    break;
		case OP_NEGINF:
		    stack[++stptr] = -DINF; 
		    break;
		case OP_NOW:
		    stack[++stptr] = (double)time(NULL);
		    break;
		case OP_TIME:
		    stack[++stptr] = (double)now;
		    break;
		case OP_ADD:
		    if(stptr<1){
			rrd_set_error("RPN stack underflow");
			free(stack);
			return -1;
		    }
		    stack[stptr-1] = stack[stptr-1] + stack[stptr];
		    stptr--;
		    break;
		case OP_SUB:
		    if(stptr<1){
			rrd_set_error("RPN stack underflow");
			free(stack);
			return -1;
		    }
		    stack[stptr-1] = stack[stptr-1] - stack[stptr];
		    stptr--;
		    break;
		case OP_MUL:
		    if(stptr<1){
			rrd_set_error("RPN stack underflow");
			free(stack);
			return -1;
		    }
		    stack[stptr-1] = stack[stptr-1] * stack[stptr];
		    stptr--;
		    break;
		case OP_DIV:
		    if(stptr<1){
			rrd_set_error("RPN stack underflow");
			free(stack);
			return -1;
		    }
		    stack[stptr-1] = stack[stptr-1] / stack[stptr];
		    stptr--;
		    break;
		case OP_MOD:
		    if(stptr<1){
			rrd_set_error("RPN stack underflow");
			free(stack);
			return -1;
		    }
		    stack[stptr-1] = fmod(stack[stptr-1],stack[stptr]);
		    stptr--;
		    break;
		case OP_SIN:
		    if(stptr<0){
			rrd_set_error("RPN stack underflow");
			free(stack);
			return -1;
		    }
		    stack[stptr] = sin(stack[stptr]);
		    break;
		case OP_COS:
		    if(stptr<0){
			rrd_set_error("RPN stack underflow");
			free(stack);
			return -1;
		    }
		    stack[stptr] = cos(stack[stptr]);
		    break;
		case OP_LOG:
		    if(stptr<0){
			rrd_set_error("RPN stack underflow");
			free(stack);
			return -1;
		    }
		    stack[stptr] = log(stack[stptr]);
		    break;
		case OP_DUP:
		    if(stptr<0){
			rrd_set_error("RPN stack underflow");
			free(stack);
			return -1;
		    }
		    stack[stptr+1] = stack[stptr];
		    stptr++;
		    break;
		case OP_POP:
		    if(stptr<0){
			rrd_set_error("RPN stack underflow");
			free(stack);
			return -1;
		    }
		    stptr--;
		    break;
		case OP_EXC:
		    if(stptr<1){
			rrd_set_error("RPN stack underflow");
			free(stack);
			return -1;
		    } else {
		      double dummy;
		      dummy = stack[stptr] ;
		      stack[stptr] = stack[stptr-1];
		      stack[stptr-1] = dummy;
		    }
		    break;
		case OP_EXP:
		    if(stptr<0){
			rrd_set_error("RPN stack underflow");
			free(stack);
			return -1;
		    }
		    stack[stptr] = exp(stack[stptr]);
		    break;
		case OP_LT:
		    if(stptr<1){
			rrd_set_error("RPN stack underflow");
			free(stack);
			return -1;
		    }
		    stack[stptr-1] = stack[stptr-1] < stack[stptr] ? 1.0 : 0.0;
		    stptr--;
		    break;
		case OP_LE:
		    if(stptr<1){
			rrd_set_error("RPN stack underflow");
			free(stack);
			return -1;
		    }
		    stack[stptr-1] = stack[stptr-1] <= stack[stptr] ? 1.0 : 0.0;
		    stptr--;
		    break;
		case OP_GT:
		    if(stptr<1){
			rrd_set_error("RPN stack underflow");
			free(stack);
			return -1;
		    }
		    stack[stptr-1] = stack[stptr-1] > stack[stptr] ? 1.0 : 0.0;
		    stptr--;
		    break;
		case OP_GE:
		    if(stptr<1){
			rrd_set_error("RPN stack underflow");
			free(stack);
			return -1;
		    }
		    stack[stptr-1] = stack[stptr-1] >= stack[stptr] ? 1.0 : 0.0;
		    stptr--;
		    break;
		case OP_EQ:
		    if(stptr<1){
			rrd_set_error("RPN stack underflow");
			free(stack);
			return -1;
		    }
		    stack[stptr-1] = stack[stptr-1] == stack[stptr] ? 1.0 : 0.0;
		    stptr--;
		    break;
		case OP_IF:
		    if(stptr<2){
			rrd_set_error("RPN stack underflow");
			free(stack);
			return -1;
		    }
		    stack[stptr-2] = stack[stptr-2] != 0.0 ? stack[stptr-1] : stack[stptr];
		    stptr--;
		    stptr--;
		    break;
		case OP_UN:
		    if(stptr<0){
			rrd_set_error("RPN stack underflow");
			free(stack);
			return -1;
		    }
		    stack[stptr] = isnan(stack[stptr]) ? 1.0 : 0.0;
		    break;
		case OP_END:
		    break;
		}
	    }
	    if(stptr!=0){
		rrd_set_error("RPN final stack size != 1");
		free(stack);
		return -1;
	    }
	    im->gdes[gdi].data[++dataidx] = stack[0];
	}
    }
    free(stack);
    return 0;
}

#undef dc_stacksize

/* massage data so, that we get one value for each x coordinate in the graph */
int
data_proc( image_desc_t *im ){
    long i,ii;
    double pixstep = (double)(im->end-im->start)
	/(double)im->xsize; /* how much time 
			       passes in one pixel */
    double paintval;
    double minval=DNAN,maxval=DNAN;
    
    unsigned long gr_time;    

    /* memory for the processed data */
    for(i=0;i<im->gdes_c;i++){
      if((im->gdes[i].gf==GF_LINE1) ||
	 (im->gdes[i].gf==GF_LINE2) ||
	 (im->gdes[i].gf==GF_LINE3) ||
	 (im->gdes[i].gf==GF_AREA) ||
	 (im->gdes[i].gf==GF_STACK)){
	if((im->gdes[i].p_data = malloc((im->xsize +1)
					* sizeof(rrd_value_t)))==NULL){
	  rrd_set_error("malloc data_proc");
	  return -1;
	}
      }
    }
    
    for(i=0;i<im->xsize;i++){
	long vidx;
	gr_time = im->start+pixstep*i; /* time of the 
					  current step */
	paintval=0.0;
	
	for(ii=0;ii<im->gdes_c;ii++){
	  double value;
	    switch(im->gdes[ii].gf){
	    case GF_LINE1:
	    case GF_LINE2:
	    case GF_LINE3:
	    case GF_AREA:
		paintval = 0.0;
	    case GF_STACK:
		vidx = im->gdes[ii].vidx;

		value =
		    im->gdes[vidx].data[
					((unsigned long)floor(
							     (gr_time - im->gdes[vidx].start ) 
							     / im->gdes[vidx].step)+1)			

					/* added one because data was not being aligned properly
					   this fixes it. We may also be having a problem in fetch ... */

					*im->gdes[vidx].ds_cnt
					+im->gdes[vidx].ds];

		if (! isnan(value)) {
		  paintval += value;
		  im->gdes[ii].p_data[i] = paintval;
		} else {
		  im->gdes[ii].p_data[i] = DNAN;
		}

		if (finite(paintval)){
		  if (isnan(minval) || paintval <  minval)
		    minval = paintval;
		  if (isnan(maxval) || paintval >  maxval)
		    maxval = paintval;
		}
		break;
	    case GF_PRINT:
	    case GF_GPRINT:
	    case GF_COMMENT:
	    case GF_HRULE:
	    case GF_VRULE:
	    case GF_DEF:	       
	    case GF_CDEF:
		break;
	    }
	}
    }

    /* if min or max have not been asigned a value this is because
       there was no data in the graph ... this is not good ...
       lets set these to dummy values then ... */

    if (isnan(minval)) minval = 0.0;
    if (isnan(maxval)) maxval = 1.0;
    
    /* adjust min and max values */
    if (isnan(im->minval) 
	|| ((!im->logarithmic && !im->rigid) /* don't adjust low-end with log scale */
	    && im->minval > minval))
	im->minval = minval;
    if (isnan(im->maxval) 
	|| (!im->rigid 
	    && im->maxval < maxval)){
	if (im->logarithmic)
	    im->maxval = maxval * 1.1;
	else
	    im->maxval = maxval;
    }
    /* make sure min and max are not equal */
    if (im->minval == im->maxval) {
      im->maxval *= 1.01; 
      if (! im->logarithmic) {
	im->minval *= 0.99;
      }
      
      /* make sure min and max are not both zero */
      if (im->maxval == 0.0) {
	    im->maxval = 1.0;
      }
        
    }
    return 0;
}



/* identify the point where the first gridline, label ... gets placed */

time_t
find_first_time(
    time_t   start, /* what is the initial time */
    enum tmt_en baseint,  /* what is the basic interval */
    long     basestep /* how many if these do we jump a time */
    )
{
    struct tm tm;
    tm = *localtime(&start);
    switch(baseint){
    case TMT_SECOND:
	tm.tm_sec -= tm.tm_sec % basestep; break;
    case TMT_MINUTE: 
	tm.tm_sec=0;
	tm.tm_min -= tm.tm_min % basestep; 
	break;
    case TMT_HOUR:
	tm.tm_sec=0;
	tm.tm_min = 0;
	tm.tm_hour -= tm.tm_hour % basestep; break;
    case TMT_DAY:
	/* we do NOT look at the basestep for this ... */
	tm.tm_sec=0;
	tm.tm_min = 0;
	tm.tm_hour = 0; break;
    case TMT_WEEK:
	/* we do NOT look at the basestep for this ... */
	tm.tm_sec=0;
	tm.tm_min = 0;
	tm.tm_hour = 0;
	tm.tm_mday -= tm.tm_wday -1 ; break;	/* -1 because we want the monday */
	if (tm.tm_wday==0) tm.tm_mday -= 7; /* we want the *previous* monday */
    case TMT_MONTH:
	tm.tm_sec=0;
	tm.tm_min = 0;
	tm.tm_hour = 0;
	tm.tm_mday = 1;
	tm.tm_mon -= tm.tm_mon % basestep; break;

    case TMT_YEAR:
	tm.tm_sec=0;
	tm.tm_min = 0;
	tm.tm_hour = 0;
	tm.tm_mday = 1;
	tm.tm_mon = 0;
	tm.tm_year -= (tm.tm_year+1900) % basestep;
	
    }
    return mktime(&tm);
}
/* identify the point where the next gridline, label ... gets placed */
time_t 
find_next_time(
    time_t   current, /* what is the initial time */
    enum tmt_en baseint,  /* what is the basic interval */
    long     basestep /* how many if these do we jump a time */
    )
{
    struct tm tm;
    time_t madetime;
    tm = *localtime(&current);
    do {
	switch(baseint){
	case TMT_SECOND:
	    tm.tm_sec += basestep; break;
	case TMT_MINUTE: 
	    tm.tm_min += basestep; break;
	case TMT_HOUR:
	    tm.tm_hour += basestep; break;
	case TMT_DAY:
	    tm.tm_mday += basestep; break;
	case TMT_WEEK:
	    tm.tm_mday += 7*basestep; break;
	case TMT_MONTH:
	    tm.tm_mon += basestep; break;
	case TMT_YEAR:
	    tm.tm_year += basestep;	
	}
	madetime = mktime(&tm);
    } while (madetime == -1); /* this is necessary to skip impssible times
				 like the daylight saving time skips */
    return madetime;
	  
}

/* create a grid on the graph. it determines what to do
   from the values of xsize, start and end */
/* the xaxis labels are determined from the number of seconds per pixel
   in the requested graph */


void gator( gdImagePtr gif, int x, int y){ 

    int li[]={0,0,1, 0,4,5, 0,8,9, 0,12,14, 0,17,17, 0,21,21, 
	      0,24,24, 0,34,34, 0,40,42, 0,45,45, 0,48,49, 0,52,54, 
	      0,61,61, 0,64,66, 0,68,70, 0,72,74, 0,76,76, 0,78,78, 
	      0,80,82, 0,84,85, 
	      1,0,0, 1,2,2, 1,4,4, 1,6,6, 1,8,8, 1,10,10, 
	      1,13,13, 1,16,16, 1,18,18, 1,20,20, 1,22,22, 1,24,24, 
	      1,34,34, 1,41,41, 1,44,44, 1,46,46, 1,48,48, 1,50,50, 
	      1,53,53, 1,60,60, 1,62,62, 1,64,64, 1,69,69, 1,73,73, 
	      1,76,76, 1,78,78, 1,80,80, 1,84,84, 1,86,86, 
	      2,0,1, 2,4,5, 2,8,8, 2,10,10, 2,13,13, 2,16,16, 
	      2,18,18, 2,20,20, 2,22,22, 2,24,24, 2,33,33, 2,41,41, 
	      2,44,44, 2,46,46, 2,48,49, 2,53,53, 2,60,60, 2,62,62, 
	      2,64,65, 2,69,69, 2,73,73, 2,76,77, 2,80,81, 2,84,85, 	      
	      3,0,0, 3,2,2, 3,4,4, 3,6,6, 3,8,8, 3,10,10, 
	      3,13,13, 3,16,16, 3,18,18, 3,20,20, 3,22,22, 3,24,24, 
	      3,32,32, 3,41,41, 3,44,44, 3,46,46, 3,48,48, 3,50,50, 
	      3,53,53, 3,60,60, 3,62,62, 3,64,64, 3,69,69, 3,73,73, 
	      3,76,76, 3,78,78, 3,80,80, 3,84,84, 3,86,86, 
	      4,0,0, 4,2,2, 4,4,4, 4,6,6, 4,8,9, 4,13,13, 
	      4,17,17, 4,21,21, 4,24,26, 4,32,32, 4,41,41, 4,45,45, 
	      4,48,49, 4,52,54, 4,61,61, 4,64,66, 4,69,69, 4,72,74, 
	      4,76,76, 4,78,78, 4,80,82, 4,84,84}; 
    int i,ii; 
    for(i=0; i<DIM(li); i=i+3)
	for(ii=y+li[i+1]; ii<=y+li[i+2];ii++)
	  gdImageSetPixel(gif,x-li[i],ii,graph_col[GRC_GRID].i); 
}

/* calculate values required for PRINT and GPRINT functions */

int
print_calc(image_desc_t *im, char ***prdata) 
{
    long i,ii,validsteps;
    double printval;
    int graphelement = 0;
    long vidx;
    int max_ii;	
    double magfact = -1;
    char *si_symb = "";
    char *percent_s;
    int prlines = 1;
    if (im->imginfo) prlines++;
    for(i=0;i<im->gdes_c;i++){
	switch(im->gdes[i].gf){
	case GF_PRINT:
	    prlines++;
	    if(((*prdata) = rrd_realloc((*prdata),prlines*sizeof(char *)))==NULL){
		rrd_set_error("realloc prdata");
		return 0;
	    }
	case GF_GPRINT:
	    vidx = im->gdes[i].vidx;
	    max_ii =((im->gdes[vidx].end 
		      - im->gdes[vidx].start)
		     /im->gdes[vidx].step
		     *im->gdes[vidx].ds_cnt);
	    printval = DNAN;
	    validsteps = 0;
	    for(ii=im->gdes[vidx].ds;
		ii < max_ii;
		ii+=im->gdes[vidx].ds_cnt){
		 if (! finite(im->gdes[vidx].data[ii]))
		     continue;
		 if (isnan(printval)){
		     printval = im->gdes[vidx].data[ii];
		     validsteps++;
		    continue;
		}

		switch (im->gdes[i].cf){
		case CF_AVERAGE:
		    validsteps++;
		    printval += im->gdes[vidx].data[ii];
		    break;
		case CF_MINIMUM:
		    printval = min( printval, im->gdes[vidx].data[ii]);
		    break;
		case CF_MAXIMUM:
		    printval = max( printval, im->gdes[vidx].data[ii]);
		    break;
		case CF_LAST:
		    printval = im->gdes[vidx].data[ii];
		}
	    }
	    if (im->gdes[i].cf ==  CF_AVERAGE) {
		if (validsteps > 1) {
		    printval = (printval / validsteps);
		}
	    }
	    if ((percent_s = strstr(im->gdes[i].format,"%S")) != NULL) {
		/* Magfact is set to -1 upon entry to print_calc.  If it
		 * is still less than 0, then we need to run auto_scale.
		 * Otherwise, put the value into the correct units.  If
		 * the value is 0, then do not set the symbol or magnification
		 * so next the calculation will be performed again. */
		if (magfact < 0.0) {
		    auto_scale(im,&printval,&si_symb,&magfact);
		    if (printval == 0.0)
			magfact = -1.0;
		} else {
		    printval /= magfact;
		}
		*(++percent_s) = 's';
	    }
	    else if (strstr(im->gdes[i].format,"%s") != NULL) {
		auto_scale(im,&printval,&si_symb,&magfact);
	    }
	    if (im->gdes[i].gf == GF_PRINT){
		(*prdata)[prlines-2] = malloc((FMT_LEG_LEN+2)*sizeof(char));
#ifdef HAVE_SNPRINTF
		snprintf((*prdata)[prlines-2],FMT_LEG_LEN,im->gdes[i].format,printval,si_symb);
#else
		sprintf((*prdata)[prlines-2],im->gdes[i].format,printval,si_symb);
#endif
		(*prdata)[prlines-1] = NULL;
	    } else {
		/* GF_GPRINT */

#ifdef HAVE_SNPRINTF
		snprintf(im->gdes[i].legend,FMT_LEG_LEN-2,im->gdes[i].format,printval,si_symb);
#else
		sprintf(im->gdes[i].legend,im->gdes[i].format,printval,si_symb);
#endif
		graphelement = 1;
	    }
	    break;
        case GF_COMMENT:
	case GF_LINE1:
	case GF_LINE2:
	case GF_LINE3:
	case GF_AREA:
	case GF_STACK:
	case GF_HRULE:
	case GF_VRULE:
	    graphelement = 1;
	    break;
	case GF_DEF:
	case GF_CDEF:	    
	    break;
	}
    }
    return graphelement;
}


/* place legends with color spots */
void
leg_place(image_desc_t *im)
{
    
    /* graph labels */
    int   interleg = SmallFont->w*2;
    int   box = SmallFont->h*1.2;
    int   border = SmallFont->w*2;
    int   fill=0, fill_last;
    int   leg_c = 0;
    int   leg_x = border, leg_y = im->ygif;
    int   leg_cc;
    int   glue = 0;
    int   i,ii, mark = 0;
    char  prt_fctn; /*special printfunctions */

    for(i=0;i<im->gdes_c;i++){
	fill_last = fill;

	leg_cc = strlen(im->gdes[i].legend);
	
	/* is there a controle code ant the end of the legend string ? */ 
	if (leg_cc >= 2 && im->gdes[i].legend[leg_cc-2] == '\\') {
	    prt_fctn = im->gdes[i].legend[leg_cc-1];
	    im->gdes[i].legend[leg_cc-2] = '\0';
	    leg_cc -= 2;
	} else {
	    prt_fctn = '\0';
	}

	if (leg_cc != 0 ){	    
	    if (fill > 0) 
		fill += interleg;
	    if (im->gdes[i].gf != GF_GPRINT && 
		im->gdes[i].gf != GF_COMMENT) 
		fill += box; 	   
	    fill += leg_cc * SmallFont->w;
	    leg_c++;
	}
	    
	if (prt_fctn == '\0') {
	    if (i == im->gdes_c -1 ) prt_fctn ='l';
	    
	    /* is it time to place the legends ? */
	    if (fill > im->xgif - 2*border){
		if (leg_c > 1) {
		    /* go back one */
		    i--; 
		    fill = fill_last;
		    leg_c--;
		    prt_fctn = 'j';
		} else {
		    prt_fctn = 'l';
		}
		
	    }
	}


	if (prt_fctn != '\0'){
	    leg_x = border;
	    if (leg_c >= 2 && prt_fctn == 'j') {
		glue = (im->xgif - fill - 2* border) / (leg_c-1);
		/* if (glue > 2 * SmallFont->w) glue = 0; */
	    } else {
		glue = 0;
	    }
	    if (prt_fctn =='c') leg_x =  (im->xgif - fill) / 2.0;
	    if (prt_fctn =='r') leg_x =  im->xgif - fill - border;

	    for(ii=mark;ii<=i;ii++){
		if(im->gdes[ii].legend[0]=='\0')
		    continue;
		im->gdes[ii].legloc.x = leg_x;
		im->gdes[ii].legloc.y = leg_y;
		leg_x =  leg_x 
		    + strlen(im->gdes[ii].legend)*SmallFont->w 
		    + interleg 
		    + glue;
		if (im->gdes[ii].gf != GF_GPRINT && 
		    im->gdes[ii].gf != GF_COMMENT) 
		    leg_x += box; 	   
	    }	    
	    leg_y = leg_y + SmallFont->h*1.2;
	    if (prt_fctn == 's') leg_y -= SmallFont->h *0.5;
	    fill = 0;
	    leg_c = 0;
	    mark = ii;
	}	   
    }
    im->ygif = leg_y+6;
}



int
horizontal_grid(gdImagePtr gif, image_desc_t   *im)
{
    double   range;
    double   scaledrange;
    int      pixel,i;
    int      sgrid,egrid;
    double   gridstep;
    double   scaledstep;
    char     graph_label[100];
    gdPoint  polyPoints[4];
    int      labfact,gridind;
    int      styleMinor[2],styleMajor[2];
    int      decimals, fractionals;
    char     labfmt[64];

    labfact=2;
    gridind=-1;
    range =  im->maxval - im->minval;
    scaledrange = range / im->magfact;

	/* does the scale of this graph make it impossible to put lines
	   on it? If so, give up. */
	if (isnan(scaledrange)) {
		return 0;
	}

    styleMinor[0] = graph_col[GRC_GRID].i;
    styleMinor[1] = gdTransparent;

    styleMajor[0] = graph_col[GRC_MGRID].i;
    styleMajor[1] = gdTransparent;

    /* find grid spaceing */
    pixel=1;
    if(isnan(im->ygridstep)){
	if(im->extra_flags & ALTYGRID) {
	    /* find the value with max number of digits. Get number of digits */
	    decimals = ceil(log10(max(fabs(im->maxval), fabs(im->minval))));
	    if(decimals <= 0) /* everything is small. make place for zero */
		decimals = 1;
	    
	    fractionals = floor(log10(range));
	    if(fractionals < 0) /* small amplitude. */
		sprintf(labfmt, "%%%d.%df", decimals - fractionals + 1, -fractionals + 1);
	    else
		sprintf(labfmt, "%%%d.1f", decimals + 1);
	    gridstep = pow(10, fractionals);
	    if(gridstep == 0) /* range is one -> 0.1 is reasonable scale */
		gridstep = 0.1;
	    /* should have at least 5 lines but no more then 15 */
	    if(range/gridstep < 5)
                gridstep /= 10;
	    if(range/gridstep > 15)
                gridstep *= 10;
	    if(range/gridstep > 5) {
		labfact = 1;
		if(range/gridstep > 8)
		    labfact = 2;
	    }
	    else {
		gridstep /= 5;
		labfact = 5;
	    }
	}
	else {
	    for(i=0;ylab[i].grid > 0;i++){
		pixel = im->ysize / (scaledrange / ylab[i].grid);
		if (gridind == -1 && pixel > 5) {
		    gridind = i;
		    break;
		}
	    }
	    
	    for(i=0; i<4;i++) {
		if (pixel * ylab[gridind].lfac[i] >=  2 * SmallFont->h) {
		    labfact =  ylab[gridind].lfac[i];
		    break;
		}		          
	    } 
	    
	    gridstep = ylab[gridind].grid * im->magfact;
	}
    } else {
	gridstep = im->ygridstep;
	labfact = im->ylabfact;
    }
    
    polyPoints[0].x=im->xorigin;
    polyPoints[1].x=im->xorigin+im->xsize;
    sgrid = (int)( im->minval / gridstep - 1);
    egrid = (int)( im->maxval / gridstep + 1);
    scaledstep = gridstep/im->magfact;
    for (i = sgrid; i <= egrid; i++){
	polyPoints[0].y=ytr(im,gridstep*i);
	if ( polyPoints[0].y >= im->yorigin-im->ysize
	     && polyPoints[0].y <= im->yorigin) {
	    if(i % labfact == 0){		
		if (i==0 || im->symbol == ' ') {
		    if(scaledstep < 1){
			if(im->extra_flags & ALTYGRID) {
			    sprintf(graph_label,labfmt,scaledstep*i);
			}
			else {
			    sprintf(graph_label,"%4.1f",scaledstep*i);
			}
		    } else {
			sprintf(graph_label,"%4.0f",scaledstep*i);
		    }
		}else {
		    if(scaledstep < 1){
			sprintf(graph_label,"%4.1f %c",scaledstep*i, im->symbol);
		    } else {
			sprintf(graph_label,"%4.0f %c",scaledstep*i, im->symbol);
		    }
		}

		gdImageString(gif, SmallFont,
                              (polyPoints[0].x - (strlen(graph_label) * 
                                                  SmallFont->w)-7), 
                              polyPoints[0].y - SmallFont->h/2+1,
                              graph_label, graph_col[GRC_FONT].i);
		
		gdImageSetStyle(gif, styleMajor, 2);

		gdImageLine(gif, polyPoints[0].x-2,polyPoints[0].y,
			    polyPoints[0].x+2,polyPoints[0].y,graph_col[GRC_MGRID].i);
		gdImageLine(gif, polyPoints[1].x-2,polyPoints[0].y,
			    polyPoints[1].x+2,polyPoints[0].y,graph_col[GRC_MGRID].i);		    
	    } else {		
		gdImageSetStyle(gif, styleMinor, 2);
		gdImageLine(gif, polyPoints[0].x-1,polyPoints[0].y,
			    polyPoints[0].x+1,polyPoints[0].y,graph_col[GRC_GRID].i);
		gdImageLine(gif, polyPoints[1].x-1,polyPoints[0].y,
			    polyPoints[1].x+1,polyPoints[0].y,graph_col[GRC_GRID].i);		    
	    }	    
	    gdImageLine(gif, polyPoints[0].x,polyPoints[0].y,
			polyPoints[1].x,polyPoints[0].y,gdStyled);
	}	
    } 
/*    if(im->minval * im->maxval < 0){
      polyPoints[0].y=ytr(0);
      gdImageLine(gif, polyPoints[0].x,polyPoints[0].y,
      polyPoints[1].x,polyPoints[0].y,graph_col[GRC_MGRID].i);
      } */

    return 1;
}

/* logaritmic horizontal grid */
int
horizontal_log_grid(gdImagePtr gif, image_desc_t   *im)
{
    double   pixpex;
    int      ii,i;
    int      minoridx=0, majoridx=0;
    char     graph_label[100];
    gdPoint  polyPoints[4];
    int      styleMinor[2],styleMajor[2];
    double   value, pixperstep, minstep;

    /* find grid spaceing */
    pixpex= (double)im->ysize / (log10(im->maxval) - log10(im->minval));

	if (isnan(pixpex)) {
		return 0;
	}

    for(i=0;yloglab[i][0] > 0;i++){
	minstep = log10(yloglab[i][0]);
	for(ii=1;yloglab[i][ii+1] > 0;ii++){
	    if(yloglab[i][ii+2]==0){
		minstep = log10(yloglab[i][ii+1])-log10(yloglab[i][ii]);
		break;
	    }
	}
	pixperstep = pixpex * minstep;
	if(pixperstep > 5){minoridx = i;}
	if(pixperstep > 2 * SmallFont->h){majoridx = i;}
    }
   
    styleMinor[0] = graph_col[GRC_GRID].i;
    styleMinor[1] = gdTransparent;

    styleMajor[0] = graph_col[GRC_MGRID].i;
    styleMajor[1] = gdTransparent;

    polyPoints[0].x=im->xorigin;
    polyPoints[1].x=im->xorigin+im->xsize;
    /* paint minor grid */
    for (value = pow(10, log10(im->minval) 
			  - fmod(log10(im->minval),log10(yloglab[minoridx][0])));
	 value  <= im->maxval;
	 value *= yloglab[minoridx][0]){
	if (value < im->minval) continue;
	i=0;	
	while(yloglab[minoridx][++i] > 0){	    
	    polyPoints[0].y = ytr(im,value * yloglab[minoridx][i]);
	    if (polyPoints[0].y <= im->yorigin - im->ysize) break;
	    gdImageSetStyle(gif, styleMinor, 2);
	    gdImageLine(gif, polyPoints[0].x-1,polyPoints[0].y,
			polyPoints[0].x+1,polyPoints[0].y,graph_col[GRC_GRID].i);
	    gdImageLine(gif, polyPoints[1].x-1,polyPoints[0].y,
			polyPoints[1].x+1,polyPoints[0].y,graph_col[GRC_GRID].i);	    

	    gdImageLine(gif, polyPoints[0].x,polyPoints[0].y,
			polyPoints[1].x,polyPoints[0].y,gdStyled);
	}
    }

    /* paint major grid and labels*/
    for (value = pow(10, log10(im->minval) 
			  - fmod(log10(im->minval),log10(yloglab[majoridx][0])));
	 value <= im->maxval;
	 value *= yloglab[majoridx][0]){
	if (value < im->minval) continue;
	i=0;	
	while(yloglab[majoridx][++i] > 0){	    
	    polyPoints[0].y = ytr(im,value * yloglab[majoridx][i]);	    
	    if (polyPoints[0].y <= im->yorigin - im->ysize) break;
	    gdImageSetStyle(gif, styleMajor, 2);
	    gdImageLine(gif, polyPoints[0].x-2,polyPoints[0].y,
			polyPoints[0].x+2,polyPoints[0].y,graph_col[GRC_MGRID].i);
	    gdImageLine(gif, polyPoints[1].x-2,polyPoints[0].y,
			polyPoints[1].x+2,polyPoints[0].y,graph_col[GRC_MGRID].i);		    
	    
	    gdImageLine(gif, polyPoints[0].x,polyPoints[0].y,
			polyPoints[1].x,polyPoints[0].y,gdStyled);
	    sprintf(graph_label,"%3.0e",value * yloglab[majoridx][i]);
	    gdImageString(gif, SmallFont,
			  (polyPoints[0].x - (strlen(graph_label) * 
					      SmallFont->w)-7), 
			  polyPoints[0].y - SmallFont->h/2+1,
			  graph_label, graph_col[GRC_FONT].i);	
	} 
    }
	return 1;
}


void
vertical_grid(
    gdImagePtr     gif,
    image_desc_t   *im )
{   
    int xlab_sel;		/* which sort of label and grid ? */
    time_t ti, tilab;
    long factor;
    char graph_label[100];
    gdPoint polyPoints[4];	 /* points for filled graph and more*/

    /* style for grid lines */
    int     styleDotted[4];

    
    /* the type of time grid is determined by finding
       the number of seconds per pixel in the graph */
    
    
    if(im->xlab_user.minsec == -1){
	factor=(im->end - im->start)/im->xsize;
	xlab_sel=0;
	while ( xlab[xlab_sel+1].minsec != -1 
		&& xlab[xlab_sel+1].minsec <= factor){ xlab_sel++; }
	im->xlab_user.gridtm = xlab[xlab_sel].gridtm;
	im->xlab_user.gridst = xlab[xlab_sel].gridst;
	im->xlab_user.mgridtm = xlab[xlab_sel].mgridtm;
	im->xlab_user.mgridst = xlab[xlab_sel].mgridst;
	im->xlab_user.labtm = xlab[xlab_sel].labtm;
	im->xlab_user.labst = xlab[xlab_sel].labst;
	im->xlab_user.precis = xlab[xlab_sel].precis;
	im->xlab_user.stst = xlab[xlab_sel].stst;
    }
    
    /* y coords are the same for every line ... */
    polyPoints[0].y = im->yorigin;
    polyPoints[1].y = im->yorigin-im->ysize;

    /* paint the minor grid */
    for(ti = find_first_time(im->start,
			    im->xlab_user.gridtm,
			    im->xlab_user.gridst);
	ti < im->end; 
	ti = find_next_time(ti,im->xlab_user.gridtm,im->xlab_user.gridst)
	){
	/* are we inside the graph ? */
	if (ti < im->start || ti > im->end) continue;
	polyPoints[0].x = xtr(im,ti);
	styleDotted[0] = graph_col[GRC_GRID].i;
	styleDotted[1] = gdTransparent;

	gdImageSetStyle(gif, styleDotted, 2);

	gdImageLine(gif, polyPoints[0].x,polyPoints[0].y,
		    polyPoints[0].x,polyPoints[1].y,gdStyled);
	gdImageLine(gif, polyPoints[0].x,polyPoints[0].y-1,
		    polyPoints[0].x,polyPoints[0].y+1,graph_col[GRC_GRID].i);
	gdImageLine(gif, polyPoints[0].x,polyPoints[1].y-1,
		    polyPoints[0].x,polyPoints[1].y+1,graph_col[GRC_GRID].i);
    }

    /* paint the major grid */
    for(ti = find_first_time(im->start,
			    im->xlab_user.mgridtm,
			    im->xlab_user.mgridst);
	ti < im->end; 
	ti = find_next_time(ti,im->xlab_user.mgridtm,im->xlab_user.mgridst)
	){
	/* are we inside the graph ? */
	if (ti < im->start || ti > im->end) continue;
	polyPoints[0].x = xtr(im,ti);
	styleDotted[0] = graph_col[GRC_MGRID].i;
	styleDotted[1] = gdTransparent;
	gdImageSetStyle(gif, styleDotted, 2);

	gdImageLine(gif, polyPoints[0].x,polyPoints[0].y,
		    polyPoints[0].x,polyPoints[1].y,gdStyled);
	gdImageLine(gif, polyPoints[0].x,polyPoints[0].y-2,
		    polyPoints[0].x,polyPoints[0].y+2,graph_col[GRC_MGRID].i);
	gdImageLine(gif, polyPoints[0].x,polyPoints[1].y-2,
		    polyPoints[0].x,polyPoints[1].y+2,graph_col[GRC_MGRID].i);
    }
    /* paint the labels below the graph */
    for(ti = find_first_time(im->start,
			    im->xlab_user.labtm,
			    im->xlab_user.labst);
	ti <= im->end; 
	ti = find_next_time(ti,im->xlab_user.labtm,im->xlab_user.labst)
	){
	int gr_pos,width;
        tilab= ti + im->xlab_user.precis/2; /* correct time for the label */

#if HAVE_STRFTIME
	strftime(graph_label,99,im->xlab_user.stst,localtime(&tilab));
#else
# error "your libc has no strftime I guess we'll abort the exercise here."
#endif
	width=strlen(graph_label) *  SmallFont->w;
	gr_pos=xtr(im,tilab) - width/2;
	if (gr_pos  >= im->xorigin 
	    && gr_pos + width <= im->xorigin+im->xsize) 
	    gdImageString(gif, SmallFont,
			  gr_pos,  polyPoints[0].y+4,
			  graph_label, graph_col[GRC_FONT].i);
    }

}


void 
axis_paint(
    image_desc_t   *im,
    gdImagePtr     gif
    )
{   
    /* draw x and y axis */
    gdImageLine(gif, im->xorigin+im->xsize,im->yorigin,
		im->xorigin+im->xsize,im->yorigin-im->ysize,
		graph_col[GRC_GRID].i);
    
    gdImageLine(gif, im->xorigin,im->yorigin-im->ysize,
		im->xorigin+im->xsize,im->yorigin-im->ysize,
		graph_col[GRC_GRID].i);

    gdImageLine(gif, im->xorigin-4,im->yorigin,
		im->xorigin+im->xsize+4,im->yorigin,
		graph_col[GRC_FONT].i);

    gdImageLine(gif, im->xorigin,im->yorigin,
		im->xorigin,im->yorigin-im->ysize,
		graph_col[GRC_GRID].i);
    
    /* arrow for X axis direction */
    gdImageLine(gif, im->xorigin+im->xsize+4, im->yorigin-3, im->xorigin+im->xsize+4, im->yorigin+3,graph_col[GRC_ARROW].i);
    gdImageLine(gif, im->xorigin+im->xsize+4, im->yorigin-3, im->xorigin+im->xsize+9, im->yorigin,graph_col[GRC_ARROW].i);
    gdImageLine(gif, im->xorigin+im->xsize+4, im->yorigin+3, im->xorigin+im->xsize+9, im->yorigin,graph_col[GRC_ARROW].i);

    /*    gdImageLine(gif, im->xorigin+im->xsize-1, im->yorigin-3, im->xorigin+im->xsize-1, im->yorigin+3,graph_col[GRC_MGRID].i);
    gdImageLine(gif, im->xorigin+im->xsize, im->yorigin-2, im->xorigin+im->xsize, im->yorigin+2,graph_col[GRC_MGRID].i);
    gdImageLine(gif, im->xorigin+im->xsize+1, im->yorigin-2, im->xorigin+im->xsize+1, im->yorigin+2,graph_col[GRC_MGRID].i);
    gdImageLine(gif, im->xorigin+im->xsize+2, im->yorigin-2, im->xorigin+im->xsize+2, im->yorigin+2,graph_col[GRC_MGRID].i);
    gdImageLine(gif, im->xorigin+im->xsize+3, im->yorigin-1, im->xorigin+im->xsize+3, im->yorigin+1,graph_col[GRC_MGRID].i);
    gdImageLine(gif, im->xorigin+im->xsize+4, im->yorigin-1, im->xorigin+im->xsize+4, im->yorigin+1,graph_col[GRC_MGRID].i);
    gdImageLine(gif, im->xorigin+im->xsize+5, im->yorigin, im->xorigin+im->xsize+5, im->yorigin,graph_col[GRC_MGRID].i); */



}

void
grid_paint(
    image_desc_t   *im,
    gdImagePtr     gif
    )
{   
    long i;
    int boxH=8, boxV=8;
	int res;
    gdPoint polyPoints[4];	 /* points for filled graph and more*/

    /* draw 3d border */
    gdImageLine(gif,0,0,im->xgif-1,0,graph_col[GRC_SHADEA].i);
    gdImageLine(gif,1,1,im->xgif-2,1,graph_col[GRC_SHADEA].i);
    gdImageLine(gif,0,0,0,im->ygif-1,graph_col[GRC_SHADEA].i);
    gdImageLine(gif,1,1,1,im->ygif-2,graph_col[GRC_SHADEA].i);
    gdImageLine(gif,im->xgif-1,0,im->xgif-1,im->ygif-1,graph_col[GRC_SHADEB].i);
    gdImageLine(gif,0,im->ygif-1,im->xgif-1,im->ygif-1,graph_col[GRC_SHADEB].i);
    gdImageLine(gif,im->xgif-2,1,im->xgif-2,im->ygif-2,graph_col[GRC_SHADEB].i);
    gdImageLine(gif,1,im->ygif-2,im->xgif-2,im->ygif-2,graph_col[GRC_SHADEB].i);


    vertical_grid(gif, im);
    
    /* dont draw horizontal grid if there is no min and max val */
	if(im->logarithmic){
		res = horizontal_log_grid(gif,im);
	} else {
		res = horizontal_grid(gif,im);
	}
    if (! res) {
       char *nodata = "No Data found";
       gdImageString(gif, LargeFont,
		     im->xgif/2 
		     - (strlen(nodata)*LargeFont->w)/2,
		     (2*im->yorigin-im->ysize) / 2,
		     nodata, graph_col[GRC_FONT].i);
    }


    /* yaxis description */
    gdImageStringUp(gif, SmallFont,
		    7,
		    (im->yorigin - im->ysize/2
		     +(strlen(im->ylegend)*SmallFont->w)/2 ),
		    im->ylegend, graph_col[GRC_FONT].i);
    

    /* graph title */
    gdImageString(gif, LargeFont,
		    im->xgif/2 
		    - (strlen(im->title)*LargeFont->w)/2,
		  8,
		    im->title, graph_col[GRC_FONT].i);
    
    /* graph labels */

    for(i=0;i<im->gdes_c;i++){
	if(im->gdes[i].legend[0] =='\0')
	    continue;
	
	if(im->gdes[i].gf != GF_GPRINT && im->gdes[i].gf != GF_COMMENT){
	    
	    polyPoints[0].x = im->gdes[i].legloc.x;
	    polyPoints[0].y = im->gdes[i].legloc.y+1;
	    polyPoints[1].x = polyPoints[0].x+boxH;
	    polyPoints[2].x = polyPoints[0].x+boxH;
	    polyPoints[3].x = polyPoints[0].x;
	    polyPoints[1].y = polyPoints[0].y;
	    polyPoints[2].y = polyPoints[0].y+boxV;
	    polyPoints[3].y = polyPoints[0].y+boxV;
	    gdImageFilledPolygon(gif,polyPoints,4,im->gdes[i].col.i);
	    gdImagePolygon(gif,polyPoints,4,graph_col[GRC_FRAME].i);
	
	    gdImageString(gif, SmallFont,
			  polyPoints[0].x+boxH+6, 
			  polyPoints[0].y-1,
			  im->gdes[i].legend,
			  graph_col[GRC_FONT].i);
	} else {
	    polyPoints[0].x = im->gdes[i].legloc.x;
	    polyPoints[0].y = im->gdes[i].legloc.y;
	    
	    gdImageString(gif, SmallFont,
			  polyPoints[0].x, 
			  polyPoints[0].y,
			  im->gdes[i].legend,
			  graph_col[GRC_FONT].i);
	}
    }
    
    
    gator(gif, (int) im->xgif-5, 5);

}


gdImagePtr
MkLineBrush(image_desc_t *im,long cosel, enum gf_en typsel){
  gdImagePtr brush;
  int pen;
  switch (typsel){
  case GF_LINE1:
    brush=gdImageCreate(1,1);
    break;
  case GF_LINE2:
    brush=gdImageCreate(2,2);
    break;
  case GF_LINE3:
    brush=gdImageCreate(3,3);
    break;
  default:
    return NULL;
  }

  gdImageColorTransparent(brush, 
			  gdImageColorAllocate(brush, 0, 0, 0));

  pen = gdImageColorAllocate(brush, 
			     im->gdes[cosel].col.red,
			     im->gdes[cosel].col.green,
			     im->gdes[cosel].col.blue);
    
  switch (typsel){
  case GF_LINE1:
    gdImageSetPixel(brush,0,0,pen);
    break;
  case GF_LINE2:
    gdImageSetPixel(brush,0,0,pen);
    gdImageSetPixel(brush,0,1,pen);
    gdImageSetPixel(brush,1,0,pen);
    gdImageSetPixel(brush,1,1,pen);
    break;
  case GF_LINE3:
    gdImageSetPixel(brush,1,0,pen);
    gdImageSetPixel(brush,0,1,pen);
    gdImageSetPixel(brush,1,1,pen);
    gdImageSetPixel(brush,2,1,pen);
    gdImageSetPixel(brush,1,2,pen);
    break;
  default:
    return NULL;
  }
  return brush;
}
/*****************************************************
 * lazy check make sure we rely need to create this graph
 *****************************************************/

int lazy_check(image_desc_t *im){
    FILE *fd = NULL;
    struct stat  gifstat;
    
    if (im->lazy == 0) return 0; /* no lazy option */
    if (stat(im->graphfile,&gifstat) != 0) 
      return 0; /* can't stat */
    /* one pixel in the existing graph is more then what we would
       change here ... */
    if (time(NULL) - gifstat.st_mtime > 
	(im->end - im->start) / im->xsize) 
      return 0;
    if ((fd = fopen(im->graphfile,"rb")) == NULL) 
      return 0; /* the file does not exist */
    switch (im->imgformat) {
    case IF_GIF:
	GifSize(fd,&(im->xgif),&(im->ygif));
	break;
    case IF_PNG:
	PngSize(fd,&(im->xgif),&(im->ygif));
	break;
    }
    fclose(fd);
    return 1;
}

/* draw that picture thing ... */
int
graph_paint(image_desc_t *im, char ***calcpr)
{
    int i,ii;
    int lazy =     lazy_check(im);
    FILE  *fo;
    
    /* gif stuff */
    gdImagePtr	gif,brush;

    double areazero = 0.0;
    enum gf_en stack_gf = GF_PRINT;
    graph_desc_t *lastgdes = NULL;    
    gdPoint canvas[4], back[4];	 /* points for canvas*/

    /* if we are lazy and there is nothing to PRINT ... quit now */
    if (lazy && im->prt_c==0) return 0;
    
    /* pull the data from the rrd files ... */
    
    if(data_fetch(im)==-1)
	return -1;

    /* evaluate CDEF  operations ... */
    if(data_calc(im)==-1)
	return -1;

    /* calculate and PRINT and GPRINT definitions. We have to do it at
     * this point because it will affect the length of the legends
     * if there are no graph elements we stop here ... 
     * if we are lazy, try to quit ... 
     */
    if(print_calc(im,calcpr)==0 || lazy)
	return 0;

    /* get actual drawing data and find min and max values*/
    if(data_proc(im)==-1)
	return -1;

    if(!im->logarithmic){si_unit(im);}        /* identify si magnitude Kilo, Mega Giga ? */

    if(!im->rigid && ! im->logarithmic)
	expand_range(im);   /* make sure the upper and lower limit are
			   sensible values */

    /* init xtr and ytr */
    /* determine the actual size of the gif to draw. The size given
       on the cmdline is the graph area. But we need more as we have
       draw labels and other things outside the graph area */


    im->xorigin = 10 + 9 * SmallFont->w+SmallFont->h;
    xtr(im,0); 

    im->yorigin = 14 + im->ysize;
    ytr(im,DNAN);

    if(im->title[0] != '\0')
	im->yorigin += (LargeFont->h+4);

    im->xgif=20+im->xsize + im->xorigin;
    im->ygif= im->yorigin+2*SmallFont->h;
    
    /* determine where to place the legends onto the graphics.
       and set im->ygif to match space requirements for text */
    leg_place(im);

    gif=gdImageCreate(im->xgif,im->ygif);

    gdImageInterlace(gif, im->interlaced);
    
    /* allocate colors for the screen elements */
    for(i=0;i<DIM(graph_col);i++)
	/* check for user override values */
	if(im->graph_col[i].red != -1)
	    graph_col[i].i = 
		gdImageColorAllocate( gif,
				      im->graph_col[i].red, 
				      im->graph_col[i].green, 
				      im->graph_col[i].blue);
	else
	    graph_col[i].i = 
		gdImageColorAllocate( gif,
				      graph_col[i].red, 
				      graph_col[i].green, 
				      graph_col[i].blue);
	
    
    /* allocate colors for the graph */
    for(i=0;i<im->gdes_c;i++)
	/* only for elements which have a color defined */
	if (im->gdes[i].col.red != -1)
	    im->gdes[i].col.i = 
		gdImageColorAllocate(gif,
				     im->gdes[i].col.red,
				     im->gdes[i].col.green,
				     im->gdes[i].col.blue);
    
    
    /* the actual graph is created by going through the individual
       graph elements and then drawing them */
    
    back[0].x = 0;
    back[0].y = 0;
    back[1].x = back[0].x+im->xgif;
    back[1].y = back[0].y;
    back[2].x = back[1].x;
    back[2].y = back[0].y+im->ygif;
    back[3].x = back[0].x;
    back[3].y = back[2].y;

    gdImageFilledPolygon(gif,back,4,graph_col[GRC_BACK].i);

    canvas[0].x = im->xorigin;
    canvas[0].y = im->yorigin;
    canvas[1].x = canvas[0].x+im->xsize;
    canvas[1].y = canvas[0].y;
    canvas[2].x = canvas[1].x;
    canvas[2].y = canvas[0].y-im->ysize;
    canvas[3].x = canvas[0].x;
    canvas[3].y = canvas[2].y;

    gdImageFilledPolygon(gif,canvas,4,graph_col[GRC_CANVAS].i);

    if (im->minval > 0.0)
	areazero = im->minval;
    if (im->maxval < 0.0)
	areazero = im->maxval;

    axis_paint(im,gif);

    for(i=0;i<im->gdes_c;i++){	
        
	switch(im->gdes[i].gf){
	case GF_CDEF:
	case GF_DEF:
	case GF_PRINT:
	case GF_GPRINT:
	case GF_COMMENT:
	case GF_HRULE:
	case GF_VRULE:
	  break;
	case GF_LINE1:
	case GF_LINE2:
	case GF_LINE3:
	case GF_AREA:
	    stack_gf = im->gdes[i].gf;
	case GF_STACK:	    
	    /* fix data points at oo and -oo */
	    for(ii=0;ii<im->xsize;ii++){
		if (isinf(im->gdes[i].p_data[ii])){
		    if (im->gdes[i].p_data[ii] > 0) {
			im->gdes[i].p_data[ii] = im->maxval ;
		    } else {
			im->gdes[i].p_data[ii] = im->minval ;
		    }		    
		
		}
	    }

	    if (im->gdes[i].col.i != -1){               
	       /* GF_LINE and frined */
	       if(stack_gf == GF_LINE1 || stack_gf == GF_LINE2 || stack_gf == GF_LINE3 ){
		   brush = MkLineBrush(im,i,stack_gf);
		   gdImageSetBrush(gif, brush);
		   for(ii=1;ii<im->xsize;ii++){
		       if (isnan(im->gdes[i].p_data[ii-1]) ||
			   isnan(im->gdes[i].p_data[ii]))
                            continue;
		       gdImageLine(gif,
                                    ii+im->xorigin-1,ytr(im,im->gdes[i].p_data[ii-1]),
                                    ii+im->xorigin,ytr(im,im->gdes[i].p_data[ii]),
                                    gdBrushed);
                        
                    }
                    gdImageDestroy(brush);
                }
                else 
                    /* GF_AREA STACK type*/
                    if (im->gdes[i].gf == GF_STACK )
                        for(ii=0;ii<im->xsize;ii++){
			    if(isnan(im->gdes[i].p_data[ii])){
				im->gdes[i].p_data[ii] = lastgdes->p_data[ii];
				continue;
			    }
			    
			    if (lastgdes->p_data[ii] == im->gdes[i].p_data[ii]){
				continue;
			    }
			    gdImageLine(gif,
					ii+im->xorigin,ytr(im,lastgdes->p_data[ii]),
					ii+im->xorigin,ytr(im,im->gdes[i].p_data[ii]),
					im->gdes[i].col.i);
			}
	       
		    else /* simple GF_AREA */
			for(ii=0;ii<im->xsize;ii++){
                            if (isnan(im->gdes[i].p_data[ii])) {
				im->gdes[i].p_data[ii] = 0;
                                continue;
			    }
                            gdImageLine(gif,
                                        ii+im->xorigin,ytr(im,areazero),
                                        ii+im->xorigin,ytr(im,im->gdes[i].p_data[ii]),
                                        im->gdes[i].col.i);
                        }
	   }
	   lastgdes = &(im->gdes[i]);	    	   
	   break;
	}
    }
    
    grid_paint(im,gif);

    /* the RULES are the last thing to paint ... */
    for(i=0;i<im->gdes_c;i++){	
        
	switch(im->gdes[i].gf){
	case GF_HRULE:
	    if(im->gdes[i].yrule >= im->minval
	       && im->gdes[i].yrule <= im->maxval)
	      gdImageLine(gif,
			  im->xorigin,ytr(im,im->gdes[i].yrule),
			  im->xorigin+im->xsize,ytr(im,im->gdes[i].yrule),
			  im->gdes[i].col.i); 
	    break;
	case GF_VRULE:
	  if(im->gdes[i].xrule >= im->start
	     && im->gdes[i].xrule <= im->end)
	    gdImageLine(gif,
			xtr(im,im->gdes[i].xrule),im->yorigin,
			xtr(im,im->gdes[i].xrule),im->yorigin-im->ysize,
			im->gdes[i].col.i); 
	  break;
	default:
	    break;
	}
    }

    if (strcmp(im->graphfile,"-")==0) {
	fo = stdout;
    } else {
	if ((fo = fopen(im->graphfile,"wb")) == NULL) {
	    rrd_set_error("cannot open %s for write",im->graphfile);
	    return (-1);
	}
    }
    switch (im->imgformat) {
    case IF_GIF:
	gdImageGif(gif, fo);    
	break;
    case IF_PNG:
	gdImagePng(gif, fo);    
	break;
    }
    if (strcmp(im->graphfile,"-") != 0)
	fclose(fo);
    gdImageDestroy(gif);

    return 0;
}


/*****************************************************
 * graph stuff 
 *****************************************************/

int
gdes_alloc(image_desc_t *im){

    long def_step = (im->end-im->start)/im->xsize;

    im->gdes_c++;
    
    if ((im->gdes = (graph_desc_t *) rrd_realloc(im->gdes, (im->gdes_c)
					   * sizeof(graph_desc_t)))==NULL){
	rrd_set_error("realloc graph_descs");
	return -1;
    }


    im->gdes[im->gdes_c-1].step=def_step; 
    im->gdes[im->gdes_c-1].start=im->start; 
    im->gdes[im->gdes_c-1].end=im->end; 
    im->gdes[im->gdes_c-1].vname[0]='\0'; 
    im->gdes[im->gdes_c-1].data=NULL;
    im->gdes[im->gdes_c-1].ds_namv=NULL;
    im->gdes[im->gdes_c-1].data_first=0;
    im->gdes[im->gdes_c-1].p_data=NULL;
    im->gdes[im->gdes_c-1].rpnp=NULL;
    im->gdes[im->gdes_c-1].col.red = -1;
    im->gdes[im->gdes_c-1].col.i=-1;
    im->gdes[im->gdes_c-1].legend[0]='\0';
    im->gdes[im->gdes_c-1].rrd[0]='\0';
    im->gdes[im->gdes_c-1].ds=-1;    
    im->gdes[im->gdes_c-1].p_data=NULL;    
    return 0;
}

/* copies input untill the first unescaped colon is found
   or until input ends. backslashes have to be escaped as well */
int
scan_for_col(char *input, int len, char *output)
{
    int inp,outp=0;
    for (inp=0; 
	 inp < len &&
	   input[inp] != ':' &&
	   input[inp] != '\0';
	 inp++){
      if (input[inp] == '\\' &&
	  input[inp+1] != '\0' && 
	  (input[inp+1] == '\\' ||
	   input[inp+1] == ':')){
	output[outp++] = input[++inp];
      }
      else {
	output[outp++] = input[inp];
      }
    }
    output[outp] = '\0';
    return inp;
}

int 
rrd_graph(int argc, char **argv, char ***prdata, int *xsize, int *ysize)
{
    
    image_desc_t   im;
    int            i;
    long           long_tmp;
    time_t	   start_tmp=0,end_tmp=0;
    char           scan_gtm[12],scan_mtm[12],scan_ltm[12],col_nam[12];
    char           symname[100];
    unsigned int            col_red,col_green,col_blue;
    long           scancount;
    int linepass = 0; /* stack can only follow directly after LINE* AREA or STACK */    
    struct time_value start_tv, end_tv;
    char *parsetime_error = NULL;

    (*prdata)=NULL;

    parsetime("end-24h", &start_tv);
    parsetime("now", &end_tv);

    im.xlab_user.minsec = -1;
    im.xgif=0;
    im.ygif=0;
    im.xsize = 400;
    im.ysize = 100;
    im.ylegend[0] = '\0';
    im.title[0] = '\0';
    im.minval = DNAN;
    im.maxval = DNAN;    
    im.interlaced = 0;
    im.extra_flags= 0;
    im.rigid = 0;
    im.imginfo = NULL;
    im.lazy = 0;
    im.logarithmic = 0;
    im.ygridstep = DNAN;
    im.base = 1000;
    im.prt_c = 0;
    im.gdes_c = 0;
    im.gdes = NULL;
    im.imgformat = IF_GIF; /* we default to GIF output */

    for(i=0;i<DIM(graph_col);i++)
	im.graph_col[i].red=-1;
    
    
    while (1){
	static struct option long_options[] =
	{
	    {"start",      required_argument, 0,  's'},
	    {"end",        required_argument, 0,  'e'},
	    {"x-grid",     required_argument, 0,  'x'},
	    {"y-grid",     required_argument, 0,  'y'},
	    {"vertical-label",required_argument,0,'v'},
	    {"width",      required_argument, 0,  'w'},
	    {"height",     required_argument, 0,  'h'},
	    {"interlaced", no_argument,       0,  'i'},
	    {"upper-limit",required_argument, 0,  'u'},
	    {"lower-limit",required_argument, 0,  'l'},
	    {"rigid",      no_argument,       0,  'r'},
	    {"base",       required_argument, 0,  'b'},
	    {"logarithmic",no_argument,       0,  'o'},
	    {"color",      required_argument, 0,  'c'},
	    {"title",      required_argument, 0,  't'},
	    {"imginfo",    required_argument, 0,  'f'},
	    {"imgformat",  required_argument, 0,  'a'},
	    {"lazy",       no_argument,       0,  'z'},
	    {"alt-y-grid", no_argument,       0,   257 },
	    {"alt-autoscale", no_argument,    0,   258 },
	    {0,0,0,0}};
	int option_index = 0;
	int opt;

	
	opt = getopt_long(argc, argv, 
			  "s:e:x:y:v:w:h:iu:l:rb:oc:t:f:a:z",
			  long_options, &option_index);

	if (opt == EOF)
	    break;
	
	switch(opt) {
	case 257:
	    im.extra_flags |= ALTYGRID;
	    break;
	case 258:
	    im.extra_flags |= ALTAUTOSCALE;
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
	case 'x':
	    if(sscanf(optarg,
		      "%10[A-Z]:%lu:%10[A-Z]:%lu:%10[A-Z]:%lu:%lu:%100s",
		      scan_gtm,
		      &im.xlab_user.gridst,
		      scan_mtm,
		      &im.xlab_user.mgridst,
		      scan_ltm,
		      &im.xlab_user.labst,
		      &im.xlab_user.precis,
		      im.xlab_form) == 8){
		if((im.xlab_user.gridtm = tmt_conv(scan_gtm)) == -1){
		    rrd_set_error("unknown keyword %s",scan_gtm);
		    return -1;
		} else if ((im.xlab_user.mgridtm = tmt_conv(scan_mtm)) == -1){
		    rrd_set_error("unknown keyword %s",scan_mtm);
		    return -1;
		} else if ((im.xlab_user.labtm = tmt_conv(scan_ltm)) == -1){
		    rrd_set_error("unknown keyword %s",scan_ltm);
		    return -1;
		} 
		im.xlab_user.minsec = 1;
		im.xlab_user.stst = im.xlab_form;
	    } else {
		rrd_set_error("invalid xgrid format");
		return -1;
	    }
	    break;
	case 'y':
	    if(sscanf(optarg,
		      "%lf:%d",
		      &im.ygridstep,
		      &im.ylabfact) == 2) {
		if(im.ygridstep<=0){
		    rrd_set_error("grid step must be > 0");
		    return -1;
		} else if (im.ylabfact < 1){
		    rrd_set_error("label factor must be > 0");
		    return -1;
		} 
	    } else {
		rrd_set_error("invalid ygrid format");
		return -1;
	    }
	    break;
	case 'v':
	    strncpy(im.ylegend,optarg,150);
	    im.ylegend[150]='\0';
	    break;
	case 'u':
	    im.maxval = atof(optarg);
	    break;
	case 'l':
	    im.minval = atof(optarg);
	    break;
	case 'b':
	    im.base = atol(optarg);
	    if(im.base != 1024 && im.base != 1000 ){
		rrd_set_error("the only sensible value for base apart from 1000 is 1024");
		return -1;
	    }
	    break;
	case 'w':
	    long_tmp = atol(optarg);
	    if (long_tmp < 10) {
		rrd_set_error("width below 10 pixels");
		return -1;
	    }
	    im.xsize = long_tmp;
	    break;
	case 'h':
	    long_tmp = atol(optarg);
	    if (long_tmp < 10) {
		rrd_set_error("height below 10 pixels");
		return -1;
	    }
	    im.ysize = long_tmp;
	    break;
	case 'i':
	    im.interlaced = 1;
	    break;
	case 'r':
	    im.rigid = 1;
	    break;
	case 'f':
	    im.imginfo = optarg;
	    break;
    	case 'a':
	    if((im.imgformat = if_conv(optarg)) == -1) {
		rrd_set_error("unsupported graphics format '%s'",optarg);
		return -1;
	    }
	    break;
	case 'z':
	    im.lazy = 1;
	    break;
	case 'o':
	    im.logarithmic = 1;
	    if (isnan(im.minval))
		im.minval=1;
	    break;
	case 'c':
	    if(sscanf(optarg,
		      "%10[A-Z]#%2x%2x%2x",
		      col_nam,&col_red,&col_green,&col_blue) == 4){
		int ci;
		if((ci=grc_conv(col_nam)) != -1){
		    im.graph_col[ci].red=col_red;
		    im.graph_col[ci].green=col_green;
		    im.graph_col[ci].blue=col_blue;
		}  else {
		  rrd_set_error("invalid color name '%s'",col_nam);
		}
	    } else {
		rrd_set_error("invalid color def format");
		return -1;
	    }
	    break;	  
	case 't':
	    strncpy(im.title,optarg,150);
	    im.title[150]='\0';
	    break;

	case '?':
	    rrd_set_error("unknown option '%s'",argv[optind-1]);
	    return -1;
	}
    }
    

    if (im.logarithmic == 1 && (im.minval <= 0 || isnan(im.minval))){
	rrd_set_error("for a logarithmic yaxis you must specify a lower-limit > 0");	
	return -1;
    }

    strncpy(im.graphfile,argv[optind],sizeof(im.graphfile)-1);
    im.graphfile[sizeof(im.graphfile)-1]='\0';

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

    
    for(i=optind+1;i<argc;i++){
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

	/* reset linepass if a non LINE/STACK/AREA operator gets parsed 
	
	   if (im.gdes[im.gdes_c-1].gf != GF_LINE1 &&
	   im.gdes[im.gdes_c-1].gf != GF_LINE2 &&
	   im.gdes[im.gdes_c-1].gf != GF_LINE3 &&
	   im.gdes[im.gdes_c-1].gf != GF_AREA &&
	   im.gdes[im.gdes_c-1].gf != GF_STACK) {
	   linepass = 0;
	   } 
	*/
	
	switch(im.gdes[im.gdes_c-1].gf){
	case GF_PRINT:
	    im.prt_c++;
	case GF_GPRINT:
	    if(sscanf(
		&argv[i][argstart],
		"%29[^#:]:" CF_NAM_FMT ":%n",
		varname,symname,&strstart) == 2){
		scan_for_col(&argv[i][argstart+strstart],FMT_LEG_LEN,im.gdes[im.gdes_c-1].format);
		if((im.gdes[im.gdes_c-1].vidx=find_var(&im,varname))==-1){
		    im_free(&im);
		    rrd_set_error("unknown variable '%s'",varname);
		    return -1;
		}	
		if((im.gdes[im.gdes_c-1].cf=cf_conv(symname))==-1){
		    im_free(&im);
		    return -1;
		}
		
	    } else {
		im_free(&im);
		rrd_set_error("can't parse '%s'",&argv[i][argstart]);
		return -1;
	    }
	    break;
	case GF_COMMENT:
	    if(strlen(&argv[i][argstart])>FMT_LEG_LEN) argv[i][argstart+FMT_LEG_LEN-3]='\0' ;
	    strcpy(im.gdes[im.gdes_c-1].legend, &argv[i][argstart]);
	    break;
	case GF_HRULE:
	    if(sscanf(
		&argv[i][argstart],
		"%lf#%2x%2x%2x:%n",
		&im.gdes[im.gdes_c-1].yrule,
		&col_red,&col_green,&col_blue,
		&strstart) >=  4){
		im.gdes[im.gdes_c-1].col.red = col_red;
		im.gdes[im.gdes_c-1].col.green = col_green;
		im.gdes[im.gdes_c-1].col.blue = col_blue;
		if(strstart <= 0){
		    im.gdes[im.gdes_c-1].legend[0] = '\0';
		} else { 
		    scan_for_col(&argv[i][argstart+strstart],FMT_LEG_LEN,im.gdes[im.gdes_c-1].legend);
		}
	    } else {
		im_free(&im);
		rrd_set_error("can't parse '%s'",&argv[i][argstart]);
		return -1;
	    } 
	    break;
	case GF_VRULE:
	    if(sscanf(
		&argv[i][argstart],
		"%lu#%2x%2x%2x:%n",
		&im.gdes[im.gdes_c-1].xrule,
		&col_red,
		&col_green,
		&col_blue,
		&strstart) >=  4){
		im.gdes[im.gdes_c-1].col.red = col_red;
		im.gdes[im.gdes_c-1].col.green = col_green;
		im.gdes[im.gdes_c-1].col.blue = col_blue;
		if(strstart <= 0){                    
		    im.gdes[im.gdes_c-1].legend[0] = '\0';
		} else { 
		    scan_for_col(&argv[i][argstart+strstart],FMT_LEG_LEN,im.gdes[im.gdes_c-1].legend);
		}
	    } else {
		im_free(&im);
		rrd_set_error("can't parse '%s'",&argv[i][argstart]);
		return -1;
	    }
	    break;
	case GF_STACK:
	    if(linepass == 0){
		im_free(&im);
		rrd_set_error("STACK must follow AREA, LINE or STACK");
		return -1; 
	    }		
	case GF_LINE1:
	case GF_LINE2:
	case GF_LINE3:
	case GF_AREA:
	    linepass = 1;
	    if((scancount=sscanf(
		&argv[i][argstart],
		"%29[^:#]#%2x%2x%2x:%n",
		varname,
		&col_red,
		&col_green,
		    &col_blue,
		&strstart))>=1){
		im.gdes[im.gdes_c-1].col.red = col_red;
		im.gdes[im.gdes_c-1].col.green = col_green;
		im.gdes[im.gdes_c-1].col.blue = col_blue;
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
		if (scancount < 4)
		    im.gdes[im.gdes_c-1].col.red = -1;		
		
	    } else {
		im_free(&im);
		rrd_set_error("can't parse '%s'",&argv[i][argstart]);
		return -1;
	    }
	    break;
	case GF_CDEF:
	    if((rpnex = malloc(strlen(&argv[i][argstart])*sizeof(char)))==NULL){
		rrd_set_error("malloc for CDEF");
		return -1;
	    }
	    if(sscanf(
		    &argv[i][argstart],
		    "%29[_A-Za-z0-9]=%[^: ]",
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
		"%29[_A-Za-z0-9]=%n",
		im.gdes[im.gdes_c-1].vname,
		&strstart)== 1){
		if(sscanf(&argv[i][argstart
				  +strstart
				  +scan_for_col(&argv[i][argstart+strstart],
						254,im.gdes[im.gdes_c-1].rrd)],
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
	}
	
    }

    if (im.gdes_c==0){
	rrd_set_error("can't make a graph without contents");
	im_free(&im);
	return(-1); 
    }
    
	/* parse rest of arguments containing information on what to draw*/
    if (graph_paint(&im,prdata)==-1){
	im_free(&im);
	return -1;
    }
    
    *xsize=im.xgif;
    *ysize=im.ygif;
    if (im.imginfo){
      char *filename;
      if (! (*prdata)) {	
	/* maybe prdata is not allocated yet ... lets do it now */
	if((*prdata = calloc(2,sizeof(char *)))==NULL){
	  rrd_set_error("malloc imginfo");
	  return -1; 
	};
      }
      if(((*prdata)[0] = malloc((strlen(im.imginfo)+200+strlen(im.graphfile))*sizeof(char)))
	 ==NULL){
	rrd_set_error("malloc imginfo");
	return -1;
      }
      filename=im.graphfile+strlen(im.graphfile);      
      while(filename > im.graphfile){
	if (*(filename-1)=='/' || *(filename-1)=='\\' ) break;
	filename--;
      }
      
      sprintf((*prdata)[0],im.imginfo,filename,im.xgif,im.ygif);
    }
    im_free(&im);
    return 0;
}


