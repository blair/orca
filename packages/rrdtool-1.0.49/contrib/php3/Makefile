# code by Joey Miller <joeym@inficad.com>
#
#
# BEFORE COMPILING YOU MUST SET THE VARIABLES BELOW
# TO INDICATE THE CORRECT DIRECTORIES!!!!!!!!!!!!!!!!!!!!!
#
#
# USE AT YOUR OWN RISK!
#

## begin configurable vars

## PHPINCLUDE -- the directory where php is untarred
##
PHPINCLUDE =  -I/usr/home/joeym/apache_build/php-3.0.14

## PHPLIBS -- the directory where you can find some of the PHP objects
## and compiled libs (the directory where php is untarred, and
## has already been compiled!
##
PHPLIBS    =  /usr/home/joeym/apache_build/php-3.0.14

## RRDINCLUDE, GDINCLUDE -- where to find some of the header
## files needed by rrdtool and it's libs
##
RRDINCLUDE =  -I/usr/home/joeym/newshit/rrdtool-1.0.10/src
GDINCLUDE  =  -I/usr/home/joeym/newshit/rrdtool-1.0.10/gd1.3

## RRDLIB -- where to find librrd.a (usually /usr/local/rrdtool-1.0.10/lib)
RRDLIB	   =	/usr/local/rrdtool-1.0.10/lib

#
# if php is compiled as an apache module
#
APACHEINC = -I/var/www/include



###### end primary config vars  .. change the vars below only
###### if you need to
######




CFLAGS	= -O -fpic
CC	= gcc

CXX	= g++
CXXFLAGS= $(CFLAGS)

LD	= cc
LDFLAGS	= -shared

RM	= /bin/rm

OBJS    =  php3_rrdtool.o
CFLAGS	:= $(CFLAGS) -I../lib $(PHPINCLUDE) $(APACHEINC) $(RRDINCLUDE) $(GDINCLUDE)
CXXFLAGS:= $(CXXFLAGS) -I../lib $(PHPINCLUDE) $(APACHEINC) $(RRDINCLUDE) $(GDINCLUDE)
LIBS	:= -L$(RRDLIB) -L$(PHPLIBS) -lrrd 

all: php3_rrdtool.so

php3_rrdtool.so: $(OBJS)
	$(LD) $(LDFLAGS) $(OBJS) -o $@ $(LIBS)

clean:
	$(RM) *.o
	$(RM) *.so
	
veryclean: clean
	$(RM) *~
