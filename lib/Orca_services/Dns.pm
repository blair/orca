#
# Dns.pm : Orca_Services package for dns monitoring
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

package Orca_Services::Dns;

BEGIN {
	use strict;
	use Carp;
	use Exporter;
	use IO::File;
	use Sys::Syslog;
	use Orca_Services::Vars;
	$Services{Dns}{File} = "/var/log/named";
	$Services{Dns}{FileD} = "";
	$Services{Dns}{Ok} = -1;
	$Services{Dns}{External} = 0;
	$Services{Dns}{Init} = "init_dns";
	$Services{Dns}{Init_Vars} = "init_dns_vars";
	$Services{Dns}{Measure} = "measure_dns";
	$Services{Dns}{Put} = "put_dns";

	$PrgOptions{"dns_logfile=s"} = \$Services{Dns}{File};

	$HelpText{$Services{Dns}{File}} = "--dns_logfile=FILE    syslog from named           (default:";
}


use Orca_Services::Utils;
use Orca_Services::Output;
use vars qw(@EXPORT @ISA $VERSION);

@EXPORT = qw(init_dns
		init_dns_vars
		measure_dns
		put_dns
                );
@ISA       = qw(Exporter);
$VERSION   = substr q$Revision: 0.01 $, 10;

my ($dns_cpu_u, $dns_cpu_s, $dns_ccpu_u, $dns_ccpu_s, $dns_a);
my ($dns_ptr, $dns_mx, $dns_any, $dns_ns, $dns_soa, $dns_axfr);
my ($dns_aaaa, $dns_other, $dns_rr, $dns_rq, $dns_rother, $dns_sans);
my ($dns_snaans, $dns_snxd, $dns_sother);
my ($dns_usage_started, $dns_nstats_started, $dns_xstats_started);
my ($odns_rr, $odns_rq, $odns_rother, $odns_sans, $odns_snaans, $odns_snxd, $odns_sother);
my ($odns_cpu_u, $odns_cpu_s, $odns_ccpu_u, $odns_ccpu_s, $odns_a);
my ($odns_ptr, $odns_mx, $odns_any, $odns_ns, $odns_soa, $odns_axfr);
my ($odns_aaaa, $odns_other);
my ($dns_ino, $dns_size);


#
# usage: &init_dns($dns_logfile);
#
sub init_dns {
	my ($filename) = @_;
	my ($retval);

	if ($filename) {
		$retval = OpenFile($filename, "Dns", \$dns_ino, \$dns_size);
	}

	if($retval == 0) {
		&init_dns_vars ();
	}
	return $retval;
}

#
# Get values for dns columns
#
# usage: &measure_dns( );
#
sub measure_dns () {
	my ($buf);

	$buf = $Services{Dns}{FileD}->getline;
	while ($buf) {
		## process line read and check for eof
		if ($buf) {
			&process_dns_line ($buf);
		}
		if ($Services{Dns}{FileD}->eof) {
			printf "DNS: eof on $Services{Dns}{File}\n" if $Options{debug};
			last; # get out of while($buf)
		}
		$buf = $Services{Dns}{FileD}->getline;
	} ## while ($buf)

	my $retval =  CheckFileChange ("Dns", \$dns_ino, \$dns_size);

	return $retval;
}


#
# init dns vars
#
# usage: &init_dns_vars();
#
sub init_dns_vars() {
	$dns_usage_started       = 0;
	$dns_nstats_started      = 0;
	$dns_xstats_started      = 0;

	&init_dns_usage_vars();
	&init_dns_nstats_vars();
	&init_dns_xstats_vars();

	&init_odns_vars();
}

sub init_dns_usage_vars () {
	$dns_cpu_u      = 0;
	$dns_cpu_s      = 0;
	$dns_ccpu_u     = 0;
	$dns_ccpu_s     = 0;
}
sub init_dns_nstats_vars () {
	$dns_a          = 0;
	$dns_ptr        = 0;
	$dns_mx         = 0;
	$dns_any        = 0;

	$dns_ns         = 0;
	$dns_soa        = 0;
	$dns_axfr       = 0;
	$dns_aaaa       = 0;
	$dns_other      = 0;
}

