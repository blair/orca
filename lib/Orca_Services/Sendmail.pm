#
# Sendmail.pm : Orca_Services package to process sendmail log
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

package Orca_Services::Sendmail;

BEGIN {
	use strict;
	use Carp;
	use Exporter;
	use IO::File;
	use Sys::Syslog;
	use Orca_Services::Vars;

	$Services{Sendmail}{File} = "/var/log/mail.log";
	$Services{Sendmail}{FileD} = "";
	$Services{Sendmail}{Ok} = -1;
	$Services{Sendmail}{External} = 0;
	$Services{Sendmail}{Init} = "init_smtp";
	$Services{Sendmail}{Init_Vars} = "init_smtp_vars";
	$Services{Sendmail}{Measure} = "measure_smtp";
	$Services{Sendmail}{Put} = "put_smtp";

	$PrgOptions{"smtp_logfile=s"} = \$Services{Sendmail}{File};

	$HelpText{$Services{Sendmail}{File}} = "--smtp_logfile=FILE   syslog from sendmail        (default:";
}

use Orca_Services::Output;
use Orca_Services::Utils;
use vars qw(@EXPORT @ISA $VERSION);

@EXPORT = qw(init_smtp
		init_smtp_vars
		measure_smtp
		put_smtp
		);

@ISA       = qw(Exporter);
$VERSION   = substr q$Revision: 0.01 $, 10;

my ($smtp_froms, $smtp_MaxSize, $smtp_sizes, $smtp_MaxSeconds, $smtp_seconds);
my ($smtp_sent, $smtp_fail, $smtp_retries, $smtp_queued, $smtp_t_or_f);
my ($smtp_check_mail, $smtp_check_rcpt, $smtp_notifies, $smtp_dsns);
my ($smtp_spam, $smtp_virus, $smtp_overquota, $smtp_undefs);
my ($smtp_ino, $smtp_size);

# -------------------------------------------------------------------
#
# init_smtp - set SMTP vars, open the logfile and seek into the end.
#
# usage: &init_smtp($smtp_logfile);
#

sub init_smtp {
	my ($filename) = @_;
	my ($retval);

	if ($filename) {
		$retval = OpenFile($filename, "Sendmail", \$smtp_ino, \$smtp_size);
	}

	if($retval == 0) {
		&init_smtp_vars ();
	}
	return $retval;
}

# -------------------------------------------------------------------
#
# Get values for smtp columns
#
# usage: &measure_smtp( );
#

sub measure_smtp () {
	my ($buf);

	$buf = $Services{Sendmail}{FileD}->getline;
	while ($buf) {
		## process line read and check for eof
		if ($buf) {
			process_smtp_line ($buf);
		}
		if ($Services{Sendmail}{FileD}->eof) {
			printf "SMTP: eof on $Services{Sendmail}{File}\n" if $Options{debug};
			last; # get out of while($buf)
		}
		$buf = $Services{Sendmail}{FileD}->getline;
	} ## while ($buf)

	my $retval =  CheckFileChange ("Sendmail", \$smtp_ino, \$smtp_size);

	return $retval;
}


# -------------------------------------------------------------------
#
# init smtp vars
#
# usage: &init_smtp_vars();
#

sub init_smtp_vars() {
	$smtp_froms      = 0;
	$smtp_MaxSize    = 0;
	$smtp_sizes      = 0;

	$smtp_MaxSeconds = 0;
	$smtp_seconds    = 0;
	$smtp_sent       = 0;

	$smtp_fail       = 0;
	$smtp_retries    = 0;
	$smtp_queued     = 0;
	$smtp_t_or_f     = 0;

	$smtp_check_mail = 0;
	$smtp_check_rcpt = 0;
	$smtp_notifies   = 0;
	$smtp_dsns       = 0;

	$smtp_spam       = 0;
	$smtp_virus      = 0;

	$smtp_overquota  = 0;

	$smtp_undefs     = 0;
}


