#!./perl

# $Id: canonical.t,v 0.6 1998/06/04 16:08:24 ram Exp $
#
#  Copyright (c) 1995-1998, Raphael Manfredi
#  
#  You may redistribute only under the terms of the Artistic License,
#  as specified in the README file that comes with the distribution.
#  
# $Log: canonical.t,v $
# Revision 0.6  1998/06/04 16:08:24  ram
# Baseline for first beta release.
#

BEGIN { push @INC, "../blib" }

use Storable qw(freeze thaw dclone);
use vars qw($debugging $verbose);

print "1..5\n";

sub ok {
    my($testno, $ok) = @_;
    print "not " unless $ok;
    print "ok $testno\n";
}


# Uncomment the folowing line to get a dump of the constructed data structure
# (you may want to reduce the size of the hashes too)
# $debugging = 1;

$hashsize = 100;
$maxhash2size = 100;
$maxarraysize = 100;

# Use MD5 if its available to make random string keys

eval { require "MD5.pm" };
$gotmd5 = !$@;

# Use Data::Dumper if debugging and it is available to create an ASCII dump

if ($debugging) {
    eval { require "Data/Dumper.pm" };
    $gotdd  = !$@;
}

@fixed_strings = ("January", "February", "March", "April", "May", "June",
		  "July", "August", "September", "October", "November", "December" );

# Build some arbitrarily complex data structure starting with a top level hash
# (deeper levels contain scalars, references to hashes or references to arrays);

for (my $i = 0; $i < $hashsize; $i++) {
	my($k) = int(rand(1_000_000));
	$k = MD5->hexhash($k) if $gotmd5 and int(rand(2));
	$a1{$k} = { key => "$k", value => $i };

	# A third of the elements are references to further hashes

	if (int(rand(1.5))) {
		my($hash2) = {};
		my($hash2size) = int(rand($maxhash2size));
		while ($hash2size--) {
			my($k2) = $k . $i . int(rand(100));
			$hash2->{$k2} = $fixed_strings[rand(int(@fixed_strings))];
		}
		$a1{$k}->{value} = $hash2;
	}

	# A further third are references to arrays

	elsif (int(rand(2))) {
		my($arr_ref) = [];
		my($arraysize) = int(rand($maxarraysize));
		while ($arraysize--) {
			push(@$arr_ref, $fixed_strings[rand(int(@fixed_strings))]);
		}
		$a1{$k}->{value} = $arr_ref;
	}	
}


print STDERR Data::Dumper::Dumper(\%a1) if ($verbose and $gotdd);


# Copy the hash, element by element in order of the keys

foreach $k (sort keys %a1) {
    $a2{$k} = { key => "$k", value => $a1{$k}->{value} };
}

# Deep clone the hash

$a3 = dclone(\%a1);

# In canonical mode the frozen representation of each of the hashes
# should be identical

$Storable::canonical = 1;

$x1 = freeze(\%a1);
$x2 = freeze(\%a2);
$x3 = freeze($a3);

ok 1, (length($x1) > $hashsize);	# sanity check
ok 2, length($x1) == length($x2);	# idem
ok 3, $x1 eq $x2;
ok 4, $x1 eq $x3;

# In normal mode it is exceedingly unlikely that the frozen
# representaions of all the hashes will be the same (normally the hash
# elements are frozen in the order they are stored internally,
# i.e. pseudo-randomly).

$Storable::canonical = 0;

$x1 = freeze(\%a1);
$x2 = freeze(\%a2);
$x3 = freeze($a3);


# Two out of three the same may be a coincidence, all three the same
# is much, much more unlikely.  Still it could happen, so this test
# may report a false negative.

ok 5, ($x1 ne $x2) || ($x1 ne $x3);    
