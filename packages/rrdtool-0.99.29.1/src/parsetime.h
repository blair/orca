#ifndef __PARSETIME_H__
#define __PARSETIME_H__

#include <time.h>
#include <stdio.h>

typedef enum {
	ABSOLUTE_TIME,
	RELATIVE_TO_START_TIME, 
	RELATIVE_TO_END_TIME
} timetype;

#define TIME_OK NULL

struct time_value {
  timetype type;
  long offset;
  struct tm tm;
};

char *parsetime(char *spec, struct time_value *ptv);

#endif
