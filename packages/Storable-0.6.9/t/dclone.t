#!./perl

# $Id: dclone.t,v 0.6.1.1 2000/03/02 22:21:05 ram Exp $
#
#  Copyright (c) 1995-1998, Raphael Manfredi
#  
#  You may redistribute only under the terms of the Artistic License,
#  as specified in the README file that comes with the distribution.
#
# $Log: dclone.t,v $
# Revision 0.6.1.1  2000/03/02 22:21:05  ram
# patch9: added test case for "undef" bug in hashes
#
# Revision 0.6  1998/06/04  16:08:25  ram
# Baseline for first beta release.
#

require 't/dump.pl';

use Storable qw(dclone);

print "1..9\n";

$a = 'toto';
$b = \$a;
$c = bless {}, CLASS;
$c->{attribute} = 'attrval';
%a = ('key', 'value', 1, 0, $a, $b, 'cvar', \$c);
@a = ('first', undef, 3, -4, -3.14159, 456, 4.5,
	$b, \$a, $a, $c, \$c, \%a);

print "not " unless defined ($aref = dclone(\@a));
print "ok 1\n";

$dumped = &dump(\@a);
print "ok 2\n";

$got = &dump($aref);
print "ok 3\n";

print "not " unless $got eq $dumped; 
print "ok 4\n";

package FOO; @ISA = qw(Storable);

sub make {
	my $self = bless {};
	$self->{key} = \%main::a;
	return $self;
};

package main;

$foo = FOO->make;
print "not " unless defined($r = $foo->dclone);
print "ok 5\n";

print "not " unless &dump($foo) eq &dump($r);
print "ok 6\n";

# Ensure refs to "undef" values are properly shared during cloning
my $hash;
push @{$$hash{''}}, \$$hash{a};
print "not " unless $$hash{''}[0] == \$$hash{a};
print "ok 7\n";

my $cloned = dclone(dclone($hash));
print "not " unless $$cloned{''}[0] == \$$cloned{a};
print "ok 8\n";

$$cloned{a} = "blah";
print "not " unless $$cloned{''}[0] == \$$cloned{a};
print "ok 9\n";

