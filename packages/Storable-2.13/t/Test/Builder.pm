package Test::Builder;

use 5.004;

# $^C was only introduced in 5.005-ish.  We do this to prevent
# use of uninitialized value warnings in older perls.
$^C ||= 0;

use strict;
use vars qw($VERSION $CLASS);
$VERSION = '0.17';
$CLASS = __PACKAGE__;

my $IsVMS = $^O eq 'VMS';

# Make Test::Builder thread-safe for ithreads.
BEGIN {
    use Config;
    if( $] >= 5.008 && $Config{useithreads} ) {
        require threads;
        require threads::shared;
        threads::shared->import;
    }
    else {
        *share = sub { 0 };
        *lock  = sub { 0 };
    }
}

use vars qw($Level);
my($Test_Died) = 0;
my($Have_Plan) = 0;
my $Original_Pid = $$;
my $Curr_Test = 0;      share($Curr_Test);
my @Test_Results = ();  share(@Test_Results);
my @Test_Details = ();  share(@Test_Details);


=head1 NAME

Test::Builder - Backend for building test libraries

=head1 SYNOPSIS

  package My::Test::Module;
  use Test::Builder;
  require Exporter;
  @ISA = qw(Exporter);
  @EXPORT = qw(ok);

  my $Test = Test::Builder->new;
  $Test->output('my_logfile');

  sub import {
      my($self) = shift;
      my $pack = caller;

      $Test->exported_to($pack);
      $Test->plan(@_);

      $self->export_to_level(1, $self, 'ok');
  }

  sub ok {
      my($test, $name) = @_;

      $Test->ok($test, $name);
  }


=head1 DESCRIPTION

Test::Simple and Test::More have proven to be popular testing modules,
but they're not always flexible enough.  Test::Builder provides the a
building block upon which to write your own test libraries I<which can
work together>.

=head2 Construction

=over 4

=item B<new>

  my $Test = Test::Builder->new;

Returns a Test::Builder object representing the current state of the
test.

Since you only run one test per program, there is B<one and only one>
Test::Builder object.  No matter how many times you call new(), you're
getting the same object.  (This is called a singleton).

=cut

my $Test;
sub new {
    my($class) = shift;
    $Test ||= bless ['Move along, nothing to see here'], $class;
    return $Test;
}

=back

=head2 Setting up tests

These methods are for setting up tests and declaring how many there
are.  You usually only want to call one of these methods.

=over 4

=item B<exported_to>

  my $pack = $Test->exported_to;
  $Test->exported_to($pack);

Tells Test::Builder what package you exported your functions to.
This is important for getting TODO tests right.

=cut

my $Exported_To;
sub exported_to {
    my($self, $pack) = @_;

    if( defined $pack ) {
        $Exported_To = $pack;
    }
    return $Exported_To;
}

=item B<plan>

  $Test->plan('no_plan');
  $Test->plan( skip_all => $reason );
  $Test->plan( tests => $num_tests );

A convenient way to set up your tests.  Call this and Test::Builder
will print the appropriate headers and take the appropriate actions.

If you call plan(), don't call any of the other methods below.

=cut

sub plan {
    my($self, $cmd, $arg) = @_;

    return unless $cmd;

    if( $Have_Plan ) {
        die sprintf "You tried to plan twice!  Second plan at %s line %d\n",
          ($self->caller)[1,2];
    }

    if( $cmd eq 'no_plan' ) {
        $self->no_plan;
    }
    elsif( $cmd eq 'skip_all' ) {
        return $self->skip_all($arg);
    }
    elsif( $cmd eq 'tests' ) {
        if( $arg ) {
            return $self->expected_tests($arg);
        }
        elsif( !defined $arg ) {
            die "Got an undefined number of tests.  Looks like you tried to ".
                "say how many tests you plan to run but made a mistake.\n";
        }
        elsif( !$arg ) {
            die "You said to run 0 tests!  You've got to run something.\n";
        }
    }
    else {
        require Carp;
        my @args = grep { defined } ($cmd, $arg);
        Carp::croak("plan() doesn't understand @args");
    }

    return 1;
}

