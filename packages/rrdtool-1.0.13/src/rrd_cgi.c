/*****************************************************************************
 * RRDtool  Copyright Tobias Oetiker, 1997, 1998, 1999
 *****************************************************************************
 * rrd_cgi.c  RRD Web Page Generator
 *****************************************************************************/

#include "rrd_tool.h"
#include <cgi.h>
#include <time.h>


#define MEMBLK 1024

/* global variable for libcgi */
s_cgi **cgiArg;

/* in arg[0] find tags beginning with arg[1] call arg[2] on them
   and replace by result of arg[2] call */
int parse(char **, long, char *, char *(*)(long , char **));

/**************************************************/
/* tag replacers ... they are called from parse   */
/* through function pointers                      */
/**************************************************/

/* return cgi var named arg[0] */ 
char* cgiget(long , char **);

/* return a quoted cgi var named arg[0] */ 
char* cgigetq(long , char **);

/* return a quoted and sanitized cgi variable */
char* cgigetqp(long , char **);

/* call rrd_graph and insert apropriate image tag */
char* drawgraph(long, char **);

/* return PRINT functions from last rrd_graph call */
char* drawprint(long, char **);

/* set an evironment variable */
char* rrdsetenv(long, char **);

/* include the named file at this point */
char* includefile(long, char **);

/** http protocol needs special format, and GMT time **/
char *http_time(time_t *);


static char **calcpr=NULL;
static void calfree (void){
  if (calcpr) {
    long i;
    for(i=0;calcpr[i];i++){
      free(calcpr[i]);
    } 
    free(calcpr);
  }
}

/* create freeable version of the string */
char * stralloc(char *str){
  char *nstr = malloc((strlen(str)+1)*sizeof(char));
  strcpy(nstr,str);
  return(nstr);
}
int main(int argc, char *argv[]) {
  long length;
  char *buffer;
  char *server_url = NULL;
  long i;
  long goodfor=0;
  long filter=0;
  long refresh=0;
  while (1){
      static struct option long_options[] =
      {
	  {"goodfor",        required_argument, 0, 'g'},
	  {"filter",          no_argument, 0, 'f'},
	  {"refresh",        no_argument, 0, 'r'},
	  {0,0,0,0}
      };
      int option_index = 0;
      int opt;
      opt = getopt_long(argc, argv, "g:fr", 
			long_options, &option_index);
      if (opt == EOF)
	  break;
      switch(opt) {
      case 'g': 
	  goodfor=atol(optarg);
	  break;
      case 'f':
	  filter=1;
	  break;
	  case 'r':
	  refresh=1;
	  break;
      case '?':
            printf("unknown commandline option '%s'\n",argv[optind-1]);
            return -1;
      }
  }

  if(filter==0) {
      cgiDebug(0,0);
      cgiArg = cgiInit ();
      server_url = getenv("SERVER_URL");
  }
  if (optind != argc-1) { 
      fprintf (stderr, "Command line error. Expected Input file name! %d\n",optind);
      exit(1);
  }

  length  = readfile(argv[optind], &buffer, 1);

  if(rrd_test_error()){
      fprintf(stderr, "ERROR: %s\n",rrd_get_error());
      exit(1);
  }

  if(filter==0) {
  /* pass 1 makes only sense in cgi mode */
      for (i=0;buffer[i] != '\0'; i++){    
	  i +=parse(&buffer,i,"<RRD::CV ",cgiget);
	  i +=parse(&buffer,i,"<RRD::CV::QUOTE ",cgigetq);
	  i +=parse(&buffer,i,"<RRD::CV::PATH ",cgigetqp);
      }
  }

  /* pass 2 */
  for (i=0;buffer[i] != '\0'; i++){    
      i += parse(&buffer,i,"<RRD::INCLUDE ",includefile);
  }

  /* pass 3 */
  for (i=0;buffer[i] != '\0'; i++){    
    i += parse(&buffer,i,"<RRD::SETENV ",rrdsetenv);
    i += parse(&buffer,i,"<RRD::GRAPH ",drawgraph);
    i += parse(&buffer,i,"<RRD::PRINT ",drawprint);
  }

  if (filter==0){
      printf ("Content-Type: text/html\n"
	      "Content-Length: %d\n", strlen(buffer));
      if (goodfor > 0){
		  time_t now;
		  now = time(NULL);
		  printf ("Last-Modified: %s\n",http_time(&now));
		  now += goodfor;
		  printf ("Expires: %s\n",http_time(&now));
		  if (refresh) {
			printf("Refresh: %ld\n", goodfor);
		  }
      }
      printf ("\n");
  }
  printf ("%s", buffer);
  calfree();
  free(buffer);
  exit(0);
}

