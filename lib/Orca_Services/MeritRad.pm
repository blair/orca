#
# MeritRad.pm : Orca_Services package for monitoring Merit Radius
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

package Orca_Services::MeritRad;

BEGIN {
	use strict;
	use Carp;
	use Exporter;
	use IO::File;
	use Sys::Syslog;
	use Orca_Services::Vars;
	$Services{Merit}{File} = "/usr/local/etc/raddb/logfile";
	$Services{Merit}{FileD} = "";
	$Services{Merit}{Ok} = -1;
	$Services{Merit}{External} = 0;
	$Services{Merit}{Init} = "init_merit_radius";
	$Services{Merit}{Init_Vars} = "init_merit_radius_vars";
	$Services{Merit}{Measure} = "measure_merit_radius";
	$Services{Merit}{Put} = "put_merit_radius";

	$PrgOptions{"merit_radius_logfile=s"} = \$Services{Merit}{File};

	$HelpText{$Services{Merit}{File}} = "--merit_radius_logile=FILE    syslog from merit radius      (default:";
}

use Orca_Services::Output;
use Orca_Services::Utils;
use vars qw(@EXPORT @ISA $VERSION);

@EXPORT = qw(init_merit_radius
		init_merit_radius_vars
		measure_merit_radius
		put_merit_radius
                );
@ISA       = qw(Exporter);
$VERSION   = substr q$Revision: 0.01 $, 10;

my ($merit_radius_auth, $merit_radius_auth_ok, $merit_radius_auth_nok);
my ($merit_radius_acct_start, $merit_radius_acct_stop);
my ($merit_radius_rem_auth, $merit_radius_rem_auth_ok);
my ($merit_radius_rem_auth_nok, $merit_radius_undefs);
my ($merit_radius_ino, $merit_radius_size);

#
# init_merit_radius - set Merit_RADIUS vars, open the logfile and seek into the end.
#
# usage: &init_merit_radius($radius_logfile);
#

sub init_merit_radius {
	my ($filename) = @_;
	my ($retval);

	if ($filename) {
		$retval = OpenFile($filename, "Merit", \$merit_radius_ino, \$merit_radius_size);
	}

	if($retval == 0) {
		&init_merit_radius_vars ();
	}
	return $retval;
}


#
# init merit_radius vars
#
# usage: &init_merit_radius_vars();
#

sub init_merit_radius_vars() {
	$merit_radius_auth          = 0;
	$merit_radius_auth_ok       = 0;
	$merit_radius_auth_nok      = 0;

	$merit_radius_acct_start    = 0;
	$merit_radius_acct_stop     = 0;

	$merit_radius_rem_auth      = 0;
	$merit_radius_rem_auth_ok   = 0;
	$merit_radius_rem_auth_nok  = 0;

	$merit_radius_undefs        = 0;
}


#
# Get values for merit_radius columns
#
# usage: &measure_merit_radius( );
#

sub measure_merit_radius () {
    my ($buf);

	$buf = $Services{Merit}{FileD}->getline;
	while ($buf) {
	## process line read and check for eof
	if ($buf) {
		&process_merit_radius_line ($buf);
	}
	if ($Services{Merit}{FileD}->eof) {
		printf "Merit_RADIUS: eof on $Services{Merit}{File}\n" if $Options{debug};
		last; # get out of while($buf)
	}
	$buf = $Services{Merit}{FileD}->getline;
	} ## while ($buf)

	my $retval =  CheckFileChange ("Merit", \$merit_radius_ino, \$merit_radius_size);

	return $retval;
}


#
# Parse merit_radius log line
#
# usage: &process_merit_radius_line ($buf);
#

