# Generated automatically from Makefile.in by configure.
# things that the GNU standards document suggests all makefiles
# should have.
SHELL = /bin/sh
.SUFFIXES:
.SUFFIXES: .c .o .pl .pm .pod .html .man

# variables we got from configure
# (you can mess with these, if you want)

CC = gcc
AR = ar
CFLAGS_EXTRA =  -Wall -pedantic -fpic
CFLAGS = -g -O2
CFLAGS_ALL = $(CFLAGS) $(CFLAGS_EXTRA) -I.. -I../../src -DHAVE_CONFIG_H \
             -DWANT_AT_STYLE_TIMESPEC
LDFLAGS = 
LIBS = -L../../src -lrrd
LIBS_DEPEND = ../../src/librrd.a

###
### Things you might NOT want to play with ... 
###

HEADERS = ../../src/getopt.h ../../src/parsetime.h

SRC = trytime.c

OBJ = $(SRC:.c=.o)

all: trytime

trytime: $(OBJ) $(LIBS_DEPEND)
	$(CC) -o trytime $(OBJ) $(LDFLAGS) $(LIBS)

clean:  
	-rm *.o

realclean: clean
	-rm trytime

.c.o:	$(HEADERS)
	$(CC) $(CFLAGS_ALL) -c $<
