/*
** rrdproc.c Copyright 1999 Damien Miller <djm@mindrot.org>
**
**
** This program is a very lightweight collecter for rrdtool. It reads
** and parses /proc/net/dev and sends a rrdtool remote control update
** command to stdout.
**
** rrdproc will sleep a user-defined amount of time between reads from
** /proc/net/dev. This time should match the sample rate you created your
** RRD files with.
**
** Example:
**
** rrdproc --interface=ppp0 \
**         --wait 30 \
**         --filename=/home/djm/traffic-ppp0.rrd | rrdtool -
**
** This will update the RRD file /home/djm/traffic-eth0.rrd with bytes
** received and sent on eth0 every 30 seconds.
**
** rrdproc --interface=eth0 \
**         --wait 300 \
**         --frame \
**         --filename=/home/djm/traffic-eth0.rrd | rrdtool -
**
** Will update /home/djm/traffic-eth0.rrd with counts of framing errors and
** collisions every 5 minutes
**
** rrdproc is licensed under the GNU GPL version 2. Please refer to
** http://www.fsf.org/copyleft/gpl.html for details.
**
*/

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <syslog.h>
#include <getopt.h>
#include <unistd.h>
#include <time.h>

#define PROC_DEV					"/proc/net/dev"

#define DEFAULT_SLEEP_TIME		3
#define DEFAULT_INTERFACE		"eth0"
#define DEFAULT_FILENAME		"traffic"

#define COLUMN_BYTES				0
#define COLUMN_PACKETS			1
#define COLUMN_ERRORS			2
#define COLUMN_DROPPED			3
#define COLUMN_FIFO				4
#define COLUMN_FRAME				5

void get_stats(FILE *devstats, const char *interface, int start_column);
const char *skip_columns(const char *p, int num_columns);
void help(void);
void version(void);

static struct option long_options[] =
{
	{ "wait", 1, NULL, 'w'},
	{ "interface", 1, NULL, 'i'},
	{ "filename", 1, NULL, 'f'},
	{ "help", 0, NULL, 'h'},
	{ "version", 0, NULL, 'v'},
	{ "bytes", 0, NULL, 'B'},
	{ "packets", 0, NULL, 'P'},
	{ "errors", 0, NULL, 'E'},
	{ "dropped", 0, NULL, 'D'},
	{ "fifo", 0, NULL, 'F'},
	{ "frame", 0, NULL, 'R'},
};

int main(int argc, char **argv)
{
	int sleep_time = DEFAULT_SLEEP_TIME;
	char *interface = DEFAULT_INTERFACE;
	char *filename = DEFAULT_FILENAME;
	int start_column = COLUMN_BYTES;
	int c;
	FILE *devstats;
	
	extern char *optarg;
	
	openlog("if-update", LOG_PERROR|LOG_PID, LOG_DAEMON);
	
	while(1)
	{
		c = getopt_long(argc, argv, "w:i:f:hvBPEDFRCM", long_options, NULL);
		if (c == -1)
			break;
		
		switch(c)
		{
			case 'w':
				sleep_time = atoi(optarg);
				break;
			case 'i':
				interface = strdup(optarg);
				break;
			case 'f':
				filename = strdup(optarg);
				break;
			case 'h':
				help();
				exit(0);
			case 'v':
				version();
				exit(0);
			case 'B':
				start_column = COLUMN_BYTES;
				break;
			case 'P':
				start_column = COLUMN_PACKETS;
				break;
			case 'E':
				start_column = COLUMN_ERRORS;
				break;
			case 'D':
				start_column = COLUMN_DROPPED;
				break;
			case 'F':
				start_column = COLUMN_FIFO;
				break;
			case 'R':
				start_column = COLUMN_FRAME;
				break;
			default:
				fprintf(stderr, "Invalid commandline options.\n");
				help();
				exit(1);
		}		
	}
	
	setlinebuf(stdout);
	
	while(1)
	{
		devstats = fopen(PROC_DEV, "r");
		if (devstats == NULL)
		{
			syslog(LOG_ERR, "Couldn't open proc file \"%s\" for reading: %m", PROC_DEV);
			exit(1);
		}
		printf("update %s N:", filename);
		get_stats(devstats, interface, start_column);
		sleep(sleep_time);
		fclose(devstats);
	}
	exit(0);
}

void get_stats(FILE *devstats, const char *interface, int start_column)
{
	char buffer[2048];
	const char *p;
	int if_len;
	unsigned long long in;
	unsigned long long out;
	
	if_len = strlen(interface);
	
	while(fgets(buffer, sizeof(buffer), devstats) != NULL)
	{
		p = buffer;
		
		/* skip space at start of line */
		while(*p && (*p == ' '))
			p++;

		if (strncmp(p, interface, if_len) == 0)
		{
			/* Skip to the statistic we wnt to report */
			p = skip_columns(p + if_len + 1, start_column);

			in = strtoull(p, NULL, 10);

			/* Skip from received column to transmit column */
			p = skip_columns(p, 8);

			out = strtoull(p, NULL, 10);

			printf("%Lu:%Lu\n", in, out);

			return;
		}		
	}

	/* Non-fatal error if interface not found */
	syslog(LOG_WARNING, "Couldn't find statistics for interface \"%s\"", interface);
	printf("U:U\n");
	return;
}

void help(void)
{
	fprintf(stderr, "\
rrdproc - Update rrd file using statistics in /proc\n\
\n\
rrdproc will periodically read /proc/net/dev and update an RRD database\n\
with the numbers that it finds there.\n\
\n\
Options:\n\
    --wait, -w      [time]      Time to wait between statistics updates\n\
    --interface, -i [name]      Name of network interface to report on\n\
    --filename, -f  [filename]  Path of RRD file to update\n\
    --help, -h                  Display this help\n\
    --version, -v               Display version information\n\
    --bytes, -B                 Report bytes in / out\n\
    --packets, -P               Report packets in / out\n\
    --errors, -E                Report errors in / out\n\
    --dropped, -D               Report dropped packets in / out\n\
    --fifo, -F                  Report fifo in / out\n\
    --frame, -R                 Report framing errors / collisions\n\
");
}

void version(void)
{
	fprintf(stderr, "rrdproc v0.0\n");
}

const char *skip_columns(const char *p, int num_columns)
{
	int c;
	
	for(c = 0; c < num_columns; c++)
	{
		/* Skip numbers */
		while(*p && (*p != ' '))
			p++;

		/* Skip space */
		while(*p && (*p == ' '))
			p++;

		if (!*p)
		{
			/* Line finished early */
			printf("U:U\n");
			syslog(LOG_WARNING, "Couldn't parse interface statistics");
			return;
		}
	}
	
	return(p);
}
