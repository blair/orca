#
# Mailq.pm : Orca_Services package for mailq monitoring
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

package Orca_Services::Mailq;

BEGIN {
	use strict;
	use Carp;
	use Exporter;
	use IO::File;
	use Sys::Syslog;
	use Orca_Services::Vars;
	$Services{Mailq}{File} = "on";
	$Services{Mailq}{FileD} = "";
	$Services{Mailq}{Ok} = -1;
	$Services{Mailq}{External} = 1;
	$Services{Mailq}{Init} = "init_mailq";
	$Services{Mailq}{Init_Vars} = "init_mailq_vars";
	$Services{Mailq}{Measure} = "measure_mailq";
	$Services{Mailq}{Put} = "put_mailq";

	$PrgOptions{"mailq=s"} = \$Services{Mailq}{File};

	$HelpText{$Services{Mailq}{File}} = "--mailq=[on|off]      get mailq total requests    (default:";
}

use Orca_Services::Output;
use vars qw(@EXPORT @ISA $VERSION);

@EXPORT = qw(init_mailq
			init_mailq_vars
			measure_mailq
			put_mailq
			);
@ISA       = qw(Exporter);
$VERSION   = substr q$Revision: 0.01 $, 10;

my ($mailq_total);

#
# Get values for mailq columns
#
# usage: &measure_mailq( );
#

sub measure_mailq () {
	my ($mailq_t, $line);

	open (MFD, "$MAILQCMD |");
	$line = <MFD>;
	close (MFD);

	if ($line =~ /(\d+)/i) {
		$mailq_t = $1;
	} else {
		$mailq_t = 0;
	}

	print "MAILQ : $mailq_t\n" if $Options{debug};
	$mailq_total += $mailq_t;

	return 0;
}


#
# init mailq
#
# usage: &init_mailq();
#

sub init_mailq() {
    if ($Services{Mailq}{File} eq "off" ){
       return -1;
    }
    return 0;
}


#
# init mailq vars
#
# usage: &init_mailq_vars();
#

sub init_mailq_vars() {
    $mailq_total      = 0;
}


#
# Put the mailq values for output
#
# usage: &put_mailq();
#

sub put_mailq() {

    &put_output("mailq_total",  sprintf("%8.2f", $mailq_total));

    return 0;
}

1;
