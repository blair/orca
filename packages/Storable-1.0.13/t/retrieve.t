#!./perl

# $Id: retrieve.t,v 1.0 2000/09/01 19:40:42 ram Exp $
#
#  Copyright (c) 1995-2000, Raphael Manfredi
#  
#  You may redistribute only under the same terms as Perl 5, as specified
#  in the README file that comes with the distribution.
#
# $Log: retrieve.t,v $
# Revision 1.0  2000/09/01 19:40:42  ram
# Baseline for first official release.
#

require 't/dump.pl';

use Storable qw(store retrieve nstore);

print "1..14\n";

$a = 'toto';
$b = \$a;
$c = bless {}, CLASS;
$c->{attribute} = 'attrval';
%a = ('key', 'value', 1, 0, $a, $b, 'cvar', \$c);
@a = ('first', '', undef, 3, -4, -3.14159, 456, 4.5,
	$b, \$a, $a, $c, \$c, \%a);

print "not " unless defined store(\@a, 't/store');
print "ok 1\n";
print "not " if Storable::last_op_in_netorder();
print "ok 2\n";
print "not " unless defined nstore(\@a, 't/nstore');
print "ok 3\n";
print "not " unless Storable::last_op_in_netorder();
print "ok 4\n";
print "not " unless Storable::last_op_in_netorder();
print "ok 5\n";

$root = retrieve('t/store');
print "not " unless defined $root;
print "ok 6\n";
print "not " if Storable::last_op_in_netorder();
print "ok 7\n";

$nroot = retrieve('t/nstore');
print "not " unless defined $nroot;
print "ok 8\n";
print "not " unless Storable::last_op_in_netorder();
print "ok 9\n";

$d1 = &dump($root);
print "ok 10\n";
$d2 = &dump($nroot);
print "ok 11\n";

print "not " unless $d1 eq $d2; 
print "ok 12\n";

# Make sure empty string is defined at retrieval time
print "not " unless defined $root->[1];
print "ok 13\n";
print "not " if length $root->[1];
print "ok 14\n";

unlink 't/store', 't/nstore';