# -------------------------------------------------------------------
#
# Parse smtp log line
#
# usage: &process_smtp_line ($buf);
#

sub process_smtp_line () {
	my ($line) = @_;
	my ($size, $seconds);

	if (($line !~ /\ssendmail\[\d+\]:\s/) && ($line !~ /\smailscanner\[\d+\]:\s/) && ($line !~ /\sllmail\[\d+\]:\s/)) {
		return 0;
	}


	# from
	# Jul 16 03:22:12 server123 sendmail[4977]: e6G2M7O04977: from=<jsmith@server321.domain.com>, size=981, class=0, nrcpts=1, msgid=<200007152000.VAA24441@server321.domain.com>, proto=ESMTP, daemon=MTA, relay=server321.domain.com [10.0.0.65]
	#   0 Month, 1 Day, 2 hh:mm:ss, 3 nodename, 4 sendmail[NNNNN]:, 5 msg-id:, 6 from=FROM\,, 7 size=NNNNN\,, ...
	if ($line =~ /: from=.*, size=(\d+)/i) {
		$smtp_froms ++;
		$size = $1;
		$smtp_sizes += $size;
		if ($size > $smtp_MaxSize) {
			$smtp_MaxSize = $size;
		}
		printf "SMTP_FROM: %s", $line if $Options{debug};
		#	printf "smtp_froms=%s, size=%s, smtp_sizes=%s, smtp_MaxSize=%s\n", $smtp_froms, $size, $smtp_sizes, $smtp_MaxSize if $Options{debug};
		return 0;
	}

	# to
	#Jul 16 03:26:32 server123 sendmail[5060]: e6G2PqO05058: to=<info@domain1.pt>, delay=00:00:35, xdelay=00:00:35, mailer=esmtp, pri=120745, relay=server321.domain.com. [10.0.0.65], dsn=2.0.0, stat=Sent (DAA19487 Message accepted for delivery)
	#Jul 16 03:15:16 server123 sendmail[4828]: e6EBXrO12616: to=<sales@mail.domain2.pt>, delay=1+14:41:13, xdelay=00:00:55, mailer=esmtp, pri=3001977, relay=mail.domain2.pt. [11.0.0.130], dsn=4.0.0, stat=Deferred: Connection refused by mail.domain2.pt.
	#Jul 16 22:31:20 server123 sendmail[881]: e6GLUxP00881: to=<info@domain3.pt>, delay=00:00:11, xdelay=00:00:11, mailer=esmtp, pri=37973, relay=mail.domain4.pt. [12.0.0.15], dsn=5.0.0, stat=Service unavailable
	#Jul 24 18:33:05 server999 sendmail[15932]: SAA15929: to=<jsmith@domain4.pt>, ctladdr=<jjjj@domain9.pt> (16306/1984), delay=00:00:10, xdelay=00:00:09, mailer=esmtp, relay=mail.domain4.pt. [13.0.0.3], stat=Sent (Ok)
	if ($line =~ /: to=/) {
		if ($line =~ /, delay=(\d+)*\+*(\d+):(\d+):(\d+), .*, stat=Sent/i) {
			$seconds = 86400*$1 + 3600*$2 + 60*$3 + $4;

			$smtp_seconds += $seconds;
			if ($seconds > $smtp_MaxSeconds) {
				$smtp_MaxSeconds = $seconds;
			}
			$smtp_sent ++;
			printf "SMTP_SENT: %s", $line if $Options{debug};
			#	    printf "seconds=%s, smtp_seconds=%s, smtp_MaxSeconds=%s, smtp_sent=%s\n", $seconds, $smtp_seconds, $smtp_MaxSeconds, $smtp_sent if $Options{debug};
			return 0;
		}
		if ($line =~ /, dsn=5/i) {
			$smtp_fail++;
			printf "SMTP_FAIL: %s", $line if $Options{debug};
			#	    printf "smtp_fail=%s\n", $smtp_fail if $Options{debug};
			return 0;
		}
		if (($line =~ /, dsn=4/i) || ($line =~ /, stat=Deferred:/i)) {
			$smtp_retries++;
			printf "SMTP_RETRY: %s", $line if $Options{debug};
			#	    printf "smtp_retries=%s\n", $smtp_retries if $Options{debug};
			return 0;
		}
		if ($line =~ /, stat=queued/i) {
			$smtp_queued++;
			printf "SMTP_QUEUE: %s", $line if $Options{debug};
			#	    printf "smtp_queued=%s\n", $smtp_queued if $Options{debug};
			return 0;
		}
		$smtp_t_or_f++;
		printf "SMTP_T_OR_F: %s", $line if $Options{debug};
		#	printf "smtp_t_or_f=%s\n", $smtp_t_or_f if $Options{debug};
		return 0;
	}

	# ruleset=check_mail
	#Jul 16 22:24:43 server123 sendmail[604]: e6GLNMO00604: ruleset=check_mail, arg1=<Mary.Wilson@domain10.pt>, relay=server321.domain.com [10.0.0.65], reject=451 4.1.8 <Mary.Wilson@domain10.pt>... Domain of sender address Mary.Wilson@domain10.pt does not resolve
	if ($line =~ /: ruleset=check_mail, /i) {
		$smtp_check_mail ++;
		printf "SMTP_CHECK_MAIL: %s", $line if $Options{debug};
		#	printf "smtp_check_mail=%s\n", $smtp_check_mail if $Options{debug};
		return 0;
	}

	# ruleset=check_rcpt
	#Jul 19 16:54:55 server123 sendmail[11437]: e6JFsoO11437: ruleset=check_rcpt, arg1=<xyz@domain777.net>, relay=a.b.c.net [6.1.6.7], reject=550 5.7.1 <xyz@domain777.net>... Relaying denied
	#Jul 19 17:34:54 server123 sendmail[12479]: e6JGYKO12479: ruleset=check_rcpt, arg1=<Edgar.Silva@mail.soso.domain8888.pt>, relay=individual [10.0.0.67], reject=450 4.7.1 <Edgar.Silva@mail.soso.domain8888.pt>... Can not check MX records for recipient host mail.soso.domain8888.pt
	if ($line =~ /: ruleset=check_rcpt, /i) {
		$smtp_check_rcpt ++;
		printf "SMTP_CHECK_RCPT: %s", $line if $Options{debug};
		#	printf "smtp_check_rcpt=%s\n", $smtp_check_rcpt if $Options{debug};
		return 0;
	}

	# postmaster notify:
	#Jul 17 05:30:04 server123 sendmail[10016]: e6EKWRO24933: e6H401o10016: postmaster notify: Cannot send message within 2 days
	if ($line =~ /: postmaster notify: /i) {
		$smtp_notifies ++;
		printf "SMTP_NOTIFIES: %s", $line if $Options{debug};
		#	printf "smtp_notifies=%s\n", $smtp_notifies if $Options{debug};
		return 0;
	}

	# DSN
	#Jul 18 22:28:58 server123 sendmail[7172]: e6ILQlO07170: e6ILSwO07172: DSN: Service unavailable
	#Jul 19 14:38:00 server123 sendmail[1846]: e6HBWSO21997: e6JDU0t01846: DSN: Cannot send message within 2 days
	#Jul 19 17:33:51 server123 sendmail[12272]: e6JGTlO12270: e6JGXpO12272: DSN: Return receipt
	if ($line =~ /: DSN: /i) {
		$smtp_dsns ++;
		printf "SMTP_DSN: %s", $line if $Options{debug};
		#	printf "smtp_dsns=%s\n", $smtp_dsns if $Options{debug};
		return 0;
	}

	# Jun  7 11:37:08 server24 mailscanner[494]: Message g57Aam400830 is spam according to SpamAssassin (score=10.5, required 5, FROM_MALFORMED, FROM_NO_USER, PLING, PLING_PLING, HTML_EMBEDS, RAZOR_CHECK, CTYPE_JUST_HTML)
	if ($line =~ /: Message .* is spam according to/) {
		$smtp_spam ++;
		printf "SMTP_SPAM: %s", $line if $Options{debug};
		# printf "smtp_spam=%s\n", $smtp_spam if $Options{debug};
		return 0;
	}


	# Jun  7 10:31:33 ns2 mailscanner[23848]: Found 3 viruses in messages g579Uu428481,g579Uv428484
	# Jun  7 10:34:20 ns2 mailscanner[23848]: Found 1 viruses in messages g579Xm428666
	if ($line =~ /: Found (\d+) viruses in message/i) {
		$smtp_virus += $1;
		printf "SMTP_VIRUS: %s", $line if $Options{debug};
		# printf "smtp_virus=%s\n", $smtp_virus if $Options{debug};
		return 0;
	}

	# ignore the rest of mailscanner
	# Jun  7 10:31:33 ns2 mailscanner[23848]: 
	if ($line =~ / mailscanner\[\d+\]: /) {
		return 0;
	}

	# Nov  4 16:30:29 host2 llmail[9188]: OverQuota: user4 current: 15808428 bytes limit: 15728640 bytes
		if ($line =~ / llmail\[\d+\]: OverQuota: /) {
		$smtp_overquota ++;
		printf "SMTP_OVERQUOTA: %s", $line if $Options{debug};
		# printf "smtp_overquota: %s\n", $smtp_overquota if $Options{debug};
		return 0;
	}

	$smtp_undefs ++;
	printf "SMTP_UNDEF: %s", $line if $Options{debug};
	#    printf "smtp_undefs=%s\n", $smtp_undefs if $Options{debug};
	return 0;
}

