#
# Var.pm : Orca_Services package for global vars
# 
# Author: Sjaak Westdijk <westdijk@fastmail.fm>
#
# thanks to :
#     Carlos Canau <Carlos.Canau@KPNQwest.pt>
#     Jose Carlos Pereira <Jose.Pereira@KPNQwest.pt>
#
# Most code is adapted from Orca_servcies 1.X written by Carlos Canau
#
# Portions ported to perl from Orcallator.se written by Blair Zajac
# other portions adapted from several other open source scripts
#
#
# BUGS:
#
#
# TODO:
#
#
# LICENSE:
#         GPL.
#         (c) 2003      Sjaak Westdijk
#         (c) 2000-2002 Carlos Canau & Jose Carlos Pereira
#
#
# DISCLAIMER:
#            you use this program at your own and complete risk
#            if you don't agree with that then delete it
#
#

package Orca_Services::Vars;

use strict;
use Exporter;
use vars qw(@EXPORT @ISA $VERSION);
@ISA     = qw(Exporter);

#
# program VERSION
#
push(@EXPORT, qw($VERSION));
$VERSION = "2.0a1";


#
# progra name
#
use vars qw($progname);
push(@EXPORT, qw($progname));
$progname = "Orca_Services";

#
# vars for syslogging
#
use vars qw($log_facility $log_priority);
push(@EXPORT, qw($log_facility $log_priority));
$log_facility	 = "user";
$log_priority	 = "info";

#
# some helper programs
#
use vars qw($CAT $ECHO $TOUCH);
push(@EXPORT, qw($CAT $ECHO $TOUCH));
$CAT="/usr/local/bin/cat";
$ECHO="/usr/local/bin/echo";
$TOUCH="/usr/local/bin/touch";

#
#
#
use vars qw($SaveDay $OutputFilename $print_header $current_column);
push(@EXPORT, qw($SaveDay $Compress $OutputFilename $print_header $current_column));
$SaveDay = 0;
$OutputFilename = "";
$print_header = 0;
$current_column = 0;

#
# the mailq command
#
# mailq when postfix is installed
# $MAILQCMD = "/usr/bin/mailq | egrep -v '^-' | egrep '^[A-Z0-9]' | egrep -v 'empty' | wc -l";
#
use vars qw($MAILQCMD);
push(@EXPORT, qw($MAILQCMD));
$MAILQCMD = "/usr/bin/mailq | egrep -v '^-' | egrep '^[A-Z0-9]' | egrep -v 'empty' | wc -l";

#
# Central Hash for Services parameter
#
use vars qw(%Services %Options %PrgOptions %HelpText);
push(@EXPORT, qw(%Services %Options %PrgOptions %HelpText));
%Services=();
%Options=("interval" => 300,
	  "outputdir" => "@VAR_DIR@/Orca_Services",
	  "compress" => "@COMPRESSOR@",
          "debug" => 0,
          "help" => 0
	);
$Options{pidfile} = "$Options{outputdir}/${progname}.pid";

%PrgOptions = ("pidfile=s"               => \$Options{pidfile},
           "debug:s"                 => \$Options{debug},
           "interval=i"              => \$Options{interval},
	   "outputdir=s"             => \$Options{outputdir},
	   "compress=s"              => \$Options{compress},
           "help"                    => \$Options{help},
           "version"                 => \$Options{help}
	);

%HelpText = ($Options{pidfile} =>   "--pidfile=FILE        write my PID here           (default:",
	     $Options{debug} =>     "--debug[=0|1]         show copious debugging info (default:",
	     $Options{interval} =>  "--interval=i          pooling interval in sec.    (default:",
	     $Options{outputdir} => "--outputdir=DIR                                   (default:",
    	     $Options{compress} =>  "--compress=COMMAND    use this to compress files  (default:",
	);

#
#
#
use vars qw($interval $nodename);
push(@EXPORT, qw($interval $nodename));
$interval=0;

my $UNAME = "/usr/bin/uname";
$nodename = `$UNAME -n`;
chop($nodename);

1;
