#
# Pop.pm : Orca_Services package for monitoring pop service
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

package Orca_Services::Pop;
BEGIN {
	use strict;
	use Carp;
	use Exporter;
	use IO::File;
	use Sys::Syslog;
	use Orca_Services::Vars;
	$Services{Pop}{File} = "/var/log/ipop3d.log";
	$Services{Pop}{FileD} = "";
	$Services{Pop}{Ok} = -1;
	$Services{Pop}{External} = 0;
	$Services{Pop}{Init} = "init_pop";
	$Services{Pop}{Init_Vars} = "init_pop_vars";
	$Services{Pop}{Measure} = "measure_pop";
	$Services{Pop}{Put} = "put_pop";

	$PrgOptions{"pop_logfile=s"} = \$Services{Pop}{File};

	$HelpText{$Services{Dns}{File}} = "--pop_logfile=FILE    syslog from pop           (default:";
}

use Orca_Services::Utils;
use Orca_Services::Output;
use vars qw(@EXPORT @ISA $VERSION);

@EXPORT = qw(init_pop
		init_pop_vars
		measure_pop
		put_pop
                );
@ISA       = qw(Exporter);
$VERSION   = substr q$Revision: 0.01 $, 10;

my ($pop_connect, $pop_login , $pop_logout, $pop_failure, $pop_refused);
my ($pop_net_error, $pop_local_error, $pop_undefs);
my ($pop_ino, $pop_size);

#
# init_pop - set POP vars, open the logfile and seek into the end.
#
# usage: &init_pop($pop_logfile);
#
sub init_pop {
	my ($filename) = @_;
	my ($retval);

	if ($filename) {
		$retval = OpenFile($filename, "Pop", \$pop_ino, \$pop_size);
	}

	if($retval == 0) {
		&init_pop_vars ();
	}
	return $retval;
}


#
# init pop vars
#
# usage: &init_pop_vars();
#
sub init_pop_vars() {
	$pop_connect      = 0;
	$pop_login        = 0;
	$pop_logout       = 0;

	$pop_failure      = 0;
	$pop_refused      = 0;

	$pop_net_error    = 0;
	$pop_local_error  = 0;

	$pop_undefs       = 0;
}


#
# Get values for pop columns
#
# usage: &measure_pop( );
#

sub measure_pop () {
	my($buf);

	$buf = $Services{Pop}{FileD}->getline;
	while ($buf) {
		## process line read and check for eof
		if ($buf) {
			&process_pop_line ($buf);
		}
		if ($Services{Pop}{FileD}->eof) {
			printf "POP: eof on $Services{Pop}{File}\n" if $Options{debug};
			last; # get out of while($buf)
		}
		$buf = $Services{Pop}{FileD}->getline;
	} ## while ($buf)

	my $retval =  CheckFileChange ("Pop", \$pop_ino, \$pop_size);

	return $retval;

}