sub init_dns_xstats_vars () {
	$dns_rr         = 0;
	$dns_rq         = 0;
	$dns_rother     = 0;

	$dns_sans       = 0;
	$dns_snaans     = 0;
	$dns_snxd       = 0;
	$dns_sother     = 0;
}    


#
# init odns vars    (save old values)
#
# usage: &init_odns_vars();
#

sub init_odns_vars() {
	&init_odns_usage_vars();
	&init_odns_nstats_vars();
	&init_odns_xstats_vars();
}

sub init_odns_usage_vars() {
	$odns_cpu_u      = $dns_cpu_u      ;
	$odns_cpu_s      = $dns_cpu_s      ;
	$odns_ccpu_u     = $dns_ccpu_u     ;
	$odns_ccpu_s     = $dns_ccpu_s     ;

	&init_dns_usage_vars();
}

sub init_odns_nstats_vars() {
	$odns_a          = $dns_a          ;
	$odns_ptr        = $dns_ptr        ;
	$odns_mx         = $dns_mx         ;
	$odns_any        = $dns_any        ;

	$odns_ns         = $dns_ns         ;
	$odns_soa        = $dns_soa        ;
	$odns_axfr       = $dns_axfr       ;
	$odns_aaaa       = $dns_aaaa       ;
	$odns_other      = $dns_other      ;

	&init_dns_nstats_vars();
}

sub init_odns_xstats_vars() {
	$odns_rr         = $dns_rr         ;
	$odns_rq         = $dns_rq         ;
	$odns_rother     = $dns_rother     ;

	$odns_sans       = $dns_sans       ;
	$odns_snaans     = $dns_snaans     ;
	$odns_snxd       = $dns_snxd       ;
	$odns_sother     = $dns_sother     ;

	&init_dns_xstats_vars();
}


#
# calc dns delta
#
# usage: &calc_dns_delta();
#
sub calc_dns_delta() {
	&calc_dns_usage_delta();
	&calc_dns_nstats_delta();
	&calc_dns_xstats_delta();
}