/* remove occurences of .. this is a general measure to make
   paths which came in via cgi do not go UP ... */

char* rrdsetenv(long argc, char **args){
  if (argc >= 2) {
      char *xyz=malloc((strlen(args[0])+strlen(args[1])+3)*sizeof(char));
      if (xyz == NULL){	
	return stralloc("[ERROR: allocating setenv buffer]");
      };
      sprintf(xyz,"%s=%s",args[0],args[1]);
      if( putenv(xyz) == -1) {
	return stralloc("[ERROR: faild to do putenv]");
      };
  } else {
    return stralloc("[ERROR: setenv faild because not enough arguments were defined]");
  }
  return stralloc("");
}

char* includefile(long argc, char **args){
  char *buffer;
  if (argc >= 1) {
      readfile(args[0], &buffer, 0);
      if (rrd_test_error()) {
	  char *err = malloc((strlen(rrd_get_error())+20)*sizeof(char));
	  sprintf(err, "[ERROR: %s]",rrd_get_error());
	  rrd_clear_error();
	  return err;
      } else {
       return buffer;
      }
  }
  else
  {
      return stralloc("[ERROR: No Inclue file defined]");
  }
}

char* rrdstrip(char *buf){
  char *start;
  if (buf == NULL) return NULL;
  while ((start = strstr(buf,"<"))){
    *start = '_';
  }
  while ((start = strstr(buf,">"))){
    *start = '_';
  }
  return stralloc(buf);
}

char* cgigetq(long argc, char **args){
  if (argc>= 1){
    char *buf = rrdstrip(cgiGetValue(cgiArg,args[0]));
    char *buf2;
    char *c,*d;
    int  qc=0;
    if (buf==NULL) return NULL;

    for(c=buf;*c != '\0';c++)
      if (*c == '"') qc++;
    if((buf2=malloc((strlen(buf) + qc*4 +2) * sizeof(char)))==NULL){
	perror("Malloc Buffer");
	exit(1);
    };
    c=buf;
    d=buf2;
    *(d++) = '"';
    while(*c != '\0'){
	if (*c == '"') {
	    *(d++) = '"';
	    *(d++) = '\'';
	    *(d++) = '"';
	    *(d++) = '\'';
	} 
	*(d++) = *(c++);
    }
    *(d++) = '"';
    *(d) = '\0';
    free(buf);
    return buf2;
  }

  return stralloc("[ERROR: not enough argument for RRD::CV::QUOTE]");
}

/* remove occurences of .. this is a general measure to make
   paths which came in via cgi do not go UP ... */

char* cgigetqp(long argc, char **args){
  if (argc>= 1){
    char *buf = rrdstrip(cgiGetValue(cgiArg,args[0]));
    char *buf2;
    char *c,*d;
    int  qc=0;
    if (buf==NULL) return NULL;

    for(c=buf;*c != '\0';c++)
      if (*c == '"') qc++;
    if((buf2=malloc((strlen(buf) + qc*4 +2) * sizeof(char)))==NULL){
	perror("Malloc Buffer");
	exit(1);
    };
    c=buf;
    d=buf2;
    *(d++) = '"';
    while(*c != '\0'){
	if (*c == '"') {
	    *(d++) = '"';
	    *(d++) = '\'';
	    *(d++) = '"';
	    *(d++) = '\'';
	} 
	if(*c == '/') {
	    *(d++) = '_';c++;
	} else {
	    if (*c=='.' && *(c+1) == '.'){
		c += 2;
		*(d++) = '_'; *(d++) ='_';	
	    } else {
		
		*(d++) = *(c++);
	    }
	}
    }
    *(d++) = '"';
    *(d) = '\0';
    free(buf);
    return buf2;
  }

  return stralloc("[ERROR: not enough arguments for RRD::CV::PATH]");

}


char* cgiget(long argc, char **args){
  if (argc>= 1)
    return rrdstrip(cgiGetValue(cgiArg,args[0]));
  else
    return stralloc("[ERROR: not enough arguments for RRD::CV]");
}



