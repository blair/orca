#
# Http.pm : Orca_Services package for http monitoring
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

package Orca_Services::Http;

BEGIN {
	use strict;
	use Carp;
	use Exporter;
	use IO::File;
	use Sys::Syslog;
	use Orca_Services::Vars;
	$Services{Http}{File} = "/export/home/squid/logs/access.log";
	$Services{Http}{FileD} = "";
	$Services{Http}{Ok} = -1;
	$Services{Http}{External} = 0;
	$Services{Http}{Init} = "init_http";
	$Services{Http}{Init_Vars} = "init_http_vars";
	$Services{Http}{Measure} = "measure_http";
	$Services{Http}{Put} = "put_http";

	#
	# something you want to do in the external loop 
	$Services{Http}{Extra} = "count_http_procs";

	$PrgOptions{"http_logfile=s"} = \$Services{Http}{File};

	$HelpText{$Services{Http}{File}} = "--http_logfile=FILE   log from http               (default:";
}

use Proc::ProcessTable;
use Orca_Services::Utils;
use Orca_Services::Output;
use vars qw(@EXPORT @ISA $VERSION);

@EXPORT = qw(init_http
		init_http_vars
		measure_http
		put_http
		count_http_procs
                );
@ISA       = qw(Exporter);
$VERSION   = substr q$Revision: 0.01 $, 10;

my ($http_procs, $http_condgets, $http_gets, $http_heads, $http_posts);
my ($http_hits, $http_errors, $http_total_bytes, $http_1k, $http_10k);
my ($http_100k, $http_1000k, $http_1M, $http_undefs);
my ($http_ino, $http_size);

#
# init_http - set HTTP vars, open the logfile and seek into the end.
#
# usage: &init_http($http_logfile);
#
sub init_http {
	my ($filename) = @_;
	my ($retval);

	if ($filename) {
		$retval = OpenFile($filename, "Http", \$http_ino, \$http_size);
	}

	if($retval == 0) {
		&init_http_vars ();
	}
	return $retval;
}

#
# Get values for http columns
#
# usage: &measure_http( );
#

sub measure_http () {
	my ($buf);

	$buf = $Services{Http}{FileD}->getline;
	while ($buf) {
		## process line read and check for eof
		if ($buf) {
			&process_http_line ($buf);
		}
		if ($Services{Http}{FileD}->eof) {
			printf "HTTP: eof on $Services{Http}{File}\n" if $Options{debug};
			last; # get out of while($buf)
		}
		$buf = $Services{Http}{FileD}->getline;
	} ## while ($buf)

	my $retval =  CheckFileChange ("Http", \$http_ino, \$http_size);

	return $retval;
}


#
# init http vars
#
# usage: &init_http_vars();
#

sub init_http_vars() {
	$http_procs  = 0;

	$http_condgets  = 0;
	$http_gets   = 0;
	$http_heads  = 0;
	$http_posts  = 0;

	$http_hits   = 0;
	$http_errors = 0;
	$http_total_bytes = 0;
	$http_1k = $http_10k = $http_100k = $http_1000k = $http_1M = 0;

	$http_undefs = 0;
}

#
# Parse http log line
#
# usage: &process_http_line ($buf);
#

