#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "getopt.h"
#include "parsetime.h"

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
  char *ct;

#ifdef WANT_AT_STYLE_TIMESPEC
    struct time_value start_tv, end_tv;
    char *parsetime_error = NULL;
    int start_tmp_is_ok = 0,
	end_tmp_is_ok = 0;
#endif

    /* default values */
    end_tmp = time(NULL);
    start_tmp = -24*3600;
#ifdef WANT_AT_STYLE_TIMESPEC
    end_tv.type = ABSOLUTE_TIME;
    end_tv.tm = *localtime(&end_tmp);
    end_tv.offset = 0;

    start_tv.type = RELATIVE_TO_END_TIME;
    start_tv.tm = *localtime(&end_tmp); /* to init tm_zone and tm_gmtoff */
    start_tv.offset = -24*3600;/* to be compatible with the original code.  */
    start_tv.tm.tm_sec = 0;    /** alternatively we could set tm_mday to -1 */
    start_tv.tm.tm_min = 0;    /** but this would yield -23(25) hours offset */
    start_tv.tm.tm_hour = 0;   /** twice a year, when DST is coming in or   */
    start_tv.tm.tm_mday = 0;   /** out of effect                            */
    start_tv.tm.tm_mon = 0;
    start_tv.tm.tm_year = 0;
    start_tv.tm.tm_wday = 0;
    start_tv.tm.tm_yday = 0;
    start_tv.tm.tm_isdst = -1; /* for mktime to guess */
#endif
    *soption = '\0';
    *eoption = '\0';

  if( ac < 2 )
    {
    printf( "usage: %s time-specification-to-try\n"
	    "or     %s [--start|-s start] [--end|-e end]\n"
	    "\n"
	    "In plain English, this means that to time specification try\n"
	    "a single time specification (just like in the rrdtool create)\n"
	    "you can use the first form, while to try two of them at once\n"
	    "(just like in rrdtool graph or fetch) you need the seconf form\n",
	    av[0], av[0] );
    exit(0);
    }

  printf( "The time now is: %s\n", ctime(&Now) );

  if( av[1][0] != '-' )
    {
    if( ac > 2 )
      {
      printf( "Warning: you specified several arguments,\n"
	      "         of those I will use only one: '%s'\n"
	      "(hint: perhaps, you should put quotes around your timespec?)\n",
	      av[1] );
      }
#ifdef WANT_AT_STYLE_TIMESPEC
    {
    char *endp;
    start_tmp_is_ok = 0;
    start_tmp = strtol(av[1], &endp, 0);
    if (*endp == '\0') /* it was a valid number */
        if (start_tmp > 31122038 || /* 31 Dec 2038 in DDMMYYYY */
            start_tmp < 0) {
            start_tmp_is_ok = 1;
            goto CheckRelative;
        }
    if ((parsetime_error = parsetime(av[1], &start_tv))) {
        fprintf( stderr, "ERROR: %s\n", parsetime_error );
        return(-1);
    }
    if (start_tv.type == RELATIVE_TO_END_TIME ||
        start_tv.type == RELATIVE_TO_START_TIME) {
        fprintf( stderr, "ERROR: specifying time relative to the 'start' "
                      "or 'end' makes no sense here\n");
        return(-1);
    }
    if (!start_tmp_is_ok)
        start_tmp = mktime(&start_tv.tm) + start_tv.offset;
    }/* this is for the entire block */

#else
    start_tmp = atol(av[1]);
#endif
CheckRelative:
    if (start_tmp < 0) /* if time is negative this means go back from now. */
      start_tmp = time(NULL)+start_tmp;

    {
    ct = ctime(&start_tmp);
    ct[24] = '\0'; /* zap that nasty embedded'\n' */
    printf( "You specified the following: '%s',\n"
	     "for me this means: %s (or %ld sec since epoch)\n\n", 
              av[1], ct, start_tmp );

    }
    exit(0);
    }/* if( av[1][0]... */

  while(1)
    {
    opt = getopt_long(ac, av, "s:e:", long_options, &option_index);

    if (opt == EOF)  
       break;
    
    switch(opt)
      {
      case 's': 
	 strncpy( soption, optarg, BUF_LEN );
#ifdef WANT_AT_STYLE_TIMESPEC
	    {
	    char *endp;
	    start_tmp_is_ok = 0;
	    start_tmp = strtol(optarg, &endp, 0);
	    if (*endp == '\0') /* it was a valid number */
	        if (start_tmp > 31122038 || /* 31 Dec 2038 in DDMMYYYY */
		    start_tmp < 0) {
		    start_tmp_is_ok = 1;
		    break;
		}
	    if ((parsetime_error = parsetime(optarg, &start_tv))) {
	        fprintf( stderr, "ERROR: start time: %s\n", parsetime_error );
		return -1;
	     }
	    }
#else
	    start_tmp = atol(optarg);
#endif
	    break;
      case 'e': 
	 strncpy( eoption, optarg, BUF_LEN );
#ifdef WANT_AT_STYLE_TIMESPEC
	    {
	    char *endp;
	    end_tmp_is_ok = 0;
	    end_tmp = strtol(optarg, &endp, 0);
	    if (*endp == '\0') /* it was a valid number */
	        if (end_tmp > 31122038) { /* 31 Dec 2038 in DDMMYYYY */
		    end_tmp_is_ok = 1;
		    break;
		}
	    if ((parsetime_error = parsetime(optarg, &end_tv))) {
	        fprintf( stderr, "ERROR: end time: %s\n", parsetime_error );
		return -1;
	     }
	    }
#else
 	    end_tmp = atol(optarg);
#endif
 	    break;
      }
    }