=item B<expected_tests>

    my $max = $Test->expected_tests;
    $Test->expected_tests($max);

Gets/sets the # of tests we expect this test to run and prints out
the appropriate headers.

=cut

my $Expected_Tests = 0;
sub expected_tests {
    my($self, $max) = @_;

    if( defined $max ) {
        $Expected_Tests = $max;
        $Have_Plan      = 1;

        $self->_print("1..$max\n") unless $self->no_header;
    }
    return $Expected_Tests;
}


=item B<no_plan>

  $Test->no_plan;

Declares that this test will run an indeterminate # of tests.

=cut

my($No_Plan) = 0;
sub no_plan {
    $No_Plan    = 1;
    $Have_Plan  = 1;
}

=item B<has_plan>

  $plan = $Test->has_plan
  
Find out whether a plan has been defined. $plan is either C<undef> (no plan has been set), C<no_plan> (indeterminate # of tests) or an integer (the number of expected tests).

=cut

sub has_plan {
	return($Expected_Tests) if $Expected_Tests;
	return('no_plan') if $No_Plan;
	return(undef);
};


=item B<skip_all>

  $Test->skip_all;
  $Test->skip_all($reason);

Skips all the tests, using the given $reason.  Exits immediately with 0.

=cut

my $Skip_All = 0;
sub skip_all {
    my($self, $reason) = @_;

    my $out = "1..0";
    $out .= " # Skip $reason" if $reason;
    $out .= "\n";

    $Skip_All = 1;

    $self->_print($out) unless $self->no_header;
    exit(0);
}

=back

=head2 Running tests

These actually run the tests, analogous to the functions in
Test::More.

$name is always optional.

=over 4

=item B<ok>

  $Test->ok($test, $name);

Your basic test.  Pass if $test is true, fail if $test is false.  Just
like Test::Simple's ok().

=cut

sub ok {
    my($self, $test, $name) = @_;

    # $test might contain an object which we don't want to accidentally
    # store, so we turn it into a boolean.
    $test = $test ? 1 : 0;

    unless( $Have_Plan ) {
        require Carp;
        Carp::croak("You tried to run a test without a plan!  Gotta have a plan.");
    }

    lock $Curr_Test;
    $Curr_Test++;

    $self->diag(<<ERR) if defined $name and $name =~ /^[\d\s]+$/;
    You named your test '$name'.  You shouldn't use numbers for your test names.
    Very confusing.
ERR

    my($pack, $file, $line) = $self->caller;

    my $todo = $self->todo($pack);

    my $out;
    my $result = {};
    share($result);

    unless( $test ) {
        $out .= "not ";
        @$result{ 'ok', 'actual_ok' } = ( ( $todo ? 1 : 0 ), 0 );
    }
    else {
        @$result{ 'ok', 'actual_ok' } = ( 1, $test );
    }

    $out .= "ok";
    $out .= " $Curr_Test" if $self->use_numbers;

    if( defined $name ) {
        $name =~ s|#|\\#|g;     # # in a name can confuse Test::Harness.
        $out   .= " - $name";
        $result->{name} = $name;
    }
    else {
        $result->{name} = '';
    }

    if( $todo ) {
        my $what_todo = $todo;
        $out   .= " # TODO $what_todo";
        $result->{reason} = $what_todo;
        $result->{type}   = 'todo';
    }
    else {
        $result->{reason} = '';
        $result->{type}   = '';
    }

    $Test_Results[$Curr_Test-1] = $result;
    $out .= "\n";

    $self->_print($out);

    unless( $test ) {
        my $msg = $todo ? "Failed (TODO)" : "Failed";
        $self->diag("    $msg test ($file at line $line)\n");
    } 

    return $test ? 1 : 0;
}

=item B<is_eq>

  $Test->is_eq($got, $expected, $name);

Like Test::More's is().  Checks if $got eq $expected.  This is the
string version.

=item B<is_num>

  $Test->is_num($got, $expected, $name);

Like Test::More's is().  Checks if $got == $expected.  This is the
numeric version.

=cut

sub is_eq {
    my($self, $got, $expect, $name) = @_;
    local $Level = $Level + 1;

    if( !defined $got || !defined $expect ) {
        # undef only matches undef and nothing else
        my $test = !defined $got && !defined $expect;

        $self->ok($test, $name);
        $self->_is_diag($got, 'eq', $expect) unless $test;
        return $test;
    }

    return $self->cmp_ok($got, 'eq', $expect, $name);
}

sub is_num {
    my($self, $got, $expect, $name) = @_;
    local $Level = $Level + 1;

    if( !defined $got || !defined $expect ) {
        # undef only matches undef and nothing else
        my $test = !defined $got && !defined $expect;

        $self->ok($test, $name);
        $self->_is_diag($got, '==', $expect) unless $test;
        return $test;
    }

    return $self->cmp_ok($got, '==', $expect, $name);
}

sub _is_diag {
    my($self, $got, $type, $expect) = @_;

    foreach my $val (\$got, \$expect) {
        if( defined $$val ) {
            if( $type eq 'eq' ) {
                # quote and force string context
                $$val = "'$$val'"
            }
            else {
                # force numeric context
                $$val = $$val+0;
            }
        }
        else {
            $$val = 'undef';
        }
    }

    return $self->diag(sprintf <<DIAGNOSTIC, $got, $expect);
         got: %s
    expected: %s
DIAGNOSTIC

}    

=item B<isnt_eq>

  $Test->isnt_eq($got, $dont_expect, $name);

Like Test::More's isnt().  Checks if $got ne $dont_expect.  This is
the string version.

=item B<isnt_num>

  $Test->is_num($got, $dont_expect, $name);

Like Test::More's isnt().  Checks if $got ne $dont_expect.  This is
the numeric version.

=cut

sub isnt_eq {
    my($self, $got, $dont_expect, $name) = @_;
    local $Level = $Level + 1;

    if( !defined $got || !defined $dont_expect ) {
        # undef only matches undef and nothing else
        my $test = defined $got || defined $dont_expect;

        $self->ok($test, $name);
        $self->_cmp_diag('ne', $got, $dont_expect) unless $test;
        return $test;
    }

    return $self->cmp_ok($got, 'ne', $dont_expect, $name);
}

sub isnt_num {
    my($self, $got, $dont_expect, $name) = @_;
    local $Level = $Level + 1;

    if( !defined $got || !defined $dont_expect ) {
        # undef only matches undef and nothing else
        my $test = defined $got || defined $dont_expect;

        $self->ok($test, $name);
        $self->_cmp_diag('!=', $got, $dont_expect) unless $test;
        return $test;
    }

    return $self->cmp_ok($got, '!=', $dont_expect, $name);
}


=item B<like>

  $Test->like($this, qr/$regex/, $name);
  $Test->like($this, '/$regex/', $name);

Like Test::More's like().  Checks if $this matches the given $regex.

You'll want to avoid qr// if you want your tests to work before 5.005.

=item B<unlike>

  $Test->unlike($this, qr/$regex/, $name);
  $Test->unlike($this, '/$regex/', $name);

Like Test::More's unlike().  Checks if $this B<does not match> the
given $regex.

=cut

sub like {
    my($self, $this, $regex, $name) = @_;

    local $Level = $Level + 1;
    $self->_regex_ok($this, $regex, '=~', $name);
}

sub unlike {
    my($self, $this, $regex, $name) = @_;

    local $Level = $Level + 1;
    $self->_regex_ok($this, $regex, '!~', $name);
}

=item B<maybe_regex>

  $Test->maybe_regex(qr/$regex/);
  $Test->maybe_regex('/$regex/');

Convenience method for building testing functions that take regular
expressions as arguments, but need to work before perl 5.005.

Takes a quoted regular expression produced by qr//, or a string
representing a regular expression.

Returns a Perl value which may be used instead of the corresponding
regular expression, or undef if it's argument is not recognised.

For example, a version of like(), sans the useful diagnostic messages,
could be written as:

  sub laconic_like {
      my ($self, $this, $regex, $name) = @_;
      my $usable_regex = $self->maybe_regex($regex);
      die "expecting regex, found '$regex'\n"
          unless $usable_regex;
      $self->ok($this =~ m/$usable_regex/, $name);
  }

=cut


sub maybe_regex {
	my ($self, $regex) = @_;
    my $usable_regex = undef;
    if( ref $regex eq 'Regexp' ) {
        $usable_regex = $regex;
    }
    # Check if it looks like '/foo/'
    elsif( my($re, $opts) = $regex =~ m{^ /(.*)/ (\w*) $ }sx ) {
        $usable_regex = length $opts ? "(?$opts)$re" : $re;
    };
    return($usable_regex)
};

sub _regex_ok {
    my($self, $this, $regex, $cmp, $name) = @_;

    local $Level = $Level + 1;

    my $ok = 0;
    my $usable_regex = $self->maybe_regex($regex);
    unless (defined $usable_regex) {
        $ok = $self->ok( 0, $name );
        $self->diag("    '$regex' doesn't look much like a regex to me.");
        return $ok;
    }

    {
        local $^W = 0;
        my $test = $this =~ /$usable_regex/ ? 1 : 0;
        $test = !$test if $cmp eq '!~';
        $ok = $self->ok( $test, $name );
    }

    unless( $ok ) {
        $this = defined $this ? "'$this'" : 'undef';
        my $match = $cmp eq '=~' ? "doesn't match" : "matches";
        $self->diag(sprintf <<DIAGNOSTIC, $this, $match, $regex);
                  %s
    %13s '%s'
DIAGNOSTIC

    }

    return $ok;
}

=item B<cmp_ok>

  $Test->cmp_ok($this, $type, $that, $name);

Works just like Test::More's cmp_ok().

    $Test->cmp_ok($big_num, '!=', $other_big_num);

=cut

sub cmp_ok {
    my($self, $got, $type, $expect, $name) = @_;

    my $test;
    {
        local $^W = 0;
        local($@,$!);   # don't interfere with $@
                        # eval() sometimes resets $!
        $test = eval "\$got $type \$expect";
    }
    local $Level = $Level + 1;
    my $ok = $self->ok($test, $name);

    unless( $ok ) {
        if( $type =~ /^(eq|==)$/ ) {
            $self->_is_diag($got, $type, $expect);
        }
        else {
            $self->_cmp_diag($got, $type, $expect);
        }
    }
    return $ok;
}

sub _cmp_diag {
    my($self, $got, $type, $expect) = @_;
    
    $got    = defined $got    ? "'$got'"    : 'undef';
    $expect = defined $expect ? "'$expect'" : 'undef';
    return $self->diag(sprintf <<DIAGNOSTIC, $got, $type, $expect);
    %s
        %s
    %s
DIAGNOSTIC
}

=item B<BAILOUT>

    $Test->BAILOUT($reason);

Indicates to the Test::Harness that things are going so badly all
testing should terminate.  This includes running any additional test
scripts.

It will exit with 255.

=cut

sub BAILOUT {
    my($self, $reason) = @_;

    $self->_print("Bail out!  $reason");
    exit 255;
}

=item B<skip>

    $Test->skip;
    $Test->skip($why);

Skips the current test, reporting $why.

=cut

sub skip {
    my($self, $why) = @_;
    $why ||= '';

    unless( $Have_Plan ) {
        require Carp;
        Carp::croak("You tried to run tests without a plan!  Gotta have a plan.");
    }

    lock($Curr_Test);
    $Curr_Test++;

    my %result;
    share(%result);
    %result = (
        'ok'      => 1,
        actual_ok => 1,
        name      => '',
        type      => 'skip',
        reason    => $why,
    );
    $Test_Results[$Curr_Test-1] = \%result;

    my $out = "ok";
    $out   .= " $Curr_Test" if $self->use_numbers;
    $out   .= " # skip $why\n";

    $Test->_print($out);

    return 1;
}


=item B<todo_skip>

  $Test->todo_skip;
  $Test->todo_skip($why);

Like skip(), only it will declare the test as failing and TODO.  Similar
to

    print "not ok $tnum # TODO $why\n";

=cut

sub todo_skip {
    my($self, $why) = @_;
    $why ||= '';

    unless( $Have_Plan ) {
        require Carp;
        Carp::croak("You tried to run tests without a plan!  Gotta have a plan.");
    }

    lock($Curr_Test);
    $Curr_Test++;

    my %result;
    share(%result);
    %result = (
        'ok'      => 1,
        actual_ok => 0,
        name      => '',
        type      => 'todo_skip',
        reason    => $why,
    );

    $Test_Results[$Curr_Test-1] = \%result;

    my $out = "not ok";
    $out   .= " $Curr_Test" if $self->use_numbers;
    $out   .= " # TODO & SKIP $why\n";

    $Test->_print($out);

    return 1;
}


=begin _unimplemented

=item B<skip_rest>

  $Test->skip_rest;
  $Test->skip_rest($reason);

Like skip(), only it skips all the rest of the tests you plan to run
and terminates the test.

If you're running under no_plan, it skips once and terminates the
test.

=end _unimplemented

=back


=head2 Test style

=over 4

=item B<level>

    $Test->level($how_high);

How far up the call stack should $Test look when reporting where the
test failed.

Defaults to 1.

Setting $Test::Builder::Level overrides.  This is typically useful
localized:

    {
        local $Test::Builder::Level = 2;
        $Test->ok($test);
    }

=cut

sub level {
    my($self, $level) = @_;

    if( defined $level ) {
        $Level = $level;
    }
    return $Level;
}

$CLASS->level(1);


=item B<use_numbers>

    $Test->use_numbers($on_or_off);

Whether or not the test should output numbers.  That is, this if true:

  ok 1
  ok 2
  ok 3

or this if false

  ok
  ok
  ok

Most useful when you can't depend on the test output order, such as
when threads or forking is involved.

Test::Harness will accept either, but avoid mixing the two styles.

Defaults to on.

=cut

my $Use_Nums = 1;
sub use_numbers {
    my($self, $use_nums) = @_;

    if( defined $use_nums ) {
        $Use_Nums = $use_nums;
    }
    return $Use_Nums;
}

=item B<no_header>

    $Test->no_header($no_header);

If set to true, no "1..N" header will be printed.

=item B<no_ending>

    $Test->no_ending($no_ending);

Normally, Test::Builder does some extra diagnostics when the test
ends.  It also changes the exit code as described in Test::Simple.

If this is true, none of that will be done.

=cut

my($No_Header, $No_Ending) = (0,0);
sub no_header {
    my($self, $no_header) = @_;

    if( defined $no_header ) {
        $No_Header = $no_header;
    }
    return $No_Header;
}

sub no_ending {
    my($self, $no_ending) = @_;

    if( defined $no_ending ) {
        $No_Ending = $no_ending;
    }
    return $No_Ending;
}


=back

=head2 Output

Controlling where the test output goes.

It's ok for your test to change where STDOUT and STDERR point to,
Test::Builder's default output settings will not be affected.

=over 4

=item B<diag>

    $Test->diag(@msgs);

Prints out the given $message.  Normally, it uses the failure_output()
handle, but if this is for a TODO test, the todo_output() handle is
used.

Output will be indented and marked with a # so as not to interfere
with test output.  A newline will be put on the end if there isn't one
already.

We encourage using this rather than calling print directly.

Returns false.  Why?  Because diag() is often used in conjunction with
a failing test (C<ok() || diag()>) it "passes through" the failure.

    return ok(...) || diag(...);

=for blame transfer
Mark Fowler <mark@twoshortplanks.com>

=cut

sub diag {
    my($self, @msgs) = @_;
    return unless @msgs;

    # Prevent printing headers when compiling (i.e. -c)
    return if $^C;

    # Escape each line with a #.
    foreach (@msgs) {
        $_ = 'undef' unless defined;
        s/^/# /gms;
    }

    push @msgs, "\n" unless $msgs[-1] =~ /\n\Z/;

    local $Level = $Level + 1;
    my $fh = $self->todo ? $self->todo_output : $self->failure_output;
    local($\, $", $,) = (undef, ' ', '');
    print $fh @msgs;

    return 0;
}

=begin _private

=item B<_print>

    $Test->_print(@msgs);

Prints to the output() filehandle.

=end _private

=cut

sub _print {
    my($self, @msgs) = @_;

    # Prevent printing headers when only compiling.  Mostly for when
    # tests are deparsed with B::Deparse
    return if $^C;

    local($\, $", $,) = (undef, ' ', '');
    my $fh = $self->output;

    # Escape each line after the first with a # so we don't
    # confuse Test::Harness.
    foreach (@msgs) {
        s/\n(.)/\n# $1/sg;
    }

    push @msgs, "\n" unless $msgs[-1] =~ /\n\Z/;

    print $fh @msgs;
}


=item B<output>

    $Test->output($fh);
    $Test->output($file);

Where normal "ok/not ok" test output should go.

Defaults to STDOUT.

=item B<failure_output>

    $Test->failure_output($fh);
    $Test->failure_output($file);

Where diagnostic output on test failures and diag() should go.

Defaults to STDERR.

=item B<todo_output>

    $Test->todo_output($fh);
    $Test->todo_output($file);

Where diagnostics about todo test failures and diag() should go.

Defaults to STDOUT.

=cut

my($Out_FH, $Fail_FH, $Todo_FH);
sub output {
    my($self, $fh) = @_;

    if( defined $fh ) {
        $Out_FH = _new_fh($fh);
    }
    return $Out_FH;
}

sub failure_output {
    my($self, $fh) = @_;

    if( defined $fh ) {
        $Fail_FH = _new_fh($fh);
    }
    return $Fail_FH;
}

sub todo_output {
    my($self, $fh) = @_;

    if( defined $fh ) {
        $Todo_FH = _new_fh($fh);
    }
    return $Todo_FH;
}

sub _new_fh {
    my($file_or_fh) = shift;

    my $fh;
    unless( UNIVERSAL::isa($file_or_fh, 'GLOB') ) {
        $fh = do { local *FH };
        open $fh, ">$file_or_fh" or 
            die "Can't open test output log $file_or_fh: $!";
    }
    else {
        $fh = $file_or_fh;
    }

    return $fh;
}

unless( $^C ) {
    # We dup STDOUT and STDERR so people can change them in their
    # test suites while still getting normal test output.
    open(TESTOUT, ">&STDOUT") or die "Can't dup STDOUT:  $!";
    open(TESTERR, ">&STDERR") or die "Can't dup STDERR:  $!";

    # Set everything to unbuffered else plain prints to STDOUT will
    # come out in the wrong order from our own prints.
    _autoflush(\*TESTOUT);
    _autoflush(\*STDOUT);
    _autoflush(\*TESTERR);
    _autoflush(\*STDERR);

    $CLASS->output(\*TESTOUT);
    $CLASS->failure_output(\*TESTERR);
    $CLASS->todo_output(\*TESTOUT);
}

sub _autoflush {
    my($fh) = shift;
    my $old_fh = select $fh;
    $| = 1;
    select $old_fh;
}


=back


=head2 Test Status and Info

=over 4

=item B<current_test>

    my $curr_test = $Test->current_test;
    $Test->current_test($num);

Gets/sets the current test # we're on.

You usually shouldn't have to set this.

=cut

sub current_test {
    my($self, $num) = @_;

    lock($Curr_Test);
    if( defined $num ) {
        unless( $Have_Plan ) {
            require Carp;
            Carp::croak("Can't change the current test number without a plan!");
        }

        $Curr_Test = $num;
        if( $num > @Test_Results ) {
            my $start = @Test_Results ? $#Test_Results + 1 : 0;
            for ($start..$num-1) {
                my %result;
                share(%result);
                %result = ( ok        => 1, 
                            actual_ok => undef, 
                            reason    => 'incrementing test number', 
                            type      => 'unknown', 
                            name      => undef 
                          );
                $Test_Results[$_] = \%result;
            }
        }
    }
    return $Curr_Test;
}


=item B<summary>

    my @tests = $Test->summary;

A simple summary of the tests so far.  True for pass, false for fail.
This is a logical pass/fail, so todos are passes.

Of course, test #1 is $tests[0], etc...

=cut

sub summary {
    my($self) = shift;

    return map { $_->{'ok'} } @Test_Results;
}

=item B<details>

    my @tests = $Test->details;

Like summary(), but with a lot more detail.

    $tests[$test_num - 1] = 
            { 'ok'       => is the test considered a pass?
              actual_ok  => did it literally say 'ok'?
              name       => name of the test (if any)
              type       => type of test (if any, see below).
              reason     => reason for the above (if any)
            };

'ok' is true if Test::Harness will consider the test to be a pass.

'actual_ok' is a reflection of whether or not the test literally
printed 'ok' or 'not ok'.  This is for examining the result of 'todo'
tests.  

'name' is the name of the test.

'type' indicates if it was a special test.  Normal tests have a type
of ''.  Type can be one of the following:

    skip        see skip()
    todo        see todo()
    todo_skip   see todo_skip()
    unknown     see below

Sometimes the Test::Builder test counter is incremented without it
printing any test output, for example, when current_test() is changed.
In these cases, Test::Builder doesn't know the result of the test, so
it's type is 'unkown'.  These details for these tests are filled in.
They are considered ok, but the name and actual_ok is left undef.

For example "not ok 23 - hole count # TODO insufficient donuts" would
result in this structure:

    $tests[22] =    # 23 - 1, since arrays start from 0.
      { ok        => 1,   # logically, the test passed since it's todo
        actual_ok => 0,   # in absolute terms, it failed
        name      => 'hole count',
        type      => 'todo',
        reason    => 'insufficient donuts'
      };

=cut

sub details {
    return @Test_Results;
}

=item B<todo>

    my $todo_reason = $Test->todo;
    my $todo_reason = $Test->todo($pack);

todo() looks for a $TODO variable in your tests.  If set, all tests
will be considered 'todo' (see Test::More and Test::Harness for
details).  Returns the reason (ie. the value of $TODO) if running as
todo tests, false otherwise.

todo() is pretty part about finding the right package to look for
$TODO in.  It uses the exported_to() package to find it.  If that's
not set, it's pretty good at guessing the right package to look at.

Sometimes there is some confusion about where todo() should be looking
for the $TODO variable.  If you want to be sure, tell it explicitly
what $pack to use.

=cut

sub todo {
    my($self, $pack) = @_;

    $pack = $pack || $self->exported_to || $self->caller(1);

    no strict 'refs';
    return defined ${$pack.'::TODO'} ? ${$pack.'::TODO'}
                                     : 0;
}

=item B<caller>

    my $package = $Test->caller;
    my($pack, $file, $line) = $Test->caller;
    my($pack, $file, $line) = $Test->caller($height);

Like the normal caller(), except it reports according to your level().

=cut

sub caller {
    my($self, $height) = @_;
    $height ||= 0;

    my @caller = CORE::caller($self->level + $height + 1);
    return wantarray ? @caller : $caller[0];
}

=back

=cut

=begin _private

=over 4

=item B<_sanity_check>

  _sanity_check();

Runs a bunch of end of test sanity checks to make sure reality came
through ok.  If anything is wrong it will die with a fairly friendly
error message.

=cut

#'#
sub _sanity_check {
    _whoa($Curr_Test < 0,  'Says here you ran a negative number of tests!');
    _whoa(!$Have_Plan and $Curr_Test, 
          'Somehow your tests ran without a plan!');
    _whoa($Curr_Test != @Test_Results,
          'Somehow you got a different number of results than tests ran!');
}

=item B<_whoa>

  _whoa($check, $description);

A sanity check, similar to assert().  If the $check is true, something
has gone horribly wrong.  It will die with the given $description and
a note to contact the author.

=cut

sub _whoa {
    my($check, $desc) = @_;
    if( $check ) {
        die <<WHOA;
WHOA!  $desc
This should never happen!  Please contact the author immediately!
WHOA
    }
}

=item B<_my_exit>

  _my_exit($exit_num);

Perl seems to have some trouble with exiting inside an END block.  5.005_03
and 5.6.1 both seem to do odd things.  Instead, this function edits $?
directly.  It should ONLY be called from inside an END block.  It
doesn't actually exit, that's your job.

=cut

sub _my_exit {
    $? = $_[0];

    return 1;
}


=back

=end _private

=cut

$SIG{__DIE__} = sub {
    # We don't want to muck with death in an eval, but $^S isn't
    # totally reliable.  5.005_03 and 5.6.1 both do the wrong thing
    # with it.  Instead, we use caller.  This also means it runs under
    # 5.004!
    my $in_eval = 0;
    for( my $stack = 1;  my $sub = (CORE::caller($stack))[3];  $stack++ ) {
        $in_eval = 1 if $sub =~ /^\(eval\)/;
    }
    $Test_Died = 1 unless $in_eval;
};

sub _ending {
    my $self = shift;

    _sanity_check();

    # Don't bother with an ending if this is a forked copy.  Only the parent
    # should do the ending.
    do{ _my_exit($?) && return } if $Original_Pid != $$;

    # Bailout if plan() was never called.  This is so
    # "require Test::Simple" doesn't puke.
    do{ _my_exit(0) && return } if !$Have_Plan && !$Test_Died;

    # Figure out if we passed or failed and print helpful messages.
    if( @Test_Results ) {
        # The plan?  We have no plan.
        if( $No_Plan ) {
            $self->_print("1..$Curr_Test\n") unless $self->no_header;
            $Expected_Tests = $Curr_Test;
        }

        # 5.8.0 threads bug.  Shared arrays will not be auto-extended 
        # by a slice.  Worse, we have to fill in every entry else
        # we'll get an "Invalid value for shared scalar" error
        for my $idx ($#Test_Results..$Expected_Tests-1) {
            my %empty_result = ();
            share(%empty_result);
            $Test_Results[$idx] = \%empty_result
              unless defined $Test_Results[$idx];
        }

        my $num_failed = grep !$_->{'ok'}, @Test_Results[0..$Expected_Tests-1];
        $num_failed += abs($Expected_Tests - @Test_Results);

        if( $Curr_Test < $Expected_Tests ) {
            $self->diag(<<"FAIL");
Looks like you planned $Expected_Tests tests but only ran $Curr_Test.
FAIL
        }
        elsif( $Curr_Test > $Expected_Tests ) {
            my $num_extra = $Curr_Test - $Expected_Tests;
            $self->diag(<<"FAIL");
Looks like you planned $Expected_Tests tests but ran $num_extra extra.
FAIL
        }
        elsif ( $num_failed ) {
            $self->diag(<<"FAIL");
Looks like you failed $num_failed tests of $Expected_Tests.
FAIL
        }

        if( $Test_Died ) {
            $self->diag(<<"FAIL");
Looks like your test died just after $Curr_Test.
FAIL

            _my_exit( 255 ) && return;
        }

        _my_exit( $num_failed <= 254 ? $num_failed : 254  ) && return;
    }
    elsif ( $Skip_All ) {
        _my_exit( 0 ) && return;
    }
    elsif ( $Test_Died ) {
        $self->diag(<<'FAIL');
Looks like your test died before it could output anything.
FAIL
    }
    else {
        $self->diag("No tests run!\n");
        _my_exit( 255 ) && return;
    }
}

END {
    $Test->_ending if defined $Test and !$Test->no_ending;
}

=head1 THREADS

In perl 5.8.0 and later, Test::Builder is thread-safe.  The test
number is shared amongst all threads.  This means if one thread sets
the test number using current_test() they will all be effected.

=head1 EXAMPLES

CPAN can provide the best examples.  Test::Simple, Test::More,
Test::Exception and Test::Differences all use Test::Builder.

=head1 SEE ALSO

Test::Simple, Test::More, Test::Harness

=head1 AUTHORS

Original code by chromatic, maintained by Michael G Schwern
E<lt>schwern@pobox.comE<gt>

=head1 COPYRIGHT

Copyright 2002 by chromatic E<lt>chromatic@wgz.orgE<gt>,
                  Michael G Schwern E<lt>schwern@pobox.comE<gt>.

This program is free software; you can redistribute it and/or 
modify it under the same terms as Perl itself.

See F<http://www.perl.com/perl/misc/Artistic.html>

=cut

1;