#
# Parse pop log line
#
# usage: &process_pop_line ($buf);
#
sub process_pop_line () {
	my ($line) = @_;


	# Oct 27 04:03:00 host2 pop3d: Connection, ip=[::ffff:10.0.0.133]
	# Oct 27 04:03:00 host2 pop3d: LOGIN, user=user7, ip=[::ffff:10.0.0.133]
	# Oct 27 04:03:00 host2 pop3d: LOGOUT, user=user7, ip=[::ffff:10.0.0.133], top=0, retr=0

	if (($line !~ / ipop3d\[\d+\]: /) &&
		($line !~ / perdition\[\d+\]: /) &&
		($line !~ / pop3d: /)) {
		return 0;
	}

	### connect
	# Aug 11 07:01:50 host1 ipop3d[13929]: connect from 14.5.8.10
	# Feb 28 22:13:34 host1 perdition[26127]: Connect: 10.0.0.1->12.1.1.1 user="id1" server="host1.KPNQwest.pt" port="110"
	# Oct 27 04:03:00 host2 pop3d: Connection, ip=[::ffff:10.0.0.133]

	if (($line =~ /: connect from /i) || 
		($line =~ /: Connect: /i) ||
		($line =~ /: Connection, /i)) {
		$pop_connect ++;
		printf "POP_CONNECT: %s", $line if $Options{debug};
		printf "pop_connect=%s\n", $pop_connect if $Options{debug};
		return 0;
	}

	### login + auth
	# Aug 11 07:01:57 host1 ipop3d[13928]: Login user=luser2 host=host.domain.pt [13.16.6.27] nmsgs=0/0
	# Aug 11 07:02:06 host1 ipop3d[13936]: Auth user=luser3 host=2-4-4.domain.pt [13.16.2.18] nmsgs=0/0
	# Feb 28 22:13:34 host1 perdition[26121]: Auth: 10.0.0.1->12.1.1.1 user="id1" server="host1.KPNQwest.pt" port="110"
	# Oct 27 04:03:00 host2 pop3d: LOGIN, user=user7, ip=[::ffff:10.0.0.133]

	if ( ($line =~ /: Login user=/i) || 
		($line =~ /: Auth user=/i) ||
		($line =~ /: Auth: /i) ||
		($line =~ /: LOGIN, /i)) {
		$pop_login ++;
		printf "POP_LOGIN: %s", $line if $Options{debug};
		printf "pop_login=%s\n", $pop_login if $Options{debug};
		return 0;
	}

	### logout
	# Aug 11 07:01:50 host1 ipop3d[13929]: Logout user=luser4 host=[14.6.8.10] nmsgs=0 ndele=0
	# Aug 11 11:20:24 host1 ipop3d[1866]: Autologout user=luser5 host=3-0-0.domain.pt [13.16.1.18]
	# Feb 28 22:13:35 host1 perdition[26127]: Closing: 10.0.0.1->12.1.1.1 user=id1 12 18
	# Oct 27 04:03:48 host2 perdition[14872]: Close: 11.1.1.2->13.3.3.4 user="user2" received=6 sent=0
	# Oct 27 04:03:00 host2 pop3d: LOGOUT, user=user7, ip=[::ffff:10.0.0.133], top=0, retr=0

	if (($line =~ /: .*[lL]ogout user=/i) ||
		($line =~ /: Closing: /i) || 
		($line =~ /: Close: /i) ||
		($line =~ /: LOGOUT, /i)) {
		$pop_logout ++;
		printf "POP_LOGOUT: %s", $line if $Options{debug};
		printf "pop_LOGOUT=%s\n", $pop_logout if $Options{debug};
		return 0;
	}

	### failure
	# Aug 11 09:19:19 host1 ipop3d[22171]: Login failure user=luser44 host=4-0-0.domain.pt [13.16.12.1]
	# Aug 11 09:19:22 host1 ipop3d[22171]: AUTHENTICATE LOGIN failure host=4-0-0.domain.pt [13.16.12.1]
	# Aug 11 09:47:47 host1 ipop3d[25308]: AUTHENTICATE luser323 failure host=[13.12.24.24]
	# Feb 28 21:42:54 host1 perdition[21930]: Fatal Error reading authentication information from client "10.0.0.1->12.1.1.1 ": Exiting child
	# Feb 28 21:46:56 host1 perdition[22466]: Fail reauthentication for user id1

	if (($line =~ / failure /i) ||
		($line =~ /: Fatal Error reading authentication information from client /i) || 
		($line =~ /: Fail reauthentication for user /i)) {
		$pop_failure ++;
		printf "POP_FAILURE: %s", $line if $Options{debug};
		printf "pop_failure=%s\n", $pop_failure if $Options{debug};
	return 0;
	}

	### refused
	# Aug 11 13:32:14 host1 ipop3d[28886]: refused connect from 13.17.8.28

	if ($line =~ /: refused connect from /i) {
		$pop_refused ++;
		printf "POP_REFUSED: %s", $line if $Options{debug};
		printf "pop_refused=%s\n", $pop_refused if $Options{debug};
		return 0;
	}

	### local_error
	# Aug 11 11:50:36 host1 ipop3d[13132]: Error opening or locking INBOX user=luser10 host=3-4-3.domain.pt [13.16.4.7]
	# Feb 28 21:41:53 host1 perdition[20588]: Fatal error piping data. Exiting child.

	if (($line =~ /: Error opening or locking INBOX user=/i) ||
		($line =~ /: Fatal error piping data. Exiting child./i)) {
		$pop_local_error ++;
		printf "POP_LOCAL_ERROR: %s", $line if $Options{debug};
		printf "pop_local_error=%s\n", $pop_local_error if $Options{debug};
		return 0;
	}

	### net_error
	# Aug 11 07:36:14 host1 ipop3d[15759]: Command stream end of file while reading line user=luser234 host=9-9-9-domain.pt [13.16.4.5]
	# Aug 11 09:50:09 host1 ipop3d[24960]: Connection reset by peer while reading line user=luser555 host=[12.5.19.16]
	# Aug 11 12:15:01 host1 ipop3d[16601]: Connection timed out while reading line user=luser7985 host=4-5-6.domain.pt [13.16.1.15]
	# Oct 27 04:17:16 host2 pop3d: Disconnected, ip=[::ffff:10.0.0.132]
	# Oct 27 04:19:59 host2 pop3d: DISCONNECTED, user=user4, ip=[::ffff:10.0.0.133], top=0, retr=0
	# Oct 27 10:46:50 host2 pop3d: TIMEOUT, user=user55, ip=[::ffff:10.0.0.133], top=0, retr=0

	if ( ($line =~ /: Command stream end of file while reading line user=/i) ||
		($line =~ /: Connection reset by peer while reading line user=/i) || 
		($line =~ /: Connection timed out while reading line user=/i) || 
		($line =~ /: Disconnected,/i) || 
		($line =~ /: TIMEOUT,/i) ) {
		$pop_net_error ++;
		printf "POP_NET_ERROR: %s", $line if $Options{debug};
		printf "pop_net_error=%s\n", $pop_net_error if $Options{debug};
		return 0;
	}


	$pop_undefs ++;
	printf "POP_UNDEF: %s", $line if $Options{debug};
	printf "pop_undefs=%s\n", $pop_undefs if $Options{debug};
	return 0;
}


#
# Put the pop values for output
#
# usage: &put_pop();
#

sub put_pop() {
	&put_output("pop_connect",  sprintf("%8.2f", $pop_connect));
	&put_output("pop_login",  sprintf("%8.2f", $pop_login));
	&put_output("pop_logout",  sprintf("%8.2f", $pop_logout));

	&put_output("pop_failure",  sprintf("%8.2f", $pop_failure));
	&put_output("pop_refused",  sprintf("%8.2f", $pop_refused));

	&put_output("pop_net_error",  sprintf("%8.2f", $pop_net_error));
	&put_output("pop_local_error",  sprintf("%8.2f", $pop_local_error));

	&put_output("pop_undefs",  sprintf("%8.2f", $pop_undefs));

	return 0;
}

1;