sub calc_dns_usage_delta() {
	my $temp = 0;

	if ($dns_cpu_u < $odns_cpu_u) {
		$odns_cpu_u = $dns_cpu_u;
	} else {
		$temp = $dns_cpu_u; $dns_cpu_u = $dns_cpu_u - $odns_cpu_u; $odns_cpu_u = $temp;
	}

	if ($dns_cpu_s < $odns_cpu_s) {
		$odns_cpu_s = $dns_cpu_s;
	} else {
		$temp = $dns_cpu_s; $dns_cpu_s = $dns_cpu_s - $odns_cpu_s; $odns_cpu_s = $temp;

	}
	if ($dns_ccpu_u < $odns_ccpu_u) {
		$odns_ccpu_u = $dns_ccpu_u;
	} else {
		$temp = $dns_ccpu_u; $dns_ccpu_u = $dns_ccpu_u - $odns_ccpu_u; $odns_ccpu_u = $temp;

	}
	if ($dns_ccpu_s < $odns_ccpu_s) {
		$odns_ccpu_s = $dns_ccpu_s;
	} else {
		$temp = $dns_ccpu_s; $dns_ccpu_s = $dns_ccpu_s - $odns_ccpu_s; $odns_ccpu_s = $temp;
	}

}
sub calc_dns_nstats_delta() {
	my $temp = 0;

	if ($dns_a < $odns_a) {
		$odns_a = $dns_a;
	} else {
		$temp = $dns_a; $dns_a = $dns_a - $odns_a; $odns_a = $temp;
	}

	if ($dns_ptr < $odns_ptr) {
		$odns_ptr = $dns_ptr;
	} else {
		$temp = $dns_ptr; $dns_ptr = $dns_ptr - $odns_ptr; $odns_ptr = $temp;
	}

	if ($dns_mx < $odns_mx) {
		$odns_mx = $dns_mx;
	} else {
		$temp = $dns_mx; $dns_mx = $dns_mx - $odns_mx; $odns_mx = $temp;
	}

	if ($dns_any < $odns_any) {
		$odns_any = $dns_any;
	} else {
		$temp = $dns_any; $dns_any = $dns_any - $odns_any; $odns_any = $temp;
	}

	if ($dns_ns < $odns_ns) {
		$odns_ns = $dns_ns;
	} else {
		$temp = $dns_ns; $dns_ns = $dns_ns - $odns_ns; $odns_ns = $temp;
	}

	if ($dns_soa < $odns_soa) {
		$odns_soa = $dns_soa;
	} else {
		$temp = $dns_soa; $dns_soa = $dns_soa - $odns_soa; $odns_soa = $temp;
	}
	if ($dns_axfr < $odns_axfr) {
		$odns_axfr = $dns_axfr;
	} else {
		$temp = $dns_axfr; $dns_axfr = $dns_axfr - $odns_axfr; $odns_axfr = $temp;
	}

	if ($dns_aaaa < $odns_aaaa) {
		$odns_aaaa = $dns_aaaa;
	} else {
		$temp = $dns_aaaa; $dns_aaaa = $dns_aaaa - $odns_aaaa; $odns_aaaa = $temp;
	}

	if ($dns_other < $odns_other) {
		$odns_other = $dns_other;
	} else {
		$temp = $dns_other; $dns_other = $dns_other - $odns_other; $odns_other = $temp;
	}
}

sub calc_dns_xstats_delta() {
	my $temp = 0;

	if ($dns_rr < $odns_rr) {
		$odns_rr = $dns_rr;
	} else {
		$temp = $dns_rr; $dns_rr = $dns_rr - $odns_rr; $odns_rr = $temp;
	}

	if ($dns_rq < $odns_rq) {
		$odns_rq = $dns_rq;
	} else {
		$temp = $dns_rq; $dns_rq = $dns_rq - $odns_rq; $odns_rq = $temp;
	}

	if ($dns_rother < $odns_rother) {
		$odns_rother = $dns_rother;
	} else {
		$temp = $dns_rother; $dns_rother = $dns_rother - $odns_rother; $odns_rother = $temp;
	}

	if ($dns_sans < $odns_sans) {
		$odns_sans = $dns_sans;
	} else {
		$temp = $dns_sans; $dns_sans = $dns_sans - $odns_sans; $odns_sans = $temp;
	}

	if ($dns_snaans < $odns_snaans) {
		$odns_snaans = $dns_snaans;
	} else {
		$temp = $dns_snaans; $dns_snaans = $dns_snaans - $odns_snaans; $odns_snaans = $temp;
	}

	if ($dns_snxd < $odns_snxd) {
		$odns_snxd = $dns_snxd;
	} else {
		$temp = $dns_snxd; $dns_snxd = $dns_snxd - $odns_snxd; $odns_snxd = $temp;
	}

	if ($dns_sother < $odns_sother) {
		$odns_sother = $dns_sother;
	} else {
		$temp = $dns_sother; $dns_sother = $dns_sother - $odns_sother; $odns_sother = $temp;
	}
}


# -------------------------------------------------------------------
#
# Parse dns log line
#
# usage: &process_dns_line ($buf);
#

