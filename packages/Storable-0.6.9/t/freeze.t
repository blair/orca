#!./perl

# $Id: freeze.t,v 0.6.1.1 1998/06/12 09:47:08 ram Exp $
#
#  Copyright (c) 1995-1998, Raphael Manfredi
#  
#  You may redistribute only under the terms of the Artistic License,
#  as specified in the README file that comes with the distribution.
#
# $Log: freeze.t,v $
# Revision 0.6.1.1  1998/06/12 09:47:08  ram
# patch1: added test for the LVALUE bug workaround
#
# Revision 0.6  1998/06/04  16:08:31  ram
# Baseline for first beta release.
#

require 't/dump.pl';

use Storable qw(freeze nfreeze thaw);

print "1..15\n";

$a = 'toto';
$b = \$a;
$c = bless {}, CLASS;
$c->{attribute} = $b;
$d = {};
$e = [];
$d->{'a'} = $e;
$e->[0] = $d;
%a = ('key', 'value', 1, 0, $a, $b, 'cvar', \$c);
@a = ('first', undef, 3, -4, -3.14159, 456, 4.5, $d, \$d, \$e, $e,
	$b, \$a, $a, $c, \$c, \%a);

print "not " unless defined ($f1 = freeze(\@a));
print "ok 1\n";

$dumped = &dump(\@a);
print "ok 2\n";

$root = thaw($f1);
print "not " unless defined $root;
print "ok 3\n";

$got = &dump($root);
print "ok 4\n";

print "not " unless $got eq $dumped; 
print "ok 5\n";

package FOO; @ISA = qw(Storable);

sub make {
	my $self = bless {};
	$self->{key} = \%main::a;
	return $self;
};

package main;

$foo = FOO->make;
print "not " unless $f2 = $foo->freeze;
print "ok 6\n";

print "not " unless $f3 = $foo->nfreeze;
print "ok 7\n";

$root3 = thaw($f3);
print "not " unless defined $root3;
print "ok 8\n";

print "not " unless &dump($foo) eq &dump($root3);
print "ok 9\n";

$root = thaw($f2);
print "not " unless &dump($foo) eq &dump($root);
print "ok 10\n";

print "not " unless &dump($root3) eq &dump($root);
print "ok 11\n";

$other = freeze($root);
print "not " unless length($other) == length($f2);
print "ok 12\n";

$root2 = thaw($other);
print "not " unless &dump($root2) eq &dump($root);
print "ok 13\n";

$VAR1 = [
	'method',
	1,
	'prepare',
	'SELECT table_name, table_owner, num_rows FROM iitables
                  where table_owner != \'$ingres\' and table_owner != \'DBA\''
];

$x = nfreeze($VAR1);
$VAR2 = thaw($x);
print "not " unless $VAR2->[3] eq $VAR1->[3];
print "ok 14\n";

# Test the workaround for LVALUE bug in perl 5.004_04 -- from Gisle Aas
sub foo { $_[0] = 1 }
$foo = [];
foo($foo->[1]);
eval { freeze($foo) };
print "not " if $@;
print "ok 15\n";

