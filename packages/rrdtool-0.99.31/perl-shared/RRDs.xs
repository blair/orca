#ifdef __cplusplus
extern "C" {
#endif

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#ifdef __cplusplus
}
#endif

#include "../src/rrd_tool.h"

#define rrdcode(name) \
		argv = (char **) malloc((items+1)*sizeof(char *));\
		argv[0] = "dummy";\
		for (i = 0; i < items; i++) argv[i+1] = (char *) SvPV(ST(i),na);\
		optind=0; opterr=0; \
		rrd_clear_error();\
		RETVAL=name(items+1,argv); free(argv);\
		if (rrd_get_error() != NULL) XSRETURN_UNDEF;


#ifdef WIN32
 #define free free
 #define malloc malloc
 #define realloc realloc
#endif /*WIN32*/


MODULE = RRDs	PACKAGE = RRDs	PREFIX = rrd_

SV*
rrd_error()
	CODE:
		if (! rrd_test_error()) XSRETURN_UNDEF;
                RETVAL = newSVpv(rrd_get_error(),0);
	OUTPUT:
		RETVAL

	
int
rrd_last(...)
      PROTOTYPE: @
      PREINIT:
      int i;
      char **argv;
      CODE:
              rrdcode(rrd_last);
      OUTPUT:
            RETVAL


int
rrd_create(...)
	PROTOTYPE: @	
	PREINIT:
        int i;
	char **argv;
	CODE:
		rrdcode(rrd_create);
	        RETVAL = 1;
        OUTPUT:
		RETVAL


int
rrd_update(...)
	PROTOTYPE: @	
	PREINIT:
        int i;
	char **argv;
	CODE:
		rrdcode(rrd_update);
       	        RETVAL = 1;
	OUTPUT:
		RETVAL


void
rrd_graph(...)
	PROTOTYPE: @	
	PREINIT:
	char **calcpr;
	int i,xsize,ysize;
	char **argv;
	AV *retar;
	PPCODE:
		calcpr = NULL;
		argv = (char **) malloc((items+1)*sizeof(char *));
		argv[0] = "dummy";
		for (i = 0; i < items; i++) argv[i+1] = (char *) SvPV(ST(i),na);
		optind=0; opterr=0; 
		rrd_clear_error();
		rrd_graph(items+1,argv,&calcpr,&xsize,&ysize); free(argv);

		if (rrd_test_error()) {
			if(calcpr)
			   for(i=0;calcpr[i];i++)
				free(calcpr[i]);
			XSRETURN_UNDEF;
		}
		retar=newAV();
		if(calcpr){
			for(i=0;calcpr[i];i++){
				 av_push(retar,newSVpv(calcpr[i],0));
				 free(calcpr[i]);
			}
			free(calcpr);
		}
		EXTEND(sp,4);
		PUSHs(sv_2mortal(newRV_inc((SV*)retar)));
		PUSHs(sv_2mortal(newSViv(xsize)));
		PUSHs(sv_2mortal(newSViv(ysize)));

void
rrd_fetch(...)
	PROTOTYPE: @	
	PREINIT:
		time_t        start,end;		
		unsigned long step, ds_cnt,i,ii;
		rrd_value_t   *data,*datai;
		char **argv;
		char **ds_namv;
		AV *retar,*line,*names;
	PPCODE:
		argv = (char **) malloc((items+1)*sizeof(char *));
		argv[0] = "dummy";
		for (i = 0; i < items; i++) argv[i+1] = (char *) SvPV(ST(i),na);
		optind=0; opterr=0; 
		rrd_clear_error();
		rrd_fetch(items+1,argv,&start,&end,&step,&ds_cnt,&ds_namv,&data); 
		if (rrd_test_error()) XSRETURN_UNDEF;
		free(argv);
		/* convert the ds_namv into perl format */
		names=newAV();
		for (ii = 0; ii < ds_cnt; ii++){
		    av_push(names,newSVpv(ds_namv[ii],0));
		    free(ds_namv[ii]);
		}
		free(ds_namv);			
		/* convert the data array into perl format */
		datai=data;
		retar=newAV();
		for (i = start; i <= end; i += step){
			line = newAV();
			for (ii = 0; ii < ds_cnt; ii++)
				av_push(line,newSVnv(*(datai++)));
			av_push(retar,newRV_noinc((SV*)line));
		}
		free(data);
		EXTEND(sp,5);
		PUSHs(sv_2mortal(newSViv(start)));
		PUSHs(sv_2mortal(newSViv(step)));
		PUSHs(sv_2mortal(newRV_inc((SV*)names)));
		PUSHs(sv_2mortal(newRV_inc((SV*)retar)));

int
rrd_tune(...)
	PROTOTYPE: @	
	PREINIT:
        int i;
	char **argv;
	CODE:
		rrdcode(rrd_tune);
       	        RETVAL = 1;
	OUTPUT:
		RETVAL





