#ifndef CONFIG_H
#define CONFIG_H

@TOP@

/* IEEE can be prevented from raising signals with fpsetmask(0) */
#undef MUST_DISABLE_FPMASK

/* IEEE math only works if SIGFPE gets actively set to IGNORE */

#undef MUST_DISABLE_SIGFPE

/* realloc does not support NULL as argument */
#undef NO_NULL_REALLOC

@BOTTOM@

/* define strrchr, strchr and memcpy, memmove in terms of bsd funcs
   make sure you are NOT using bcopy, index or rindex in the code */
      
#if STDC_HEADERS
# include <string.h>
#else
# ifndef HAVE_STRCHR
#  define strchr index
#  define strrchr rindex
# endif
char *strchr (), *strrchr ();
# ifndef HAVE_MEMMOVE
#  define memcpy(d, s, n) bcopy ((s), (d), (n))
#  define memmove(d, s, n) bcopy ((s), (d), (n))
# endif
#endif

#if NO_NULL_REALLOC
# define rrd_realloc(a,b) ( (a) == NULL ? malloc( (b) ) : realloc( (a) , (b) ))
#else
# define rrd_realloc(a,b) realloc((a), (b))
#endif      

#if (! defined(HAVE_FINITE) && defined(HAVE_ISNAN) && defined(HAVE_ISINF))
#define HAVE_FINITE 1
#define finite(a) (! isnan(a) && ! isinf(a))
#endif

#if (! defined(HAVE_ISINF) && defined(HAVE_FPCLASS))
#define HAVE_ISINF 1
#include <ieeefp.h>
#define isinf(a) (fpclass(a) == FP_NINF || fpclass(a) == FP_PINF)
#endif

#ifndef HAVE_FINITE
#error "Can't compile without finite function"
#endif

#ifndef HAVE_ISINF
#error "Can't compile without isinf function"
#endif

#endif /* CONFIG_H */


