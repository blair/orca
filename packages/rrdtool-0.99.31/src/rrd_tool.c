/*****************************************************************************
 * RRDTOOL 0.99.31 Copyright Tobias Oetiker, 1997, 1998, 1999
 *****************************************************************************
 * rrd_tool.c  Startup wrapper
 *****************************************************************************
 * $Id: rrd_tool.c,v 1.8 1998/03/08 12:35:11 oetiker Exp oetiker $
 * $Log: rrd_tool.c,v $
 *****************************************************************************/

#include "rrd_tool.h"

void PrintUsage(void);
int CountArgs(char *aLine);
int CreateArgs(char *, char *, int, char **);
int HandleInputLine(int, char **, FILE*);
#define TRUE		1
#define FALSE		0
#define MAX_LENGTH	10000


void PrintUsage(void)
{
    printf("\n"
	   "RRD TOOL 0.99.28  Copyright (C) 1999 by Tobias Oetiker <tobi@oetiker.ch>\n\n"
	   "Usage: rrdtool [options] command command_options\n\n"
	   "Valid commands and command_options are listed below.\n\n"

	   "* create - create a new RRD\n\n"
	   "\trrdtool create filename [--start|-b start time]\n"
	   "\t\t[--step|-s step]\n"
	   "\t\t[DS:ds-name:DST:heartbeat:min:max] [RRA:CF:xff:steps:rows]\n\n"

	   "* dump - dump an RRD\n\n"
	   "\trrdtool dump filename.rrd [--full|-f]\n\n"

           "* last - show last update time for RRD\n\n"
           "\trrdtool last filename.rrd\n\n"

	   "* update - update an RRD\n\n"
	   "\trrdtool update filename\n"
	   "\t\ttime|N:value[:value...]\n\n"
	   "\t\t[ time:value[:value...] ..]\n\n"

	   "* fetch - fetch data out of an RRD\n\n"
	   "\trrdtool fetch filename.rrd CF\n"
	   "\t\t[--resolution|-r resolution]\n"
	   "\t\t[--start|-s start] [--end|-e end]\n\n"
	   	   
	   "* graph - generate a graph from one or several RRD\n\n"
	   "\trrdtool graph filename [-s|--start seconds] [-e|--end seconds]\n"
	   "\t\t[-x|--x-grid x-axis grid and label]\n"
	   "\t\t[-y|--y-grid y-axis grid and label]\n"
	   "\t\t[-v|--vertical-label string] [-w|--width pixels]\n"
	   "\t\t[-h|--height pixels] [-o|--logarithmic]\n"
	   "\t\t[-u|--upper-limit value]\n"
	   "\t\t[-l|--lower-limit value] [-r|--rigid]\n"
	   "\t\t[-c|--color COLORTAG#rrggbb] [-t|--title string]\n"
	   "\t\t[DEF:vname=rrd:ds-name:CF]\n"
	   "\t\t[CDEF:vname=rpn-expression]\n"
	   "\t\t[PRINT:vname:CF:format]\n"
	   "\t\t[GPRINT:vname:CF:format]\n"
	   "\t\t[HRULE:value#rrggbb[:legend]]\n"
	   "\t\t[VRULE:value#rrggbb[:legend]]\n"
	   "\t\t[LINE{1|2|3}:vname[#rrggbb[:legend]]]\n"
	   "\t\t[AREA:vname[#rrggbb[:legend]]]\n"
	   "\t\t[STACK:vname[#rrggbb[:legend]]]\n\n"

	   
	   " * tune -  Modify some basic properties of an RRD\n\n"
	   "\trrdtool tune filename\n"
	   "\t\t[--heartbeat|-h ds-name:heartbeat]\n"
	   "\t\t[--data-source-type|-d ds-name:DST\n"
	   "\t\t[--data-source-rename|-r old-name:new-name\n"
	   "\t\t[--minimum|-i ds-name:min] [--maximum|-a ds-name:max]\n\n"

	   " * resize - alter the lenght of one of the RRAs in an RRD\n\n"
	   "\trrdtool resize filename rranum GROW|SHRINK rows\n\n"

	   "RRD TOOL is distributed under the Terms of the GNU General\n"
	   "Public License Version 2. (www.gnu.org/copyleft/gpl.html)\n\n"

	   "For more information read the RRD manpages\n\n");
}


int main(int argc, char *argv[])
{
    char **myargv;
    char aLine[MAX_LENGTH];

    if (argc == 1)
	{
	    PrintUsage();
	    return 0;
	}
    
    if ((argc == 2) && (*argv[1] == '-'))
	{
#if HAVE_GETRUSAGE
	  struct rusage  myusage;
	  struct timeval starttime;
	  struct timeval currenttime;
	  struct timezone tz;

	    tz.tz_minuteswest =0;
	    tz.tz_dsttime=0;
	    gettimeofday(&starttime,&tz);
#endif

	    while (fgets(aLine, sizeof(aLine)-1, stdin)){
		if ((argc = CountArgs(aLine)) == 0)  {
		    fprintf(stderr,"ERROR: not enough arguments\n");		    
		}
		if ((myargv = (char **) malloc((argc+1) * 
					       sizeof(char *))) == NULL)   {
		    perror("malloc");
		    return -1;
		}
		if ((argc=CreateArgs(argv[0], aLine, argc, myargv)) < 0) {
		    fprintf(stderr, "ERROR: creating arguments\n");
		    return -1;
		}

		if (HandleInputLine(argc, myargv, stdout))
		    return -1;
		free(myargv);

#if HAVE_GETRUSAGE
		getrusage(RUSAGE_SELF,&myusage);
		gettimeofday(&currenttime,&tz);
		printf("OK u:%1.2f s:%1.2f r:%1.2f\n",
		       (double)myusage.ru_utime.tv_sec+
		       (double)myusage.ru_utime.tv_usec/1000000.0,
		       (double)myusage.ru_stime.tv_sec+
		       (double)myusage.ru_stime.tv_usec/1000000.0,
		       (double)(currenttime.tv_sec-starttime.tv_sec)
		       +(double)(currenttime.tv_usec-starttime.tv_usec)
		       /1000000.0);
#else
		printf("OK\n");
#endif
		fflush(stdout); /* this is important for pipes to work */
	    }
	}
    else
	HandleInputLine(argc, argv, stderr);    
    return 0;
}