sub process_merit_radius_line () {
	my ($line) = @_;

	### AUTH RECEIVED
	# Mon Jul 24 00:02:16 2000: Received-Authentication: 214/28832 'luser' from 13.12.15.17 port 25 PPP

	if ($line =~ /: Received-Authentication: .* from /i) {
		$merit_radius_auth ++;
		printf "Merit_RADIUS_AUTH: %s", $line if $Options{debug};
		printf "merit_radius_auth=%s\n", $merit_radius_auth if $Options{debug};
		return 0;
	}

	### AUTH OK
	# Mon Jul 24 00:02:16 2000: Authentication: 214/28832 'luser2' from 13.12.25.17 port 35 PPP - OK -- total 0, holding 0

	if ($line =~ /: Authentication: .* from .* OK /i) {
		$merit_radius_auth_ok ++;
		printf "Merit_RADIUS_AUTH_OK: %s", $line if $Options{debug};
		printf "merit_radius_auth_ok=%s\n", $merit_radius_auth_ok if $Options{debug};
		return 0;
	}

	### AUTH FAILED
	# Mon Jul 24 01:49:20 2000: Authentication: 201/29347 'luser3' from 13.16.19.20 port 2 PPP - FAILED Authentication failure -- total 0, holding 0

	if ($line =~ /: Authentication: .* from .* FAILED Authentication /i) {
		$merit_radius_auth_nok ++;
		printf "Merit_RADIUS_AUTH_NOK: %s", $line if $Options{debug};
		printf "merit_radius_auth_nok=%s\n", $merit_radius_auth_nok if $Options{debug};
		return 0;
	}

	### ACCT START RECEIVED
	# Mon Jul 24 00:02:16 2000: Received-Accounting: 215/8376 'luser4' from 13.16.15.17 port 35 $"5200DB70" PPP/13.16.19.25 Start
	### ACCT STOP RECEIVED
	# Mon Jul 24 00:02:19 2000: Received-Accounting: 176/8377 'luser5' from 13.16.11.18 port 1 $"040065AE" PPP/13.16.24.22 Stop/User-Request
	# Wed Aug  9 16:55:15 2000: getpwnam: good line for luser6 on file
	if ( ($line =~ /: Received-Accounting: .* from /i) || 
		($line =~ /: getpwnam: good line for /i) ){
		printf "Merit_RADIUS_IGNORE: %s", $line if $Options{debug};
		return 0;
	}

	### ACCT START OK
	# Mon Jul 24 00:02:16 2000: Accounting: 215/8376 'luser6' from 13.16.15.17 port 35 $"5200DB70" PPP/13.16.19.24 Start - OK -- total 0, holding 0

	if ($line =~ /: Accounting: .* from .* Start - OK /i) {
		$merit_radius_acct_start ++;
		printf "Merit_RADIUS_ACCT_START: %s", $line if $Options{debug};
		printf "merit_radius_acct_start=%s\n", $merit_radius_acct_start if $Options{debug};
		return 0;
	}

	### ACCT STOP OK
	# Mon Jul 24 00:02:19 2000: Accounting: 176/8377 'luser7' from 13.16.11.18 port 1 $"040065AE" PPP/13.16.24.22 Stop/User-Request - OK -- total 0, holding 0

	if ($line =~ /: Accounting: .* from .* Stop.* OK /i) {
		$merit_radius_acct_stop ++;
		printf "Merit_RADIUS_ACCT_STOP: %s", $line if $Options{debug};
		printf "merit_radius_acct_stop=%s\n", $merit_radius_acct_stop if $Options{debug};
		return 0;
	}

	### REMOTE AUTH RECEIVED
	# Mon Jul 24 20:53:38 2000: Received-AUTHENTICATE: 167/44566 'luser9@realm.com' via some.host.com from some.nas.com port 6 PPP

	if ($line =~ /: Received-AUTHENTICATE: .* via .* from /i) {
		$merit_radius_rem_auth ++;
		printf "Merit_RADIUS_REM_AUTH: %s", $line if $Options{debug};
		printf "merit_radius_rem_auth=%s\n", $merit_radius_rem_auth if $Options{debug};
		return 0;
	}

	### REMOTE AUTH OK
	# Mon Jul 24 20:53:38 2000: AUTHENTICATE: 167/44566 'luser9@realm.com' via some.host.com from some.nas.com port 6 PPP - OK -- total 0, holding 0

	if ($line =~ /: AUTHENTICATE: .* via .* from .* OK /i) {
		$merit_radius_rem_auth_ok ++;
		printf "Merit_RADIUS_REM_AUTH_OK: %s", $line if $Options{debug};
		printf "merit_radius_rem_auth_ok=%s\n", $merit_radius_rem_auth_ok if $Options{debug};
		return 0;
	}

	### REMOTE AUTH FAILED
	# Mon Jul 24 14:05:56 2000: AUTHENTICATE: 230/37578 'luser9@realm.com' via some.host.com from i-Pass VNAS\0\0\0\0 port 1 - FAILED Authentication failure -- total 0, holding 0

	if ($line =~ /: AUTHENTICATE: .* via .* from .* FAILED Authentication /i) {
		$merit_radius_rem_auth_nok ++;
		printf "Merit_RADIUS_REM_AUTH_NOK: %s", $line if $Options{debug};
		printf "merit_radius_rem_auth_nok=%s\n", $merit_radius_rem_auth_nok if $Options{debug};
		return 0;
	}

	$merit_radius_undefs ++;
	printf "Merit_RADIUS_UNDEF: %s", $line if $Options{debug};
	printf "merit_radius_undefs=%s\n", $merit_radius_undefs if $Options{debug};
	return 0;
}


#
# Put the merit_radius values for output
#
# usage: &put_merit_radius();
#

sub put_merit_radius() {
	&put_output("merit_radius_auth",  sprintf("%8.2f", $merit_radius_auth));
	&put_output("merit_radius_auth_ok",  sprintf("%8.2f", $merit_radius_auth_ok));
	&put_output("merit_radius_auth_nok",  sprintf("%8.2f", $merit_radius_auth_nok));
	&put_output("merit_radius_acct_start",  sprintf("%8.2f", $merit_radius_acct_start));
	&put_output("merit_radius_acct_stop",  sprintf("%8.2f", $merit_radius_acct_stop));
	&put_output("merit_radius_rem_auth",  sprintf("%8.2f", $merit_radius_rem_auth));
	&put_output("merit_radius_rem_auth_ok",  sprintf("%8.2f", $merit_radius_rem_auth_ok));
	&put_output("merit_radius_rem_auth_nok",  sprintf("%8.2f", $merit_radius_rem_auth_nok));

	&put_output("merit_radius_undefs",  sprintf("%8.2f", $merit_radius_undefs));

	return 0;
}

1;
