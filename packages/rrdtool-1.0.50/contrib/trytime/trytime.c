#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>
#include <rrd_tool.h>

#ifndef	WANT_AT_STYLE_TIMESPEC
#define	WANT_AT_STYLE_TIMESPEC
#endif

#define BUF_LEN 128

static char soption[BUF_LEN];
static char eoption[BUF_LEN];

int main ( int ac, char **av )
{
  static struct option long_options[] =
  {
     {"start",      required_argument, 0, 's'},
     {"end",        required_argument, 0, 'e'},
     {0,0,0,0}};
  int option_index = 0;
  int opt;
   
  time_t start_tmp, end_tmp, Now = time(NULL);
  char tim_b[200];
  
  struct rrd_time_value start_tv, end_tv;
  char *parsetime_error = NULL;
  
  /* default values */
  parsetime("end-24h", &start_tv);
  parsetime("now", &end_tv);

  if( ac < 2 )
    {
    printf( "usage: %s [--start|-s start] [--end|-e end]\n"
	    "\n"
	    "In plain English, this means that to time specification try\n"
	    "a single time specification (just like in the rrdtool create)\n"
	    "you can use the first form, while to try two of them at once\n"
	    "(just like in rrdtool graph or fetch) you need the seconf form\n",
	    av[0] );
    exit(0);
    }
  
  printf( "The time now is: %s\n", ctime(&Now) );
  
  while(1){
	opt = getopt_long(ac, av, "s:e:", long_options, &option_index);
    
	if (opt == EOF)  
	    break;
	
	switch(opt)
	{
	case 's': 
	    strncpy( soption, optarg, BUF_LEN );
	    if ((parsetime_error = parsetime(optarg, &start_tv))) {
		fprintf( stderr, "ERROR: start time: %s\n", parsetime_error );
		exit(1);
	    }
	    
	    break;
	case 'e': 
	    strncpy( eoption, optarg, BUF_LEN );
	    if ((parsetime_error = parsetime(optarg, &end_tv))) {
	        fprintf( stderr, "ERROR: end time: %s\n", parsetime_error );
		exit(1);
	    }	    
 	    break;
	}
  }
  
  if (proc_start_end(&start_tv,&end_tv,&start_tmp,&end_tmp) == -1){
      printf("ERROR: %s\n",rrd_get_error());
      rrd_clear_error();
      exit(1);
  }
  
  strftime(tim_b,100,"%c %Z",localtime(&start_tmp));
  if( *soption )
      printf( "Start time was specified as: '%s',\n"
	      "for me this means: %s (or %ld sec since epoch)\n\n", 
              soption, tim_b, start_tmp );
    else
      printf( "Start time was not specified, default value will be used (end-24h)\n"
	      "for me this means: %s (or %ld sec since epoch)\n\n",
	      tim_b, start_tmp );
    
  strftime(tim_b,100,"%c %Z",localtime(&end_tmp));
  if( *eoption )
      printf( "End time was specified as: '%s',\n"
	      "for me this means: %s (or %ld sec since epoch)\n", 
              eoption, tim_b, end_tmp );
  else
      printf( "End time was not specified, default value will be used (now)\n"
	      "for me this means: %s (or %ld sec since epoch)\n\n",
	      tim_b, end_tmp );
  exit(0);
}


