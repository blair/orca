# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..14\n"; }
END {print "not ok 1\n" unless $loaded;}
use Time::HiRes qw(tv_interval);
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

use strict;

my $have_gettimeofday	= defined &Time::HiRes::gettimeofday;
my $have_usleep		= defined &Time::HiRes::usleep;
my $have_ualarm		= defined &Time::HiRes::ualarm;

import Time::HiRes 'gettimeofday'	if $have_gettimeofday;
import Time::HiRes 'usleep'		if $have_usleep;
import Time::HiRes 'ualarm'		if $have_ualarm;

sub skip {
    map { print "ok $_ (skipped)\n" } @_;
}

sub ok {
    my ($n, $result, @info) = @_;
    if ($result) {
    	print "ok $n\n";
    }
    else {
	print "not ok $n\n";
    	print "# @info\n" if @info;
    }
}

if (!$have_gettimeofday) {
    skip 2..6;
}
else {
    my @one = gettimeofday();
    ok 2, @one == 2, 'gettimeofday returned ', 0+@one, ' args';
    ok 3, $one[0] > 850_000_000, "@one too small";

    sleep 1;

    my @two = gettimeofday();
    ok 4, ($two[0] > $one[0] || ($two[0] == $one[0] && $two[1] > $one[1])),
    	    "@two is not greater than @one";

    my $f = Time::HiRes::time;
    ok 5, $f > 850_000_000, "$f too small";
    ok 6, $f - $two[0] < 2, "$f - @two >= 2";
}

if (!$have_usleep) {
    skip 7..8;
}
else {
    my $one = time;
    usleep(10_000);
    my $two = time;
    usleep(10_000);
    my $three = time;
    ok 7, $one == $two || $two == $three, "slept too long, $one $two $three";

    if (!$have_gettimeofday) {
    	skip 8;
    }
    else {
    	my $f = Time::HiRes::time;
	usleep(500_000);
        my $f2 = Time::HiRes::time;
	my $d = $f2 - $f;
	ok 8, $d > 0.4 && $d < 0.8, "slept $d secs $f to $f2";
    }
}

# Two-arg tv_interval() is always available.
{
    my $f = tv_interval [5, 100_000], [10, 500_000];
    ok 9, $f == 5.4, $f;
}

if (!$have_gettimeofday) {
    skip 10;
}
else {
    my $r = [gettimeofday()];
    my $f = tv_interval $r;
    ok 10, $f < 2, $f;
}

if (!$have_usleep) {
    skip 11;
}
else {
    my $r = [gettimeofday()];
    #jTime::HiRes::sleep 0.5;
    Time::HiRes::sleep( 0.5 );
    my $f = tv_interval $r;
    ok 11, $f > 0.4 && $f < 0.8, "slept $f secs";
}

if (!$have_ualarm) {
    skip 12..13;
}
else {
    my $tick = 0;
    local $SIG{ALRM} = sub { $tick++ };

    my $one = time; $tick = 0; ualarm(10_000); sleep until $tick;
    my $two = time; $tick = 0; ualarm(10_000); sleep until $tick;
    my $three = time;
    ok 12, $one == $two || $two == $three, "slept too long, $one $two $three";

    $tick = 0;
    ualarm(10_000, 10_000);
    sleep until $tick >= 3;
    ok 13, 1;
    ualarm(0);
}

# new test: did we even get close?

{
 my $t = time();
 my $tf = Time::HiRes::time();
 ok 14, ($tf >= $t) && (($tf - $t) <= 1),
  "time $t differs from Time::HiRes::time $tf";
}
