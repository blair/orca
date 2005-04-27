/****************************************************************************
 * RRDtool 1.0.50  Copyright Tobias Oetiker, 1997 - 2000
 ****************************************************************************
 * rrd__graph.h  
 ****************************************************************************/
#ifdef  __cplusplus
extern "C" {
#endif

#ifndef _RRD_GRAPH_H
#define _RRD_GRAPH_H


#define DEF_NAM_FMT "%29[_A-Za-z0-9]"

enum tmt_en {TMT_SECOND=0,TMT_MINUTE,TMT_HOUR,TMT_DAY,
	     TMT_WEEK,TMT_MONTH,TMT_YEAR};

enum grc_en {GRC_CANVAS=0,GRC_BACK,GRC_SHADEA,GRC_SHADEB,
	     GRC_GRID,GRC_MGRID,GRC_FONT,GRC_FRAME,GRC_ARROW,__GRC_END__};


enum gf_en {GF_PRINT=0,GF_GPRINT,GF_COMMENT,GF_HRULE,GF_VRULE,GF_LINE1,
	    GF_LINE2,GF_LINE3,GF_AREA,GF_STACK, GF_DEF, GF_CDEF, GF_XPORT };

enum op_en {OP_NUMBER=0,OP_VARIABLE,OP_INF,OP_PREV,OP_PREV_OTHER,OP_NEGINF,
	    OP_UNKN,OP_NOW,OP_TIME,OP_LTIME,OP_ADD,OP_MOD,
            OP_SUB,OP_MUL,
	    OP_DIV,OP_SIN, OP_DUP, OP_EXC, OP_POP,
	    OP_COS,OP_LOG,OP_EXP,OP_LT,OP_LE,OP_GT,OP_GE,OP_EQ,OP_IF,
	    OP_MIN,OP_MAX,OP_LIMIT, OP_FLOOR, OP_CEIL,
	    OP_UN,OP_END};

enum if_en {IF_GIF=0,IF_PNG=1,IF_GD=2};

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

typedef struct ylab_t {
    double   grid;    /* grid spacing */
    int      lfac[4]; /* associated label spacing*/
} ylab_t;

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

typedef struct image_desc_t {

    /* configuration of graph */

    char           graphfile[MAXPATH]; /* filename for graphic */
    long           xsize,ysize;    /* graph area size in pixels */
    col_trip_t     graph_col[__GRC_END__]; /* real colors for the graph */   
    char           ylegend[200];   /* legend along the yaxis */
    char           title[200];     /* title for graph */
    int            draw_x_grid;      /* no x-grid at all */
    int            draw_y_grid;      /* no x-grid at all */
    xlab_t         xlab_user;      /* user defined labeling for xaxis */
    char           xlab_form[200]; /* format for the label on the xaxis */

    double         ygridstep;      /* user defined step for y grid */
    int            ylabfact;       /* every how many y grid shall a label be written ? */

    time_t         start,end;      /* what time does the graph cover */
    unsigned long           step;           /* any preference for the default step ? */
    rrd_value_t    minval,maxval;  /* extreme values in the data */
    int            rigid;          /* do not expand range even with 
				      values outside */
    char*          imginfo;         /* construct an <IMG ... tag and return 
				      as first retval */
    int            lazy;           /* only update the gif if there is reasonable
				      probablility that the existing one is out of date */
    int            logarithmic;    /* scale the yaxis logarithmic */
    int            quadrant;         
    double          scaledstep;
    int            decimals;
    enum if_en     imgformat;         /* image format */
    
    char* bkg_image; /* background image source */
    char* ovl_image; /* overlay image source */
    char* unit; /* measured value unit */

    /* status information */
    	    
    long           xorigin,yorigin;/* where is (0,0) of the graph */
    long           xgif,ygif;      /* total size of the gif */
    int            interlaced;     /* will the graph be interlaced? */
    double         magfact;        /* numerical magnitude*/
    long           base;            /* 1000 or 1024 depending on what we graph */
    char           symbol;         /* magnitude symbol for y-axis */
    int            unitsexponent;    /* 10*exponent for units on y-asis */
    int            unitslength;    /* character length for units on y-asis */
    int            extra_flags;    /* flags for boolean options */
    /* data elements */

    long  prt_c;                  /* number of print elements */
    long  gdes_c;                  /* number of graphics elements */
    graph_desc_t   *gdes;          /* points to an array of graph elements */

} image_desc_t;

/* Prototypes */
int xtr(image_desc_t *,time_t);
int ytr(image_desc_t *, double);
enum gf_en gf_conv(char *);
enum if_en if_conv(char *);
enum tmt_en tmt_conv(char *);
enum grc_en grc_conv(char *);
int im_free(image_desc_t *);
void auto_scale( image_desc_t *,  double *, char **, double *);
void si_unit( image_desc_t *);
void expand_range(image_desc_t *);
void reduce_data( enum cf_en,  unsigned long,  time_t *, time_t *,  unsigned long *,  unsigned long *,  rrd_value_t **);
int data_fetch( image_desc_t *);
long find_var(image_desc_t *, char *);
long lcd(long *);
int data_calc( image_desc_t *);
int data_proc( image_desc_t *);
time_t find_first_time( time_t,  enum tmt_en,  long);
time_t find_next_time( time_t,  enum tmt_en,  long);
void gator( gdImagePtr, int, int);
int tzoffset(time_t);
int print_calc(image_desc_t *, char ***);
int leg_place(image_desc_t *);
int horizontal_grid(gdImagePtr, image_desc_t *);
int horizontal_mrtg_grid(gdImagePtr, image_desc_t *);
int horizontal_log_grid(gdImagePtr, image_desc_t *);
void vertical_grid( gdImagePtr, image_desc_t *);
void axis_paint( image_desc_t *, gdImagePtr);
void grid_paint( image_desc_t *, gdImagePtr);
gdImagePtr MkLineBrush(image_desc_t *,long, enum gf_en);
void copyImage(gdImagePtr gif, char *bkg_image, int copy_white);
int lazy_check(image_desc_t *);
int graph_paint(image_desc_t *, char ***);
int gdes_alloc(image_desc_t *);
int scan_for_col(char *, int, char *);
int rrd_graph(int, char **, char ***, int *, int *);
int bad_format(char *);
rpnp_t * str2rpn(image_desc_t *,char *);
int color_allocate(gdImagePtr, int, int, int);

#define ALTYGRID          0x01  /* use alternative y grid algorithm */
#define ALTAUTOSCALE      0x02  /* use alternative algorithm to find lower and upper bounds */
#define ALTAUTOSCALE_MAX  0x04  /* use alternative algorithm to find upper bounds */
#define NOLEGEND          0x08  /* use no legend */
#define ALTYMRTG          0x10  /* simulate mrtg's scaling */
#define NOMINOR           0x20  /* Turn off minor gridlines */
#define FORCE_RULES_LEGEND 0x40  /* force printing of HRULE and VRULE legend */
#define ONLY_GRAPH        0x80   /* use only graph*/

#endif


#ifdef  __cplusplus
}
#endif
