#!./perl

# $Id: retrieve.t,v 0.6 1998/06/04 16:08:33 ram Exp ram $
#
#  Copyright (c) 1995-1998, Raphael Manfredi
#  
#  You may redistribute only under the terms of the Artistic License,
#  as specified in the README file that comes with the distribution.
#
# $Log: retrieve.t,v $
# Revision 0.6  1998/06/04  16:08:33  ram
# Baseline for first beta release.
#

require 't/dump.pl';

use Storable qw(store retrieve nstore);

print "1..9\n";

$a = 'toto';
$b = \$a;
$c = bless {}, CLASS;
$c->{attribute} = 'attrval';
%a = ('key', 'value', 1, 0, $a, $b, 'cvar', \$c);
@a = ('first', '', undef, 3, -4, -3.14159, 456, 4.5,
	$b, \$a, $a, $c, \$c, \%a);

print "not " unless defined store(\@a, 't/store');
print "ok 1\n";
print "not " unless defined nstore(\@a, 't/nstore');
print "ok 2\n";

$root = retrieve('t/store');
print "not " unless defined $root;
print "ok 3\n";

$nroot = retrieve('t/nstore');
print "not " unless defined $nroot;
print "ok 4\n";

$d1 = &dump($root);
print "ok 5\n";
$d2 = &dump($nroot);
print "ok 6\n";

print "not " unless $d1 eq $d2; 
print "ok 7\n";

# Make sure empty string is defined at retrieval time
print "not " unless defined $root->[1];
print "ok 8\n";
print "not " if length $root->[1];
print "ok 9\n";

unlink 't/store', 't/nstore';