sub process_http_line () {
	my ($line) = @_;

	printf "HTTP_LINE: %s", $line if $Options{debug};

	### mix-bayonne-102-1-111.abo.wanadoo.fr - - [28/Feb/2001:17:46:54 +0000] "GET /Lisboa/i/lisboa.html HTTP/1.1" 301 328 "http://www.quid.fr/generation/detail_selectweb.php?iso=pt" "Mozilla/4.0 (compatible; MSIE 5.0; Windows 95; DigExt; KITV4.7 Wanadoo)"
	if ($line =~ / \"GET\s.*\"\s(3\d+)\s(\d+)/) {
		$http_condgets++;
		&process_http_values( $1, $2 );
		return 0
	}
	### mail.abola.pt - - [28/Feb/2001:17:49:24 +0000] "GET /images/mc_kpnq.gif HTTP/1.1" 304 - "http://www.kpnqwest.pt/entrada.html" "Mozilla/4.0 (compatible; MSIE 5.0; Windows 98; DigExt)"
	if ($line =~ / \"GET\s.*\"\s(3\d+)\s\-/) {
		$http_condgets++;
		&process_http_values( $1, 0 );
		return 0
	}

	### p153a155.teleweb.pt - - [27/Feb/2001:02:02:28 +0000] "GET /images/menu_0.gif HTTP/1.1" 200 6356 "http://www.kpnqwest.pt/menu.html" "Mozilla/4.0 (compatible; MSIE 5.5; Windows 98; Win 9x 4.90)"
	if ($line =~ / \"GET\s.*\"\s(\d+)\s(\d+)/) {
		$http_gets++;
		&process_http_values( $1, $2 );
		return 0
	}


	### marvin.northernlight.com - - [27/Feb/2001:17:55:52 +0000] "HEAD /corporate/press_130100.html HTTP/1.1" 200 0 "-" "Gulliver/1.3"
	if ($line =~ / \"HEAD\s.*\"\s(\d+)\s(\d+)/) {
		$http_heads++;
		&process_http_values( $1, $2 );
		return 0
	}

	### p87.b.shuttle.de - - [27/Feb/2001:10:55:58 +0000] "POST /cgi-bin/idx/eunet/search.dat HTTP/1.0" 200 5932 "http://www.kpnqwest.pt/entrada.html" "Mozilla/4.0 (compatible; MSIE 5.0; Windows 98; DigExt)"
	if ($line =~ / \"HEAD\s.*\"\s(\d+)\s(\d+)/) {
		$http_posts++;
		&process_http_values( $1, $2 );
		return 0
	}

	$http_undefs++;
	printf "HTTP_UNDEF: %s", $line if $Options{debug};
	return 0;
}

sub process_http_values () {
	my ($code, $bytes) = @_;


	$http_hits++;
	$http_total_bytes += $bytes;

	if ($code =~ /^[45]\d\d/) {
		$http_errors++;
	}

	printf "HTTP_code_bytes: %s %s", $code, $bytes if $Options{debug};
	if ($bytes < 1024) {
		$http_1k ++;
	} elsif ($bytes < 10240) {
		$http_10k ++;
	} elsif ($bytes < 102400) {
		$http_100k ++;
	} elsif ($bytes < 1024000) {
		$http_1000k ++;
	} else {
		$http_1M ++;
	}

	return 0;
}



# -------------------------------------------------------------------
#
# Put the http values for output
#
# usage: &put_http();
#

sub put_http() {
	&put_output("http_hits",  sprintf("%8.2f", $http_hits));
	&put_output("http_condgets",  sprintf("%8.2f", $http_condgets));
	&put_output("http_gets",  sprintf("%8.2f", $http_gets));
	&put_output("http_heads",  sprintf("%8.2f", $http_heads));
	&put_output("http_posts",  sprintf("%8.2f", $http_posts));
	&put_output("http_errors",  sprintf("%8.2f", $http_errors));
	&put_output("http_undefs",  sprintf("%8.2f", $http_undefs));

	if ($interval) {
		&put_output("http_Bps", sprintf("%8.2f", $http_total_bytes/$interval));
	} else {
		&put_output("http_Bps", sprintf("%8.2f", 0));
	}

	if ($http_hits) {
		&put_output("http_1k", sprintf("%8.2f", $http_1k/$http_hits));
		&put_output("http_10k", sprintf("%8.2f", $http_10k/$http_hits));
		&put_output("http_100k", sprintf("%8.2f", $http_100k/$http_hits));
		&put_output("http_1000k", sprintf("%8.2f", $http_1000k/$http_hits));
		&put_output("http_1M", sprintf("%8.2f", $http_1M/$http_hits));
	} else {
		&put_output("http_1k", sprintf("%8.2f", 0));
		&put_output("http_10k", sprintf("%8.2f", 0));
		&put_output("http_100k", sprintf("%8.2f", 0));
		&put_output("http_1000k", sprintf("%8.2f", 0));
		&put_output("http_1M", sprintf("%8.2f", 0));
	}

	&put_output("http_procs",  sprintf("%8.2f", $http_procs));
}

sub count_http_procs {
	my $t = new Proc::ProcessTable;
	$http_procs = 0;
	foreach $p ( @{$t->table} ){
		if ($p->cmndline =~ /http/) {
			$http_procs++;
		}
	}
}

1;
