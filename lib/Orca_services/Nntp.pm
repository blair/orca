#
# Nntp.pm : Orca_Services package for monitoring nntp
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

package Orca_Services::Nntp;

BEGIN {
	use strict;
	use Carp;
	use Exporter;
	use IO::File;
	use Sys::Syslog;
	use Orca_Services::Vars;
	$Services{Nntp}{File} = "/var/log/news/news.debug";
	$Services{Nntp}{FileD} = "";
	$Services{Nntp}{Ok} = -1;
	$Services{Nntp}{External} = 0;
	$Services{Nntp}{Init} = "init_nntpcache";
	$Services{Nntp}{Init_Vars} = "init_nntpcache";
	$Services{Nntp}{Measure} = "measure_nntpcache";
	$Services{Nntp}{Put} = "put_nntpcache";

	$PrgOptions{"nntpcache_logfile=s"} = \$Services{Nntp}{File};

	$HelpText{$Services{Nntp}{File}} = "--nntpcache_logfile=FILE    log from nntpcache       (default:";
}

use Orca_Services::Utils;
use Orca_Services::Output;
use vars qw(@EXPORT @ISA $VERSION);

@EXPORT = qw(init_nntpcache
		init_nntpcache_vars
		measure_nntpcache
		put_nntpcache
                );
@ISA       = qw(Exporter);
$VERSION   = substr q$Revision: 0.01 $, 10;

my ($nntpcache_connects,$nntpcache_groups,$nntpcache_articles);
my ($nntpcache_ino, $nntpcache_size);

#
# init_nntpcache - set NNTPCACHE vars, open the logfile and seek into the end.
#
# usage: &init_nntpcache($nntpcache_logfile);
#
sub init_nntpcache {
	my ($filename) = @_;
	my ($retval);

	if ($filename) {
		$retval = OpenFile($filename, "Nntp", \$nntpcache_ino, \$nntpcache_size);
	}

	if($retval == 0) {
		&init_nntpcache_vars ();
	}
	return $retval;
}


#
# Get values for nntpcache columns
#
# usage: &measure_nntpcache( );
#

sub measure_nntpcache () {
	my($buf);

	$buf = $Services{Nntp}{FileD}->getline;
	while ($buf) {
		## process line read and check for eof
		if ($buf) {
			&process_nntpcache_line ($buf);
		}
		if ($Services{Nntp}{FileD}->eof) {
			printf "NNTPCACHE: eof on $Services{Nntp}{File}\n" if $Options{debug};
			last; # get out of while($buf)
		}
		$buf = $Services{Nntp}{FileD}->getline;
	} ## while ($buf)

	my $retval =  CheckFileChange ("Nntp", \$nntpcache_ino, \$nntpcache_size);

	return $retval;
}


#
# init nntpcache vars
#
# usage: &init_nntpcache_vars();
#

sub init_nntpcache_vars() {
	$nntpcache_connects   = 0;
	$nntpcache_groups     = 0;
	$nntpcache_articles   = 0;
}


#
# Parse nntpcache log line
#
# usage: &process_nntpcache_line ($buf);
#

sub process_nntpcache_line () {
	my ($line) = @_;

	if ($line !~ /\snntpcache-client\[\d+\]:\s/) {
		return 0;
	}


	# connect from
	# Nov  5 16:27:01 news nntpcache-client[6789]: 10.1.2.2 connect from  (10.1.2.2)

	if ($line =~ /\sconnect\sfrom\s/) {
		$nntpcache_connects ++;
		printf "NNTPCACHE_CONNECTS: %s", $line if $Options{debug};
		return 0;
	}

	# GROUP
	# Nov  5 16:27:01 news nntpcache-client[6789]: sockets.c:455: <- GROUP microsoft.public.visual.sourcesafe

	if ($line =~ /:\s<-\sGROUP\s/) {
		$nntpcache_groups ++;
		printf "NNTPCACHE_GROUPS: %s", $line if $Options{debug};
		return 0;
	}

	# ARTICLE
	# Nov  5 16:27:07 news nntpcache-client[6789]: sockets.c:455: <- ARTICLE 13460

	if ($line =~ /:\s<-\sARTICLE\s/) {
		$nntpcache_articles ++;
		printf "NNTPCACHE_ARTICLES: %s", $line if $Options{debug};
		return 0;
	}

	return 0;
}


#
# Put the nntpcache values for output
#
# usage: &put_nntpcache();
#
sub put_nntpcache() {
	&put_output("nntpcache_connects",  sprintf("%8.2f", $nntpcache_connects));
	&put_output("nntpcache_groups",  sprintf("%8.2f", $nntpcache_groups));
	&put_output("nntpcache_articles",  sprintf("%8.2f", $nntpcache_articles));

	return 0;
}

1;