char* drawgraph(long argc, char **args){
  int i,xsize, ysize;
  for(i=0;i<argc;i++)
    if(strcmp(args[i],"--imginfo")==0 || strcmp(args[i],"-g")==0) break;
  if(i==argc) {
    args[argc++] = "--imginfo";
    args[argc++] = "<IMG SRC=\"./%s\" WIDTH=\"%lu\" HEIGHT=\"%lu\">";
  }
  optind=0; /* reset gnu getopt */
  opterr=0; /* reset gnu getopt */
  calfree();
  if( rrd_graph(argc+1, args-1, &calcpr, &xsize, &ysize) != -1 ) {
    return stralloc(calcpr[0]);
  } else {
    if (rrd_test_error()) {
      char *err = malloc((strlen(rrd_get_error())+20)*sizeof(char));
      sprintf(err, "[ERROR: %s]",rrd_get_error());
      rrd_clear_error();
      calfree();
      return err;
    }
  }
  return NULL;
}

char* drawprint(long argc, char **args){
  if (argc>=1 && calcpr != NULL){
    long i=0;
    while (calcpr[i] != NULL) i++; /*determine number lines in calcpr*/
    if (atol(args[0])<i-1)
      return calcpr[atol(args[0])+1];    
  }
  return stralloc("[ERROR: RRD::PRINT argument error]");
}

/* scan aLine until an unescaped '>' arives */
char* scanargs(char *aLine, long *argc, char ***args)
{
  char        *getP, *putP;
  char        Quote = 0;
  int argal = MEMBLK;
  int braket = 0;
  int inArg = 0;
  if (((*args) = (char **) malloc(MEMBLK*sizeof(char *))) == NULL)   {
    return NULL;
  }
  /* sikp leading blanks */
  while (*aLine && *aLine <= ' ') aLine++;
  
  *argc = 0;
  getP = aLine;
  putP = aLine;
  while (*getP && !( !Quote  && (braket == 0) && ((*getP) == '>'))){
    if (*getP < ' ') *getP = ' '; /*remove all special chars*/
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
	  (*args)[++(*argc)] = putP;
	  inArg=1;
	}           
	Quote = *getP;
      }
      break;
    default:
      if (Quote == 0 && (*getP) == '<') {
	braket++;
      }
      if (Quote == 0 && (*getP) == '>') {
	braket--;
      }

      if(!inArg){
	(*args)[++(*argc)] = putP;
	inArg=1;
      }
      *(putP++)=*getP;
      break;
    }
    if ((*argc) >= argal-10 ) {
      argal += MEMBLK;
    if (((*args)=rrd_realloc((*args),(argal)*sizeof(char *))) == NULL) {
	return NULL;
      }
    }   
    getP++;
  }
  
  *putP = '\0';
  (*argc)++;
  if (Quote) 
    return NULL;
  else
    return getP+1; /* pointer to next char after parameter */
}



int parse(char **buf, long i, char *tag, 
	    char *(*func)(long argc, char **args)){

  /* the name of the vairable ... */
  char *val;
  long valln;  
  char **args;
  char *end;
  long end_offset;
  long argc;
  /* do we like it ? */
  if (strncmp((*buf)+i, tag, strlen(tag))!=0) return 0;      
  /* scanargs puts \0 into *buf ... so after scanargs it is probably
     not a good time to use strlen on buf */
  end = scanargs((*buf)+i+strlen(tag),&argc,&args);
  if (! end) {
    for (;argc>2;argc--){
      *((args[argc-1])-1)=' ';
    }
    val = stralloc("[ERROR: Parsing Problem with the following text\n"
		   " Check original file. This may have been altered by parsing.]\n\n");
    end = (*buf)+i+1;
  } else {
    val = func(argc-1,args+1);
    free (args);
  }
  /* for (ii=0;ii<argc;ii++) printf("'%s'\n", args[ii]); */
  if (val != NULL) {
    valln = strlen(val); 
  } else { valln = 0;}
  
  /* make enough room for replacement */
  end_offset = end - (*buf);
  if(end-(*buf) < i + valln){ /* make sure we do not shrink the mallocd block */
  /* calculating the new length of the buffer is simple. add current
     buffer pos (i) to length of string after replaced tag to length
     of replacement string and add 1 for the final zero ... */
    if(((*buf) = rrd_realloc((*buf),
			 (i+strlen(end) + valln +1) * sizeof(char)))==NULL){
      perror("Realoc buf:");
      exit(1);
    };
  }
  end = (*buf) + end_offset; /* make sure the 'end' pointer gets moved
                                along with the buf pointer when realoc
                                moves memmory ... */
  /* splice the variable */
  memmove ((*buf)+i+valln,end,strlen(end)+1);
  if (val != NULL ) memmove ((*buf)+i,val, valln);
  free(val);
  return valln;
}

char *
http_time(time_t *now) {
        struct tm *tmptime;
        static char buf[60];

        tmptime=gmtime(now);
        strftime(buf,sizeof(buf),"%a, %d %b %Y %H:%M:%S GMT",tmptime);
        return(buf);
}
