#!./perl
#
#  Copyright (c) 2002 Slaven Rezic
#
#  You may redistribute only under the same terms as Perl 5, as specified
#  in the README file that comes with the distribution.
#

sub BEGIN {
    if ($ENV{PERL_CORE}){
	chdir('t') if -d 't';
	@INC = ('.', '../lib');
    } else {
	unshift @INC, 't';
    }
    require Config; import Config;
    if ($ENV{PERL_CORE} and $Config{'extensions'} !~ /\bStorable\b/) {
        print "1..0 # Skip: Storable was not built\n";
        exit 0;
    }
}

use strict;
BEGIN {
    if (!eval q{
	use Test;
	use B::Deparse 0.61;
	use 5.6.0;
	1;
    }) {
	print "1..0 # skip: tests only work with B::Deparse 0.61 and at least perl 5.6.0\n";
	exit;
    }
    require File::Spec;
    if ($File::Spec::VERSION < 0.8) {
	print "1..0 # Skip: newer File::Spec needed\n";
	exit 0;
    }
}

BEGIN { plan tests => 47 }

use Storable qw(retrieve store nstore freeze nfreeze thaw dclone);
use Safe;

#$Storable::DEBUGME = 1;

use vars qw($freezed $thawed @obj @res $blessed_code);

sub code { "JAPH" }
$blessed_code = bless sub { "blessed" }, "Some::Package";
{ package Another::Package; sub foo { __PACKAGE__ } }

@obj =
    ([\&code,                   # code reference
      sub { 6*7 },
      $blessed_code,            # blessed code reference
      \&Another::Package::foo,  # code in another package
      sub ($$;$) { 0 },         # prototypes
      sub { print "test\n" },
      \&Test::ok,               # large scalar
     ],

     {"a" => sub { "srt" }, "b" => \&code},

     sub { ord("a")-ord("7") },

     \&code,

     \&dclone,                 # XS function

     sub { open FOO, "/" },
    );

$Storable::Deparse = 1;
$Storable::Eval    = 1;

######################################################################
# Test freeze & thaw

$freezed = freeze $obj[0];
$thawed  = thaw $freezed;

ok($thawed->[0]->(), "JAPH");
ok($thawed->[1]->(), 42);
ok($thawed->[2]->(), "blessed");
ok($thawed->[3]->(), "Another::Package");
ok(prototype($thawed->[4]), prototype($obj[0]->[4]));

######################################################################

$freezed = freeze $obj[1];
$thawed  = thaw $freezed;

ok($thawed->{"a"}->(), "srt");
ok($thawed->{"b"}->(), "JAPH");

######################################################################

$freezed = freeze $obj[2];
$thawed  = thaw $freezed;

ok($thawed->(), 42);

######################################################################

$freezed = freeze $obj[3];
$thawed  = thaw $freezed;

ok($thawed->(), "JAPH");

######################################################################

eval { $freezed = freeze $obj[4] };
ok($@ =~ /The result of B::Deparse::coderef2text was empty/);

######################################################################
# Test dclone

my $new_sub = dclone($obj[2]);
ok($new_sub->(), $obj[2]->());

######################################################################
# Test retrieve & store

store $obj[0], 'store';
$thawed = retrieve 'store';

ok($thawed->[0]->(), "JAPH");
ok($thawed->[1]->(), 42);
ok($thawed->[2]->(), "blessed");
ok($thawed->[3]->(), "Another::Package");
ok(prototype($thawed->[4]), prototype($obj[0]->[4]));

######################################################################

nstore $obj[0], 'store';
$thawed = retrieve 'store';
unlink 'store';

ok($thawed->[0]->(), "JAPH");
ok($thawed->[1]->(), 42);
ok($thawed->[2]->(), "blessed");
ok($thawed->[3]->(), "Another::Package");
ok(prototype($thawed->[4]), prototype($obj[0]->[4]));

######################################################################
# Security with
#   $Storable::Eval
#   $Storable::Deparse

{
    local $Storable::Eval = 0;

    for my $i (0 .. 1) {
	$freezed = freeze $obj[$i];
	$@ = "";
	eval { $thawed  = thaw $freezed };
	ok($@ =~ /Can\'t eval/);
    }
}

{

    local $Storable::Deparse = 0;
    for my $i (0 .. 1) {
	$@ = "";
	eval { $freezed = freeze $obj[$i] };
	ok($@ =~ /Can\'t store CODE items/);
    }
}

{
    local $Storable::Eval = 0;
    local $Storable::forgive_me = 1;
    for my $i (0 .. 4) {
	$freezed = freeze $obj[0]->[$i];
	$@ = "";
	eval { $thawed  = thaw $freezed };
	ok($@, "");
	ok($$thawed =~ /^sub/);
    }
}

{
    local $Storable::Deparse = 0;
    local $Storable::forgive_me = 1;

    my $devnull = File::Spec->devnull;

    open(SAVEERR, ">&STDERR");
    open(STDERR, ">$devnull") or
	( print SAVEERR "Unable to redirect STDERR: $!\n" and exit(1) );

    eval { $freezed = freeze $obj[0]->[0] };

    open(STDERR, ">&SAVEERR");

    ok($@, "");
    ok($freezed ne '');
}

{
    my $safe = new Safe;
    $safe->permit(qw(:default require));
    local $Storable::Eval = sub { $safe->reval(shift) };

    for my $def ([0 => "JAPH",
		  1 => 42,
		 ]
		) {
	my($i, $res) = @$def;
	$freezed = freeze $obj[0]->[$i];
	$@ = "";
	eval { $thawed = thaw $freezed };
	ok($@, "");
	ok($thawed->(), $res);
    }

    $freezed = freeze $obj[0]->[6];
    eval { $thawed = thaw $freezed };
    ok($@ =~ /trapped/);

    if (0) {
	# Disable or fix this test if the internal representation of Storable
	# changes.
	skip("no malicious storable file check", 1);
    } else {
	# Construct malicious storable code
	$freezed = nfreeze $obj[0]->[0];
	my $bad_code = ';open FOO, "/badfile"';
	# 5th byte is (short) length of scalar
	my $len = ord(substr($freezed, 4, 1));
	substr($freezed, 4, 1, chr($len+length($bad_code)));
	substr($freezed, -1, 0, $bad_code);
	$@ = "";
	eval { $thawed = thaw $freezed };
	ok($@ =~ /trapped/);
    }
}

{
    {
	package MySafe;
	sub new { bless {}, shift }
	sub reval {
	    my $source = $_[1];
	    # Here you can apply some nifty regexpes to ensure the
	    # safeness of the source code.
	    my $coderef = eval $source;
	    $coderef;
	}
    }

    my $safe = new MySafe;
    local $Storable::Eval = sub { $safe->reval($_[0]) };

    $freezed = freeze $obj[0];
    eval { $thawed  = thaw $freezed };
    ok($@, "");

    if ($@ ne "") {
        ok(0) for (1..5);
    } else {
	ok($thawed->[0]->(), "JAPH");
	ok($thawed->[1]->(), 42);
	ok($thawed->[2]->(), "blessed");
	ok($thawed->[3]->(), "Another::Package");
	ok(prototype($thawed->[4]), prototype($obj[0]->[4]));
    }
}