sub process_dns_line () {
	my ($line) = @_;
	my ($t, $v, @types);

	#
	# Oct 24 14:27:49 r1 named[17279]: USAGE 972394069 970586866 CPU=188.82u/82.79s CHILDCPU=0u/0s
	# Oct 24 14:27:49 r1 named[17279]: NSTATS 972394069 970586866 0=6 A=322014 NS=25 SOA=415 PTR=35772 MX=111 SRV=110 ANY=238
	# Oct 24 14:27:49 r1 named[17279]: XSTATS 972394069 970586866 RR=293985 RNXD=22941 RFwdR=205718 RDupR=3603 RFail=508 RFErr=0 RErr=141 RAXFR=0 RLame=2636 ROpts=0 SSysQ=58851 SAns=205888 SFwdQ=169140 SDupQ=23529 SErr=0 RQ=358773 RIQ=0 RFwdQ=0 RDupQ=8397 RTCP=206 SFwdR=205718 SFail=3 SFErr=0 SNaAns=204478 SNXD=45736
	#
	if ($line !~ / named\[\d+\]: (USAGE|NSTATS|XSTATS) /) {
		return 0;
	}


	# Oct 24 14:27:49 r1 named[17279]: USAGE 972394069 970586866 CPU=188.82u/82.79s CHILDCPU=0u/0s
	if ($line =~ /: USAGE \d+ \d+ CPU=([\d\.]+)u\/([\d\.]+)s CHILDCPU=([\d\.]+)u\/([\d\.]+)s/) {
		$dns_cpu_u = $1;
		$dns_cpu_s = $2;
		$dns_ccpu_u = $3;
		$dns_ccpu_s = $4;

		printf "DNS_USAGE: %s", $line if $Options{debug};
		printf "dns_cpu_u=%s, dns_cpu_s=%s, dns_ccpu_u=%s, dns_ccpu_s=%s\n", $dns_cpu_u, $dns_cpu_s, $dns_ccpu_u, $dns_ccpu_s if $Options{debug};

		if ($dns_usage_started) {
			&calc_dns_usage_delta(); # puts delta into vars to print -&- saves into old
		} else {
			$dns_usage_started = 1;
			&init_odns_usage_vars();  # saves old and cleans current values
		}

	# Oct 24 14:27:49 r1 named[17279]: NSTATS 972394069 970586866 0=6 A=322014 NS=25 SOA=415 PTR=35772 MX=111 SRV=110 ANY=238
	} elsif ($line =~ /: NSTATS \d+ \d+ /) {
		my $l;

		($l = $line) =~ s/^.*: NSTATS \d+ \d+ //;  # trim beginning
		chop $l;

		@types = split(' ',$l);

		$dns_other = 0;
		while (@types) {
			($t,$v) = split ('=', pop @types);
			if ($t eq 'A') {
				$dns_a = $v;
			} elsif ($t eq 'PTR') {
				$dns_ptr = $v;
			} elsif ($t eq 'MX') {
				$dns_mx = $v;
			} elsif ($t eq 'ANY') {
				$dns_any = $v;
			} elsif ($t eq 'NS') {
				$dns_ns = $v;
			} elsif ($t eq 'SOA') {
				$dns_soa = $v;
			} elsif ($t eq 'AXFR') {
				$dns_axfr = $v;
			} elsif ($t eq 'AAAA') {
				$dns_aaaa = $v;
			} else {
				$dns_other += $v;
			}
		}

		printf "DNS_NSTATS: %s", $line if $Options{debug};
		printf "dns_a=%s, dns_ptr=%s, dns_mx=%s, dns_any=%s, dns_ns=%s, dns_soa=%s, dns_axfr=%s, dns_aaaa=%s, dns_other=%s\n", $dns_a, $dns_ptr, $dns_mx, $dns_any, $dns_ns, $dns_soa, $dns_axfr, $dns_aaaa, $dns_other if $Options{debug};

		if ($dns_nstats_started) {
			&calc_dns_nstats_delta(); # puts delta into vars to print -&- saves into old
		} else {
			$dns_nstats_started = 1;
			&init_odns_nstats_vars();  # saves old and cleans current values
		}

	# Oct 24 14:27:49 r1 named[17279]: XSTATS 972394069 970586866 RR=293985 RNXD=22941 RFwdR=205718 RDupR=3603 RFail=508 RFErr=0 RErr=141 RAXFR=0 RLame=2636 ROpts=0 SSysQ=58851 SAns=205888 SFwdQ=169140 SDupQ=23529 SErr=0 RQ=358773 RIQ=0 RFwdQ=0 RDupQ=8397 RTCP=206 SFwdR=205718 SFail=3 SFErr=0 SNaAns=204478 SNXD=45736
	} elsif ($line =~ /: XSTATS \d+ \d+ /) {
		my $l;

		($l = $line) =~ s/^.*: XSTATS \d+ \d+ //;  # trim beginning
		chop $l;

		@types = split(' ',$l);

		$dns_rother = $dns_sother = 0;
		while (@types) {
			($t,$v) = split ('=', pop @types);
			if ($t eq 'RR') {
				$dns_rr = $v;
			} elsif ($t eq 'RQ') {
				$dns_rq = $v;
			} elsif ($t =~ /^R/) {
				$dns_rother += $v;
			} elsif ($t eq 'SAns') {
				$dns_sans = $v;
			} elsif ($t eq 'SNaAns') {
				$dns_snaans = $v;
			} elsif ($t eq 'SNXD') {
				$dns_snxd = $v;
			} elsif ($t =~ /^S/) {
				$dns_sother += $v;
			}
		}

		printf "DNS_XSTATS: %s", $line if $Options{debug};
		printf "dns_rr=%s, dns_rq=%s, dns_rother=%s, dns_sans=%s, dns_snaans=%s, dns_snxd=%s, dns_sother=%s\n", $dns_rr, $dns_rq, $dns_rother, $dns_sans, $dns_snaans, $dns_snxd, $dns_sother if $Options{debug};

		if ($dns_xstats_started) {
			&calc_dns_xstats_delta(); # puts delta into vars to print -&- saves into old
		} else {
			$dns_xstats_started = 1;
			&init_odns_xstats_vars();  # saves old and cleans current values
		}
	}
	return 0;
}


