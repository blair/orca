#!./perl

# $Id: forgive.t,v 0.6 1998/06/04 16:08:38 ram Exp $
#
#  Copyright (c) 1995-1998, Raphael Manfredi
#  
#  You may redistribute only under the terms of the Artistic License,
#  as specified in the README file that comes with the distribution.
#
# Original Author: Ulrich Pfeifer
# (C) Copyright 1997, Universitat Dortmund, all rights reserved.
#
# $Log: forgive.t,v $
# Revision 0.6  1998/06/04 16:08:38  ram
# Baseline for first beta release.
#

use Storable qw(store retrieve);

print "1..8\n";

my $test = 1;
my $bad = ['foo', sub { 1 },  'bar'];
my $result;

eval {$result = store ($bad , 't/store')};
print ((!defined $result)?"ok $test\n":"not ok $test\n"); $test++;
print (($@ ne '')?"ok $test\n":"not ok $test\n"); $test++;

$Storable::forgive_me=1;

open(SAVEERR, ">&STDERR");
open(STDERR, ">/dev/null") or 
  ( print SAVEERR "Unable to redirect STDERR: $!\n" and exit(1) );

eval {$result = store ($bad , 't/store')};

open(STDERR, ">&SAVEERR");

print ((defined $result)?"ok $test\n":"not ok $test\n"); $test++;
print (($@ eq '')?"ok $test\n":"not ok $test\n"); $test++;

my $ret = retrieve('t/store');
print ((defined $ret)?"ok $test\n":"not ok $test\n"); $test++;
print (($ret->[0] eq 'foo')?"ok $test\n":"not ok $test\n"); $test++;
print (($ret->[2] eq 'bar')?"ok $test\n":"not ok $test\n"); $test++;
print ((ref $ret->[1] eq 'SCALAR')?"ok $test\n":"not ok $test\n"); $test++;


END {
  unlink 't/store';
}
