#
# Slapd.pm : Orca_Services package for monitoring slapd
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
#

package Orca_Services::Slapd;
BEGIN {
	use strict;
	use Carp;
	use Exporter;
	use IO::File;
	use Sys::Syslog;
	use Orca_Services::Vars;
	$Services{Slapd}{File} = "/var/ds5/slapd-velsatis/logs/access";
	$Services{Slapd}{FileD} = "";
	$Services{Slapd}{Ok} = -1;
	$Services{Slapd}{External} = 0;
	$Services{Slapd}{Init} = "init_slapd";
	$Services{Slapd}{Init_Vars} = "init_slapd_vars";
	$Services{Slapd}{Measure} = "measure_slapd";
	$Services{Slapd}{Put} = "put_slapd";

	$PrgOptions{"slapd_logfile=s"} = \$Services{Slapd}{File};

	$HelpText{$Services{Slapd}{File}} = "--slapd_logfile=FILE    log from slapd           (default:";
}


use Orca_Services::Output;
use Orca_Services::Utils;
use vars qw(@EXPORT @ISA $VERSION);

@EXPORT = qw(init_slapd
		init_slapd_vars
		measure_slapd
		put_slapd
                );
@ISA       = qw(Exporter);
$VERSION   = substr q$Revision: 0.01 $, 10;

my ($slapd_binds, $slapd_searchs);
my ($slapd_ino, $slapd_size);

#
# When we do a Iplanet access file, all records are valid
#
my ($Iplanet) = 1;


#
# init_slapd - set SLAPD vars, open the logfile and seek into the end.
#
# usage: &init_slapd($slapd_logfile);
#
sub init_slapd {
	my ($filename) = @_;
	my ($retval);

	if ($filename) {
		$retval = OpenFile($filename, "Slapd", \$slapd_ino, \$slapd_size);
	}

	if($retval == 0) {
		&init_slapd_vars ();
	}
	return $retval;
}


#
# Get values for slapd columns
#
# usage: &measure_slapd( );
#
sub measure_slapd () {
	my ($buf);

	$buf = $Services{Slapd}{FileD}->getline;
	while ($buf) {
		## process line read and check for eof
		if ($buf) {
			&process_slapd_line ($buf);
		}
		if ($Services{Slapd}{FileD}->eof) {
			printf "SLAPD: eof on $Services{Slapd}{File}\n" if $Options{debug};
			last; # get out of while($buf)
		}
		$buf = $Services{Slapd}{FileD}->getline;
	} ## while ($buf)

	my $retval =  CheckFileChange ("Slapd", \$slapd_ino, \$slapd_size);

	return $retval;
}


#
# init slapd vars
#
# usage: &init_slapd_vars();
#
sub init_slapd_vars() {
	$slapd_binds      = 0;
	$slapd_searchs    = 0;
}


#
# Parse slapd log line
#
# usage: &process_slapd_line ($buf);
#

sub process_slapd_line () {
	my ($line) = @_;

	if ($line !~ /\sslapd\[\d+\]:\s/ && $Iplanet == 0) {
		return 0;
	}

	# BIND
	# Nov  6 18:24:05 ldap1 slapd[259]: conn=808413 op=0 BIND dn="xxxxxxxxxxxx" method=128
	if ($line =~ /\sBIND\s/) {
		$slapd_binds ++;
		printf "SLAPD_BINDS: %s", $line if $Options{debug};
		return 0;
	}

	# SRCH
	# Nov  6 18:24:05 ldap10 slapd[3456]: conn=32453 op=1 SRCH base="zzzzzzzzzzzzzz" scope=1 filter="yyyyyyyyyyyyyyyyyyy"
	if ($line =~ /\sSRCH\s/) {
		$slapd_searchs ++;
		printf "SLAPD_SEARCHS: %s", $line if $Options{debug};
		return 0;
	}

	return 0;
}


#
# Put the slapd values for output
#
# usage: &put_slapd();
#

sub put_slapd() {
	&put_output("slapd_binds",  sprintf("%8.2f", $slapd_binds));
	&put_output("slapd_searchs",  sprintf("%8.2f", $slapd_searchs));

	return 0;
}

1;
