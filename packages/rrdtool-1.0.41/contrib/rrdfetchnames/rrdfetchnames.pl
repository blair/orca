#!/usr/bin/perl

use strict;

#makes things work when run without install
use lib qw( ../../perl-shared/blib/lib ../../perl-shared/blib/arch );

#makes programm work AFTER install
use lib qw( /usr/local/rrdtool-1.0.41/lib/perl ../lib/perl );

use vars qw(@ISA $loaded);

use RRDs;

my $NAME = $ARGV[ 0];
my $SEPARATOR = " ";
my $CF = "AVERAGE";

my ($start,$step,$names,$data) = RRDs::fetch "$NAME", "$CF", "--start", "now","--end","start+1";

if ( my $ERR = RRDs::error){
	die "ERROR while fetching data from $NAME $ERR\n";
}

print join( $SEPARATOR, @$names), "\n";

sub usage{
	print "usage: rrdfetchnames filename";
};