#ifdef WANT_AT_STYLE_TIMESPEC
    if ((start_tv.type == RELATIVE_TO_END_TIME ||
	   (start_tmp_is_ok && start_tmp < 0)) && /* same as the line above */
           end_tv.type == RELATIVE_TO_START_TIME) {
	fprintf( stderr, "the start and end times cannot be specified "
		      "relative to each other\n");
	return(-1);
    }

    if (start_tv.type == RELATIVE_TO_START_TIME) {
	fprintf( stderr, "the start time cannot be specified relative to itself\n");
	return(-1);
    }

    if (end_tv.type == RELATIVE_TO_END_TIME) {
	fprintf( stderr, "the end time cannot be specified relative to itself\n");
	return(-1);
    }

    /* We don't care to keep all the values in their range,
       mktime will do this for us */
    if (start_tv.type == RELATIVE_TO_END_TIME) {
	if (end_tmp_is_ok)
	    end_tv.tm = *localtime( &end_tmp );
	start_tv.tm.tm_sec  += end_tv.tm.tm_sec; 
	start_tv.tm.tm_min  += end_tv.tm.tm_min; 
	start_tv.tm.tm_hour += end_tv.tm.tm_hour; 
	start_tv.tm.tm_mday += end_tv.tm.tm_mday; 
	start_tv.tm.tm_mon  += end_tv.tm.tm_mon; 
	start_tv.tm.tm_year += end_tv.tm.tm_year; 
    }
    if (end_tv.type == RELATIVE_TO_START_TIME) {
	if (start_tmp_is_ok)
	    start_tv.tm = *localtime( &start_tmp );
	end_tv.tm.tm_sec  += start_tv.tm.tm_sec; 
	end_tv.tm.tm_min  += start_tv.tm.tm_min; 
	end_tv.tm.tm_hour += start_tv.tm.tm_hour; 
	end_tv.tm.tm_mday += start_tv.tm.tm_mday; 
	end_tv.tm.tm_mon  += start_tv.tm.tm_mon; 
	end_tv.tm.tm_year += start_tv.tm.tm_year; 
    }
    if (!start_tmp_is_ok)
        start_tmp = mktime(&start_tv.tm) + start_tv.offset;
    if (!end_tmp_is_ok)
        end_tmp = mktime(&end_tv.tm) + end_tv.offset;
#endif

    if (start_tmp < 0) 
 	start_tmp = end_tmp + start_tmp;
     
    ct = ctime(&start_tmp);
    ct[24] = '\0'; /* zap that nasty embedded'\n' */
    if( *soption )
      printf( "Start time was specified as: '%s',\n"
	      "for me this means: %s (or %ld sec since epoch)\n\n", 
              soption, ct, start_tmp );
    else
      printf( "Start time was not specified, default value will be used (-86400)\n"
	      "for me this means: %s (or %ld sec since epoch)\n\n",
	      ct, start_tmp );
    
    ct = ctime(&end_tmp);
    ct[24] = '\0';
    if( *eoption )
      printf( "End time was specified as: '%s',\n"
	      "for me this means: %s (or %ld sec since epoch)\n", 
              eoption, ct, end_tmp );
    else
      printf( "End time was not specified, default value will be used (now)\n"
	      "for me this means: %s (or %ld sec since epoch)\n\n",
	      ct, start_tmp );

  exit(0);
}