#
# Put the dns values for output
#
# usage: &put_dns();
#
sub put_dns() {
	&put_output("dns_cpu_u",  sprintf("%8.2f", $dns_cpu_u));
	&put_output("dns_cpu_s",  sprintf("%8.2f", $dns_cpu_s));
	&put_output("dns_ccpu_u",  sprintf("%8.2f", $dns_ccpu_u));
	&put_output("dns_ccpu_s",  sprintf("%8.2f", $dns_ccpu_s));

	&put_output("dns_a",  sprintf("%8.2f", $dns_a));
	&put_output("dns_ptr",  sprintf("%8.2f", $dns_ptr));
	&put_output("dns_mx",  sprintf("%8.2f", $dns_mx));
	&put_output("dns_any",  sprintf("%8.2f", $dns_any));

	&put_output("dns_ns",  sprintf("%8.2f", $dns_ns));
	&put_output("dns_soa",  sprintf("%8.2f", $dns_soa));
	&put_output("dns_axfr",  sprintf("%8.2f", $dns_axfr));
	&put_output("dns_aaaa",  sprintf("%8.2f", $dns_aaaa));
	&put_output("dns_other",  sprintf("%8.2f", $dns_other));

	&put_output("dns_rr",  sprintf("%8.2f", $dns_rr));
	&put_output("dns_rq",  sprintf("%8.2f", $dns_rq));
	&put_output("dns_rother",  sprintf("%8.2f", $dns_rother));

	&put_output("dns_sans",  sprintf("%8.2f", $dns_sans));
	&put_output("dns_snaans",  sprintf("%8.2f", $dns_snaans));
	&put_output("dns_snxd",  sprintf("%8.2f", $dns_snxd));
	&put_output("dns_sother",  sprintf("%8.2f", $dns_sother));

	return 0;
}

1;