int HandleInputLine(int argc, char **argv, FILE* out)
{
    optind=0; /* reset gnu getopt */
    opterr=0; /* no error messages */

    if (argc < 3 
	|| strcmp("help", argv[1]) == 0
	|| strcmp("-h", argv[1]) == 0 ) {
	PrintUsage();
	return 0;
    }
    
    if (strcmp("create", argv[1]) == 0)	
	rrd_create(argc-1, &argv[1]);
    else if (strcmp("dump", argv[1]) == 0)
	rrd_dump(argc-1, &argv[1]);
    else if (strcmp("resize", argv[1]) == 0)
	rrd_resize(argc-1, &argv[1]);
    else if (strcmp("last", argv[1]) == 0)
        printf("%ld\n",rrd_last(argc-1, &argv[1]));
    else if (strcmp("update", argv[1]) == 0)
	rrd_update(argc-1, &argv[1]);
    else if (strcmp("fetch", argv[1]) == 0) {
	time_t        start,end;
	unsigned long step, ds_cnt,i,ii;
	rrd_value_t   *data,*datai;
	char          **ds_namv;
	if (rrd_fetch(argc-1, &argv[1],&start,&end,&step,&ds_cnt,&ds_namv,&data) != -1) {
	    datai=data;
	    printf("           ");
	    for (i = 0; i<ds_cnt;i++)
	        printf("%10s",ds_namv[i]);
	    printf ("\n\n");
	    for (i = start; i <= end; i += step){
	        printf("%10lu:", i);
	        for (ii = 0; ii < ds_cnt; ii++)
		    printf("%10.2f", *(datai++));
	        printf("\n");
	    }
	    for (i=0;i<ds_cnt;i++)
	          free(ds_namv[i]);
	    free(ds_namv);
	    free (data);
	}
    }
    else if (strcmp("graph", argv[1]) == 0) {
	char **calcpr;
	int xsize, ysize;
	int i;
	calcpr = NULL;
	if( rrd_graph(argc-1, &argv[1], &calcpr, &xsize, &ysize) != -1 ) {
	    if (strcmp(argv[2],"-") != 0) 
		printf ("%dx%d\n",xsize,ysize);
	    if (calcpr) {
		for(i=0;calcpr[i];i++){
		    if (strcmp(argv[2],"-") != 0) 
			printf("%s\n",calcpr[i]);
		    free(calcpr[i]);
		} 
		free(calcpr);
	    }
	}
	
    } else if (strcmp("tune", argv[1]) == 0) 
		rrd_tune(argc-1, &argv[1]);
    else {
		rrd_set_error("unknown function '%s'",argv[1]);
    }
    if (rrd_test_error()) {
	fprintf(out, "ERROR: %s\n",rrd_get_error());
	rrd_clear_error();
    }
    return(0);
}

int CountArgs(char *aLine)
{
    int i=0;
    int aCount = 0;
    int inarg = 0;
    while (aLine[i] == ' ') i++;
    while (aLine[i] != 0){       
	if((aLine[i]== ' ') && inarg){
	    inarg = 0;
	}
	if((aLine[i]!= ' ') && ! inarg){
	    inarg = 1;
	    aCount++;
	}
	i++;
    }
    return aCount;
}

/*
 * CreateArgs - take a string (aLine) and tokenize
 */
int CreateArgs(char *pName, char *aLine, int argc, char **argv)
{
    char	*getP, *putP;
    char	**pargv = argv;
    char        Quote = 0;
    int inArg = 0;
    int	len;

    len = strlen(aLine);
    /* remove trailing space and newlines */
    while (len && aLine[len] <= ' ') {
	aLine[len] = 0 ; len--;
    }
    /* sikp leading blanks */
    while (*aLine && *aLine <= ' ') aLine++;

    pargv[0] = pName;
    argc = 1;
    getP = aLine;
    putP = aLine;
    while (*getP){
	switch (*getP) {
	case ' ': 
	    if (Quote){
		*(putP++)=*getP;
	    } else 
		if(inArg) {
		    *(putP++) = 0;
		    inArg = 0;
		}
	    break;
	case '"':
	case '\'':
	    if (Quote != 0) {
		if (Quote == *getP) 
		    Quote = 0;
		else {
		    *(putP++)=*getP;
		}
	    } else {
		if(!inArg){
		    pargv[argc++] = putP;
		    inArg=1;
		}	    
		Quote = *getP;
	    }
	    break;
	default:
	    if(!inArg){
		pargv[argc++] = putP;
		inArg=1;
	    }
	    *(putP++)=*getP;
	    break;
	}
	getP++;
    }

    *putP = '\0';

    if (Quote) 
	return -1;
    else
	return argc;
}