# -------------------------------------------------------------------
#
# Put the smtp values for output
#
# usage: &put_smtp();
#

sub put_smtp() {
	&put_output("smtp_from",  sprintf("%8.2f", $smtp_froms));
	&put_output("smtp_tops",  sprintf("%8.2f", $smtp_MaxSize));
	if ($smtp_froms) {
		&put_output("smtp_sizes",  sprintf("%8.2f", $smtp_sizes/$smtp_froms));
	} else {
		&put_output("smtp_sizes",  sprintf("%8.2f", 0));
	}
	&put_output("smtp_sent",  sprintf("%8.2f", $smtp_sent));
	&put_output("smtp_maxd",  sprintf("%8.2f", $smtp_MaxSeconds));
	if ($smtp_sent) {
		&put_output("smtp_delay", sprintf("%8.2f", $smtp_seconds/$smtp_sent));
	} else {
		&put_output("smtp_delay", sprintf("%8.2f", 0));
	}
	&put_output("smtp_fail",  sprintf("%8.2f", $smtp_fail));
	&put_output("smtp_rtrs",  sprintf("%8.2f", $smtp_retries));
	&put_output("smtp_queued",  sprintf("%8.2f", $smtp_queued));
	&put_output("smtp_torf",  sprintf("%8.2f", $smtp_t_or_f));
	&put_output("smtp_c_ml",  sprintf("%8.2f", $smtp_check_mail));
	&put_output("smtp_c_rt",  sprintf("%8.2f", $smtp_check_rcpt));
	&put_output("smtp_ntfs",  sprintf("%8.2f", $smtp_notifies));
	&put_output("smtp_dsns",  sprintf("%8.2f", $smtp_dsns));

	&put_output("smtp_spam",  sprintf("%8.2f", $smtp_spam));
	&put_output("smtp_virus",  sprintf("%8.2f", $smtp_virus));

	&put_output("smtp_overquota",  sprintf("%8.2f", $smtp_overquota));

	&put_output("smtp_undf",  sprintf("%8.2f", $smtp_undefs));

	return 0;
}

1;
