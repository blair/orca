#!./perl

# $Id: tied.t,v 0.6 1998/06/04 16:08:40 ram Exp $
#
#  Copyright (c) 1995-1998, Raphael Manfredi
#  
#  You may redistribute only under the terms of the Artistic License,
#  as specified in the README file that comes with the distribution.
#
# $Log: tied.t,v $
# Revision 0.6  1998/06/04  16:08:40  ram
# Baseline for first beta release.
#

require 't/dump.pl';

use Storable qw(freeze thaw);

print "1..15\n";

($scalar_fetch, $array_fetch, $hash_fetch) = (0, 0, 0);

package TIED_HASH;

sub TIEHASH {
	my $self = bless {}, shift;
	return $self;
}

sub FETCH {
	my $self = shift;
	my ($key) = @_;
	$main::hash_fetch++;
	return $self->{$key};
}

sub STORE {
	my $self = shift;
	my ($key, $value) = @_;
	$self->{$key} = $value;
}

sub FIRSTKEY {
	my $self = shift;
	scalar keys %{$self};
	return each %{$self};
}

sub NEXTKEY {
	my $self = shift;
	return each %{$self};
}

package TIED_ARRAY;

sub TIEARRAY {
	my $self = bless [], shift;
	return $self;
}

sub FETCH {
	my $self = shift;
	my ($idx) = @_;
	$main::array_fetch++;
	return $self->[$idx];
}

sub STORE {
	my $self = shift;
	my ($idx, $value) = @_;
	$self->[$idx] = $value;
}

sub FETCHSIZE {
	my $self = shift;
	return @{$self};
}

package TIED_SCALAR;

sub TIESCALAR {
	my $scalar;
	my $self = bless \$scalar, shift;
	return $self;
}

sub FETCH {
	my $self = shift;
	$main::scalar_fetch++;
	return $$self;
}

sub STORE {
	my $self = shift;
	my ($value) = @_;
	$$self = $value;
}

package main;

$a = 'toto';
$b = \$a;

$c = tie %hash, TIED_HASH;
$d = tie @array, TIED_ARRAY;
tie $scalar, TIED_SCALAR;

#$scalar = 'foo';
#$hash{'attribute'} = \$d;
#$array[0] = $c;
#$array[1] = \$scalar;

### If I say
###   $hash{'attribute'} = $d;
### below, then dump() incorectly dumps the hash value as a string the second
### time it is reached. I have not investigated enough to tell whether it's
### a bug in my dump() routine or in the Perl tieing mechanism.
$scalar = 'foo';
$hash{'attribute'} = 'plain value';
$array[0] = \$scalar;
$array[1] = $c;
$array[2] = \@array;

@tied = (\$scalar, \@array, \%hash);
%a = ('key', 'value', 1, 0, $a, $b, 'cvar', \$a, 'scalarref', \$scalar);
@a = ('first', 3, -4, -3.14159, 456, 4.5, $d, \$d,
	$b, \$a, $a, $c, \$c, \%a, \@array, \%hash, \@tied);

print "not " unless defined($f = freeze(\@a));
print "ok 1\n";

$dumped = &dump(\@a);
print "ok 2\n";

$root = thaw($f);
print "not " unless defined $root;
print "ok 3\n";

$got = &dump($root);
print "ok 4\n";

### Used to see the manifestation of the bug documented above.
### print "original: $dumped";
### print "--------\n";
### print "got: $got";
### print "--------\n";

print "not " unless $got eq $dumped; 
print "ok 5\n";

$g = freeze($root);
print "not " unless length($f) == length($g);
print "ok 6\n";

# Ensure the tied items in the retrieved image work
@old = ($scalar_fetch, $array_fetch, $hash_fetch);
@tied = ($tscalar, $tarray, $thash) = @{$root->[$#{$root}]};
@type = qw(SCALAR  ARRAY  HASH);

print "not " unless tied $$tscalar;
print "ok 7\n";
print "not " unless tied @{$tarray};
print "ok 8\n";
print "not " unless tied %{$thash};
print "ok 9\n";

@new = ($$tscalar, $tarray->[0], $thash->{'attribute'});
@new = ($scalar_fetch, $array_fetch, $hash_fetch);

# Tests 10..15
for ($i = 0; $i < @new; $i++) {
	print "not " unless $new[$i] == $old[$i] + 1;
	printf "ok %d\n", 10 + 2*$i;	# Tests 10,12,14
	print "not " unless ref $tied[$i] eq $type[$i];
	printf "ok %d\n", 11 + 2*$i;	# Tests 11,13,15
}

